// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Oracle} from "../contracts/contract/Oracle.sol";

// After a Fuji deploy, initialize the protocol
contract InitFuji is Script, EnvironmentConfig {
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
		s.setUint(keccak256("ProtocolDAO.MinipoolCancelMoratoriumSeconds"), 60);
		s.setUint(keccak256("ProtocolDAO.MinipoolMinAVAXStakingAmt"), 2 ether);
		s.setUint(keccak256("ProtocolDAO.MinipoolMaxAVAXAssignment"), 1 ether);
		s.setUint(keccak256("ProtocolDAO.MinipoolMinAVAXAssignment"), 1 ether);
		s.setUint(keccak256("ProtocolDAO.MinipoolMinDuration"), 1 days);
		s.setUint(keccak256("ProtocolDAO.MinipoolMaxDuration"), 14 days);

		TokenggAVAX ggAVAX = TokenggAVAX(payable(getAddress("TokenggAVAX")));
		uint256 amt = 5 ether - ggAVAX.totalReleasedAssets();
		if (amt > 0) {
			console2.log("Topping up ggAVAX with amt: ", amt);
			ggAVAX.depositAVAX{value: amt}();
		}

		if (rialto == address(0)) {
			console2.log("RIALTO not set, registering fakerialto");
			address fakeRialto = getUser("fakerialto");
			rialto = fakeRialto;
			MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));
			int256 idx = multisigManager.getIndexOf(fakeRialto);
			if (idx == -1) {
				multisigManager.registerMultisig(fakeRialto);
				multisigManager.enableMultisig(fakeRialto);
				payable(fakeRialto).transfer(0.5 ether);
			}
		} else {
			console2.log("Registering RIALTO as Multisig:", rialto);
			MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));
			multisigManager.registerMultisig(rialto);
			multisigManager.enableMultisig(rialto);
			payable(rialto).transfer(1 ether);
		}

		vm.stopBroadcast();

		// Set initial GGP Price

		Oracle oracle = Oracle(getAddress("Oracle"));
		(uint256 priceInAVAX, ) = oracle.getGGPPriceInAVAX();
		if (priceInAVAX == 0) {
			vm.startBroadcast(rialto);
			oracle.setGGPPriceInAVAX(1 ether, block.timestamp);
			vm.stopBroadcast();
		}
	}
}
