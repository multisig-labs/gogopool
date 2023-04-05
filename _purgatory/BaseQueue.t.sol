pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import {BaseTest} from "./utils/BaseTest.sol";

contract BaseQueueTest is BaseTest {
	// test node IDs
	address public NODE_ID_1 = 0x0000000000000000000000000000000000000001;
	address public NODE_ID_2 = 0x0000000000000000000000000000000000000002;
	address public NODE_ID_3 = 0x0000000000000000000000000000000000000003;
	bytes32 private key = keccak256("minipoolQueue");

	function setUp() public override {
		super.setUp();
	}

	function testEmpty() public {
		assertEq(baseQueue.getLength(key), 0);
	}

	function testEnqueue() public {
		// enqueue the first node
		baseQueue.enqueue(key, NODE_ID_1);

		// check the length
		assertEq(baseQueue.getLength(key), 1);
	}

	function testDequeue() public {
		// enqueue the first node
		baseQueue.enqueue(key, NODE_ID_1);

		// check the length
		assertEq(baseQueue.getLength(key), 1);

		// dequeue the first node
		address nodeId = baseQueue.dequeue(key);

		// check the length
		assertEq(baseQueue.getLength(key), 0);

		// check the node ID
		assertEq(nodeId, NODE_ID_1);
	}

	function testIndexOf() public {
		// enqueue the first node
		baseQueue.enqueue(key, NODE_ID_1);

		// check the length
		assertEq(baseQueue.getLength(key), 1);

		// check the index of the first node
		assertEq(baseQueue.getIndexOf(key, NODE_ID_1), 0);
	}

	function testGetItem() public {
		// enqueue the first node
		baseQueue.enqueue(key, NODE_ID_1);

		// check the length
		assertEq(baseQueue.getLength(key), 1);

		// check the index of the first node
		assertEq(baseQueue.getIndexOf(key, NODE_ID_1), 0);

		// check the node ID
		assertEq(baseQueue.getItem(key, 0), NODE_ID_1);
	}

	function testCancel() public {
		address addr;
		baseQueue.enqueue(key, NODE_ID_1);
		baseQueue.enqueue(key, NODE_ID_2);
		baseQueue.enqueue(key, NODE_ID_3);
		assertEq(baseQueue.getLength(key), 3);
		baseQueue.cancel(key, NODE_ID_2);
		assertEq(baseQueue.getLength(key), 2);
		startMeasuringGas("baseQueue.dequeue first");
		addr = baseQueue.dequeue(key);
		stopMeasuringGas();
		assertEq(addr, NODE_ID_1);
		assertEq(baseQueue.getLength(key), 1);
		// TODO why is this dequeue cheaper than the first by 5x?
		startMeasuringGas("baseQueue.dequeue second");
		addr = baseQueue.dequeue(key);
		stopMeasuringGas();
		assertEq(addr, NODE_ID_3);
		assertEq(baseQueue.getLength(key), 0);
	}

	function testManyPools(uint256 x) public {
		vm.assume(x <= 1000);
		vm.assume(x > 0);
		// add x pools to the queue
		for (uint256 i = 0; i < x; i++) {
			baseQueue.enqueue(key, randAddress());
		}

		// check the length
		assertEq(baseQueue.getLength(key), x);

		// get a random uint
		uint256 index = randUint(x);

		// try to access it
		address nodeId = baseQueue.getItem(key, index);

		// check its index
		assertEq(baseQueue.getIndexOf(key, nodeId), int256(index));
	}
}
