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

		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(getAddress("SubnetHardwareRentalMapping"));
		AvalancheHardwareRental avalancheHardwareRental = AvalancheHardwareRental(getAddress("AvalancheHardwareRental"));
		CoqnetHardwareRental coqnetHardwareRental = CoqnetHardwareRental(getAddress("CoqnetHardwareRental"));

		// Adding avalanche and coqnet as subnets
		subnetHardwareRentalMapping.addSubnetRentalContract(
			0x0000000000000000000000000000000000000000000000000000000000000000,
			address(avalancheHardwareRental)
		);
		subnetHardwareRentalMapping.addSubnetRentalContract(
			0x0ad6355dc6b82cd375e3914badb3e2f8d907d0856f8e679b2db46f8938a2f012,
			address(coqnetHardwareRental)
		);

		// Adding subnet staking as a renter for coqnet
		address subnetStaking = 0x9BFaDE56e75798167A84c24704Fed6098B590819;
		coqnetHardwareRental.grantRole(coqnetHardwareRental.RENTER_ROLE(), subnetStaking);

		//NEXT TIME: Add approved hardware providers for coqnet

		//AFTER THAT: Remove deployer as owner for mapping contract, and role for subnet contracts

		vm.stopBroadcast();
	}
}
