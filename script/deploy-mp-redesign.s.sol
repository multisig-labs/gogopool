// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Staking} from "../contracts/contract/Staking.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {MinipoolStreamliner} from "../contracts/contract/MinipoolStreamliner.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Deploying a single contract
contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		// Ensure deployer has enough funds to deploy protocol
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		address wavaxAddress = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
		address usdcAddress = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
		address lbRouterAddress = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
		address oonodzWrapperAddress = 0x769Fc9b5038d8843895b50a904e04b58b0d4a9CB;

		vm.startBroadcast(deployer);

		Storage s;

		s = Storage(getAddress("Storage"));

		MinipoolManager minipoolManager = new MinipoolManager(s);
		saveAddress("MinipoolManager", address(minipoolManager));

		Staking staking = new Staking(s);
		saveAddress("Staking", address(staking));

		MinipoolStreamliner streamlinedMinipool = new MinipoolStreamliner(s, wavaxAddress, usdcAddress, lbRouterAddress, oonodzWrapperAddress);
		saveAddress("MinipoolStreamliner", address(streamlinedMinipool));

		vm.stopBroadcast();
	}
	// Following this: upgrade both minipool manager and staking and then register the streamlined Minipool contract address with oonodz. Make sure FE has correct addresses
}
