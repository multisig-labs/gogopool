pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import "../Base.sol";

// Address set storage helper for RocketStorage data (contains unique items; has reverse index lookups)

contract AddressSetStorage is Base {
	// Construct
	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	// The number of items in a set
	function getCount(bytes32 _key) external view returns (uint256) {
		return getUint(keccak256(abi.encodePacked(_key, ".count")));
	}

	// The item in a set by index
	function getItem(bytes32 _key, uint256 _index) external view returns (address) {
		return getAddress(keccak256(abi.encodePacked(_key, ".item", _index)));
	}

	// The index of an item in a set
	// Returns -1 if the value is not found
	function getIndexOf(bytes32 _key, address _value) external view returns (int256) {
		return int256(getUint(keccak256(abi.encodePacked(_key, ".index", _value)))) - 1;
	}

	// Add an item to a set
	// Requires that the item does not exist in the set
	// TODO 	constructor(Storage storageAddress) Base(storageAddress) {
	function addItem(bytes32 _key, address _value) external {
		require(getUint(keccak256(abi.encodePacked(_key, ".index", _value))) == 0, "Item already exists in set");
		uint256 count = getUint(keccak256(abi.encodePacked(_key, ".count")));
		setAddress(keccak256(abi.encodePacked(_key, ".item", count)), _value);
		setUint(keccak256(abi.encodePacked(_key, ".index", _value)), count + 1);
		setUint(keccak256(abi.encodePacked(_key, ".count")), count + 1);
	}

	// Remove an item from a set
	// Swaps the item with the last item in the set and truncates it; computationally cheap
	// Requires that the item exists in the set
	function removeItem(bytes32 _key, address _value) external {
		uint256 index = getUint(keccak256(abi.encodePacked(_key, ".index", _value)));
		require(index-- > 0, "Item does not exist in set");
		uint256 count = getUint(keccak256(abi.encodePacked(_key, ".count")));
		if (index < count - 1) {
			address lastItem = getAddress(keccak256(abi.encodePacked(_key, ".item", count - 1)));
			setAddress(keccak256(abi.encodePacked(_key, ".item", index)), lastItem);
			setUint(keccak256(abi.encodePacked(_key, ".index", lastItem)), index + 1);
		}
		setUint(keccak256(abi.encodePacked(_key, ".index", _value)), 0);
		setUint(keccak256(abi.encodePacked(_key, ".count")), count - 1);
	}
}
