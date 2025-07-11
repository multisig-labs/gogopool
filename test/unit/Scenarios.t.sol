// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract ScenariosTest is BaseTest {
	using FixedPointMathLib for uint256;
	uint128 internal constant ONE_K = 1_000 ether;
	uint256 internal constant TOTAL_INITIAL_GGP_SUPPLY = 22_500_000 ether;

	address private nodeOp1;
	address private nodeOp2;
	address private nodeOp3;
	address private nodeOp4;
	address private liqStaker1;
	address private liqStaker2;
	address private liqStaker3;
	address private investor1;
	address private investor2;

	function setUp() public override {
		super.setUp();

		nodeOp1 = getActorWithTokens("nodeOp1", ONE_K, ONE_K);
		nodeOp2 = getActorWithTokens("nodeOp2", ONE_K, ONE_K);
		nodeOp3 = getActorWithTokens("nodeOp3", ONE_K, ONE_K);
		nodeOp4 = getActorWithTokens("nodeOp4", ONE_K, ONE_K);
		liqStaker1 = getActorWithTokens("liqStaker1", ONE_K, 0);
		liqStaker2 = getActorWithTokens("liqStaker2", ONE_K, 0);
		liqStaker3 = getActorWithTokens("liqStaker3", ONE_K * 7, 0);
		investor1 = getInvestorWithTokens("investor1", ONE_K, ONE_K);
		investor2 = getInvestorWithTokens("investor2", ONE_K, ONE_K);

		grantWithdrawQueueRole(liqStaker1);
		grantWithdrawQueueRole(liqStaker2);

		fundGGPRewardsPool();
	}

	function fundGGPRewardsPool() public {
		// guardian is minted 100% of the supply
		vm.startPrank(guardian);
		uint256 rewardsPoolAmt = TOTAL_INITIAL_GGP_SUPPLY.mulWadDown(.20 ether);
		ggp.approve(address(vault), rewardsPoolAmt);
		vault.depositToken("RewardsPool", ggp, rewardsPoolAmt);
		vm.stopPrank();
	}

	// For this test we wont do lots of intermediate asserts, just focus on end results
	function testFullCycleHappyPath() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		// Liq Stakers deposit all their AVAX and get ggAVAX in return
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: ONE_K}();

		vm.prank(liqStaker2);
		ggAVAX.depositAVAX{value: ONE_K}();

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		// Cannot unstake GGP at this point
		vm.expectRevert(Staking.CannotWithdrawUnder150CollateralizationRatio.selector);
		vm.prank(nodeOp1);
		staking.withdrawGGP(ggpStakeAmt);

		mp = rialto.processMinipoolStart(mp.nodeID);
		skip(mp.duration);

		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		// test that the node op can withdraw the funds they are due
		uint256 nodeOp1PriorBalance = nodeOp1.balance;
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp.nodeID);
		assertEq((nodeOp1.balance - nodeOp1PriorBalance), mp.avaxNodeOpAmt + mp.avaxNodeOpRewardAmt);

		skip(block.timestamp - rewardsPool.getRewardsCycleStartTime());
		assertTrue(rewardsPool.canStartRewardsCycle());
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		rialto.processGGPRewards();

		assertEq(staking.getRewardsStartTime(nodeOp1), 0);

		// Not testing if the rewards are "correct", depends on elapsed time too much
		// So just restake it all
		uint256 ggpRewards = staking.getGGPRewards(nodeOp1);
		vm.prank(nodeOp1);
		nopClaim.claimAndRestake(0);
		assertEq(staking.getGGPStake(nodeOp1), ggpStakeAmt + ggpRewards);

		// Skip forward 2 cycles to ensure all ggAVAX rewards are available
		skip(ggAVAX.rewardsCycleLength());
		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());
		ggAVAX.syncRewards();

		// liqStaker1 can withdraw all their funds
		uint256 amt = ggAVAX.balanceOf(liqStaker1);
		vm.prank(liqStaker1);
		ggAVAX.redeemAVAX(amt);
		uint256 expectedTotal = ONE_K + (mp.avaxLiquidStakerRewardAmt / 2);
		assertEq(liqStaker1.balance, expectedTotal);

		// liqStaker2 can not withdraw all because of the float
		assertEq(ggAVAX.maxWithdraw(liqStaker2), expectedTotal);
		amt = ggAVAX.amountAvailableForStaking();
		vm.prank(liqStaker2);
		ggAVAX.withdrawAVAX(amt);
		assertEq(liqStaker2.balance, amt);
	}

	function testFullCycleNoRewards() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		// Liq Stakers deposit all their AVAX and get ggAVAX in return
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: ONE_K}();

		vm.prank(liqStaker2);
		ggAVAX.depositAVAX{value: ONE_K}();

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		// Cannot unstake GGP at this point
		vm.expectRevert(Staking.CannotWithdrawUnder150CollateralizationRatio.selector);
		vm.prank(nodeOp1);
		staking.withdrawGGP(ggpStakeAmt);

		mp = rialto.processMinipoolStart(mp.nodeID);
		skip(mp.duration);

		mp = rialto.processMinipoolEndWithoutRewards(mp.nodeID);

		// test that the node op can withdraw the funds they are due
		uint256 priorBalance_nodeOp1 = nodeOp1.balance;
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp.nodeID);
		assertEq((nodeOp1.balance - priorBalance_nodeOp1), mp.avaxNodeOpAmt + mp.avaxNodeOpRewardAmt);

		// nodeOp1 should have been slashed
		uint256 expectedAvaxRewardsAmt = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, depositAmt);
		uint256 slashedGGPAmt = minipoolMgr.calculateGGPSlashAmt(expectedAvaxRewardsAmt);
		assertEq(staking.getGGPStake(nodeOp1), ggpStakeAmt - slashedGGPAmt);

		skip(block.timestamp - rewardsPool.getRewardsCycleStartTime());
		assertTrue(rewardsPool.canStartRewardsCycle());
		// nopeOp1 is still "eligible" even though they were slashed
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		rialto.processGGPRewards();

		// Not testing if the rewards are "correct", depends on elapsed time too much
		// So just restake it all
		uint256 ggpRewards = staking.getGGPRewards(nodeOp1);
		vm.prank(nodeOp1);
		nopClaim.claimAndRestake(0);
		assertEq(staking.getGGPStake(nodeOp1), ggpStakeAmt + ggpRewards - slashedGGPAmt);

		// Skip forward 2 cycles so all rewards are available
		skip(ggAVAX.rewardsCycleLength());
		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());
		ggAVAX.syncRewards();

		// liqStaker1 can withdraw all their funds
		uint256 amt = ggAVAX.balanceOf(liqStaker1);
		vm.prank(liqStaker1);
		ggAVAX.redeemAVAX(amt);
		uint256 expectedTotal = ONE_K + (mp.avaxLiquidStakerRewardAmt / 2);
		assertEq(liqStaker1.balance, expectedTotal);

		// liqStaker2 can not withdraw all because of the float
		assertEq(ggAVAX.maxWithdraw(liqStaker2), expectedTotal);
		amt = ggAVAX.amountAvailableForStaking();
		vm.prank(liqStaker2);
		ggAVAX.withdrawAVAX(amt);
		assertEq(liqStaker2.balance, amt);
	}

	function testStakingGGPOnly() public {
		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), 100 ether);
		staking.stakeGGP(100 ether);
		skip(dao.getRewardsCycleSeconds());
		rialto.processGGPRewards();
		assertEq(staking.getGGPRewards(address(nodeOp1)), 0);
	}

	//Documenting that this is possible
	function testStakeMinipoolUnstakeStakeScenario() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		// Cannot unstake GGP at this point
		vm.expectRevert(Staking.CannotWithdrawUnder150CollateralizationRatio.selector);
		vm.prank(nodeOp1);
		staking.withdrawGGP(ggpStakeAmt);

		skip(mp.duration);

		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		// test that the node op can withdraw the funds they are due
		uint256 nodeOp1PriorBalance = nodeOp1.balance;
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp.nodeID);
		assertEq((nodeOp1.balance - nodeOp1PriorBalance), mp.avaxNodeOpAmt + mp.avaxNodeOpRewardAmt);

		//test that node op can withdraw all their GGP
		uint256 nodeOp1PriorBalanceGGP = ggp.balanceOf(nodeOp1);
		vm.prank(nodeOp1);
		staking.withdrawGGP(ggpStakeAmt);
		assertEq((ggp.balanceOf(nodeOp1) - nodeOp1PriorBalanceGGP), ggpStakeAmt);
		assertEq(staking.getGGPStake(address(nodeOp1)), 0);

		//fwd in time 1 day before the rewards cycle
		skip(block.timestamp - rewardsPool.getRewardsCycleStartTime() - 1 days);

		//stake at max collat
		(uint256 ggpPriceInAvax, ) = oracle.getGGPPriceInAVAX();
		uint256 highwater = staking.getAVAXValidatingHighWater(address(nodeOp1));
		uint256 ggp150pct = highwater.divWadDown(ggpPriceInAvax);
		uint256 ggpMaxCollat = ggp150pct.mulWadDown(dao.getMaxCollateralizationRatio());
		dealGGP(nodeOp1, ggpMaxCollat);
		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpMaxCollat);
		staking.stakeGGP(ggpMaxCollat);
		assertEq(staking.getGGPRewards(address(nodeOp1)), 0);

		skip(1 days);
		assertTrue(rewardsPool.canStartRewardsCycle());
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		rialto.processGGPRewards();

		assertEq(staking.getGGPRewards(address(nodeOp1)), nopClaim.getRewardsCycleTotal());
	}

	// Verifies minipools get properly rewarded for each rewards cycle and high water mark is working correctly
	function testRewardsManipulation() public {
		skip(dao.getRewardsCycleSeconds());
		rialto.processGGPRewards();

		// half way + 1 day (15th day of the 28 day cycle)
		skip((dao.getRewardsCycleSeconds() / 2) + 1 days);
		assertFalse(rewardsPool.canStartRewardsCycle());

		uint256 duration = dao.getRewardsEligibilityMinSeconds();
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createAndStartMinipool(depositAmt, depositAmt, duration);
		uint256 rewardsStartTimeMP1 = staking.getRewardsStartTime(address(nodeOp1));
		vm.stopPrank();

		// fwd in time to  the rewards cycle
		skip(dao.getRewardsCycleSeconds() - (block.timestamp - rewardsPool.getRewardsCycleStartTime()));
		assertFalse(nopClaim.isEligible(address(nodeOp1)));
		rialto.processGGPRewards();

		assertEq(staking.getGGPRewards(address(nodeOp1)), 0);
		skip(1 days);

		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);

		// test that the node op can withdraw the funds they are due
		uint256 nodeOp1PriorBalance = nodeOp1.balance;
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp1.nodeID);
		assertEq((nodeOp1.balance - nodeOp1PriorBalance), mp1.avaxNodeOpAmt + mp1.avaxNodeOpRewardAmt);

		// day 15 of second cycle
		skip((dao.getRewardsCycleSeconds() / 2));
		vm.prank(nodeOp1);
		MinipoolManager.Minipool memory mp2 = createMinipool(depositAmt, depositAmt, duration);
		mp2 = rialto.processMinipoolStart(mp2.nodeID);

		// fwd in time to  the rewards cycle
		skip(dao.getRewardsCycleSeconds() - (block.timestamp - rewardsPool.getRewardsCycleStartTime()));

		// they should get rewarded for their first minipool only
		assertEq(staking.getAVAXValidatingHighWater(address(nodeOp1)), depositAmt);
		assertEq(staking.getRewardsStartTime(address(nodeOp1)), rewardsStartTimeMP1);
		assertTrue(nopClaim.isEligible(address(nodeOp1)));
		assertTrue(rewardsPool.canStartRewardsCycle());

		rialto.processGGPRewards();

		assertGt(staking.getGGPRewards(address(nodeOp1)), 0);

		skip(1 days);

		mp2 = rialto.processMinipoolEndWithRewards(mp2.nodeID);

		// test that the node op can withdraw the funds they are due
		nodeOp1PriorBalance = nodeOp1.balance;
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp2.nodeID);
		assertEq((nodeOp1.balance - nodeOp1PriorBalance), mp2.avaxNodeOpAmt + mp2.avaxNodeOpRewardAmt);

		skip(dao.getRewardsCycleSeconds() - (block.timestamp - rewardsPool.getRewardsCycleStartTime()));

		// they should get rewarded for their second minipool only
		assertEq(staking.getAVAXValidatingHighWater(address(nodeOp1)), depositAmt);
		assertTrue(nopClaim.isEligible(address(nodeOp1)));
		rialto.processGGPRewards();

		assertGt(staking.getGGPRewards(address(nodeOp1)), 0);

		// test that node op can withdraw all their GGP
		uint256 nodeOp1PriorBalanceGGP = ggp.balanceOf(nodeOp1);
		vm.prank(nodeOp1);
		staking.withdrawGGP(ggpStakeAmt);
		assertEq((ggp.balanceOf(nodeOp1) - nodeOp1PriorBalanceGGP), ggpStakeAmt);
		assertEq(staking.getGGPStake(address(nodeOp1)), 0);
	}

	// Investors should only get about half rewards on their gpp, this should not effect the other users GGP rewards
	function testHalfRewardsForUnvestedGGPSmallScale() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(nodeOp2);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp2 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(investor1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp3 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		skip(duration);

		// avax rewards
		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);
		mp2 = rialto.processMinipoolEndWithRewards(mp2.nodeID);
		mp3 = rialto.processMinipoolEndWithRewards(mp3.nodeID);

		skip(block.timestamp - rewardsPool.getRewardsCycleStartTime());
		assertTrue(rewardsPool.canStartRewardsCycle());

		// investors and regular nodes have the same eligibility requirements
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		assertTrue(nopClaim.isEligible(nodeOp2), "isEligible");
		assertTrue(nopClaim.isEligible(investor1), "isEligible");

		rialto.processGGPRewards();

		uint256 totalRewards = nopClaim.getRewardsCycleTotal();

		uint256 nodeOpsRewards = totalRewards.mulWadDown(0.4 ether);
		uint256 investorRewards = totalRewards.mulWadDown(0.2 ether);

		assertEq(staking.getGGPRewards(nodeOp1), nodeOpsRewards);
		assertEq(staking.getGGPRewards(nodeOp2), nodeOpsRewards);
		assertEq(staking.getGGPRewards(investor1), investorRewards);
	}

	function testHalfRewardsForUnvestedGGPLargerScale() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(nodeOp2);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp2 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(nodeOp3);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp5 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(nodeOp4);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp6 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(investor1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp3 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		vm.startPrank(investor2);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp4 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		skip(duration);

		// avax rewards
		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);
		mp2 = rialto.processMinipoolEndWithRewards(mp2.nodeID);
		mp3 = rialto.processMinipoolEndWithRewards(mp3.nodeID);
		mp4 = rialto.processMinipoolEndWithRewards(mp4.nodeID);
		mp5 = rialto.processMinipoolEndWithRewards(mp5.nodeID);
		mp6 = rialto.processMinipoolEndWithRewards(mp6.nodeID);

		skip(block.timestamp - rewardsPool.getRewardsCycleStartTime());
		assertTrue(rewardsPool.canStartRewardsCycle());

		//investors and regular nodes have the same eligibility requirements
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		assertTrue(nopClaim.isEligible(nodeOp2), "isEligible");
		assertTrue(nopClaim.isEligible(nodeOp3), "isEligible");
		assertTrue(nopClaim.isEligible(nodeOp4), "isEligible");
		assertTrue(nopClaim.isEligible(investor1), "isEligible");
		assertTrue(nopClaim.isEligible(investor2), "isEligible");

		rialto.processGGPRewards();

		uint256 totalRewards = nopClaim.getRewardsCycleTotal();

		uint256 nodeOpsRewards = totalRewards.mulWadDown(0.2 ether);
		uint256 investorRewards = totalRewards.mulWadDown(0.1 ether);

		assertEq(staking.getGGPRewards(nodeOp1), nodeOpsRewards);
		assertEq(staking.getGGPRewards(nodeOp2), nodeOpsRewards);
		assertEq(staking.getGGPRewards(nodeOp3), nodeOpsRewards);
		assertEq(staking.getGGPRewards(nodeOp4), nodeOpsRewards);
		assertEq(staking.getGGPRewards(investor1), investorRewards);
		assertEq(staking.getGGPRewards(investor2), investorRewards);
	}

	function testAVAXValidatingHighWaterMarkCancelledMinipool() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		// Liq Stakers deposit all their AVAX and get ggAVAX in return
		vm.prank(liqStaker3);
		ggAVAX.depositAVAX{value: (ONE_K * 7)}();

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		assertEq(staking.getAVAXAssigned(nodeOp1), depositAmt);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 0);
		mp1 = rialto.processMinipoolStart(mp1.nodeID);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), depositAmt);
		skip(mp1.duration);
		// avax rewards
		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);
		vm.prank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp1.nodeID);

		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		assertEq(staking.getAVAXAssigned(nodeOp1), 0);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), depositAmt);
		assertGt(staking.getEffectiveGGPStaked(nodeOp1), 0);

		vm.startPrank(nodeOp1);
		MinipoolManager.Minipool memory mp2 = createMinipool(depositAmt, depositAmt, duration);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), depositAmt);
		skip(5 seconds); //cancel min time
		minipoolMgr.cancelMinipool(mp2.nodeID);
		vm.stopPrank();

		// We canceled mp2, but we should still have a highwater mark of mp1 and be eligible for rewards
		assertTrue(nopClaim.isEligible(nodeOp1), "isEligible");
		assertEq(staking.getAVAXAssigned(nodeOp1), 0);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), depositAmt);
		assertGt(staking.getEffectiveGGPStaked(nodeOp1), 0);
	}

	function testChangeInflationRate() public {
		// change the inflation rate to be 0
		// do a rewards cycle
		// change inflation rate to 1%
		// do a rewards cycle
		// change inflation rate to 5% (normal)
		// do the rewards cycle
		assertEq(dao.getInflationIntervalRate(), 1000133680617113500); // 5%
		store.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 0);

		skip(dao.getRewardsCycleSeconds());
		assertEq(rewardsPool.getRewardsCyclesElapsed(), 1);
		assertTrue(rewardsPool.canStartRewardsCycle());

		vm.expectRevert(Vault.InvalidAmount.selector);
		rewardsPool.startRewardsCycle();

		store.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1000002738360826244); // 0.1%

		skip(dao.getRewardsCycleSeconds());
		assertEq(rewardsPool.getRewardsCyclesElapsed(), 2);
		assertTrue(rewardsPool.canStartRewardsCycle());

		rewardsPool.startRewardsCycle();

		assertGt(nopClaim.getRewardsCycleTotal(), 0);
		assertGt(vault.balanceOfToken("ClaimNodeOp", ggp), 0);
		store.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1000027261552008994); // 1%

		skip(dao.getRewardsCycleSeconds());
		assertEq(rewardsPool.getRewardsCyclesElapsed(), 1);
		assertTrue(rewardsPool.canStartRewardsCycle());
		rewardsPool.startRewardsCycle();

		uint256 previousRewardsTotal = nopClaim.getRewardsCycleTotal();

		assertGt(nopClaim.getRewardsCycleTotal(), 0);
		assertGt(vault.balanceOfToken("ClaimNodeOp", ggp), 0);

		store.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1000133680617113500); // 5%

		skip(dao.getRewardsCycleSeconds());
		assertEq(rewardsPool.getRewardsCyclesElapsed(), 1);
		assertTrue(rewardsPool.canStartRewardsCycle());
		rewardsPool.startRewardsCycle();

		assertGt(nopClaim.getRewardsCycleTotal(), previousRewardsTotal);
	}

	// minipool in withdrawable state will still get rewarded, even if they are under the 10% collat ratio
	function testGGPRewardsForWithdrawableMinipoolsUnderCollat() public {
		uint256 duration = dao.getRewardsEligibilityMinSeconds();
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		skip(dao.getRewardsEligibilityMinSeconds());

		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);

		// check the status
		MinipoolManager.Minipool memory mp2 = minipoolMgr.getMinipoolByNodeID(mp1.nodeID);
		assertEq(mp2.status, uint256(MinipoolStatus.Withdrawable));

		// unstake some GGP to get under 10% collat
		vm.startPrank(nodeOp1);
		staking.withdrawGGP((ggpStakeAmt / 2));
		assertEq(staking.getGGPStake(nodeOp1), ggpStakeAmt / 2);
		assertEq(staking.getCollateralizationRatio(nodeOp1), type(uint256).max);
		assertLt(staking.getEffectiveRewardsRatio(nodeOp1), dao.getMinCollateralizationRatio());

		// fwd in time to  the rewards cycle
		skip(dao.getRewardsCycleSeconds() - (block.timestamp - rewardsPool.getRewardsCycleStartTime()));

		// they should get rewarded for their first minipool only
		assertEq(staking.getAVAXValidatingHighWater(address(nodeOp1)), depositAmt);
		assertTrue(nopClaim.isEligible(address(nodeOp1)));
		assertTrue(rewardsPool.canStartRewardsCycle());

		rialto.processGGPRewards();

		assertEq(staking.getGGPRewards(address(nodeOp1)), nopClaim.getRewardsCycleTotal());
	}

	// minipool in finished state will still get rewarded, even if they are under the 10% collat ratio
	function testGGPRewardsForFinishedMinipoolsUnderCollat() public {
		uint256 duration = dao.getRewardsEligibilityMinSeconds();
		uint256 depositAmt = dao.getMinipoolMinAVAXAssignment();
		uint256 ggpStakeAmt = depositAmt.mulWadDown(dao.getMinCollateralizationRatio());

		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createAndStartMinipool(depositAmt, depositAmt, duration);
		vm.stopPrank();

		skip(dao.getRewardsEligibilityMinSeconds());

		mp1 = rialto.processMinipoolEndWithRewards(mp1.nodeID);

		// check the status
		uint256 nodeOp1PriorBalance = nodeOp1.balance;
		vm.startPrank(nodeOp1);
		minipoolMgr.withdrawMinipoolFunds(mp1.nodeID);
		assertEq((nodeOp1.balance - nodeOp1PriorBalance), mp1.avaxNodeOpAmt + mp1.avaxNodeOpRewardAmt);
		MinipoolManager.Minipool memory mp2 = minipoolMgr.getMinipoolByNodeID(mp1.nodeID);
		assertEq(mp2.status, uint256(MinipoolStatus.Finished));

		// unstake some GGP to get under 10% collat
		staking.withdrawGGP((ggpStakeAmt / 2));
		assertEq(staking.getGGPStake(nodeOp1), ggpStakeAmt / 2);
		assertEq(staking.getCollateralizationRatio(nodeOp1), type(uint256).max);
		assertLt(staking.getEffectiveRewardsRatio(nodeOp1), dao.getMinCollateralizationRatio());

		// fwd in time to  the rewards cycle
		skip(dao.getRewardsCycleSeconds() - (block.timestamp - rewardsPool.getRewardsCycleStartTime()));

		// they should get rewarded for their first minipool only
		assertEq(staking.getAVAXValidatingHighWater(address(nodeOp1)), depositAmt);
		assertTrue(nopClaim.isEligible(address(nodeOp1)));
		assertTrue(rewardsPool.canStartRewardsCycle());

		rialto.processGGPRewards();

		assertEq(staking.getGGPRewards(address(nodeOp1)), nopClaim.getRewardsCycleTotal());
	}
}
