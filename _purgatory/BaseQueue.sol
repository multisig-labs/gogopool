pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import {Base} from "./Base.sol";
import {Storage} from "./Storage.sol";

// Delegation queue storage helper (ring buffer implementation)
// Based off the Minipool queue

contract BaseQueue is Base {
	// Settings
	uint256 public constant CAPACITY = 2**255; // max uint256 / 2

	// Construct
	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	// Add item to the end of the queue
	function enqueue(bytes32 key, address nodeID) external {
		require(getLength(key) < CAPACITY - 1, "Queue is at capacity");
		require(getUint(keccak256(abi.encodePacked(key, ".index", nodeID))) == 0, "NodeID exists in queue");
		uint256 index = getUint(keccak256(abi.encodePacked(key, ".end")));
		setAddress(keccak256(abi.encodePacked(key, ".item", index)), nodeID);
		setUint(keccak256(abi.encodePacked(key, ".index", nodeID)), index + 1);
		index = index + 1;
		if (index >= CAPACITY) {
			index = index - CAPACITY;
		}
		setUint(keccak256(abi.encodePacked(key, ".end")), index);
	}

	// Remove an item from the start of a queue and return it
	// Requires that the queue is not empty
	function dequeue(bytes32 key) external returns (address) {
		require(getLength(key) > 0, "Queue is empty");
		uint256 start = getUint(keccak256(abi.encodePacked(key, ".start")));
		address nodeID = getAddress(keccak256(abi.encodePacked(key, ".item", start)));
		start = start + 1;
		if (start >= CAPACITY) {
			start = start - CAPACITY;
		}
		setUint(keccak256(abi.encodePacked(key, ".index", nodeID)), 0);
		setUint(keccak256(abi.encodePacked(key, ".start")), start);
		return nodeID;
	}

	// Peeks next item from the start of a queue (does not modify state)
	// Requires that the queue is not empty
	function peek(bytes32 key) external view returns (address) {
		uint256 start = getUint(keccak256(abi.encodePacked(key, ".start")));
		address nodeID = getAddress(keccak256(abi.encodePacked(key, ".item", start)));
		return nodeID;
	}

	// Swaps the item with the last item in the queue and truncates it; computationally cheap
	function cancel(bytes32 key, address nodeID) external {
		uint256 index = getUint(keccak256(abi.encodePacked(key, ".index", nodeID)));
		require(index-- > 0, "NodeID does not exist in queue");
		uint256 lastIndex = getUint(keccak256(abi.encodePacked(key, ".end")));
		if (lastIndex == 0) lastIndex = CAPACITY;
		lastIndex = lastIndex - 1;
		if (index != lastIndex) {
			address lastItem = getAddress(keccak256(abi.encodePacked(key, ".item", lastIndex)));
			setAddress(keccak256(abi.encodePacked(key, ".item", index)), lastItem);
			setUint(keccak256(abi.encodePacked(key, ".index", lastItem)), index + 1);
		}
		setUint(keccak256(abi.encodePacked(key, ".index", nodeID)), 0);
		setUint(keccak256(abi.encodePacked(key, ".end")), lastIndex);
	}

	// The number of items in a queue
	function getLength(bytes32 key) public view returns (uint256) {
		uint256 start = getUint(keccak256(abi.encodePacked(key, ".start")));
		uint256 end = getUint(keccak256(abi.encodePacked(key, ".end")));
		if (end < start) {
			end = end + CAPACITY;
		}
		return end - start;
	}

	// The item in a queue by index
	function getItem(bytes32 key, uint256 _index) public view returns (address) {
		uint256 index = getUint(keccak256(abi.encodePacked(key, ".start"))) + _index;
		if (index >= CAPACITY) {
			index = index - CAPACITY;
		}
		return getAddress(keccak256(abi.encodePacked(key, ".item", index)));
	}

	// The index of an item in a queue
	// Returns -1 if the value is not found
	function getIndexOf(bytes32 key, address nodeID) public view returns (int256) {
		int256 index = int256(getUint(keccak256(abi.encodePacked(key, ".index", nodeID)))) - 1;
		if (index != -1) {
			index -= int256(getUint(keccak256(abi.encodePacked(key, ".start"))));
			if (index < 0) {
				index += int256(CAPACITY);
			}
		}
		return index;
	}
}
