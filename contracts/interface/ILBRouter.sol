// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {IERC20} from "./IERC20.sol";

/**
 * @title Liquidity Book Router Interface
 * @author Trader Joe
 * @notice Required interface of LBRouter contract
 */
interface ILBRouter {
	error LBRouter__SenderIsNotWNATIVE();
	error LBRouter__PairNotCreated(address tokenX, address tokenY, uint256 binStep);
	error LBRouter__WrongAmounts(uint256 amount, uint256 reserve);
	error LBRouter__SwapOverflows(uint256 id);
	error LBRouter__BrokenSwapSafetyCheck();
	error LBRouter__NotFactoryOwner();
	error LBRouter__TooMuchTokensIn(uint256 excess);
	error LBRouter__BinReserveOverflows(uint256 id);
	error LBRouter__IdOverflows(int256 id);
	error LBRouter__LengthsMismatch();
	error LBRouter__WrongTokenOrder();
	error LBRouter__IdSlippageCaught(uint256 activeIdDesired, uint256 idSlippage, uint256 activeId);
	error LBRouter__AmountSlippageCaught(uint256 amountXMin, uint256 amountX, uint256 amountYMin, uint256 amountY);
	error LBRouter__IdDesiredOverflows(uint256 idDesired, uint256 idSlippage);
	error LBRouter__FailedToSendNATIVE(address recipient, uint256 amount);
	error LBRouter__DeadlineExceeded(uint256 deadline, uint256 currentTimestamp);
	error LBRouter__AmountSlippageBPTooBig(uint256 amountSlippage);
	error LBRouter__InsufficientAmountOut(uint256 amountOutMin, uint256 amountOut);
	error LBRouter__MaxAmountInExceeded(uint256 amountInMax, uint256 amountIn);
	error LBRouter__InvalidTokenPath(address wrongToken);
	error LBRouter__InvalidVersion(uint256 version);
	error LBRouter__WrongNativeLiquidityParameters(address tokenX, address tokenY, uint256 amountX, uint256 amountY, uint256 msgValue);

	/**
	 * @dev This enum represents the version of the pair requested
	 * - V1: Joe V1 pair
	 * - V2: LB pair V2. Also called legacyPair
	 * - V2_1: LB pair V2.1 (current version)
	 */
	enum Version {
		V1,
		V2,
		V2_1
	}

	/**
	 * @dev The path parameters, such as:
	 * - pairBinSteps: The list of bin steps of the pairs to go through
	 * - versions: The list of versions of the pairs to go through
	 * - tokenPath: The list of tokens in the path to go through
	 */
	struct Path {
		uint256[] pairBinSteps;
		Version[] versions;
		IERC20[] tokenPath;
	}

	function swapExactTokensForTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		Path memory path,
		address to,
		uint256 deadline
	) external returns (uint256 amountOut);

	function swapExactTokensForNATIVE(
		uint256 amountIn,
		uint256 amountOutMinNATIVE,
		Path memory path,
		address payable to,
		uint256 deadline
	) external returns (uint256 amountOut);

	function swapExactNATIVEForTokens(
		uint256 amountOutMin,
		Path memory path,
		address to,
		uint256 deadline
	) external payable returns (uint256 amountOut);

	function swapTokensForExactTokens(
		uint256 amountOut,
		uint256 amountInMax,
		Path memory path,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amountsIn);

	function swapTokensForExactNATIVE(
		uint256 amountOut,
		uint256 amountInMax,
		Path memory path,
		address payable to,
		uint256 deadline
	) external returns (uint256[] memory amountsIn);

	function swapNATIVEForExactTokens(
		uint256 amountOut,
		Path memory path,
		address to,
		uint256 deadline
	) external payable returns (uint256[] memory amountsIn);

	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		Path memory path,
		address to,
		uint256 deadline
	) external returns (uint256 amountOut);

	function swapExactTokensForNATIVESupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMinNATIVE,
		Path memory path,
		address payable to,
		uint256 deadline
	) external returns (uint256 amountOut);

	function swapExactNATIVEForTokensSupportingFeeOnTransferTokens(
		uint256 amountOutMin,
		Path memory path,
		address to,
		uint256 deadline
	) external payable returns (uint256 amountOut);
}
