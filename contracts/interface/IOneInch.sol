// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "@rari-capital/solmate/src/tokens/ERC20.sol";

interface IOneInch {
	function getRateToEth(ERC20 srcToken, bool useSrcWrappers) external view returns (uint256 weightedRate);
}
