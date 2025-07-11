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

	address public vault;
	address public underlyingAsset;
	address public withdrawQueue;

	event Deposited(address indexed user, uint256 avaxAmount, uint256 vaultShares);
	event Withdrawn(address indexed user, uint256 pstShares, uint256 vaultShares);
	event WithdrawnViaQueue(address indexed user, uint256 pstShares, uint256 vaultShares, uint256 requestId);
	event YieldStripped(uint256 excessShares, uint256 avaxAmount);

	error InsufficientBalance();
	error InvalidVault();
	error NoYieldToStrip();
	error ZeroAmount();

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
	function withdrawViaQueue(uint256 assets) external nonReentrant whenNotPaused returns (uint256 vaultShares, uint256 requestId) {
		if (assets == 0) revert ZeroAmount();
		if (balanceOf(msg.sender) < assets) revert InsufficientBalance();

		vaultShares = IERC4626(vault).convertToShares(assets);

		_burn(msg.sender, assets);

		IERC4626(vault).approve(withdrawQueue, vaultShares);
		requestId = WithdrawQueue(payable(withdrawQueue)).requestUnstakeOnBehalfOf(vaultShares, msg.sender);

		emit WithdrawnViaQueue(msg.sender, assets, vaultShares, requestId);
	}

	/// @notice Calculate how much excess vault shares the contract has, and send them to vault to increase it's yield
	function stripYield() external nonReentrant whenNotPaused {
		uint256 excessShares = getExcessShares();
		if (excessShares == 0) revert NoYieldToStrip();

		// Call depositAdditionalYield on the vault to burn the shares and emit event
		IYieldDonor(payable(vault)).donateYield(excessShares, "pstAVAX");

		uint256 avaxAmount = IERC4626(vault).convertToAssets(excessShares);
		emit YieldStripped(excessShares, avaxAmount);
	}

	/// @notice Calculate how much excess vault shares the contract has
	function getExcessShares() public view returns (uint256) {
		uint256 totalVaultShares = IERC4626(vault).balanceOf(address(this));
		uint256 totalPstTokens = totalSupply();
		// Calculate how many vault shares should be backing pstAVAX tokens
		uint256 requiredVaultShares = IERC4626(vault).convertToShares(totalPstTokens);
		// Calculate excess shares (yield)
		uint256 excessShares = totalVaultShares > requiredVaultShares ? totalVaultShares - requiredVaultShares : 0;
		return excessShares;
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
