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

// Deploy script is idempotent based on addresses in ./deployed/<chainid>-addresses.json
// This will deploy the protocol for both dev and prod. An additional step after this
// will finalize the deploy for the correct environment
contract Deploy is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");

		// Ensure deployer has enough funds to deploy protocol
		require(deployer.balance > 4 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		CREATE3Factory fac;
		Storage s;

		if (isContractDeployed("CREATE3Factory")) {
			console2.log("CREATE3Factory Factory exists, skipping...");
			fac = CREATE3Factory(getAddress("CREATE3Factory"));
		} else {
			fac = new CREATE3Factory();
			saveAddress("CREATE3Factory", address(fac));
		}

		// If these don't exist (i.e. hardhat or ANR) then we will create them
		if (isContractDeployed("Multicall3")) {
			console2.log("Multicall3 exists, skipping...");
		} else {
			bytes memory multicallCode = type(Multicall3).creationCode;
			address multicallAddr = fac.deploy("Multicall3", multicallCode);
			saveAddress("Multicall3", multicallAddr);
		}

		if (isContractDeployed("WAVAX")) {
			console2.log("WAVAX exists, skipping...");
		} else {
			bytes memory wavaxCode = type(WAVAX).creationCode;
			address wavaxAddr = fac.deploy("WAVAX", wavaxCode);
			saveAddress("WAVAX", wavaxAddr);
		}

		if (isContractDeployed("OneInchMock")) {
			console2.log("OneInchMock exists, skipping...");
		} else {
			bytes memory oneInchMockCode = type(OneInchMock).creationCode;
			address oneInchMockAddr = fac.deploy("OneInchMock", oneInchMockCode);
			saveAddress("OneInchMock", oneInchMockAddr);
		}

		if (isContractDeployed("Storage")) {
			console2.log("Storage exists, skipping...");
		} else {
			bytes memory storageCode = type(Storage).creationCode;
			address storageAddr = fac.deploy("Storage", storageCode);
			saveAddress("Storage", storageAddr);
		}

		//
		// All following contracts will be registered with Storage
		// DO NOT change the order of these, as their addrs depend on
		// the deployer's nonce, and we want them to be stable across
		// dev deploys
		//

		s = Storage(getAddress("Storage"));

		if (isContractDeployed("ProtocolDAO")) {
			console2.log("ProtocolDAO exists, skipping...");
		} else {
			ProtocolDAO protocolDAO = new ProtocolDAO(s);
			registerContract(s, address(protocolDAO), "ProtocolDAO");
			// Not Initializing here, we do it in a later step
			saveAddress("ProtocolDAO", address(protocolDAO));
		}

		if (isContractDeployed("RewardsPool")) {
			console2.log("RewardsPool exists, skipping...");
		} else {
			RewardsPool rewardsPool = new RewardsPool(s);
			registerContract(s, address(rewardsPool), "RewardsPool");
			// Not Initializing here, we do it in a later step
			saveAddress("RewardsPool", address(rewardsPool));
		}

		if (isContractDeployed("TokenggAVAX")) {
			console2.log("TokenggAVAX exists, skipping...");
		} else {
			WAVAX wavax = WAVAX(payable(getAddress("WAVAX")));

			ProxyAdmin proxyAdmin = new ProxyAdmin();
			saveAddress("TokenggAVAXAdmin", address(proxyAdmin));

			TokenggAVAX ggAVAXImpl = new TokenggAVAX();
			saveAddress("TokenggAVAXImpl", address(ggAVAXImpl));

			TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
				address(ggAVAXImpl),
				address(proxyAdmin),
				abi.encodeWithSelector(ggAVAXImpl.initialize.selector, s, wavax, 0)
			);
			TokenggAVAX ggAVAX = TokenggAVAX(payable(ggAVAXProxy));
			registerContract(s, address(ggAVAX), "TokenggAVAX");
			ggAVAX.depositAVAX{value: 1 ether}();
			ggAVAX.syncRewards();
			saveAddress("TokenggAVAX", address(ggAVAX));
		}

		if (isContractDeployed("TokenGGP")) {
			console2.log("TokenGGP exists, skipping...");
		} else {
			TokenGGP tokenGGP = new TokenGGP(s);
			registerContract(s, address(tokenGGP), "TokenGGP");
			saveAddress("TokenGGP", address(tokenGGP));
		}

		if (isContractDeployed("Vault")) {
			console2.log("Vault exists, skipping...");
		} else {
			Vault vault = new Vault(s);
			registerContract(s, address(vault), "Vault");
			vault.addAllowedToken(getAddress("TokenGGP"));
			saveAddress("Vault", address(vault));
		}

		if (isContractDeployed("ClaimNodeOp")) {
			console2.log("ClaimNodeOp exists, skipping...");
		} else {
			ClaimNodeOp claimNodeOp = new ClaimNodeOp(s);
			registerContract(s, address(claimNodeOp), "ClaimNodeOp");
			saveAddress("ClaimNodeOp", address(claimNodeOp));
		}

		if (isContractDeployed("Oracle")) {
			console2.log("Oracle exists, skipping...");
		} else {
			Oracle oracle = new Oracle(s);
			registerContract(s, address(oracle), "Oracle");
			oracle.setTWAP(getAddress("OneInchMock"));
			saveAddress("Oracle", address(oracle));
		}

		if (isContractDeployed("ClaimProtocolDAO")) {
			console2.log("ClaimProtocolDAO exists, skipping...");
		} else {
			ClaimProtocolDAO claimProtocolDAO = new ClaimProtocolDAO(s);
			registerContract(s, address(claimProtocolDAO), "ClaimProtocolDAO");
			saveAddress("ClaimProtocolDAO", address(claimProtocolDAO));
		}

		if (isContractDeployed("MultisigManager")) {
			console2.log("MultisigManager exists, skipping...");
		} else {
			MultisigManager multisigManager = new MultisigManager(s);
			registerContract(s, address(multisigManager), "MultisigManager");
			saveAddress("MultisigManager", address(multisigManager));
		}

		if (isContractDeployed("MinipoolManager")) {
			console2.log("MinipoolManager exists, skipping...");
		} else {
			MinipoolManager minipoolManager = new MinipoolManager(s);
			registerContract(s, address(minipoolManager), "MinipoolManager");
			saveAddress("MinipoolManager", address(minipoolManager));
		}

		if (isContractDeployed("Ocyticus")) {
			console2.log("Ocyticus exists, skipping...");
		} else {
			Ocyticus ocyticus = new Ocyticus(s);
			registerContract(s, address(ocyticus), "Ocyticus");
			saveAddress("Ocyticus", address(ocyticus));
		}

		if (isContractDeployed("Staking")) {
			console2.log("Staking exists, skipping...");
		} else {
			Staking staking = new Staking(s);
			registerContract(s, address(staking), "Staking");
			saveAddress("Staking", address(staking));
		}

		bool result = checkContractRegistration(s);
		console2.log("Registration Successful?", result);

		vm.stopBroadcast();
	}
}
