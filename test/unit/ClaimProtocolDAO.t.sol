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

		vm.startPrank(address(daoClaim));
		vm.deal(address(daoClaim), 1000 ether);
		vault.depositAVAX{value: 1000 ether}();
		// vault.transferAVAX("ClaimProtocolDAO", 1000 ether);
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

	function testSpendAVAX() public {
		address alice = getActor("alice");
		bytes memory customError = abi.encodeWithSignature("MustBeGuardian()");
		vm.expectRevert(customError);
		daoClaim.spendAVAX("Invoice1", alice, 100 ether);

		vm.startPrank(guardian);
		vm.expectRevert(ClaimProtocolDAO.InvalidAmount.selector);
		daoClaim.spendAVAX("Invoice1", alice, 0 ether);

		vm.expectRevert(Vault.InvalidAmount.selector);
		daoClaim.spendAVAX("Invoice1", alice, 1001 ether);

		daoClaim.spendAVAX("Invoice1", alice, 1000 ether);
		assertEq(address(daoClaim).balance, 0 ether);
		assertEq(alice.balance, 1000 ether);
	}
}
