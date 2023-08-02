// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

interface IRateProvider {
	function getRate() external view returns (uint256);
}

interface IggAVAX {
	function convertToAssets(uint256 shares) external view returns (uint256);
}

/**
 * @title ggAVAX Rate Provider
 * @notice Returns the value of ggAVAX in terms of AVAX
 */
contract GGAVAXRateProvider is IRateProvider {
	IggAVAX public immutable ggAVAX;

	constructor(address addr) {
		ggAVAX = IggAVAX(addr);
	}

	/**
	 * @return the value of ggAVAX in terms of AVAX
	 */
	function getRate() external view override returns (uint256) {
		return ggAVAX.convertToAssets(1e18);
	}
}
