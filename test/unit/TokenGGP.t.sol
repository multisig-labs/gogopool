// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract TokenGGPTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testConstructorMint() public {
		TokenGGP token = new TokenGGP(store);
		assertEq(token.balanceOf(address(0xd98C0e8352352b3c486Cc9676F1b593F4cf28102)), 18_000_000 ether);
	}

	function testMintOnlyRewardsPool() public {
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		ggp.mint(1 ether);
	}

	function testMintMaxReached() public {
		uint256 max = ggp.MAX_SUPPLY();
		uint256 total = ggp.totalSupply();
		vm.startPrank(address(rewardsPool));
		vm.expectRevert(TokenGGP.MaximumTokensReached.selector);
		ggp.mint(max - total + 1);
		vm.stopPrank();
	}

	function testMint() public {
		uint256 previousBalance = vault.balanceOfToken("RewardsPool", ggp);
		vm.prank(address(rewardsPool));
		ggp.mint(1 ether);

		assertEq(vault.balanceOfToken("RewardsPool", ggp), previousBalance + 1 ether);
	}
}
