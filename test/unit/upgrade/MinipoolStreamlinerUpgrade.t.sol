// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "../utils/BaseTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MinipoolStreamlinerV2} from "../../../contracts/contract/previousVersions/MinipoolStreamlinerV2.sol";
import {MinipoolStreamliner} from "../../../contracts/contract/MinipoolStreamliner.sol";
import {MinipoolStreamlinerV1} from "../../../contracts/contract/previousVersions/MinipoolStreamlinerV1.sol";
import {Staking} from "../../../contracts/contract/Staking.sol";
import {Storage} from "../../../contracts/contract/Storage.sol";
import {ClaimNodeOp} from "../../../contracts/contract/ClaimNodeOp.sol";
import {RewardsPool} from "../../../contracts/contract/RewardsPool.sol";
import {Oracle} from "../../../contracts/contract/Oracle.sol";
import {TokenggAVAX} from "../../../contracts/contract/tokens/TokenggAVAX.sol";
import {MultisigManager} from "../../../contracts/contract/MultisigManager.sol";
import {MinipoolManager} from "../../../contracts/contract/MinipoolManager.sol";
import {MinipoolStatus} from "../../../contracts/types/MinipoolStatus.sol";
import {TokenGGP} from "../../../contracts/contract/tokens/TokenGGP.sol";
import {ProtocolDAO} from "../../../contracts/contract/ProtocolDAO.sol";
import {IERC20} from "../../../contracts/interface/IERC20.sol";
import {RialtoSimulator} from "../../../contracts/contract/utils/RialtoSimulator.sol";
// import {IHardwareProvider} from "../../../contracts/interface/IHardwareProvider.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MockERC20} from "@rari-capital/solmate/src/test/utils/mocks/MockERC20.sol";

import {ILBRouter} from "../../../contracts/interface/ILBRouter.sol";
import {MockTraderJoeRouter} from "../utils/MockTraderJoeRouter.sol";
import {MockHardwareProvider} from "../utils/MockHardwareProvider.sol";
import {MockChainlinkPriceFeed} from "../utils/MockChainlink.sol";
import {SubnetHardwareRentalMapping} from "../../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {MockSubnetHardwareRental} from "../utils/MockSubnetHardwareRental.sol";

