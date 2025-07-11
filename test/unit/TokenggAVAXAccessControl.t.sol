// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";

contract TokenggAVAXAccessControlTest is BaseTest {
	using FixedPointMathLib for uint256;

	TokenggAVAX public token;
	address public admin;
	address public user1;
	address public user2;
	address public newAdmin;

	bytes32 public STAKER_ROLE;
	bytes32 public WITHDRAW_QUEUE_ROLE;
	bytes32 public DEFAULT_ADMIN_ROLE;

	function setUp() public override {
		super.setUp();

		// Create test users
		admin = getActor("admin");
		user1 = getActor("user1");
		user2 = getActor("user2");
		newAdmin = getActor("newAdmin");

		// Deploy and initialize token
		vm.startPrank(guardian);
		TokenggAVAX tokenImpl = new TokenggAVAX();
		token = TokenggAVAX(deployProxy(address(tokenImpl), guardian));
		registerContract(store, "TokenggAVAX", address(token));
		vm.stopPrank();

		// Initialize with admin
		vm.prank(admin);
		token.initialize(store, wavax, 0 ether);

		STAKER_ROLE = token.STAKER_ROLE();
		WITHDRAW_QUEUE_ROLE = token.WITHDRAW_QUEUE_ROLE();
		DEFAULT_ADMIN_ROLE = token.DEFAULT_ADMIN_ROLE();
	}

	// =============================================================================
	// Role Granting Tests
	// =============================================================================

	function testGrantDelegatorRole() public {
		// Admin can grant STAKER_ROLE
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		assertTrue(token.hasRole(STAKER_ROLE, user1));
		assertFalse(token.hasRole(STAKER_ROLE, user2));
	}

	function testGrantWithdrawQueueRole() public {
		// Admin can grant WITHDRAW_QUEUE_ROLE
		vm.prank(admin);
		token.grantRole(WITHDRAW_QUEUE_ROLE, user1);

		assertTrue(token.hasRole(WITHDRAW_QUEUE_ROLE, user1));
		assertFalse(token.hasRole(WITHDRAW_QUEUE_ROLE, user2));
	}

	function testGrantRoleEmitsEvent() public {
		// Check event emission
		vm.expectEmit(true, true, true, true);
		emit RoleGranted(STAKER_ROLE, user1, admin);

		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);
	}

	function testGrantRoleIdempotent() public {
		// First grant
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		// Second grant should be idempotent (no revert)
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		assertTrue(token.hasRole(STAKER_ROLE, user1));
	}

	function testGrantRoleOnlyAdmin() public {
		// Non-admin cannot grant roles
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(user1);
		token.grantRole(STAKER_ROLE, user2);
	}

	// =============================================================================
	// Role Revoking Tests
	// =============================================================================

	function testRevokeRole() public {
		// Grant role first
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);
		assertTrue(token.hasRole(STAKER_ROLE, user1));

		// Revoke role
		vm.prank(admin);
		token.revokeRole(STAKER_ROLE, user1);
		assertFalse(token.hasRole(STAKER_ROLE, user1));
	}

	function testRevokeRoleEmitsEvent() public {
		// Grant role first
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		// Check event emission for revoke
		vm.expectEmit(true, true, true, true);
		emit RoleRevoked(STAKER_ROLE, user1, admin);

		vm.prank(admin);
		token.revokeRole(STAKER_ROLE, user1);
	}

	function testRevokeRoleIdempotent() public {
		// First revoke (user doesn't have role)
		vm.prank(admin);
		token.revokeRole(STAKER_ROLE, user1);

		// Should not revert
		assertFalse(token.hasRole(STAKER_ROLE, user1));
	}

	function testRevokeRoleOnlyAdmin() public {
		// Grant role first
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		// Non-admin cannot revoke roles
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user2,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(user2);
		token.revokeRole(STAKER_ROLE, user1);
	}

	// =============================================================================
	// Admin Self-Revoke Prevention Tests
	// =============================================================================

	function testAdminCannotRevokeOwnRoleWithoutPending() public {
		// Admin cannot revoke their own admin role without pending admin
		vm.expectRevert("Cannot revoke admin role without pending admin");

		vm.prank(admin);
		token.revokeRole(DEFAULT_ADMIN_ROLE, admin);
	}

	function testAdminCanRevokeOwnRoleWithPending() public {
		// Start admin transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Now admin can revoke their own role
		vm.prank(admin);
		token.revokeRole(DEFAULT_ADMIN_ROLE, admin);

		assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
	}

	// =============================================================================
	// Admin Transfer Tests
	// =============================================================================

	function testTransferAdmin() public {
		// Check initial state
		assertEq(token.admin(), admin);
		assertEq(token.pendingAdmin(), address(0));

		// Initiate transfer
		vm.expectEmit(true, true, false, true);
		emit AdminTransferInitiated(admin, newAdmin);

		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Check intermediate state
		assertEq(token.admin(), admin);
		assertEq(token.pendingAdmin(), newAdmin);
	}

	function testTransferAdminCannotBeZeroAddress() public {
		vm.expectRevert("New admin cannot be zero address");

		vm.prank(admin);
		token.transferAdmin(address(0));
	}

	function testTransferAdminCannotBeSelf() public {
		vm.expectRevert("Cannot transfer to self");

		vm.prank(admin);
		token.transferAdmin(admin);
	}

	function testTransferAdminOnlyAdmin() public {
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(user1);
		token.transferAdmin(newAdmin);
	}

	// =============================================================================
	// Accept Admin Tests
	// =============================================================================

	function testAcceptAdmin() public {
		// Initiate transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Accept transfer
		vm.expectEmit(true, true, false, true);
		emit AdminTransferCompleted(admin, newAdmin);

		vm.prank(newAdmin);
		token.acceptAdmin();

		// Check final state
		assertEq(token.admin(), newAdmin);
		assertEq(token.pendingAdmin(), address(0));
		assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
		assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));
	}

	function testAcceptAdminOnlyPendingAdmin() public {
		// Initiate transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Only pending admin can accept
		vm.expectRevert("Only pending admin can accept");

		vm.prank(user1);
		token.acceptAdmin();
	}

	function testAcceptAdminRequiresPendingTransfer() public {
		// Cannot accept without pending transfer
		vm.expectRevert("No pending admin transfer");

		vm.prank(newAdmin);
		token.acceptAdmin();
	}

	// =============================================================================
	// Cancel Admin Transfer Tests
	// =============================================================================

	function testCancelAdminTransfer() public {
		// Initiate transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Cancel transfer
		vm.expectEmit(true, true, false, true);
		emit AdminTransferCanceled(admin, newAdmin);

		vm.prank(admin);
		token.cancelAdminTransfer();

		// Check state
		assertEq(token.admin(), admin);
		assertEq(token.pendingAdmin(), address(0));
		assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
	}

	function testCancelAdminTransferOnlyAdmin() public {
		// Initiate transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Only admin can cancel
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(user1);
		token.cancelAdminTransfer();
	}

	function testCancelAdminTransferRequiresPendingTransfer() public {
		// Cannot cancel without pending transfer
		vm.expectRevert("No pending admin transfer");

		vm.prank(admin);
		token.cancelAdminTransfer();
	}

	// =============================================================================
	// Renounce Admin Tests
	// =============================================================================

	function testRenounceAdmin() public {
		// Initiate transfer first
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Renounce admin
		vm.prank(admin);
		token.renounceAdmin();

		// Admin should no longer have role
		assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
		assertEq(token.admin(), address(0));
		assertEq(token.pendingAdmin(), newAdmin);
	}

	function testRenounceAdminRequiresPendingAdmin() public {
		// Cannot renounce without pending admin
		vm.expectRevert("Must have pending admin to renounce");

		vm.prank(admin);
		token.renounceAdmin();
	}

	function testRenounceAdminOnlyAdmin() public {
		// Initiate transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// Only admin can renounce
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(user1);
		token.renounceAdmin();
	}

	// =============================================================================
	// Role Access Control Tests
	// =============================================================================

	function testWithdrawForStakingRequiresDelegatorRole() public {
		// Enable delegation withdrawals
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		// Should revert without role
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			STAKER_ROLE
		));

		vm.prank(user1);
		token.withdrawForStaking(1 ether, bytes32("DELEGATION"));
	}

	function testWithdrawForStakingWorksWithRole() public {
		// Enable delegation withdrawals
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		// Grant role and add some funds
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);

		address depositor = getActor("depositor");

		// Add funds to token
		vm.deal(depositor, 10 ether);
		vm.prank(depositor);
		token.depositAVAX{value: 10 ether}();

		// Should work with role - withdraw a smaller amount to account for reserves
		vm.prank(user1);
		token.withdrawForStaking(0.5 ether, bytes32("DELEGATION"));
	}

	function testWithdrawAVAXRequiresWithdrawQueueRole() public {
		// Should revert without role
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			token.WITHDRAW_QUEUE_ROLE()
		));

		vm.prank(user1);
		token.withdrawAVAX(1 ether);
	}

	function testRedeemAVAXRequiresWithdrawQueueRole() public {
		// Should revert without role
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			user1,
			token.WITHDRAW_QUEUE_ROLE()
		));

		vm.prank(user1);
		token.redeemAVAX(1 ether);
	}

	// =============================================================================
	// Complex Transfer Scenarios
	// =============================================================================

	function testCompleteAdminTransferFlow() public {
		// Initial state
		assertEq(token.admin(), admin);
		assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));

		// 1. Admin initiates transfer
		vm.prank(admin);
		token.transferAdmin(newAdmin);

		// 2. Admin can still perform admin actions
		vm.prank(admin);
		token.grantRole(STAKER_ROLE, user1);
		assertTrue(token.hasRole(STAKER_ROLE, user1));

		// 3. New admin accepts
		vm.prank(newAdmin);
		token.acceptAdmin();

		// 4. New admin has control, old admin does not
		assertEq(token.admin(), newAdmin);
		assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, newAdmin));
		assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));

		// 5. New admin can perform admin actions
		vm.prank(newAdmin);
		token.grantRole(STAKER_ROLE, user2);
		assertTrue(token.hasRole(STAKER_ROLE, user2));

		// 6. Old admin cannot perform admin actions
		vm.expectRevert(abi.encodeWithSelector(
			TokenggAVAX.AccessControlUnauthorizedAccount.selector,
			admin,
			DEFAULT_ADMIN_ROLE
		));

		vm.prank(admin);
		token.revokeRole(STAKER_ROLE, user1);
	}

	function testTransferOverwritesPendingAdmin() public {
		// First transfer
		vm.prank(admin);
		token.transferAdmin(user1);
		assertEq(token.pendingAdmin(), user1);

		// Second transfer overwrites
		vm.prank(admin);
		token.transferAdmin(newAdmin);
		assertEq(token.pendingAdmin(), newAdmin);

		// First pending admin cannot accept
		vm.expectRevert("Only pending admin can accept");
		vm.prank(user1);
		token.acceptAdmin();

		// Second pending admin can accept
		vm.prank(newAdmin);
		token.acceptAdmin();
		assertEq(token.admin(), newAdmin);
	}

	// =============================================================================
	// Events
	// =============================================================================

	event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
	event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
	event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
	event AdminTransferCompleted(address indexed previousAdmin, address indexed newAdmin);
	event AdminTransferCanceled(address indexed admin, address indexed canceledPendingAdmin);
}
