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
		address lbRouterAddress = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;

		vm.startBroadcast(deployer);

		Storage s;

		s = Storage(getAddress("Storage"));

		MinipoolManager minipoolManager = new MinipoolManager(s);
		saveAddress("MinipoolManager", address(minipoolManager));

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		saveAddress("MinipoolStreamlinerAdmin", address(proxyAdmin));

		MinipoolStreamliner minipoolStreamlinerImpl = new MinipoolStreamliner();

		TransparentUpgradeableProxy minipoolStreamlinerProxy = new TransparentUpgradeableProxy(
			address(minipoolStreamlinerImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(minipoolStreamlinerImpl.initialize.selector, s, wavaxAddress, lbRouterAddress)
		);

		MinipoolStreamliner streamlinedMinipool = MinipoolStreamliner(payable(minipoolStreamlinerProxy));
		saveAddress("MinipoolStreamliner", address(streamlinedMinipool));

		ProtocolDAO pdao = new ProtocolDAO(s);
		saveAddress("ProtocolDAO", address(pdao));

		vm.stopBroadcast();
	}
}
