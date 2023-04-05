// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Storage} from "../contracts/contract/Storage.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ClaimNodeOp} from "../contracts/contract/ClaimNodeOp.sol";
import {ClaimProtocolDAO} from "../contracts/contract/ClaimProtocolDAO.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Ocyticus} from "../contracts/contract/Ocyticus.sol";
import {Oracle} from "../contracts/contract/Oracle.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {Staking} from "../contracts/contract/Staking.sol";
import {WAVAX} from "../contracts/contract/utils/WAVAX.sol";
import {TokenGGP} from "../contracts/contract/tokens/TokenGGP.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";

// forge script --slow --rpc-url=${ETH_RPC_URL} --private-key=${PRIVATE_KEY} --broadcast scripts/deploy.s.sol

// The /broadcast directory will have the details (including contract addresses) so after we deploy to a chain
// we can copy those to a /deployed folder and check them in to the repo

// Deploy will create contracts and register with storage
contract Deploy is Script, EnvironmentConfig {
	string[] public allContracts = [
		"ClaimNodeOp",
		"ClaimProtocolDAO",
		"MinipoolManager",
		"MultisigManager",
		"Ocyticus",
		"Oracle",
		"ProtocolDAO",
		"RewardsPool",
		"Staking"
	];

	string[] contracts = vm.envOr("CONTRACTS", ",", allContracts);

	function run() external {
		loadAddresses();

		Storage s = Storage(getAddress("Storage"));

		vm.startBroadcast();

		if (contains(contracts, "ProtocolDAO")) {
			ProtocolDAO protocolDAO = new ProtocolDAO(s);
			protocolDAO.registerContract(address(protocolDAO), "ProtocolDAO");
		}

		if (contains(contracts, "ClaimNodeOp")) {
			ClaimNodeOp claimNodeOp = new ClaimNodeOp(s);
			registerContract(s, "ClaimNodeOp", address(claimNodeOp));
		}

		if (contains(contracts, "Oracle")) {
			Oracle oracle = new Oracle(s);
			registerContract(s, "Oracle", address(oracle));
		}

		if (contains(contracts, "ClaimProtocolDAO")) {
			ClaimProtocolDAO claimProtocolDAO = new ClaimProtocolDAO(s);
			registerContract(s, "ClaimProtocolDAO", address(claimProtocolDAO));
		}

		if (contains(contracts, "MultisigManager")) {
			MultisigManager multisigManager = new MultisigManager(s);
			registerContract(s, "MultisigManager", address(multisigManager));
		}

		if (contains(contracts, "Ocyticus")) {
			Ocyticus ocyticus = new Ocyticus(s);
			registerContract(s, "Ocyticus", address(ocyticus));
		}

		if (contains(contracts, "RewardsPool")) {
			RewardsPool rewardsPool = new RewardsPool(s);
			registerContract(s, "RewardsPool", address(rewardsPool));
		}

		if (contains(contracts, "Staking")) {
			Staking staking = new Staking(s);
			registerContract(s, "Staking", address(staking));
		}

		vm.stopBroadcast();
		listRegisteredContracts(s);
	}

	// Register a contract in Storage
	function registerContract(Storage s, bytes memory name, address addr) internal {
		s.setBool(keccak256(abi.encodePacked("contract.exists", addr)), true);
		s.setAddress(keccak256(abi.encodePacked("contract.address", name)), addr);
		s.setString(keccak256(abi.encodePacked("contract.name", addr)), string(name));
	}

	function getRegisteredContract(Storage s, bytes memory name) internal view returns (address) {
		address addr = s.getAddress(keccak256(abi.encodePacked("contract.address", name)));
		require(addr != address(0), "Contract must be registered");
		return addr;
	}

	function listRegisteredContracts(Storage s) internal view {
		for (uint256 i = 0; i < contracts.length; i++) {
			string memory name = contracts[i];
			address addr = s.getAddress(keccak256(abi.encodePacked("contract.address", name)));
			bool exists = s.getBool(keccak256(abi.encodePacked("contract.exists", addr)));
			console2.log(name, addr);
			console2.log(name, exists);
		}
	}

	function contains(string[] memory haystack, string memory needle) public pure returns (bool) {
		for (uint256 i = 0; i < haystack.length; i++) {
			if (keccak256(abi.encodePacked(haystack[i])) == keccak256(abi.encodePacked(needle))) return true;
		}
		return false;
	}

	function compare(string memory s1, string memory s2) public pure returns (bool) {
		return keccak256(abi.encodePacked(s1)) == keccak256(abi.encodePacked(s2));
	}
}
