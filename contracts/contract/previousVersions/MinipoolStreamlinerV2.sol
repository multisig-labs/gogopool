// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {BaseUpgradeable} from "../BaseUpgradeable.sol";
import {IERC20} from "../../interface/IERC20.sol";
import {ILBRouter} from "../../interface/ILBRouter.sol";
import {IWAVAX} from "../../interface/IWAVAX.sol";
import {IWithdrawer} from "../../interface/IWithdrawer.sol";
import {IHardwareProvider} from "./IHardwareProvider.sol";
import {MinipoolManager} from "../MinipoolManager.sol";
import {Staking} from "../Staking.sol";
import {Storage} from "../Storage.sol";
import {TokenGGP} from "../tokens/TokenGGP.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract MinipoolStreamlinerV2 is IWithdrawer, Initializable, BaseUpgradeable {
	using SafeTransferLib for TokenGGP;

	error MismatchedFunds();
	error SwapFailed();
	error OnlyOwner();
	error InvalidHardwareProvider(bytes32 providerName);
	error TooManyMinipools(uint256 actualCount);

	event NewStreamlinedMinipoolMade(address nodeID, address owner, bytes32 hardwareProvider, uint256 avaxForNodeRental, uint256 duration);
	event MinipoolRelaunched(address nodeID, address owner, bytes32 hardwareProvider, uint256 avaxForNodeRental, uint256 duration);

	address internal WAVAX_ADDR;
	address internal JOE_LB_ROUTER;

	mapping(bytes32 => address) public approvedHardwareProviders;

	uint256 public batchLimit;

	/// @notice Prevents initialization if contract is constructed
	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Called on creation to initialize MinipoolStreamliner
	function initialize() public reinitializer(2) {
		version = 2;
		batchLimit = 10;
	}

	/// @notice Payable function to receive funds from the vault
	function receiveWithdrawalAVAX() external payable {}

	// This is actually what a minipool needs to know to relaunch or create
	struct StreamlinedMinipool {
		address nodeID;
		bytes blsPubkeyAndSig;
		uint256 duration;
		uint256 avaxForMinipool;
		uint256 avaxForNodeRental;
		bytes32 hardwareProvider;
	}

	/// @notice New entry point for all minipools - new or being relaunched.
	///         The user can bring their own nodeID or rent a node from a hardware provider.
	/// @param avaxForGGP AVAX to swap for GGP then stake on behalf of msg.sender
	/// @param minGGPAmountOut Minimum expected amount of GGP after swap
	/// @param ggpStakeAmount Amount of GGP to stake on the behalf of msg.sender
	/// @param newMinipools Array of minipool objects to create or relaunch
	function createOrRelaunchStreamlinedMinipool(
		uint256 avaxForGGP,
		uint256 minGGPAmountOut,
		uint256 ggpStakeAmount,
		StreamlinedMinipool[] memory newMinipools
	) public payable {
		// Verify no more than 10 minipools are being modified
		if (newMinipools.length > batchLimit) {
			revert TooManyMinipools(newMinipools.length);
		}

		// Verify payment amount and revert if hardware provider is invalid
		uint256 minipoolFundsRequired = 0;
		for (uint256 i = 0; i < newMinipools.length; i++) {
			minipoolFundsRequired += newMinipools[i].avaxForMinipool + newMinipools[i].avaxForNodeRental;

			address hardwareProviderContract = approvedHardwareProviders[newMinipools[i].hardwareProvider];
			if (hardwareProviderContract == address(0x0) && newMinipools[i].avaxForNodeRental > 0) {
				revert InvalidHardwareProvider(newMinipools[i].hardwareProvider);
			}
		}
		if (msg.value != (minipoolFundsRequired + avaxForGGP)) {
			revert MismatchedFunds();
		}

		// Swap AVAX -> GGP and stake
		if (avaxForGGP > 0) {
			this.swapAndStakeGGPOnBehalfOf{value: avaxForGGP}(msg.sender, avaxForGGP, minGGPAmountOut);
		}

		// Stake GGP on behalf of user
		if (ggpStakeAmount > 0) {
			TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
			Staking staking = Staking(getContractAddress("Staking"));
			ggp.safeTransferFrom(msg.sender, address(this), ggpStakeAmount);
			ggp.approve(address(staking), ggpStakeAmount);
			staking.stakeGGPOnBehalfOf(msg.sender, ggpStakeAmount);
		}

		MinipoolManager minipoolMgr = MinipoolManager(getContractAddress("MinipoolManager"));

		// Create or relaunch minipools
		for (uint i = 0; i < newMinipools.length; i++) {
			StreamlinedMinipool memory newMinipool = newMinipools[i];

			address hardwareProviderContract = approvedHardwareProviders[newMinipool.hardwareProvider];
			if (hardwareProviderContract != address(0x0)) {
				IHardwareProvider(hardwareProviderContract).rentHardware{value: newMinipool.avaxForNodeRental}(
					msg.sender,
					newMinipool.nodeID,
					newMinipool.duration
				);
			}

			if (newMinipool.avaxForMinipool > 0) {
				minipoolMgr.createMinipoolOnBehalfOf{value: newMinipool.avaxForMinipool}(
					msg.sender,
					newMinipool.nodeID,
					newMinipool.duration,
					20_000,
					newMinipool.avaxForMinipool,
					newMinipool.blsPubkeyAndSig,
					newMinipool.hardwareProvider
				);
				emit NewStreamlinedMinipoolMade(
					newMinipool.nodeID,
					msg.sender,
					newMinipool.hardwareProvider,
					newMinipool.avaxForNodeRental,
					newMinipool.duration
				);
			} else {
				// Verify sender and recreate minipool
				int256 minipoolIndex = minipoolMgr.requireValidMinipool(newMinipool.nodeID);
				onlyOwner(minipoolIndex);

				minipoolMgr.withdrawRewardsAndRelaunchMinipool(newMinipool.nodeID, newMinipool.duration, newMinipool.hardwareProvider);
				emit MinipoolRelaunched(newMinipool.nodeID, msg.sender, newMinipool.hardwareProvider, newMinipool.avaxForNodeRental, newMinipool.duration);
			}
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

	/// @notice Swaps AVAX for GGP
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

		ILBRouter.Path memory path; // instantiate and populate the path to perform the swap.
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

	/// @notice Add an approved hardware provider with contract address
	/// @param providerName Bytes32 name of the hardware provider
	/// @param providerContract Hardware Provider contract address
	function addHardwareProvider(bytes32 providerName, address providerContract) external onlyGuardian {
		approvedHardwareProviders[providerName] = providerContract;
	}

	/// @notice Remove an approved hardware provider
	/// @param providerName Name of the hardware provider
	function removeHardwareProvider(bytes32 providerName) external onlyGuardian {
		approvedHardwareProviders[providerName] = address(0x0);
	}

	/// @notice Update batch minipool limit
	/// @param newBatchLimit new limit
	function setBatchLimit(uint256 newBatchLimit) external onlyGuardian {
		batchLimit = newBatchLimit;
	}
}
