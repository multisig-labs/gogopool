// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../unit/utils/BaseTest.sol";
import {SubnetHardwareRentalBase} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalBase.sol";
import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {AvalancheHardwareRental} from "../../contracts/contract/hardwareProviders/AvalancheHardwareRental.sol";
import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import {ILBRouter} from "../../contracts/interface/ILBRouter.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";
import {MinipoolStreamliner} from "../../contracts/contract/MinipoolStreamliner.sol";
import {TokenGGP} from "../../contracts/contract/tokens/TokenGGP.sol";
import {console2} from "forge-std/console2.sol";
import {Staking} from "../../contracts/contract/Staking.sol";

contract TestFailure is BaseTest {
	MinipoolStreamliner public minipoolStreamliner;
	SubnetHardwareRentalMapping public subnetHardwareRentalMapping;

	address public nop;

	function setUp() public override {
		super.setUp();
		uint256 fork = vm.createFork(vm.envString("FORK_URL"));
		vm.selectFork(fork);

		subnetHardwareRentalMapping = SubnetHardwareRentalMapping(0x1c2DCA76502eb24cD9F98C5Cc8eAeE46D2685Edd);
		minipoolStreamliner = MinipoolStreamliner(0x9D2498375B7b1EB6262B421935B948C6adBe24e1);
		ggp = TokenGGP(0xACdDAEfab64c8038ED294BAA45183Cf4d6454dF7);
		staking = Staking(0x823de3b24C6461aA91234cFb42C571dEf8035B9b);
	}

	function testMinipoolStreamlinerFailure() public {
		// Test is only valid on Fuji
		if (block.chainid != 43113) {
			return;
		}
		bytes memory pubkey = hex"80817f8db58126d1b06a1fdce4a94b630c60f7b026dd6f516320fc53e13ffa7355d01dd8c8acf8b57a5d266de52bfe34";
		bytes
			memory sig = hex"81b3e5ceff61f2c9e6b424d6ac1209c0f8f24a2240d8875b9b686ce8b3e980eef7ce3e88564351cd23d855d49783621015eee95ab9b2591f723ed6e7a88a533bf9efca78876031cafbc6eefb833b90881bdef9d9673aab1a11214a7bea6e0179";
		bytes memory blsPubkeyAndSig = abi.encodePacked(pubkey, sig);
		setupNOP();
		bytes32 hardwareProviderName = keccak256(abi.encodePacked("Artifact"));
		MinipoolStreamliner.StreamlinedMinipool memory newMpV3 = MinipoolStreamliner.StreamlinedMinipool(
			randAddress(),
			blsPubkeyAndSig,
			25 hours,
			1 ether,
			0.01 ether,
			hardwareProviderName
		);

		MinipoolStreamliner.StreamlinedMinipool[] memory newMinipoolsV3 = new MinipoolStreamliner.StreamlinedMinipool[](1);
		newMinipoolsV3[0] = newMpV3;

		vm.startPrank(nop);
		// assertTrue(staking.getGGPStake(address(nop)) == 49180256258459173814);
		ggp.approve(address(minipoolStreamliner), 10 ether); // Approve before transfer

		minipoolStreamliner.createOrRelaunchStreamlinedMinipool{value: 1 ether + 0 ether + 0.01 ether}(0 ether, 0 ether, 0 ether, newMinipoolsV3);
		vm.stopPrank();
	}

	function setupNOP() internal {
		nop = address(0x8640577C7e9C906C6b1CdCeF532f030F21D2381A);
		vm.label(nop, "nop");
		vm.deal(nop, 1_000_000 ether);
		deal(address(ggp), address(nop), 1_000_000 ether);
	}
}
