// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MinipoolStreamlinerV2} from "../contracts/contract/MinipoolStreamlinerV2.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Deploying a single contract
contract DeployMinipoolStreamlinerV2 is Script, EnvironmentConfig {
	function run() external {
		// only to be run on fuji
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		// deploy new contract
		MinipoolStreamlinerV2 mpStreamImplV2 = new MinipoolStreamlinerV2();

		// upgrade existing to the new implementation
		TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(getAddress("MinipoolStreamliner")));
		ProxyAdmin proxyAdmin = ProxyAdmin(getAddress("MinipoolStreamlinerAdmin"));
		proxyAdmin.upgradeAndCall(proxy, address(mpStreamImplV2), abi.encodeWithSelector(mpStreamImplV2.initialize.selector));

		vm.stopBroadcast();

		saveAddress("MinipoolStreamlinerImpl", address(mpStreamImplV2));
	}
}
