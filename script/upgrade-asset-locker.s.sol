// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {AssetLocker} from "../contracts/contract/AssetLocker.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeAssetLocker is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address existingAssetLocker = getAddress("AssetLocker");
		address proxyAdminAddr = getAddress("AssetLockerAdmin");
		
		TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(existingAssetLocker));
		ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddr);

		AssetLocker newAssetLockerImpl = new AssetLocker();
		console2.log("New AssetLockerImpl deployed at", address(newAssetLockerImpl));

		proxyAdmin.upgrade(proxy, address(newAssetLockerImpl));
		console2.log("AssetLocker upgraded to", address(newAssetLockerImpl));

		ProtocolDAO dao = ProtocolDAO(getAddress("ProtocolDAO"));
		dao.upgradeContract("AssetLocker", existingAssetLocker, existingAssetLocker);
		console2.log("AssetLocker upgrade registered in ProtocolDAO");

		saveAddress("AssetLockerImpl", address(newAssetLockerImpl));

		vm.stopBroadcast();
	}
}