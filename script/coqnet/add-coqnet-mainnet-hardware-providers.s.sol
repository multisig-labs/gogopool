// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {AvalancheHardwareRental} from "../../contracts/contract/hardwareProviders/AvalancheHardwareRental.sol";
import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import {EnvironmentConfig} from "../EnvironmentConfig.s.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract AddCoqnetMainnetHardwareProviders is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.5 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address guardian;

		if (block.chainid == 43114) {
			guardian = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;
		} else if (block.chainid == 43113) {
			guardian = deployer;
		} else {
			revert("Unsupported chain");
		}

		// SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(getAddress("SubnetHardwareRentalMapping"));
		// AvalancheHardwareRental avalancheHardwareRental = AvalancheHardwareRental(getAddress("AvalancheHardwareRental"));
		CoqnetHardwareRental coqnetHardwareRental = CoqnetHardwareRental(getAddress("CoqnetHardwareRental"));

		//Add approved hardware providers for coqnet
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Gogopool")), 0xf5c149aCB200f5BC8FC5e51dF4a7DEf38d64cfB2);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Artifact")), 0xba8Bcb4EB9a90D5A0eAe0098496703b49f909cB2);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("RedRobot")), 0x8cC385ae7d7575B9037eFAD483a703d64218d646);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("BlockchainServicesLabs")), 0x2bF0c31E3a2c23f67f3CD8efB9f92957DE1733A1);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Zalutions")), 0x18943179500f1Bd5a7d54b041487cf9739b94906);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Proviroll")), 0x4F93216Fa501db9793AA70f01FbD1F9Ad632fd94);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Jared")), 0xC7e212B916cC61F441EfD34916A1FE968D016b44);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("ChorusOne")), 0x624c4F9E55d2D1158fD5dee555C3bc8110b1E936);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("D6cGto6RZnJ")), 0x6bca018B1f51f918fdbF35DAD6EbA6dC64a74e06);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("T3nd0n")), 0xD7DC947035A4115b778E79C9b5f4D8D0981B863a);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Spaced")), 0x4874a38FAEd1aD404843943Cb08Df0453f4C59C5);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("0xNodeRunner")), 0x4F87C6Ed3A98fA0DdE80c29477504D1Bc0617fB0);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("ChristianS")), 0x6338104292Ca1b2B48c5eA7f57f55162a8750479);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("BakerMan")), 0xE0E6694EBD65D2691F5a67b0429d936020814e35);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("JoeE")), 0xF7A5601459555DFB5d46db6c5Ed56F11e26257d2);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Erwin")), 0x9ddC8496De24aD9A58c861A2498bf1FA0c8C3a5c);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("PaulT")), 0xD6b199946b3e34F239F606dA0a8024B8eCD390F5);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Spectura")), 0xD9cAfFBeE3CF1971Aec0B38cbd523bB99AdDC077);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("HaloAvax")), 0x2f51B1E265971A0B0b0A744AD3C075b55357626d);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Zwetschge")), 0x9F4dEAC7daFEC5243bc37358fB9B3589f864dc3A);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Polkachu")), 0xC653E9188532238A36Dd2c02d63eE1931F3E46F0);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Scorchio")), 0xA357AD734f3d6ab03E37e163E7675F0f1b7c1338);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("RR")), 0x8118ef85cc3303AB48Cbb4028B7d5c1a2CAec5bA);
		// coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Sanghren")), 0xff26CEAE36F279F40bf8cBfc7Cef0C28cf616ede);
		coqnetHardwareRental.addHardwareProvider(keccak256(abi.encodePacked("Altostake")), 0x5b70B89BDa20d056231D5bc2027a448Dfc19C26D);

		// console.logString("Name | Bytes32 | Address");

		// console.logString("Gogopool");
		// console.logBytes32(keccak256(abi.encodePacked("Gogopool")));
		// console.logAddress(0xf5c149aCB200f5BC8FC5e51dF4a7DEf38d64cfB2);
		// console.logString("Artifact");
		// console.logBytes32(keccak256(abi.encodePacked("Artifact")));
		// console.logAddress(0xba8Bcb4EB9a90D5A0eAe0098496703b49f909cB2);
		// console.logString("RedRobot");
		// console.logBytes32(keccak256(abi.encodePacked("RedRobot")));
		// console.logAddress(0x8cC385ae7d7575B9037eFAD483a703d64218d646);
		// console.logString("BlockchainServicesLabs");
		// console.logBytes32(keccak256(abi.encodePacked("BlockchainServicesLabs")));
		// console.logAddress(0x2bF0c31E3a2c23f67f3CD8efB9f92957DE1733A1);
		// console.logString("Zalutions");
		// console.logBytes32(keccak256(abi.encodePacked("Zalutions")));
		// console.logAddress(0x18943179500f1Bd5a7d54b041487cf9739b94906);
		// console.logString("Proviroll");
		// console.logBytes32(keccak256(abi.encodePacked("Proviroll")));
		// console.logAddress(0x4F93216Fa501db9793AA70f01FbD1F9Ad632fd94);
		// console.logString("Jared");
		// console.logBytes32(keccak256(abi.encodePacked("Jared")));
		// console.logAddress(0xC7e212B916cC61F441EfD34916A1FE968D016b44);
		// console.logString("ChorusOne");
		// console.logBytes32(keccak256(abi.encodePacked("ChorusOne")));
		// console.logAddress(0x624c4F9E55d2D1158fD5dee555C3bc8110b1E936);
		// console.logString("D6cGto6RZnJ");
		// console.logBytes32(keccak256(abi.encodePacked("D6cGto6RZnJ")));
		// console.logAddress(0x6bca018B1f51f918fdbF35DAD6EbA6dC64a74e06);
		// console.logString("T3nd0n");
		// console.logBytes32(keccak256(abi.encodePacked("T3nd0n")));
		// console.logAddress(0xD7DC947035A4115b778E79C9b5f4D8D0981B863a);
		// console.logString("Spaced");
		// console.logBytes32(keccak256(abi.encodePacked("Spaced")));
		// console.logAddress(0x4874a38FAEd1aD404843943Cb08Df0453f4C59C5);
		// console.logString("0xNodeRunner");
		// console.logBytes32(keccak256(abi.encodePacked("0xNodeRunner")));
		// console.logAddress(0x4F87C6Ed3A98fA0DdE80c29477504D1Bc0617fB0);
		// console.logString("ChristianS");
		// console.logBytes32(keccak256(abi.encodePacked("ChristianS")));
		// console.logAddress(0x6338104292Ca1b2B48c5eA7f57f55162a8750479);
		// console.logString("BakerMan");
		// console.logBytes32(keccak256(abi.encodePacked("BakerMan")));
		// console.logAddress(0xE0E6694EBD65D2691F5a67b0429d936020814e35);
		// console.logString("JoeE");
		// console.logBytes32(keccak256(abi.encodePacked("JoeE")));
		// console.logAddress(0xF7A5601459555DFB5d46db6c5Ed56F11e26257d2);
		// console.logString("Erwin");
		// console.logBytes32(keccak256(abi.encodePacked("Erwin")));
		// console.logAddress(0x9ddC8496De24aD9A58c861A2498bf1FA0c8C3a5c);
		// console.logString("PaulT");
		// console.logBytes32(keccak256(abi.encodePacked("PaulT")));
		// console.logAddress(0xD6b199946b3e34F239F606dA0a8024B8eCD390F5);
		// console.logString("Spectura");
		// console.logBytes32(keccak256(abi.encodePacked("Spectura")));
		// console.logAddress(0xD9cAfFBeE3CF1971Aec0B38cbd523bB99AdDC077);
		// console.logString("HaloAvax");
		// console.logBytes32(keccak256(abi.encodePacked("HaloAvax")));
		// console.logAddress(0x2f51B1E265971A0B0b0A744AD3C075b55357626d);
		// console.logString("Zwetschge");
		// console.logBytes32(keccak256(abi.encodePacked("Zwetschge")));
		// console.logAddress(0x9F4dEAC7daFEC5243bc37358fB9B3589f864dc3A);
		// console.logString("Polkachu");
		// console.logBytes32(keccak256(abi.encodePacked("Polkachu")));
		// console.logAddress(0xC653E9188532238A36Dd2c02d63eE1931F3E46F0);
		// console.logString("Scorchio");
		// console.logBytes32(keccak256(abi.encodePacked("Scorchio")));
		// console.logAddress(0xA357AD734f3d6ab03E37e163E7675F0f1b7c1338);
		// console.logString("RR");
		// console.logBytes32(keccak256(abi.encodePacked("RR")));
		// console.logAddress(0x8118ef85cc3303AB48Cbb4028B7d5c1a2CAec5bA);
		// console.logString("Sanghren");
		// console.logBytes32(keccak256(abi.encodePacked("Sanghren")));
		// console.logAddress(0xff26CEAE36F279F40bf8cBfc7Cef0C28cf616ede);
		console.logString("Altostake");
		console.logBytes32(keccak256(abi.encodePacked("Altostake")));
		console.logAddress(0x5b70B89BDa20d056231D5bc2027a448Dfc19C26D);

		//AFTER THAT: Remove deployer as owner for mapping contract, and role for subnet contracts

		vm.stopBroadcast();
	}
}
