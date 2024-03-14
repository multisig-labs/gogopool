// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
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
import {OonodzHardwareProvider} from "../../contracts/contract/OonodzHardwareProvider.sol";
import {IERC20} from "../../contracts/interface/IERC20.sol";
import {RialtoSimulator} from "../../contracts/contract/utils/RialtoSimulator.sol";

contract MinipoolStreamlinerTest is Test {
	uint256 mainnetFork;
	uint256 fujiFork;
	address public guardian;
	address public nop;

	Storage store;
	ProtocolDAO pdao;
	ProtocolDAO oldPdao;
	Staking staking;
	TokenGGP ggp;
	ClaimNodeOp nopClaim;
	RewardsPool rewardsPool;
	Oracle oracle;
	TokenggAVAX ggAvax;
	MultisigManager multisigManager;
	OonodzHardwareProvider oonodzHWP;

	MinipoolManager minipoolManager;
	MinipoolStreamliner mpstream;
	RialtoSimulator rialto;

	address usdc;
	address wavax;
	address tjRouter;
	uint256 private randNonce = 0;
	address relaunchNodeID;

	bytes private pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
	bytes private sig =
		hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
	bytes private blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

	function setUp() public {
		// Mainnet addrs
		// string memory MAINNET_RPC_URL = vm.envString("MAINNET_NODE");
		// mainnetFork = vm.createFork(MAINNET_RPC_URL);
		fujiFork = vm.createFork("https://api.avax-test.network/ext/bc/C/rpc");
		vm.selectFork(fujiFork);
		setUpFuji();

		// if (vm.activeFork() == mainnetFork) {
		// 	usdc = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
		// 	guardian = address(0x6C104D5b914931BA179168d63739A297Dc29bCF3);
		// 	store = Storage(address(0x1cEa17F9dE4De28FeB6A102988E12D4B90DfF1a9));
		// 	pdao = ProtocolDAO(address(0xA008Cc1839024A311ad769e4aC302EE35A8EF546));
		// 	ggp = TokenGGP(address(0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d));
		// } else {

		// if (vm.activeFork() == mainnetFork) {
		// 	mpstream = MinipoolStreamliner(address(0x0A75a480Af4ADC81b20b1664A1Da2bd7caEFA430));
		// 	vm.label(address(mpstream), "MinipoolStreamliner");
		// 	staking = Staking(address(0xB6dDbf75e2F0C7FC363B47B84b5C03959526AecB));
		// 	vm.label(address(staking), "Staking");
		// } else {
	}

	function setUpFuji() public {
		// users
		guardian = address(0x5e32bAb27EC0B44d490066385f827838C49b61E1);
		nop = address(0x01);

		vm.label(guardian, "guardian");
		vm.label(nop, "nop");

		// protocol contracts
		store = Storage(address(0x399D78327E665D21c8B9582D4843CA5DCA0e7dc4));
		oldPdao = ProtocolDAO(address(0xbd2fdec34071246cF5a4843836b7e6eCfd2c6725));
		staking = Staking(address(0x823de3b24C6461aA91234cFb42C571dEf8035B9b));
		ggp = TokenGGP(address(0xACdDAEfab64c8038ED294BAA45183Cf4d6454dF7));
		nopClaim = ClaimNodeOp(address(0x80436920F50c01b271A88A1E333C40744982c034));
		rewardsPool = RewardsPool(address(0xcbcB6Fb777c526b28Cc981Af8cf10592eBA02228));
		oracle = Oracle(address(0x115dfC5e48cc31ffadB007Ad376023f422d218BF));
		ggAvax = TokenggAVAX(payable(0x2630D024c0D34766E194E79C0fb079bDfFeb37dc));
		multisigManager = MultisigManager(address(0x23A1D61b199038b79888A43701BBfDaE27dAaBfB));

		vm.label(address(store), "Storage");
		vm.label(address(staking), "Staking");
		vm.label(address(ggp), "GGPToken");
		vm.label(address(nopClaim), "ClaimNodeOp");
		vm.label(address(rewardsPool), "RewardsPool");
		vm.label(address(oracle), "Oracle");
		vm.label(address(ggAvax), "TokenggAVAX");
		vm.label(address(multisigManager), "MultisigManager");

		// external contracts
		usdc = address(0xB6076C93701D6a07266c31066B298AeC6dd65c2d);
		wavax = address(0xd00ae08403B9bbb9124bB305C09058E32C39A48c);
		tjRouter = address(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);
		address oonodzWrapper = address(0xF82364d989A87791Ac2C6583B85DbC56DE7F2cf5);

		vm.label(address(usdc), "USDC");
		vm.label(address(wavax), "WAVAX");
		vm.label(address(tjRouter), "TJRouter");
		vm.label(address(oonodzWrapper), "ooNodzWrapper");

		// Construct all contracts as Guardian
		vm.startPrank(guardian, guardian);

		// deploy new contracts
		// minipoolManager = new MinipoolManager(store);
		// mpstream = new MinipoolStreamliner(store, wavax, tjRouter);
		// pdao = new ProtocolDAO(store);
		//BAD ONE
		// oonodzHWP = OonodzHardwareProvider(address(0x591D52Dac66A0ba20CF02fFe554cC48c73DA4F95));

		// oonodzHWP = OonodzHardwareProvider(address(0x9A177b38c998F35d924D7E38bF31DE43674b735C));

		minipoolManager = MinipoolManager(address(0xD28DB337F7D7FEFe5C257D337484c3f34545c933));
		mpstream = MinipoolStreamliner(address(0x159B5774F16823D1599cc25de4692B9891D9Cf0C));
		pdao = ProtocolDAO(address(0x92c79AcEDA6fc81931353eAB8c0882168aa7f106));
		oonodzHWP = OonodzHardwareProvider(address(0xE17298532EB44A5B52fcdD0A293192E782E01Ac8));

		vm.label(address(minipoolManager), "MinipoolManager");
		vm.label(address(mpstream), "MinipoolStreamliner");
		vm.label(address(pdao), "ProtocolDAO");
		vm.label(address(oonodzHWP), "OonodzHardwareProvider");

		// // register ProtocolDAO
		// oldPdao.upgradeContract("ProtocolDAO", address(oldPdao), address(pdao));

		// // register MinipoolManager
		// pdao.upgradeContract("MinipoolManager", address(0x0E28dc579992C8a93d20df1f3e3652F55fC59944), address(minipoolManager));

		// //register mpstream as a role
		// pdao.setRole("Relauncher", address(mpstream), true);

		// // register oonodzHW as an approved HW provider
		// pdao.setRole("HWProvider", address(oonodzHWP), true);

		// depoly and register Rialto
		rialto = new RialtoSimulator(minipoolManager, nopClaim, rewardsPool, staking, oracle, ggAvax);
		vm.label(address(rialto), "RialtoSimulator");

		multisigManager.registerMultisig(address(rialto));
		multisigManager.enableMultisig(address(rialto));
		multisigManager.disableMultisig(address(0x282e8c1a3c4A9F908dcb6194Fb6b19E03E23D4cb));
		rialto.setGGPPriceInAVAX(1 ether, block.timestamp);
		deal(address(rialto), type(uint128).max);
		vm.label(address(rialto), "RialtoSimulator");

		nop = address(0x01);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		ggp.transfer(address(nop), 10 ether);
		vm.stopPrank();
	}

	function randAddress() internal returns (address) {
		randNonce++;
		return address(uint160(uint256(randHash())));
	}

	function randHash() internal returns (bytes32) {
		randNonce++;
		return keccak256(abi.encodePacked(randNonce, blockhash(block.timestamp)));
	}

	function setUpRelaunch() internal {
		// create the minipool
		relaunchNodeID = randAddress();
		vm.startPrank(nop);
		ggp.approve(address(staking), 10 ether);
		staking.stakeGGP(1 ether);
		minipoolManager.createMinipool{value: 1 ether}(relaunchNodeID, 1 days, 20000, 1 ether, blsPubkeyAndSig);
		vm.stopPrank();

		vm.startPrank(guardian);

		MinipoolManager.Minipool memory minipool = minipoolManager.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool.status, uint256(MinipoolStatus.Prelaunch));
		rialto.processMinipoolStart(minipool.nodeID);

		skip(1 days);

		// move the minipool to withdrawable state
		rialto.processMinipoolEndWithRewards(minipool.nodeID);
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(minipool.nodeID);
		assertEq(minipool_1.status, uint256(MinipoolStatus.Withdrawable));

		// check that the minipool has rewards
		assertGt(minipool_1.avaxNodeOpRewardAmt, 0 ether);

		vm.stopPrank();
	}

	function testCreateRevertUnregisteredHWProvider() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = address(0);
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 1 ether;
		newMinipool.avaxForGGP = 110 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0.59 ether;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(2);
		uint16 countryOfResidence = 5;
		bool withdrawalRightWaiver = true;
		bool bestRate = true;
		uint256 minUSDCAmountOut = 0.00000000000000022 ether;
		uint256 tokenID = 0;

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);

		vm.expectRevert(MinipoolStreamliner.NotApprovedHardwareProvider.selector);
		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);
	}

	/* *****************************************
							CREATION TESTS
	***************************************** */

	function testCreateWithOonodzWithGGP() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = address(0);
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 1 ether;
		newMinipool.avaxForGGP = 110 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0.59 ether;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(oonodzHWP);
		uint16 countryOfResidence = 5;
		bool withdrawalRightWaiver = true;
		bool bestRate = true;
		uint256 minUSDCAmountOut = 0.00000000000000022 ether;
		uint256 tokenID = 0;

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		// no states to verify since we dont know the nodeID.
	}

	function testCreateWithOonodzNoGGP() public {
		vm.startPrank(nop);

		// must stake GGP prior to creating minipool
		ggp.approve(address(staking), 10 ether);
		staking.stakeGGP(1 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = address(0);
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 1 ether;
		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0.59 ether;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(oonodzHWP);
		uint16 countryOfResidence = 5;
		bool withdrawalRightWaiver = true;
		bool bestRate = true;
		uint256 minUSDCAmountOut = 0.00000000000000022 ether;
		uint256 tokenID = 0;

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		// no states to verify since we dont know the nodeID.
	}

	function testCreateNoNodeRentalYesGGP() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = randAddress();

		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 1 ether;
		newMinipool.avaxForGGP = 110 ether; //because we set it to 1:1 in the setup
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(0);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode("");

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);

		// verify states
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool_1.status, uint256(MinipoolStatus.Prelaunch));

		vm.stopPrank();
	}

	function testCreateNoNodeRentalNoGGP() public {
		vm.startPrank(nop);

		// must stake GGP prior to creating minipool
		ggp.approve(address(staking), 10 ether);
		staking.stakeGGP(1 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = randAddress();

		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 1 ether;
		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(0);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode("");

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);

		// verify states
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(newMinipool.nodeID);
		assertEq(minipool_1.status, uint256(MinipoolStatus.Prelaunch));

		vm.stopPrank();
	}

	/* *****************************************
							RELAUNCH TESTS
	***************************************** */

	function testRelaunchWithOonodzAndGGP() public {
		// NOTE: If this minipool is moved out of withdrawable status, this will fail. You will need to get another.

		address testWallet = address(0x8640577C7e9C906C6b1CdCeF532f030F21D2381A);
		address testNodeID = address(0x41F97B9701521bdA55e5ab2E19622C4A918aE4ea);

		// verify states
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(testNodeID);
		assertEq(minipool_1.status, uint256(MinipoolStatus.Withdrawable));

		vm.startPrank(testWallet); // Test wallet

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = testNodeID; //Withdrawable, NodeID-71qnqV56mmpvWK1Y4Qp6t5UNG87mH96Ko
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForGGP = 1 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0.39 ether;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(oonodzHWP);
		uint16 countryOfResidence = 5;
		bool withdrawalRightWaiver = true;
		bool bestRate = true;
		uint256 minUSDCAmountOut = 0.00000000000000022 ether;
		uint256 tokenID = 151; //NodeID-KNYw6wseN8Tmbx195uUqiTXBgWn7jKtWz

		uint256 nopPriorBalance = testWallet.balance - (newMinipool.avaxForGGP + newMinipool.avaxForNodeRental);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);
		console2.log(address(minipoolManager));

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		uint256 nopBalanceDifference = testWallet.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, minipool_1.avaxNodeOpRewardAmt);
	}

	function testRelaunchWithOonodzNoGGP() public {
		// NOTE: If this minipool is moved out of withdrawable status, this will fail. You will need to get another.

		address testWallet = address(0x8640577C7e9C906C6b1CdCeF532f030F21D2381A);
		address testNodeID = address(0x41F97B9701521bdA55e5ab2E19622C4A918aE4ea);

		// verify states
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(testNodeID);
		assertEq(minipool_1.status, uint256(MinipoolStatus.Withdrawable));

		vm.startPrank(testWallet); // Test wallet

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = testNodeID; //NodeID-71qnqV56mmpvWK1Y4Qp6t5UNG87mH96Ko
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 0 ether;
		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0.39 ether;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(oonodzHWP);
		uint16 countryOfResidence = 5;
		bool withdrawalRightWaiver = true;
		bool bestRate = true;
		uint256 minUSDCAmountOut = 0.00000000000000022 ether;
		uint256 tokenID = 151; //NodeID-71qnqV56mmpvWK1Y4Qp6t5UNG87mH96Ko

		uint256 nopPriorBalance = testWallet.balance - (newMinipool.avaxForGGP + newMinipool.avaxForNodeRental);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);
		console2.log(address(minipoolManager));

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		// verify states
		MinipoolManager.Minipool memory minipool_2 = minipoolManager.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool_2.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = testWallet.balance - nopPriorBalance;
		assertEq(nopBalanceDifference, minipool_1.avaxNodeOpRewardAmt);
	}

	function testRelaunchNoNodeRentalNoGGP() public {
		setUpRelaunch();

		// States before Relaunch
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(relaunchNodeID);
		uint256 nopPriorBalance = nop.balance;

		// relaunch
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = relaunchNodeID; //withdrawable
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForGGP = 0 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(0);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode(" ");

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		MinipoolManager.Minipool memory minipool_2 = minipoolManager.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool_2.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;

		assertEq(nopBalanceDifference, minipool_1.avaxNodeOpRewardAmt);
	}

	function testRelaunchNoNodeRentalYesGGP() public {
		setUpRelaunch();

		// States before Relaunch
		MinipoolManager.Minipool memory minipool_1 = minipoolManager.getMinipoolByNodeID(relaunchNodeID);

		// relaunch
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;

		// minipool information
		newMinipool.nodeID = relaunchNodeID; //withdrawable
		newMinipool.duration = 1 days;
		newMinipool.avaxForMinipool = 0;
		newMinipool.avaxForGGP = 1 ether;
		newMinipool.minGGPAmountOut = 0 ether;
		newMinipool.avaxForNodeRental = 0;
		newMinipool.blsPubkeyAndSig = blsPubkeyAndSig;

		// oonodz specific information
		newMinipool.hardwareProviderContract = address(0);

		// MUST be abi.encode, not abi.encodePacked
		newMinipool.hardwareProviderInformation = abi.encode("");

		uint256 nopPriorBalance = nop.balance - newMinipool.avaxForGGP;

		mpstream.createOrRelaunchStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(
			newMinipool
		);

		MinipoolManager.Minipool memory minipool_2 = minipoolManager.getMinipoolByNodeID(relaunchNodeID);
		assertEq(minipool_2.status, uint256(MinipoolStatus.Prelaunch));

		uint256 nopBalanceDifference = nop.balance - nopPriorBalance;

		assertEq(nopBalanceDifference, minipool_1.avaxNodeOpRewardAmt);
	}
}
