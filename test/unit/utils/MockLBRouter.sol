// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {StdCheats} from "forge-std/StdCheats.sol";
import {IERC20} from "../../../contracts/interface/IERC20.sol";

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
