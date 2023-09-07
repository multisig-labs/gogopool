// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract DelegationTest is BaseTest {
	using FixedPointMathLib for uint256;
	address public delegatedNodeID = address(1);

	function setUp() public override {
		super.setUp();
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0 ether);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
	}

	function testDelegation(uint128 amount) public {
		vm.assume(amount > 1 ether && amount < MAX_AMT);
		vm.deal(address(rialto), 0);

		address alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		assertEq(ggAVAX.amountAvailableForStaking(), 0);
		assertEq(ggAVAX.totalAssets(), 0);

		vm.prank(alice);
		ggAVAX.depositAVAX{value: amount}();
		assertEq(ggAVAX.amountAvailableForStaking(), amount);
		assertEq(ggAVAX.totalAssets(), amount);

		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		minipoolMgr.withdrawForDelegation(amount, delegatedNodeID);

		assertEq(address(rialto).balance, 0);
		rialto.withdrawForDelegation(amount, delegatedNodeID);
		assertEq(address(rialto).balance, amount);
		assertEq(ggAVAX.amountAvailableForStaking(), 0);
		assertEq(ggAVAX.totalAssets(), amount);

		uint256 rewards = 1 ether;
		vm.deal(address(rialto), amount + rewards);
		vm.prank(address(rialto));
		rialto.depositFromDelegation{value: amount + rewards}(rewards, delegatedNodeID);

		assertEq(ggAVAX.totalAssets(), amount);
		assertEq(ggAVAX.amountAvailableForStaking(), amount);
		assertEq(ggAVAX.lastRewardsAmt(), 0);
		assertEq(address(rialto).balance, 0);

		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		assertEq(ggAVAX.lastRewardsAmt(), rewards);
	}

	function testDelegationZeroRewards(uint128 amount) public {
		vm.assume(amount > 1 ether && amount < MAX_AMT);
		vm.deal(address(rialto), 0);

		address alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		vm.prank(alice);
		ggAVAX.depositAVAX{value: amount}();

		rialto.withdrawForDelegation(amount, delegatedNodeID);

		uint256 rewards = 0 ether;
		vm.deal(address(rialto), amount + rewards);
		vm.prank(address(rialto));
		rialto.depositFromDelegation{value: amount + rewards}(rewards, delegatedNodeID);

		assertEq(ggAVAX.totalAssets(), amount);
		assertEq(ggAVAX.amountAvailableForStaking(), amount);
		assertEq(ggAVAX.lastRewardsAmt(), 0);
		assertEq(address(rialto).balance, 0);

		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		assertEq(ggAVAX.lastRewardsAmt(), rewards);
	}

	function testDelegationIncorrectDeposit(uint128 amount) public {
		vm.assume(amount > 1 ether && amount < MAX_AMT);
		vm.deal(address(rialto), 0);

		address alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		vm.prank(alice);
		ggAVAX.depositAVAX{value: amount}();

		rialto.withdrawForDelegation(amount, delegatedNodeID);

		uint256 rewards = 1 ether;
		vm.deal(address(rialto), amount + rewards);
		vm.expectRevert();
		rialto.depositFromDelegation{value: 1 ether}(2 ether, delegatedNodeID);
		vm.expectRevert();
		rialto.depositFromDelegation{value: 0 ether}(1 ether, delegatedNodeID);
	}

	function testDelegationDisabled() public {
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), false);
		vm.expectRevert(MinipoolManager.WithdrawForDelegationDisabled.selector);
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(1 ether, delegatedNodeID);
	}

	function testDelegationPaused() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("MinipoolManager");
		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		vm.prank(address(rialto));
		rialto.withdrawForDelegation(1 ether, delegatedNodeID);
	}
}
