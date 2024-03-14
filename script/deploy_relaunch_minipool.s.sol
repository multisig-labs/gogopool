// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Staking} from "../contracts/contract/Staking.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {MinipoolStreamliner} from "../contracts/contract/MinipoolStreamliner.sol";
import {OonodzHardwareProvider} from "../contracts/contract/OonodzHardwareProvider.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Deploying a single contract
contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		console.log("Deployer address: ", deployer);
		console.log("Deployer balance: ", deployer.balance);

		// Ensure deployer has enough funds to deploy protocol
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		// FUJI ADDRS
		// address wavaxAddress = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
		// address lbRouterAddress = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
		// address usdcAddress = 0xB6076C93701D6a07266c31066B298AeC6dd65c2d;
		// address oonodzWrapperAddress = 0xF82364d989A87791Ac2C6583B85DbC56DE7F2cf5;

		//MAINNET ADDRS
		address wavaxAddress = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
		address usdcAddress = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;
		address lbRouterAddress = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
		address oonodzWrapperAddress = 0x769Fc9b5038d8843895b50a904e04b58b0d4a9CB;

		address currentPdao = 0xA008Cc1839024A311ad769e4aC302EE35A8EF546;
		address currentMinipoolManager = 0xb84fA022c7fE1CE3a1F94C49f2F13236C3d1Ed08;

		vm.startBroadcast(deployer);

		Storage s;

		s = Storage(getAddress("Storage"));
		// ProtocolDAO oldPdao = ProtocolDAO(address(currentPdao));

		MinipoolManager minipoolManager = new MinipoolManager(s);
		saveAddress("MinipoolManager", address(minipoolManager));

		MinipoolStreamliner streamlinedMinipool = new MinipoolStreamliner(s, wavaxAddress, lbRouterAddress);
		saveAddress("MinipoolStreamliner", address(streamlinedMinipool));

		ProtocolDAO pdao = new ProtocolDAO(s);
		saveAddress("ProtocolDAO", address(pdao));

		OonodzHardwareProvider oonodzHWP = new OonodzHardwareProvider(
			wavaxAddress,
			usdcAddress,
			lbRouterAddress,
			oonodzWrapperAddress,
			address(streamlinedMinipool)
		);
		saveAddress("OonodzHardwareProvider", address(oonodzHWP));

		// register ProtocolDAO
		// oldPdao.upgradeContract("ProtocolDAO", address(oldPdao), address(pdao));

		// register MinipoolManager
		// pdao.upgradeContract("MinipoolManager", address(currentMinipoolManager), address(minipoolManager));

		//register mpstream as a role
		// pdao.setRole("Relauncher", address(streamlinedMinipool), true);

		//register guardian as a role
		// pdao.setRole("Relauncher", address(guardian), true);

		// register oonodzHW as an approved HW provider
		// pdao.setRole("HWProvider", address(oonodzHWP), true);

		vm.stopBroadcast();
	}
	// Following this: upgrade both minipool manager and staking and then register the OonodzHardwareProvider contract address with oonodz. Make sure FE has correct addresses
}
