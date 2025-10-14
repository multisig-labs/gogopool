// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {WithdrawQueue} from "../contracts/contract/WithdrawQueue.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeWithdrawQueue is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*                DEPLOY WITHDRAWQUEUE V3 IMPL                  */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		WithdrawQueue withdrawQueueImplV3 = new WithdrawQueue();

		// Get the existing proxy and admin
		TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(getAddress("WithdrawQueue")));
		ProxyAdmin proxyAdmin = ProxyAdmin(getAddress("WithdrawQueueAdmin"));

		saveAddress("WithdrawQueueImpl", address(withdrawQueueImplV3));

		console2.log("WithdrawQueue V3 implementation deployed at:", address(withdrawQueueImplV3));
		console2.log("Proxy address:", address(proxy));
		console2.log("ProxyAdmin address:", address(proxyAdmin));

		console2.log("\n=== GOVERNANCE TRANSACTION DATA ===");
		console2.log("ProxyAdmin address:", address(proxyAdmin));
		console2.log("Function: upgrade(address,address)");
		console2.log("Proxy (arg 1):", address(proxy));
		console2.log("New Implementation (arg 2):", address(withdrawQueueImplV3));

		// Generate complete Gnosis Safe transaction calldata
		bytes memory upgradeCallData = abi.encodeWithSignature("upgrade(address,address)", address(proxy), address(withdrawQueueImplV3));

		console2.log("\n=== GNOSIS SAFE TRANSACTION ===");
		console2.log("To:", address(proxyAdmin));
		console2.log("Value: 0");
		console2.log("Data:");
		console2.logBytes(upgradeCallData);

		vm.stopBroadcast();
	}
}
