// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {Base} from "../../contracts/contract/Base.sol";
import {BaseUpgradeable} from "../../contracts/contract/BaseUpgradeable.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract BaseContractTest is Initializable, BaseTest, BaseAbstract {
	MockBase public mockBase;

	function setUp() public override initializer {
		super.setUp();
		gogoStorage = store;
		mockBase = new MockBase(store);
		registerContract(store, "MockBase", address(mockBase));
	}

	function testOnlyRegisteredNetworkContract() public {
		address alice = getActor("alice");

		vm.startPrank(alice);
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		mockBase.onlyRegisteredNetworkContractFunction();
		vm.stopPrank();

		vm.startPrank(address(minipoolMgr));
		bool result = mockBase.onlyRegisteredNetworkContractFunction();
		assertTrue(result);
	}

	function testOnlySpecificRegisteredContract() public {
		vm.startPrank(address(multisigMgr));
		vm.expectRevert(BaseAbstract.InvalidOrOutdatedContract.selector);
		mockBase.onlySpecificRegisteredContractFunction();
		vm.stopPrank();

		vm.prank(address(minipoolMgr));
		bool result = mockBase.onlyRegisteredNetworkContractFunction();
		assertTrue(result);
	}

	function testGuardianOrRegisteredContractContract() public {
		address alice = getActor("alice");
		vm.startPrank(alice);
		vm.expectRevert(BaseAbstract.MustBeGuardianOrValidContract.selector);
		mockBase.guardianOrRegisteredContractFunction();
		vm.stopPrank();

		vm.prank(address(guardian));
		bool result = mockBase.guardianOrRegisteredContractFunction();
		assertTrue(result);

		vm.prank(address(multisigMgr));
		bool result2 = mockBase.guardianOrRegisteredContractFunction();
		assertTrue(result2);
	}

	function testGuardianOrSpecificRegisteredContractContract() public {
		vm.startPrank(address(multisigMgr));
		vm.expectRevert(BaseAbstract.MustBeGuardianOrValidContract.selector);
		mockBase.guardianOrSpecificRegisteredContractFunction();
		vm.stopPrank();

		vm.prank(address(minipoolMgr));
		bool result = mockBase.guardianOrSpecificRegisteredContractFunction();
		assertTrue(result);
	}

	function testOnlyGuardian() public {
		address alice = getActor("alice");
		vm.startPrank(alice);
		vm.expectRevert(BaseAbstract.MustBeGuardian.selector);
		mockBase.onlyGuardianFunction();
		vm.stopPrank();

		vm.prank(guardian);
		bool result = mockBase.onlyGuardianFunction();
		assertTrue(result);
	}

	function testOnlyMultisig() public {
		address multisig1 = getActor("multisig1");

		vm.startPrank(multisig1);
		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		mockBase.onlyMultisigFunction();
		vm.stopPrank();

		vm.prank(guardian);
		multisigMgr.registerMultisig(multisig1);

		vm.startPrank(multisig1);
		vm.expectRevert(BaseAbstract.MustBeMultisig.selector);
		mockBase.onlyMultisigFunction();
		vm.stopPrank();

		vm.prank(guardian);
		multisigMgr.enableMultisig(multisig1);

		vm.prank(multisig1);
		bool result = mockBase.onlyMultisigFunction();
		assertTrue(result);
	}

	function testWhenNotPaused() public {
		bool result = mockBase.whenNotPausedFunction();
		assertTrue(result);

		vm.prank(address(ocyticus));
		dao.pauseContract("MockBase");

		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		mockBase.whenNotPausedFunction();
	}

	function testGetContractAddress() public {
		string memory contractName = "name";
		address contractAddress = address(123);

		setAddress(keccak256(abi.encodePacked("contract.address", contractName)), contractAddress);
		address result = getContractAddress(contractName);

		assertEq(result, address(123));
	}

	function testGetContractName() public {
		string memory contractName = "name";
		address contractAddress = address(123);

		setString(keccak256(abi.encodePacked("contract.name", contractAddress)), contractName);
		string memory result = getContractName(contractAddress);

		assertEq(result, contractName);
	}

	function testAddress() public {
		bytes32 key = bytes32("key");
		address value = address(123);

		setAddress(key, value);

		address result = getAddress(key);
		assertEq(result, value);

		deleteAddress(key);
		result = getAddress(key);
		assertEq(result, address(0));
	}

	function testBool() public {
		bytes32 key = bytes32("key");
		bool value = true;

		setBool(key, value);
		bool result = getBool(key);
		assertEq(result, value);

		deleteBool(key);
		result = getBool(key);
		assertEq(result, false);
	}

	function testBytes() public {
		bytes32 key = bytes32("key");
		bytes memory value = bytes("value");

		setBytes(key, value);
		bytes memory result = getBytes(key);
		assertEq(result, value);

		deleteBytes(key);
		result = getBytes(key);
		assertEq(result, bytes(""));
	}

	function testBytes32() public {
		bytes32 key = bytes32("key");
		bytes32 value = bytes32("value");

		setBytes32(key, value);
		bytes32 result = getBytes32(key);
		assertEq(result, value);

		deleteBytes32(key);
		result = getBytes32(key);
		assertEq(result, bytes32(""));
	}

	function testInt() public {
		bytes32 key = bytes32("key");
		int256 value = 11;

		setInt(key, value);
		int256 result = getInt(key);
		assertEq(result, value);

		deleteInt(key);
		result = getInt(key);
		assertEq(result, 0);
	}

	function testUint() public {
		bytes32 key = bytes32("key");
		uint256 value = 11;

		setUint(key, value);
		uint256 result = getUint(key);
		assertEq(result, value);

		deleteUint(key);
		result = getUint(key);
		assertEq(result, 0);
	}

	function testString() public {
		bytes32 key = bytes32("key");
		string memory value = "test";
		setString(key, value);

		string memory result = getString(key);
		assertEq(result, value);

		deleteString(key);
		result = getString(key);
		assertEq(result, "");
	}

	function testAddUint() public {
		bytes32 key = bytes32("key");
		uint256 value = 10;
		setUint(key, value);

		addUint(key, 1);
		uint256 result = getUint(key);
		assertEq(result, value + 1);
	}

	function testSubUint() public {
		bytes32 key = bytes32("key");
		uint256 value = 10;
		setUint(key, value);

		subUint(key, 1);
		uint256 result = getUint(key);
		assertEq(result, value - 1);
	}
}

contract MockBase is Base {
	constructor(Storage _gogoStorageAddress) Base(_gogoStorageAddress) {}

	function onlyRegisteredNetworkContractFunction() public view onlyRegisteredNetworkContract returns (bool) {
		return true;
	}

	function onlySpecificRegisteredContractFunction() public view onlySpecificRegisteredContract("MinipoolManager", msg.sender) returns (bool) {
		return true;
	}

	function guardianOrRegisteredContractFunction() public view guardianOrRegisteredContract returns (bool) {
		return true;
	}

	function guardianOrSpecificRegisteredContractFunction()
		public
		view
		guardianOrSpecificRegisteredContract("MinipoolManager", msg.sender)
		returns (bool)
	{
		return true;
	}

	function onlyGuardianFunction() public view onlyGuardian returns (bool) {
		return true;
	}

	function onlyMultisigFunction() public view onlyMultisig returns (bool) {
		return true;
	}

	function whenNotPausedFunction() public view whenNotPaused returns (bool) {
		return true;
	}
}
