// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
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

		vm.startBroadcast(deployer);

		//roll back to old
		ProtocolDAO oldPdao = ProtocolDAO(address(0xbd2fdec34071246cF5a4843836b7e6eCfd2c6725));
		ProtocolDAO currentPdao = ProtocolDAO(address(0x3EA314a720E6D0Bc947F1B9A58d472893CAd477a));

		MinipoolManager oldMinipoolManager = MinipoolManager(address(0x0E28dc579992C8a93d20df1f3e3652F55fC59944));
		MinipoolManager currentMinipoolManager = MinipoolManager(address(0xC42D658635FF69d9df6b638540c861e0DE6023c2));

		currentPdao.upgradeContract("MinipoolManager", address(currentMinipoolManager), address(oldMinipoolManager));
		currentPdao.upgradeContract("ProtocolDAO", address(currentPdao), address(oldPdao));

		saveAddress("MinipoolManager", address(oldMinipoolManager));
		saveAddress("ProtocolDAO", address(oldPdao));

		vm.stopBroadcast();
	}
	// Following this: upgrade both minipool manager and staking and then register the streamlined Minipool contract address with oonodz. Make sure FE has correct addresses
}
