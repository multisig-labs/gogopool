// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {TwapGGP} from "../../contracts/contract/TwapGGP.sol";
import {Oracle} from "../../contracts/contract/Oracle.sol";
import {IUniswapV2Pair} from "../../contracts/interface/IUniswapV2Pair.sol";
import {IWAVAX} from "../../contracts/interface/IWAVAX.sol";
import {IERC20} from "../../contracts/interface/IERC20.sol";

interface IJoeRouter01 {
	function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) external pure returns (uint256 amountOut);
}

contract TwapGGPTest is Test {
	uint256 mainnetFork;
	TwapGGP public twapGGP;
	address public tjpair;
	address public tjrouter;
	address public wavax;
	address public ggp;
	address public trader;
	address public guardian;

	function setUp() public {
		// Mainnet addrs
		mainnetFork = vm.createFork("https://api.avax.network/ext/bc/C/rpc");
		vm.selectFork(mainnetFork);

		tjpair = address(0xae671e0bF91CEaa4a6cB0D1294735EA3236d4586);
		vm.label(tjpair, "tjpair");

		tjrouter = address(0x60aE616a2155Ee3d9A68541Ba4544862310933d4);
		vm.label(tjrouter, "tjrouter");

		wavax = address(0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7);
		vm.label(wavax, "WAVAX");

		ggp = address(0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d);
		vm.label(ggp, "GGP");

		guardian = address(0x6C104D5b914931BA179168d63739A297Dc29bCF3);
		vm.label(guardian, "guardian");

		trader = address(0x01);
		vm.label(trader, "trader");
		vm.deal(trader, 1_000_000 ether);
		vm.prank(trader);
		IWAVAX(wavax).deposit{value: 1_000_000 ether}();
		twapGGP = new TwapGGP(tjpair, 86_400);
	}

	function testReplaceOneInchMock() public {
		Oracle oracle = Oracle(address(0x30fb915258D844E9dC420B2C3AA97420AEA16Db7));
		vm.prank(guardian);
		oracle.setTWAP(address(twapGGP));
		(uint256 p, ) = oracle.getGGPPriceInAVAXFromTWAP();
		assertEq(p, uint256(twapGGP.ggpTwapPriceInAVAX()));
	}

	function test1() public {
		logVars();
		skip(86_400);
		twapGGP.update();
		logPrices();
		assertEq(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("---------");

		console2.log("Skip 1 hour and Swap 1000 WAVAX -> GGP");
		skip(3600);
		doSwapWAVAXForGGP(1000 ether);
		logPrices();
		assertGt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("Skip 1 hour and Swap 1000 WAVAX -> GGP");
		skip(3600);
		doSwapWAVAXForGGP(1000 ether);
		logPrices();
		assertGt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("Skip 1 hour and Swap 1000 WAVAX -> GGP");
		skip(3600);
		doSwapWAVAXForGGP(1000 ether);
		logPrices();
		assertGt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("Skip 1 hour and Swap 1000 WAVAX -> GGP");
		skip(3600);
		doSwapWAVAXForGGP(1000 ether);
		logPrices();
		assertGt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("Skip 1 hour and Swap all GGP back to wavax");
		skip(3600);
		doSwapGGPForWAVAX(IERC20(ggp).balanceOf(trader));
		logPrices();
		assertLt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("Skip to end of 24 hour period and update twap checkpoint");
		skip(86_400 - 3600 * 5);
		twapGGP.update();
		logPrices();
		assertLt(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());

		console2.log("No new trades, skip 1 day and update twap checkpoint");
		skip(86_400);
		twapGGP.update();
		logPrices();
		assertEq(twapGGP.ggpSpotPriceInAVAX(), twapGGP.ggpTwapPriceInAVAX());
	}

	function doSwapWAVAXForGGP(uint256 wavaxAmt) internal {
		(uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(tjpair).getReserves();
		uint256 amountOut = IJoeRouter01(tjrouter).getAmountOut(wavaxAmt, reserve1, reserve0);
		vm.startPrank(trader);
		IWAVAX(wavax).transfer(tjpair, wavaxAmt);
		IUniswapV2Pair(tjpair).swap(amountOut, 0, trader, new bytes(0));
		vm.stopPrank();
	}

	function doSwapGGPForWAVAX(uint256 ggpAmt) internal {
		(uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(tjpair).getReserves();
		uint256 amountOut = IJoeRouter01(tjrouter).getAmountOut(ggpAmt, reserve0, reserve1);
		vm.startPrank(trader);
		IERC20(ggp).transfer(tjpair, ggpAmt);
		IUniswapV2Pair(tjpair).swap(0, amountOut, trader, new bytes(0));
		vm.stopPrank();
	}

	function logVars() public view {
		console2.log("blockTimestampLast", twapGGP.blockTimestampLast());
		console2.log("price0Average", twapGGP.price0Average());
		console2.log("price0CumulativeLast", twapGGP.price0CumulativeLast());
	}

	function logPrices() public view {
		console2.log("GGP Spot", twapGGP.ggpSpotPriceInAVAX());
		console2.log("GGP Twap", twapGGP.ggpTwapPriceInAVAX());
	}
}
