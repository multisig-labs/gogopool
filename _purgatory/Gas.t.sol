// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

// +-----------+-----------+--------+---------+
// |    Gas    | Gas Price | Avax $ | Tx $    |
// +-----------+-----------+--------+---------+
// |    10,000 |       30  |     20 |   0.006 |
// |   100,000 |       30  |     20 |   0.06  |
// | 1,000,000 |       30  |     20 |   0.60  |
// | 3,000,000 |       30  |     20 |   1.80  |
// +-----------+-----------+--------+---------+
// |    10,000 |       120 |     80 |   0.096 |
// |   100,000 |       120 |     80 |    0.96 |
// | 1,000,000 |       120 |     80 |     9.6 |
// | 3,000,000 |       120 |     80 |    28.8 |
// +-----------+-----------+--------+---------+

contract GasSettingsTest is BaseTest {
	bytes32 private settingNamespace;

	function setUp() public override {
		super.setUp();
		settingNamespace = keccak256(abi.encodePacked("mysettingnamespace."));
	}

	// gas: 7849
	function testNoNamespace() public view {
		store.getUint(keccak256(abi.encodePacked("mykey.")));
	}

	// gas: 10047
	function testWithNamespace() public view {
		store.getUint(keccak256(abi.encodePacked(settingNamespace, "mykey.")));
	}
}

contract GasTest is BaseTest {
	function testGas() public {
		bytes memory key = bytes("key");
		bytes32 key2 = bytes32("key2");
		bytes memory result;
		bytes32 h;

		// This takes 22455 gas
		startMeasuringGas("test1");
		result = abi.encodePacked(key, ".keyA");
		stopMeasuringGas();

		// This takes 244 gas
		startMeasuringGas("test2");
		result = abi.encodePacked(key2, ".keyA");
		stopMeasuringGas();

		// This takes 208 gas
		startMeasuringGas("test3");
		result = abi.encodePacked("key1.keyA");
		stopMeasuringGas();

		// This takes 229 gas
		startMeasuringGas("test4");
		result = abi.encodePacked("key1", ".keyA");
		stopMeasuringGas();

		// This takes 259 gas
		startMeasuringGas("test5");
		h = keccak256(abi.encodePacked("key1"));
		stopMeasuringGas();

		// This takes 139 gas
		startMeasuringGas("test6");
		h = keccak256("key1");
		stopMeasuringGas();
	}
}
