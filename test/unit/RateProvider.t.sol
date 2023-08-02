// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {GGAVAXRateProvider} from "../../contracts/contract/tokens/GGAVAXRateProvider.sol";

interface IggAVAX {
	function convertToAssets(uint256 shares) external view returns (uint256);
}

contract RateProviderTest is Test {
	uint256 mainnetFork;
	address ggAVAXAddr;
	IggAVAX ggAVAX;
	GGAVAXRateProvider rp;

	function setUp() public {
		mainnetFork = vm.createFork("https://api.avax.network/ext/bc/C/rpc");
		vm.selectFork(mainnetFork);

		ggAVAXAddr = address(0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3);
		vm.label(ggAVAXAddr, "ggAVAX");

		rp = new GGAVAXRateProvider(ggAVAXAddr);
	}

	function testRate() public {
		uint256 rate = rp.getRate();
		assertGt(rate, 1 ether);
		console2.log(rate);
	}
}
