// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {console2} from "forge-std/console2.sol";

contract WithdrawQueueGasTests is BaseTest {
	using FixedPointMathLib for uint256;

	WithdrawQueue private withdrawQueue;
	address private alice;
	address private bob;
	address private backgroundJob;

	uint48 private constant UNSTAKE_DELAY = 7 days;
	uint48 private constant EXPIRATION_DELAY = 14 days;

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);
		backgroundJob = getActorWithTokens("backgroundJob", MAX_AMT, MAX_AMT);

		// Give backgroundJob some tokens
		vm.deal(backgroundJob, MAX_AMT);
		deal(address(ggp), backgroundJob, MAX_AMT);

		// Deploy WithdrawQueue
		vm.startPrank(guardian);
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory initData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);
		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(withdrawQueueImpl), address(proxyAdmin), initData);
		withdrawQueue = WithdrawQueue(payable(address(proxy)));

		// Grant roles
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), backgroundJob);
		withdrawQueue.grantRole(withdrawQueue.DEPOSITOR_ROLE(), backgroundJob);

		// Set max pending requests limit to 25 for testing
		withdrawQueue.setMaxPendingRequestsLimit(25);

		// Set reserve ratio to 0% for testing
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		vm.stopPrank();
	}

	// ==================== depositFromStaking Gas Tests ====================

	function testGas_DepositFromStaking_Staker_NoFee() public {
		// Setup: Set fee to 0
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 0);

		// First withdraw some assets for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		// Deposit some liquid staker funds first
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();

		// Withdraw for delegation
		vm.prank(backgroundJob);
		ggAVAX.withdrawForStaking(1000 ether, bytes32("DELEGATION"));

		// Test depositFromStaking gas usage
		uint256 baseAmt = 1000 ether;
		uint256 rewardAmt = 10 ether;
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.prank(backgroundJob);
		uint256 gasStart = gasleft();
		ggAVAX.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));
		uint256 gasUsed = gasStart - gasleft();

		console2.log("depositFromStaking (Staker role, 0% fee) gas:", gasUsed);
	}

	function testGas_DepositFromStaking_Staker_WithFee() public {
		// Setup: Set fee to 10%
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 1000);

		// First withdraw some assets for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		// Deposit some liquid staker funds first
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();

		// Withdraw for staking as a staker
		vm.prank(backgroundJob);
		ggAVAX.withdrawForStaking(1000 ether, bytes32("DELEGATION"));

		// Test depositFromStaking gas usage
		uint256 baseAmt = 1000 ether;
		uint256 rewardAmt = 10 ether;
		uint256 feeAmt = rewardAmt.mulDivDown(1000, 10000);
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.prank(backgroundJob);
		uint256 gasStart = gasleft();
		ggAVAX.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));
		uint256 gasUsed = gasStart - gasleft();

		console2.log("depositFromStaking (Staker role, 10% fee) gas:", gasUsed);
	}

	// ==================== WithdrawQueue depositFromStaking Gas Tests ====================

	function testGas_WithdrawQueue_DepositFromStaking_NoRequests() public {
		// First set up some staking assets by having WithdrawQueue withdraw for staking
		vm.prank(alice);
		ggAVAX.depositAVAX{value: 2000 ether}();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(backgroundJob));
		ggAVAX.withdrawForStaking(1000 ether, bytes32("DELEGATION"));

		// Now test depositFromStaking
		uint256 baseAmt = 1000 ether;
		uint256 rewardAmt = 100 ether;
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.prank(backgroundJob);
		uint256 gasStart = gasleft();
		withdrawQueue.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));
		uint256 gasUsed = gasStart - gasleft();

		console2.log("WithdrawQueue.depositFromStaking (no pending requests) gas:", gasUsed);
	}

	function testGas_WithdrawQueue_DepositFromStaking_WithRequests() public {
		// Create some unstake requests first
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 3000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);

		// Create multiple requests
		for (uint i = 0; i < 5; i++) {
			withdrawQueue.requestUnstake(100 ether);
		}
		vm.stopPrank();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(backgroundJob));
		ggAVAX.withdrawForStaking(500 ether, bytes32("DELEGATION"));

		// Now deposit from staking to fulfill requests
		uint256 baseAmt = 500 ether;
		uint256 rewardAmt = 50 ether;
		uint256 totalAmt = baseAmt + rewardAmt;

		vm.prank(backgroundJob);
		uint256 gasStart = gasleft();
		withdrawQueue.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, bytes32("DELEGATION"));
		uint256 gasUsed = gasStart - gasleft();

		console2.log("WithdrawQueue.depositFromStaking (fulfilling 5 requests) gas:", gasUsed);
	}

	// ==================== cancelRequest Gas Tests ====================

	function testGas_CancelRequest_Pending() public {
		// Create an unstake request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Cancel the pending request
		vm.prank(alice);
		uint256 gasStart = gasleft();
		withdrawQueue.cancelRequest(requestId);
		uint256 gasUsed = gasStart - gasleft();

		console2.log("cancelRequest (pending request) gas:", gasUsed);
	}

	function testGas_CancelRequest_Fulfilled() public {
		// Create an unstake request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(backgroundJob));
		ggAVAX.withdrawForStaking(100 ether, bytes32("DELEGATION"));

		// Fulfill the request
		vm.prank(backgroundJob);
		withdrawQueue.depositFromStaking{value: 110 ether}(100 ether, 10 ether, bytes32("DELEGATION"));

		// Cancel the fulfilled request
		vm.prank(alice);
		uint256 gasStart = gasleft();
		withdrawQueue.cancelRequest(requestId);
		uint256 gasUsed = gasStart - gasleft();

		console2.log("cancelRequest (fulfilled request) gas:", gasUsed);
	}

	function testGas_CancelRequests_Multiple() public {
		// Create multiple unstake requests
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);

		uint256[] memory requestIds = new uint256[](10);
		for (uint i = 0; i < 10; i++) {
			requestIds[i] = withdrawQueue.requestUnstake(50 ether);
		}
		vm.stopPrank();

		// Grant STAKER_ROLE to WithdrawQueue and withdraw for staking
		vm.prank(guardian);
		dao.setWithdrawForDelegationEnabled(true);

		vm.prank(address(backgroundJob));
		ggAVAX.withdrawForStaking(250 ether, bytes32("DELEGATION"));

		// Fulfill half of them
		vm.prank(backgroundJob);
		withdrawQueue.depositFromStaking{value: 275 ether}(250 ether, 25 ether, bytes32("DELEGATION"));

		// Cancel all requests (both pending and fulfilled)
		vm.prank(alice);
		uint256 gasStart = gasleft();
		uint256 cancelled = withdrawQueue.cancelRequests(0); // 0 means cancel all
		uint256 gasUsed = gasStart - gasleft();

		console2.log("cancelRequests (10 requests, 5 fulfilled) gas:", gasUsed);
		console2.log("Requests cancelled:", cancelled);
	}

	function testGas_CancelRequest_AfterExchangeRateChange() public {
		// Create an unstake request
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: 1000 ether}();
		ggAVAX.approve(address(withdrawQueue), type(uint256).max);
		uint256 requestId = withdrawQueue.requestUnstake(100 ether);
		vm.stopPrank();

		// Simulate exchange rate increase by depositing yield
		vm.prank(bob);
		ggAVAX.depositYield{value: 10 ether}(bytes32("YIELD"));

		// Sync rewards to update exchange rate
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		// Cancel the request after exchange rate change
		vm.prank(alice);
		uint256 gasStart = gasleft();
		withdrawQueue.cancelRequest(requestId);
		uint256 gasUsed = gasStart - gasleft();

		console2.log("cancelRequest (after exchange rate change) gas:", gasUsed);
	}
}
