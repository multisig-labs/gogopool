// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Storage} from "../contracts/contract/Storage.sol";

// After running deploy.s.sol and init-dev.s.sol
// we can register the real rialto
contract InitRialto is Script, EnvironmentConfig {
	function run() external onlyDev {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		address fakeRialto = getUser("fakerialto");
		address realRialto = vm.envAddress("RIALTO");

		MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));

		vm.startBroadcast(deployer);

		int256 idx = multisigManager.getIndexOf(fakeRialto);
		if (idx != -1) {
			console2.log("Unregistering fakerialto as Multisig...");
			multisigManager.disableMultisig(fakeRialto);
		}

		idx = multisigManager.getIndexOf(realRialto);
		if (idx == -1) {
			console2.log("Registering realRialto as Multisig...");
			multisigManager.registerMultisig(realRialto);
			multisigManager.enableMultisig(realRialto);
			payable(realRialto).transfer(1000 ether);
		}

		vm.stopBroadcast();
	}
}
