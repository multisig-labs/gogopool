// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {Base} from "./Base.sol";
import {IERC20} from "../interface/IERC20.sol";
import {ILBRouter} from "../interface/ILBRouter.sol";
import {IWAVAX} from "../interface/IWAVAX.sol";
import {IWithdrawer} from "../interface/IWithdrawer.sol";
import {IGoGoPoolHardwareProvider} from "../interface/IGoGoPoolHardwareProvider.sol";
import {MinipoolManager} from "./MinipoolManager.sol";
import {ProtocolDAO} from "./ProtocolDAO.sol";
import {Staking} from "./Staking.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";

contract MinipoolStreamliner is Base, IWithdrawer {
	error MismatchedFunds();
	error SwapFailed();
	error OnlyOwner();
	error NotApprovedHardwareProvider();
	event NewStreamlinedMinipoolMade(address nodeID, address owner, address hardwareProviderContract);
	event MinipoolRelaunched(address nodeID, address owner, address hardwareProviderContract);

	address internal WAVAX_ADDR;
	address internal JOE_LB_ROUTER;

	constructor(Storage storageAddress, address WAVAX, address TJRouter) Base(storageAddress) {
		version = 1;
		WAVAX_ADDR = WAVAX;
		JOE_LB_ROUTER = TJRouter;
	}

	function receiveWithdrawalAVAX() external payable {}

	struct StreamlinedMinipool {
		address nodeID;
		bytes blsPubkeyAndSig;
		uint256 duration;
		uint256 avaxForMinipool;
		uint256 avaxForGGP;
		uint256 minGGPAmountOut;
		uint256 avaxForNodeRental;
		address hardwareProviderContract;
		bytes hardwareProviderInformation;
	}

	/// @notice new entry point for all minipools - new or being relaunched.
	/// The user can bring their own nodeID or rent a node from a hardware provider.
	/// @param newMinipool struct containing all information necessary to create or relaunch a minipool
	function createOrRelaunchStreamlinedMinipool(StreamlinedMinipool memory newMinipool) external payable {
		// verify there is enough avax being transferred
		if (msg.value != (newMinipool.avaxForMinipool + newMinipool.avaxForGGP + newMinipool.avaxForNodeRental)) {
			revert MismatchedFunds();
		}

		// swap and stake ggp for the user if needed
		if (newMinipool.avaxForGGP > 0) {
			this.swapAndStakeGGPOnBehalfOf{value: newMinipool.avaxForGGP}(msg.sender, newMinipool.avaxForGGP, newMinipool.minGGPAmountOut);
		}

		// rent hardware for the user if needed
		if (newMinipool.hardwareProviderContract != address(0) && isApprovedHardwareProvider(newMinipool.hardwareProviderContract)) {
			IGoGoPoolHardwareProvider hardwareProvider = IGoGoPoolHardwareProvider(newMinipool.hardwareProviderContract);
			(newMinipool.nodeID, newMinipool.blsPubkeyAndSig) = hardwareProvider.rentHardware{value: newMinipool.avaxForNodeRental}(
				msg.sender,
				newMinipool
			);
			// hardware provider is responsibe for sending back any unused tokens from the swap to the user
		}
		MinipoolManager minipoolMgr = MinipoolManager(getContractAddress("MinipoolManager"));

		if (newMinipool.avaxForMinipool > 0) {
			// create minipool for user
			minipoolMgr.createMinipoolOnBehalfOf{value: newMinipool.avaxForMinipool}(
				msg.sender,
				newMinipool.nodeID,
				newMinipool.duration,
				20_000,
				newMinipool.avaxForMinipool,
				newMinipool.blsPubkeyAndSig
			);
			emit NewStreamlinedMinipoolMade(newMinipool.nodeID, msg.sender, newMinipool.hardwareProviderContract);
		} else {
			// verify that the sender is the owner of the minipool
			int256 minipoolIndex = minipoolMgr.requireValidMinipool(newMinipool.nodeID);
			onlyOwner(minipoolIndex);

			minipoolMgr.withdrawRewardsAndRelaunchMinipool(newMinipool.nodeID, newMinipool.duration);
			emit MinipoolRelaunched(newMinipool.nodeID, msg.sender, newMinipool.hardwareProviderContract);
		}
	}

	/// @notice Look up minipool owner by minipool index
	/// @param minipoolIndex A valid minipool index
	/// @return minipool owner or revert
	function onlyOwner(int256 minipoolIndex) internal view returns (address) {
		address owner = getAddress(keccak256(abi.encodePacked("minipool.item", minipoolIndex, ".owner")));
		if (msg.sender != owner) {
			revert OnlyOwner();
		}
		return owner;
	}

	/// @notice Verifies if a contract is an approved partner
	/// @param contractAddress The address of the contract to verify
	/// @return bool True if the contract is an approved partner
	function isApprovedHardwareProvider(address contractAddress) public view returns (bool) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		if (!dao.hasRole("HWProvider", contractAddress)) {
			revert NotApprovedHardwareProvider();
		}
		return true;
	}

	/// @notice Swaps AVAX  for GGP
	/// @dev The tokens stay in this contract.
	/// @param avaxForToken The amount of avax the user has sent to be swapped for the desired token
	/// @param minTokenOut Minimum amount of the token amount that is expected from the swap - best calcualted off chain
	/// @return tokenPurchased The amount of the token obtained from the swap
	function swapAvaxForGGP(uint256 avaxForToken, uint256 minTokenOut) internal returns (uint256 tokenPurchased) {
		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));

		IERC20[] memory tokenPath = new IERC20[](2);
		uint256[] memory pairBinSteps = new uint256[](1);
		ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);

		tokenPath[0] = IERC20(WAVAX_ADDR);
		tokenPath[1] = IERC20(address(ggp));

		// ggp specific
		pairBinSteps[0] = 0; // Bin step of 0 points to the Joe V1 pair
		versions[0] = ILBRouter.Version.V1;

		ILBRouter.Path memory path; // instanciate and populate the path to perform the swap.
		path.pairBinSteps = pairBinSteps;
		path.versions = versions;
		path.tokenPath = tokenPath;

		tokenPurchased = ILBRouter(JOE_LB_ROUTER).swapExactNATIVEForTokens{value: avaxForToken}(minTokenOut, path, address(this), block.timestamp + 1);

		// make sure the token is in this contract
		if (ggp.balanceOf(address(this)) < tokenPurchased || tokenPurchased < minTokenOut) {
			revert SwapFailed();
		}
		return tokenPurchased;
	}

	/// @notice Swap AVAX for GGP and stake that GGP for the user
	/// @param user The user you are staking GGP on behalf of
	/// @param avaxForGGP The amount of AVAX that will be used for the swap
	/// @param minGGPAmountOut Minimum amount of GGP that is expected from the swap - best calcualted off chain
	/// @return ggpPurchased The amount of GGP onbtained from the swap and staked for the user
	function swapAndStakeGGPOnBehalfOf(address user, uint256 avaxForGGP, uint256 minGGPAmountOut) public payable returns (uint256 ggpPurchased) {
		// verify there is enough avax being transferred
		if (msg.value != avaxForGGP) {
			revert MismatchedFunds();
		}

		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		Staking staking = Staking(getContractAddress("Staking"));

		ggpPurchased = swapAvaxForGGP(avaxForGGP, minGGPAmountOut);

		// Stake GGP on behalf of user
		ggp.approve(address(staking), ggpPurchased);
		staking.stakeGGPOnBehalfOf(user, ggpPurchased);

		return ggpPurchased;
	}
}
