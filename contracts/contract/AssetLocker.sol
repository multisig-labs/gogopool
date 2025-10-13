// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract AssetLocker is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
	using SafeTransferLib for ERC20;

	error InvalidAmount();
	error InvalidToken();
	error WithdrawalsNotEnabled();
	error InsufficientBalance();
	error TokenTransferFailed();
	error LockPeriodNotExpired();
	error InvalidLockDuration();
	error NoExcessFunds();
	error InvalidTreasury();

	event TokenLocked(address indexed user, address indexed token, uint256 amount, uint256 unlockTime, uint256 duration);
	event TokenWithdrawn(address indexed user, address indexed token, uint256 amount);
	event WithdrawDateSet(uint256 withdrawDate);
	event AllowedTokenAdded(address indexed token);
	event AllowedTokenRemoved(address indexed token);
	event LockDurationRangeSet(uint256 minDuration, uint256 maxDuration);
	event ExcessSwept(address indexed token, uint256 amount, address indexed treasury);
	event TreasurySet(address indexed treasury);

	struct UserLock {
		uint256 amount;
		uint256 unlockTime;
	}

	mapping(address => bool) private allowedTokens;
	mapping(address => mapping(address => UserLock)) private userLocks;
	mapping(address => uint256) private totalLockedByToken;
	uint256 private withdrawDate;
	uint256 private minLockDuration;
	uint256 private maxLockDuration;
	address private treasury;

	uint8 public version;

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(address admin, address _treasury) external initializer {
		__ReentrancyGuard_init();
		__AccessControl_init();
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		minLockDuration = 1 weeks;
		maxLockDuration = 52 weeks;
		treasury = _treasury;
		version = 1;
	}

	function lockTokens(address tokenAddress, uint256 amount, uint256 duration) external nonReentrant {
		if (amount == 0) {
			revert InvalidAmount();
		}
		if (!allowedTokens[tokenAddress]) {
			revert InvalidToken();
		}
		if (duration < minLockDuration || duration > maxLockDuration) {
			revert InvalidLockDuration();
		}

		ERC20 token = ERC20(tokenAddress);
		token.safeTransferFrom(msg.sender, address(this), amount);

		uint256 unlockTime = block.timestamp + duration;

		userLocks[msg.sender][tokenAddress].amount += amount;
		// Only extend unlockTime if the new unlockTime is later than the current one
		if (unlockTime > userLocks[msg.sender][tokenAddress].unlockTime) {
			userLocks[msg.sender][tokenAddress].unlockTime = unlockTime;
		}
		totalLockedByToken[tokenAddress] += amount;

		emit TokenLocked(msg.sender, tokenAddress, amount, unlockTime, duration);
	}

	function withdrawTokens(address tokenAddress, uint256 amount) external nonReentrant {
		if (amount == 0) {
			revert InvalidAmount();
		}
		if (withdrawDate > 0 && block.timestamp < withdrawDate) {
			revert WithdrawalsNotEnabled();
		}
		if (block.timestamp < userLocks[msg.sender][tokenAddress].unlockTime) {
			revert LockPeriodNotExpired();
		}
		if (userLocks[msg.sender][tokenAddress].amount < amount) {
			revert InsufficientBalance();
		}

		userLocks[msg.sender][tokenAddress].amount -= amount;
		totalLockedByToken[tokenAddress] -= amount;

		ERC20 token = ERC20(tokenAddress);
		token.safeTransfer(msg.sender, amount);

		emit TokenWithdrawn(msg.sender, tokenAddress, amount);
	}

	function setWithdrawDate(uint256 newWithdrawDate) external onlyRole(DEFAULT_ADMIN_ROLE) {
		withdrawDate = newWithdrawDate;
		emit WithdrawDateSet(newWithdrawDate);
	}

	function setLockDurationRange(uint256 newMinDuration, uint256 newMaxDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
		if (newMinDuration == 0 || newMinDuration >= newMaxDuration) {
			revert InvalidLockDuration();
		}
		minLockDuration = newMinDuration;
		maxLockDuration = newMaxDuration;
		emit LockDurationRangeSet(newMinDuration, newMaxDuration);
	}

	function addAllowedToken(address tokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
		allowedTokens[tokenAddress] = true;
		emit AllowedTokenAdded(tokenAddress);
	}

	function removeAllowedToken(address tokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
		allowedTokens[tokenAddress] = false;
		emit AllowedTokenRemoved(tokenAddress);
	}

	function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
		if (newTreasury == address(0)) {
			revert InvalidTreasury();
		}
		treasury = newTreasury;
		emit TreasurySet(newTreasury);
	}

	function sweepExcess(address tokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
		ERC20 token = ERC20(tokenAddress);
		uint256 contractBalance = token.balanceOf(address(this));
		uint256 lockedAmount = totalLockedByToken[tokenAddress];

		if (contractBalance <= lockedAmount) {
			revert NoExcessFunds();
		}

		uint256 excessAmount = contractBalance - lockedAmount;
		token.safeTransfer(treasury, excessAmount);

		emit ExcessSwept(tokenAddress, excessAmount, treasury);
	}

	function getUserLock(address user, address tokenAddress) external view returns (uint256 amount, uint256 unlockTime) {
		UserLock memory lock = userLocks[user][tokenAddress];
		return (lock.amount, lock.unlockTime);
	}

	function getTotalLockedByToken(address tokenAddress) external view returns (uint256) {
		return totalLockedByToken[tokenAddress];
	}

	function getWithdrawDate() external view returns (uint256) {
		return withdrawDate;
	}

	function getLockDurationRange() external view returns (uint256 minDuration, uint256 maxDuration) {
		return (minLockDuration, maxLockDuration);
	}

	function isTokenAllowed(address tokenAddress) external view returns (bool) {
		return allowedTokens[tokenAddress];
	}

	function getTreasury() external view returns (address) {
		return treasury;
	}

	function getExcessBalance(address tokenAddress) external view returns (uint256) {
		ERC20 token = ERC20(tokenAddress);
		uint256 contractBalance = token.balanceOf(address(this));
		uint256 lockedAmount = totalLockedByToken[tokenAddress];
		return contractBalance > lockedAmount ? contractBalance - lockedAmount : 0;
	}

	uint256[50] private __gap;
}
