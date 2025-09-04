// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {WithdrawQueue} from "../WithdrawQueue.sol";
import {IWAVAX} from "../../interface/IWAVAX.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

interface IYieldDonor {
	function donateYield(uint256 sharesToBurn, bytes32 source) external;
}

/// @title TokenpstAVAX - Principal Staked AVAX
/// @author Multisig Labs (https://multisiglabs.org)
/// @notice This contract implements an ERC20 token vault that accepts native AVAX and WAVAX, and then stakes them in the ggAVAX yield generating ERC4626 vault.
///         AVAX staked in this vault will NOT generate any yield for the user, the yield will be stripped and donated to the ggAVAX vault to increase it's yield.
///         In addition, holders of pstAVAX will be eligible to earn Hypha Points
///         pstAVAX can be redeemed at any time for an equivalent amount of ggAVAX shares at the current exchange rate
contract TokenpstAVAX is ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
	using SafeERC20 for IERC20;
	using SafeERC20 for IERC4626;
	using SafeERC20 for IWAVAX;
	using FixedPointMathLib for uint256;

	address public vault;
	address public underlyingAsset;
	address public withdrawQueue;

	uint256 public stripYieldFeeBips; // Fee percentage in basis points (0-10000)
	address public stripYieldFeeRecipient; // Address to receive fee shares

	event Deposited(address indexed user, uint256 avaxAmount, uint256 vaultShares);
	event Withdrawn(address indexed user, uint256 pstShares, uint256 vaultShares);
	event WithdrawnViaQueue(address indexed user, uint256 pstShares, uint256 vaultShares, uint256 requestId);
	event YieldStripped(uint256 excessShares, uint256 feeShares, uint256 burnShares, uint256 avaxAmount);
	event StripYieldFeeCollected(uint256 feeShares, address indexed recipient);
	event StripYieldFeeBipsUpdated(uint256 oldFeeBips, uint256 newFeeBips);
	event StripYieldFeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);

	error InsufficientBalance();
	error InvalidVault();
	error NoYieldToStrip();
	error ZeroAmount();
	error InvalidFeeBips();
	error InvalidFeeRecipient();

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Allow users to send native AVAX to this contract and receive pstAVAX tokens with 1:1 ratio
	receive() external payable {
		depositAVAX();
	}

	function initialize(address _vault, address _withdrawQueue) external initializer {
		__Ownable_init();
		__Pausable_init();
		__ReentrancyGuard_init();
		__ERC20_init("Principal Staked AVAX", "pstAVAX");

		if (_vault == address(0)) revert InvalidVault();
		// Validate that _vault implements IERC4626
		try IERC4626(_vault).asset() returns (address asset) {
			vault = _vault;
			underlyingAsset = asset;
			withdrawQueue = _withdrawQueue;
		} catch {
			revert InvalidVault();
		}
	}

	/// @notice Allow users to deposit native AVAX and receive pstAVAX tokens with 1:1 ratio
	function depositAVAX() public payable nonReentrant whenNotPaused {
		uint256 assets = msg.value;
		if (assets == 0) revert ZeroAmount();

		// Convert native AVAX to WAVAX
		IWAVAX(underlyingAsset).deposit{value: assets}();
		_deposit(assets, msg.sender);
	}

	/// @notice Allow users to deposit WAVAX and receive pstAVAX tokens with 1:1 ratio
	function deposit(uint256 assets) external nonReentrant whenNotPaused {
		if (assets == 0) revert ZeroAmount();
		IERC20(underlyingAsset).safeTransferFrom(msg.sender, address(this), assets);
		_deposit(assets, msg.sender);
	}

	/// @notice Allow users to deposit WAVAX and receive pstAVAX tokens with 1:1 ratio
	/// @dev This contract should have the WAVAX before calling this fn
	function _deposit(uint256 assets, address receiver) internal {
		_mint(receiver, assets);

		// Approve vault to spend WAVAX
		IWAVAX(underlyingAsset).approve(address(vault), assets);

		stripYield();

		// Deposit WAVAX into vault and get shares
		uint256 vaultShares = IERC4626(vault).deposit(assets, address(this));

		emit Deposited(receiver, assets, vaultShares);
	}

	/// @notice Allow users to withdraw by burning pstAVAX and receiving an equivalent amount of vault shares (ggAVAX),
	///         so user receives IERC4626(vault).convertToShares(assets) ggAVAX shares.
	/// @param assets Amount of pstAVAX to redeem for ggAVAX
	/// @return vaultShares Amount of ggAVAX shares received
	/// @dev Invariant: the ERC4626 vault exchange rate is monotonically increasing, thus cannot lose value.
	function withdraw(uint256 assets) public nonReentrant whenNotPaused returns (uint256 vaultShares) {
		if (assets == 0) revert ZeroAmount();
		if (balanceOf(msg.sender) < assets) revert InsufficientBalance();

		stripYield();

		// Calculate how many vault shares this represents
		vaultShares = IERC4626(vault).convertToShares(assets);

		_burn(msg.sender, assets);

		IERC4626(vault).safeTransfer(msg.sender, vaultShares);

		emit Withdrawn(msg.sender, assets, vaultShares);
	}

	/// @notice Allow users to withdraw by burning pstAVAX and receiving an equivalent amount of vault shares (ggAVAX),
	///         then immediately requesting an unstake on behalf of the user.
	/// @param assets Amount of pstAVAX to redeem for ggAVAX
	/// @return vaultShares Amount of ggAVAX shares received
	/// @return requestId The ID of the unstake request
	function withdrawViaQueue(
		uint256 assets,
		uint48 expirationDelay
	) external nonReentrant whenNotPaused returns (uint256 vaultShares, uint256 requestId) {
		if (assets == 0) revert ZeroAmount();
		if (balanceOf(msg.sender) < assets) revert InsufficientBalance();

		stripYield();
		vaultShares = IERC4626(vault).convertToShares(assets);

		_burn(msg.sender, assets);

		IERC4626(vault).approve(withdrawQueue, vaultShares);
		requestId = WithdrawQueue(payable(withdrawQueue)).requestUnstakeOnBehalfOf(vaultShares, msg.sender, expirationDelay);

		emit WithdrawnViaQueue(msg.sender, assets, vaultShares, requestId);
	}

	/// @notice Calculate how much excess vault shares the contract has, collect fee, and send remainder to vault to increase yield
	/// @return feeShares Amount of excess shares taken as a fee (fee)
	/// @return burnShares Amount of excess shares burned to increase yield (burn)
	function stripYield() public whenNotPaused returns (uint256 feeShares, uint256 burnShares) {
		(feeShares, burnShares) = getExcessShares();
		uint256 totalExcess = feeShares + burnShares;

		if (totalExcess == 0) return (0, 0);

		// Burn remaining shares to boost yield
		if (burnShares > 0) {
			IYieldDonor(payable(vault)).donateYield(burnShares, "pstAVAX");
		}

		uint256 avaxAmount = IERC4626(vault).convertToAssets(totalExcess);

		// Send fee shares to recipient (if any)
		if (feeShares > 0 && stripYieldFeeRecipient != address(0)) {
			IERC4626(vault).safeTransfer(stripYieldFeeRecipient, feeShares);
			emit StripYieldFeeCollected(feeShares, stripYieldFeeRecipient);
		}

		emit YieldStripped(totalExcess, feeShares, burnShares, avaxAmount);
	}

	/// @notice Calculate excess shares split between fee and burn portions
	/// @dev When fee > 0, calculates total shares to extract such that burning burnShares achieves target exchange rate
	/// @return feeShares Amount of shares to collect as fee
	/// @return burnShares Amount of shares to burn for yield boost
	function getExcessShares() public view returns (uint256 feeShares, uint256 burnShares) {
		uint256 pstAVAXVaultShares = IERC4626(vault).balanceOf(address(this));
		uint256 totalPstTokens = totalSupply();

		if (totalPstTokens == 0) return (0, pstAVAXVaultShares);

		uint256 ggAVAXTotalShares = IERC4626(vault).totalSupply();
		uint256 ggAVAXTotalAssets = IERC4626(vault).totalAssets();

		if (ggAVAXTotalAssets <= totalPstTokens) return (0, 0); // No excess if no yield
		if (pstAVAXVaultShares * ggAVAXTotalAssets < totalPstTokens * ggAVAXTotalShares) return (0, 0);

		uint256 totalExcess;
		uint256 numerator = pstAVAXVaultShares * ggAVAXTotalAssets - totalPstTokens * ggAVAXTotalShares;

		// If no fee, use original calculation
		if (stripYieldFeeBips == 0 || stripYieldFeeRecipient == address(0)) {
			uint256 simpleDenominator = ggAVAXTotalAssets - totalPstTokens;
			totalExcess = numerator / simpleDenominator;
			return (0, totalExcess);
		}

		// Modified calculation accounting for fee
		// E = (S×A - T×G) / (A - T×(1 - feePct))
		// where feePct = stripYieldFeeBips / 10000
		uint256 burnPct = 10000 - stripYieldFeeBips; // basis points
		uint256 denominator = ggAVAXTotalAssets - totalPstTokens.mulDivDown(burnPct, 10000);

		// Check for potential division issues
		if (denominator == 0) return (0, 0);

		totalExcess = numerator / denominator;

		// Split into fee and burn portions
		feeShares = totalExcess.mulDivDown(stripYieldFeeBips, 10000);
		burnShares = totalExcess - feeShares;
	}

	/// @notice Set the fee percentage for stripYield in basis points
	/// @param _feeBips Fee percentage in basis points (0-10000, where 10000 = 100%)
	function setStripYieldFeeBips(uint256 _feeBips) external onlyOwner {
		if (_feeBips > 10000) revert InvalidFeeBips();
		if (_feeBips > 0 && stripYieldFeeRecipient == address(0)) revert InvalidFeeRecipient();
		uint256 oldFeeBips = stripYieldFeeBips;
		stripYieldFeeBips = _feeBips;
		emit StripYieldFeeBipsUpdated(oldFeeBips, _feeBips);
	}

	/// @notice Set the recipient address for stripYield fees
	/// @param _recipient Address to receive fee shares
	function setStripYieldFeeRecipient(address _recipient) external onlyOwner {
		if (stripYieldFeeBips > 0 && _recipient == address(0)) revert InvalidFeeRecipient();
		address oldRecipient = stripYieldFeeRecipient;
		stripYieldFeeRecipient = _recipient;
		emit StripYieldFeeRecipientUpdated(oldRecipient, _recipient);
	}

	/// @notice Emergency pause function
	function setPaused(bool paused) external onlyOwner {
		if (paused) _pause();
		else _unpause();
	}

	/// @notice Emergency function to recover stuck ERC20 tokens with safe transfer
	/// @param token The ERC20 token address to recover
	/// @param amount The amount to recover (0 = recover all)
	function recoverERC20Safe(address token, uint256 amount) external onlyOwner {
		if (amount == 0) {
			amount = IERC20(token).balanceOf(address(this));
		}

		// Don't allow recovery of the underlying asset (WAVAX) or vault shares
		require(token != underlyingAsset, "Cannot recover underlying asset");
		require(token != vault, "Cannot recover vault shares");

		// Use safe transfer to handle tokens that might revert
		IERC20(token).safeTransfer(owner(), amount);
	}
}
