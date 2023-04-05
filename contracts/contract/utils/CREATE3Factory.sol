// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.17;

import {CREATE3} from "@rari-capital/solmate/src/utils/CREATE3.sol";

/// @title Factory for deploying contracts to deterministic addresses via CREATE3
/// @author based on zefram.eth
/// @notice GoGoPool deterministic addresses
contract CREATE3Factory {
	function deploy(bytes32 salt, bytes memory creationCode) external payable returns (address deployed) {
		// hash salt with the deployer address to give each deployer its own namespace
		salt = keccak256(abi.encodePacked(msg.sender, salt));
		return CREATE3.deploy(salt, creationCode, msg.value);
	}

	function getDeployed(bytes32 salt) external view returns (address deployed) {
		// hash salt with the deployer address to give each deployer its own namespace
		salt = keccak256(abi.encodePacked(msg.sender, salt));
		return CREATE3.getDeployed(salt);
	}
}
