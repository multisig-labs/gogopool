// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

contract AVAXStateVariableTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testDifferentAVAXAssignment() public {
		// Create minipool with 1000 AVAX
		// Complete cycle and withdraw funds
		// Create another minipool under same owner with 1500 AVAX

		uint256 initialDepositAmt = 1000 ether;
		uint256 initialAssignmentRequest = 1000 ether;
		uint256 duration = 2 weeks;
		uint256 ggpStakeAmt = 1000 ether;
		uint256 liquidStakingAmt = 2000 ether;

		address nodeOp = getActorWithTokens("nodeOp", 3500 ether, 1000 ether);

		vm.startPrank(nodeOp);
		ggAVAX.depositAVAX{value: liquidStakingAmt}();

		// create first minipool
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);

		MinipoolManager.Minipool memory mp = createMinipool(initialDepositAmt, initialAssignmentRequest, duration);
		vm.stopPrank();

		assertEq(staking.getAVAXAssigned(nodeOp), initialAssignmentRequest);
		assertEq(staking.getAVAXValidating(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), 0 ether);

		// launch minipool
		rialto.processMinipoolStart(mp.nodeID);

		assertEq(staking.getAVAXAssigned(nodeOp), initialAssignmentRequest);
		assertEq(staking.getAVAXValidating(nodeOp), initialAssignmentRequest);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), initialAssignmentRequest);

		skip(duration);

		// end minipool
		rialto.processMinipoolEndWithRewards(mp.nodeID);

		assertEq(staking.getAVAXAssigned(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidating(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), initialAssignmentRequest);

		// withdraw funds
		vm.prank(nodeOp);
		minipoolMgr.withdrawMinipoolFunds(mp.nodeID);

		assertEq(staking.getAVAXAssigned(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidating(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), initialAssignmentRequest);

		uint256 secondDepositAmt = 1500 ether;
		uint256 secondAssignmentRequest = 1500 ether;

		// create second minipool
		vm.prank(nodeOp);
		MinipoolManager.Minipool memory mp2 = createMinipool(secondDepositAmt, secondAssignmentRequest, duration);

		assertEq(staking.getAVAXAssigned(nodeOp), secondAssignmentRequest);
		assertEq(staking.getAVAXValidating(nodeOp), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), initialAssignmentRequest);

		// launch minipool
		rialto.processMinipoolStart(mp2.nodeID);

		assertEq(staking.getAVAXAssigned(nodeOp), secondAssignmentRequest);
		assertEq(staking.getAVAXValidating(nodeOp), secondAssignmentRequest);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), secondAssignmentRequest);
	}

	function testMultipleMinipools() public {
		// node op creates three 1k avax minipools
		// launch all three minipools

		uint256 depositAmt = 1000 ether;
		uint256 assignmentRequest = 1000 ether;
		uint256 duration = 2 weeks;
		uint256 ggpStakeAmt = 1000 ether;
		uint256 liquidStakingAmt = 3334 ether;

		address nodeOp = getActorWithTokens("nodeOp", 6334 ether, 1000 ether);

		// deposit liquid staking funds
		vm.startPrank(nodeOp);
		ggAVAX.depositAVAX{value: liquidStakingAmt}();

		// stake ggp
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);

		// create minipools
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, assignmentRequest, duration);
		MinipoolManager.Minipool memory mp2 = createMinipool(depositAmt, assignmentRequest, duration);
		MinipoolManager.Minipool memory mp3 = createMinipool(depositAmt, assignmentRequest, duration);
		vm.stopPrank();

		// launch minipools
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp1.nodeID);
		rialto.processMinipoolStart(mp2.nodeID);
		rialto.processMinipoolStart(mp3.nodeID);
		vm.stopPrank();

		// highwater should be 3k
		assertEq(staking.getAVAXAssigned(nodeOp), 3000 ether);
		assertEq(staking.getAVAXValidating(nodeOp), 3000 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), 3000 ether);
	}

	function testQueuedMinipools() public {
		// node op created three 1k avax minipools
		// launch just one minipool

		uint256 depositAmt = 1000 ether;
		uint256 assignmentRequest = 1000 ether;
		uint256 duration = 2 weeks;
		uint256 ggpStakeAmt = 1000 ether;
		uint256 liquidStakingAmt = 3334 ether;

		address nodeOp = getActorWithTokens("nodeOp", 6334 ether, 1000 ether);

		// deposit liquid staking funds
		vm.startPrank(nodeOp);
		ggAVAX.depositAVAX{value: liquidStakingAmt}();

		// stake ggp
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);

		// create minipools
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, assignmentRequest, duration);
		createMinipool(depositAmt, assignmentRequest, duration);
		createMinipool(depositAmt, assignmentRequest, duration);
		vm.stopPrank();

		// launch one minipool
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp1.nodeID);
		vm.stopPrank();

		// highwater should be 1k for 1 launched minipool
		assertEq(staking.getAVAXAssigned(nodeOp), 3000 ether);
		assertEq(staking.getAVAXValidating(nodeOp), 1000 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), 1000 ether);
	}

	function testRewardsReset() public {
		// day 0
		// create minipool 1k
		// launch minipool
		// day 14
		// finish minipool
		// day 28
		// create minipool 1k
		// create minipool 1k
		// highWater should reset to 0

		uint256 depositAmt = 1000 ether;
		uint256 assignmentRequest = 1000 ether;
		uint256 duration = 2 weeks;
		uint256 ggpStakeAmt = 1000 ether;
		uint256 liquidStakingAmt = 3334 ether;

		address nodeOp = getActorWithTokens("nodeOp", 6334 ether, 1000 ether);

		// deposit liquid staking funds
		vm.startPrank(nodeOp);
		ggAVAX.depositAVAX{value: liquidStakingAmt}();

		// stake ggp
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);

		// create first minipool
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, assignmentRequest, duration);
		vm.stopPrank();

		// launch minipool, end minipool
		rialto.processMinipoolStart(mp1.nodeID);
		skip(duration);
		rialto.processMinipoolEndWithRewards(mp1.nodeID);

		assertEq(staking.getAVAXValidatingHighWater(nodeOp), 1000 ether);

		// skip for rewardsCycle
		skip(dao.getRewardsCycleSeconds());

		// create more minipools that are in queue (unlaunched)
		vm.startPrank(nodeOp);
		createMinipool(depositAmt, assignmentRequest, duration);
		createMinipool(depositAmt, assignmentRequest, duration);
		vm.stopPrank();

		// make sure to distribute ggp before processing first rewards
		rialto.processGGPRewards();

		// with no validating minipool nodeOp's high water should be 0
		assertEq(staking.getAVAXAssigned(nodeOp), 2000 ether);
		assertEq(staking.getAVAXValidating(nodeOp), 0);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), 0);
	}
}
