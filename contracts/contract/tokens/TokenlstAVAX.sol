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

/// @title TokenlstAVAX - Principal Staked AVAX (Whitelabel)
/// @author Multisig Labs (https://multisiglabs.org)
/// @notice This contract implements an ERC20 token vault that accepts native AVAX, and then stakes them in the stAVAX yield generating ERC4626 vault.
///         AVAX staked in this contract will NOT generate any yield for the user, instead the yield will be stripped and directed to a treasury address.
///         lstAVAX can be redeemed at any time for an equivalent amount of stAVAX shares at the current exchange rate
contract TokenlstAVAX is ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
	using SafeERC20 for IERC20;
	using SafeERC20 for IERC4626;
	using SafeERC20 for IWAVAX;
	using FixedPointMathLib for uint256;

	address public vault;
	address public underlyingAsset;
	address public withdrawQueue;

	address public treasury; // Address to receive yield

	event Deposited(address indexed user, uint256 avaxAmount, uint256 vaultShares);
	event Withdrawn(address indexed user, uint256 pstShares, uint256 vaultShares);
	event WithdrawnViaQueue(address indexed user, uint256 pstShares, uint256 vaultShares, uint256 requestId);
	event YieldStripped(uint256 excessShares, uint256 avaxAmount);
	event TreasuryUpdated(address indexed newTreasury);

	error InsufficientBalance();
	error InvalidVault();
	error NoYieldToStrip();
	error ZeroAddress();
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

	function initialize(address _vault, address _withdrawQueue, address _treasury) external initializer {
		__Ownable_init();
		__Pausable_init();
		__ReentrancyGuard_init();
		__ERC20_init("Whitelabel Staked AVAX", "lstAVAX");

		if (_vault == address(0)) revert ZeroAddress();
		if (_treasury == address(0)) revert ZeroAddress();
		// Validate that _vault implements IERC4626
		try IERC4626(_vault).asset() returns (address asset) {
			vault = _vault;
			underlyingAsset = asset;
			withdrawQueue = _withdrawQueue;
			treasury = _treasury;
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

	/// @notice Calculate how much excess vault shares the contract has, and send to treasury
	/// @return excessShares Amount of excess shares sent to treasury
	function stripYield() public whenNotPaused returns (uint256 excessShares) {
		excessShares = getExcessShares();

		if (excessShares == 0) return 0;

		// Instead of burning shares like pstAVAX, we instead send them to the treasury
		if (excessShares > 0) {
			IERC4626(vault).transfer(treasury, excessShares);
		}

		uint256 avaxAmount = IERC4626(vault).convertToAssets(excessShares);

		emit YieldStripped(excessShares, avaxAmount);
	}

	/// @notice Calculate excess shares
	/// @return excessShares Amount of excess shares
	function getExcessShares() public view returns (uint256 excessShares) {
		uint256 totalAVAX = IERC4626(vault).convertToAssets(IERC4626(vault).balanceOf(address(this)));
		uint256 principalAVAX = totalSupply();

		if (principalAVAX == 0) return 0;

		if (totalAVAX <= principalAVAX) return 0;
		uint256 yield = totalAVAX - principalAVAX;
		return IERC4626(vault).convertToShares(yield);
	}

	/// @notice Set the treasury address
	/// @param _treasury Address to receive yield
	function setTreasury(address _treasury) external onlyOwner {
		treasury = _treasury;
		emit TreasuryUpdated(_treasury);
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
