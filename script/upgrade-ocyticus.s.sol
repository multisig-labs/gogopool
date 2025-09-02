// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {Ocyticus} from "../contracts/contract/Ocyticus.sol";

contract UpgradeOcyticus is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		Storage s = Storage(getAddress("Storage"));
		Ocyticus ocyticus = new Ocyticus(s);
		saveAddress("Ocyticus", address(ocyticus));

		vm.stopBroadcast();
	}
}
