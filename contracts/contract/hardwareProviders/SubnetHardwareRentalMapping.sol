// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SubnetHardwareRentalMapping is OwnableUpgradeable {
	// mapping of subnetID to contract for that subnet - data lives in this base contract
	mapping(bytes32 => address) public subnetHardwareRentalContracts;

	error InvalidSubnetContract();
	error SubnetAlreadyRegistered();

	event SubnetHardwareRentalContractAdded(bytes32 indexed subnetId, address indexed contractAddress);
	event SubnetHardwareRentalContractRemoved(bytes32 indexed subnetId, address indexed contractAddress);

	constructor() {
		_disableInitializers();
	}

	function initialize(address _owner) external initializer {
		__Ownable_init();
		_transferOwnership(_owner);
	}

	/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
	/*              BASE CONTRACT SPECIFIC DETAILS                */
	/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

	/// @notice Register a new subnet rental contract
	/// @param _subnetId The ID of the subnet being registered
	/// @param _contractAddress The address of the rental contract for that subnet
	function addSubnetRentalContract(bytes32 _subnetId, address _contractAddress) external onlyOwner {
		if (_contractAddress == address(0)) revert InvalidSubnetContract();
		if (subnetHardwareRentalContracts[_subnetId] != address(0)) revert SubnetAlreadyRegistered();

		subnetHardwareRentalContracts[_subnetId] = _contractAddress;
		emit SubnetHardwareRentalContractAdded(_subnetId, _contractAddress);
	}

	/// @notice Remove a subnet rental contract
	/// @param _subnetId The ID of the subnet to remove
	/// @param _contractAddress The address of the rental contract for that subnet
	function removeSubnetRentalContract(bytes32 _subnetId, address _contractAddress) external onlyOwner {
		if (subnetHardwareRentalContracts[_subnetId] != _contractAddress) revert InvalidSubnetContract();

		subnetHardwareRentalContracts[_subnetId] = address(0);
		emit SubnetHardwareRentalContractRemoved(_subnetId, _contractAddress);
	}
}
