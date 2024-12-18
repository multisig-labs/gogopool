// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {ArtifactHardwareProvider} from "../contracts/contract/ArtifactHardwareProvider.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ClaimNodeOp} from "../contracts/contract/ClaimNodeOp.sol";
import {ClaimProtocolDAO} from "../contracts/contract/ClaimProtocolDAO.sol";
import {CREATE3Factory} from "../contracts/contract/utils/CREATE3Factory.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Multicall3} from "../contracts/contract/utils/Multicall3.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";
import {MinipoolStreamliner} from "../contracts/contract/MinipoolStreamliner.sol";
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

import {MockChainlinkPriceFeed} from "../test/unit/utils/MockChainlink.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// Deploying a single contract
contract HardwareProviderUpgrades is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address chainlinkPriceFeed;
		address wavax;
		address tjRouter;
		address guardian;
		address paymentReceiver;

		if (block.chainid == 43113) {
			MockChainlinkPriceFeed mockChainlinkPriceFeed = new MockChainlinkPriceFeed(deployer, 1 ether);
			chainlinkPriceFeed = address(mockChainlinkPriceFeed);
			mockChainlinkPriceFeed.setPrice(1 * 10 ** 8);
			console2.log("MockChainlinkPriceFeed", address(mockChainlinkPriceFeed));

			wavax = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
			tjRouter = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
			guardian = deployer;
		}

		if (block.chainid == 31337 || block.chainid == 43114) {
			chainlinkPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156;
			wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
			tjRouter = 0x18556DA13313f3532c54711497A8FedAC273220E;
			guardian = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;
		}

		////
		// Deploy Artifact Hardware Provider
		////
		ArtifactHardwareProvider artifactHardwareProvider = new ArtifactHardwareProvider(guardian, paymentReceiver, chainlinkPriceFeed);

		////
		// Deploy MinipoolStreamliner behind a proxy
		////
		Storage s = Storage(getAddress("Storage"));
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		MinipoolStreamliner minipoolStreamlinerImpl = new MinipoolStreamliner();
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(minipoolStreamlinerImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamliner.initialize.selector, s, wavax, tjRouter)
		);
		MinipoolStreamliner minipoolStreamliner = MinipoolStreamliner(payable(transparentProxy));

		// Transfer ownership to guardian
		proxyAdmin.transferOwnership(guardian);

		////
		// Deploy new MinipoolManager
		////
		MinipoolManager newMinipoolManager = new MinipoolManager(s);

		vm.stopBroadcast();

		guardianActions(guardian, deployer, minipoolStreamliner, artifactHardwareProvider, newMinipoolManager);

		saveAddress("ArtifactHardwareProvider", address(artifactHardwareProvider));
		saveAddress("MinipoolManager", address(newMinipoolManager));
		saveAddress("MinipoolStreamliner", address(minipoolStreamliner));
		saveAddress("MinipoolStreamlinerImpl", address(minipoolStreamlinerImpl));
		saveAddress("MinipoolStreamlinerAdmin", address(proxyAdmin));

		vm.stopPrank();
	}

	function guardianActions(
		address guardian,
		address deployer,
		MinipoolStreamliner minipoolStreamliner,
		ArtifactHardwareProvider artifactHardwareProvider,
		MinipoolManager newMinipoolManager
	) internal {
		ProtocolDAO pDao = ProtocolDAO(getAddress("ProtocolDAO"));
		address oldMinipoolManager = getAddress("MinipoolManager");
		////
		// Guardian actions
		////
		// ProtocolDAO::upgradeContract(MinipoolManager)
		// ProtocolDAO::setRole(Relauncher, MinipoolStreamliner)
		// MinipoolStreamliner::addHardwareProvider(hardwareProviderAddress)
		// artifactHardwareProvider.grantRole(artifactHardwareProvider.RENTER_ROLE(), address(minipoolStreamliner));
		if (block.chainid == 31337) {
			vm.startPrank(guardian);
			pDao.upgradeContract("MinipoolManager", oldMinipoolManager, address(newMinipoolManager));
			minipoolStreamliner.addHardwareProvider(artifactHardwareProvider.getHardwareProviderName(), address(artifactHardwareProvider));
			pDao.setRole("Relauncher", address(minipoolStreamliner), true);
			vm.stopPrank();
		}
		if (block.chainid == 43113) {
			vm.startBroadcast(deployer);
			pDao.upgradeContract("MinipoolManager", oldMinipoolManager, address(newMinipoolManager));
			minipoolStreamliner.addHardwareProvider(artifactHardwareProvider.getHardwareProviderName(), address(artifactHardwareProvider));
			pDao.setRole("Relauncher", address(minipoolStreamliner), true);
			vm.stopBroadcast();
		}
	}
}
