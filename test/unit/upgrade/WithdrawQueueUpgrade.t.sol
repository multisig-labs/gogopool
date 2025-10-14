// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../utils/BaseTest.sol";
import {WithdrawQueue as WithdrawQueueV1} from "../../../contracts/contract/previousVersions/WithdrawQueueV1.sol";
import {WithdrawQueue} from "../../../contracts/contract/WithdrawQueue.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract WithdrawQueueUpgradeTest is BaseTest {
	WithdrawQueue private withdrawQueue;
	WithdrawQueueV1 private withdrawQueueV1;
	TransparentUpgradeableProxy private proxy;

	address private alice;
	address private bob;

	uint48 private constant UNSTAKE_DELAY = 7 days;
	uint48 private constant MAX_EXPIRATION_DELAY = 60 days;

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);

		// Deploy V1 WithdrawQueue (same setup as WithdrawQueue.t.sol)
		vm.startPrank(guardian);
		WithdrawQueueV1 withdrawQueueV1Impl = new WithdrawQueueV1();
		bytes memory initData = abi.encodeWithSelector(
			WithdrawQueueV1.initialize.selector,
			address(ggAVAX),
			address(store),
			UNSTAKE_DELAY,
			MAX_EXPIRATION_DELAY
		);

		proxy = new TransparentUpgradeableProxy(address(withdrawQueueV1Impl), address(proxyAdmin), initData);
		withdrawQueueV1 = WithdrawQueueV1(payable(address(proxy)));

		// Grant roles (same as WithdrawQueue.t.sol)
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), address(withdrawQueueV1));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(withdrawQueueV1));
		withdrawQueueV1.grantRole(withdrawQueueV1.DEPOSITOR_ROLE(), address(ggAVAX));

		// Set reserve ratio to 0% for testing
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		vm.stopPrank();
	}

	function testV1Functionality() public {
		// Test that V1 works as expected
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 1 ether}();

		vm.prank(alice);
		ggAVAX.approve(address(withdrawQueueV1), 0.5 ether);

		vm.prank(alice);
		uint256 requestId = withdrawQueueV1.requestUnstake(0.5 ether, 7 days);

		assertEq(requestId, 0);
		assertEq(withdrawQueueV1.nextRequestId(), 1);
		assertEq(withdrawQueueV1.getPendingRequestsCount(), 1);
	}

	function testUpgradePreservesStorageAndAddsNewFeatures() public {
		// First, create some state in V1
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 1 ether}();

		vm.prank(alice);
		ggAVAX.approve(address(withdrawQueueV1), 0.5 ether);

		vm.prank(alice);
		uint256 requestId = withdrawQueueV1.requestUnstake(0.5 ether, 7 days);

		// Store V1 state
		uint256 v1NextRequestId = withdrawQueueV1.nextRequestId();
		uint256 v1TotalAllocated = withdrawQueueV1.totalAllocatedFunds();
		uint48 v1UnstakeDelay = withdrawQueueV1.unstakeDelay();

		// Upgrade to V2
		vm.startPrank(guardian);
		WithdrawQueue withdrawQueueV2Impl = new WithdrawQueue();
		proxyAdmin.upgrade(proxy, address(withdrawQueueV2Impl));
		vm.stopPrank();

		// Cast to new interface
		withdrawQueue = WithdrawQueue(payable(address(proxy)));

		// Grant new roles needed for V2
		vm.startPrank(guardian);
		withdrawQueue.grantRole(withdrawQueue.PAUSER_ROLE(), guardian);
		vm.stopPrank();

		// Verify storage is preserved
		assertEq(withdrawQueue.nextRequestId(), v1NextRequestId);
		assertEq(withdrawQueue.totalAllocatedFunds(), v1TotalAllocated);
		assertEq(withdrawQueue.unstakeDelay(), v1UnstakeDelay);
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);

		// Verify original request is preserved
		(address requester, uint256 shares,,,,,) = withdrawQueue.requests(requestId);
		assertEq(requester, alice);
		assertEq(shares, 0.5 ether);

		// Test new pause functionality works
		assertFalse(withdrawQueue.paused());

		vm.prank(guardian);
		withdrawQueue.pause();
		assertTrue(withdrawQueue.paused());

		// Test that new requests are blocked when paused
		vm.prank(bob);
		ggAVAX.depositAVAX{value: 1 ether}();

		vm.prank(bob);
		ggAVAX.approve(address(withdrawQueue), 0.5 ether);

		vm.prank(bob);
		vm.expectRevert(WithdrawQueue.ContractPausedError.selector);
		withdrawQueue.requestUnstake(0.5 ether, 7 days);

		// Test that old functionality still works after unpause
		vm.prank(guardian);
		withdrawQueue.unpause();

		vm.prank(bob);
		uint256 newRequestId = withdrawQueue.requestUnstake(0.5 ether, 7 days);

		assertEq(newRequestId, 1); // Should be next ID
		assertEq(withdrawQueue.nextRequestId(), 2);
		assertEq(withdrawQueue.getPendingRequestsCount(), 2);
	}
}
