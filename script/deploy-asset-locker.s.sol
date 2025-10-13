// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {AssetLocker} from "../contracts/contract/AssetLocker.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployAssetLocker is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		// Get guardian address (admin)
		address guardian = vm.envAddress("GUARDIAN");
		// Set treasury to guardian for initial deployment (can be changed later)
		address treasury = guardian;

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		console2.log("ProxyAdmin deployed at", address(proxyAdmin));

		AssetLocker assetLockerImpl = new AssetLocker();
		console2.log("AssetLockerImpl deployed at", address(assetLockerImpl));

		TransparentUpgradeableProxy assetLockerProxy = new TransparentUpgradeableProxy(
			address(assetLockerImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(assetLockerImpl.initialize.selector, guardian, treasury)
		);

		AssetLocker assetLocker = AssetLocker(payable(assetLockerProxy));
		console2.log("AssetLocker deployed at", address(assetLocker));

		// Transfer ProxyAdmin ownership to guardian
		proxyAdmin.transferOwnership(guardian);
		console2.log("ProxyAdmin ownership transferred to guardian:", guardian);

		saveAddress("AssetLocker", address(assetLocker));
		saveAddress("AssetLockerAdmin", address(proxyAdmin));
		saveAddress("AssetLockerImpl", address(assetLockerImpl));

		vm.stopBroadcast();
	}
}
