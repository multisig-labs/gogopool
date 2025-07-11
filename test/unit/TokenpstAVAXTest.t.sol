// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {console2} from "forge-std/console2.sol";
import {TokenpstAVAX} from "../../contracts/contract/tokens/TokenpstAVAX.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";

contract TokenpstAVAXTest is BaseTest {
	TokenpstAVAX pstAVAX;
	address alice;
	address bob;

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);

		// Deploy WithdrawQueue
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory withdrawQueueInitData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), 7 days, 14 days);
		TransparentUpgradeableProxy withdrawQueueProxy = new TransparentUpgradeableProxy(address(withdrawQueueImpl), address(proxyAdmin), withdrawQueueInitData);
		WithdrawQueue withdrawQueue = WithdrawQueue(payable(address(withdrawQueueProxy)));

		// Deploy
		TokenpstAVAX pstAVAXImpl = new TokenpstAVAX();
		bytes memory initData = abi.encodeWithSelector(TokenpstAVAX.initialize.selector, address(ggAVAX), address(withdrawQueue));
		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(pstAVAXImpl), address(proxyAdmin), initData);
		pstAVAX = TokenpstAVAX(payable(address(proxy)));
	}

	function testSetup() public {
		assertEq(pstAVAX.vault(), address(ggAVAX));
		assertEq(pstAVAX.underlyingAsset(), address(ggAVAX.asset()));
	}

	function testDeposit() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), assets);

		vm.prank(alice);
		pstAVAX.withdraw(assets);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertEq(ggAVAX.balanceOf(alice), assets);
	}

	function testDepositWithReceive() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		(bool sent, ) = payable(address(pstAVAX)).call{value: assets}("");
		require(sent, "Failed to send AVAX");
		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(address(pstAVAX).balance, 0);
	}

	function testStripYield() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		assertEq(pstAVAX.getExcessShares(), 0);

		// Send WAVAX directly to TokenggAVAX as rewards
		vm.startPrank(bob);
		uint256 rewardsAmt = 1 ether;
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());
		vm.stopPrank();

		uint256 pstAVAXInggAVAX = ggAVAX.convertToShares(assets);
		console2.log("pstAVAXInggAVAX", pstAVAXInggAVAX);
		assertEq(pstAVAX.getExcessShares(), pstAVAXInggAVAX);

		vm.prank(alice);
		pstAVAX.withdraw(assets);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), pstAVAXInggAVAX);
		assertEq(ggAVAX.balanceOf(alice), pstAVAXInggAVAX);

		pstAVAX.stripYield();
		assertEq(pstAVAX.getExcessShares(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
	}
}
