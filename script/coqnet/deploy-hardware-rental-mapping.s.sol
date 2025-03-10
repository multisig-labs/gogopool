// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
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

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              DEPLOY SUBNET CONTRACTS                       */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		ProxyAdmin subnetRentalMappingProxyAdmin = new ProxyAdmin();

		SubnetHardwareRentalMapping subnetHardwareRentalMappingImpl = new SubnetHardwareRentalMapping();

		TransparentUpgradeableProxy subnetHardwareRentalMappingTransparentProxy = new TransparentUpgradeableProxy(
			address(subnetHardwareRentalMappingImpl),
			address(subnetRentalMappingProxyAdmin),
			abi.encodeWithSelector(SubnetHardwareRentalMapping.initialize.selector, guardian)
		);
		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(payable(subnetHardwareRentalMappingTransparentProxy));

		subnetRentalMappingProxyAdmin.transferOwnership(guardian);

		saveAddress("SubnetHardwareRentalMapping", address(subnetHardwareRentalMapping));
		saveAddress("SubnetHardwareRentalMappingImpl", address(subnetHardwareRentalMappingImpl));
		saveAddress("SubnetHardwareRentalMappingAdmin", address(subnetRentalMappingProxyAdmin));

		vm.stopBroadcast();
	}
}
