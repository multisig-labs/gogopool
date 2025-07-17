// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {stdError} from "forge-std/StdError.sol";
import {console2} from "forge-std/console2.sol";

contract WithdrawQueueTest is BaseTest {
	using FixedPointMathLib for uint256;

	WithdrawQueue private withdrawQueue;
	address private alice;
	address private bob;
	address private charlie;

	uint48 private constant UNSTAKE_DELAY = 7 days;
	uint48 private constant EXPIRATION_DELAY = 14 days;

	event ExpiredFundsReclaimed(uint256 indexed requestId, uint256 amount);
	event ExpiredSharesReturned(uint256 indexed requestId, address indexed requester, uint256 shares);
	event RequestCancelled(uint256 indexed requestId, address indexed requester, uint256 shares);
	event ExcessSharesBurnt(uint256 indexed requestId, uint256 sharesBurnt);
	event BatchExpiredFundsReclaimed(uint256 totalAmount, uint256 requestsProcessed);
	event ContractInitialized(address indexed tokenggAVAX, uint48 unstakeDelay, uint48 expirationDelay);

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);
		charlie = getActorWithTokens("charlie", MAX_AMT, MAX_AMT);

		// Deploy WithdrawQueue
		vm.startPrank(guardian);
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory initData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);

		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(withdrawQueueImpl), address(proxyAdmin), initData);

		withdrawQueue = WithdrawQueue(payable(address(proxy)));

		// Grant WITHDRAW_QUEUE_ROLE to the WithdrawQueue contract
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), charlie);
		withdrawQueue.grantRole(withdrawQueue.DEPOSITOR_ROLE(), charlie);

		// Set max pending requests limit for testing
		withdrawQueue.setMaxPendingRequestsLimit(25);

		// Set reserve ratio to 0% so all funds can be withdrawn for staking
		vm.startPrank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		vm.stopPrank();
	}

	function testInitialization() public {
		assertEq(address(withdrawQueue.tokenggAVAX()), address(ggAVAX));
		assertEq(withdrawQueue.unstakeDelay(), UNSTAKE_DELAY);
		assertEq(withdrawQueue.expirationDelay(), EXPIRATION_DELAY);
		assertEq(withdrawQueue.nextRequestId(), 0);
		assertEq(withdrawQueue.getMaxPendingRequestsLimit(), 25);
	}

	function testMaxPendingRequestsLimit() public {
		// Test getter
		assertEq(withdrawQueue.getMaxPendingRequestsLimit(), 25);

		// Test setter (only admin can set)
		vm.prank(guardian);
		withdrawQueue.setMaxPendingRequestsLimit(100);
		assertEq(withdrawQueue.getMaxPendingRequestsLimit(), 100);

		// Test that non-admin cannot set
		vm.prank(alice);
		vm.expectRevert();
		withdrawQueue.setMaxPendingRequestsLimit(200);
	}

	function testSetUnstakeDelay() public {
		// Test initial value
		assertEq(withdrawQueue.unstakeDelay(), UNSTAKE_DELAY);
		
		// Test setter (only admin can set)
		uint48 newDelay = 10 days;
		vm.prank(guardian);
		withdrawQueue.setUnstakeDelay(newDelay);
		assertEq(withdrawQueue.unstakeDelay(), newDelay);
		
		// Test that non-admin cannot set
		vm.prank(alice);
		vm.expectRevert();
		withdrawQueue.setUnstakeDelay(5 days);
	}

	function testSetExpirationDelay() public {
		// Test initial value
		assertEq(withdrawQueue.expirationDelay(), EXPIRATION_DELAY);
		
		// Test setter (only admin can set)
		uint48 newDelay = 21 days;
		vm.prank(guardian);
		withdrawQueue.setExpirationDelay(newDelay);
		assertEq(withdrawQueue.expirationDelay(), newDelay);
		
		// Test that non-admin cannot set
		vm.prank(alice);
		vm.expectRevert();
		withdrawQueue.setExpirationDelay(7 days);
	}

	function testInitializationEvent() public {
		// Deploy a new WithdrawQueue to test the initialization event
		WithdrawQueue newWithdrawQueueImpl = new WithdrawQueue();
		bytes memory initData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);

		// Expect the ContractInitialized event
		vm.expectEmit(true, false, false, true);
		emit ContractInitialized(address(ggAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);

		TransparentUpgradeableProxy newProxy = new TransparentUpgradeableProxy(address(newWithdrawQueueImpl), address(proxyAdmin), initData);
		WithdrawQueue newWithdrawQueue = WithdrawQueue(payable(address(newProxy)));

		// Verify initialization
		assertEq(address(newWithdrawQueue.tokenggAVAX()), address(ggAVAX));
		assertEq(newWithdrawQueue.unstakeDelay(), UNSTAKE_DELAY);
		assertEq(newWithdrawQueue.expirationDelay(), EXPIRATION_DELAY);
	}

	function testRequestUnstakeBasic() public {
		// Setup initial ggAVAX deposit for alice
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();

		uint256 sharesToUnstake = 100 ether;
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		WithdrawQueue.UnstakeRequest memory request = withdrawQueue.getRequestInfo(requestId);

		assertEq(requestId, 0);
		assertEq(request.requester, alice);
		assertEq(request.shares, sharesToUnstake);
		assertEq(request.requestTime, block.timestamp);
		assertEq(request.claimableTime, block.timestamp + UNSTAKE_DELAY);
		assertEq(request.expirationTime, block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY);

		// Request should be pending and not fulfilled
		assertEq(withdrawQueue.isRequestPending(requestId), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);

		// Check expected assets equals current conversion
		uint256 expectedExpectedAssets = ggAVAX.convertToAssets(sharesToUnstake);
		assertEq(request.expectedAssets, expectedExpectedAssets);

		// Check shares were transferred to queue (not redeemed yet)
		assertEq(ggAVAX.balanceOf(alice), aliceSharesBefore - sharesToUnstake);
		assertEq(ggAVAX.balanceOf(address(withdrawQueue)), sharesToUnstake);

		// Check request is in pending queue
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);
		assertEq(withdrawQueue.isRequestPending(requestId), true);

		// Check user requests mapping
		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(alice);
		assertEq(userRequests.length, 1);
		assertEq(userRequests[0], requestId);
	}

	function testRequestUnstakeZeroShares() public {
		vm.startPrank(alice);
		vm.expectRevert(WithdrawQueue.ZeroShares.selector);
		withdrawQueue.requestUnstake(0);
		vm.stopPrank();
	}

	function testRequestUnstakeInsufficientBalance() public {
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = ggAVAX.balanceOf(alice) + 1;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		vm.expectRevert(WithdrawQueue.InsufficientTokenBalance.selector);
		withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();
	}

	function testMultipleRequestsFromSameUser() public {
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 shares1 = 100 ether;
		uint256 shares2 = 200 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1 + shares2);

		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		assertEq(requestId1, 0);
		assertEq(requestId2, 1);

		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(alice);
		assertEq(userRequests.length, 2);
		assertEq(userRequests[0], requestId1);
		assertEq(userRequests[1], requestId2);
	}

	function testDepositAdditionalYield() public {
		uint256 yieldAmount = 100 ether;

		uint256 ggAVAXWAVAXBefore = ggAVAX.asset().balanceOf(address(ggAVAX));

		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Since no pending requests, all yield should be returned to ggAVAX as WAVAX
		assertEq(ggAVAX.asset().balanceOf(address(ggAVAX)), ggAVAXWAVAXBefore + yieldAmount);
	}

	function testDepositAdditionalYieldWithInsufficientAvailableAVAX() public {
		// Setup initial deposits and drain liquidity
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain all liquidity by withdrawing for delegation
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Create a large request that won't be fulfilled
		uint256 sharesToUnstake = 500 ether;
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Deposit yield that's less than needed
		uint256 yieldAmount = 100 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Request should still be pending since not enough available AVAX
		assertEq(withdrawQueue.isRequestPending(requestId), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);
		assertEq(address(withdrawQueue).balance, yieldAmount);
	}

	function testReceiveAVAXReverts() public {
		uint256 yieldAmount = 50 ether;

		uint256 ggAVAXWAVAXBefore = ggAVAX.asset().balanceOf(address(ggAVAX));

		vm.deal(charlie, yieldAmount);
		vm.startPrank(charlie);
		vm.expectRevert(WithdrawQueue.DirectAVAXDepositsNotSupported.selector);
		address(withdrawQueue).call{value: yieldAmount}("");
		vm.stopPrank();
	}

	function testDepositAdditionalYieldAutoFulfillsPendingRequests() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 ggAVAXWAVAXBefore = ggAVAX.asset().balanceOf(address(ggAVAX));

		// Create a request that goes to pending queue
		uint256 sharesToUnstake = 100 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Verify it's queued
		assertEq(withdrawQueue.isRequestPending(requestId), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);

		// Deposit yield - should auto-fulfill the pending request
		uint256 yieldAmount = 150 ether; // More than enough
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Check request is now fulfilled
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), true);
		assertEq(withdrawQueue.getRequestInfo(requestId).allocatedFunds, withdrawQueue.getRequestInfo(requestId).expectedAssets);

		// Check pending queue is empty
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);

		// Verify that the additional yield is sent to ggavax
		assertEq(ggAVAX.asset().balanceOf(address(ggAVAX)), ggAVAXWAVAXBefore + yieldAmount - sharesToUnstake);
	}

	function testPartialYieldFulfillment() public {
		// Setup initial deposits - alice and bob both deposit, but then we'll drain liquidity
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 300 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 300 ether}();
		vm.stopPrank();

		// Use rialto to withdraw all funds from ggAVAX to simulate staking
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();

		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Now ggAVAX should have 0 liquidity
		// Create two requests that get queued
		uint256 shares1 = 100 ether;
		uint256 shares2 = 150 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Both should be queued
		assertEq(withdrawQueue.getPendingRequestsCount(), 2);

		// Deposit yield - only enough for first request
		uint256 yieldAmount = 120 ether; // Enough for first (100), not second (150)
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// First request should be fulfilled, second still pending
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId2), false);

		// One request still pending
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);
	}

	function testMultipleYieldDepositsAutoFulfillQueue() public {
		// Setup ggAVAX deposits for both users
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 200 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 300 ether}();
		vm.stopPrank();

		// Withdraw all funds for delegation
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Create multiple requests that get queued
		uint256 shares1 = 100 ether;
		uint256 shares2 = 150 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Both should be queued
		assertEq(withdrawQueue.getPendingRequestsCount(), 2);

		// First yield deposit - fulfill first request
		vm.deal(charlie, 120 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 120 ether}(0, 120 ether, bytes32("TEST_YIELD"));

		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);

		// Second yield deposit - fulfill second request
		vm.deal(charlie, 160 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 160 ether}(0, 160 ether, bytes32("TEST_YIELD"));

		assertEq(withdrawQueue.isFulfilledRequest(requestId2), true);
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
	}

	function testClaimUnstake() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 100 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Should not be claimable before delay
		assertEq(withdrawQueue.canClaimRequest(requestId), false);

		// Fast forward past delay
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Now should be claimable
		assertEq(withdrawQueue.canClaimRequest(requestId), true);

		// Check balance before claim
		uint256 aliceBalanceBefore = alice.balance;
		uint256 expectedAmount = withdrawQueue.getRequestInfo(requestId).expectedAssets;

		// Claim the unstake
		vm.prank(alice);
		withdrawQueue.claimUnstake(requestId);

		// Check balance after claim
		assertEq(alice.balance, aliceBalanceBefore + expectedAmount);
		assertEq(withdrawQueue.getRequestInfo(requestId).allocatedFunds, 0);
		assertEq(withdrawQueue.canClaimRequest(requestId), false);
	}

	function testcanClaimRequest() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Should not be claimable before fulfillment
		assertEq(withdrawQueue.canClaimRequest(requestId), false);

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Should not be claimable before delay even after fulfillment
		assertEq(withdrawQueue.canClaimRequest(requestId), false);

		// Fast forward past delay
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Now should be claimable
		assertEq(withdrawQueue.canClaimRequest(requestId), true);
	}

	function testReclaimExpiredFunds() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Verify request is fulfilled
		assertEq(withdrawQueue.isFulfilledRequest(requestId), true);
		uint256 allocatedAmount = withdrawQueue.getRequestInfo(requestId).allocatedFunds;
		assertGt(allocatedAmount, 0);

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Check that there's 1 expired request
		assertEq(withdrawQueue.getExpiredRequestsCount(), 1);

		// Check alice's ggAVAX balance before reclaim (NEW BEHAVIOR)
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);
		uint256 totalAllocatedBefore = withdrawQueue.totalAllocatedFunds();

		// Reclaim expired funds
		(uint256 reclaimedAmount, uint256 processedCount) = withdrawQueue.reclaimExpiredFunds(10);

		// Verify reclaim results
		assertEq(processedCount, 1);
		assertEq(reclaimedAmount, allocatedAmount);

		// Verify request data has been deleted
		assertEq(withdrawQueue.getRequestInfo(requestId).allocatedFunds, 0);
		assertEq(withdrawQueue.totalAllocatedFunds(), totalAllocatedBefore - allocatedAmount);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);

		// Verify alice received ggAVAX shares back
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		assertEq(aliceSharesAfter, aliceSharesBefore + sharesToUnstake);

		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);
		assertEq(withdrawQueue.canClaimRequest(requestId), false);
	}

	function testReclaimExpiredFundsMultiple() public {
		// Setup initial ggAVAX deposits
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Create multiple requests
		uint256 shares1 = 100 ether;
		uint256 shares2 = 150 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Fulfill both with MEV
		uint256 yieldAmount = 300 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Verify both requests are fulfilled
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId2), true);

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Check that there are 2 expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 2);

		// Check users' ggAVAX balances before reclaim
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);
		uint256 bobSharesBefore = ggAVAX.balanceOf(bob);

		// Reclaim with limit of 1
		(uint256 reclaimedAmount1, uint256 processedCount1) = withdrawQueue.reclaimExpiredFunds(1);
		assertEq(processedCount1, 1);
		assertGt(reclaimedAmount1, 0);

		// Should still have 1 expired request
		assertEq(withdrawQueue.getExpiredRequestsCount(), 1);

		// Reclaim the remaining one
		(uint256 reclaimedAmount2, uint256 processedCount2) = withdrawQueue.reclaimExpiredFunds(1);
		assertEq(processedCount2, 1);
		assertGt(reclaimedAmount2, 0);

		// Should have no more expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);

		// Verify both users received ggAVAX shares back
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		uint256 bobSharesAfter = ggAVAX.balanceOf(bob);

		assertEq(aliceSharesAfter, aliceSharesBefore + shares1);
		assertEq(bobSharesAfter, bobSharesBefore + shares2);
	}

	function testBatchExpiredFundsReclaimedEvent() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Get expected values
		uint256 expectedAmount = withdrawQueue.getRequestInfo(requestId).allocatedFunds;

		// Expect BatchExpiredFundsReclaimed event
		vm.expectEmit(false, false, false, true);
		emit BatchExpiredFundsReclaimed(expectedAmount, 1);

		// Reclaim expired funds
		(uint256 reclaimedAmount, uint256 processedCount) = withdrawQueue.reclaimExpiredFunds(10);

		// Verify event data matches
		assertEq(reclaimedAmount, expectedAmount);
		assertEq(processedCount, 1);
	}

	function testReclaimExpiredFundsWithPendingRequests() public {
		// Setup initial ggAVAX deposits
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Get balances before unstake
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);
		uint256 bobSharesBefore = ggAVAX.balanceOf(bob);

		// Drain liquidity for one request to stay pending
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		uint256 shares1 = 100 ether;
		uint256 shares2 = 150 ether;

		// Create requests - one will be fulfilled, one will stay pending
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Both users have their shares deducted
		assertEq(ggAVAX.balanceOf(alice), aliceSharesBefore - shares1);
		assertEq(ggAVAX.balanceOf(bob), bobSharesBefore - shares2);

		// Fulfill only one request with yield
		uint256 yieldAmount = 120 ether; // Only enough for one request
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Verify one fulfilled, one pending
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);

		// --- Now increase the exchange rate while requests are in the queue ---
		// Add more AVAX to the contract as WAVAX to support the exchange rate increase
		vm.deal(address(ggAVAX), 1000 ether);
		vm.prank(address(ggAVAX));
		wavax.deposit{value: 1000 ether}();

		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(400 ether);
		vm.deal(address(minipoolMgr), 500 ether);
		vm.prank(address(minipoolMgr));
		ggAVAX.depositFromStaking{value: 500 ether}(400 ether, 100 ether);

		// Wait for rewards cycle to end, then sync
		vm.warp(block.timestamp + 14 days + 1);
		ggAVAX.syncRewards();
		// --- END exchange rate increase ---

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Should be 2 expired requests (1 fulfilled, 1 pending)
		assertEq(withdrawQueue.getExpiredRequestsCount(), 2);

		// Reclaim expired funds (should handle both types)
		(uint256 reclaimedAmount, uint256 processedCount) = withdrawQueue.reclaimExpiredFunds(10);

		// Verify both requests were processed
		assertEq(processedCount, 2);
		assertGt(reclaimedAmount, 0);

		// Verify both requests are cleaned up
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), false);
		assertEq(withdrawQueue.isRequestPending(requestId2), false);
		assertEq(withdrawQueue.getRequestInfo(requestId1).requester, address(0));
		assertEq(withdrawQueue.getRequestInfo(requestId2).requester, address(0));

		// Verify users received shares back
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		uint256 bobSharesAfter = ggAVAX.balanceOf(bob);

		// Alice had fulfilled request - gets shares from depositing allocated AVAX (at new, higher rate)
		// She should have less shares than she started with
		assertLt(aliceSharesAfter, aliceSharesBefore);

		// Bob had pending request - gets his unstaked shares back (regardless of exchange rate)
		// So his final balance should be his original balance
		assertEq(bobSharesAfter, bobSharesBefore);

		// No more expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);
		assertEq(withdrawQueue.canClaimRequest(requestId1), false);
		assertEq(withdrawQueue.canClaimRequest(requestId2), false);
	}

	function testReclaimExpiredFundsBeforeExpiration() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Time hasn't passed expiration period yet
		vm.warp(block.timestamp + UNSTAKE_DELAY); // Only past claimable time, not expiration

		// Should be no expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);

		// Reclaim should process 0 requests
		(uint256 reclaimedAmount, uint256 processedCount) = withdrawQueue.reclaimExpiredFunds(10);
		assertEq(processedCount, 0);
		assertEq(reclaimedAmount, 0);

		// Request should still be claimable
		assertEq(withdrawQueue.canClaimRequest(requestId), true);
	}

	function testGetExpiredRequestsCountWithPendingRequests() public {
		// Setup initial ggAVAX deposits
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain liquidity so some requests stay pending
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		uint256 shares1 = 100 ether;
		uint256 shares2 = 150 ether;

		// Create requests - one will be fulfilled, one will stay pending
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Fulfill only one request with yield
		uint256 yieldAmount = 120 ether; // Only enough for one request
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Verify one fulfilled, one pending
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);

		// Initially no expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Should count both expired requests (1 fulfilled, 1 pending)
		assertEq(withdrawQueue.getExpiredRequestsCount(), 2);

		// Process one expired request
		withdrawQueue.reclaimExpiredRequest(requestId1);

		// Should now count only 1 expired request (the remaining pending one)
		assertEq(withdrawQueue.getExpiredRequestsCount(), 1);

		// Process the remaining expired request
		withdrawQueue.reclaimExpiredRequest(requestId2);

		// Should now count 0 expired requests
		assertEq(withdrawQueue.getExpiredRequestsCount(), 0);
	}

	function testReclaimExpiredPendingRequestOriginalShares() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain liquidity so request stays pending
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		uint256 sharesToUnstake = 100 ether;

		// Create request that won't be fulfilled
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Simulate exchange rate improvement (more assets per share)
		// This can happen through yield accumulation in ggAVAX
		vm.deal(address(ggAVAX), address(ggAVAX).balance + 200 ether);

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Get expected values
		uint256 expectedAssets = withdrawQueue.getRequestInfo(requestId).expectedAssets;
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);

		// Reclaim expired pending request
		uint256 reclaimedAmount = withdrawQueue.reclaimExpiredRequest(requestId);

		// Verify reclaim results
		assertEq(reclaimedAmount, expectedAssets);
		assertEq(withdrawQueue.isRequestPending(requestId), false);

		// Verify alice received original shares back (regardless of exchange rate)
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		assertEq(aliceSharesAfter, aliceSharesBefore + sharesToUnstake);
	}

	function testReclaimExpiredPendingRequestEvents() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain liquidity so request stays pending
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		uint256 sharesToUnstake = 100 ether;

		// Create request that won't be fulfilled
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Get expected values
		uint256 expectedAssets = withdrawQueue.getRequestInfo(requestId).expectedAssets;

		// Expect ExpiredFundsReclaimed event
		vm.expectEmit(true, false, false, true);
		emit ExpiredFundsReclaimed(requestId, expectedAssets);

		// Expect ExpiredSharesReturned event with original shares amount
		vm.expectEmit(true, true, false, true);
		emit ExpiredSharesReturned(requestId, alice, sharesToUnstake);

		// Reclaim expired pending request
		withdrawQueue.reclaimExpiredRequest(requestId);
	}

	function testReclaimExpiredRequestInvalidState() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and immediately claim request
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Fast forward past claimable time
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Claim the request
		vm.prank(alice);
		withdrawQueue.claimUnstake(requestId);

		// Fast forward past expiration time
		vm.warp(block.timestamp + EXPIRATION_DELAY + 1);

		// Should revert when trying to reclaim already claimed request
		vm.expectRevert(WithdrawQueue.RequestNotFulfilledOrPending.selector);
		withdrawQueue.reclaimExpiredRequest(requestId);
	}

	function testCannotClaimAfterReclaim() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Reclaim expired funds
		withdrawQueue.reclaimExpiredFunds(10);

		// User should no longer be able to claim
		vm.startPrank(alice);
		vm.expectRevert(WithdrawQueue.RequestNotFound.selector);
		withdrawQueue.claimUnstake(requestId);
		vm.stopPrank();
	}

	function testCannotClaimAfterExpiration() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Fast forward past expiration time but don't reclaim yet
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// User should not be able to claim expired request
		vm.startPrank(alice);
		vm.expectRevert(WithdrawQueue.RequestExpired.selector);
		withdrawQueue.claimUnstake(requestId);
		vm.stopPrank();
	}

	function testEnumerableSetHelperFunctions() public {
		// Setup initial ggAVAX deposits and drain liquidity to ensure requests stay pending
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain all liquidity by withdrawing for delegation
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Initially no pending requests
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.getAllPendingRequests().length, 0);

		// Create first request
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId1 = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Should have 1 pending request
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);
		assertEq(withdrawQueue.isRequestPending(requestId1), true);

		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		assertEq(pendingRequests.length, 1);
		assertEq(pendingRequests[0], requestId1);

		// Create second request
		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), 150 ether);
		uint256 requestId2 = withdrawQueue.requestUnstake(150 ether);
		vm.stopPrank();

		// Should have 2 pending requests
		assertEq(withdrawQueue.getPendingRequestsCount(), 2);
		assertEq(withdrawQueue.isRequestPending(requestId1), true);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);

		pendingRequests = withdrawQueue.getAllPendingRequests();
		assertEq(pendingRequests.length, 2);
		// Note: EnumerableSet doesn't guarantee order, so we check both requests are present
		assertTrue(
			(pendingRequests[0] == requestId1 && pendingRequests[1] == requestId2) || (pendingRequests[0] == requestId2 && pendingRequests[1] == requestId1)
		);

		// Fulfill first request with MEV
		vm.deal(charlie, 120 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 120 ether}(0, 120 ether, bytes32("TEST_YIELD"));

		// First request should no longer be pending
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);
		assertEq(withdrawQueue.isRequestPending(requestId1), false);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);

		pendingRequests = withdrawQueue.getAllPendingRequests();
		assertEq(pendingRequests.length, 1);
		assertEq(pendingRequests[0], requestId2);

		// Fulfill second request
		vm.deal(charlie, 160 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 160 ether}(0, 160 ether, bytes32("TEST_YIELD"));

		// No pending requests should remain
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.isRequestPending(requestId1), false);
		assertEq(withdrawQueue.isRequestPending(requestId2), false);
		assertEq(withdrawQueue.getAllPendingRequests().length, 0);
	}

	function testDualSetLifecycleAndCleanup() public {
		// Setup initial ggAVAX deposit
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Create request - should be in pending set
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Verify initial state: pending set has request, fulfilled set is empty
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);
		assertEq(withdrawQueue.getFulfilledRequestsCount(), 0);
		assertEq(withdrawQueue.isRequestPending(requestId), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);

		// Fulfill request with MEV - should move from pending to fulfilled
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		// Verify after fulfillment: pending set empty, fulfilled set has request
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.getFulfilledRequestsCount(), 1);
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), true);

		// Fast forward past delay
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Check that user can see their fulfilled request
		uint256[] memory fulfilledRequests = withdrawQueue.getAllFulfilledRequests();
		assertEq(fulfilledRequests.length, 1);
		assertEq(fulfilledRequests[0], requestId);

		// Check request info exists
		assertTrue(withdrawQueue.getRequestInfo(requestId).requester == alice);

		// Claim request - should be removed from fulfilled set and deleted entirely
		vm.prank(alice);
		withdrawQueue.claimUnstake(requestId);

		// Verify complete cleanup: both sets empty, request deleted
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.getFulfilledRequestsCount(), 0);
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);
		assertEq(withdrawQueue.getAllFulfilledRequests().length, 0);

		// Verify request struct is deleted (requester should be zero address)
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));

		// Verify user's request history was cleaned up
		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(alice);
		assertEq(userRequests.length, 0);
	}

	function testCancelPendingRequestSameExchangeRate() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);

		// Create request
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Verify request is pending
		assertEq(withdrawQueue.isRequestPending(requestId), true);
		assertEq(withdrawQueue.getPendingRequestsCount(), 1);

		// Cancel request - exchange rate hasn't changed
		vm.expectEmit(true, true, false, true);
		emit RequestCancelled(requestId, alice, sharesToUnstake);

		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId);

		// Verify user got back same amount of shares (no exchange rate change)
		assertEq(ggAVAX.balanceOf(alice), aliceSharesBefore);

		// Verify request is completely removed
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));

		// Verify user's request history was cleaned up
		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(alice);
		assertEq(userRequests.length, 0);
	}

	function testCancelPendingRequestAfterExchangeRateIncrease() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);

		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(400 ether);

		// Add rewards to increase exchange rate
		vm.deal((address(minipoolMgr)), 500 ether);
		vm.prank(address(minipoolMgr));
		ggAVAX.depositFromStaking{value: 500 ether}(400 ether, 100 ether);

		//time skip
		vm.warp(block.timestamp + 15 days);
		ggAVAX.syncRewards();

		// Create request - expectedAssets will be calculated at current (improved) rate
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Get the expectedAssets from the request (calculated at request time)
		uint256 expectedAssets = withdrawQueue.getRequestInfo(requestId).expectedAssets;

		skip(2 days);

		// Calculate how many shares user will get back based on new rate
		uint256 sharesReturned = ggAVAX.convertToShares(expectedAssets);
		uint256 sharesBurned = sharesToUnstake - sharesReturned;

		// Verify exchange rate has increased (fewer shares needed for same assets)
		assertLt(sharesReturned, sharesToUnstake);

		// Cancel request - user should get fewer shares back
		vm.expectEmit(true, true, false, true);
		emit ExcessSharesBurnt(requestId, sharesBurned);
		vm.expectEmit(true, true, false, true);
		emit RequestCancelled(requestId, alice, sharesReturned);

		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId);

		// Verify user got back fewer shares
		assertEq(ggAVAX.balanceOf(alice), aliceSharesBefore - sharesToUnstake + sharesReturned);

		// Verify request is completely removed
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));
	}

	function testCancelRequestNotYours() public {
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		vm.startPrank(bob);
		vm.expectRevert(WithdrawQueue.NotYourRequest.selector);
		withdrawQueue.cancelRequest(requestId);
		vm.stopPrank();
	}

	function testCancelRequestNotFound() public {
		vm.startPrank(alice);
		vm.expectRevert(WithdrawQueue.RequestNotFound.selector);
		withdrawQueue.cancelRequest(999);
		vm.stopPrank();
	}

	function testCancelFulfilledRequest() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);

		// Create request
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill the request
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		// Verify request is fulfilled
		assertEq(withdrawQueue.isFulfilledRequest(requestId), true);
		uint256 allocatedFunds = withdrawQueue.getRequestInfo(requestId).allocatedFunds;
		uint256 totalAllocatedBefore = withdrawQueue.totalAllocatedFunds();

		// Cancel fulfilled request - should convert AVAX back to stAVAX
		uint256 expectedShares = ggAVAX.previewDeposit(allocatedFunds);

		vm.expectEmit(true, true, false, true);
		emit RequestCancelled(requestId, alice, expectedShares);

		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId);

		// Verify user received stAVAX shares
		assertEq(ggAVAX.balanceOf(alice), aliceSharesBefore - sharesToUnstake + expectedShares);

		// Verify accounting was updated
		assertEq(withdrawQueue.totalAllocatedFunds(), totalAllocatedBefore - allocatedFunds);

		// Verify request is completely removed
		assertEq(withdrawQueue.isFulfilledRequest(requestId), false);
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));
	}

	function testCancelFulfilledRequestAfterExchangeRateChange() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;
		uint256 expectedAssets = ggAVAX.convertToAssets(sharesToUnstake);

		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(400 ether);

		// Add rewards to increase exchange rate
		vm.deal((address(minipoolMgr)), 500 ether);
		vm.prank(address(minipoolMgr));
		ggAVAX.depositFromStaking{value: 500 ether}(400 ether, 100 ether);

		//time skip
		vm.warp(block.timestamp + 15 days);
		ggAVAX.syncRewards();

		// Create request
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill the request
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		skip(2 days);

		// Cancel fulfilled request
		// User will get shares based on current rate when depositing allocated AVAX
		uint256 allocatedFunds = withdrawQueue.getRequestInfo(requestId).allocatedFunds;
		uint256 expectedSharesReturned = ggAVAX.previewDeposit(allocatedFunds);

		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId);

		// User may get fewer shares than originally deposited due to rate change
		assertLt(expectedSharesReturned, sharesToUnstake);
	}

	function testReclaimExpiredRequestNotExpired() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		uint256 sharesToUnstake = 100 ether;

		// Create and fulfill request with yield
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Fulfill with yield
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Time hasn't passed expiration period yet
		vm.warp(block.timestamp + UNSTAKE_DELAY); // Only past claimable time, not expiration

		// Should revert when trying to reclaim non-expired request
		vm.expectRevert(WithdrawQueue.RequestNotExpired.selector);
		withdrawQueue.reclaimExpiredRequest(requestId);
	}

	function testReclaimExpiredRequestNotFound() public {
		vm.expectRevert(WithdrawQueue.RequestNotFound.selector);
		withdrawQueue.reclaimExpiredRequest(999);
	}

	function testReclaimExpiredRequestPending() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Drain liquidity so request stays pending
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		uint256 sharesToUnstake = 100 ether;

		// Create request that won't be fulfilled
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), sharesToUnstake);
		uint256 requestId = withdrawQueue.requestUnstake(sharesToUnstake);
		vm.stopPrank();

		// Verify request is still pending
		assertEq(withdrawQueue.isRequestPending(requestId), true);

		// Fast forward past expiration time
		vm.warp(block.timestamp + UNSTAKE_DELAY + EXPIRATION_DELAY + 1);

		// Get alice's balance before reclaim
		uint256 aliceSharesBefore = ggAVAX.balanceOf(alice);
		uint256 expectedAssets = withdrawQueue.getRequestInfo(requestId).expectedAssets;

		// Should now successfully reclaim expired pending request
		uint256 reclaimedAmount = withdrawQueue.reclaimExpiredRequest(requestId);

		// Verify reclaim results
		assertEq(reclaimedAmount, expectedAssets);
		assertEq(withdrawQueue.isRequestPending(requestId), false);
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));

		// Verify alice received original shares back (NEW LOGIC)
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		assertEq(aliceSharesAfter, aliceSharesBefore + sharesToUnstake);
	}

	function testAvailableAVAXCalculation() public {
		// This test verifies the new available AVAX calculation:
		// availableAVAX = (contract.balance - totalAllocatedFunds) + (ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets())

		// Setup initial deposits
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Withdraw some funds for delegation (simulating staking)
		uint256 stakingAmount = 800 ether;
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(stakingAmount, randAddress());

		// Now ggAVAX should have 1200 ether liquid (2000 - 800)
		uint256 ggAVAXLiquidity = ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets();
		assertEq(ggAVAXLiquidity, 1200 ether);

		// Create a request from alice
		uint256 shares1 = 500 ether;
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		vm.stopPrank();

		// Add some yield to the queue
		uint256 yieldAmount = 300 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// Check available AVAX calculation:
		// Contract balance: 300 ether (yield)
		// Total allocated: 0 (no fulfilled requests yet)
		// ggAVAX liquidity: 1200 ether
		// Available AVAX = 300 + 1200 = 1500 ether
		// This should be enough to fulfill the 500 ether request

		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);

		// Create another request that exceeds available AVAX
		uint256 shares2 = 1000 ether;
		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), shares2);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// This request should remain pending because:
		// Contract balance: ~0 (used for first request)
		// Total allocated: 500 ether (first request)
		// ggAVAX liquidity: ~500 ether (1000 - 500 from first redemption)
		// Available AVAX = 0 + 500 = 500 ether < 1000 ether needed

		assertEq(withdrawQueue.isRequestPending(requestId2), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestId2), false);
	}

	function testDepositExactAmountForNextRequest() public {
		// Test that depositFromStaking deposits exact amount needed for next request

		// Setup and drain liquidity
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();
		vm.stopPrank();

		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());
		assertEq(ggAVAX.totalAssets(), ggAVAX.stakingTotalAssets());

		// Create multiple requests
		uint256 shares1 = 100 ether;
		uint256 shares2 = 200 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), shares1 + shares2);
		uint256 requestId1 = withdrawQueue.requestUnstake(shares1);
		uint256 requestId2 = withdrawQueue.requestUnstake(shares2);
		vm.stopPrank();

		// Both should be pending
		assertEq(withdrawQueue.getPendingRequestsCount(), 2);

		// Check ggAVAX WAVAX balance before
		uint256 ggAVAXWAVAXBefore = ggAVAX.asset().balanceOf(address(ggAVAX));

		// Deposit enough yield for first request plus some extra
		uint256 yieldAmount = 150 ether;
		vm.deal(charlie, yieldAmount);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: yieldAmount}(0, yieldAmount, bytes32("TEST_YIELD"));

		// First request should be fulfilled
		assertEq(withdrawQueue.isFulfilledRequest(requestId1), true);
		assertEq(withdrawQueue.isRequestPending(requestId2), true);

		// ggAVAX should have received exactly the amount needed for first request
		// The rest stays in the queue for the next request
		assertEq(ggAVAX.asset().balanceOf(address(ggAVAX)), ggAVAXWAVAXBefore);
		assertEq(address(withdrawQueue).balance, yieldAmount - shares1 + withdrawQueue.totalAllocatedFunds());
	}

	function testCancelRequestsBatch() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();
		vm.stopPrank();

		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(2000 ether);

		// Create multiple requests (some will be pending, some fulfilled)
		uint256[] memory requestIds = new uint256[](4);
		uint256[] memory shares = new uint256[](4);
		shares[0] = 100 ether;
		shares[1] = 150 ether;
		shares[2] = 200 ether;
		shares[3] = 250 ether;

		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 700 ether);
		for (uint i = 0; i < 4; i++) {
			requestIds[i] = withdrawQueue.requestUnstake(shares[i]);
		}
		vm.stopPrank();

		// Fulfill first two requests
		vm.deal(charlie, 300 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 300 ether}(0, 300 ether, bytes32("TEST_YIELD"));

		// Verify state: first 2 fulfilled, last 2 pending
		assertEq(withdrawQueue.isFulfilledRequest(requestIds[0]), true);
		assertEq(withdrawQueue.isFulfilledRequest(requestIds[1]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[2]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[3]), true);

		// Calculate expected shares and verify accounting
		uint256 totalExpectedShares;
		uint256 totalAllocatedToReturn;
		{
			// Scope to reduce stack depth
			uint256 allocatedFunds0 = withdrawQueue.getRequestInfo(requestIds[0]).allocatedFunds;
			uint256 allocatedFunds1 = withdrawQueue.getRequestInfo(requestIds[1]).allocatedFunds;
			totalAllocatedToReturn = allocatedFunds0 + allocatedFunds1;

			uint256 expectedShares0 = ggAVAX.previewDeposit(allocatedFunds0);
			uint256 expectedShares1 = ggAVAX.previewDeposit(allocatedFunds1);
			uint256 expectedShares2 = ggAVAX.convertToShares(withdrawQueue.getRequestInfo(requestIds[2]).expectedAssets);
			uint256 expectedShares3 = ggAVAX.convertToShares(withdrawQueue.getRequestInfo(requestIds[3]).expectedAssets);

			totalExpectedShares = expectedShares0 + expectedShares1 + expectedShares2 + expectedShares3;
		}

		// Capture state before cancellation
		uint256 aliceBalanceBeforeCancel = ggAVAX.balanceOf(alice);
		uint256 totalAllocatedBefore = withdrawQueue.totalAllocatedFunds();

		// Cancel all requests with batch function (before claimable time)
		vm.prank(alice);
		uint256 cancelledCount = withdrawQueue.cancelRequests(0);

		// Should have cancelled all 4 requests
		assertEq(cancelledCount, 4);

		// Verify alice received correct shares
		assertEq(ggAVAX.balanceOf(alice), aliceBalanceBeforeCancel + totalExpectedShares);

		// Verify allocated funds were properly returned to protocol
		assertEq(withdrawQueue.totalAllocatedFunds(), totalAllocatedBefore - totalAllocatedToReturn);

		// Verify all requests are removed
		for (uint i = 0; i < 4; i++) {
			assertEq(withdrawQueue.getRequestInfo(requestIds[i]).requester, address(0));
			assertEq(withdrawQueue.isRequestPending(requestIds[i]), false);
			assertEq(withdrawQueue.isFulfilledRequest(requestIds[i]), false);
		}

		// Verify user has no more requests
		assertEq(withdrawQueue.getRequestsByOwner(alice).length, 0);

		// Verify pending and fulfilled queues are empty
		assertEq(withdrawQueue.getPendingRequestsCount(), 0);
		assertEq(withdrawQueue.getFulfilledRequestsCount(), 0);
	}

	function testCancelRequestsWithLimit() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		// Create multiple pending requests
		uint256[] memory requestIds = new uint256[](5);
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 500 ether);
		for (uint i = 0; i < 5; i++) {
			requestIds[i] = withdrawQueue.requestUnstake(100 ether);
		}
		vm.stopPrank();

		// Cancel only 3 requests
		vm.prank(alice);
		uint256 cancelledCount = withdrawQueue.cancelRequests(3);

		// Should have cancelled exactly 3
		assertEq(cancelledCount, 3);

		// User should still have 2 requests
		assertEq(withdrawQueue.getRequestsByOwner(alice).length, 2);
	}

	function testCancelNonExistentRequest() public {
		vm.prank(alice);
		vm.expectRevert(WithdrawQueue.RequestNotFound.selector);
		withdrawQueue.cancelRequest(999);
	}

	function testCancelAfterClaim() public {
		// Setup and create request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Fulfill request
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		// Fast forward and claim
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);
		vm.prank(alice);
		withdrawQueue.claimUnstake(requestId);

		// Try to cancel after claim
		vm.prank(alice);
		vm.expectRevert(WithdrawQueue.RequestNotFound.selector);
		withdrawQueue.cancelRequest(requestId);
	}

	function testCannotCancelAfterClaimable() public {
		// Setup and create request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Fulfill request
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		// Fast forward past claimable time
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Should not be able to cancel after claimable time
		vm.prank(alice);
		vm.expectRevert(WithdrawQueue.TooLateToCancelRequest.selector);
		withdrawQueue.cancelRequest(requestId);

		// Verify request is still there and claimable
		assertEq(withdrawQueue.canClaimRequest(requestId), true);
	}

	function testCancelFulfilledBeforeClaimable() public {
		// Setup and create request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Fulfill request
		vm.deal(charlie, 150 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 150 ether}(0, 150 ether, bytes32("TEST_YIELD"));

		// Verify request is fulfilled but not yet claimable
		assertEq(withdrawQueue.isFulfilledRequest(requestId), true);
		assertEq(withdrawQueue.canClaimRequest(requestId), false);

		// Should be able to cancel before claimable time
		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId);

		// Verify request is removed
		assertEq(withdrawQueue.getRequestInfo(requestId).requester, address(0));
	}

	function testMultipleCancellationsWithRateChanges() public {
		// Setup
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.depositAVAX{value: 1000 ether}();
		vm.stopPrank();

		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(400 ether);

		// Add rewards to increase exchange rate
		vm.deal((address(minipoolMgr)), 400 ether);
		vm.prank(address(minipoolMgr));
		ggAVAX.depositFromStaking{value: 400 ether}(300 ether, 100 ether);

		//time skip
		vm.warp(block.timestamp + 15 days);
		ggAVAX.syncRewards();

		// Create requests
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId1 = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		vm.startPrank(bob);
		ggAVAX.approve(address(withdrawQueue), 100 ether);
		uint256 requestId2 = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		skip(2 days);

		// Both users cancel - should get fewer shares back
		uint256 aliceBalanceBefore = ggAVAX.balanceOf(alice);
		uint256 bobBalanceBefore = ggAVAX.balanceOf(bob);

		vm.prank(alice);
		withdrawQueue.cancelRequest(requestId1);

		vm.prank(bob);
		withdrawQueue.cancelRequest(requestId2);

		// Both should have received less than 100 ether in shares
		uint256 aliceReceived = ggAVAX.balanceOf(alice) - aliceBalanceBefore;
		uint256 bobReceived = ggAVAX.balanceOf(bob) - bobBalanceBefore;

		assertLt(aliceReceived, 100 ether);
		assertLt(bobReceived, 100 ether);
	}

	function testBatchCancelWithSomeClaimableRequests() public {
		// Setup initial ggAVAX deposit for alice
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 500 ether}();
		vm.stopPrank();

		// Create multiple requests
		uint256[] memory requestIds = new uint256[](3);
		vm.startPrank(alice);
		ggAVAX.approve(address(withdrawQueue), 300 ether);
		requestIds[0] = withdrawQueue.requestUnstake(100 ether);
		requestIds[1] = withdrawQueue.requestUnstake(100 ether);
		requestIds[2] = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Drain ALL liquidity by withdrawing for delegation
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Provide only enough yield to fulfill first request
		// This ensures the third request definitely stays pending
		vm.deal(charlie, 100 ether);
		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: 100 ether}(0, 100 ether, bytes32("TEST_YIELD"));

		// Verify first is fulfilled, second and third are pending
		assertEq(withdrawQueue.isFulfilledRequest(requestIds[0]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[1]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[2]), true);

		// Fast forward past claimable time for fulfilled requests
		vm.warp(block.timestamp + UNSTAKE_DELAY + 1);

		// Try to cancel all requests - should revert because first one is claimable
		vm.prank(alice);
		vm.expectRevert(WithdrawQueue.TooLateToCancelRequest.selector);
		withdrawQueue.cancelRequests(0);

		// Verify that none of the requests were cancelled
		assertEq(withdrawQueue.canClaimRequest(requestIds[0]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[1]), true);
		assertEq(withdrawQueue.isRequestPending(requestIds[2]), true);
	}

	function testReentrancyProtectionOnCancelRequest() public {
		// Setup: Create a malicious ggAVAX contract that attempts reentrancy
		MaliciousGGAVAX maliciousGGAVAX = new MaliciousGGAVAX(address(withdrawQueue));

		// Deploy a new WithdrawQueue with the malicious ggAVAX
		WithdrawQueue maliciousQueue;
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory initData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(maliciousGGAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);

		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(withdrawQueueImpl), address(proxyAdmin), initData);

		maliciousQueue = WithdrawQueue(payable(address(proxy)));
		maliciousGGAVAX.setWithdrawQueue(address(maliciousQueue));

		// Grant DEPOSITOR_ROLE to test contract so it can call depositFromStaking
		vm.prank(guardian);
		maliciousQueue.grantRole(maliciousQueue.DEPOSITOR_ROLE(), address(this));

		// Alice gets some shares in the malicious token
		vm.startPrank(alice);
		deal(address(maliciousGGAVAX), alice, 1000 ether);
		maliciousGGAVAX.approve(address(maliciousQueue), type(uint256).max);

		// Create an unstake request
		uint256 requestId = maliciousQueue.requestUnstake(500 ether);

		// Send AVAX to the queue to fulfill the request
		vm.stopPrank();

		vm.deal(address(maliciousQueue), 1000 ether);
		maliciousQueue.depositFromStaking{value: 1000 ether}(1000 ether, 0, "test");

		// Try to cancel the fulfilled request - the reentrancy attempt will fail but the cancellation will succeed
		vm.startPrank(alice);
		// The malicious contract will attempt reentrancy during depositAVAX, but it will be blocked
		// The cancellation itself should succeed
		maliciousQueue.cancelRequest(requestId);
		vm.stopPrank();

		// Verify the request was successfully cancelled despite the reentrancy attempt
		assertEq(maliciousQueue.getRequestInfo(requestId).requester, address(0));
	}

	function testConfigurableRequestsLimit() public {
		// Test that changing the limit affects batching behavior
		vm.prank(guardian);
		withdrawQueue.setMaxPendingRequestsLimit(10); // Set lower limit

		// Create 15 unstake requests (more than the 10 limit)
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);

		// Create 15 requests of 100 ether each
		for (uint i = 0; i < 15; i++) {
			withdrawQueue.requestUnstake(100 ether);
		}
		vm.stopPrank();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(charlie));
		ggAVAX.withdrawForStaking(1500 ether, bytes32("DELEGATION"));

		// First call - should fulfill exactly 10 requests (the new limit)
		uint256 baseAmt = 1000 ether;
		uint256 rewardAmt = 500 ether;
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.prank(charlie);
		withdrawQueue.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));

		// Check that exactly 10 requests were fulfilled
		uint256 pendingAfterFirst = withdrawQueue.getPendingRequestsCount();
		uint256 fulfilledAfterFirst = withdrawQueue.getFulfilledRequestsCount();

		assertEq(pendingAfterFirst, 5); // 15 - 10 = 5 remaining
		assertEq(fulfilledAfterFirst, 10); // 10 fulfilled

		console2.log("WithdrawQueue.depositFromStaking (fulfilling 10 of 15 requests with limit=10) - Pending remaining:", pendingAfterFirst);
		console2.log("WithdrawQueue.depositFromStaking (fulfilling 10 of 15 requests with limit=10) - Fulfilled:", fulfilledAfterFirst);
	}

	function testDepositFromStakingMaxRequestsLimit() public {
		// Create 30 unstake requests (more than the 25 limit set in setUp)
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 6000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);

		// Create 30 requests of 100 ether each
		for (uint i = 0; i < 30; i++) {
			withdrawQueue.requestUnstake(100 ether);
		}
		vm.stopPrank();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(charlie));
		ggAVAX.withdrawForStaking(4000 ether, bytes32("DELEGATION"));

		// Check initial state
		uint256 initialPending = withdrawQueue.getPendingRequestsCount();
		assertEq(initialPending, 30);

		// deposit enough to fulfill all requests
		uint256 baseAmt = 4000 ether;
		uint256 rewardAmt = 1000 ether;
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.startPrank(charlie);
		uint256 gasStart = gasleft();
		withdrawQueue.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));
		uint256 gasUsed = gasStart - gasleft();
		vm.stopPrank();

		// Check that exactly 25 requests were fulfilled
		uint256 pendingAfterFirst = withdrawQueue.getPendingRequestsCount();
		uint256 fulfilledAfterFirst = withdrawQueue.getFulfilledRequestsCount();

		assertEq(pendingAfterFirst, 5); // 30 - 25 = 5 remaining
		assertEq(fulfilledAfterFirst, 25); // 25 fulfilled

		console2.log("WithdrawQueue.depositFromStaking (fulfilling 25 of 30 requests) gas:", gasUsed);

		// Second call - should fulfill the remaining 5 requests

		vm.startPrank(charlie);
		uint256 gasStart2 = gasleft();
		withdrawQueue.depositFromStaking{value: 0}(0, 0, bytes32("DELEGATION"));
		uint256 gasUsed2 = gasStart2 - gasleft();
		vm.stopPrank();

		// Check that all requests are now fulfilled
		uint256 pendingAfterSecond = withdrawQueue.getPendingRequestsCount();
		uint256 fulfilledAfterSecond = withdrawQueue.getFulfilledRequestsCount();

		assertEq(pendingAfterSecond, 0); // All requests processed
		assertEq(fulfilledAfterSecond, 30); // All 30 requests fulfilled

		console2.log("WithdrawQueue.depositFromStaking (fulfilling remaining 5 requests) gas:", gasUsed2);
	}
}

