// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {Timelock} from "../contracts/contract/Timelock.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeTokenggAVAXSyncRewards is Script, EnvironmentConfig {
	function run() external {
		// This script upgrades TokenggAVAX to add SYNC_REWARDS_ROLE access control and Guardian functions
		// The upgrade includes:
		// 1. Deploy new TokenggAVAX implementation without remediation fixes
		// 2. Generate upgrade transaction data

		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*                DEPLOY TokenggAVAX V4 IMPL                  */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		TokenggAVAX tokenggAVAXImplV5 = new TokenggAVAX();

		TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(getAddress("TokenggAVAX")));

		// Get the current admin from the proxy for reference
		TokenggAVAX currentToken = TokenggAVAX(payable(address(proxy)));
		address currentAdmin = currentToken.admin();

		saveAddress("TokenggAVAXImpl", address(tokenggAVAXImplV5));

		console2.log("TokenggAVAX V5 implementation deployed at:", address(tokenggAVAXImplV5));
		console2.log("Proxy address:", address(proxy));
		console2.log("Current admin:", currentAdmin);


		console2.log("\n=== GOVERNANCE TRANSACTION DATA ===");
		console2.log("ProxyAdmin address:", getAddress("TokenggAVAXAdmin"));
		console2.log("Function: upgrade(address,address)");
		console2.log("Proxy (arg 1):", address(proxy));
		console2.log("New Implementation (arg 2):", address(tokenggAVAXImplV5));

		// Generate complete Gnosis Safe transaction calldata
		bytes memory upgradeCallData = abi.encodeWithSelector(
			ProxyAdmin.upgrade.selector,
			address(proxy),
			address(tokenggAVAXImplV5)
		);

		console2.log("\n=== GNOSIS SAFE TRANSACTION ===");
		console2.log("To:", getAddress("TokenggAVAXAdmin"));
		console2.log("Value: 0");
		console2.log("Data:");
		console2.logBytes(upgradeCallData);

		bytes memory timelockData = abi.encodeWithSelector(Timelock.queueTransaction.selector, getAddress("TokenggAVAXAdmin"), upgradeCallData);

		console2.log("1. Queue the upgrade transaction with timelock:");
		console2.log("   To (timelock):", getAddress("Timelock"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(timelockData);

		vm.stopBroadcast();
	}
}
