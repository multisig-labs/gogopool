pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";

import {Staking} from "../contracts/contract/Staking.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {TokenGGP} from "../contracts/contract/tokens/TokenGGP.sol";
import {Vault} from "../contracts/contract/Vault.sol";

contract GetGGPRewards is EnvironmentConfig {
	function run() external {
		uint256 amount = 5 ether;

		loadAddresses();
		loadUsers();

		address deployer = getUser("deployer");

		vm.startBroadcast(deployer);

		TokenGGP ggp = TokenGGP(getAddress("TokenGGP"));
		ggp.approve(getAddress("Vault"), amount);

		Vault vault = Vault(getAddress("Vault"));
		vault.depositToken("ClaimNodeOp", ggp, amount);

		address me = vm.envAddress("MY_ADDR");
		Staking staking = Staking(getAddress("Staking"));
		int256 index = staking.requireValidStaker(me);

		Storage store = Storage(getAddress("Storage"));
		store.addUint(keccak256(abi.encodePacked("staker.item", index, ".ggpRewards")), amount);

		vm.stopBroadcast();
	}
}
