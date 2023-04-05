// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

contract OcyticusTest is BaseTest {
	function setUp() public override {
		super.setUp();
	}

	function testPauseEverything() public {
		vm.prank(guardian);
		ocyticus.pauseEverything();
		assertTrue(dao.getContractPaused("MinipoolManager"));
		assertTrue(dao.getContractPaused("RewardsPool"));
		assertTrue(dao.getContractPaused("TokenggAVAX"));
		assertTrue(dao.getContractPaused("Staking"));

		vm.expectRevert(MultisigManager.NoEnabledMultisigFound.selector);
		multisigMgr.requireNextActiveMultisig();

		vm.prank(guardian);
		ocyticus.resumeEverything();
		assertFalse(dao.getContractPaused("TokenggAVAX"));
		assertFalse(dao.getContractPaused("RewardsPool"));
		assertFalse(dao.getContractPaused("MinipoolManager"));
		assertFalse(dao.getContractPaused("Staking"));

		// Multisigs don't get auto-re-enabled. We need to do that manually.
		vm.expectRevert(MultisigManager.NoEnabledMultisigFound.selector);
		multisigMgr.requireNextActiveMultisig();
	}

	function testAddRemoveDefender() public {
		address alice = getActor("alice");
		vm.prank(guardian);
		ocyticus.addDefender(alice);
		assertTrue(ocyticus.defenders(alice));

		vm.prank(guardian);
		ocyticus.removeDefender(alice);
		assertFalse(ocyticus.defenders(alice));
	}

	function testOnlyDefender() public {
		address alice = getActor("alice");

		vm.startPrank(alice);
		vm.expectRevert(Ocyticus.NotAllowed.selector);
		ocyticus.pauseEverything();

		vm.expectRevert(Ocyticus.NotAllowed.selector);
		ocyticus.resumeEverything();

		vm.expectRevert(Ocyticus.NotAllowed.selector);
		ocyticus.disableAllMultisigs();
		vm.stopPrank();

		vm.prank(guardian);
		ocyticus.addDefender(alice);

		vm.startPrank(alice);
		ocyticus.pauseEverything();
		assertTrue(dao.getContractPaused("TokenggAVAX"));

		ocyticus.resumeEverything();
		assertFalse(dao.getContractPaused("TokenggAVAX"));

		ocyticus.disableAllMultisigs();
		vm.expectRevert(MultisigManager.NoEnabledMultisigFound.selector);
		multisigMgr.requireNextActiveMultisig();

		vm.stopPrank();
	}

	function testDisableAllMultisigs() public {
		address alice = getActor("alice");
		vm.startPrank(guardian);
		multisigMgr.registerMultisig(alice);
		multisigMgr.enableMultisig(alice);
		vm.stopPrank();

		int256 rialtoIndex = multisigMgr.getIndexOf(address(rialto));
		int256 aliceIndex = multisigMgr.getIndexOf(alice);
		assert(rialtoIndex != -1);
		assert(aliceIndex != -1);

		address addr;
		bool enabled;
		(addr, enabled) = multisigMgr.getMultisig(uint256(rialtoIndex));
		assert(enabled);
		(addr, enabled) = multisigMgr.getMultisig(uint256(aliceIndex));
		assert(enabled);

		vm.prank(guardian);
		ocyticus.disableAllMultisigs();

		(addr, enabled) = multisigMgr.getMultisig(uint256(rialtoIndex));
		assert(!enabled);
		(addr, enabled) = multisigMgr.getMultisig(uint256(aliceIndex));
		assert(!enabled);
	}
}
