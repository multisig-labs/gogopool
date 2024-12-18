// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "./utils/BaseTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MinipoolStreamlinerV2} from "../../contracts/contract/MinipoolStreamlinerV2.sol";
import {Staking} from "../../contracts/contract/Staking.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {ClaimNodeOp} from "../../contracts/contract/ClaimNodeOp.sol";
import {RewardsPool} from "../../contracts/contract/RewardsPool.sol";
import {Oracle} from "../../contracts/contract/Oracle.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {MultisigManager} from "../../contracts/contract/MultisigManager.sol";
import {MinipoolManager} from "../../contracts/contract/MinipoolManager.sol";
import {MinipoolStatus} from "../../contracts/types/MinipoolStatus.sol";
import {TokenGGP} from "../../contracts/contract/tokens/TokenGGP.sol";
import {ProtocolDAO} from "../../contracts/contract/ProtocolDAO.sol";
import {IERC20} from "../../contracts/interface/IERC20.sol";
import {RialtoSimulator} from "../../contracts/contract/utils/RialtoSimulator.sol";
import {IHardwareProvider} from "../../contracts/interface/IHardwareProvider.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MockERC20} from "@rari-capital/solmate/src/test/utils/mocks/MockERC20.sol";

import {ILBRouter} from "../../contracts/interface/ILBRouter.sol";
import {MockLBRouter} from "./utils/MockLBRouter.sol";
import {MockHardwareProvider} from "./utils/MockHardwareProvider.sol";