// Malicious contract that attempts reentrancy
contract MaliciousGGAVAX {
	address public withdrawQueue;
	mapping(address => uint256) public balanceOf;
	mapping(address => mapping(address => uint256)) public allowance;

	constructor(address _withdrawQueue) {
		withdrawQueue = _withdrawQueue;
	}

	function setWithdrawQueue(address _withdrawQueue) external {
		withdrawQueue = _withdrawQueue;
	}

	function approve(address spender, uint256 amount) external returns (bool) {
		allowance[msg.sender][spender] = amount;
		return true;
	}

	function convertToShares(uint256) external pure returns (uint256) {
		return 500 ether;
	}

	function convertToAssets(uint256) external pure returns (uint256) {
		return 500 ether;
	}

	function transfer(address to, uint256 amount) external returns (bool) {
		balanceOf[msg.sender] -= amount;
		balanceOf[to] += amount;
		return true;
	}

	function transferFrom(address from, address to, uint256 amount) external returns (bool) {
		require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
		allowance[from][msg.sender] -= amount;
		balanceOf[from] -= amount;
		balanceOf[to] += amount;
		return true;
	}

	function donateYield(uint256, string memory) external {
		// No-op for test
	}

	function stakingTotalAssets() external pure returns (uint256) {
		return 0;
	}

	function totalAssets() external pure returns (uint256) {
		return 1000 ether;
	}

	function redeemAVAX(uint256) external pure returns (uint256) {
		return 500 ether;
	}

	function depositFromStaking(uint256, uint256, bytes32) external payable {
		// No-op for test
	}

	function depositYield(bytes32) external payable {
		// No-op for test
	}

	// This function attempts reentrancy when receiving AVAX
	function depositAVAX() external payable returns (uint256) {
		// Attempt to re-enter cancelRequest
		if (withdrawQueue != address(0)) {
			try WithdrawQueue(payable(withdrawQueue)).cancelRequest(0) {
				// If this succeeds, the reentrancy protection failed
			} catch {
				// Expected behavior - reentrancy should be blocked
			}
		}
		return msg.value;
	}
}
