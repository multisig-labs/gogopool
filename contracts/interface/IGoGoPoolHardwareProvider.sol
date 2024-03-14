// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {MinipoolStreamliner} from "../contract/MinipoolStreamliner.sol";

interface IGoGoPoolHardwareProvider {
	function rentHardware(address, MinipoolStreamliner.StreamlinedMinipool memory newMinipool) external payable returns (address, bytes memory);
}
