// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {MinipoolStreamliner} from "../../contracts/contract/MinipoolStreamliner.sol";
import {Staking} from "../../contracts/contract/Staking.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {MinipoolManager} from "../../contracts/contract/MinipoolManager.sol";
import {TokenGGP} from "../../contracts/contract/tokens/TokenGGP.sol";
import {ProtocolDAO} from "../../contracts/contract/ProtocolDAO.sol";
import {IERC20} from "../../contracts/interface/IERC20.sol";

contract MinipoolStreamlinerTest is Test {
	uint256 mainnetFork;
	uint256 fujiFork;
	address public nop;
	address public guardian;
	MinipoolManager minipoolManager;
	Staking staking;
	MinipoolStreamliner mpstream;
	Storage store;
	TokenGGP ggp;
	ProtocolDAO pdao;
	address usdc;
	uint256 private randNonce = 0;

	function setUp() public {
		// Mainnet addrs
		string memory MAINNET_RPC_URL = vm.envString("MAINNET_NODE");
		mainnetFork = vm.createFork(MAINNET_RPC_URL);
		fujiFork = vm.createFork("https://api.avax-test.network/ext/bc/C/rpc");
		vm.selectFork(fujiFork);

		if (vm.activeFork() == mainnetFork) {
			usdc = address(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
			guardian = address(0x6C104D5b914931BA179168d63739A297Dc29bCF3);
			store = Storage(address(0x1cEa17F9dE4De28FeB6A102988E12D4B90DfF1a9));
			pdao = ProtocolDAO(address(0xA008Cc1839024A311ad769e4aC302EE35A8EF546));
			ggp = TokenGGP(address(0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d));
		} else {
			usdc = address(0xB6076C93701D6a07266c31066B298AeC6dd65c2d);
			guardian = address(0x5e32bAb27EC0B44d490066385f827838C49b61E1);
			store = Storage(address(0x399D78327E665D21c8B9582D4843CA5DCA0e7dc4));
			pdao = ProtocolDAO(address(0xbd2fdec34071246cF5a4843836b7e6eCfd2c6725));
			staking = Staking(address(0x823de3b24C6461aA91234cFb42C571dEf8035B9b));
			minipoolManager = MinipoolManager(address(0x23A1D61b199038b79888A43701BBfDaE27dAaBfB));
			ggp = TokenGGP(address(0xACdDAEfab64c8038ED294BAA45183Cf4d6454dF7));
		}
		vm.label(guardian, "guardian");
		vm.label(address(store), "Storage");
		vm.label(address(pdao), "ProtocolDAO");

		// Construct all contracts as Guardian
		vm.startPrank(guardian, guardian);

		if (vm.activeFork() == mainnetFork) {
			mpstream = MinipoolStreamliner(address(0x0A75a480Af4ADC81b20b1664A1Da2bd7caEFA430));
			vm.label(address(mpstream), "MinipoolStreamliner");
			staking = Staking(address(0xB6dDbf75e2F0C7FC363B47B84b5C03959526AecB));
			vm.label(address(staking), "Staking");
		} else {
			mpstream = MinipoolStreamliner(address(0xEf0ECC0e63b9C262beC45D7EF27e75CF969534F0));
			vm.label(address(mpstream), "MinipoolStreamliner");
			staking = Staking(address(0x823de3b24C6461aA91234cFb42C571dEf8035B9b));
			vm.label(address(staking), "Staking");
		}

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

	function testCreateStreamlinedMinipool() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = address(0);
		newMinipool.countryOfResidence = 5;
		newMinipool.bestRate = true;
		newMinipool.withdrawalRightWaiver = true;

		if (vm.activeFork() == mainnetFork) {
			newMinipool.duration = 15 days;
			newMinipool.avaxForMinipool = 1000 ether;
			newMinipool.avaxForGGP = 110 ether;
			newMinipool.minGGPAmountOut = 0.1 ether;
			newMinipool.avaxForNodeRental = 1.1 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		} else {
			newMinipool.duration = 1 days;
			newMinipool.avaxForMinipool = 1 ether;
			newMinipool.avaxForGGP = 100 ether;
			newMinipool.minGGPAmountOut = 0 ether;
			newMinipool.avaxForNodeRental = 0.5 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		}

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(newMinipool);

		assertGt(IERC20(usdc).balanceOf(address(nop)), 0);
		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);
		vm.stopPrank();
	}

	function testCreateStreamlinedMinipoolNoGGP() public {
		vm.startPrank(nop);

		// user must have staked ggp before hand
		ggp.approve(address(staking), 10 ether);
		staking.stakeGGP(10 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = address(0);
		newMinipool.countryOfResidence = 5;
		newMinipool.bestRate = true;
		newMinipool.withdrawalRightWaiver = true;

		if (vm.activeFork() == mainnetFork) {
			newMinipool.duration = 15 days;
			newMinipool.avaxForMinipool = 1000 ether;
			newMinipool.avaxForGGP = 0 ether;
			newMinipool.minGGPAmountOut = 0.1 ether;
			newMinipool.avaxForNodeRental = 1.1 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		} else {
			newMinipool.duration = 1 days;
			newMinipool.avaxForMinipool = 1 ether;
			newMinipool.avaxForGGP = 0 ether;
			newMinipool.minGGPAmountOut = 0 ether;
			newMinipool.avaxForNodeRental = 0.5 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		}

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(newMinipool);

		assertGt(IERC20(usdc).balanceOf(address(nop)), 0);
		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);
		vm.stopPrank();
	}

	function testCreateStreamlinedMinipoolNoNodeRental() public {
		vm.startPrank(nop);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = randAddress();
		// newMinipool.nodeID = address(0);
		newMinipool.countryOfResidence = 0;
		newMinipool.bestRate = true;
		newMinipool.withdrawalRightWaiver = true;

		if (vm.activeFork() == mainnetFork) {
			newMinipool.duration = 15 days;
			newMinipool.avaxForMinipool = 1000 ether;
			newMinipool.avaxForGGP = 110 ether;
			newMinipool.minGGPAmountOut = 0.1 ether;
			newMinipool.avaxForNodeRental = 0 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		} else {
			newMinipool.duration = 1 days;
			newMinipool.avaxForMinipool = 1 ether;
			newMinipool.avaxForGGP = 100 ether;
			newMinipool.minGGPAmountOut = 0 ether;
			newMinipool.avaxForNodeRental = 0 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		}

		// assertEq(IERC20(usdc).balanceOf(address(nop)), 0);
		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(newMinipool);

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);
		vm.stopPrank();
	}

	function testCreateStreamlinedMinipoolNoGGPAndNoNodeRental() public {
		vm.startPrank(nop);

		// user must have staked ggp before hand
		ggp.approve(address(staking), 10 ether);
		staking.stakeGGP(10 ether);

		MinipoolStreamliner.StreamlinedMinipool memory newMinipool;
		newMinipool.nodeID = randAddress();
		newMinipool.countryOfResidence = 0;
		newMinipool.bestRate = true;
		newMinipool.withdrawalRightWaiver = true;

		if (vm.activeFork() == mainnetFork) {
			newMinipool.duration = 15 days;
			newMinipool.avaxForMinipool = 1000 ether;
			newMinipool.avaxForGGP = 0 ether;
			newMinipool.minGGPAmountOut = 0.1 ether;
			newMinipool.avaxForNodeRental = 0 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		} else {
			newMinipool.duration = 1 days;
			newMinipool.avaxForMinipool = 1 ether;
			newMinipool.avaxForGGP = 0 ether;
			newMinipool.minGGPAmountOut = 0 ether;
			newMinipool.avaxForNodeRental = 0 ether;
			newMinipool.minUSDCAmountOut = 0.00000000000000022 ether;
		}

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);

		mpstream.createStreamlinedMinipool{value: newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental}(newMinipool);

		assertEq(IERC20(usdc).balanceOf(address(mpstream)), 0);
		assertGt(staking.getGGPStake(address(nop)), 0);
		assertGt(staking.getCollateralizationRatio(address(nop)), 0.1 ether);
		vm.stopPrank();
	}
}
