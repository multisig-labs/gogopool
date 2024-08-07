// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import "forge-std/Vm.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract MinipoolManagerTest is BaseTest {
	using FixedPointMathLib for uint256;
	int256 private index;
	address private nodeOp;
	uint256 private status;
	uint256 private ggpBondAmt;
	bytes private pubkey = hex"8c11f8f09e15059611fa549ba0019e26570b7331a15b0283ab966cc51538fa98d955b0b699943ca5e4225034485b9743";
	bytes private sig =
		hex"b8c820f854116b4916f64434732f9155cc4f2f8f31580b1cc8d831d5969dbda834f12c5028c7b17355d67ce6437616a60e67d7809699b99ddae7d91950547a3807a569d0f6fbcc9ec85e0ec3cb908d2d3d1d5ebd8f04424fe0dd9ff7b792e465";
	bytes private blsPubkeyAndSig = abi.encodePacked(pubkey, sig);
	event MinipoolLaunched(address indexed nodeID, bytes32 hardwareProvider, uint256 duration);

	function setUp() public override {
		super.setUp();
		nodeOp = getActorWithTokens("nodeOp", MAX_AMT, MAX_AMT);
	}

	function testGetTotalAVAXLiquidStakerAmt() public {
		address nodeOp2 = getActorWithTokens("nodeOp", MAX_AMT, MAX_AMT);
		address liqStaker1 = getActorWithTokens("liqStaker1", 4000 ether, 0);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: 4000 ether}();

		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(200 ether);
		MinipoolManager.Minipool memory mp1 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();
		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);
		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 1000 ether);

		vm.prank(nodeOp);
		MinipoolManager.Minipool memory mp2 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp2.nodeID);
		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 2000 ether);

		vm.startPrank(nodeOp2);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		MinipoolManager.Minipool memory mp3 = createMinipool(1000 ether, 1000 ether, 2 weeks);
		vm.stopPrank();
		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp3.nodeID);
		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 3000 ether);
	}

	function testCreateMinipool() public {
		address nodeID = address(1);
		uint256 duration = 2 weeks;
		uint256 delegationFee = 20_000;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 nopAvaxAmount = 1000 ether;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("provider"));

		uint256 vaultOriginalBalance = vault.balanceOf("MinipoolManager");

		//fail
		vm.startPrank(nodeOp);
		vm.expectRevert(MinipoolManager.InvalidNodeID.selector);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(address(0), duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		//fail
		vm.expectRevert(MinipoolManager.InvalidAVAXAssignmentRequest.selector);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, 2000 ether, blsPubkeyAndSig, hardwareProvider);

		//fail
		vm.expectRevert(MinipoolManager.InvalidAVAXAssignmentRequest.selector);
		minipoolMgr.createMinipool{value: 2000 ether}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		//fail
		vm.expectRevert(Staking.StakerNotFound.selector);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		//fail
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(50 ether);
		vm.expectRevert(MinipoolManager.InsufficientGGPCollateralization.selector);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		staking.stakeGGP(50 ether);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		//check vault balance to increase by 1000 ether
		assertEq(vault.balanceOf("MinipoolManager") - vaultOriginalBalance, nopAvaxAmount);

		int256 stakerIndex = staking.getIndexOf(address(nodeOp));
		Staking.Staker memory staker = staking.getStaker(stakerIndex);
		assertEq(staker.avaxStaked, avaxAssignmentRequest);
		assertEq(staker.avaxAssigned, nopAvaxAmount);
		assertEq(staker.avaxValidating, 0);
		assertTrue(staker.rewardsStartTime != 0);

		int256 minipoolIndex = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(minipoolIndex);

		assertEq(mp.nodeID, nodeID);
		assertEq(mp.status, uint256(MinipoolStatus.Prelaunch));
		assertEq(mp.duration, duration);
		assertEq(mp.delegationFee, delegationFee);
		assertEq(mp.avaxLiquidStakerAmt, avaxAssignmentRequest);
		assertEq(mp.avaxNodeOpAmt, nopAvaxAmount);
		assertEq(mp.owner, address(nodeOp));
		assertEq(mp.hardwareProvider, hardwareProvider);

		//check that making the same minipool with this id will reset the minipool data
		skip(5 seconds); //cancellation moratorium
		minipoolMgr.cancelMinipool(nodeID);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, 3 weeks, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);
		int256 minipoolIndex1 = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp1 = minipoolMgr.getMinipool(minipoolIndex1);
		assertEq(mp1.nodeID, nodeID);
		assertEq(mp1.status, uint256(MinipoolStatus.Prelaunch));
		assertEq(mp1.duration, 3 weeks);
		assertEq(mp1.delegationFee, delegationFee);
		assertEq(mp1.avaxLiquidStakerAmt, avaxAssignmentRequest);
		assertEq(mp1.avaxNodeOpAmt, nopAvaxAmount);
		assertEq(mp1.owner, address(nodeOp));
	}

	function testCancelMinipool() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		//will fail
		vm.expectRevert(MinipoolManager.MinipoolNotFound.selector);
		minipoolMgr.cancelMinipool(address(0));

		//will fail
		vm.expectRevert(MinipoolManager.OnlyOwner.selector);
		minipoolMgr.cancelMinipool(mp1.nodeID);

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(nodeOp);

		//will fail
		vm.expectRevert(MinipoolManager.CancellationTooEarly.selector);
		minipoolMgr.cancelMinipool(mp1.nodeID);

		skip(5 seconds); //cancellation moratorium

		vm.prank(nodeOp);
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.cancelMinipool(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Prelaunch));

		vm.startPrank(nodeOp);
		uint256 priorBalance = nodeOp.balance;
		minipoolMgr.cancelMinipool(mp1.nodeID);

		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);

		assertEq(mp1Updated.status, uint256(MinipoolStatus.Canceled));
		assertEq(staking.getAVAXStake(mp1Updated.owner), 0);
		assertEq(staking.getAVAXAssigned(mp1Updated.owner), 0);
		assertEq(staking.getAVAXValidating(mp1Updated.owner), 0);

		assertEq(nodeOp.balance - priorBalance, mp1Updated.avaxNodeOpAmt);
	}

	function testWithdrawMinipoolFunds() public {
		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		vm.startPrank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);
		bytes32 txID = keccak256("txid");
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);

		skip(duration);

		uint256 rewards = 10 ether;
		uint256 halfRewards = rewards / 2;
		deal(address(rialto), address(rialto).balance + rewards);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp1.nodeID, block.timestamp, rewards);
		uint256 percentage = dao.getMinipoolNodeCommissionFeePct();
		uint256 commissionFee = (percentage).mulWadDown(halfRewards);
		vm.stopPrank();

		vm.startPrank(nodeOp);
		uint256 priorBalanceNodeOp = nodeOp.balance;
		minipoolMgr.withdrawMinipoolFunds(mp1.nodeID);
		assertEq((nodeOp.balance - priorBalanceNodeOp), (1000 ether + halfRewards + commissionFee));
	}

	function testCanClaimAndInitiateStaking() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.canClaimAndInitiateStaking(mp1.nodeID);
		vm.stopPrank();

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.canClaimAndInitiateStaking(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Prelaunch));

		//will fail
		vm.prank(address(rialto));
		assertEq(minipoolMgr.canClaimAndInitiateStaking(mp1.nodeID), false);

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.prank(address(rialto));
		assertEq(minipoolMgr.canClaimAndInitiateStaking(mp1.nodeID), true);
	}

	function testClaimAndInitiateStaking() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;
		uint256 originalRialtoBalance = address(rialto).balance;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);
		vm.stopPrank();

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Prelaunch));

		//will fail
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.WithdrawAmountTooLarge.selector);
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		uint256 originalMMbalance = vault.balanceOf("MinipoolManager");

		uint256 originalGGAVAXBalance = ggAVAX.amountAvailableForStaking();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);
		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Launched));
		assertEq(address(rialto).balance - originalRialtoBalance, (depositAmt + avaxAssignmentRequest));
		assertEq(originalMMbalance - vault.balanceOf("MinipoolManager"), depositAmt);
		assertEq((originalGGAVAXBalance - ggAVAX.amountAvailableForStaking()), avaxAssignmentRequest);
	}

	function testRecordStakingStart() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		bytes32 txID = keccak256("txid");

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Launched));

		uint256 initialAVAXAssigned = staking.getAVAXAssigned(nodeOp);

		vm.prank(address(rialto));
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);
		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Staking));
		assertEq(mp1Updated.txID, txID);
		assertTrue(mp1Updated.startTime != 0);
		assertEq(staking.getAVAXValidating(nodeOp), avaxAssignmentRequest);
		assertEq(staking.getAVAXAssigned(nodeOp), initialAVAXAssigned);
		assertEq(staking.getAVAXValidatingHighWater(nodeOp), avaxAssignmentRequest);
	}

	function testRecordStakingStartInvalidStartTime() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;
		uint256 liquidStakerAmt = 1200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", uint128(liquidStakerAmt), 0);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: liquidStakerAmt}();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		bytes32 txID = keccak256("txid");

		vm.expectRevert(MinipoolManager.InvalidStartTime.selector);
		vm.prank(address(rialto));
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp + 1);
	}

	function testRecordStakingEnd() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		bytes32 txID = keccak256("txid");
		vm.prank(address(rialto));
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Staking));

		vm.startPrank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidEndTime.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);

		skip(duration);

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEnd{value: 0 ether}(mp1.nodeID, block.timestamp, 0 ether);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		uint256 halfRewards = rewards / 2;
		deal(address(rialto), address(rialto).balance + rewards);

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt + rewards}(mp1.nodeID, block.timestamp, 9 ether);

		//right now rewards are split equally between the node op and user. User provided half the total funds in this test
		minipoolMgr.recordStakingEnd{value: validationAmt + rewards}(mp1.nodeID, block.timestamp, rewards);
		uint256 commissionFee = (halfRewards * 15) / 100;
		//checking the node operators rewards are correct
		assertEq(vault.balanceOf("MinipoolManager"), (depositAmt + halfRewards + commissionFee));

		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Withdrawable));
		assertEq(mp1Updated.avaxTotalRewardAmt, rewards);
		assertTrue(mp1Updated.endTime != 0);
		assertEq(mp1Updated.avaxNodeOpRewardAmt, (halfRewards + commissionFee));
		assertEq(mp1Updated.avaxLiquidStakerRewardAmt, (halfRewards - commissionFee));

		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		assertEq(staking.getAVAXAssigned(mp1Updated.owner), 0);
		assertEq(staking.getAVAXValidating(mp1Updated.owner), 0);
		assertEq(staking.getAVAXValidatingHighWater(mp1Updated.owner), avaxAssignmentRequest);
	}

	function testRecordStakingEndWithSlash() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		bytes32 txID = keccak256("txid");
		vm.prank(address(rialto));
		minipoolMgr.recordStakingStart(mp1.nodeID, txID, block.timestamp);

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Error));
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Staking));

		vm.startPrank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidEndTime.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);

		skip(duration);

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEnd{value: 0 ether}(mp1.nodeID, block.timestamp, 0 ether);

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 9 ether);

		minipoolMgr.recordStakingEnd{value: validationAmt}(mp1.nodeID, block.timestamp, 0 ether);

		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);

		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Withdrawable));
		assertEq(mp1Updated.avaxTotalRewardAmt, 0);

		assertGt(mp1Updated.ggpSlashAmt, 0);
		assertLt(staking.getGGPStake(mp1Updated.owner), ggpStakeAmt);
	}

	function testRecordStakingEndWithSlashingMoreThanTheyStaked() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		//Manually set their GGP stake to 1, to ensure that the GGP slash amount will be more than the GGP staked.
		int256 stakerIndex = staking.getIndexOf(address(nodeOp));
		store.subUint(keccak256(abi.encodePacked("staker.item", stakerIndex, ".ggpStaked")), ggpStakeAmt - 1);

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		rialto.processMinipoolStart(mp1.nodeID);

		skip(duration);

		MinipoolManager.Minipool memory mp1Updated = rialto.processMinipoolEndWithoutRewards(mp1.nodeID);

		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);

		assertEq(mp1Updated.avaxTotalRewardAmt, 0);
		assertTrue(mp1Updated.endTime != 0);

		assertEq(mp1Updated.avaxNodeOpRewardAmt, 0);
		assertEq(mp1Updated.avaxLiquidStakerRewardAmt, 0);

		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		assertEq(staking.getAVAXAssigned(mp1Updated.owner), 0);

		// if the slash amt is more than what they had staked, it gets set to what the amt they had staked
		assertEq(mp1Updated.ggpSlashAmt, 1);

		// all of their ggp was slashed
		assertEq(staking.getGGPStake(mp1Updated.owner), 0);
	}

	function testRecordStakingError() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp1.nodeID);

		bytes32 errorCode = "INVALID_NODEID";

		//will fail
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.recordStakingError{value: validationAmt}(mp1.nodeID, errorCode);

		//will fail
		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Prelaunch));

		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.recordStakingError{value: validationAmt}(mp1.nodeID, errorCode);

		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Launched));

		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingError{value: 0 ether}(mp1.nodeID, errorCode);

		vm.prank(address(rialto));
		minipoolMgr.recordStakingError{value: validationAmt}(mp1.nodeID, errorCode);

		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);

		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Error));
		assertEq(mp1Updated.avaxTotalRewardAmt, 0);
		assertEq(mp1Updated.errorCode, errorCode);
		assertEq(mp1Updated.avaxNodeOpRewardAmt, 0);
		assertEq(mp1Updated.avaxLiquidStakerRewardAmt, 0);

		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		assertEq(staking.getAVAXAssigned(mp1Updated.owner), 0);
		assertEq(staking.getAVAXValidating(mp1Updated.owner), 0);
		assertEq(staking.getAVAXValidatingHighWater(mp1Updated.owner), 0);

		// withdraw funds to move minipool to finished state
		uint256 nodeOpStartingBalance = nodeOp.balance;

		vm.prank(nodeOp);
		minipoolMgr.withdrawMinipoolFunds(mp1.nodeID);

		assertEq(nodeOp.balance, nodeOpStartingBalance + depositAmt);

		mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Finished));
	}

	function testCancelMinipoolByMultisig() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		uint256 priorBalance = nodeOp.balance;

		bytes32 errorCode = "INVALID_NODEID";

		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.cancelMinipoolByMultisig(mp1.nodeID, errorCode);

		int256 minipoolIndex = minipoolMgr.getIndexOf(mp1.nodeID);
		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Staking));

		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.cancelMinipoolByMultisig(mp1.nodeID, errorCode);

		store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Prelaunch));

		vm.prank(address(rialto));
		minipoolMgr.cancelMinipoolByMultisig(mp1.nodeID, errorCode);

		MinipoolManager.Minipool memory mp1Updated = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1Updated.status, uint256(MinipoolStatus.Canceled));
		assertEq(mp1Updated.errorCode, errorCode);

		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		assertEq(staking.getAVAXAssigned(mp1Updated.owner), 0);
		assertEq(staking.getAVAXStake(mp1Updated.owner), 0);

		assertEq(nodeOp.balance - priorBalance, depositAmt);
	}

	function testExpectedRewards() public {
		uint256 amt = minipoolMgr.getExpectedAVAXRewardsAmt(365 days, 1_000 ether);
		assertEq(amt, 100 ether);
		amt = minipoolMgr.getExpectedAVAXRewardsAmt((365 days / 2), 1_000 ether);
		assertEq(amt, 50 ether);
		amt = minipoolMgr.getExpectedAVAXRewardsAmt((365 days / 3), 1_000 ether);
		assertEq(amt, 33333333333333333333);

		// Set 5% annual expected rewards rate
		vm.prank(address(rialto));
		dao.setExpectedAVAXRewardsRate(5e16);
		amt = minipoolMgr.getExpectedAVAXRewardsAmt(365 days, 1_000 ether);
		assertEq(amt, 50 ether);
		amt = minipoolMgr.getExpectedAVAXRewardsAmt((365 days / 3), 1_000 ether);
		assertEq(amt, 16.666666666666666666 ether);
	}

	function testGetMinipool() public {
		address nodeID = address(1);
		uint256 duration = 2 weeks;
		uint256 delegationFee = 20_000;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 nopAvaxAmount = 1000 ether;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("hardwareProvider"));

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);

		int256 minipoolIndex = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(minipoolIndex);

		assertEq(mp.nodeID, nodeID);
		assertEq(mp.status, uint256(MinipoolStatus.Prelaunch));
		assertEq(mp.duration, duration);
		assertEq(mp.delegationFee, delegationFee);
		assertEq(mp.avaxLiquidStakerAmt, avaxAssignmentRequest);
		assertEq(mp.avaxNodeOpAmt, nopAvaxAmount);
		assertEq(mp.owner, address(nodeOp));
		assertEq(mp.hardwareProvider, hardwareProvider);
	}

	function testGetMinipools() public {
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 depositAmt = 1000 ether;
		uint128 ggpStakeAmt = 100 ether;

		vm.startPrank(nodeOp);
		MinipoolManager.Minipool memory mp;
		for (uint256 i = 0; i < 10; i++) {
			ggp.approve(address(staking), ggpStakeAmt);
			staking.stakeGGP(ggpStakeAmt);
			mp = createMinipool(depositAmt, avaxAssignmentRequest, 14 days);
		}
		vm.stopPrank();

		assertEq(mp.index, 9);

		MinipoolManager.Minipool[] memory mps = minipoolMgr.getMinipools(MinipoolStatus.Prelaunch, 0, 0);
		assertEq(mps.length, 10);

		for (uint256 i = 0; i < 5; i++) {
			int256 minipoolIndex = minipoolMgr.getIndexOf(mps[i].nodeID);
			store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".status")), uint256(MinipoolStatus.Launched));
		}
		MinipoolManager.Minipool[] memory mps1 = minipoolMgr.getMinipools(MinipoolStatus.Launched, 0, 0);
		assertEq(mps1.length, 5);
	}

	function testGetMinipoolCount() public {
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 depositAmt = 1000 ether;
		uint128 ggpStakeAmt = 100 ether;

		vm.startPrank(nodeOp);
		for (uint256 i = 0; i < 10; i++) {
			ggp.approve(address(staking), ggpStakeAmt);
			staking.stakeGGP(ggpStakeAmt);
			createMinipool(depositAmt, avaxAssignmentRequest, 14 days);
		}
		vm.stopPrank();
		assertEq(minipoolMgr.getMinipoolCount(), 10);
	}

	function testCalculateGGPSlashAmt() public {
		vm.prank(address(rialto));
		oracle.setGGPPriceInAVAX(1 ether, block.timestamp);
		uint256 slashAmt = minipoolMgr.calculateGGPSlashAmt(100 ether);
		assertEq(slashAmt, 100 ether);

		vm.prank(address(rialto));
		oracle.setGGPPriceInAVAX(0.5 ether, block.timestamp);
		slashAmt = minipoolMgr.calculateGGPSlashAmt(100 ether);
		assertEq(slashAmt, 200 ether);

		vm.prank(address(rialto));
		oracle.setGGPPriceInAVAX(3 ether, block.timestamp);
		slashAmt = minipoolMgr.calculateGGPSlashAmt(100 ether);
		assertEq(slashAmt, 33333333333333333333);
	}

	function testFullCycle_WithUserFunds() public {
		uint256 originalRialtoBalance = address(rialto).balance;
		address lilly = getActorWithTokens("lilly", MAX_AMT, MAX_AMT);
		vm.prank(lilly);
		ggAVAX.depositAVAX{value: MAX_AMT}();
		assertEq(lilly.balance, 0);

		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);

		vm.startPrank(address(rialto));

		minipoolMgr.claimAndInitiateStaking(mp.nodeID);

		assertEq(vault.balanceOf("MinipoolManager"), 0);
		assertEq(address(rialto).balance - originalRialtoBalance, validationAmt);

		bytes32 txID = keccak256("txid");
		minipoolMgr.recordStakingStart(mp.nodeID, txID, block.timestamp);

		vm.expectRevert(MinipoolManager.InvalidEndTime.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt}(mp.nodeID, block.timestamp, 0 ether);

		skip(duration);

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: 0 ether}(mp.nodeID, block.timestamp, 0 ether);

		uint256 rewards = 10 ether;

		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, 9 ether);

		//right now rewards are split equally between the node op and user. User provided half the total funds in this test
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, 10 ether);
		uint256 commissionFee = (5 ether * 15) / 100;
		//checking the node operators rewards are correct
		assertEq(vault.balanceOf("MinipoolManager"), (1005 ether + commissionFee));

		vm.stopPrank();

		///test that the node op can withdraw the funds they are due
		vm.startPrank(nodeOp);
		uint256 priorBalance_nodeOp = nodeOp.balance;

		minipoolMgr.withdrawMinipoolFunds(mp.nodeID);
		assertEq((nodeOp.balance - priorBalance_nodeOp), (1005 ether + commissionFee));
	}

	function testFullCycle_Error() public {
		address lilly = getActorWithTokens("lilly", MAX_AMT, MAX_AMT);
		vm.prank(lilly);
		ggAVAX.depositAVAX{value: MAX_AMT}();
		assertEq(lilly.balance, 0);

		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;
		uint256 amountAvailForStaking = ggAVAX.amountAvailableForStaking();
		uint256 originalRialtoBalance = address(rialto).balance;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);

		vm.startPrank(address(rialto));

		minipoolMgr.claimAndInitiateStaking(mp.nodeID);

		assertEq(vault.balanceOf("MinipoolManager"), 0);
		assertEq(address(rialto).balance - originalRialtoBalance, validationAmt);
		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), avaxAssignmentRequest);

		// Assume something goes wrong and we are unable to launch a minipool

		bytes32 errorCode = "INVALID_NODEID";

		// Expect revert on sending wrong amt
		vm.expectRevert(MinipoolManager.InvalidAmount.selector);
		minipoolMgr.recordStakingError{value: 0}(mp.nodeID, errorCode);

		// Now send correct amt
		minipoolMgr.recordStakingError{value: validationAmt}(mp.nodeID, errorCode);
		assertEq(address(rialto).balance - originalRialtoBalance, 0);
		// NodeOps funds should be back in vault
		assertEq(vault.balanceOf("MinipoolManager"), depositAmt);
		// Liq stakers funds should be returned
		assertEq(ggAVAX.amountAvailableForStaking(), amountAvailForStaking);
		assertEq(minipoolMgr.getTotalAVAXLiquidStakerAmt(), 0);

		mp = minipoolMgr.getMinipool(mp.index);
		assertEq(mp.status, uint256(MinipoolStatus.Error));
		assertEq(mp.errorCode, errorCode);
	}

	function testCycleMinipoolInvalidState() public {
		uint256 duration = 4 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		// stake ggp
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		// deposit liquid staker funds
		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		// launch minipool
		rialto.processMinipoolStart(mp.nodeID);

		// give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		skip(duration / 2);

		// end the minipool
		rialto.processMinipoolEndWithRewards(mp.nodeID);

		// attempt to cycle, but state will be invalid
		vm.startPrank(address(rialto));
		vm.expectRevert(MinipoolManager.InvalidStateTransition.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);
		vm.stopPrank();
	}

	function testCycleMinipoolDurationExceeded() public {
		uint256 duration = 4 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 200 ether;

		// stake ggp
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		// deposit liquid staker funds
		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		// launch minipool
		rialto.processMinipoolStart(mp.nodeID);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		skip(duration);

		// attempt to cycle when block.timestamp equals duration
		vm.startPrank(address(rialto));
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);
		vm.stopPrank();

		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		assertEq(mp.status, uint256(MinipoolStatus.Withdrawable));
	}

	function testCycleMinipool() public {
		uint256 duration = 4 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		// Enough to start but not to re-stake, we will add more later
		uint128 ggpStakeAmt = 100 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		rialto.processMinipoolStart(mp.nodeID);

		skip(duration / 2);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		// Fail due to invalid multisig
		vm.expectRevert(MinipoolManager.InvalidMultisigAddress.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);

		// Fail due to under collat
		vm.prank(address(rialto));
		vm.expectRevert(MinipoolManager.InsufficientGGPCollateralization.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);

		// Add a bit more collateral to cover the compounding rewards
		vm.prank(nodeOp);
		staking.stakeGGP(1 ether);

		// Pay out the rewards and cycle
		vm.prank(address(rialto));
		startMeasuringGas("testGas-recordStakingEndAndCycle");
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);
		stopMeasuringGas();

		MinipoolManager.Minipool memory mpCompounded = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		assertEq(mpCompounded.status, uint256(MinipoolStatus.Launched));
		assertGt(mpCompounded.avaxNodeOpAmt, mp.avaxNodeOpAmt);
		assertGt(mpCompounded.avaxNodeOpAmt, mp.avaxNodeOpInitialAmt);
		assertGt(mpCompounded.avaxLiquidStakerAmt, mp.avaxLiquidStakerAmt);
		assertEq(staking.getAVAXStake(mp.owner), mpCompounded.avaxNodeOpAmt);
		assertEq(staking.getAVAXAssigned(mp.owner), mpCompounded.avaxLiquidStakerAmt);
		assertEq(mpCompounded.startTime, 0);
		assertGt(mpCompounded.initialStartTime, 0);
	}

	function testCycleMinipoolInsufficientAvailableForStaking() public {
		uint128 depositAmt = 10_000 ether;
		// liquid staker deposit 10,000 total assets
		// set collateral rate to 30%,
		// 		Total Assets 	-> 10,000
		// 		Reserve 			-> 3,000

		// withdraw for staking 7000
		// liquid staker withdraws 1000
		// 		Total Assets 		-> 9000
		// 		Reserve 				-> 2700

		// now `amountAvailableForStaking` is -700 but returns 0

		// new money deposited will be counted towards the reserve, and won't increase
		// 	amount available for staking
		// If this happens before a minipool cycles, the recreate will fail

		// deposit 10,000 avax
		address staker = getActorWithTokens("staker", depositAmt + 1000 ether, 0 ether);
		vm.startPrank(staker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, staker);
		vm.stopPrank();

		// set reserve rate
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.3 ether); // 30% collateral held in reserve

		assertEq(ggAVAX.amountAvailableForStaking(), 7000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 3000 ether);

		// withdraw 6000 ether for staking artificially
		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(6000 ether);

		// create a minipool and withdraw an additional 1000 ether
		// 7000 total out for staking
		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 300 ether);
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 300 ether);
		staking.stakeGGP(300 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 28 days);
		vm.stopPrank();
		rialto.processMinipoolStart(mp.nodeID);

		// liquid stakers withdraw assets
		vm.prank(staker);
		ggAVAX.withdraw(1000 ether, staker, staker);
		assertEq(ggAVAX.totalAssets(), 9000 ether);
		assertEq(ggAVAX.stakingTotalAssets(), 7000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 2700 ether);

		// now cycle a minipool
		// fails because there's not enough avax for staking
		uint256 totalAVAX = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, totalAVAX);
		skip(14 days);
		vm.prank(address(rialto));
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalAVAX + rewards}(mp.nodeID, block.timestamp, rewards);
	}

	// Test that cycling can complete even when the ggAVAX deposit pool is empty
	function testCycleMinipoolZeroGGAVAXReserve() public {
		uint128 depositAmt = 1000 ether;

		// deposit 1000 avax
		address staker = getActorWithTokens("staker", depositAmt, 0 ether);
		vm.startPrank(staker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, staker);
		vm.stopPrank();

		// set reserve rate
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0 ether); // 30% collateral held in reserve

		assertEq(ggAVAX.amountAvailableForStaking(), 1000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 0);

		// create a minipool to withdraw 1000 avax
		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 300 ether);
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 300 ether);
		staking.stakeGGP(300 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 28 days);
		vm.stopPrank();
		rialto.processMinipoolStart(mp.nodeID);

		assertEq(ggAVAX.totalAssets(), 1000 ether);
		assertEq(ggAVAX.stakingTotalAssets(), 1000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 0);

		// now cycle a minipool
		uint256 totalAVAX = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, totalAVAX);

		skip(14 days);
		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		// minipool has cycled properly
		assertEq(mp.status, uint256(MinipoolStatus.Launched));

		// and the ggAVAX contract is still empty
		uint256 liquidStakerRewards = (rewards / 2) - (rewards / 2).mulWadDown(dao.getMinipoolNodeCommissionFeePct());
		assertEq(ggAVAX.stakingTotalAssets(), 1000 ether + liquidStakerRewards);
		assertEq(ggAVAX.amountAvailableForStaking(), 0);
	}

	function testCycleMinipoolUnderCollateralized() public {
		uint128 depositAmt = 1000 ether;

		// deposit 1000 avax
		address staker = getActorWithTokens("staker", depositAmt, 0 ether);
		vm.startPrank(staker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, staker);
		vm.stopPrank();

		// set reserve rate
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0 ether); // 0% collateral held in reserve

		assertEq(ggAVAX.amountAvailableForStaking(), 1000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 0);

		// create a minipool
		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 300 ether);
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 300 ether);
		staking.stakeGGP(300 ether);
		MinipoolManager.Minipool memory mp = createMinipool(1000 ether, 1000 ether, 28 days);
		vm.stopPrank();
		rialto.processMinipoolStart(mp.nodeID);

		assertEq(ggAVAX.totalAssets(), 1000 ether);
		assertEq(ggAVAX.stakingTotalAssets(), 1000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 0);
		assertEq(staking.getCollateralizationRatio(nodeOp), 0.3 ether);

		vm.prank(address(rialto));
		oracle.setGGPPriceInAVAX(0.3 ether, block.timestamp);

		assertEq(staking.getCollateralizationRatio(nodeOp), 0.09 ether);

		uint256 totalAVAX = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, totalAVAX);
		skip(14 days);

		// cycling will error with insufficient collateralization
		vm.startPrank(address(rialto));
		vm.expectRevert(MinipoolManager.InsufficientGGPCollateralization.selector);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalAVAX + rewards}(mp.nodeID, block.timestamp, rewards);
		vm.stopPrank();
	}

	function testCycleMinipoolCommission() public {
		store.setUint(keccak256("ProtocolDAO.MinipoolNodeCommissionFeePct"), 0.15 ether);

		uint256 duration = 4 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 140 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		rialto.processMinipoolStart(mp.nodeID);

		skip(duration / 2);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		// Pay out the rewards and cycle
		vm.prank(address(rialto));
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);

		MinipoolManager.Minipool memory mpCompounded = minipoolMgr.getMinipoolByNodeID(mp.nodeID);

		uint256 expectedLiquidStakerAmt = depositAmt + rewards / 2 - ((rewards / 2).mulWadDown(dao.getMinipoolNodeCommissionFeePct()));

		// NOTE: Subsequent tests demonstrate incorrectly calculated commission fee.
		// Requires logic correction before reactivation.
		assertEq(mpCompounded.avaxNodeOpAmt, expectedLiquidStakerAmt);
		assertEq(mpCompounded.avaxNodeOpRewardAmt, 0);

		assertEq(mpCompounded.avaxLiquidStakerAmt, expectedLiquidStakerAmt);
		assertEq(mpCompounded.avaxLiquidStakerRewardAmt, 0);
	}

	function testCycleMinipoolCommissionZero() public {
		store.setUint(keccak256("ProtocolDAO.MinipoolNodeCommissionFeePct"), 0 ether);

		uint256 duration = 4 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 validationAmt = depositAmt + avaxAssignmentRequest;
		uint128 ggpStakeAmt = 140 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		rialto.processMinipoolStart(mp.nodeID);

		skip(duration / 2);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		// Pay out the rewards and cycle
		vm.prank(address(rialto));
		minipoolMgr.recordStakingEndThenMaybeCycle{value: validationAmt + rewards}(mp.nodeID, block.timestamp, rewards);

		MinipoolManager.Minipool memory mpCompounded = minipoolMgr.getMinipoolByNodeID(mp.nodeID);

		uint256 evenSplitAmt = depositAmt + rewards / 2;

		assertEq(mpCompounded.avaxNodeOpAmt, evenSplitAmt);
		assertEq(mpCompounded.avaxNodeOpRewardAmt, 0);

		assertEq(mpCompounded.avaxLiquidStakerAmt, evenSplitAmt);
		assertEq(mpCompounded.avaxLiquidStakerRewardAmt, 0);
	}

	function testBondZeroGGP() public {
		vm.startPrank(nodeOp);
		address nodeID = randAddress();
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 delegationFee = 20_000;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("hardwareProvider"));

		vm.expectRevert(Staking.StakerNotFound.selector); //no ggp will be staked under the address, so it will fail upon lookup
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, 14 days, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);
		vm.stopPrank();
	}

	function testUndercollateralized() public {
		vm.startPrank(nodeOp);
		address nodeID = randAddress();
		uint256 avaxAmt = 1000 ether;
		uint256 ggpStakeAmt = 50 ether; // 5%
		uint256 delegationFee = 20_000;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("hardwareProvider"));

		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		vm.expectRevert(MinipoolManager.InsufficientGGPCollateralization.selector); //no ggp will be staked under the address, so it will fail upon lookup
		minipoolMgr.createMinipool{value: avaxAmt}(nodeID, 14 days, delegationFee, avaxAmt, blsPubkeyAndSig, hardwareProvider);
		vm.stopPrank();
	}

	function testEmptyState() public {
		vm.startPrank(nodeOp);
		index = minipoolMgr.getIndexOf(ZERO_ADDRESS);
		assertEq(index, -1);
		MinipoolManager.Minipool memory mp;
		mp = minipoolMgr.getMinipool(index);
		assertEq(mp.nodeID, ZERO_ADDRESS);
		vm.stopPrank();
	}

	// Maybe we have testGas... tests that just do a single important operation
	// to make it easier to monitor gas usage
	function testGasCreateMinipool() public {
		uint256 duration = 2 weeks;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		startMeasuringGas("testGasCreateMinipool");
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		stopMeasuringGas();
		vm.stopPrank();

		index = minipoolMgr.getIndexOf(mp.nodeID);
		assertFalse(index == -1);
	}

	function testCreateAndGetMany() public {
		address nodeID;
		uint256 avaxAssignmentRequest = 1000 ether;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("provider"));

		for (uint256 i = 0; i < 10; i++) {
			nodeID = randAddress();
			vm.startPrank(nodeOp);
			ggp.approve(address(staking), 100 ether);
			staking.stakeGGP(100 ether);
			minipoolMgr.createMinipool{value: 1000 ether}(nodeID, 14 days, 20_000, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);
			vm.stopPrank();
		}
		index = minipoolMgr.getIndexOf(nodeID);
		assertEq(index, 9);
	}

	function testDurationOutOfBounds() public {
		address nodeID = randAddress();
		uint256 delegationFee = 20_000;
		uint128 nodeOpAmt = 1000 ether;
		uint128 request = nodeOpAmt;
		uint128 stakeAmt = 100 ether;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("provider"));

		nodeOp = getActorWithTokens("nodeOp", nodeOpAmt, stakeAmt);

		uint256 duration;

		vm.startPrank(nodeOp);

		ggp.approve(address(staking), stakeAmt);
		staking.stakeGGP(stakeAmt);

		// too low
		duration = dao.getMinipoolMinDuration() - 1;
		vm.expectRevert(MinipoolManager.DurationOutOfBounds.selector);
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, duration, delegationFee, request, blsPubkeyAndSig, hardwareProvider);

		// too high
		duration = dao.getMinipoolMaxDuration() + 1;
		vm.expectRevert(MinipoolManager.DurationOutOfBounds.selector);
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, duration, delegationFee, request, blsPubkeyAndSig, hardwareProvider);

		// just right
		duration = dao.getMinipoolCycleDuration();
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, duration, delegationFee, request, blsPubkeyAndSig, hardwareProvider);
		vm.stopPrank();

		index = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(index);

		assertEq(mp.duration, duration);
	}

	function testOneCycleWithDelay() public {
		fillLiquidStaker();

		uint256 duration = dao.getMinipoolCycleDuration();
		uint256 delay = 2 days;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);
		MinipoolManager.Minipool memory mp;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 200 ether);
		staking.stakeGGP(200 ether);
		mp = createMinipool(1000 ether, 1000 ether, duration);
		vm.stopPrank();

		// complete one cycle
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp.nodeID);

		// some delay
		skip(dao.getMinipoolCycleDuration() + delay);

		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		assertEq(mp.status, uint256(MinipoolStatus.Withdrawable));
		assertEq(mp.errorCode, bytes32(""));
	}

	function testMultipleCycleWithDelay() public {
		fillLiquidStaker();

		uint256 duration = dao.getMinipoolCycleDuration() * 2; // two minipool periods
		uint256 delay = 2 days;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);
		MinipoolManager.Minipool memory mp;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 200 ether);
		staking.stakeGGP(200 ether);
		mp = createMinipool(1000 ether, 1000 ether, duration);
		vm.stopPrank();

		// complete one cycle
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp.nodeID);

		// some delay in running the minipool.
		skip(dao.getMinipoolCycleDuration() + delay);

		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		assertEq(mp.errorCode, bytes32("EC1"));
		assertEq(mp.status, uint(MinipoolStatus.Withdrawable));
	}

	// duration for two cycles with delay within tolerance
	function testMultipleCycleSmallDelay() public {
		fillLiquidStaker();

		uint256 duration = dao.getMinipoolCycleDuration() * 2;
		uint256 delay = 1 days;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);
		MinipoolManager.Minipool memory mp;

		// create minipool
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 200 ether);
		staking.stakeGGP(200 ether);
		mp = createMinipool(1000 ether, 1000 ether, duration);
		vm.stopPrank();

		// complete one cycle
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp.nodeID);

		// some delay in running the minipool.
		skip(dao.getMinipoolCycleDuration() + delay);

		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		assertEq(mp.status, uint(MinipoolStatus.Launched));
		assertEq(mp.errorCode, bytes32(""));
	}

	function testOneCycleLongerDuration() public {
		fillLiquidStaker();

		// duration slightly longer than default cycle duration
		uint256 duration = dao.getMinipoolCycleDuration() + 1 days;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);
		MinipoolManager.Minipool memory mp;

		// create minipool
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 200 ether);
		staking.stakeGGP(200 ether);
		mp = createMinipool(1000 ether, 1000 ether, duration);
		vm.stopPrank();

		// complete one cycle
		vm.startPrank(address(rialto));
		rialto.processMinipoolStart(mp.nodeID);

		skip(dao.getMinipoolCycleDuration());

		// shouldn't recycle, and also shouldn't error
		mp = rialto.processMinipoolEndWithRewards(mp.nodeID);

		assertEq(mp.status, uint(MinipoolStatus.Withdrawable));
		// this returns with an error code, but this situation won't happen through our FE,
		//   since we will only be setting duration on 14 day increments
		assertEq(mp.errorCode, bytes32("EC1"));
	}

	function testMultipleCycleNoDelay() public {
		fillLiquidStaker();

		// duration slightly longer than default cycle duration
		uint256 duration = dao.getMinipoolCycleDuration() * 3;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);
		MinipoolManager.Minipool memory mp;
		bytes32 txID;

		// create minipool
		vm.startPrank(nodeOp);
		ggp.approve(address(staking), 200 ether);
		staking.stakeGGP(200 ether);
		mp = createMinipool(1000 ether, 1000 ether, duration);
		vm.stopPrank();

		// start first cycle
		rialto.processMinipoolStart(mp.nodeID);
		skip(dao.getMinipoolCycleDuration()); // 1
		mp = rialto.processMinipoolEndWithRewards(mp.nodeID); // start 2
		assertEq(mp.status, uint(MinipoolStatus.Launched));

		// start cycle two
		vm.startPrank(address(rialto));
		txID = keccak256(abi.encodePacked(mp.nodeID, blockhash(block.timestamp)));
		minipoolMgr.recordStakingStart(mp.nodeID, txID, block.timestamp);
		skip(dao.getMinipoolCycleDuration()); // 2
		mp = rialto.processMinipoolEndWithRewards(mp.nodeID); // start 3
		assertEq(mp.status, uint(MinipoolStatus.Launched));

		// start cycle thee
		txID = keccak256(abi.encodePacked(mp.nodeID, blockhash(block.timestamp)));
		minipoolMgr.recordStakingStart(mp.nodeID, txID, block.timestamp);
		skip(dao.getMinipoolCycleDuration()); // 3
		mp = rialto.processMinipoolEndWithRewards(mp.nodeID); // end 4

		assertEq(mp.status, uint(MinipoolStatus.Withdrawable));
		assertEq(mp.errorCode, bytes32(""));
	}

	function testBlskeys() public {
		address nodeID = address(1);
		uint256 duration = 2 weeks;
		uint256 delegationFee = 20_000;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint256 nopAvaxAmount = 1000 ether;
		bytes32 hardwareProvider = keccak256(abi.encodePacked("provider"));
		fillLiquidStaker();

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(100 ether);
		minipoolMgr.createMinipool{value: nopAvaxAmount}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);
		int256 minipoolIndex = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp.blsPubkeyAndSig, blsPubkeyAndSig);
	}

	function fillLiquidStaker() internal {
		address liqStaker = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker);
		ggAVAX.depositAVAX{value: MAX_AMT}();
	}

	// Proving that a minipool can start if it is under collat ratio if
	// the minipool falls below the collat ratio in the queue. But it will
	// be kicked out if cycling
	function testClaimAndInitiateStakingNotEnoughColl() public {
		uint256 duration = 30 days;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 100 ether;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory minipool_1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		// collat ratio falls below the min
		vm.startPrank(guardian);
		int256 stakerIndex = staking.requireValidStaker(nodeOp);
		store.setUint(keccak256(abi.encodePacked("staker.item", stakerIndex, ".ggpStaked")), 50 ether);
		assertLt(staking.getCollateralizationRatio(nodeOp), dao.getMinCollateralizationRatio()); // alice's collateralization ratio is lower than minCollateralizationRatio
		vm.stopPrank();

		int256 minipoolIndex = minipoolMgr.getIndexOf(minipool_1.nodeID);
		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();
		rialto.processMinipoolStart(minipool_1.nodeID);

		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp.status, uint(MinipoolStatus.Staking));

		skip(15 days);

		vm.expectRevert(MinipoolManager.InsufficientGGPCollateralization.selector);
		rialto.processMinipoolEndWithRewards(minipool_1.nodeID);

		rialto.processErroredMinipoolEndWithRewards(minipool_1.nodeID);
	}

	function testSetBLSKeys() public {
		uint256 duration = 15 days;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		uint128 ggpStakeAmt = 100 ether;

		nodeOp = getActorWithTokens("nodeOp", 1000 ether, 200 ether);

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory minipool_1 = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		int256 minipoolIndex = minipoolMgr.getIndexOf(minipool_1.nodeID);

		// make sure only the guardian can set the BLS keys
		vm.expectRevert(MinipoolManager.OnlyRole.selector);
		minipoolMgr.setBLSKeys(minipool_1.nodeID, blsPubkeyAndSig);

		vm.startPrank(guardian);
		dao.setRole("Relauncher", address(guardian), true);
		minipoolMgr.setBLSKeys(minipool_1.nodeID, blsPubkeyAndSig);
		MinipoolManager.Minipool memory mp1 = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp1.blsPubkeyAndSig, blsPubkeyAndSig);

		dao.setRole("Relauncher", address(guardian), false);
		vm.expectRevert(MinipoolManager.OnlyRole.selector);
		minipoolMgr.setBLSKeys(minipool_1.nodeID, bytes("0"));
		MinipoolManager.Minipool memory mp2 = minipoolMgr.getMinipool(minipoolIndex);
		assertEq(mp2.blsPubkeyAndSig, blsPubkeyAndSig);
	}

	function testMinipoolLaunchEventOnlyOnFirstLaunch() public {
		uint256 duration = dao.getMinipoolCycleDuration() * 3;
		uint256 depositAmt = 1000 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		// Enough to start but not to re-stake, we will add more later
		uint128 ggpStakeAmt = 120 ether;

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), MAX_AMT);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(depositAmt, avaxAssignmentRequest, duration);
		vm.stopPrank();

		address liqStaker1 = getActorWithTokens("liqStaker1", MAX_AMT, MAX_AMT);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: MAX_AMT}();

		vm.expectEmit(address(minipoolMgr));
		emit MinipoolLaunched(mp.nodeID, mp.hardwareProvider, duration);
		rialto.processMinipoolStart(mp.nodeID);

		skip(duration / 3);

		// Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(address(rialto), address(rialto).balance + rewards);

		// Add a bit more collateral to cover the compounding rewards
		vm.prank(nodeOp);
		staking.stakeGGP(1 ether);

		// Pay out the rewards and cycle
		vm.startPrank(address(rialto));

		vm.recordLogs();

		rialto.processMinipoolEndWithRewards(mp.nodeID);

		Vm.Log[] memory entries = vm.getRecordedLogs();

		assertEq(entries.length, 11);

		MinipoolManager.Minipool memory mpCompounded = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		assertEq(mpCompounded.status, uint256(MinipoolStatus.Launched));
		assertGt(mpCompounded.avaxNodeOpAmt, mp.avaxNodeOpAmt);
		assertGt(mpCompounded.avaxNodeOpAmt, mp.avaxNodeOpInitialAmt);
		assertGt(mpCompounded.avaxLiquidStakerAmt, mp.avaxLiquidStakerAmt);
		assertEq(staking.getAVAXStake(mp.owner), mpCompounded.avaxNodeOpAmt);
		assertEq(staking.getAVAXAssigned(mp.owner), mpCompounded.avaxLiquidStakerAmt);
		assertEq(mpCompounded.startTime, 0);
		assertGt(mpCompounded.initialStartTime, 0);

		// stake minipool again
		bytes32 txID = keccak256(abi.encodePacked(mpCompounded.nodeID, blockhash(block.timestamp)));
		minipoolMgr.recordStakingStart(mpCompounded.nodeID, txID, block.timestamp);

		skip(duration / 3);

		vm.recordLogs();

		rialto.processMinipoolEndWithRewards(mp.nodeID);
		entries = vm.getRecordedLogs();
		assertEq(entries.length, 11);

		MinipoolManager.Minipool memory mpCompounded2 = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		assertEq(mpCompounded2.status, uint256(MinipoolStatus.Launched));
		assertGt(mpCompounded2.avaxNodeOpAmt, mp.avaxNodeOpAmt);
		assertGt(mpCompounded2.avaxNodeOpAmt, mp.avaxNodeOpInitialAmt);
		assertGt(mpCompounded2.avaxLiquidStakerAmt, mp.avaxLiquidStakerAmt);
		assertEq(staking.getAVAXStake(mp.owner), mpCompounded2.avaxNodeOpAmt);
		assertEq(staking.getAVAXAssigned(mp.owner), mpCompounded2.avaxLiquidStakerAmt);
		assertEq(mpCompounded2.startTime, 0);
		assertGt(mpCompounded2.initialStartTime, 0);

		// stake minipool again
		bytes32 txID1 = keccak256(abi.encodePacked(mpCompounded.nodeID, blockhash(block.timestamp)));
		minipoolMgr.recordStakingStart(mpCompounded.nodeID, txID1, block.timestamp);

		skip(duration / 3);

		vm.recordLogs();

		rialto.processMinipoolEndWithRewards(mp.nodeID);
		entries = vm.getRecordedLogs();
		assertEq(entries.length, 5);

		MinipoolManager.Minipool memory mpCompounded3 = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		assertEq(mpCompounded3.status, uint256(MinipoolStatus.Withdrawable));
		assertGt(mpCompounded3.avaxNodeOpAmt, mp.avaxNodeOpAmt);
		assertGt(mpCompounded3.avaxNodeOpAmt, mp.avaxNodeOpInitialAmt);
		assertGt(mpCompounded3.avaxLiquidStakerAmt, mp.avaxLiquidStakerAmt);
		assertEq(staking.getAVAXStake(mp.owner), mpCompounded3.avaxNodeOpAmt);
		assertEq(staking.getAVAXAssigned(mp.owner), 0);
		assertGt(mpCompounded3.endTime, 0);
	}
}
