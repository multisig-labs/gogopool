// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Storage} from "./Storage.sol";

/// @title Base contract for network contracts
abstract contract BaseAbstract {
	error InvalidOrOutdatedContract();
	error MustBeGuardian();
	error MustBeMultisig();
	error ContractPaused();
	error ContractNotFound();
	error MustBeGuardianOrValidContract();

	uint8 public version;

	Storage internal gogoStorage;

	/// @dev Verify caller is a registered network contract
	modifier onlyRegisteredNetworkContract() {
		if (getBool(keccak256(abi.encodePacked("contract.exists", msg.sender))) == false) {
			revert InvalidOrOutdatedContract();
		}
		_;
	}

	/// @dev Verify caller is registered version of `contractName`
	modifier onlySpecificRegisteredContract(string memory contractName, address contractAddress) {
		if (contractAddress != getAddress(keccak256(abi.encodePacked("contract.address", contractName)))) {
			revert InvalidOrOutdatedContract();
		}
		_;
	}

	/// @dev Verify caller is a guardian or registered network contract
	modifier guardianOrRegisteredContract() {
		bool isContract = getBool(keccak256(abi.encodePacked("contract.exists", msg.sender)));
		bool isGuardian = msg.sender == gogoStorage.getGuardian();

		if (!(isGuardian || isContract)) {
			revert MustBeGuardianOrValidContract();
		}
		_;
	}

	/// @dev Verify caller is a guardian or registered version of `contractName`
	modifier guardianOrSpecificRegisteredContract(string memory contractName, address contractAddress) {
		bool isContract = contractAddress == getAddress(keccak256(abi.encodePacked("contract.address", contractName)));
		bool isGuardian = msg.sender == gogoStorage.getGuardian();

		if (!(isGuardian || isContract)) {
			revert MustBeGuardianOrValidContract();
		}
		_;
	}

	/// @dev Verify caller is the guardian
	modifier onlyGuardian() {
		if (msg.sender != gogoStorage.getGuardian()) {
			revert MustBeGuardian();
		}
		_;
	}

	/// @dev Verify caller is a valid multisig
	modifier onlyMultisig() {
		int256 multisigIndex = int256(getUint(keccak256(abi.encodePacked("multisig.index", msg.sender)))) - 1;
		address addr = getAddress(keccak256(abi.encodePacked("multisig.item", multisigIndex, ".address")));
		bool enabled = (addr != address(0)) && getBool(keccak256(abi.encodePacked("multisig.item", multisigIndex, ".enabled")));
		if (enabled == false) {
			revert MustBeMultisig();
		}
		_;
	}

	/// @dev Verify contract is not paused
	modifier whenNotPaused() {
		string memory contractName = getContractName(address(this));
		if (getBool(keccak256(abi.encodePacked("contract.paused", contractName)))) {
			revert ContractPaused();
		}
		_;
	}

	/// @dev Get the address of a network contract by name
	function getContractAddress(string memory contractName) internal view returns (address) {
		address contractAddress = getAddress(keccak256(abi.encodePacked("contract.address", contractName)));
		if (contractAddress == address(0x0)) {
			revert ContractNotFound();
		}
		return contractAddress;
	}

	/// @dev Get the name of a network contract by address
	function getContractName(address contractAddress) internal view returns (string memory) {
		string memory contractName = getString(keccak256(abi.encodePacked("contract.name", contractAddress)));
		if (bytes(contractName).length == 0) {
			revert ContractNotFound();
		}
		return contractName;
	}

	function getAddress(bytes32 key) internal view returns (address) {
		return gogoStorage.getAddress(key);
	}

	function getBool(bytes32 key) internal view returns (bool) {
		return gogoStorage.getBool(key);
	}

	function getBytes(bytes32 key) internal view returns (bytes memory) {
		return gogoStorage.getBytes(key);
	}

	function getBytes32(bytes32 key) internal view returns (bytes32) {
		return gogoStorage.getBytes32(key);
	}

	function getInt(bytes32 key) internal view returns (int256) {
		return gogoStorage.getInt(key);
	}

	function getUint(bytes32 key) internal view returns (uint256) {
		return gogoStorage.getUint(key);
	}

	function getString(bytes32 key) internal view returns (string memory) {
		return gogoStorage.getString(key);
	}

	function setAddress(bytes32 key, address value) internal {
		gogoStorage.setAddress(key, value);
	}

	function setBool(bytes32 key, bool value) internal {
		gogoStorage.setBool(key, value);
	}

	function setBytes(bytes32 key, bytes memory value) internal {
		gogoStorage.setBytes(key, value);
	}

	function setBytes32(bytes32 key, bytes32 value) internal {
		gogoStorage.setBytes32(key, value);
	}

	function setInt(bytes32 key, int256 value) internal {
		gogoStorage.setInt(key, value);
	}

	function setUint(bytes32 key, uint256 value) internal {
		gogoStorage.setUint(key, value);
	}

	function setString(bytes32 key, string memory value) internal {
		gogoStorage.setString(key, value);
	}

	function deleteAddress(bytes32 key) internal {
		gogoStorage.deleteAddress(key);
	}

	function deleteBool(bytes32 key) internal {
		gogoStorage.deleteBool(key);
	}

	function deleteBytes(bytes32 key) internal {
		gogoStorage.deleteBytes(key);
	}

	function deleteBytes32(bytes32 key) internal {
		gogoStorage.deleteBytes32(key);
	}

	function deleteInt(bytes32 key) internal {
		gogoStorage.deleteInt(key);
	}

	function deleteUint(bytes32 key) internal {
		gogoStorage.deleteUint(key);
	}

	function deleteString(bytes32 key) internal {
		gogoStorage.deleteString(key);
	}

	function addUint(bytes32 key, uint256 amount) internal {
		gogoStorage.addUint(key, amount);
	}

	function subUint(bytes32 key, uint256 amount) internal {
		gogoStorage.subUint(key, amount);
	}
}