contract MinipoolStreamlinerUpgradeTest is BaseTest {
	address public nop;
	address public constant DEPLOYER = address(12345);
	bytes32 public hardwareProviderName;
	bytes public blsPubkeyAndSig;
	MockTraderJoeRouter public tjRouter;
	MockHardwareProvider public mockProvider;

	TransparentUpgradeableProxy public transparentProxy;

	function setUp() public override {
		uint256 fork = vm.createFork(vm.envString("FORK_URL"));
		vm.selectFork(fork);
		super.setUp();

		// Setup reusable test data
		hardwareProviderName = keccak256(abi.encodePacked("provider"));
		bytes memory pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
		bytes
			memory sig = hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
		blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

		tjRouter = new MockTraderJoeRouter();
		tjRouter.setToken(address(ggp));
		mockProvider = new MockHardwareProvider();
	}

	function setupV1() internal returns (MinipoolStreamlinerV1) {
		proxyAdmin = new ProxyAdmin();
		MinipoolStreamlinerV1 mpstreamImplV1 = new MinipoolStreamlinerV1();
		transparentProxy = new TransparentUpgradeableProxy(
			address(mpstreamImplV1),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamlinerV1.initialize.selector, store, wavax, tjRouter)
		);
		MinipoolStreamlinerV1 mpstream = MinipoolStreamlinerV1(payable(transparentProxy));

		assertEq(proxyAdmin.getProxyImplementation(transparentProxy), address(mpstreamImplV1));
		proxyAdmin.transferOwnership(guardian);

		vm.startPrank(guardian);
		mpstream.addHardwareProvider(hardwareProviderName, address(mockProvider));
		dao.setRole("Relauncher", address(mpstream), true);
		vm.stopPrank();

		return mpstream;
	}

	function setupV3(address mpstreamV2) internal returns (MinipoolStreamliner) {
		// Setup price feed
		MockChainlinkPriceFeed priceFeed = new MockChainlinkPriceFeed(guardian, 1 ether);

		ProxyAdmin subnetMappingProxyAdmin = new ProxyAdmin();
		SubnetHardwareRentalMapping subnetMappingImpl = new SubnetHardwareRentalMapping();
		TransparentUpgradeableProxy subnetMappingTransparentProxy = new TransparentUpgradeableProxy(
			address(subnetMappingImpl),
			address(subnetMappingProxyAdmin),
			abi.encodeWithSelector(
				SubnetHardwareRentalMapping.initialize.selector,
				guardian,
				address(priceFeed),
				0 days,
				0 ether,
				address(ggp),
				address(wavax),
				address(tjRouter)
			)
		);
		SubnetHardwareRentalMapping subnetMapping = SubnetHardwareRentalMapping(payable(subnetMappingTransparentProxy));
		subnetMappingProxyAdmin.transferOwnership(guardian);

		ProxyAdmin avalancheSubnetRentalProxyAdmin = new ProxyAdmin();
		MockSubnetHardwareRental avalancheSubnetRentalImpl = new MockSubnetHardwareRental();
		TransparentUpgradeableProxy avalancheSubnetRentalTransparentProxy = new TransparentUpgradeableProxy(
			address(avalancheSubnetRentalImpl),
			address(avalancheSubnetRentalProxyAdmin),
			abi.encodeWithSelector(
				MockSubnetHardwareRental.initialize.selector,
				guardian,
				address(priceFeed),
				15 days,
				60 ether,
				address(ggp),
				address(wavax),
				address(tjRouter)
			)
		);
		MockSubnetHardwareRental avalancheSubnetRental = MockSubnetHardwareRental(payable(avalancheSubnetRentalTransparentProxy));
		avalancheSubnetRentalProxyAdmin.transferOwnership(guardian);

		vm.startPrank(guardian);
		priceFeed.setPrice(1 * 10 ** 8);
		subnetMapping.addSubnetRentalContract(0x0000000000000000000000000000000000000000000000000000000000000000, address(avalancheSubnetRental)); // this has to be Avalanche because we actually look for this in minipoolstreamliner createOrRelaunch function
		avalancheSubnetRental.addHardwareProvider(hardwareProviderName, address(guardian));

		MinipoolStreamliner mpStreamImplV3 = new MinipoolStreamliner();
		proxyAdmin.upgradeAndCall(
			transparentProxy,
			address(mpStreamImplV3),
			abi.encodeWithSelector(MinipoolStreamliner.initialize.selector, address(subnetMapping))
		);

		vm.stopPrank();
		return MinipoolStreamliner(payable(mpstreamV2));
	}

	function setupNOP() internal {
		nop = address(0x01);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		deal(address(ggp), address(nop), 1_000_000 ether);
	}

	function testUpgradeMinipoolStreamliner() public {
		MinipoolStreamlinerV1 mpstreamV1 = setupV1();
		setupNOP();

		// Test V1
		MinipoolStreamlinerV1.StreamlinedMinipool memory newMinipoolV1 = MinipoolStreamlinerV1.StreamlinedMinipool(
			randAddress(),
			blsPubkeyAndSig,
			14 days,
			1000 ether,
			110 ether,
			110 ether,
			1 ether,
			0 ether,
			hardwareProviderName
		);

		vm.prank(nop);
		mpstreamV1.createOrRelaunchStreamlinedMinipool{value: newMinipoolV1.avaxForMinipool + newMinipoolV1.avaxForGGP + newMinipoolV1.avaxForNodeRental}(
			newMinipoolV1
		);

		address hardwareProviderAddressV1 = mpstreamV1.approvedHardwareProviders(hardwareProviderName);

		// Upgrade to V2
		MinipoolStreamlinerV2 mpStreamImplV2 = new MinipoolStreamlinerV2();
		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(transparentProxy, address(mpStreamImplV2), abi.encodeWithSelector(MinipoolStreamlinerV2.initialize.selector));
		MinipoolStreamlinerV2 mpstreamV2 = MinipoolStreamlinerV2(payable(address(mpstreamV1)));
		console2.log(address(mpstreamV2));

		assertEq(mpstreamV2.approvedHardwareProviders(hardwareProviderName), hardwareProviderAddressV1);

		// Test V2
		testV2Functionality(mpstreamV2);

		// Upgrade to V3
		MinipoolStreamliner mpstreamV3 = setupV3(address(mpstreamV2));

		// Test V3
		testV3Functionality(mpstreamV3, mpstreamV2);
	}

	function testV2Functionality(MinipoolStreamlinerV2 mpstreamV2) internal {
		MinipoolStreamlinerV2.StreamlinedMinipool memory newMpV2 = MinipoolStreamlinerV2.StreamlinedMinipool(
			randAddress(),
			blsPubkeyAndSig,
			14 days,
			1000 ether,
			1 ether,
			hardwareProviderName
		);

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipoolsV2 = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipoolsV2[0] = newMpV2;

		assertEq(mpstreamV2.batchLimit(), 10);
		assertEq(mpstreamV2.version(), 2);

		vm.startPrank(nop);
		ggp.approve(address(mpstreamV2), 10 ether);
		mpstreamV2.createOrRelaunchStreamlinedMinipool{value: newMpV2.avaxForMinipool + 110 ether + newMpV2.avaxForNodeRental}(
			110 ether,
			110 ether,
			10 ether,
			newMinipoolsV2
		);
		vm.stopPrank();
	}

	function testV3Functionality(MinipoolStreamliner mpstreamV3, MinipoolStreamlinerV2 mpstreamV2) internal {
		MinipoolStreamliner.StreamlinedMinipool memory newMpV3 = MinipoolStreamliner.StreamlinedMinipool(
			randAddress(),
			blsPubkeyAndSig,
			14 days,
			1000 ether,
			1 ether,
			hardwareProviderName
		);

		MinipoolStreamliner.StreamlinedMinipool[] memory newMinipoolsV3 = new MinipoolStreamliner.StreamlinedMinipool[](1);
		newMinipoolsV3[0] = newMpV3;

		assertEq(mpstreamV3.batchLimit(), mpstreamV2.batchLimit());
		assertEq(mpstreamV3.version(), 3);

		vm.startPrank(nop);
		ggp.approve(address(mpstreamV3), 10 ether); // Approve before transfer
		mpstreamV3.createOrRelaunchStreamlinedMinipool{value: newMpV3.avaxForMinipool + 110 ether + newMpV3.avaxForNodeRental}(
			110 ether,
			110 ether,
			10 ether,
			newMinipoolsV3
		);
		vm.stopPrank();
	}
}