contract MinipoolStreamlinerV2Test is BaseTest {
	address public nop;
	address relaunchNodeID;

	MinipoolStreamlinerV2 public mpstream;
	MockLBRouter public tjRouter;
	MockHardwareProvider public mockProvider;

	bytes private pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
	bytes private sig =
		hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
	bytes private blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

	bytes32 private defaultHardwareProvider = keccak256(abi.encodePacked("provider"));
	uint256 public defaultGGPStakeAmount = 0 ether;
	uint256 public defaultAVAXForGGP = 0 ether;
	uint256 public defaultMinGGPAmountOut = 110 ether;

	address private defaultNodeID;
	MinipoolStreamlinerV2.StreamlinedMinipool public defaultMinipool;
	MinipoolStreamlinerV2.StreamlinedMinipool[] public defaultMinipools;

	function setUp() public override {
		super.setUp();

		tjRouter = new MockLBRouter();
		tjRouter.setToken(address(ggp));

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		MinipoolStreamlinerV2 mpstreamImpl = new MinipoolStreamlinerV2();
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(mpstreamImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamlinerV2.initialize.selector, store, wavax, tjRouter)
		);
		mpstream = MinipoolStreamlinerV2(payable(transparentProxy));
		proxyAdmin.transferOwnership(guardian);

		nop = address(0x01);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		deal(address(ggp), address(nop), 1_000_000 ether);
		vm.prank(nop);
		ggp.approve(address(mpstream), 1_000_000 ether);

		mockProvider = new MockHardwareProvider();

		vm.startPrank(guardian, guardian);
		mpstream.addHardwareProvider(defaultHardwareProvider, address(mockProvider));
		dao.setRole("Relauncher", address(mpstream), true);
		vm.stopPrank();

		defaultNodeID = randAddress();
		defaultMinipool = MinipoolStreamlinerV2.StreamlinedMinipool(
			defaultNodeID,
			blsPubkeyAndSig,
			14 days, // duration
			1000 ether, // avaxForMinipool
			0 ether, // avaxForNodeRental
			defaultHardwareProvider
		);

		defaultMinipools.push(defaultMinipool);
	}

	/* *****************************************
							CREATION TESTS
	***************************************** */

	function testCreateNodeRentalWithGGP() public {
		vm.startPrank(nop);

		uint256 avaxForGGP = 110 ether;
		uint256 minGGPAmountOut = 110 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			minGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		assertEq(staking.getGGPStake(nop), avaxForGGP);
		assertEq(mockProvider.hasHardware(nop), true);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	function testCreateNodeRentalNoGGP() public {
		vm.startPrank(nop);

		ggp.approve(address(staking), 110 ether);
		staking.stakeGGP(110 ether);

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 0 ether;
		uint256 minGGPAmountOut = 0 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			minGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		assertEq(mockProvider.hasHardware(nop), true);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	function testCreateNoNodeRentalYesGGP() public {
		vm.startPrank(nop);

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.hardwareProvider = bytes32("");
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 110 ether;
		uint256 minGGPAmountOut = 110 ether;
		uint256 ggpStakeAmount = 0 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			minGGPAmountOut,
			ggpStakeAmount,
			newMinipools
		);

		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);

		assertEq(mockProvider.hasHardware(nop), false);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		vm.stopPrank();
	}

	function testCreateNoNodeRentalNoGGP() public {
		vm.startPrank(nop);

		ggp.approve(address(staking), 110 ether);
		staking.stakeGGP(110 ether);

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.hardwareProvider = bytes32("");
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 0 ether;
		uint256 minGGPAmountOut = 0 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			minGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		vm.stopPrank();
	}

	function testCreateStakeGGP() public {
		vm.startPrank(nop);

		uint256 ggpStakeAmount = 110 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + defaultAVAXForGGP + newMinipool.avaxForNodeRental}(
			defaultAVAXForGGP,
			defaultMinGGPAmountOut,
			ggpStakeAmount,
			newMinipools
		);

		assertEq(staking.getGGPStake(nop), ggpStakeAmount);
		assertEq(mockProvider.hasHardware(nop), true);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	// /* *****************************************
	// 						RELAUNCH TESTS
	// ***************************************** */

	function testRelaunchNotOwner() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Withdrawable));

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.nodeID = nodeId;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForNodeRental = 1 ether;
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		address notNop = randAddress();
		vm.deal(notNop, 1_000_000 ether);
		deal(address(ggp), address(notNop), 1_000_000 ether);

		vm.startPrank(notNop);
		vm.expectRevert(MinipoolStreamlinerV2.OnlyOwner.selector);
		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForNodeRental}(0, 0, 0, newMinipools);
	}

	function testRelaunchWithNodeRentalAndGGP() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Withdrawable));

		vm.startPrank(nop); // Test wallet

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		// minipool information
		newMinipool.nodeID = nodeId; //Withdrawable, NodeID-71qnqV56mmpvWK1Y4Qp6t5UNG87mH96Ko
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForNodeRental = 1 ether;
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 110 ether;
		uint256 nopPriorBalance = nop.balance - (avaxForGGP + newMinipool.avaxForNodeRental);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			defaultMinGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, minipool.avaxNodeOpRewardAmt);
	}

	function testRelaunchWithOonodzNoGGP() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Withdrawable));
		uint256 rewardAmount = minipool.avaxNodeOpRewardAmt;

		vm.startPrank(nop);

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.nodeID = nodeId;
		newMinipool.avaxForMinipool = 0 ether;
		newMinipool.avaxForNodeRental = 1 ether;
		newMinipool.hardwareProvider = defaultHardwareProvider;
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 0;

		uint256 nopPriorBalance = nop.balance - (avaxForGGP + newMinipool.avaxForNodeRental);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			defaultAVAXForGGP,
			defaultMinGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, rewardAmount);
	}

	function testRelaunchNoNodeRentalNoGGP() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		uint256 nopPriorBalance = nop.balance;
		uint256 rewardAmount = minipool.avaxNodeOpRewardAmt;

		vm.startPrank(nop);
		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.nodeID = nodeId;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.hardwareProvider = bytes32("");
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + defaultAVAXForGGP + newMinipool.avaxForNodeRental}(
			defaultAVAXForGGP,
			defaultMinGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		minipool = minipoolMgr.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;

		assertEq(nopBalanceDifference, rewardAmount);
	}

	function testRelaunchNoNodeRentalYesGGP() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		// States before Relaunch
		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		uint256 rewardAmount = minipool.avaxNodeOpRewardAmt;

		vm.startPrank(nop);

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.nodeID = nodeId; //withdrawable
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.hardwareProvider = bytes32("");
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		uint256 avaxForGGP = 110 ether;
		uint256 nopPriorBalance = nop.balance - avaxForGGP;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + avaxForGGP + newMinipool.avaxForNodeRental}(
			avaxForGGP,
			defaultMinGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);

		minipool = minipoolMgr.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, rewardAmount);
	}

	function testCreateOrRelaunchStreamlinedMinipoolInvalidHardwareProvider() public {
		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.hardwareProvider = bytes32("badProvider");
		newMinipool.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		newMinipools[0] = newMinipool;

		vm.expectRevert(abi.encodeWithSelector(MinipoolStreamlinerV2.InvalidHardwareProvider.selector, newMinipool.hardwareProvider));
		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + defaultAVAXForGGP + newMinipool.avaxForNodeRental}(
			defaultAVAXForGGP,
			defaultMinGGPAmountOut,
			defaultGGPStakeAmount,
			newMinipools
		);
	}

	// /* *****************************************
	// 						   BATCH TESTS
	// ***************************************** */

	function testBatchRelaunchWithNodeRentalAndGGP() public {
		address nodeId1 = randAddress();
		setUpRelaunch(nodeId1);
		address nodeId2 = randAddress();
		setUpRelaunch(nodeId2);

		MinipoolManager.Minipool memory minipool1 = minipoolMgr.getMinipoolByNodeID(nodeId1);
		assertEq(minipool1.status, uint256(MinipoolStatus.Withdrawable));

		MinipoolManager.Minipool memory minipool2 = minipoolMgr.getMinipoolByNodeID(nodeId2);
		assertEq(minipool2.status, uint256(MinipoolStatus.Withdrawable));

		vm.startPrank(nop); // Test wallet

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool1 = defaultMinipool;
		newMinipool1.nodeID = nodeId1;
		newMinipool1.avaxForMinipool = 0;
		newMinipool1.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool memory newMinipool2 = defaultMinipool;
		newMinipool2.nodeID = nodeId2;
		newMinipool2.avaxForMinipool = 0;
		newMinipool2.avaxForNodeRental = 1 ether;

		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](2);
		newMinipools[0] = newMinipool1;
		newMinipools[1] = newMinipool2;

		uint256 avaxForGGP = 110 ether;
		uint256 minGGPAmountOut = 110 ether;
		uint256 ggpStakeAmount = 0 ether;

		uint256 nopPriorBalance = nop.balance - (newMinipool1.avaxForNodeRental) - (newMinipool2.avaxForNodeRental) - avaxForGGP;

		mpstream.createOrRelaunchStreamlinedMinipool{
			value: newMinipool1.avaxForMinipool +
				newMinipool1.avaxForNodeRental +
				newMinipool2.avaxForMinipool +
				newMinipool2.avaxForNodeRental +
				avaxForGGP
		}(avaxForGGP, minGGPAmountOut, ggpStakeAmount, newMinipools);

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, minipool1.avaxNodeOpRewardAmt + minipool2.avaxNodeOpRewardAmt);
		// Should I also check the states of these minipools?

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool1.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);

		minipool = minipoolMgr.getMinipoolByNodeID(newMinipool2.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	function testBatchTooManyMinipools() public {
		uint256 minipoolCount = 11;
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](minipoolCount);
		newMinipools[0] = defaultMinipool;
		newMinipools[1] = defaultMinipool;
		newMinipools[2] = defaultMinipool;
		newMinipools[3] = defaultMinipool;
		newMinipools[4] = defaultMinipool;
		newMinipools[5] = defaultMinipool;
		newMinipools[6] = defaultMinipool;
		newMinipools[7] = defaultMinipool;
		newMinipools[8] = defaultMinipool;
		newMinipools[9] = defaultMinipool;
		newMinipools[10] = defaultMinipool;

		vm.startPrank(nop);
		vm.expectRevert(abi.encodeWithSelector(MinipoolStreamlinerV2.TooManyMinipools.selector, minipoolCount));
		mpstream.createOrRelaunchStreamlinedMinipool(defaultAVAXForGGP, defaultMinGGPAmountOut, defaultGGPStakeAmount, newMinipools);
		vm.stopPrank();
	}

	function testBatchMismatchedFunds() public {
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](2);
		MinipoolStreamlinerV2.StreamlinedMinipool memory minipool = defaultMinipool;
		minipool.avaxForMinipool = 1000 ether;
		minipool.avaxForNodeRental = 1 ether;

		newMinipools[0] = minipool;
		newMinipools[1] = minipool;

		uint256 expectedAvax = 2002 ether;
		vm.startPrank(nop);
		vm.expectRevert(MinipoolStreamlinerV2.MismatchedFunds.selector);
		mpstream.createOrRelaunchStreamlinedMinipool{value: expectedAvax + 1}(0, 0, 0, newMinipools);
		vm.stopPrank();
	}

	function testBatchInvalidHardwareProvider() public {
		MinipoolStreamlinerV2.StreamlinedMinipool[] memory newMinipools = new MinipoolStreamlinerV2.StreamlinedMinipool[](1);
		MinipoolStreamlinerV2.StreamlinedMinipool memory minipool = defaultMinipool;
		minipool.hardwareProvider = bytes32(keccak256("invalidprovider"));
		minipool.avaxForNodeRental = 1 ether;

		console2.log("miniipoolavax", minipool.avaxForMinipool);

		newMinipools[0] = minipool;

		vm.startPrank(nop);
		vm.expectRevert(abi.encodeWithSelector(MinipoolStreamlinerV2.InvalidHardwareProvider.selector, minipool.hardwareProvider));
		mpstream.createOrRelaunchStreamlinedMinipool{value: minipool.avaxForMinipool + minipool.avaxForNodeRental}(0, 0, 0, newMinipools);
		vm.stopPrank();

		minipool.avaxForNodeRental = 0 ether;
		newMinipools[0] = minipool;

		vm.prank(nop);
		mpstream.createOrRelaunchStreamlinedMinipool{value: minipool.avaxForMinipool + minipool.avaxForNodeRental}(0, 0, 100 ether, newMinipools);

		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(minipool.nodeID);
		assertEq(mp.status, uint8(MinipoolStatus.Prelaunch));
	}

	function setUpRelaunch(address nodeId) internal {
		// Fill liquid staking pool
		address liqStaker1 = getActorWithTokens("liqStaker1", 4000 ether, 0);
		vm.prank(liqStaker1);
		ggAVAX.depositAVAX{value: 4000 ether}();

		// Stake GGP and create minipool
		vm.startPrank(nop);
		ggp.approve(address(staking), 110 ether);
		staking.stakeGGP(110 ether);
		minipoolMgr.createMinipool{value: 1000 ether}(nodeId, 14 days, 20000, 1000 ether, blsPubkeyAndSig, defaultHardwareProvider);
		vm.stopPrank();

		// Start and cycle minipool
		vm.startPrank(guardian);
		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));
		rialto.processMinipoolStart(minipool.nodeID);
		skip(14 days);

		rialto.processMinipoolEndWithRewards(minipool.nodeID);
		minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint8(MinipoolStatus.Withdrawable));
		vm.stopPrank();
	}
}
