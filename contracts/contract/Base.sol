// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseAbstract} from "./BaseAbstract.sol";
import {Storage} from "./Storage.sol";

abstract contract Base is BaseAbstract {
	/// @dev Set the main GoGo Storage address
	constructor(Storage _gogoStorageAddress) {
		// Update the contract address
		gogoStorage = Storage(_gogoStorageAddress);
	}
}
