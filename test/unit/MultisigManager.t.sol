// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {MultisigManager} from "../../contracts/contract/MultisigManager.sol";

contract MultisigManagerTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testRegisterMultisigNotGuardian() public {
		bytes memory customError = abi.encodeWithSignature("MustBeGuardian()");
		vm.expectRevert(customError);
		multisigMgr.registerMultisig(address(rialto));
	}

	function testRegisterMultisigAlreadyRegistered() public {
		vm.startPrank(guardian);
		vm.expectRevert(MultisigManager.MultisigAlreadyRegistered.selector);
		multisigMgr.registerMultisig(address(rialto));
	}

	function testRegisterMultisig() public {
		uint256 initCount = multisigMgr.getCount();
		address rialto1 = getActor("rialto1");

		vm.startPrank(guardian);
		multisigMgr.registerMultisig(rialto1);

		int256 index = multisigMgr.getIndexOf(rialto1);
		(address a, bool enabled) = multisigMgr.getMultisig(uint256(index));
		assertEq(a, rialto1);
		assertEq(enabled, false);

		assertEq(initCount + 1, multisigMgr.getCount());
	}

	function testEnableMultisigNotGuardian() public {
		bytes memory customError = abi.encodeWithSignature("MustBeGuardian()");
		vm.expectRevert(customError);
		multisigMgr.enableMultisig(address(rialto));
	}

	function testEnableMultisigNotFound() public {
		vm.startPrank(guardian);
		vm.expectRevert(MultisigManager.MultisigNotFound.selector);
		multisigMgr.enableMultisig(address(123));
	}

	function testEnableMultisig() public {
		address rialto1 = getActor("rialto1");

		vm.startPrank(guardian);
		multisigMgr.registerMultisig(rialto1);
		multisigMgr.enableMultisig(rialto1);

		int256 index = multisigMgr.getIndexOf(rialto1);
		(, bool enabled) = multisigMgr.getMultisig(uint256(index));

		assertEq(enabled, true);
	}

	function testDisableMultisigNotFound() public {
		address rialto1 = getActor("rialto1");

		vm.prank(guardian);
		vm.expectRevert(MultisigManager.MultisigNotFound.selector);
		multisigMgr.disableMultisig(rialto1);
	}

	function testDisableMultisig() public {
		address rialto1 = getActor("rialto1");

		vm.startPrank(guardian);

		multisigMgr.registerMultisig(rialto1);
		multisigMgr.enableMultisig(rialto1);

		int256 index = multisigMgr.getIndexOf(rialto1);
		(, bool enabled) = multisigMgr.getMultisig(uint256(index));
		assertEq(enabled, true);

		multisigMgr.disableMultisig(rialto1);
		(, enabled) = multisigMgr.getMultisig(uint256(index));
		assertEq(enabled, false);
	}

	function testFindActive() public {
		// Disable the global one
		vm.startPrank(guardian);
		multisigMgr.disableMultisig(address(rialto));
		address rialto1 = getActor("rialto1");
		multisigMgr.registerMultisig(rialto1);
		multisigMgr.enableMultisig(rialto1);
		address rialto2 = getActor("rialto2");
		multisigMgr.registerMultisig(rialto2);
		multisigMgr.enableMultisig(rialto2);
		multisigMgr.disableMultisig(rialto1);
		vm.stopPrank();
		address ms = multisigMgr.requireNextActiveMultisig();
		assertEq(rialto2, ms);
	}

	function testMultisigLimit() public {
		uint256 count = multisigMgr.getCount();
		uint256 limit = multisigMgr.MULTISIG_LIMIT();
		vm.startPrank(guardian);
		for (uint256 i = 0; i < limit - count; i++) {
			multisigMgr.registerMultisig(randAddress());
		}

		assertEq(multisigMgr.getCount(), limit);

		vm.expectRevert(MultisigManager.MultisigLimitReached.selector);
		multisigMgr.registerMultisig(randAddress());
	}

	function testWithdrawUnclaimedGGP() public {
		// Disable the global one
		vm.prank(guardian);
		multisigMgr.disableMultisig(address(rialto));
		assertEq(vault.balanceOfToken("MultisigManager", ggp), 0);

		// start the rewards cycle
		skip(dao.getRewardsCycleSeconds());
		rewardsPool.startRewardsCycle();

		assertGt(vault.balanceOfToken("MultisigManager", ggp), 0);

		address rialto1 = getActor("rialto1");
		vm.startPrank(rialto1);
		vm.expectRevert(MultisigManager.MultisigNotFound.selector);
		multisigMgr.withdrawUnclaimedGGP();
		vm.stopPrank();

		vm.prank(guardian);
		multisigMgr.registerMultisig(rialto1);

		vm.startPrank(rialto1);
		vm.expectRevert(MultisigManager.MultisigMustBeEnabled.selector);
		multisigMgr.withdrawUnclaimedGGP();
		vm.stopPrank();

		vm.prank(guardian);
		multisigMgr.enableMultisig(rialto1);

		vm.prank(rialto1);
		multisigMgr.withdrawUnclaimedGGP();
	}
}
