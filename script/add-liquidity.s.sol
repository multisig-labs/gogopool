// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {console2} from "forge-std/console2.sol";

interface JoeRouter {
	function addLiquidity(
		address tokenA,
		address tokenB,
		uint256 amountADesired,
		uint256 amountBDesired,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);
}

interface JoeLPToken {
	function getReserves() external returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract AddLiquidity is Script, EnvironmentConfig {
	JoeRouter private joeRouter;
	JoeLPToken private joeLPToken;
	address private deployer;
	address private ggpTokenAddress;
	address private wAvax;
	uint256 private deadline;
	uint256 private amountADesired;
	uint256 private amountBDesired;
	uint256 private amountAMin;
	uint256 private amountBMin;

	function setUp() internal {
		joeRouter = JoeRouter(0xd7f655E3376cE2D7A2b08fF01Eb3B1023191A901);
		joeLPToken = JoeLPToken(0x6fc0aE8F34B011D81Fa3F89a3D877e5d7c7F9fb5);
		deployer = getUser("deployer");
		ggpTokenAddress = getAddress("TokenGGP");
		wAvax = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
		deadline = block.timestamp + 1000;
		amountADesired = 1 ether;
		amountBDesired = 1 ether;
		amountAMin = 0 ether;
		amountBMin = 0 ether;
	}

	function logPoolInfo() internal {
		(uint112 ggpInPool, uint112 wAvaxInPool, ) = joeLPToken.getReserves();
		console2.log("GGP in pool before: ", ggpInPool);
		console2.log("WAVAX in pool before: ", wAvaxInPool);
		console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
		console2.log("Desired GGP to add: ", amountADesired);
		console2.log("Desired WAVAX to add: ", amountBDesired);
		console2.log("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
	}

	function run() external {
		loadAddresses();
		loadUsers();
		setUp();
		logPoolInfo();

		vm.startBroadcast(deployer);
		ERC20(ggpTokenAddress).approve(address(joeRouter), amountADesired);
		ERC20(wAvax).approve(address(joeRouter), amountBDesired);
		(uint256 amountA, uint256 amountB, uint256 liquidity) = joeRouter.addLiquidity(
			ggpTokenAddress,
			wAvax,
			amountADesired,
			amountBDesired,
			amountAMin,
			amountBMin,
			deployer,
			deadline
		);
		console2.log("GGP added to pool: ", amountA);
		console2.log("WAVAX added to pool: ", amountB);
		console2.log("Total Liquidity: ", liquidity);
		vm.stopBroadcast();
	}
}
