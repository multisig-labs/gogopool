// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {Storage} from "../contracts/contract/Storage.sol";

contract SetGuardian is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		address newGuardian = vm.envAddress("NEW_GUARDIAN");

		vm.startBroadcast(deployer);

		Storage s = Storage(getAddress("Storage"));
		s.setGuardian(newGuardian);
		console2.log("Transfer initiated. New guardian must call 'confirmGuardian()'");

		vm.stopBroadcast();
	}
}
