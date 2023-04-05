// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OneInchMock {
	uint256 public rateToEth = 1 ether;
	address public constant authorizedSetter = 0x7de56fe2bb806BA048FE95efc2f0C3547F539dc8;

	error NotAuthorized();

	function setRateToEth(uint256 rate) public {
		if (msg.sender != authorizedSetter) {
			revert NotAuthorized();
		}
		rateToEth = rate;
	}

	function getRateToEth(IERC20 srcToken, bool useSrcWrappers) external view returns (uint256 weightedRate) {
		srcToken; // silence linter
		useSrcWrappers; // silence linter
		weightedRate = rateToEth;
	}
}
