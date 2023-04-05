// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {BaseAbstract} from "./BaseAbstract.sol";
import {Storage} from "./Storage.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract BaseUpgradeable is Initializable, BaseAbstract {
	function __BaseUpgradeable_init(Storage gogoStorageAddress) internal onlyInitializing {
		gogoStorage = Storage(gogoStorageAddress);
	}

	/// @dev This empty reserved space is put in place to allow future versions to add new
	/// variables without shifting down storage in the inheritance chain.
	uint256[50] private __gap;
}
