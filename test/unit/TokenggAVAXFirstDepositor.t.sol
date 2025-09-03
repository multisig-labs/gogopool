// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";

contract TokenggAVAXTestFirstDepositor is BaseTest, IWithdrawer {
	using FixedPointMathLib for uint256;

	function setUp() public override {
		super.setUp();
	}

	function testInflationAttackNoDeposit() public {
		// setup ggavax token
		vm.startPrank(guardian);
		TokenggAVAX tokenImpl = new TokenggAVAX();
		TokenggAVAX token = TokenggAVAX(deployProxy(address(tokenImpl), guardian));
		vm.stopPrank();

		token.initialize(store, wavax, 0 ether);

		address attacker = getActorWithTokens("attacker", 1 ether + 1, 0);
		address victim = getActorWithTokens("victim", 2 ether, 0);

		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), attacker);
		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), victim);

		// deposit 1 wei to mint 1 wei of shares
		vm.startPrank(attacker);
		wavax.approve(address(token), 1);
		token.deposit(1, attacker);
		vm.stopPrank();

		assertEq(token.balanceOf(attacker), 1);
		assertEq(token.convertToShares(1 ether), 1 ether);

		// donate 1e18
		vm.prank(attacker);
		wavax.transfer(address(token), 1 ether);

		// fully sync shares
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();

		assertEq(token.balanceOf(attacker), 1);
		assertEq(token.convertToAssets(1), 1 ether + 1);

		// victim attempt a deposit
		// because the share conversion of 1e18 / (1e18 +1) is less than 1 and rounds to 0
		// we revert because 0 shares
		vm.startPrank(victim);
		wavax.approve(address(token), 1 ether);
		vm.expectRevert("ZERO_SHARES");
		token.deposit(1 ether, victim);
		vm.stopPrank();

		// deposit 2 ether this time
		vm.startPrank(victim);
		wavax.approve(address(token), 2 ether);
		token.deposit(2 ether, victim);
		vm.stopPrank();

		// victim is only minted one share because
		// 2 ether / (1 ether + 1) == 1.99999 shares which rounds down to 1 share
		assertEq(token.balanceOf(victim), 1);

		// now attacker can withdraw a bonus 0.5 ether
		vm.prank(attacker);
		token.redeem(1, attacker, attacker);

		assertEq(wavax.balanceOf(attacker), 1.5 ether);

		vm.prank(victim);
		token.redeem(1, victim, victim);

		// victim is left with 1.5 ether
		// the extra 1 coming from the first wei from attacker
		assertEq(wavax.balanceOf(victim), 1.5 ether + 1);
	}

	function testInflationAttackWithInitialDeposit() public {
		// create a ggavax token with some initial amount
		vm.deal(address(this), 1 ether);
		wavax.deposit{value: 1 ether}();

		TokenggAVAX tokenImpl = new TokenggAVAX();
		TokenggAVAX token = TokenggAVAX(deployProxy(address(tokenImpl), guardian));

		wavax.approve(address(token), 1 ether);

		token.initialize(store, wavax, 1 ether);

		address attacker = getActorWithTokens("attacker", 1 ether + 1, 0);
		address victim = getActorWithTokens("victim", 1 ether, 0);

		// Grant WITHDRAW_QUEUE_ROLE to actors for the custom token instance
		// Note: calling from test contract since guardian is proxy admin and cannot call implementation
		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), attacker);
		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), victim);

		// deposit 1 wei to mint 1 wei of shares
		vm.startPrank(attacker);
		wavax.approve(address(token), 1);
		token.deposit(1, attacker);
		vm.stopPrank();

		assertEq(token.balanceOf(attacker), 1);
		assertEq(token.convertToShares(1 ether), 1 ether);

		// donate 1e18
		vm.prank(attacker);
		wavax.transfer(address(token), 1 ether);

		// fully sync shares
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();

		assertEq(token.convertToAssets(1), 1);

		// victim can now deposit 1 ether without issue
		vm.startPrank(victim);
		wavax.approve(address(token), 1 ether);
		token.deposit(1 ether, victim);
		vm.stopPrank();

		// victims 1 ether is worth 0.5 ether of shares after attackers deposit
		assertEq(token.balanceOf(victim), 0.5 ether);

		// attacker redeems for 1 wei
		vm.prank(attacker);
		token.redeem(1, attacker, attacker);
		assertEq(wavax.balanceOf(attacker), 1);

		// victim is able to redeem for their full amount
		vm.startPrank(victim);
		token.redeem(token.balanceOf(victim), victim, victim);
		vm.stopPrank();

		assertEq(wavax.balanceOf(victim), 1 ether);
	}

	function testLargerInflationAttackWithInitialDeposit() public {
		// create a ggavax with some initial amount
		vm.deal(address(this), 1 ether);
		wavax.deposit{value: 1 ether}();

		TokenggAVAX tokenImpl = new TokenggAVAX();
		TokenggAVAX token = TokenggAVAX(deployProxy(address(tokenImpl), guardian));

		wavax.approve(address(token), 1 ether);

		token.initialize(store, wavax, 1 ether);

		// now attempt attack with 1e6 ether == 1e24
		address attacker = getActorWithTokens("attacker", 1_000_000 ether + 1, 0);
		address victim = getActorWithTokens("victim", 1 ether, 0);

		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), attacker);
		token.grantRole(token.WITHDRAW_QUEUE_ROLE(), victim);

		// deposit 1 wei to mint 1 wei of shares
		vm.startPrank(attacker);
		wavax.approve(address(token), 1);
		token.deposit(1, attacker);
		vm.stopPrank();

		assertEq(token.balanceOf(attacker), 1);
		assertEq(token.convertToShares(1 ether), 1 ether);

		// donate 1e24
		vm.prank(attacker);
		wavax.transfer(address(token), 1_000_000 ether);

		// fully sync shares
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();
		vm.warp(token.rewardsCycleEnd());
		token.syncRewards();

		// one share is now worth 1e6
		assertEq(token.convertToAssets(1), 1_000_000);

		// 1 share being worth 1e6 means that the attack can take
		// advantage of at most a 1e6 difference between deposit
		// amount and shares minted.

		// victim can now deposit 1 ether
		vm.startPrank(victim);
		wavax.approve(address(token), 1 ether);
		token.deposit(1 ether, victim);
		vm.stopPrank();

		// victim is minted close to the "correct" amount
		// victim should really get 9.999...e11 (1e18 * ((1e18 + 1) / (1e24+1e18+1) worth of shares
		// but is cut off 1e6 worth of "9"s
		assertEq(token.balanceOf(victim), 999_999_000_000);

		// attacker redeems for 1 wei shares
		vm.prank(attacker);
		token.redeem(1, attacker, attacker);

		// attacker gets back 1_000_000 + 1 wei for their trouble, but is net down 1e24 - 1e6
		assertEq(wavax.balanceOf(attacker), 1_000_001);

		// victim is able to redeem close to their full amount
		vm.startPrank(victim);
		token.redeem(token.balanceOf(victim), victim, victim);
		vm.stopPrank();

		assertEq(wavax.balanceOf(victim), 999_999_999_999_000_000);
	}

	function receiveWithdrawalAVAX() external payable {}
}
