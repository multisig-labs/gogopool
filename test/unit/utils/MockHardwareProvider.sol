// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IHardwareProvider} from "../../../contracts/interface/IHardwareProvider.sol";

contract MockHardwareProvider is IHardwareProvider {
	mapping(address => bool) public hasHardware;

	function rentHardware(address user, address, uint256) external payable override {
		hasHardware[user] = true;
	}

	function getHardwareProviderName() public pure override returns (bytes32) {
		return keccak256("MockHardwareProvider");
	}
}
