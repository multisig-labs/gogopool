// SPDX-License-Identifier: GPL-3.0-only
// Copied from https://github.com/fei-protocol/ERC4626/blob/main/src/xERC4626.sol
// Rewards logic inspired by xERC20 (https://github.com/ZeframLou/playpen/blob/main/src/xERC20.sol)
pragma solidity 0.8.17;

import "../BaseUpgradeable.sol";
import {ERC20Upgradeable} from "./upgradeable/ERC20Upgradeable.sol";
import {ERC4626Upgradeable} from "./upgradeable/ERC4626Upgradeable.sol";
import {ProtocolDAO} from "../ProtocolDAO.sol";
import {Storage} from "../Storage.sol";
import {Vault} from "../Vault.sol";

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
	error InvalidDelegationDeposit();
	error ZeroSharesToBurn();
	error InsufficientShares();
	error WithdrawAmountTooLarge();
	error WithdrawForStakingDisabled();
	error AccessControlUnauthorizedAccount(address account, bytes32 neededRole);

	event NewRewardsCycle(uint256 indexed cycleEnd, uint256 rewardsAmt);
	event DepositedFromStaking(address indexed caller, uint256 baseAmt, uint256 rewardsAmt);
	event DepositedAdditionalYield(bytes32 indexed source, address indexed caller, uint256 baseAmount, uint256 rewardAmt);
	event FeeCollected(bytes32 indexed source, uint256 feeAmount);
	event YieldDonated(address indexed caller, bytes32 indexed source, uint256 sharesBurnt, uint256 avaxEquivalent);
	event WithdrawnForStaking(address indexed caller, bytes32 indexed purpose, uint256 assets);

	/// @notice Role events
	event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
	event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

	/// @notice Admin transfer events
	event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
	event AdminTransferCompleted(address indexed previousAdmin, address indexed newAdmin);
	event AdminTransferCanceled(address indexed admin, address indexed canceledPendingAdmin);

	/// @notice Additional operational events
	event ContractPauseStateChanged(bool paused);
	event RewardsCycleParametersUpdated(uint32 newCycleLength);
	event ContractReinitialize(uint256 version, address asset, address admin);

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

	/// @notice Default admin role identifier
	bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

	/// @notice Role identifier for delegator operations
	bytes32 public constant STAKER_ROLE = keccak256("STAKER_ROLE");

	/// @notice Role identifier for withdraw queue operations
	bytes32 public constant WITHDRAW_QUEUE_ROLE = keccak256("WITHDRAW_QUEUE_ROLE");

	/// @notice Mapping from role to account to whether they have the role
	mapping(bytes32 => mapping(address => bool)) private _roles;

	/// @notice Pending admin for two-step admin transfer
	address private _pendingAdmin;

	/// @notice Current admin address
	address private _currentAdmin;

	/// @notice Modifier to check if caller has a specific role
	modifier onlyRole(bytes32 role) {
		_checkRole(role);
		_;
	}

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
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		version = 1;

		// sacrifice initial seed of shares to prevent front-running early deposits
		if (initialDeposit > 0) {
			deposit(initialDeposit, address(this));
		}

		rewardsCycleLength = 14 days;
		// Ensure it will be evenly divisible by `rewardsCycleLength`.
		rewardsCycleEnd = (block.timestamp.safeCastTo32() / rewardsCycleLength) * rewardsCycleLength;
	}

	function reinitialize(ERC20 asset, address defaultAdmin) public reinitializer(3) {
		version = 3;
		__ERC4626Upgradeable_init(asset, "Hypha Staked AVAX", "stAVAX");
		_grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);

		emit ContractReinitialize(version, address(asset), defaultAdmin);
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
		ProtocolDAO protocolDAO = ProtocolDAO(getContractAddress("ProtocolDAO"));
		Vault vault = Vault(getContractAddress("Vault"));

		uint256 totalAmt = msg.value;
		uint256 feeAmount = rewardAmt.mulDivDown(protocolDAO.getFeeBips(), 10000);
		rewardAmt -= feeAmount;
		if (totalAmt != (baseAmt + rewardAmt + feeAmount) || baseAmt > stakingTotalAssets) {
			revert InvalidStakingDeposit();
		}

		if (feeAmount > 0) {
			vault.depositAVAX{value: feeAmount}();
			vault.transferAVAX("ClaimProtocolDAO", feeAmount);
			emit FeeCollected(bytes32("STAKING"), feeAmount);
		}

		stakingTotalAssets -= baseAmt;
		IWAVAX(address(asset)).deposit{value: totalAmt - feeAmount}();

		emit DepositedFromStaking(msg.sender, baseAmt, rewardAmt);
	}

	/// @notice Allows users to deposit additional yield from activities such as MEV
	/// @param baseAmt The base amount being returned from staking/delegation
	/// @param rewardAmt The reward amount from yield activities
	/// @param source The source of the additional yield (i.e. MEV)
	function depositFromStaking(uint256 baseAmt, uint256 rewardAmt, bytes32 source) public payable onlyRole(STAKER_ROLE) {
		ProtocolDAO protocolDAO = ProtocolDAO(getContractAddress("ProtocolDAO"));
		Vault vault = Vault(getContractAddress("Vault"));

		uint256 totalAmt = msg.value;
		uint256 feeAmt = rewardAmt.mulDivDown(protocolDAO.getFeeBips(), 10000);
		rewardAmt -= feeAmt;

		if (totalAmt != (baseAmt + rewardAmt + feeAmt) || baseAmt > stakingTotalAssets) {
			revert InvalidDelegationDeposit();
		}

		if (feeAmt > 0) {
			vault.depositAVAX{value: feeAmt}();
			vault.transferAVAX("ClaimProtocolDAO", feeAmt);
			emit FeeCollected(source, feeAmt);
		}

		stakingTotalAssets -= baseAmt;
		IWAVAX(address(asset)).deposit{value: totalAmt - feeAmt}();
		emit DepositedAdditionalYield(source, msg.sender, baseAmt, rewardAmt);
	}

	/// @notice Allows anyone to deposit yield to the contract
	/// @param source The source of the yield (i.e. MEV)
	function depositYield(bytes32 source) public payable {
		ProtocolDAO protocolDAO = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 totalAmt = msg.value;
		uint256 feeAmt = totalAmt.mulDivDown(protocolDAO.getFeeBips(), 10000);

		Vault vault = Vault(getContractAddress("Vault"));
		if (feeAmt > 0) {
			vault.depositAVAX{value: feeAmt}();
			vault.transferAVAX("ClaimProtocolDAO", feeAmt);
			emit FeeCollected(source, feeAmt);
		}

		IWAVAX(address(asset)).deposit{value: totalAmt - feeAmt}();
		emit DepositedAdditionalYield(source, msg.sender, totalAmt, feeAmt);
	}

	// Burn ggAVAX to increase yield for all holders
	function donateYield(uint256 sharesToBurn, bytes32 source) external {
		if (sharesToBurn == 0) {
			revert ZeroSharesToBurn();
		}

		if (balanceOf[msg.sender] < sharesToBurn) {
			revert InsufficientShares();
		}

		_burn(msg.sender, sharesToBurn);

		uint256 avaxEquivalent = convertToAssets(sharesToBurn);

		emit YieldDonated(msg.sender, source, sharesToBurn, avaxEquivalent);
	}

	/// @notice Allows the MinipoolManager contract to withdraw liquid staker funds to create a minipool
	/// @param assets The amount of AVAX to withdraw
	function withdrawForStaking(uint256 assets) external onlySpecificRegisteredContract("MinipoolManager", msg.sender) {
		emit WithdrawnForStaking(msg.sender, bytes32("MINIPOOL"), assets);

		stakingTotalAssets += assets;
		IWAVAX(address(asset)).withdraw(assets);
		IWithdrawer withdrawer = IWithdrawer(msg.sender);
		withdrawer.receiveWithdrawalAVAX{value: assets}();
	}

	/// @notice Allows any address with STAKER_ROLE to withdraw liquid staker funds for delegation
	/// @param assets The amount of AVAX to withdraw
	function withdrawForStaking(uint256 assets, bytes32 purpose) external onlyRole(STAKER_ROLE) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		if (!dao.getWithdrawForDelegationEnabled()) {
			revert WithdrawForStakingDisabled();
		}

		TokenggAVAX ggAVAX = TokenggAVAX(payable(getContractAddress("TokenggAVAX")));
		if (assets > ggAVAX.amountAvailableForStaking()) {
			revert WithdrawAmountTooLarge();
		}

		stakingTotalAssets += assets;
		IWAVAX(address(asset)).withdraw(assets);
		emit WithdrawnForStaking(msg.sender, purpose, assets);
		msg.sender.safeTransferETH(assets);
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

	/// @notice Allows withdraw queue to specify an amount of AVAX to withdraw from ggAVAX supply
	/// @param assets Amount of AVAX to be withdrawn
	/// @return shares Amount of ggAVAX burned
	function withdrawAVAX(uint256 assets) public onlyRole(WITHDRAW_QUEUE_ROLE) returns (uint256 shares) {
		shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.
		beforeWithdraw(assets, shares);
		_burn(msg.sender, shares);

		emit Withdraw(msg.sender, msg.sender, msg.sender, assets, shares);

		IWAVAX(address(asset)).withdraw(assets);
		msg.sender.safeTransferETH(assets);
	}

	/// @notice Allows withdraw queue to specify shares of ggAVAX to redeem for AVAX
	/// @param shares Amount of ggAVAX to burn
	/// @return assets Amount of AVAX withdrawn
	function redeemAVAX(uint256 shares) public onlyRole(WITHDRAW_QUEUE_ROLE) returns (uint256 assets) {
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

	/// @notice Override ERC4626 withdraw to restrict access to withdraw queue only
	/// @param assets Amount of AVAX to withdraw
	/// @param receiver Address to receive the AVAX
	/// @param owner Address that owns the shares being burned
	/// @return shares Amount of shares burned
	function withdraw(uint256 assets, address receiver, address owner) public override onlyRole(WITHDRAW_QUEUE_ROLE) returns (uint256 shares) {
		return super.withdraw(assets, receiver, owner);
	}

	/// @notice Override ERC4626 redeem to restrict access to withdraw queue only
	/// @param shares Amount of shares to redeem
	/// @param receiver Address to receive the AVAX
	/// @param owner Address that owns the shares being burned
	/// @return assets Amount of AVAX transferred
	function redeem(uint256 shares, address receiver, address owner) public override onlyRole(WITHDRAW_QUEUE_ROLE) returns (uint256 assets) {
		return super.redeem(shares, receiver, owner);
	}

	/// @notice Grant a role to an account - only admin can grant
	/// @param role The role identifier
	/// @param account The account to grant the role to
	function grantRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
		_grantRole(role, account);
	}

	/// @notice Revoke a role from an account - only admin can revoke
	/// @param role The role identifier
	/// @param account The account to revoke the role from
	function revokeRole(bytes32 role, address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
		// Prevent admin from revoking their own admin role without a pending admin
		if (role == DEFAULT_ADMIN_ROLE && account == msg.sender && _pendingAdmin == address(0)) {
			revert("Cannot revoke admin role without pending admin");
		}
		_revokeRole(role, account);
	}

	/// @notice Initiate admin transfer to a new address
	/// @param newAdmin The address to transfer admin rights to
	function transferAdmin(address newAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
		require(newAdmin != address(0), "New admin cannot be zero address");
		require(newAdmin != msg.sender, "Cannot transfer to self");

		_pendingAdmin = newAdmin;
		emit AdminTransferInitiated(msg.sender, newAdmin);
	}

	/// @notice Accept admin transfer - only pending admin can call
	function acceptAdmin() public {
		require(_pendingAdmin != address(0), "No pending admin transfer");
		require(msg.sender == _pendingAdmin, "Only pending admin can accept");

		address previousAdmin = _getAdmin();
		address newAdmin = _pendingAdmin;

		_pendingAdmin = address(0);
		_revokeRole(DEFAULT_ADMIN_ROLE, previousAdmin);
		_grantRole(DEFAULT_ADMIN_ROLE, newAdmin);

		emit AdminTransferCompleted(previousAdmin, newAdmin);
	}

	/// @notice Cancel pending admin transfer - only current admin can call
	function cancelAdminTransfer() public onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_pendingAdmin != address(0), "No pending admin transfer");

		address canceledPendingAdmin = _pendingAdmin;
		_pendingAdmin = address(0);

		emit AdminTransferCanceled(msg.sender, canceledPendingAdmin);
	}

	/// @notice Renounce admin role - only if there's a pending admin
	function renounceAdmin() public onlyRole(DEFAULT_ADMIN_ROLE) {
		require(_pendingAdmin != address(0), "Must have pending admin to renounce");
		_revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);
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

	/// @notice Check if an account has a specific role
	/// @param role The role identifier
	/// @param account The account to check
	/// @return bool True if the account has the role
	function hasRole(bytes32 role, address account) public view returns (bool) {
		return _roles[role][account];
	}

	/// @notice Get the current admin address
	/// @return address The current admin address
	function admin() public view returns (address) {
		return _getAdmin();
	}

	/// @notice Get the pending admin address
	/// @return address The pending admin address (zero if none)
	function pendingAdmin() public view returns (address) {
		return _pendingAdmin;
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

	/// @notice Internal function to check if caller has role
	/// @param role The role identifier
	function _checkRole(bytes32 role) internal view {
		if (!hasRole(role, msg.sender)) {
			revert AccessControlUnauthorizedAccount(msg.sender, role);
		}
	}

	/// @notice Internal function to grant a role
	/// @param role The role identifier
	/// @param account The account to grant the role to
	function _grantRole(bytes32 role, address account) internal {
		if (!hasRole(role, account)) {
			_roles[role][account] = true;
			if (role == DEFAULT_ADMIN_ROLE) {
				_currentAdmin = account;
			}
			emit RoleGranted(role, account, msg.sender);
		}
	}

	/// @notice Internal function to revoke a role
	/// @param role The role identifier
	/// @param account The account to revoke the role from
	function _revokeRole(bytes32 role, address account) internal {
		if (hasRole(role, account)) {
			_roles[role][account] = false;
			if (role == DEFAULT_ADMIN_ROLE && account == _currentAdmin) {
				_currentAdmin = address(0);
			}
			emit RoleRevoked(role, account, msg.sender);
		}
	}

	/// @notice Internal function to get the current admin
	/// @return address The current admin address
	function _getAdmin() internal view returns (address) {
		return _currentAdmin;
	}

	/// @dev Storage gap for future upgrades
	uint256[50] private __gap;
}
