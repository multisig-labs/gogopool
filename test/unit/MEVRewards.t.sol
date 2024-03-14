// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {IWAVAX} from "../../contracts/interface/IWAVAX.sol";

interface IggAVAX {
	function convertToAssets(uint256 shares) external view returns (uint256);
}

contract MEVRewardsTest is Test {
	uint256 mainnetFork;
	address ggAVAXAddr;
	IggAVAX ggAVAX;
	address wavaxAddr;
	IWAVAX wavax;

	function setUp() public {
		mainnetFork = vm.createFork("https://api.avax.network/ext/bc/C/rpc");
		vm.selectFork(mainnetFork);

		ggAVAXAddr = address(0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3);
		vm.label(ggAVAXAddr, "ggAVAX");
		ggAVAX = IggAVAX(ggAVAXAddr);

		wavaxAddr = address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
		vm.label(wavaxAddr, "wavax");
		wavax = IWAVAX(wavaxAddr);
	}

  function testRate() public {
		uint256 currentRate = ggAVAX.convertToAssets(1 ether);
		console2.log("current rate:",currentRate);
		uint256 currentBalance = wavax.balanceOf(ggAVAXAddr);
		console2.log("current WAVAX balance:", currentBalance);

		address safe = address(0x01);
		vm.label(safe, "safe");
		vm.deal(safe, 1_000_000 ether);
		vm.startPrank(safe);
		wavax.deposit{value: 1_000_000 ether}();
		wavax.transfer(ggAVAXAddr, 278 ether);

		currentBalance = wavax.balanceOf(ggAVAXAddr);
		console2.log("WAVAX balance increased to:",currentBalance);

		currentRate = ggAVAX.convertToAssets(1 ether);
		console2.log("Rate should stay the same", currentRate);

		skip(14 days);

		currentRate = ggAVAX.convertToAssets(1 ether);
		console2.log("Rate after skipping 14 days:", currentRate);
	}
}
