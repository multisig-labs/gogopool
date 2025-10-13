// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {AssetLocker} from "../../contracts/contract/AssetLocker.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {TokenGGP} from "../../contracts/contract/tokens/TokenGGP.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AssetLockerTest is Test {
	AssetLocker public assetLocker;
	AssetLocker public assetLockerImpl;
	Storage public store;
	TokenGGP public ggp;
	ProxyAdmin public proxyAdmin;

	address public guardian;
	address public treasury;
	address public user1;
	address public user2;

	uint256 constant WITHDRAW_DATE = 2000000000; // May 18, 2033

	function setUp() public {
		guardian = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
		treasury = address(0x3);
		user1 = address(0x1);
		user2 = address(0x2);

		vm.label(guardian, "guardian");
		vm.label(treasury, "treasury");
		vm.label(user1, "user1");
		vm.label(user2, "user2");

		vm.startPrank(guardian, guardian);

		store = new Storage();
		ggp = new TokenGGP(store);

		assetLockerImpl = new AssetLocker();
		proxyAdmin = new ProxyAdmin();

		assetLocker = AssetLocker(
			deployProxyWithAdmin(
				address(assetLockerImpl),
				abi.encodeWithSelector(assetLockerImpl.initialize.selector, guardian, treasury),
				proxyAdmin,
				guardian
			)
		);

		assetLocker.addAllowedToken(address(ggp));
		assetLocker.setWithdrawDate(WITHDRAW_DATE);

		vm.stopPrank();

		deal(address(ggp), user1, 1000 ether);
		deal(address(ggp), user2, 1000 ether);
	}

	function testLockTokens() public {
		uint256 lockAmount = 100 ether;
		uint256 duration = 4 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		(uint256 amount, uint256 unlockTime) = assetLocker.getUserLock(user1, address(ggp));
		assertEq(amount, lockAmount);
		assertEq(unlockTime, block.timestamp + duration);
		assertEq(assetLocker.getTotalLockedByToken(address(ggp)), lockAmount);
	}

	function testLockTokensMultipleUsers() public {
		uint256 lockAmount1 = 100 ether;
		uint256 lockAmount2 = 200 ether;
		uint256 duration1 = 2 weeks;
		uint256 duration2 = 8 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount1);
		assetLocker.lockTokens(address(ggp), lockAmount1, duration1);
		vm.stopPrank();

		vm.startPrank(user2);
		ggp.approve(address(assetLocker), lockAmount2);
		assetLocker.lockTokens(address(ggp), lockAmount2, duration2);
		vm.stopPrank();

		(uint256 amount1, uint256 unlockTime1) = assetLocker.getUserLock(user1, address(ggp));
		(uint256 amount2, uint256 unlockTime2) = assetLocker.getUserLock(user2, address(ggp));

		assertEq(amount1, lockAmount1);
		assertEq(unlockTime1, block.timestamp + duration1);
		assertEq(amount2, lockAmount2);
		assertEq(unlockTime2, block.timestamp + duration2);
		assertEq(assetLocker.getTotalLockedByToken(address(ggp)), lockAmount1 + lockAmount2);
	}

	function testLockTokensInvalidAmount() public {
		vm.startPrank(user1);
		vm.expectRevert(AssetLocker.InvalidAmount.selector);
		assetLocker.lockTokens(address(ggp), 0, 2 weeks);
		vm.stopPrank();
	}

	function testLockTokensInvalidToken() public {
		address invalidToken = address(0x123);
		uint256 lockAmount = 100 ether;

		vm.startPrank(user1);
		vm.expectRevert(AssetLocker.InvalidToken.selector);
		assetLocker.lockTokens(invalidToken, lockAmount, 2 weeks);
		vm.stopPrank();
	}

	function testWithdrawTokensBeforeDate() public {
		uint256 lockAmount = 100 ether;
		uint256 duration = 2 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);

		vm.expectRevert(AssetLocker.WithdrawalsNotEnabled.selector);
		assetLocker.withdrawTokens(address(ggp), lockAmount);
		vm.stopPrank();
	}

	function testWithdrawTokensAfterDate() public {
		uint256 lockAmount = 100 ether;
		uint256 duration = 2 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		// Fast forward past both withdraw date and lock duration
		vm.warp(WITHDRAW_DATE + duration + 1);

		uint256 balanceBefore = ggp.balanceOf(user1);

		vm.startPrank(user1);
		assetLocker.withdrawTokens(address(ggp), lockAmount);
		vm.stopPrank();

		uint256 balanceAfter = ggp.balanceOf(user1);
		assertEq(balanceAfter - balanceBefore, lockAmount);

		(uint256 amount, uint256 unlockTime) = assetLocker.getUserLock(user1, address(ggp));
		assertEq(amount, 0);
		assertEq(assetLocker.getTotalLockedByToken(address(ggp)), 0);
	}

	function testWithdrawTokensPartial() public {
		uint256 lockAmount = 100 ether;
		uint256 withdrawAmount = 30 ether;
		uint256 duration = 2 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		// Fast forward past both withdraw date and lock duration
		vm.warp(WITHDRAW_DATE + duration + 1);

		uint256 balanceBefore = ggp.balanceOf(user1);

		vm.startPrank(user1);
		assetLocker.withdrawTokens(address(ggp), withdrawAmount);
		vm.stopPrank();

		uint256 balanceAfter = ggp.balanceOf(user1);
		assertEq(balanceAfter - balanceBefore, withdrawAmount);

		(uint256 amount, uint256 unlockTime) = assetLocker.getUserLock(user1, address(ggp));
		assertEq(amount, lockAmount - withdrawAmount);
		assertEq(assetLocker.getTotalLockedByToken(address(ggp)), lockAmount - withdrawAmount);
	}

	function testWithdrawTokensInsufficientBalance() public {
		uint256 lockAmount = 100 ether;
		uint256 withdrawAmount = 200 ether;
		uint256 duration = 2 weeks;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		// Fast forward past both withdraw date and lock duration
		vm.warp(WITHDRAW_DATE + duration + 1);

		vm.startPrank(user1);
		vm.expectRevert(AssetLocker.InsufficientBalance.selector);
		assetLocker.withdrawTokens(address(ggp), withdrawAmount);
		vm.stopPrank();
	}

	function testSetWithdrawDate() public {
		uint256 newWithdrawDate = WITHDRAW_DATE + 86400;

		vm.prank(guardian);
		assetLocker.setWithdrawDate(newWithdrawDate);

		assertEq(assetLocker.getWithdrawDate(), newWithdrawDate);
	}

	function testSetWithdrawDateNotAdmin() public {
		uint256 newWithdrawDate = WITHDRAW_DATE + 86400;

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.setWithdrawDate(newWithdrawDate);
	}

	function testAddAllowedToken() public {
		address newToken = address(0x456);

		vm.prank(guardian);
		assetLocker.addAllowedToken(newToken);

		assertTrue(assetLocker.isTokenAllowed(newToken));
	}

	function testRemoveAllowedToken() public {
		vm.prank(guardian);
		assetLocker.removeAllowedToken(address(ggp));

		assertFalse(assetLocker.isTokenAllowed(address(ggp)));
	}

	function testAddAllowedTokenNotAdmin() public {
		address newToken = address(0x456);

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.addAllowedToken(newToken);
	}

	function testRemoveAllowedTokenNotAdmin() public {
		vm.prank(user1);
		vm.expectRevert();
		assetLocker.removeAllowedToken(address(ggp));
	}

	function testWithdrawTokensBeforeLockExpiry() public {
		uint256 lockAmount = 100 ether;
		uint256 duration = 4 weeks;

		// Set withdraw date to current time so it doesn't block withdrawals
		vm.prank(guardian);
		assetLocker.setWithdrawDate(block.timestamp);

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		// Fast forward 2 weeks (less than 4 week lock duration)
		vm.warp(block.timestamp + 2 weeks);

		vm.startPrank(user1);
		vm.expectRevert(AssetLocker.LockPeriodNotExpired.selector);
		assetLocker.withdrawTokens(address(ggp), lockAmount);
		vm.stopPrank();
	}

	function testSetLockDurationRange() public {
		uint256 newMinDuration = 3 days;
		uint256 newMaxDuration = 104 weeks; // 2 years

		vm.prank(guardian);
		assetLocker.setLockDurationRange(newMinDuration, newMaxDuration);

		(uint256 minDuration, uint256 maxDuration) = assetLocker.getLockDurationRange();
		assertEq(minDuration, newMinDuration);
		assertEq(maxDuration, newMaxDuration);
	}

	function testSetLockDurationRangeNotAdmin() public {
		uint256 newMinDuration = 3 days;
		uint256 newMaxDuration = 104 weeks;

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.setLockDurationRange(newMinDuration, newMaxDuration);
	}

	function testSetLockDurationRangeInvalid() public {
		// Test min >= max
		vm.prank(guardian);
		vm.expectRevert(AssetLocker.InvalidLockDuration.selector);
		assetLocker.setLockDurationRange(4 weeks, 2 weeks);

		// Test min = 0
		vm.prank(guardian);
		vm.expectRevert(AssetLocker.InvalidLockDuration.selector);
		assetLocker.setLockDurationRange(0, 4 weeks);
	}

	function testGetLockDurationRangeDefault() public {
		(uint256 minDuration, uint256 maxDuration) = assetLocker.getLockDurationRange();
		assertEq(minDuration, 1 weeks);
		assertEq(maxDuration, 52 weeks);
	}

	function testLockTokensInvalidDuration() public {
		uint256 lockAmount = 100 ether;

		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);

		// Test duration too short
		vm.expectRevert(AssetLocker.InvalidLockDuration.selector);
		assetLocker.lockTokens(address(ggp), lockAmount, 3 days);

		// Test duration too long
		vm.expectRevert(AssetLocker.InvalidLockDuration.selector);
		assetLocker.lockTokens(address(ggp), lockAmount, 104 weeks);

		vm.stopPrank();
	}

	function testLockTokensWithDifferentDurations() public {
		uint256 lockAmount = 100 ether;
		uint256 shortDuration = 1 weeks; // Min duration
		uint256 longDuration = 52 weeks; // Max duration

		// Lock with minimum duration
		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, shortDuration);
		vm.stopPrank();

		// Lock with maximum duration
		vm.startPrank(user2);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, longDuration);
		vm.stopPrank();

		(uint256 amount1, uint256 unlockTime1) = assetLocker.getUserLock(user1, address(ggp));
		(uint256 amount2, uint256 unlockTime2) = assetLocker.getUserLock(user2, address(ggp));

		// Both should have same amount
		assertEq(amount1, lockAmount);
		assertEq(amount2, lockAmount);

		// Unlock times should be different
		assertEq(unlockTime1, block.timestamp + shortDuration);
		assertEq(unlockTime2, block.timestamp + longDuration);
	}

	function testWithdrawTokensNoWithdrawDate() public {
		uint256 lockAmount = 100 ether;
		uint256 duration = 2 weeks;

		// Create new AssetLocker without withdraw date set
		AssetLocker newAssetLockerImpl = new AssetLocker();
		ProxyAdmin newProxyAdmin = new ProxyAdmin();

		AssetLocker newAssetLocker = AssetLocker(
			deployProxyWithAdmin(
				address(newAssetLockerImpl),
				abi.encodeWithSelector(newAssetLockerImpl.initialize.selector, guardian, treasury),
				newProxyAdmin,
				guardian
			)
		);

		vm.prank(guardian);
		newAssetLocker.addAllowedToken(address(ggp));

		vm.startPrank(user1);
		ggp.approve(address(newAssetLocker), lockAmount);
		newAssetLocker.lockTokens(address(ggp), lockAmount, duration);
		vm.stopPrank();

		// Fast forward past lock duration
		vm.warp(block.timestamp + duration + 1);

		// Should be able to withdraw since withdrawDate is 0 (not set)
		vm.startPrank(user1);
		newAssetLocker.withdrawTokens(address(ggp), lockAmount);
		vm.stopPrank();

		(uint256 amount, ) = newAssetLocker.getUserLock(user1, address(ggp));
		assertEq(amount, 0);
	}

	function testSweepExcess() public {
		uint256 lockAmount = 100 ether;
		uint256 excessAmount = 50 ether;

		// User locks tokens normally
		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, 2 weeks);
		vm.stopPrank();

		// Simulate excess tokens being sent directly to the contract (airdrop, etc)
		deal(address(ggp), address(assetLocker), lockAmount + excessAmount);

		// Check excess balance
		assertEq(assetLocker.getExcessBalance(address(ggp)), excessAmount);

		// Treasury balance before
		uint256 treasuryBalanceBefore = ggp.balanceOf(treasury);

		// Guardian sweeps excess
		vm.prank(guardian);
		assetLocker.sweepExcess(address(ggp));

		// Treasury should receive the excess
		uint256 treasuryBalanceAfter = ggp.balanceOf(treasury);
		assertEq(treasuryBalanceAfter - treasuryBalanceBefore, excessAmount);

		// Excess balance should now be 0
		assertEq(assetLocker.getExcessBalance(address(ggp)), 0);
	}

	function testSweepExcessNoExcess() public {
		uint256 lockAmount = 100 ether;

		// User locks tokens normally
		vm.startPrank(user1);
		ggp.approve(address(assetLocker), lockAmount);
		assetLocker.lockTokens(address(ggp), lockAmount, 2 weeks);
		vm.stopPrank();

		// Try to sweep when there's no excess
		vm.prank(guardian);
		vm.expectRevert(AssetLocker.NoExcessFunds.selector);
		assetLocker.sweepExcess(address(ggp));
	}

	function testSweepExcessNotAdmin() public {
		vm.prank(user1);
		vm.expectRevert();
		assetLocker.sweepExcess(address(ggp));
	}

	function testSetTreasury() public {
		address newTreasury = address(0x999);

		vm.prank(guardian);
		assetLocker.setTreasury(newTreasury);

		assertEq(assetLocker.getTreasury(), newTreasury);
	}

	function testSetTreasuryZeroAddress() public {
		vm.prank(guardian);
		vm.expectRevert(AssetLocker.InvalidTreasury.selector);
		assetLocker.setTreasury(address(0));
	}

	function testSetTreasuryNotAdmin() public {
		address newTreasury = address(0x999);

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.setTreasury(newTreasury);
	}

	function testGrantAndRevokeAdminRole() public {
		address newAdmin = address(0x777);
		bytes32 adminRole = 0x00; // DEFAULT_ADMIN_ROLE is bytes32(0)

		// Grant admin role to new admin
		vm.prank(guardian);
		assetLocker.grantRole(adminRole, newAdmin);

		// New admin should be able to perform admin functions
		vm.prank(newAdmin);
		assetLocker.setWithdrawDate(block.timestamp + 1 days);

		// Revoke admin role from new admin
		vm.prank(guardian);
		assetLocker.revokeRole(adminRole, newAdmin);

		// Should not be able to perform admin functions anymore
		vm.prank(newAdmin);
		vm.expectRevert();
		assetLocker.setWithdrawDate(block.timestamp + 2 days);
	}

	function testRoleManagementNotAdmin() public {
		address newAdmin = address(0x777);
		bytes32 adminRole = 0x00; // DEFAULT_ADMIN_ROLE is bytes32(0)

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.grantRole(adminRole, newAdmin);

		vm.prank(user1);
		vm.expectRevert();
		assetLocker.revokeRole(adminRole, guardian);
	}

	function testGetTreasury() public {
		assertEq(assetLocker.getTreasury(), treasury);
	}

	function testGetExcessBalanceZero() public {
		assertEq(assetLocker.getExcessBalance(address(ggp)), 0);
	}

	function deployProxyWithAdmin(address impl, bytes memory toCall, ProxyAdmin admin, address owner) internal returns (address payable) {
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), toCall);
		admin.transferOwnership(owner);
		return payable(transparentProxy);
	}
}