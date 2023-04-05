// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import "../../contracts/contract/Storage.sol";

contract StorageTest is BaseTest {
	address private constant NEWGUARDIAN = address(0xDEADBEEF);
	bytes32 private constant KEY = keccak256("test.key");

	function setUp() public override {
		super.setUp();
	}

	function testGuardian() public {
		// Storage() was created by guardian in setup, so it is the guardian to start
		assertEq(store.getGuardian(), guardian);

		// Change the guardian
		vm.startPrank(guardian);
		vm.expectRevert(Storage.InvalidGuardianAddress.selector);
		store.setGuardian(address(0));

		store.setGuardian(NEWGUARDIAN);
		// Should not change yet, must be confirmed
		assertEq(store.getGuardian(), guardian);
		vm.stopPrank();
		vm.startPrank(NEWGUARDIAN);
		store.confirmGuardian();
		assertEq(store.getGuardian(), NEWGUARDIAN);
		store.setString(KEY, "test");
		assertEq(store.getString(KEY), "test");
		vm.stopPrank();
	}

	// Accepting params will fuzz the test
	function testStorageFuzz(int256 i) public {
		vm.prank(guardian);
		store.setInt(KEY, i);
		assertEq(store.getInt(KEY), i);
	}

	function testNotGuardian() public {
		// Hack storage directly to unregister us as LatestNetworkContract
		store.setBool(keccak256(abi.encodePacked("contract.exists", address(this))), false);

		bytes memory customError = abi.encodeWithSignature("InvalidOrOutdatedContract()");
		vm.expectRevert(customError);
		store.setInt(KEY, 2);

		vm.prank(guardian);
		store.setInt(KEY, 2);
	}
}
