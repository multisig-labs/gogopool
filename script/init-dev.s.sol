// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Oracle} from "../contracts/contract/Oracle.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {TokenGGP} from "../contracts/contract/tokens/TokenGGP.sol";

// After a fresh deploy, setup a dev env with the modified DAO settings,
// register a fake rialto, fund ggAVAX, and fund users
contract InitDev is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		address fakeRialto = getUser("fakerialto");

		vm.startBroadcast(deployer);

		Storage s = Storage(getAddress("Storage"));

		// Run .initialize() for contracts that need it
		RewardsPool rewardsPool = RewardsPool(getAddress("RewardsPool"));
		rewardsPool.initialize();

		ProtocolDAO protocolDAO = ProtocolDAO(getAddress("ProtocolDAO"));
		protocolDAO.initialize();

		// Override settings directly for Dev
		s.setUint(keccak256("ProtocolDAO.RewardsEligibilityMinSeconds"), 1);
		s.setUint(keccak256("ProtocolDAO.RewardsCycleSeconds"), 600);
		s.setUint(keccak256("ProtocolDAO.InflationIntervalSeconds"), 120);
		// 50% annual inflation with 1min periods
		// (1 + targetAnnualRate) ** (1 / intervalsPerYear) * 1000000000000000000
		s.setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1000000771433151600);
		s.setUint(keccak256("ProtocolDAO.MinipoolCancelMoratoriumSeconds"), 60);
		s.setUint(keccak256("ProtocolDAO.MinipoolMinDuration"), 2 minutes);

		TokenggAVAX ggAVAX = TokenggAVAX(payable(getAddress("TokenggAVAX")));
		uint256 amt = 100_000 ether - ggAVAX.totalReleasedAssets();
		if (amt > 0) {
			console2.log("Topping up ggAVAX with amt: ", amt);
			ggAVAX.depositAVAX{value: amt}();
		}

		console2.log("Funding users with AVAX...");
		for (uint256 i = 1; i < userNames.length; i++) {
			payable(getUser(userNames[i])).transfer(10_000 ether);
		}

		console2.log("Funding nodeOp1/2 with GGP...");
		TokenGGP ggp = TokenGGP(getAddress("TokenGGP"));
		ggp.transfer(getUser("nodeOp1"), 1000 ether);
		ggp.transfer(getUser("nodeOp2"), 1000 ether);

		console2.log("Registering fakerialto as Multisig...");
		MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));
		int256 idx = multisigManager.getIndexOf(fakeRialto);
		if (idx == -1) {
			multisigManager.registerMultisig(fakeRialto);
			multisigManager.enableMultisig(fakeRialto);
			payable(fakeRialto).transfer(0.5 ether);
		}

		vm.stopBroadcast();

		// Set initial GGP Price
		Oracle oracle = Oracle(getAddress("Oracle"));
		vm.startBroadcast(fakeRialto);
		oracle.setGGPPriceInAVAX(1 ether, block.timestamp);
		vm.stopBroadcast();
	}
}
