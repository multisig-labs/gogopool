pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MinipoolStatus} from "../contracts/types/MinipoolStatus.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {Staking} from "../contracts/contract/Staking.sol";

contract ChangeMinipool is Script, EnvironmentConfig {
	function run() external {
		uint256 amount = 5 ether;

		loadAddresses();
		loadUsers();

		address deployer = getUser("deployer");

		vm.startBroadcast(deployer);

		Storage store = Storage(getAddress("Storage"));
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
		// Staking staking = Staking(getAddress("Staking"));

		// address addr = address(0x5f019902149844fe8041d9c5627f61a67763294c);
		// Staking.Staker memory person = staking.getStaker(addr);

		// console2.log(person);
		int256[1] memory minipoolIndex = [int256(246)];
		// int256[] public myArray = [int256(218), 219, 220];

		for (uint256 i = 0; i < minipoolIndex.length; i++) {
			store.setUint(keccak256(abi.encodePacked("minipool.item", minipoolIndex[i], ".status")), uint256(MinipoolStatus.Withdrawable));
		}

		vm.stopBroadcast();
	}
}
