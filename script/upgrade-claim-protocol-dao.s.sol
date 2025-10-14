// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {WithdrawQueue} from "../contracts/contract/WithdrawQueue.sol";
import {ClaimProtocolDAO} from "../contracts/contract/ClaimProtocolDAO.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeWithdrawQueue is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		console2.log("\n=== DEPLOYING CLAIM PROTOCOL DAO CONTRACT ===");

		ClaimProtocolDAO newClaimProtocolDAO = new ClaimProtocolDAO(Storage(getAddress("Storage")));
		console2.log("ClaimProtocolDAO deployed at:", address(newClaimProtocolDAO));

		saveAddress("ClaimProtocolDAO", address(newClaimProtocolDAO));

		console2.log("\n=== PROTOCOL DAO UPGRADE ACTION REQUIRED ===");
		bytes memory registerClaimProtocolDAOData = abi.encodeWithSelector(
			ProtocolDAO.upgradeContract.selector,
			"ClaimProtocolDAO",
			vm.envAddress("CLAIM_PROTOCOL_DAO"),
			address(newClaimProtocolDAO)
		);

		console2.log("\n5. Upgrade ProtocolDAO:");
		console2.log("   To (ProtocolDAO):", getAddress("ProtocolDAO"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(registerClaimProtocolDAOData);
	}
}
