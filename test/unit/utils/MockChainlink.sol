// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract MockChainlinkPriceFeed is AggregatorV3Interface, AccessControl {
	uint256 public price;
	uint8 public dec = 8;

	bytes32 UPDATER = keccak256("UPDATER");

	constructor(address admin, uint256 startingPrice) {
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		_grantRole(UPDATER, admin);
		price = startingPrice;
	}

	modifier onlyUpdater() {
		_checkRole(UPDATER, _msgSender());
		_;
	}

	function setDecimals(uint8 newDecimals) public onlyUpdater {
		dec = newDecimals;
	}

	function setPrice(uint256 newPrice) public onlyUpdater {
		price = newPrice;
	}

	function decimals() external view returns (uint8) {
		return dec;
	}

	function description() external pure returns (string memory) {
		return string("MockPriceFeed");
	}

	function version() external pure returns (uint256) {
		return 1;
	}

	function getRoundData(uint80) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
		return (uint80(1), int256(price), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
	}

	function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) {
		return (uint80(1), int256(price), uint256(block.timestamp), uint256(block.timestamp), uint80(1));
	}
}
