// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {TokenpstAVAX} from "../contracts/contract/tokens/TokenpstAVAX.sol";
import {WithdrawQueue} from "../contracts/contract/WithdrawQueue.sol";
import {Timelock} from "../contracts/contract/Timelock.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {Storage} from "../contracts/contract/Storage.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeTokenggAVAX is Script, EnvironmentConfig {
	function run() external {
		// This script does the following:
		// 1. Deploy WithdrawQueue
		// 2. Grant WithrawQueue roles
		// 3. Transfer ownership of WithdrawQueue to Guardian
		// 4. Deploy TokenggAVAX V3 implementation
		// 5. Create calldata for reinitialization
		// 6. Create calldata for granting roles
		// 7. Deploy ProtocolDAO
		// 8. Create calldata to upgradeContract
		// 9. Deploy TokenpstAVAX
		// 10. Transfer ownership of TokenpstAVAX to Guardian

		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		address guardian = vm.envAddress("GUARDIAN");
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		// Deploy all contracts
		deployWithdrawQueue(deployer, guardian);
		deployTokenggAVAXV3();
		deployProtocolDAO();
		deployTokenpstAVAX(guardian);

		// Generate multisig transaction data
		generateMultisigTransactionData(guardian);

		vm.stopBroadcast();
	}

	function deployWithdrawQueue(address deployer, address guardian) internal {
		console2.log("\n=== DEPLOYING WITHDRAW QUEUE CONTRACT ===");

		uint48 unstakeDelay = uint48(vm.envUint("UNSTAKE_DELAY"));
		uint48 expirationDelay = uint48(vm.envUint("EXPIRATION_DELAY"));
		address depositor = vm.envAddress("DEPOSITOR_ROLE_RECIPIENT");

		ProxyAdmin withdrawQueueProxyAdmin = new ProxyAdmin();
		console2.log("WithdrawQueue ProxyAdmin deployed at", address(withdrawQueueProxyAdmin));

		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		console2.log("WithdrawQueue implementation deployed at", address(withdrawQueueImpl));

		TransparentUpgradeableProxy withdrawQueueProxy = new TransparentUpgradeableProxy(
			address(withdrawQueueImpl),
			address(withdrawQueueProxyAdmin),
			abi.encodeWithSelector(withdrawQueueImpl.initialize.selector, getAddress("TokenggAVAX"), unstakeDelay, expirationDelay)
		);
		console2.log("WithdrawQueue proxy deployed at", address(withdrawQueueProxy));
		console2.log("Default admin (deployer):", deployer);

		// Grant roles
		{
			WithdrawQueue withdrawQueue = WithdrawQueue(payable(address(withdrawQueueProxy)));
			withdrawQueue.grantRole(withdrawQueue.DEPOSITOR_ROLE(), address(depositor));
			withdrawQueue.grantRole(withdrawQueue.DEFAULT_ADMIN_ROLE(), address(guardian));
			withdrawQueue.renounceRole(withdrawQueue.DEFAULT_ADMIN_ROLE(), address(deployer));
		}

		saveAddress("WithdrawQueueImpl", address(withdrawQueueImpl));
		saveAddress("WithdrawQueue", address(withdrawQueueProxy));
		saveAddress("WithdrawQueueAdmin", address(withdrawQueueProxyAdmin));
	}

	function deployTokenggAVAXV3() internal {
		console2.log("\n=== DEPLOYING TOKENGGAVAX V3 IMPL ===");

		TokenggAVAX tokenggAVAXImplV3 = new TokenggAVAX();
		saveAddress("TokenggAVAXImpl", address(tokenggAVAXImplV3));

		console2.log("TokenggAVAX V3 implementation deployed at:", address(tokenggAVAXImplV3));
		console2.log("TokenggAVAX proxy address:", getAddress("TokenggAVAX"));
		console2.log("Default admin (guardian):", vm.envAddress("GUARDIAN"));
	}

	function deployProtocolDAO() internal {
		console2.log("\n=== DEPLOYING PROTOCOL DAO CONTRACT ===");

		ProtocolDAO newProtocolDAO = new ProtocolDAO(Storage(getAddress("Storage")));
		console2.log("ProtocolDAO deployed at:", address(newProtocolDAO));

		saveAddress("ProtocolDAO", address(newProtocolDAO));
	}

	function deployTokenpstAVAX(address guardian) internal {
		console2.log("\n=== DEPLOYING TOKENPSTAVAX CONTRACT ===");

		ProxyAdmin tokenpstAVAXProxyAdmin = new ProxyAdmin();
		console2.log("TokenpstAVAX ProxyAdmin deployed at", address(tokenpstAVAXProxyAdmin));

		TokenpstAVAX tokenpstAVAXImpl = new TokenpstAVAX();
		console2.log("TokenpstAVAX implementation deployed at", address(tokenpstAVAXImpl));

		TransparentUpgradeableProxy tokenpstAVAXProxy = new TransparentUpgradeableProxy(
			address(tokenpstAVAXImpl),
			address(tokenpstAVAXProxyAdmin),
			abi.encodeWithSelector(tokenpstAVAXImpl.initialize.selector, getAddress("TokenggAVAX"), getAddress("WithdrawQueue"))
		);
		console2.log("TokenpstAVAX proxy deployed at", address(tokenpstAVAXProxy));

		TokenpstAVAX tokenpstAVAX = TokenpstAVAX(payable(address(tokenpstAVAXProxy)));
		tokenpstAVAX.transferOwnership(guardian);

		saveAddress("TokenpstAVAXImpl", address(tokenpstAVAXImpl));
		saveAddress("TokenpstAVAX", address(tokenpstAVAXProxy));
		saveAddress("TokenpstAVAXAdmin", address(tokenpstAVAXProxyAdmin));
	}

	function generateMultisigTransactionData(address guardian) internal {
		// Generate TokenggAVAX upgrade calldata
		generateTokenggAVAXUpgradeData(guardian);

		// Generate ProtocolDAO upgrade calldata
		generateProtocolDAOUpgradeData();
	}

	function generateTokenggAVAXUpgradeData(address guardian) internal {
		console2.log("\n=== TOKENGGAVAX UPGRADE ACTIONS REQUIRED ===");
		console2.log("The following transactions must be executed in order via multisig:\n");

		// 1. Queue timelock transaction
		bytes memory upgradeCallData = abi.encodeWithSelector(
			ProxyAdmin.upgradeAndCall.selector,
			getAddress("TokenggAVAX"),
			getAddress("TokenggAVAXImpl"),
			abi.encodeWithSelector(TokenggAVAX.reinitialize.selector, guardian)
		);

		bytes memory timelockData = abi.encodeWithSelector(
			Timelock.queueTransaction.selector,
			getAddress("TokenggAVAXAdmin"),
			upgradeCallData
		);

		console2.log("1. Queue the upgrade transaction with timelock:");
		console2.log("   To (timelock):", getAddress("Timelock"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(timelockData);

		// Get role values from the new V3 implementation
		TokenggAVAX newImpl = TokenggAVAX(payable(getAddress("TokenggAVAXImpl")));
		bytes32 withdrawQueueRole = newImpl.WITHDRAW_QUEUE_ROLE();
		bytes32 stakerRole = newImpl.STAKER_ROLE();

		// 2. Grant withdraw queue role
		bytes memory grantWithdrawQueueRole = abi.encodeWithSelector(
			TokenggAVAX.grantRole.selector,
			withdrawQueueRole,
			getAddress("WithdrawQueue")
		);

		console2.log("\n2. Grant withdraw queue role:");
		console2.log("   To (TokenggAVAX):", getAddress("TokenggAVAX"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(grantWithdrawQueueRole);

		// 3. Grant staker role
		bytes memory grantStakerRole = abi.encodeWithSelector(
			TokenggAVAX.grantRole.selector,
			stakerRole,
			vm.envAddress("STAKER_ROLE_RECIPIENT")
		);

		console2.log("\n3. Grant staker role:");
		console2.log("   To (TokenggAVAX):", getAddress("TokenggAVAX"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(grantStakerRole);
	}

	function generateProtocolDAOUpgradeData() internal {
		console2.log("\n=== PROTOCOL DAO UPGRADE ACTION REQUIRED ===");

		bytes memory registerProtocolDAOData = abi.encodeWithSelector(
			ProtocolDAO.upgradeContract.selector,
			"ProtocolDAO",
			vm.envAddress("PROTOCOL_DAO"),
			getAddress("ProtocolDAO")
		);

		console2.log("4. Upgrade ProtocolDAO:");
		console2.log("   To (ProtocolDAO):", vm.envAddress("PROTOCOL_DAO"));
		console2.log("   Value: 0");
		console2.log("   Data:");
		console2.logBytes(registerProtocolDAOData);
	}
}
