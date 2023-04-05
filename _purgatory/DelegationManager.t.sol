pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import "./utils/BaseTest.sol";
import {DelegationNodeStatus} from "../../contracts/types/DelegationNodeStatus.sol";

contract DelegationManagerTest is BaseTest {
	int256 private index;
	address private nodeID;
	address private nodeOp;
	uint256 private ggpBondAmt;
	uint256 private requestedDelegationAmt;
	uint256 private duration;
	uint128 private immutable MIN_DELEGATION_AMT = 25 ether;
	address private bob;

	function setUp() public override {
		super.setUp();
		registerMultisig(rialto1);
		nodeOp = getActorWithTokens(3_000_000 ether, 3_000_000 ether);
		bob = getActor(2);
	}

	function testFullCycle_NotMinipool() public {
		//make sure that there is a balance in the ggavax contract that can be used for delegation funds
		vm.deal(bob, 3000000 ether);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: 3000000 ether}();
		assertEq(bob.balance, 0);

		//create the delegation node
		(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
		//act as the delegation node and request delegation
		vm.startPrank(nodeOp);
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		index = delegationMgr.getIndexOf(nodeID);

		//check that the transfer of ggpbond from node op to the contract worked
		assertEq(vault.balanceOfToken("DelegationManager", ggp), ggpBondAmt);

		//check that the storage items are correct and the registration was successful
		address nodeID_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")));
		assertEq(nodeID_, nodeID);
		uint256 ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		uint256 status = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")));
		assertEq(status, uint256(DelegationNodeStatus.Prelaunch));
		address nodeOp_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		assertEq(nodeOp_, nodeOp);
		vm.stopPrank();

		//start acting as rialto
		vm.startPrank(rialto1);
		//start delegation as rialto
		delegationMgr.claimAndInitiateDelegation(nodeID);
		//check that all the funds were transfered successfully to rialto
		assertEq(rialto1.balance, requestedDelegationAmt);

		//rialto records delegation has started
		delegationMgr.recordDelegationStart(nodeID, block.timestamp);

		//testing that if we give an incorrect end time that it will trigger revert
		vm.expectRevert(DelegationManager.InvalidEndTime.selector);
		delegationMgr.recordDelegationEnd{value: requestedDelegationAmt}(nodeID, block.timestamp, 0 ether, 0 ether);

		skip(duration);

		//testing that if Rialto doesnt send back the original amt of delegation funds that it will trigger revert
		vm.expectRevert(DelegationManager.InvalidEndingDelegationAmount.selector);
		delegationMgr.recordDelegationEnd{value: 0 ether}(nodeID, block.timestamp, 0 ether, 0 ether);

		// // // Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(rialto1, rialto1.balance + rewards);

		//testing that if we give the incorrect amt of rewards it will revert
		vm.expectRevert(DelegationManager.InvalidEndingDelegationAmount.selector);
		delegationMgr.recordDelegationEnd{value: rialto1.balance}(nodeID, block.timestamp, 9 ether, 0 ether);

		//should test that if ther are no rewards then ggp will be slashed?

		//ggavax has some funds in it from bob
		uint256 priorBalance_ggAVAX = wavax.balanceOf(address(ggAVAX));

		//Is not a minipool, so no rewards for the validator
		// 10% rewards
		uint256 delegatorRewards = (requestedDelegationAmt * 10) / 100;
		uint256 delegationAndRewardsTotal = requestedDelegationAmt + delegatorRewards;

		delegationMgr.recordDelegationEnd{value: delegationAndRewardsTotal}(nodeID, block.timestamp, delegatorRewards, 0 ether);
		assertEq((wavax.balanceOf(address(ggAVAX)) - priorBalance_ggAVAX), delegationAndRewardsTotal);
		vm.stopPrank();

		//test that the node op can withdraw the funds they are due
		vm.startPrank(nodeOp);
		uint256 priorBalance_ggp = ggp.balanceOf(nodeOp);
		delegationMgr.withdrawRewardAndBondFunds(nodeID);
		assertEq((ggp.balanceOf(nodeOp) - priorBalance_ggp), ggpBondAmt);
	}

	function testFullCycle_WithMinipool() public {
		uint256 depositAmt = 1000 ether;
		uint128 ggpStakeAmt = 100 ether;
		uint256 avaxAssignmentRequest = 1000 ether;
		//make sure that there is a balance in the ggavax contract that can be used for delegation funds
		vm.deal(bob, 3000000 ether);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: 3000000 ether}();
		assertEq(bob.balance, 0);

		//create minipool and start staking
		address nodeID_notNeeded;
		uint256 minipool_duration;
		uint256 delegationFee;

		(nodeID, minipool_duration, delegationFee) = stakeAndCreateMinipool(nodeOp, depositAmt, ggpStakeAmt, avaxAssignmentRequest);
		assertEq(vault.balanceOf("MinipoolManager"), 1000 ether);

		vm.startPrank(rialto1);

		minipoolMgr.claimAndInitiateStaking(nodeID);

		assertEq(vault.balanceOf("MinipoolManager"), 0);
		assertEq(rialto1.balance, 2000 ether);

		//make sure the minipool is staking status
		bytes32 txID = keccak256("txid");
		minipoolMgr.recordStakingStart(nodeID, txID, block.timestamp);
		vm.stopPrank();

		//create the delegation node
		(nodeID_notNeeded, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
		//act as the delegation node and request delegation
		vm.deal(nodeOp, ggpBondAmt);
		vm.startPrank(nodeOp);
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		index = delegationMgr.getIndexOf(nodeID);

		//check that the transfer of ggpbond from node op to the contract worked
		assertEq(vault.balanceOfToken("DelegationManager", ggp), ggpBondAmt);

		//check that the storage items are correct and the registration was successful
		address nodeID_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")));
		assertEq(nodeID_, nodeID);
		uint256 ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		uint256 status = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")));
		assertEq(status, uint256(DelegationNodeStatus.Prelaunch));
		address nodeOp_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		assertEq(nodeOp_, nodeOp);
		bool isMinipool = store.getBool(keccak256(abi.encodePacked("delegationNode.item", index, ".isMinipool")));
		assertEq(isMinipool, true);
		vm.stopPrank();

		//start acting as rialto
		vm.startPrank(rialto1);
		uint256 priorBalance_rialto1 = rialto1.balance;
		//start delegation as rialto
		delegationMgr.claimAndInitiateDelegation(nodeID);
		//check that all the funds were transfered successfully to rialto
		assertEq((rialto1.balance - priorBalance_rialto1), requestedDelegationAmt);

		//rialto records delegation has started
		delegationMgr.recordDelegationStart(nodeID, block.timestamp);

		//testing that if we give an incorrect end time that it will trigger revert
		vm.expectRevert(DelegationManager.InvalidEndTime.selector);
		delegationMgr.recordDelegationEnd{value: requestedDelegationAmt}(nodeID, block.timestamp, 0 ether, 0 ether);

		skip(duration);

		//testing that if Rialto doesnt send back the original amt of delegation funds that it will trigger revert
		vm.expectRevert(DelegationManager.InvalidEndingDelegationAmount.selector);
		delegationMgr.recordDelegationEnd{value: 0 ether}(nodeID, block.timestamp, 0 ether, 0 ether);

		// // // Give rialto the rewards it needs
		uint256 rewards = 10 ether;
		deal(rialto1, (rialto1.balance - priorBalance_rialto1) + rewards);

		//testing that if we give the incorrect amt of rewards it will revert
		vm.expectRevert(DelegationManager.InvalidEndingDelegationAmount.selector);
		delegationMgr.recordDelegationEnd{value: rialto1.balance}(nodeID, block.timestamp, 9 ether, 0 ether);

		//should test that if ther are no rewards then ggp will be slashed?

		//ggavax has some funds in it from bob
		uint256 priorBalance_ggAVAX = wavax.balanceOf(address(ggAVAX));

		//Is a minipool, so rewards for the validator and delegator
		// 5% rewards for each
		uint256 delegatorRewards = (requestedDelegationAmt * 5) / 100;
		uint256 validatorRewards = (requestedDelegationAmt * 5) / 100;
		uint256 delegationAndRewardsTotal = requestedDelegationAmt + delegatorRewards + validatorRewards;

		delegationMgr.recordDelegationEnd{value: delegationAndRewardsTotal}(nodeID, block.timestamp, delegatorRewards, validatorRewards);
		assertEq((wavax.balanceOf(address(ggAVAX)) - priorBalance_ggAVAX), (requestedDelegationAmt + delegatorRewards));
		assertEq(vault.balanceOf("DelegationManager"), validatorRewards);

		vm.stopPrank();

		//test that the node op can withdraw the funds they are due
		vm.startPrank(nodeOp);
		uint256 priorBalance_ggp = ggp.balanceOf(nodeOp);
		uint256 priorBalance_nodeOp = nodeOp.balance;

		delegationMgr.withdrawRewardAndBondFunds(nodeID);
		assertEq((ggp.balanceOf(nodeOp) - priorBalance_ggp), ggpBondAmt);
		assertEq((nodeOp.balance - priorBalance_nodeOp), validatorRewards);
	}

	//taken form MinipoolManager
	function testExpectedReward() public {
		uint256 amt = delegationMgr.expectedRewardAmt(365 days, 1_000 ether);
		assertEq(amt, 100 ether);
		amt = delegationMgr.expectedRewardAmt((365 days / 2), 1_000 ether);
		assertEq(amt, 50 ether);
		amt = delegationMgr.expectedRewardAmt((365 days / 3), 1_000 ether);
		assertEq(amt, 33333333333333333000);

		// Set 5% annual expected reward rate
		dao.setSettingUint("avalanche.expectedRewardRate", 5e16);
		amt = delegationMgr.expectedRewardAmt(365 days, 1_000 ether);
		assertEq(amt, 50 ether);
		amt = delegationMgr.expectedRewardAmt((365 days / 3), 1_000 ether);
		assertEq(amt, 16.666666666666666 ether);
	}

	//taken from MinipoolManager
	function testCalculateSlashAmt() public {
		oracle.setGGPPriceInAVAX(1 ether, block.timestamp);
		uint256 slashAmt = delegationMgr.calculateSlashAmt(100 ether);
		assertEq(slashAmt, 100 ether);

		oracle.setGGPPriceInAVAX(0.5 ether, block.timestamp);
		slashAmt = delegationMgr.calculateSlashAmt(100 ether);
		assertEq(slashAmt, 200 ether);

		oracle.setGGPPriceInAVAX(3 ether, block.timestamp);
		slashAmt = delegationMgr.calculateSlashAmt(100 ether);
		assertEq(slashAmt, 33333333333333333333);
	}

	function testFullCycle_NotMinipool_WithSlashing() public {
		//make sure that there is a balance in the ggavax contract that can be used for delegation funds
		vm.deal(bob, 3000000 ether);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: 3000000 ether}();
		assertEq(bob.balance, 0);

		//create the delegation node
		(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
		//act as the delegation node and request delegation
		vm.startPrank(nodeOp);
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		index = delegationMgr.getIndexOf(nodeID);

		//check that the transfer of ggpbond from node op to the contract worked
		assertEq(vault.balanceOfToken("DelegationManager", ggp), ggpBondAmt);

		//check that the storage items are correct and the registration was successful
		address nodeID_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")));
		assertEq(nodeID_, nodeID);
		uint256 ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		uint256 status = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")));
		assertEq(status, uint256(DelegationNodeStatus.Prelaunch));
		address nodeOp_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		assertEq(nodeOp_, nodeOp);
		vm.stopPrank();

		//start acting as rialto
		vm.startPrank(rialto1);
		//start delegation as rialto
		delegationMgr.claimAndInitiateDelegation(nodeID);
		//check that all the funds were transfered successfully to rialto
		assertEq(rialto1.balance, requestedDelegationAmt);

		//rialto records delegation has started
		delegationMgr.recordDelegationStart(nodeID, block.timestamp);
		skip(duration);

		//ggavax has some funds in it from bob
		uint256 priorBalance_ggAVAX = wavax.balanceOf(address(ggAVAX));
		//ggp price needs to be set inorder to calculate the slash amt
		oracle.setGGPPriceInAVAX(1 ether, block.timestamp);

		//testing that if we give zero rewards that the ggp will be slashed
		delegationMgr.recordDelegationEnd{value: requestedDelegationAmt}(nodeID, block.timestamp, 0 ether, 0 ether);
		uint256 expectedAmt = delegationMgr.expectedRewardAmt(duration, requestedDelegationAmt);
		uint256 slashAmt = delegationMgr.calculateSlashAmt(expectedAmt);
		uint256 slashAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpSlashAmt")));
		assertEq(slashAmt_, slashAmt);
		assertEq((wavax.balanceOf(address(ggAVAX)) - priorBalance_ggAVAX), (requestedDelegationAmt));
		vm.stopPrank();

		//test that the node op can withdraw the funds they are due
		vm.startPrank(nodeOp);
		uint256 priorBalance_ggp = ggp.balanceOf(nodeOp);
		delegationMgr.withdrawRewardAndBondFunds(nodeID);
		assertEq((ggp.balanceOf(nodeOp) - priorBalance_ggp), (ggpBondAmt - slashAmt));

		DelegationManager.DelegationNode memory dn;
		dn = delegationMgr.getDelegationNode(index);
		//check that the status is finished for this node
		assertEq(dn.status, uint256(DelegationNodeStatus.Finished));

		//test rejoining once finished
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		int256 new_index = delegationMgr.getIndexOf(nodeID);
		assertEq(new_index, index);
		ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		vm.stopPrank();
	}

	//taken from MinipoolManger
	function testCancelAndReBondWithGGP() public {
		//create the delegation node
		(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
		//act as the delegation node and request delegation
		vm.startPrank(nodeOp);
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		index = delegationMgr.getIndexOf(nodeID);

		//check that the transfer of ggpbond from node op to the contract worked
		assertEq(vault.balanceOfToken("DelegationManager", ggp), ggpBondAmt);

		//check that the storage items are correct and the registration was successful
		address nodeID_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")));
		assertEq(nodeID_, nodeID);
		uint256 ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		uint256 status = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")));
		assertEq(status, uint256(DelegationNodeStatus.Prelaunch));
		address nodeOp_ = store.getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		assertEq(nodeOp_, nodeOp);

		uint256 priorBalance_ggp = ggp.balanceOf(nodeOp);

		//cancel delegation
		delegationMgr.cancelDelegation(nodeID);
		DelegationManager.DelegationNode memory dn;
		dn = delegationMgr.getDelegationNode(index);

		//verify that it was canceled and the funds returned
		assertEq(dn.status, uint256(DelegationNodeStatus.Canceled));
		assertEq((ggp.balanceOf(nodeOp) - priorBalance_ggp), ggpBondAmt);

		//try to reregister the node for delegation
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		int256 new_index = delegationMgr.getIndexOf(nodeID);
		assertEq(new_index, index);
		ggpBondAmt_ = store.getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		assertEq(ggpBondAmt_, ggpBondAmt);
		vm.stopPrank();
	}

	//taken form MinipoolManager
	function testCancelByOwner() public {
		vm.startPrank(nodeOp);
		//create the delegation node
		(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
		delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		delegationMgr.cancelDelegation(nodeID);
		vm.stopPrank();

		vm.startPrank(rialto1);
		vm.expectRevert(DelegationManager.OnlyOwnerCanCancel.selector);
		delegationMgr.cancelDelegation(nodeID);
		vm.stopPrank();
	}

	//taken form MinipoolManager
	function testEmptyState() public {
		vm.startPrank(nodeOp);
		index = delegationMgr.getIndexOf(ZERO_ADDRESS);
		assertEq(index, -1);
		DelegationManager.DelegationNode memory dn;
		dn = delegationMgr.getDelegationNode(index);
		assertEq(dn.nodeID, ZERO_ADDRESS);
		vm.stopPrank();
	}

	//taken form MinipoolManager
	function testCreateAndGetMany() public {
		vm.startPrank(nodeOp);
		for (uint256 i = 0; i < 10; i++) {
			//create the delegation node
			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
		}
		index = delegationMgr.getIndexOf(nodeID);
		assertEq(index, 9);
		vm.stopPrank();
	}

	//taken from MinipoolManager
	function testGetStatusCounts() public {
		uint256 prelaunchCount;
		uint256 launchedCount;
		uint256 delegatedCount;
		uint256 withdrawableCount;
		uint256 finishedCount;
		uint256 canceledCount;
		vm.startPrank(nodeOp);

		for (uint256 i = 0; i < 10; i++) {
			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);

			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
			delegationMgr.updateDelegationNodeStatus(nodeID, DelegationNodeStatus.Launched);

			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
			delegationMgr.updateDelegationNodeStatus(nodeID, DelegationNodeStatus.Delegated);

			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
			delegationMgr.updateDelegationNodeStatus(nodeID, DelegationNodeStatus.Withdrawable);

			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
			delegationMgr.updateDelegationNodeStatus(nodeID, DelegationNodeStatus.Finished);

			(nodeID, requestedDelegationAmt, ggpBondAmt, duration) = randDelegationNode();
			delegationMgr.registerNode{value: ggpBondAmt}(nodeID, requestedDelegationAmt, ggpBondAmt, duration);
			delegationMgr.updateDelegationNodeStatus(nodeID, DelegationNodeStatus.Canceled);
		}

		// Get all in one page
		(prelaunchCount, launchedCount, delegatedCount, withdrawableCount, finishedCount, canceledCount) = delegationMgr.getDelegationNodeCountPerStatus(
			0,
			0
		);
		assertEq(prelaunchCount, 10);
		assertEq(launchedCount, 10);
		assertEq(delegatedCount, 10);
		assertEq(withdrawableCount, 10);
		assertEq(finishedCount, 10);
		assertEq(canceledCount, 10);

		// Test pagination
		(prelaunchCount, launchedCount, delegatedCount, withdrawableCount, finishedCount, canceledCount) = delegationMgr.getDelegationNodeCountPerStatus(
			0,
			6
		);
		assertEq(prelaunchCount, 1);
		assertEq(launchedCount, 1);
		assertEq(delegatedCount, 1);
		assertEq(withdrawableCount, 1);
		assertEq(finishedCount, 1);
		assertEq(canceledCount, 1);

		vm.stopPrank();
	}
}
