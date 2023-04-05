// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/StdJson.sol";
import {Storage} from "../contracts/contract/Storage.sol";

// Helper funcs for the deploy scripts
// Store deployed addresses in /deployed directory.
// Because vm.writeJson can only replace keys, not create them,
// we use a template json with all contracts listed out.

contract EnvironmentConfig is Script {
	error InvalidChain();
	error InvalidUser();
	error InvalidAddress();

	string public addressesJson;

	struct User {
		uint256 pk;
		address addr;
	}
	string[] public userNames = ["deployer", "rewarder", "faucet", "alice", "bob", "cam", "nodeOp1", "nodeOp2", "fakerialto"];
	mapping(string => User) public namedUsers;

	// Map keys derived from mnemonic to our list of userNames
	function loadUsers() public {
		string memory mnemonic = vm.envString("MNEMONIC");
		for (uint32 i; i < userNames.length; i++) {
			string memory name = userNames[i];
			uint256 pk = vm.deriveKey(mnemonic, i);
			address addr = vm.rememberKey(pk);
			namedUsers[name] = User(pk, addr);
		}
	}

	// TODO load all contracts into a map or something

	string[] public contractNames = [
		"Multicall3",
		"WAVAX",
		"CREATE3Factory",
		"OneInchMock",
		"Storage",
		"TokenggAVAXImpl",
		"TokenggAVAXAdmin",
		"TokenggAVAX",
		"TokenGGP",
		"ClaimNodeOp",
		"ClaimProtocolDAO",
		"MinipoolManager",
		"MultisigManager",
		"Ocyticus",
		"Oracle",
		"ProtocolDAO",
		"RewardsPool",
		"Staking",
		"Vault"
	];

	function verifyContracts() public {
		for (uint256 i; i < contractNames.length; i++) {
			address addr = getAddress(contractNames[i]);
			console2.log(contractNames[i], addr);
		}
	}

	function loadAddresses() public {
		// these are not global so that we can use with vm.startFork
		uint256 chainID = getChainId();
		string memory pathToDeploymentTemplate = string(abi.encodePacked(vm.projectRoot(), "/deployed/", vm.toString(chainID), "-addresses.tmpl.json"));
		string memory pathToDeploymentFile = string(abi.encodePacked(vm.projectRoot(), "/deployed/", vm.toString(chainID), "-addresses.json"));

		if (fileExists(pathToDeploymentFile)) {
			addressesJson = vm.readFile(pathToDeploymentFile);
		} else {
			// TODO auto-create a blank template for a chainid if none exists
			addressesJson = vm.readFile(pathToDeploymentTemplate);
			require(bytes(addressesJson).length != 0, "Address template not found!");
			vm.writeFile(pathToDeploymentFile, addressesJson);
		}
	}

	// Would be nice to just use MNEMONIC, but only setting --private-key on CLI seems to work.
	// function getDeployer() public returns (uint256 pk, address deployer) {
	// 	// string memory mnemonic = vm.envString("MNEMONIC");
	// 	// pk = vm.deriveKey(mnemonic, 0);
	// 	pk = vm.envUint("PRIVATE_KEY");
	// 	// deployer = vm.addr(pk);
	// 	deployer = vm.rememberKey(pk);
	// 	console2.log("Deployer:", deployer);
	// }

	function getChainId() public view returns (uint256) {
		console2.log("Current chain id:", block.chainid);
		return block.chainid;
	}

	function saveAddress(string memory name, address addr) public {
		// these are not global so that we can use with vm.startFork
		uint256 chainID = getChainId();
		string memory pathToDeploymentFile = string(abi.encodePacked(vm.projectRoot(), "/deployed/", vm.toString(chainID), "-addresses.json"));

		// key is a jq-ish locator of where to store data in the JSON
		string memory key = string(abi.encodePacked(".", name));
		require(keyExists(addressesJson, key), "Must update existing key");
		vm.writeJson(vm.toString(addr), pathToDeploymentFile, key);
		loadAddresses();
	}

	function getAddress(string memory name) public returns (address) {
		// key is a jq-ish locator of where to store data in the JSON
		string memory key = string(abi.encodePacked(".", name));
		address addr = vm.parseJsonAddress(addressesJson, key);
		if (addr == address(0)) {
			revert InvalidAddress();
		}
		vm.label(addr, name);
		return addr;
	}

	function getUser(string memory name) public returns (address) {
		address addr = namedUsers[name].addr;
		if (addr == address(0)) {
			revert InvalidUser();
		}
		vm.label(addr, name);
		return addr;
	}

	function isContractDeployed(string memory name) public returns (bool) {
		// key is a jq-ish locator of where to store data in the JSON
		string memory key = string(abi.encodePacked(".", name));
		address addr = vm.parseJsonAddress(addressesJson, key);
		return addr != address(0) && addr.code.length > 0;
	}

	function keyExists(string memory json, string memory key) internal pure returns (bool) {
		return vm.parseJson(json, key).length > 0;
	}

	// Must be better way?
	function fileExists(string memory path) internal returns (bool) {
		try vm.fsMetadata(path) {
			return true;
		} catch Error(string memory) {
			return false;
		} catch (bytes memory) {
			// data is �E &No such file or directory (os error 2)
			return false;
		}
	}

	function registerContract(Storage s, address addr, string memory name) internal {
		s.setBool(keccak256(abi.encodePacked("contract.exists", addr)), true);
		s.setAddress(keccak256(abi.encodePacked("contract.address", name)), addr);
		s.setString(keccak256(abi.encodePacked("contract.name", addr)), name);
		// console2.log("----");
		// console2.log("REG:", name);
		// console2.log("REG:", addr);
		// console2.logBytes32(keccak256(abi.encodePacked("contract.address", name)));
	}

	function isContractRegistered(Storage s, string memory name) internal returns (bool) {
		string memory key = string(abi.encodePacked(".", name));
		address addr = vm.parseJsonAddress(addressesJson, key);

		address regAddr = s.getAddress(keccak256(abi.encodePacked("contract.address", name)));
		string memory regName = s.getString(keccak256(abi.encodePacked("contract.name", regAddr)));
		bool regBool = s.getBool(keccak256(abi.encodePacked("contract.exists", regAddr)));

		if (addr != address(0) && regAddr != address(0) && keccak256(abi.encodePacked(regName)) == keccak256(abi.encodePacked(name)) && regBool) {
			return true;
		} else {
			console2.log("ERROR Contract not registered properly:");
			console2.log(name, addr);
			console2.log(name, regAddr);
			console2.log(name, regName);
			console2.log(name, regBool);
			console2.log(name, regAddr.code.length);
			return false;
		}
	}

	function checkContractRegistration(Storage s) public returns (bool) {
		bool result = isContractRegistered(s, "TokenggAVAX") &&
			isContractRegistered(s, "TokenGGP") &&
			isContractRegistered(s, "ClaimNodeOp") &&
			isContractRegistered(s, "ClaimProtocolDAO") &&
			isContractRegistered(s, "MinipoolManager") &&
			isContractRegistered(s, "MultisigManager") &&
			isContractRegistered(s, "Ocyticus") &&
			isContractRegistered(s, "Oracle") &&
			isContractRegistered(s, "ProtocolDAO") &&
			isContractRegistered(s, "RewardsPool") &&
			isContractRegistered(s, "Staking") &&
			isContractRegistered(s, "Vault");
		return result;
	}

	modifier onlyMainnet() {
		if (block.chainid != 43114) {
			console2.log("Script only allowed on Mainnet");
			revert InvalidChain();
		}
		_;
	}

	modifier onlyDev() {
		if (block.chainid == 43114) {
			console2.log("Script only allowed on development chains");
			revert InvalidChain();
		}
		_;
	}
}
