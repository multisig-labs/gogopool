// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import "./utils/BaseTest.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {MinipoolStreamliner} from "../../contracts/contract/MinipoolStreamliner.sol";
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

contract MockHardwareProvider is IHardwareProvider {
	mapping(address => bool) public hasHardware;

	function rentHardware(address user, address, uint256) external payable override {
		hasHardware[user] = true;
	}

	function getHardwareProviderName() public pure override returns (bytes32) {
		return keccak256("MockHardwareProvider");
	}
}

contract MockLBRouter is StdCheats {
	enum Version {
		V1,
		V2,
		V2_1
	}

	struct Path {
		uint256[] pairBinSteps;
		Version[] versions;
		IERC20[] tokenPath;
	}
	address token;
	uint256 bonusTokens;
	uint256 customAmount;

	constructor() {
		bonusTokens = 0;
	}

	function setToken(address newToken) public {
		token = newToken;
	}

	function setBonusTokens(uint256 bonusTokenAmount) public {
		bonusTokens = bonusTokenAmount;
	}

	function setCustomAmount(uint256 _customAmount) public {
		customAmount = _customAmount;
	}

	function swapExactNATIVEForTokens(
		uint256 amountOutMin,
		Path memory, // path
		address to,
		uint256 // deadline
	) external payable returns (uint256 amountOut) {
		uint256 amountToMint = customAmount;
		if (amountToMint == 0) {
			amountToMint = amountOutMin;
		}
		deal(address(token), address(to), amountToMint + bonusTokens);
		return amountToMint;
	}
}

contract MinipoolStreamlinerTest is BaseTest {
	address public nop;
	address relaunchNodeID;

	MinipoolStreamliner public mpstream;
	MockLBRouter public tjRouter;
	MockHardwareProvider public mockProvider;

	bytes private pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
	bytes private sig =
		hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
	bytes private blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

	bytes32 private defaultHardwareProvider = keccak256(abi.encodePacked("provider"));
	address private defaultNodeID;
	MinipoolStreamliner.StreamlinedMinipool public defaultMinipool;

	function setUp() public override {
		super.setUp();

		tjRouter = new MockLBRouter();
		tjRouter.setToken(address(ggp));

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		MinipoolStreamliner mpstreamImpl = new MinipoolStreamliner();
		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(mpstreamImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(MinipoolStreamliner.initialize.selector, store, wavax, tjRouter)
		);
		mpstream = MinipoolStreamliner(payable(transparentProxy));
		proxyAdmin.transferOwnership(guardian);

		nop = address(0x01);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		deal(address(ggp), address(nop), 1_000_000 ether);

		mockProvider = new MockHardwareProvider();

		vm.startPrank(guardian, guardian);
		mpstream.addHardwareProvider(defaultHardwareProvider, address(mockProvider));
		dao.setRole("Relauncher", address(mpstream), true);
		vm.stopPrank();

		defaultNodeID = randAddress();
		defaultMinipool = MinipoolStreamliner.StreamlinedMinipool(
			defaultNodeID,
			blsPubkeyAndSig,
			14 days, // duration
			1000 ether, // avaxForMinipool
			0 ether, // avaxForGGP
			110 ether, // minGGPAmountOut
			0 ether, // avaxForNodeRental
			0 ether, // ggpStakeAmount
			defaultHardwareProvider
		);
	}

	/* *****************************************
							CREATION TESTS
	***************************************** */

	function testCreateNodeRentalWithGGP() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.avaxForGGP = 110 ether;
		newMinipool.avaxForNodeRental = 1 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		assertEq(staking.getGGPStake(nop), newMinipool.avaxForGGP);
		assertEq(mockProvider.hasHardware(nop), true);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	function testCreateNodeRentalNoGGP() public {
		vm.startPrank(nop);

		ggp.approve(address(staking), 110 ether);
		staking.stakeGGP(110 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 1 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		assertEq(mockProvider.hasHardware(nop), true);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint8(MinipoolStatus.Prelaunch));
		assertEq(minipool.hardwareProvider, defaultHardwareProvider);
	}

	function testCreateNoNodeRentalYesGGP() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.hardwareProvider = bytes32("");
		newMinipool.avaxForGGP = 110 ether;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
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

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.hardwareProvider = bytes32("");

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		vm.stopPrank();
	}

	/* *****************************************
							RELAUNCH TESTS
	***************************************** */

	function testRelaunchWithNodeRentalAndGGP() public {
		address nodeId = randAddress();
		setUpRelaunch(nodeId);

		MinipoolManager.Minipool memory minipool = minipoolMgr.getMinipoolByNodeID(nodeId);
		assertEq(minipool.status, uint256(MinipoolStatus.Withdrawable));

		vm.startPrank(nop); // Test wallet

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		// minipool information
		newMinipool.nodeID = nodeId; //Withdrawable, NodeID-71qnqV56mmpvWK1Y4Qp6t5UNG87mH96Ko
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForGGP = 110 ether;
		newMinipool.avaxForNodeRental = 1 ether;

		uint256 nopPriorBalance = nop.balance - (newMinipool.avaxForGGP + newMinipool.avaxForNodeRental);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
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

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.nodeID = nodeId;
		newMinipool.avaxForMinipool = 0 ether;
		newMinipool.avaxForNodeRental = 1 ether;
		newMinipool.hardwareProvider = defaultHardwareProvider;

		uint256 nopPriorBalance = nop.balance - (newMinipool.avaxForGGP + newMinipool.avaxForNodeRental);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
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
		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		newMinipool.nodeID = nodeId;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.hardwareProvider = bytes32("");

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
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

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;

		// minipool information
		newMinipool.nodeID = nodeId; //withdrawable
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForGGP = 110 ether;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.hardwareProvider = bytes32("");

		uint256 nopPriorBalance = nop.balance - newMinipool.avaxForGGP;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		minipool = minipoolMgr.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, rewardAmount);
	}

	function testCreateOrRelaunchStreamlinedMinipoolInvalidHardwareProvider() public {
		MinipoolStreamliner.StreamlinedMinipool memory newMinipool = defaultMinipool;
		newMinipool.hardwareProvider = bytes32("badProvider");
		newMinipool.avaxForNodeRental = 1 ether;

		vm.expectRevert(abi.encodeWithSelector(MinipoolStreamliner.InvalidHardwareProvider.selector, newMinipool.hardwareProvider));
		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);
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
	}
}
