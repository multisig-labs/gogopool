// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import "../interface/IGoGoPoolHardwareProvider.sol";
import {IERC20} from "../interface/IERC20.sol";
import {IOonodzEntryPoint} from "../interface/IOonodzEntryPoint.sol";
import {ILBRouter} from "../interface/ILBRouter.sol";
import {MinipoolStreamliner} from "../contract/MinipoolStreamliner.sol";

contract OonodzHardwareProvider is IGoGoPoolHardwareProvider {
	error InvalidSender();
	error SwapFailed();
	event USDCRefunded(address receiver, uint256 amount);
	event HardwareRentedFromOonodz(address nodeID, bytes blsPubkeyAndSig);

	address internal USDC_ADDR;
	address internal WAVAX_ADDR;
	address internal JOE_LB_ROUTER;
	address internal OONODZ_WRAPPER_ADDR;
	address internal MINIPOOL_STREAMLINER_ADDR;

	constructor(address wavax, address usdc, address tjRouter, address ooNodz, address minipoolStreamliner) {
		WAVAX_ADDR = wavax;
		USDC_ADDR = usdc;
		JOE_LB_ROUTER = tjRouter;
		OONODZ_WRAPPER_ADDR = ooNodz;
		MINIPOOL_STREAMLINER_ADDR = minipoolStreamliner;
	}

	/// @notice Rent hardware from oonodz
	/// @param user The user that is renting the hardware
	/// @param newMinipool struct containing all information necessary to create or relaunch a minipool
	/// @return nodeID The nodeID of the rented hardware and blsPubkeyAndSig The BLS keys of the rented hardware
	function rentHardware(
		address user,
		MinipoolStreamliner.StreamlinedMinipool memory newMinipool
	) public payable override returns (address nodeID, bytes memory blsPubkeyAndSig) {
		if (msg.sender != MINIPOOL_STREAMLINER_ADDR) {
			revert InvalidSender();
		}
		(uint16 countryOfResidence, bool withdrawalRightWaiver, bool bestRate, uint256 minUSDCAmountOut, uint256 tokenID) = decodeOonodzData(
			newMinipool.hardwareProviderInformation
		);

		IERC20 usdc = IERC20(USDC_ADDR);
		uint256 usdcPurchased = swapAvaxForUSDC(newMinipool.avaxForNodeRental, minUSDCAmountOut);

		usdc.approve(OONODZ_WRAPPER_ADDR, usdcPurchased);

		IOonodzEntryPoint oonodzWrapper = IOonodzEntryPoint(OONODZ_WRAPPER_ADDR);

		if (newMinipool.nodeID == address(0)) {
			// start a new subscription
			(newMinipool.nodeID, newMinipool.blsPubkeyAndSig) = oonodzWrapper.oneTransactionSubscription(
				user,
				countryOfResidence,
				uint16(newMinipool.duration / 86400),
				bestRate,
				"USDC",
				withdrawalRightWaiver
			);
		} else {
			// resubscribe the existing one
			newMinipool.blsPubkeyAndSig = oonodzWrapper.oneTransactionRestart(
				user,
				countryOfResidence,
				uint16(newMinipool.duration / 86400),
				bestRate,
				"USDC",
				withdrawalRightWaiver,
				tokenID
			);
		}

		// transfer unused USDC back to the user
		if (usdc.balanceOf(address(this)) > 0) {
			uint256 amount = usdc.balanceOf(address(this));
			usdc.approve(address(this), amount);
			usdc.transferFrom(address(this), user, amount);
			emit USDCRefunded(user, amount);
		}

		emit HardwareRentedFromOonodz(newMinipool.nodeID, newMinipool.blsPubkeyAndSig);
		return (newMinipool.nodeID, newMinipool.blsPubkeyAndSig);
	}

	/// @notice Swaps AVAX for USDC
	/// @dev The tokens stay in this contract.
	/// @param avaxForToken The amount of avax the user has sent to be swapped for the desired token
	/// @param minTokenOut Minimum amount of the token amount that is expected from the swap - best calcualted off chain
	/// @return tokenPurchased The amount of the token obtained from the swap
	function swapAvaxForUSDC(uint256 avaxForToken, uint256 minTokenOut) internal returns (uint256 tokenPurchased) {
		IERC20 usdc = IERC20(USDC_ADDR);

		IERC20[] memory tokenPath = new IERC20[](2);
		uint256[] memory pairBinSteps = new uint256[](1);
		ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);

		tokenPath[0] = IERC20(WAVAX_ADDR);
		tokenPath[1] = IERC20(USDC_ADDR);

		// usdc
		pairBinSteps[0] = 20;
		versions[0] = ILBRouter.Version.V2_1;

		ILBRouter.Path memory path; // instanciate and populate the path to perform the swap.
		path.pairBinSteps = pairBinSteps;
		path.versions = versions;
		path.tokenPath = tokenPath;

		tokenPurchased = ILBRouter(JOE_LB_ROUTER).swapExactNATIVEForTokens{value: avaxForToken}(minTokenOut, path, address(this), block.timestamp + 1);

		// make sure the token is in this contract
		if (usdc.balanceOf(address(this)) < tokenPurchased || tokenPurchased < minTokenOut) {
			revert SwapFailed();
		}
		return tokenPurchased;
	}

	/// @notice Decodes the hardware provider information
	/// @param data The data to be decoded
	function decodeOonodzData(
		bytes memory data
	) public pure returns (uint16 countryOfResidence, bool withdrawalRightWaiver, bool bestRate, uint256 minUSDCAmountOut, uint256 tokenID) {
		require(data.length >= 68, "Data is too short"); // Updated length check: 2 bytes (uint16) + 1 bytes (bool) + 1 byte (bool) + 32 bytes (uint256) + 32 bytes (uint256)

		(countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID) = abi.decode(data, (uint16, bool, bool, uint256, uint256));
		return (countryOfResidence, withdrawalRightWaiver, bestRate, minUSDCAmountOut, tokenID);
	}
}
