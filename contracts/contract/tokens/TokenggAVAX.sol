// SPDX-License-Identifier: GPL-3.0-only
// Copied from https://github.com/fei-protocol/ERC4626/blob/main/src/xERC4626.sol
// Rewards logic inspired by xERC20 (https://github.com/ZeframLou/playpen/blob/main/src/xERC20.sol)
pragma solidity 0.8.17;

import "../BaseUpgradeable.sol";
import {ERC20Upgradeable} from "./upgradeable/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "./upgradeable/ERC4626Upgradeable.sol";
import {ProtocolDAO} from "../ProtocolDAO.sol";
import {Storage} from "../Storage.sol";

import {IWithdrawer} from "../../interface/IWithdrawer.sol";
import {IWAVAX} from "../../interface/IWAVAX.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ERC20} from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {SafeCastLib} from "@rari-capital/solmate/src/utils/SafeCastLib.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

/// @dev Local variables and parent contracts must remain in order between contract upgrades
contract TokenggAVAX is Initializable, ERC4626Upgradeable, BaseUpgradeable {
	using SafeTransferLib for ERC20;
	using SafeTransferLib for address;
	using SafeCastLib for *;
	using FixedPointMathLib for uint256;

	error SyncError();
	error ZeroShares();
	error ZeroAssets();
	error InvalidStakingDeposit();

	event NewRewardsCycle(uint256 indexed cycleEnd, uint256 rewardsAmt);
	event WithdrawnForStaking(address indexed caller, uint256 assets);
	event DepositedFromStaking(address indexed caller, uint256 baseAmt, uint256 rewardsAmt);

	/// @notice the effective start of the current cycle
	uint32 public lastSync;

	/// @notice the maximum length of a rewards cycle
	uint32 public rewardsCycleLength;

	/// @notice the end of the current cycle. Will always be evenly divisible by `rewardsCycleLength`.
	uint32 public rewardsCycleEnd;

	/// @notice the amount of rewards distributed in a the most recent cycle.
	uint192 public lastRewardsAmt;

	/// @notice the total amount of avax (including avax sent out for staking and all incoming rewards)
	uint256 public totalReleasedAssets;

	/// @notice total amount of avax currently out for staking (not including any rewards)
	uint256 public stakingTotalAssets;

	modifier whenTokenNotPaused(uint256 amt) {
		if (amt > 0 && getBool(keccak256(abi.encodePacked("contract.paused", "TokenggAVAX")))) {
			revert ContractPaused();
		}
		_;
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		// The constructor is executed only when creating implementation contract
		// so prevent it's reinitialization
		_disableInitializers();
	}

	function initialize(Storage storageAddress, ERC20 asset, uint256 initialDeposit) public initializer {
		__ERC4626Upgradeable_init(asset, "GoGoPool Liquid Staking Token", "ggAVAX");
		__BaseUpgradeable_init(storageAddress);

		version = 1;

		// sacrifice initial seed of shares to prevent front-running early deposits
		if (initialDeposit > 0) {
			deposit(initialDeposit, address(this));
		}

		rewardsCycleLength = 14 days;
		// Ensure it will be evenly divisible by `rewardsCycleLength`.
		rewardsCycleEnd = (block.timestamp.safeCastTo32() / rewardsCycleLength) * rewardsCycleLength;
	}

	/// @notice only accept AVAX via fallback from the WAVAX contract
	receive() external payable {
		require(msg.sender == address(asset));
	}

	/// @notice Distributes rewards to TokenggAVAX holders. Public, anyone can call.
	/// 				All surplus `asset` balance of the contract over the internal balance becomes queued for the next cycle.
	function syncRewards() public {
		uint32 timestamp = block.timestamp.safeCastTo32();

		if (timestamp < rewardsCycleEnd) {
			revert SyncError();
		}

		uint192 lastRewardsAmt_ = lastRewardsAmt;
		uint256 totalReleasedAssets_ = totalReleasedAssets;
		uint256 stakingTotalAssets_ = stakingTotalAssets;

		uint256 nextRewardsAmt = (asset.balanceOf(address(this)) + stakingTotalAssets_) - totalReleasedAssets_ - lastRewardsAmt_;

		// Ensure nextRewardsCycleEnd will be evenly divisible by `rewardsCycleLength`.
		uint32 nextRewardsCycleEnd = ((timestamp + rewardsCycleLength) / rewardsCycleLength) * rewardsCycleLength;

		lastRewardsAmt = nextRewardsAmt.safeCastTo192();
		lastSync = timestamp;
		rewardsCycleEnd = nextRewardsCycleEnd;
		totalReleasedAssets = totalReleasedAssets_ + lastRewardsAmt_;
		emit NewRewardsCycle(nextRewardsCycleEnd, nextRewardsAmt);
	}

	/// @notice Compute the amount of tokens available to share holders.
	///         Increases linearly during a reward distribution period from the sync call, not the cycle start.
	/// @return The amount of ggAVAX tokens available
	function totalAssets() public view override returns (uint256) {
		// cache global vars
		uint256 totalReleasedAssets_ = totalReleasedAssets;
		uint192 lastRewardsAmt_ = lastRewardsAmt;
		uint32 rewardsCycleEnd_ = rewardsCycleEnd;
		uint32 lastSync_ = lastSync;

		if (block.timestamp >= rewardsCycleEnd_) {
			// no rewards or rewards are fully unlocked
			// entire reward amount is available
			return totalReleasedAssets_ + lastRewardsAmt_;
		}

		// rewards are not fully unlocked
		// return unlocked rewards and stored total
		uint256 unlockedRewards = (lastRewardsAmt_ * (block.timestamp - lastSync_)) / (rewardsCycleEnd_ - lastSync_);
		return totalReleasedAssets_ + unlockedRewards;
	}

	/// @notice Returns the AVAX amount that is available for staking on minipools
	/// @return uint256 AVAX available for staking
	function amountAvailableForStaking() public view returns (uint256) {
		ProtocolDAO protocolDAO = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 targetCollateralRate = protocolDAO.getTargetGGAVAXReserveRate();

		uint256 totalAssets_ = totalAssets();

		uint256 reservedAssets = totalAssets_.mulDivDown(targetCollateralRate, 1 ether);

		if (reservedAssets + stakingTotalAssets > totalAssets_) {
			return 0;
		}
		return totalAssets_ - reservedAssets - stakingTotalAssets;
	}

	/// @notice Accepts AVAX deposit from a minipool. Expects the base amount and rewards earned from staking
	/// @param baseAmt The amount of liquid staker AVAX used to create a minipool
	/// @param rewardAmt The rewards amount (in AVAX) earned from staking
	function depositFromStaking(uint256 baseAmt, uint256 rewardAmt) public payable onlySpecificRegisteredContract("MinipoolManager", msg.sender) {
		uint256 totalAmt = msg.value;
		if (totalAmt != (baseAmt + rewardAmt) || baseAmt > stakingTotalAssets) {
			revert InvalidStakingDeposit();
		}

		emit DepositedFromStaking(msg.sender, baseAmt, rewardAmt);
		stakingTotalAssets -= baseAmt;
		IWAVAX(address(asset)).deposit{value: totalAmt}();
	}

	/// @notice Allows the MinipoolManager contract to withdraw liquid staker funds to create a minipool
	/// @param assets The amount of AVAX to withdraw
	function withdrawForStaking(uint256 assets) public onlySpecificRegisteredContract("MinipoolManager", msg.sender) {
		emit WithdrawnForStaking(msg.sender, assets);

		stakingTotalAssets += assets;
		IWAVAX(address(asset)).withdraw(assets);
		IWithdrawer withdrawer = IWithdrawer(msg.sender);
		withdrawer.receiveWithdrawalAVAX{value: assets}();
	}

	/// @notice Allows users to deposit AVAX and receive ggAVAX
	/// @return shares The amount of ggAVAX minted
	function depositAVAX() public payable returns (uint256 shares) {
		uint256 assets = msg.value;
		// Check for rounding error since we round down in previewDeposit.
		if ((shares = previewDeposit(assets)) == 0) {
			revert ZeroShares();
		}

		emit Deposit(msg.sender, msg.sender, assets, shares);

		IWAVAX(address(asset)).deposit{value: assets}();
		_mint(msg.sender, shares);
		afterDeposit(assets, shares);
	}

	/// @notice Allows users to specify an amount of AVAX to withdraw from their ggAVAX supply
	/// @param assets Amount of AVAX to be withdrawn
	/// @return shares Amount of ggAVAX burned
	function withdrawAVAX(uint256 assets) public returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.
		beforeWithdraw(assets, shares);
		_burn(msg.sender, shares);

		emit Withdraw(msg.sender, msg.sender, msg.sender, assets, shares);

		IWAVAX(address(asset)).withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/// @notice Allows users to specify shares of ggAVAX to redeem for AVAX
	/// @param shares Amount of ggAVAX to burn
	/// @return assets Amount of AVAX withdrawn
	function redeemAVAX(uint256 shares) public returns (uint256 assets) {
		// Check for rounding error since we round down in previewRedeem.
		if ((assets = previewRedeem(shares)) == 0) {
			revert ZeroAssets();
		}
		beforeWithdraw(assets, shares);
		_burn(msg.sender, shares);

		emit Withdraw(msg.sender, msg.sender, msg.sender, assets, shares);

		IWAVAX(address(asset)).withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/// @notice Max assets an owner can deposit
	/// @param _owner User wallet address
	/// @return The max amount of ggAVAX an owner can deposit
	function maxDeposit(address _owner) public view override returns (uint256) {
		if (getBool(keccak256(abi.encodePacked("contract.paused", "TokenggAVAX")))) {
			return 0;
		}
		return super.maxDeposit(_owner);
	}

	/// @notice Max shares owner can mint
	/// @param _owner User wallet address
	/// @return The max amount of ggAVAX an owner can mint
	function maxMint(address _owner) public view override returns (uint256) {
		if (getBool(keccak256(abi.encodePacked("contract.paused", "TokenggAVAX")))) {
			return 0;
		}
		return super.maxMint(_owner);
	}

	/// @notice Max assets an owner can withdraw with consideration to liquidity in this contract
	/// @param _owner User wallet address
	/// @return The max amount of ggAVAX an owner can withdraw
	function maxWithdraw(address _owner) public view override returns (uint256) {
		uint256 assets = convertToAssets(balanceOf[_owner]);
		uint256 avail = totalAssets() - stakingTotalAssets;
		return assets > avail ? avail : assets;
	}

	/// @notice Max shares owner can withdraw with consideration to liquidity in this contract
	/// @param _owner User wallet address
	/// @return The max amount of ggAVAX an owner can redeem
	function maxRedeem(address _owner) public view override returns (uint256) {
		uint256 shares = balanceOf[_owner];
		uint256 avail = convertToShares(totalAssets() - stakingTotalAssets);
		return shares > avail ? avail : shares;
	}

	/// @notice Preview shares minted for AVAX deposit
	/// @param assets Amount of AVAX to deposit
	/// @return uint256 Amount of ggAVAX that would be minted
	function previewDeposit(uint256 assets) public view override whenTokenNotPaused(assets) returns (uint256) {
		return super.previewDeposit(assets);
	}

	/// @notice Preview assets required for mint of shares
	/// @param shares Amount of ggAVAX to mint
	/// @return uint256 Amount of AVAX required
	function previewMint(uint256 shares) public view override whenTokenNotPaused(shares) returns (uint256) {
		return super.previewMint(shares);
	}

	/// @notice Function prior to a withdraw
	/// @param amount Amount of AVAX
	function beforeWithdraw(uint256 amount, uint256 /* shares */) internal override {
		totalReleasedAssets -= amount;
	}

	/// @notice Function after a deposit
	/// @param amount Amount of AVAX
	function afterDeposit(uint256 amount, uint256 /* shares */) internal override {
		totalReleasedAssets += amount;
	}

	/// @notice Override of ERC20Upgradeable to set the contract version for EIP-2612
	/// @return hash of this contracts version
	function versionHash() internal view override returns (bytes32) {
		return keccak256(abi.encodePacked(version));
	}
}
