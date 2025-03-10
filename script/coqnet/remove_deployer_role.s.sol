// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {AvalancheHardwareRental} from "../../contracts/contract/hardwareProviders/AvalancheHardwareRental.sol";
import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import {EnvironmentConfig} from "../EnvironmentConfig.s.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployMultipleHWPUpgrades is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.5 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address guardian;

		if (block.chainid == 43114) {
			guardian = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;
		} else if (block.chainid == 43113) {
			guardian = deployer;
		} else {
			revert("Unsupported chain");
		}

		//Remove deployer as owner for mapping contract, and role for subnet contracts

		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(getAddress("SubnetHardwareRentalMapping"));
		AvalancheHardwareRental avalancheHardwareRental = AvalancheHardwareRental(getAddress("AvalancheHardwareRental"));
		CoqnetHardwareRental coqnetHardwareRental = CoqnetHardwareRental(getAddress("CoqnetHardwareRental"));

		avalancheHardwareRental.renounceRole(avalancheHardwareRental.DEFAULT_ADMIN_ROLE(), address(deployer));
		coqnetHardwareRental.renounceRole(avalancheHardwareRental.DEFAULT_ADMIN_ROLE(), address(deployer));
		subnetHardwareRentalMapping.transferOwnership(guardian);

		vm.stopBroadcast();
	}
}
