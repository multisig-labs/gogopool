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

contract UpgradeWithdrawQueue is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		vm.startBroadcast(deployer);
		console2.log("Deployer:", deployer);
		console2.log("Deployer balance:", deployer.balance);
		console2.log("chainid:", block.chainid);
		require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

		// Deploy all contracts
		deployWithdrawQueue();

		vm.stopBroadcast();
	}

	function deployWithdrawQueue() internal {
		console2.log("\n=== DEPLOYING WITHDRAW QUEUE CONTRACT ===");

		// Deploy new withdrawqueue implementation
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		console2.log("WithdrawQueue implementation deployed at", address(withdrawQueueImpl));

		ProxyAdmin withdrawQueueProxyAdmin = ProxyAdmin(getAddress("WithdrawQueueAdmin"));
		address withdrawQueueAddress = getAddress("WithdrawQueue");

		bytes memory upgradeCallData = abi.encodeWithSignature("upgrade(address,address)", address(withdrawQueueAddress), address(withdrawQueueImpl));

		console2.log("\n=== GOVERNANCE TRANSACTION DATA ===");
		console2.log("ProxyAdmin address:", getAddress("WithdrawQueueAdmin"));
		console2.log("Function: upgrade(address,address)");
		console2.log("Proxy (arg 1):", address(withdrawQueueAddress));
		console2.log("New Implementation (arg 2):", address(withdrawQueueImpl));

		console2.log("\n=== GNOSIS SAFE TRANSACTION ===");
		console2.log("To:", getAddress("WithdrawQueueAdmin"));
		console2.log("Value: 0");
		console2.log("Data:");
		console2.logBytes(upgradeCallData);

		saveAddress("WithdrawQueueImpl", address(withdrawQueueImpl));
	}
}

/*
❯ just forge-script upgrade-withdraw-queue-2 --broadcast
[⠊] Compiling...
No files changed, compilation skipped
Script ran successfully.

== Logs ==
  Deployer: 0xf5c149aCB200f5BC8FC5e51dF4a7DEf38d64cfB2
  Deployer balance: 1123186209760313098
  chainid: 43114

=== DEPLOYING WITHDRAW QUEUE CONTRACT ===
  WithdrawQueue implementation deployed at 0xf25DC803DbA114830b086e4Cc09CFDEBE2C10afD

=== GOVERNANCE TRANSACTION DATA ===
  ProxyAdmin address: 0x6e8fd36d51d159209054dADda7f87Aa4e1aED940
  Function: upgrade(address,address)
  Proxy (arg 1): 0x61f908D4992a790A2792D3C36850B4b9eB5849A3
  New Implementation (arg 2): 0xf25DC803DbA114830b086e4Cc09CFDEBE2C10afD

=== GNOSIS SAFE TRANSACTION ===
  To: 0x6e8fd36d51d159209054dADda7f87Aa4e1aED940
  Value: 0
  Data:
  0x99a88ec400000000000000000000000061f908d4992a790a2792d3c36850b4b9eb5849a3000000000000000000000000f25dc803dba114830b086e4cc09cfdebe2c10afd

## Setting up 1 EVM.

==========================

Chain 43114

Estimated gas price: 0.042703954 gwei

Estimated total gas used for script: 4264867

Estimated amount required: 0.000182126684184118 ETH

==========================

##### avalanche
✅  [Success] Hash: 0x4127aec618f4e98ac153120b1f9b7b73dd67c369980610163c60ca4328c21e61
Contract Address: 0xf25DC803DbA114830b086e4Cc09CFDEBE2C10afD
Block: 80592849
Paid: 0.000070026457927939 ETH (3281611 gas * 0.021339049 gwei)

✅ Sequence #1 on avalanche | Total Paid: 0.000070026457927939 ETH (3281611 gas * avg 0.021339049 gwei)


==========================

ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.

Transactions saved to: /Users/john/Code/GoGoPool/gogopool/broadcast/upgrade-withdraw-queue-2.s.sol/43114/run-latest.json

Sensitive values saved to: /Users/john/Code/GoGoPool/gogopool/cache/upgrade-withdraw-queue-2.s.sol/43114/run-latest.json
*/
