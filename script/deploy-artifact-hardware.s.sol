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
contract DeployContract is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 1 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address chainlinkPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156;
		address wavax;
		address tjRouter;
		address guardian;

		if (block.chainid == 43113) {
			MockChainlinkPriceFeed mockChainlinkPriceFeed = new MockChainlinkPriceFeed(deployer, 1 ether);
			chainlinkPriceFeed = address(mockChainlinkPriceFeed);
			mockChainlinkPriceFeed.setPrice(1 * 10 ** 8);
			console2.log("MockChainlinkPriceFeed", address(mockChainlinkPriceFeed));
			wavax = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
			tjRouter = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30;
			guardian = deployer;
		}

		ArtifactHardwareProvider artifactHardwareProvider = new ArtifactHardwareProvider(deployer, deployer, chainlinkPriceFeed);
		artifactHardwareProvider.setPayIncrementUsd(0.01 ether);
		artifactHardwareProvider.setPayPeriod(1 days);

		Storage s = Storage(getAddress("Storage"));

		MinipoolManager newMinipoolManager = new MinipoolManager(s);

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		MinipoolStreamliner minipoolStreamlinerImpl = new MinipoolStreamliner();
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(minipoolStreamlinerImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamliner.initialize.selector, s, wavax, tjRouter)
		);

		MinipoolStreamliner minipoolStreamliner = MinipoolStreamliner(payable(transparentProxy));
		proxyAdmin.transferOwnership(guardian);

		ProtocolDAO pDao = ProtocolDAO(getAddress("ProtocolDAO"));
		address oldMinipoolManager = getAddress("MinipoolManager");

		pDao.upgradeContract("MinipoolManager", oldMinipoolManager, address(newMinipoolManager));

		artifactHardwareProvider.grantRole(artifactHardwareProvider.RENTER_ROLE(), address(minipoolStreamliner));
		minipoolStreamliner.addHardwareProvider(artifactHardwareProvider.getHardwareProviderName(), address(artifactHardwareProvider));

		saveAddress("ArtifactHardwareProvider", address(artifactHardwareProvider));
		saveAddress("MinipoolManager", address(newMinipoolManager));
		saveAddress("MinipoolStreamliner", address(minipoolStreamliner));

		vm.stopBroadcast();
	}
}
