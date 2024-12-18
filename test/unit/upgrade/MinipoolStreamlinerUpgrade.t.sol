// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "../utils/BaseTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MinipoolStreamlinerV2} from "../../../contracts/contract/MinipoolStreamlinerV2.sol";
import {MinipoolStreamliner} from "../../../contracts/contract/MinipoolStreamliner.sol";
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
import {IHardwareProvider} from "../../../contracts/interface/IHardwareProvider.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MockERC20} from "@rari-capital/solmate/src/test/utils/mocks/MockERC20.sol";

import {ILBRouter} from "../../../contracts/interface/ILBRouter.sol";
import {MockLBRouter} from "../utils/MockLBRouter.sol";
import {MockHardwareProvider} from "../utils/MockHardwareProvider.sol";

contract MinipoolStreamlinerUpgradeTest is BaseTest {
	address public nop;
	address public constant DEPLOYER = address(12345);

	function setUp() public override {
		super.setUp();
	}

	function testUpgradeMinipoolStreamliner() public {
		MockLBRouter tjRouter = new MockLBRouter();
		tjRouter.setToken(address(ggp));
		MockHardwareProvider mockProvider = new MockHardwareProvider();
		bytes32 hardwareProviderName = keccak256(abi.encodePacked("provider"));
		bytes memory pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
		bytes
			memory sig = hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
		bytes memory blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		MinipoolStreamliner mpstreamImplV1 = new MinipoolStreamliner();
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(mpstreamImplV1),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamliner.initialize.selector, store, wavax, tjRouter)
		);
		MinipoolStreamliner mpstream = MinipoolStreamliner(payable(transparentProxy));

		assertEq(proxyAdmin.getProxyImplementation(transparentProxy), address(mpstreamImplV1));

		proxyAdmin.transferOwnership(guardian);

		// set and approved hardware provider
		vm.startPrank(guardian);
		mpstream.addHardwareProvider(hardwareProviderName, address(mockProvider));
		dao.setRole("Relauncher", address(mpstream), true);
		vm.stopPrank();

		// verify that the contract works with v1 data
		nop = address(0x01);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		deal(address(ggp), address(nop), 1_000_000 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = MinipoolStreamliner.StreamlinedMinipool(
			randAddress(),
			blsPubkeyAndSig,
			14 days, // duration
			1000 ether, // avaxForMinipool
			110 ether, // avaxForGGP
			110 ether, // minGGPAmountOut
			1 ether, // avaxForNodeRental
			0 ether, // ggpStakeAmount
			hardwareProviderName
		);

		vm.prank(nop);
		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		// store previous hardwareProviderAddress
		address hardwareProviderAddress = mpstream.approvedHardwareProviders(hardwareProviderName);

		// deploy new implemntation contract
		MinipoolStreamlinerV2 mpStreamImplV2 = new MinipoolStreamlinerV2();

		// upgrade
		vm.prank(guardian);
		proxyAdmin.upgrade(transparentProxy, address(mpStreamImplV2));
		MinipoolStreamlinerV2 mpstreamV2 = MinipoolStreamlinerV2(payable(address(mpstream)));

		// okay now verify hardwareProviderAddress is the same
		assertEq(mpstreamV2.approvedHardwareProviders(hardwareProviderName), hardwareProviderAddress);

		// and verify that we can still create a streamlined minipool
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

		vm.startPrank(nop);
		ggp.approve(address(mpstreamV2), 10 ether);
		mpstreamV2.createOrRelaunchStreamlinedMinipool{value: newMpV2.avaxForMinipool + 110 ether + newMpV2.avaxForNodeRental}(
			110 ether,
			110 ether,
			10 ether,
			newMinipoolsV2
		);
	}
}
