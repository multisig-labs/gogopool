// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ClaimNodeOp} from "../contracts/contract/ClaimNodeOp.sol";
import {ClaimProtocolDAO} from "../contracts/contract/ClaimProtocolDAO.sol";
import {CREATE3Factory} from "../contracts/contract/utils/CREATE3Factory.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Multicall3} from "../contracts/contract/utils/Multicall3.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {Ocyticus} from "../contracts/contract/Ocyticus.sol";
import {OneInchMock} from "../contracts/contract/utils/OneInchMock.sol";
import {Oracle} from "../contracts/contract/Oracle.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {Staking} from "../contracts/contract/Staking.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {TokenGGP} from "../contracts/contract/tokens/TokenGGP.sol";
import {Vault} from "../contracts/contract/Vault.sol";
import {WAVAX} from "../contracts/contract/utils/WAVAX.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Deploying a single contract
contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		// Ensure deployer has enough funds to deploy protocol
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		Storage s;

		s = Storage(getAddress("Storage"));

		Staking staking = new Staking(s);
		saveAddress("Staking", address(staking));

		vm.stopBroadcast();
	}
}
