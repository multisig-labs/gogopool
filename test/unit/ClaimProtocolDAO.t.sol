// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

contract ClaimProtocolDAOTest is BaseTest {
	function setUp() public override {
		super.setUp();

		vm.startPrank(guardian);
		ggp.approve(address(vault), 1000 ether);
		vault.depositToken("ClaimProtocolDAO", ggp, 1000 ether);
		vm.stopPrank();
	}

	function testSpendFunds() public {
		address alice = getActor("alice");
		bytes memory customError = abi.encodeWithSignature("MustBeGuardian()");
		vm.expectRevert(customError);
		daoClaim.spend("Invoice1", alice, 100 ether);

		vm.startPrank(guardian);
		vm.expectRevert(ClaimProtocolDAO.InvalidAmount.selector);
		daoClaim.spend("Invoice1", alice, 0 ether);

		vm.expectRevert(ClaimProtocolDAO.InvalidAmount.selector);
		daoClaim.spend("Invoice1", alice, 1001 ether);

		daoClaim.spend("Invoice1", alice, 1000 ether);
	}
}
