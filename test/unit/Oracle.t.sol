// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import "./utils/BaseTest.sol";

contract OracleTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testOneInch() public {
		address oneInch = address(oneInchMock);

		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		oracle.setTWAP(oneInch);

		vm.prank(guardian);
		oracle.setTWAP(oneInch);

		vm.startPrank(address(rialto));
		(uint256 price, uint256 timestamp) = oracle.getGGPPriceInAVAXFromTWAP();
		assertEq(price, 1 ether);
		assertEq(timestamp, block.timestamp);
	}

	function testGGPPriceInAvax() public {
		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		oracle.setGGPPriceInAVAX(0, block.timestamp);

		vm.startPrank(address(rialto));

		vm.expectRevert(Oracle.InvalidTimestamp.selector);
		oracle.setGGPPriceInAVAX(0, block.timestamp - 1);

		vm.expectRevert(Oracle.InvalidGGPPrice.selector);
		oracle.setGGPPriceInAVAX(0, block.timestamp);

		oracle.setGGPPriceInAVAX(10 ether, block.timestamp);

		(uint256 price, uint256 timestamp) = oracle.getGGPPriceInAVAX();

		assertEq(price, 10 ether);
		assertEq(timestamp, block.timestamp);
	}
}
