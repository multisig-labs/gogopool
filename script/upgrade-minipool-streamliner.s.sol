// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {SubnetHardwareRentalMapping} from "../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MinipoolStreamliner} from "../contracts/contract/MinipoolStreamliner.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployMultipleHWPUpgrades is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.5 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(payable(getAddress("SubnetHardwareRentalMapping")));

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              UPGRADE MINIPOOL STREAMLINER                  */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		MinipoolStreamliner mpStreamImplV3 = new MinipoolStreamliner();

		TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(getAddress("MinipoolStreamliner")));
		ProxyAdmin proxyAdmin = ProxyAdmin(getAddress("MinipoolStreamlinerAdmin"));
		proxyAdmin.upgradeAndCall(
			proxy,
			address(mpStreamImplV3),
			abi.encodeWithSelector(mpStreamImplV3.initialize.selector, address(subnetHardwareRentalMapping))
		);

		saveAddress("MinipoolStreamlinerImpl", address(mpStreamImplV3));

		vm.stopBroadcast();
	}
}
