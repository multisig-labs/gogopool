// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {Staking} from "../../contracts/contract/Staking.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract ClaimNodeOpTest is BaseTest {
	using FixedPointMathLib for uint256;
	uint256 private constant TOTAL_INITIAL_SUPPLY = 22500000 ether;

	function setUp() public override {
		super.setUp();
	}

	function testGetRewardsCycleTotal() public {
		skip(dao.getRewardsCycleSeconds());
		rewardsPool.startRewardsCycle();
		assertEq(nopClaim.getRewardsCycleTotal(), 47247734062418964737913);
	}

	function testSetRewardsCycleTotal() public {
		vm.prank(address(123));
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		nopClaim.setRewardsCycleTotal(1234 ether);

		vm.prank(address(rewardsPool));
		nopClaim.setRewardsCycleTotal(1234 ether);
		assertEq(nopClaim.getRewardsCycleTotal(), 1234 ether);
	}

	function testIsEligible() public {
		address nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp1);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		address nodeOp2 = getActorWithTokens("nodeOp2", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp2);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		createAndStartMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		address nodeOp3 = getActorWithTokens("nodeOp2", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp2);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		// do not start
		createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		assertFalse(nopClaim.isEligible(nodeOp1));
		assertFalse(nopClaim.isEligible(nodeOp2));
		assertFalse(nopClaim.isEligible(nodeOp3));

		skip(dao.getRewardsEligibilityMinSeconds());

		assertTrue(nopClaim.isEligible(nodeOp1));
		assertTrue(nopClaim.isEligible(nodeOp2));
		assertFalse(nopClaim.isEligible(nodeOp3));
	}

	function testCalculateAndDistributeRewardsInvalidStaker() public {
		address invalidStaker = getActor("invalid actor");
		vm.startPrank(address(rialto));
		vm.expectRevert(Staking.StakerNotFound.selector);
		nopClaim.calculateAndDistributeRewards(invalidStaker, 200 ether);
		vm.stopPrank();
	}

	function testCalculateAndDistributeRewardsZeroCycleCount() public {
		uint256 ggpAmt = 100 ether;
		uint256 avaxAmt = 1000 ether;
		address nodeOp = getActorWithTokens("nodeOp", uint128(avaxAmt), uint128(ggpAmt));

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpAmt);
		staking.stakeGGP(ggpAmt);
		createMinipool(avaxAmt, avaxAmt, 2 weeks);
		vm.stopPrank();

		vm.startPrank(address(rialto));
		vm.expectRevert(ClaimNodeOp.RewardsCycleNotStarted.selector);
		nopClaim.calculateAndDistributeRewards(nodeOp, ggpAmt);
	}

	function testCalculateAndDistributeRewards() public {
		skip(dao.getRewardsCycleSeconds());
		rewardsPool.startRewardsCycle();
		address nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp1);
		ggAVAX.depositAVAX{value: 2000 ether}();
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp1 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		rialto.processMinipoolStart(mp1.nodeID);
		vm.stopPrank();

		address nodeOp2 = getActorWithTokens("nodeOp2", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp2);
		ggAVAX.depositAVAX{value: 2000 ether}();
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp2 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		rialto.processMinipoolStart(mp2.nodeID);
		vm.stopPrank();

		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);

		vm.startPrank(address(rialto));
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);
		assertEq(staking.getGGPRewards(nodeOp1), (nopClaim.getRewardsCycleTotal()) / 2);
		assertEq(staking.getLastRewardsCycleCompleted(nodeOp1), rewardsPool.getRewardsCycleCount());
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), staking.getAVAXAssigned(nodeOp1));

		vm.expectRevert(abi.encodeWithSelector(ClaimNodeOp.RewardsAlreadyDistributedToStaker.selector, address(nodeOp1)));
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);
		vm.stopPrank();
	}

	function testClaimAndRestake() public {
		skip(dao.getRewardsCycleSeconds());
		rewardsPool.startRewardsCycle();
		address nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp1);
		ggAVAX.depositAVAX{value: 2000 ether}();
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 2 weeks);
		rialto.processMinipoolStart(mp.nodeID);

		uint256 nodeOp1PriorBalanceGGP = ggp.balanceOf(nodeOp1);

		assertEq(staking.getGGPRewards(nodeOp1), 0);
		vm.expectRevert(ClaimNodeOp.NoRewardsToClaim.selector);
		nopClaim.claimAndRestake(0);
		vm.stopPrank();

		vm.prank(address(rialto));
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);

		vm.startPrank(nodeOp1);
		uint256 totalRewardsThisCycle = nopClaim.getRewardsCycleTotal();
		assertEq(staking.getGGPRewards(nodeOp1), totalRewardsThisCycle / 2);
		vm.expectRevert(ClaimNodeOp.InvalidAmount.selector);
		nopClaim.claimAndRestake(totalRewardsThisCycle);

		nopClaim.claimAndRestake((totalRewardsThisCycle / 4)); // half of their rewards
		assertEq(ggp.balanceOf(nodeOp1), (nodeOp1PriorBalanceGGP + (totalRewardsThisCycle / 4)));
		assertEq(staking.getGGPStake(nodeOp1), (100 ether + (totalRewardsThisCycle / 4)));
		assertEq(staking.getGGPRewards(nodeOp1), 0);
	}

	function testClaimAndRestakePaused() public {
		// start reward cycle
		skip(dao.getRewardsCycleSeconds());
		rewardsPool.startRewardsCycle();

		// deposit ggAVAX
		address nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp1);
		ggAVAX.depositAVAX{value: 2000 ether}();

		// stake ggp and create minipool
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();

		// launch minipool
		rialto.processMinipoolStart(mp.nodeID);

		// distribute rewards
		vm.prank(address(rialto));
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);

		// pause staking
		vm.prank(address(ocyticus));
		dao.pauseContract("Staking");

		uint256 stakerRewards = staking.getGGPRewards(nodeOp1);
		uint256 previousBalance = ggp.balanceOf(nodeOp1);

		// ensure restaking fails
		vm.startPrank(nodeOp1);
		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		nopClaim.claimAndRestake((stakerRewards / 2)); // claim half of their rewards

		//  claim entire reward amount
		nopClaim.claimAndRestake((stakerRewards)); // claim all rewards
		vm.stopPrank();

		assertEq(ggp.balanceOf(nodeOp1), previousBalance + stakerRewards);
	}

	function testCalculateAndDistributeRewardsSingleStaker() public {
		address nodeOp1 = getActorWithTokens("nodeOp1", MAX_AMT, MAX_AMT);
		vm.startPrank(nodeOp1);
		ggAVAX.depositAVAX{value: 2000 ether}();
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp1 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		rialto.processMinipoolStart(mp1.nodeID);
		vm.stopPrank();

		skip(dao.getRewardsCycleSeconds());
		vm.startPrank(address(rialto));
		rialto.processGGPRewards();

		assertEq(staking.getGGPRewards(nodeOp1), (nopClaim.getRewardsCycleTotal()));
		assertEq(staking.getLastRewardsCycleCompleted(nodeOp1), rewardsPool.getRewardsCycleCount());
		assertEq(staking.getAVAXValidatingHighWater(nodeOp1), staking.getAVAXValidating(nodeOp1));

		vm.expectRevert(abi.encodeWithSelector(ClaimNodeOp.RewardsAlreadyDistributedToStaker.selector, address(nodeOp1)));
		nopClaim.calculateAndDistributeRewards(nodeOp1, 200 ether);
		vm.stopPrank();
	}
}
