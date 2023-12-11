// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;
import {Base} from "./Base.sol";
import {IERC20} from "../interface/IERC20.sol";
import {ILBRouter} from "../interface/ILBRouter.sol";
import {IWAVAX} from "../interface/IWAVAX.sol";
import {IWithdrawer} from "../interface/IWithdrawer.sol";
import {IWrapper} from "../interface/IWrapper.sol";
import {MinipoolManager} from "./MinipoolManager.sol";
import {ProtocolDAO} from "./ProtocolDAO.sol";
import {Staking} from "./Staking.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";

contract MinipoolStreamliner is Base, IWithdrawer {
	error MismatchedFunds();
	error SwapFailed();
	error IncorrectNodeIDFormat();
	error IncorrectNodeIDLength();
	event NewStreamlinedMinipoolMade(address nodeID, address owner, bool isUsingOonodz);
	event USDCRefunded(address reciever, uint256 amount);

	address internal WAVAX_ADDR;
	address internal USDC_ADDR;
	address internal JOE_LB_ROUTER;
	address internal OONODZ_WRAPPER;

	constructor(Storage storageAddress, address WAVAX, address USDC, address TJRouter, address Oonodz) Base(storageAddress) {
		version = 1;
		WAVAX_ADDR = WAVAX;
		USDC_ADDR = USDC;
		JOE_LB_ROUTER = TJRouter;
		OONODZ_WRAPPER = Oonodz;
	}

	function receiveWithdrawalAVAX() external payable {}

	struct StreamlinedMinipool {
		address nodeID;
		uint256 duration;
		uint16 countryOfResidence;
		uint256 avaxForMinipool;
		uint256 avaxForGGP;
		uint256 minGGPAmountOut;
		uint256 avaxForNodeRental;
		uint256 minUSDCAmountOut;
		bool bestRate;
		bool withdrawalRightWaiver;
	}

	function createStreamlinedMinipool(StreamlinedMinipool memory newMinipool) external payable {
		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		Staking staking = Staking(getContractAddress("Staking"));

		if (msg.value != (newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental)) {
			revert MismatchedFunds();
		}

		if (newMinipool.avaxForGGP > 0) {
			uint256 ggpPurchased = swapAvaxForToken(newMinipool.avaxForGGP, newMinipool.minGGPAmountOut, IERC20(address(ggp)));
			// Stake GGP on behalf of user
			ggp.approve(address(staking), ggpPurchased);
			staking.stakeGGPOnBehalfOf(msg.sender, ggpPurchased);
		}

		if (newMinipool.nodeID == address(0) && newMinipool.avaxForNodeRental > 0) {
			IERC20 usdc = IERC20(USDC_ADDR);
			uint256 usdcPurchased = swapAvaxForToken(newMinipool.avaxForNodeRental, newMinipool.minUSDCAmountOut, usdc);

			usdc.approve(OONODZ_WRAPPER, usdcPurchased);
			IWrapper oonodzWrapper = IWrapper(OONODZ_WRAPPER);

			newMinipool.nodeID = oonodzWrapper.oneTransactionSubscription(
				msg.sender,
				newMinipool.countryOfResidence,
				uint16(newMinipool.duration / 86400),
				newMinipool.bestRate,
				"USDC",
				newMinipool.withdrawalRightWaiver
			);

			//transfer unused USDC back to the user
			if (usdc.balanceOf(address(this)) > 0) {
				uint256 amount = usdc.balanceOf(address(this));
				usdc.approve(address(this), amount);
				usdc.transferFrom(address(this), msg.sender, amount);
				emit USDCRefunded(msg.sender, amount);
			}
		}

		// create minipool for user
		MinipoolManager minipoolmgr = MinipoolManager(getContractAddress("MinipoolManager"));
		minipoolmgr.createMinipoolOnBehalfOf{value: newMinipool.avaxForMinipool}(
			msg.sender,
			newMinipool.nodeID,
			newMinipool.duration,
			20_000,
			newMinipool.avaxForMinipool
		);

		emit NewStreamlinedMinipoolMade(newMinipool.nodeID, msg.sender, (newMinipool.avaxForNodeRental > 0) ? true : false);
	}

	function swapAvaxForToken(uint256 avaxForToken, uint256 minTokenOut, IERC20 token) internal returns (uint256) {
		IERC20[] memory tokenPath = new IERC20[](2);
		uint256[] memory pairBinSteps = new uint256[](1);
		ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);

		tokenPath[0] = IERC20(WAVAX_ADDR);
		tokenPath[1] = IERC20(address(token));

		if (token == IERC20(USDC_ADDR)) {
			pairBinSteps[0] = 20;
			versions[0] = ILBRouter.Version.V2_1;
		} else {
			pairBinSteps[0] = 0; // Bin step of 0 points to the Joe V1 pair
			versions[0] = ILBRouter.Version.V1;
		}

		ILBRouter.Path memory path; // instanciate and populate the path to perform the swap.
		path.pairBinSteps = pairBinSteps;
		path.versions = versions;
		path.tokenPath = tokenPath;

		uint256 tokenPurchased = ILBRouter(JOE_LB_ROUTER).swapExactNATIVEForTokens{value: avaxForToken}(
			minTokenOut,
			path,
			address(this),
			block.timestamp + 1
		);

		// make sure the token is in this contract
		if (token.balanceOf(address(this)) < tokenPurchased || tokenPurchased < minTokenOut) {
			revert SwapFailed();
		}
		return tokenPurchased;
	}
}
