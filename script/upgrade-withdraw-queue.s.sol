// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {TokenpstAVAX} from "../contracts/contract/tokens/TokenpstAVAX.sol";
import {WithdrawQueue} from "../contracts/contract/WithdrawQueue.sol";
import {Timelock} from "../contracts/contract/Timelock.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {Storage} from "../contracts/contract/Storage.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeWithdrawQueue is Script, EnvironmentConfig {
	function run() external {

		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		vm.startBroadcast(deployer);
		console2.log("Deployer:", deployer);
		console2.log("Deployer balance:", deployer.balance);
		console2.log("chainid:", block.chainid);
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");


		// Deploy all contracts
		deployWithdrawQueue();

		vm.stopBroadcast();
	}

	function deployWithdrawQueue() internal {
		console2.log("\n=== DEPLOYING WITHDRAW QUEUE CONTRACT ===");

		// Deploy new withdrawqueue implementation
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		console2.log("WithdrawQueue implementation deployed at", address(withdrawQueueImpl));

		ProxyAdmin withdrawQueueProxyAdmin = ProxyAdmin(getAddress("WithdrawQueueAdmin"));
		address withdrawQueueAddress = getAddress("WithdrawQueue");

		bytes memory upgradeCallData = abi.encodeWithSignature("upgrade(address,address)", address(withdrawQueueAddress), address(withdrawQueueImpl));

		console2.log("\n=== GOVERNANCE TRANSACTION DATA ===");
		console2.log("ProxyAdmin address:", getAddress("WithdrawQueueAdmin"));
		console2.log("Function: upgrade(address,address)");
		console2.log("Proxy (arg 1):", address(withdrawQueueAddress));
		console2.log("New Implementation (arg 2):", address(withdrawQueueImpl));

		console2.log("\n=== GNOSIS SAFE TRANSACTION ===");
		console2.log("To:", getAddress("WithdrawQueueAdmin"));
		console2.log("Value: 0");
		console2.log("Data:");
		console2.logBytes(upgradeCallData);

		saveAddress("WithdrawQueueImpl", address(withdrawQueueImpl));
	}
}
