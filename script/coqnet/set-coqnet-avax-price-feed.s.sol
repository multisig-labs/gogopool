// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "../EnvironmentConfig.s.sol";

import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract SetCoqnetAvaxPriceFeed is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.5 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address chainlinkPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156;

		CoqnetHardwareRental coqnetHardwareRental = CoqnetHardwareRental(getAddress("CoqnetHardwareRental"));

		coqnetHardwareRental.setAvaxPriceFeed(chainlinkPriceFeed);
		vm.stopBroadcast();
	}
}
