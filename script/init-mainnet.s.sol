// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Ocyticus} from "../contracts/contract/Ocyticus.sol";
import {Oracle} from "../contracts/contract/Oracle.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {Storage} from "../contracts/contract/Storage.sol";

// After a mainnet deploy, initialize the protocol
contract InitMainnet is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		address rialto = vm.envAddress("RIALTO");

		vm.startBroadcast(deployer);

		// Run .initialize() for contracts that need it
		RewardsPool rewardsPool = RewardsPool(getAddress("RewardsPool"));
		rewardsPool.initialize();

		ProtocolDAO protocolDAO = ProtocolDAO(getAddress("ProtocolDAO"));
		protocolDAO.initialize();

		Storage s = Storage(getAddress("Storage"));
		s.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1 ether);

		if (rialto == address(0)) {
			console2.log("RIALTO not set, skipping register", rialto);
		} else {
			console2.log("Registering RIALTO as Multisig:", rialto);
			MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));
			multisigManager.registerMultisig(rialto);
			multisigManager.enableMultisig(rialto);
			payable(rialto).transfer(1 ether);
		}

		vm.stopBroadcast();
	}
}
