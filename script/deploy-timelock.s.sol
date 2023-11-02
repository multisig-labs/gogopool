// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {CREATE3Factory} from "../contracts/contract/utils/CREATE3Factory.sol";
import {Timelock} from "../contracts/contract/Timelock.sol";

contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		// Ensure deployer has enough funds to deploy protocol
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		CREATE3Factory fac;

		if (isContractDeployed("CREATE3Factory")) {
			console2.log("CREATE3Factory Factory exists, skipping...");
			fac = CREATE3Factory(getAddress("CREATE3Factory"));
		} else {
			fac = new CREATE3Factory();
			saveAddress("CREATE3Factory", address(fac));
		}

		if (isContractDeployed("Timelock")) {
			console2.log("Timelock exists, skipping...");
		} else {
			bytes memory creationCode = type(Timelock).creationCode;
			address addr = fac.deploy("Timelock", creationCode);
			saveAddress("Timelock", addr);
			// For Mainnet we xfer to Multisig
			// Timelock timelock = Timelock(addr);
			// address guardian = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;
			// timelock.transferOwnership(guardian);
		}

		vm.stopBroadcast();
	}
}
