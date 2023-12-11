// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";

contract StakingTest is BaseTest {
	using FixedPointMathLib for uint256;

	address private nodeOp1;
	address private nodeOp2;
	address private nodeOp3;

	uint256 internal constant TOTAL_INITIAL_GGP_SUPPLY = 22_500_000 ether;

	function setUp() public override {
		super.setUp();

		nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.prank(nodeOp1);
		ggp.approve(address(staking), MAX_AMT);
		nodeOp2 = getActorWithTokens("nodeOp2", MAX_AMT, MAX_AMT);
		vm.prank(nodeOp2);
		ggp.approve(address(staking), MAX_AMT);
		nodeOp3 = getActorWithTokens("nodeOp3", MAX_AMT, MAX_AMT);
		vm.prank(nodeOp3);
		ggp.approve(address(staking), MAX_AMT);
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

	function testGetStaker() public {
		address alice = getActorWithTokens("alice", 0, 100 ether);
		vm.startPrank(alice);
		ggp.approve(address(staking), 100 ether);
		staking.stakeGGP(100 ether);

		int256 index = staking.getIndexOf(alice);

		Staking.Staker memory expectedStaker = Staking.Staker({
			stakerAddr: alice,
			avaxAssigned: 0,
			avaxStaked: 0,
			avaxValidating: 0,
			avaxValidatingHighWater: 0,
			ggpRewards: 0,
			ggpStaked: 100 ether,
			lastRewardsCycleCompleted: 0,
			rewardsStartTime: 0,
			ggpLockedUntil: 0
		});

		assertEq(staking.getStaker(index).stakerAddr, expectedStaker.stakerAddr);
		assertEq(staking.getStaker(index).avaxAssigned, expectedStaker.avaxAssigned);
		assertEq(staking.getStaker(index).avaxStaked, expectedStaker.avaxStaked);
		assertEq(staking.getStaker(index).avaxValidating, expectedStaker.avaxValidating);
		assertEq(staking.getStaker(index).avaxValidatingHighWater, expectedStaker.avaxValidatingHighWater);
		assertEq(staking.getStaker(index).ggpRewards, expectedStaker.ggpRewards);
		assertEq(staking.getStaker(index).ggpStaked, expectedStaker.ggpStaked);
		assertEq(staking.getStaker(index).lastRewardsCycleCompleted, expectedStaker.lastRewardsCycleCompleted);
		assertEq(staking.getStaker(index).rewardsStartTime, expectedStaker.rewardsStartTime);
		assertEq(staking.getStaker(index).ggpLockedUntil, expectedStaker.ggpLockedUntil);
	}

	function testGetTotalGGPStake() public {
		assert(staking.getTotalGGPStake() == 0);
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		assert(staking.getTotalGGPStake() == 100 ether);
		vm.stopPrank();

		vm.prank(nodeOp2);
		staking.stakeGGP(100 ether);
		assert(staking.getTotalGGPStake() == 200 ether);

		vm.prank(nodeOp1);
		staking.withdrawGGP(100 ether);
		assert(staking.getTotalGGPStake() == 100 ether);
	}

	function testGetStakerCount() public {
		assert(staking.getStakerCount() == 0);
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);
		assert(staking.getStakerCount() == 1);

		vm.prank(nodeOp2);
		staking.stakeGGP(100 ether);
		assert(staking.getStakerCount() == 2);
	}

	function testGetGGPStake() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);
		assert(staking.getGGPStake(address(nodeOp1)) == 100 ether);

		vm.prank(nodeOp2);
		staking.stakeGGP(10.09 ether);
		assert(staking.getGGPStake(address(nodeOp2)) == 10.09 ether);
	}

	function testGetAVAXStake() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getAVAXStake(address(nodeOp1)) == 1000 ether);
		vm.stopPrank();

		vm.startPrank(nodeOp2);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getAVAXStake(address(nodeOp2)) == 1000 ether);
		vm.stopPrank();
	}

	function testIncreaseAVAXStake() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();
		vm.prank(address(minipoolMgr));
		staking.increaseAVAXStake(address(nodeOp1), 100 ether);
		assert(staking.getAVAXStake(address(nodeOp1)) == 1100 ether);
	}

	function testDecreaseAVAXStake() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();
		vm.prank(address(minipoolMgr));
		staking.decreaseAVAXStake(address(nodeOp1), 10 ether);
		assert(staking.getAVAXStake(address(nodeOp1)) == 990 ether);
	}

	function testGetAVAXAssigned() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getAVAXAssigned(address(nodeOp1)) == 1000 ether);
		vm.stopPrank();
	}

	function testIncreaseAVAXAssigned() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		vm.prank(address(minipoolMgr));
		staking.increaseAVAXAssigned(address(nodeOp1), 100 ether);
		assert(staking.getAVAXAssigned(address(nodeOp1)) == 1100 ether);
	}

	function testDecreaseAVAXAssigned() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();
		vm.prank(address(minipoolMgr));
		staking.decreaseAVAXAssigned(address(nodeOp1), 10 ether);
		assert(staking.getAVAXAssigned(address(nodeOp1)) == 990 ether);
	}

	function testGetRewardsStartTime() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(200 ether);
		assert(staking.getRewardsStartTime(address(nodeOp1)) == 0);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getRewardsStartTime(address(nodeOp1)) != 0);
		vm.stopPrank();
	}

	function testSetRewardsStartTime() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(200 ether);
		assertEq(staking.getRewardsStartTime(address(nodeOp1)), 0);

		uint256 timestamp = 1666291634;
		vm.warp(timestamp);

		vm.prank(address(minipoolMgr));
		staking.setRewardsStartTime(address(nodeOp1), block.timestamp);
		assertEq(staking.getRewardsStartTime(address(nodeOp1)), timestamp);
	}

	function testSetRewardsStartTimeInvalid() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(200 ether);
		assert(staking.getRewardsStartTime(address(nodeOp1)) == 0);

		vm.startPrank(address(minipoolMgr));
		vm.expectRevert(Staking.InvalidRewardsStartTime.selector);
		staking.setRewardsStartTime(address(nodeOp1), block.timestamp + 1);
		vm.stopPrank();
	}

	function testGetGGPRewards() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		vm.expectRevert(RewardsPool.UnableToStartRewardsCycle.selector);
		rewardsPool.startRewardsCycle();
		assertFalse(rewardsPool.canStartRewardsCycle());
		assertEq(vault.balanceOfToken("ClaimNodeOp", ggp), 0);
		assertEq(vault.balanceOfToken("ClaimProtocolDAO", ggp), 0);

		skip(2 weeks);
		skip(dao.getRewardsCycleSeconds());

		assertEq(rewardsPool.getRewardsCyclesElapsed(), 1);
		assertTrue(rewardsPool.canStartRewardsCycle());

		rialto.processGGPRewards();

		assertGt(vault.balanceOfToken("ClaimNodeOp", ggp), 0);
		assertGt(vault.balanceOfToken("ClaimProtocolDAO", ggp), 0);

		assertGt(staking.getGGPRewards(address(nodeOp1)), 0);
	}

	function testIncreaseGGPRewards() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);

		vm.prank(address(nopClaim));
		staking.increaseGGPRewards(address(nodeOp1), 100 ether);
		assert(staking.getGGPRewards(address(nodeOp1)) == 100 ether);
	}

	function testDecreaseGGPRewards() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);
		assert(staking.getGGPRewards(address(nodeOp1)) == 0 ether);

		vm.startPrank(address(nopClaim));
		staking.increaseGGPRewards(address(nodeOp1), 100 ether);
		staking.decreaseGGPRewards(address(nodeOp1), 10 ether);
		assert(staking.getGGPRewards(address(nodeOp1)) == 90 ether);
		vm.stopPrank();
	}

	function testGetLastRewardsCycleCompleted() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(100 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		vm.expectRevert(RewardsPool.UnableToStartRewardsCycle.selector);
		rewardsPool.startRewardsCycle();
		assertFalse(rewardsPool.canStartRewardsCycle());
		assertEq(vault.balanceOfToken("ClaimNodeOp", ggp), 0);
		assertEq(vault.balanceOfToken("ClaimProtocolDAO", ggp), 0);

		skip(2 weeks);
		skip(dao.getRewardsCycleSeconds());

		assertEq(rewardsPool.getRewardsCyclesElapsed(), 1);
		assertTrue(rewardsPool.canStartRewardsCycle());
		assertEq(staking.getLastRewardsCycleCompleted(address(nodeOp1)), 0);

		rialto.processGGPRewards();

		assertGt(vault.balanceOfToken("ClaimNodeOp", ggp), 0);
		assertGt(vault.balanceOfToken("ClaimProtocolDAO", ggp), 0);

		assertGt(staking.getGGPRewards(address(nodeOp1)), 0);
		assertEq(staking.getLastRewardsCycleCompleted(address(nodeOp1)), 1);
	}

	function testGetMinimumGGPStake() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(300 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getMinimumGGPStake(address(nodeOp1)) == 100 ether);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getMinimumGGPStake(address(nodeOp1)) == 200 ether);
		vm.stopPrank();
	}

	function testGetCollateralizationRatio() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(300 ether);
		assert(staking.getCollateralizationRatio(address(nodeOp1)) == type(uint256).max);
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		assert(staking.getCollateralizationRatio(address(nodeOp1)) == 0.3 ether);
		vm.stopPrank();
	}

	function testGetEffectiveGGPStaked() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(300 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 0 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);

		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 300 ether);
		staking.stakeGGP(1700 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 1500 ether);
		vm.stopPrank();
		vm.prank(address(minipoolMgr));
		staking.decreaseAVAXAssigned(nodeOp1, 1000 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 1500 ether);
	}

	function testGetEffectiveGGPStakedWithLowGGPPrice() public {
		rialto.setGGPPriceInAVAX(0.1 ether, block.timestamp);

		vm.startPrank(nodeOp1);
		staking.stakeGGP(3000 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 0 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 3000 ether);
		staking.stakeGGP(17000 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 15000 ether);
		vm.stopPrank();
		vm.prank(address(minipoolMgr));
		staking.decreaseAVAXAssigned(nodeOp1, 1000 ether);
		assertEq(staking.getEffectiveGGPStaked(nodeOp1), 15000 ether);
	}

	function testRestakeGGP() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(300 ether);
		dealGGP(address(nopClaim), 1000 ether);
		assert(staking.getGGPStake(nodeOp1) == 300 ether);

		vm.startPrank(address(nopClaim));
		ggp.approve(address(staking), MAX_AMT);
		staking.restakeGGP(address(nodeOp1), 200 ether);
		vm.stopPrank();
		assert(staking.getGGPStake(address(nodeOp1)) == 500 ether);
	}

	function testStakeGGP() public {
		uint256 amt = 100 ether;
		vm.startPrank(nodeOp1);
		uint256 startingGGPAmt = ggp.balanceOf(nodeOp1);
		staking.stakeGGP(amt);
		assert(ggp.balanceOf(nodeOp1) == startingGGPAmt - amt);
		assert(staking.getGGPStake(nodeOp1) == amt);
		vm.stopPrank();
	}

	function testStakeOnBehalfOfMustBeAuthorized() public {
		address authorizedStaker = staking.authorizedStaker();
		dealGGP(authorizedStaker, 100 ether);
		uint256 amt = 100 ether;

		vm.expectRevert(Staking.NotAuthorized.selector);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, 0);

		vm.startPrank(guardian);
		vm.expectRevert(Staking.NotAuthorized.selector);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, 0);
		vm.stopPrank();

		vm.startPrank(authorizedStaker);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, 0);
		vm.stopPrank();

		assertEq(staking.getGGPStake(nodeOp1), amt);
	}

	function testStakeOnBehalfOfNoLock() public {
		address authorizedStaker = staking.authorizedStaker();
		dealGGP(authorizedStaker, 100 ether);
		uint256 amt = 100 ether;
		uint256 startingGGPAmtNodeOp1 = ggp.balanceOf(nodeOp1);
		uint256 startingGGPAmtDelegator = ggp.balanceOf(authorizedStaker);

		vm.startPrank(authorizedStaker);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, 0);
		vm.stopPrank();

		assertEq(ggp.balanceOf(authorizedStaker), startingGGPAmtDelegator - amt);
		assertEq(ggp.balanceOf(nodeOp1), startingGGPAmtNodeOp1);
		assertEq(staking.getGGPStake(nodeOp1), amt);

		int256 stakerIndex = staking.getIndexOf(nodeOp1);

		assertEq(store.getUint(keccak256(abi.encodePacked("staker.item", stakerIndex, ".ggpLockedUntil"))), 0);

		vm.prank(nodeOp1);
		staking.withdrawGGP(amt);
		assertEq(ggp.balanceOf(nodeOp1), startingGGPAmtNodeOp1 + amt);
	}

	function testStakeOnBehalfOfLockRecentTimestamp() public {
		address authorizedStaker = staking.authorizedStaker();
		uint256 amt = 100 ether;
		dealGGP(authorizedStaker, amt);
		uint256 startingGGPAmtNodeOp1 = ggp.balanceOf(nodeOp1);

		skip(100);
		vm.startPrank(authorizedStaker);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, block.timestamp - 1);
		vm.stopPrank();

		int256 stakerIndex = staking.getIndexOf(nodeOp1);

		assertEq(store.getUint(keccak256(abi.encodePacked("staker.item", stakerIndex, ".ggpLockedUntil"))), 0);

		vm.prank(nodeOp1);
		staking.withdrawGGP(amt);
		assertEq(ggp.balanceOf(nodeOp1), startingGGPAmtNodeOp1 + amt);
	}

	function testStakeOnBehalfOfGGPWithLock() public {
		address authorizedStaker = staking.authorizedStaker();
		uint256 amt = 100 ether;
		dealGGP(authorizedStaker, amt);
		uint256 startingGGPAmtNodeOp1 = ggp.balanceOf(nodeOp1);
		uint256 startingGGPAmtDelegator = ggp.balanceOf(authorizedStaker);

		vm.startPrank(authorizedStaker);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGPOnBehalfOfWithLock(nodeOp1, amt, block.timestamp + 1);
		vm.stopPrank();

		assertEq(ggp.balanceOf(authorizedStaker), startingGGPAmtDelegator - amt);
		assertEq(ggp.balanceOf(nodeOp1), startingGGPAmtNodeOp1);
		assertEq(staking.getGGPStake(nodeOp1), amt);

		vm.prank(nodeOp1);
		vm.expectRevert(Staking.GGPLocked.selector);
		staking.withdrawGGP(amt);

		skip(2);
		vm.prank(nodeOp1);
		staking.withdrawGGP(amt);
		assertEq(ggp.balanceOf(nodeOp1), startingGGPAmtNodeOp1 + amt);
	}

	function testStakeAndWithdrawGGPPaused() public {
		uint256 initialBalance = ggp.balanceOf(nodeOp1);
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);

		assertEq(staking.getGGPStake(nodeOp1), 100 ether);
		assertEq(ggp.balanceOf(nodeOp1), initialBalance - 100 ether);

		vm.prank(address(ocyticus));
		dao.pauseContract("Staking");

		vm.startPrank(nodeOp1);
		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		staking.stakeGGP(100 ether);

		// ensure withdrawing allowed while paused
		staking.withdrawGGP(100 ether);
		assertEq(staking.getGGPStake(nodeOp1), 0);
		assertEq(ggp.balanceOf(nodeOp1), initialBalance);
	}

	function testWithdrawGGP() public {
		uint256 amt = 100 ether;
		vm.startPrank(nodeOp1);
		uint256 startingGGPAmt = ggp.balanceOf(nodeOp1);
		staking.stakeGGP(amt);
		assert(ggp.balanceOf(nodeOp1) == startingGGPAmt - amt);
		assert(staking.getGGPStake(nodeOp1) == amt);
		staking.withdrawGGP(amt);
		assert(ggp.balanceOf(nodeOp1) == startingGGPAmt);
		vm.expectRevert(Staking.InsufficientBalance.selector);
		staking.withdrawGGP(1 ether);
		vm.stopPrank();
	}

	function testSlashGGP() public {
		uint256 amt = 100 ether;
		vm.prank(nodeOp1);
		staking.stakeGGP(amt);
		assertEq(vault.balanceOfToken("Staking", ggp), amt);
		assert(staking.getGGPStake(nodeOp1) == amt);
		vm.prank(address(minipoolMgr));
		staking.slashGGP(nodeOp1, amt);
		assertEq(staking.getGGPStake(nodeOp1), 0);
		assertEq(vault.balanceOfToken("Staking", ggp), 0);
		assertEq(vault.balanceOfToken("ProtocolDAO", ggp), amt);
	}

	function testStakeWithdraw() public {
		vm.startPrank(nodeOp1);
		staking.stakeGGP(300 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 2 weeks);

		vm.expectRevert(Staking.CannotWithdrawUnder150CollateralizationRatio.selector);
		staking.withdrawGGP(1 ether);

		vm.expectRevert(Staking.InsufficientBalance.selector);
		staking.withdrawGGP(10_000 ether);

		staking.stakeGGP(1300 ether);
		vm.expectRevert(Staking.CannotWithdrawUnder150CollateralizationRatio.selector);
		staking.withdrawGGP(1600 ether);

		skip(5 seconds); // cancellation moratorium
		minipoolMgr.cancelMinipool(mp.nodeID);

		staking.withdrawGGP(300 ether);

		vm.stopPrank();
	}

	// To ensure we are managing getAVAXValidating and getAVAXValidatingHighWater separately now
	function testAVAXValidatingHighWaterMark() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);

		vm.startPrank(address(minipoolMgr));
		assertEq(staking.getAVAXValidating(nodeOp1), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 0 ether);

		staking.increaseAVAXValidating(nodeOp1, 1000 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 0 ether);
		staking.setAVAXValidatingHighWater(nodeOp1, 1000 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 1000 ether);

		staking.decreaseAVAXValidating(nodeOp1, 1000 ether);
		assertEq(staking.getAVAXAssigned(nodeOp1), 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 1000 ether);

		staking.setAVAXValidatingHighWater(nodeOp1, 0 ether);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), 0 ether);
		vm.stopPrank();
	}

	function testAVAXValidating() public {
		vm.prank(nodeOp1);
		staking.stakeGGP(100 ether);

		vm.startPrank(address(minipoolMgr));
		staking.increaseAVAXValidating(nodeOp1, 1000 ether);

		assertEq(staking.getAVAXValidating(nodeOp1), 1000 ether);

		staking.decreaseAVAXValidating(nodeOp1, 1000 ether);
		assertEq(staking.getAVAXValidating(nodeOp1), 0);
		vm.stopPrank();
	}
}
