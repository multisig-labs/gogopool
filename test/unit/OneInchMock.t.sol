// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract OneInchMockTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testSetRateToEth() public {
		assertEq(oneInchMock.getRateToEth(IERC20(address(ggp)), true), 1 ether);

		vm.expectRevert(OneInchMock.NotAuthorized.selector);
		oneInchMock.setRateToEth(1.5 ether);

		vm.prank(oneInchMock.authorizedSetter());
		oneInchMock.setRateToEth(1.5 ether);
		assertEq(oneInchMock.getRateToEth(IERC20(address(ggp)), true), 1.5 ether);
	}
}
