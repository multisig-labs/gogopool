// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {GGAVAXRateProvider} from "../contracts/contract/tokens/GGAVAXRateProvider.sol";

contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadUsers();
		address deployer = getUser("deployer");

		vm.startBroadcast(deployer);

		address ggAVAXAddr = 0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3;
		new GGAVAXRateProvider(ggAVAXAddr);

		vm.stopBroadcast();
	}
}
