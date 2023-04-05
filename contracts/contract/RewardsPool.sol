// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {ClaimNodeOp} from "./ClaimNodeOp.sol";
import {MultisigManager} from "./MultisigManager.sol";
import {ProtocolDAO} from "./ProtocolDAO.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {Vault} from "./Vault.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

/// @title Vault for GGP Rewards
contract RewardsPool is Base {
	using FixedPointMathLib for uint256;

	/// @notice Distribution cannot exceed total rewards
	error IncorrectRewardsDistribution();
	error UnableToStartRewardsCycle();
	error ContractHasNotBeenInitialized();
	error MaximumTokensReached();

	event GGPInflated(uint256 newTokens);
	event NewRewardsCycleStarted(uint256 totalRewardsAmt);
	event ClaimNodeOpRewardsTransferred(uint256 value);
	event ProtocolDAORewardsTransferred(uint256 value);
	event MultisigRewardsTransferred(uint256 value);

	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	function initialize() external onlyGuardian {
		if (getBool(keccak256("RewardsPool.initialized"))) {
			return;
		}
		setBool(keccak256("RewardsPool.initialized"), true);

		setUint(keccak256("RewardsPool.RewardsCycleStartTime"), block.timestamp);
		setUint(keccak256("RewardsPool.InflationIntervalStartTime"), block.timestamp);
	}

	/* INFLATION */

	/// @notice Get the last time that inflation was calculated at
	/// @return timestamp when inflation was last calculated
	function getInflationIntervalStartTime() public view returns (uint256) {
		return getUint(keccak256("RewardsPool.InflationIntervalStartTime"));
	}

	/// @notice Inflation intervals that have elapsed since inflation was last calculated
	/// @return Number of intervals since last inflation cycle (0, 1, 2, etc)
	function getInflationIntervalsElapsed() public view returns (uint256) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 startTime = getInflationIntervalStartTime();
		if (startTime == 0) {
			revert ContractHasNotBeenInitialized();
		}
		return (block.timestamp - startTime) / dao.getInflationIntervalSeconds();
	}

	/// @notice Function to compute how many tokens should be minted
	/// @return currentTotalSupply current total supply
	/// @return newTotalSupply supply after mint
	function getInflationAmt() public view returns (uint256 currentTotalSupply, uint256 newTotalSupply) {
		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 inflationRate = dao.getInflationIntervalRate();
		uint256 inflationIntervalsElapsed = getInflationIntervalsElapsed();
		currentTotalSupply = ggp.totalSupply();
		newTotalSupply = currentTotalSupply;

		// Compute inflation for total inflation intervals elapsed
		for (uint256 i = 0; i < inflationIntervalsElapsed; i++) {
			newTotalSupply = newTotalSupply.mulWadDown(inflationRate);
		}
		return (currentTotalSupply, newTotalSupply);
	}

	/// @notice Releases more GGP if appropriate
	/// @dev Mint new tokens if enough time has elapsed since last mint. Also, minting 0 tokens will revert.
	function inflate() internal {
		uint256 inflationIntervalElapsedSeconds = (block.timestamp - getInflationIntervalStartTime());
		(uint256 currentTotalSupply, uint256 newTotalSupply) = getInflationAmt();

		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));

		uint256 newTokens = newTotalSupply - currentTotalSupply;

		if (newTotalSupply > ggp.MAX_SUPPLY()) {
			newTokens = ggp.MAX_SUPPLY() - currentTotalSupply;
		}

		emit GGPInflated(newTokens);

		ggp.mint(newTokens);

		addUint(keccak256("RewardsPool.InflationIntervalStartTime"), inflationIntervalElapsedSeconds);
		setUint(keccak256("RewardsPool.RewardsCycleTotalAmt"), newTokens);
	}

	/* REWARDS */

	/// @notice Public function that will run a GGP rewards cycle if possible
	function startRewardsCycle() external whenNotPaused {
		if (!canStartRewardsCycle()) {
			revert UnableToStartRewardsCycle();
		}

		emit NewRewardsCycleStarted(getRewardsCycleTotalAmt());

		// Set start of new rewards cycle
		setUint(keccak256("RewardsPool.RewardsCycleStartTime"), block.timestamp);
		increaseRewardsCycleCount();
		// Mint any new tokens from GGP inflation
		// This will always 'mint' (release) new tokens if the rewards cycle length requirement is met
		// 		since inflation is on a 1 day interval and it needs at least one cycle since last calculation
		inflate();

		uint256 multisigClaimContractAllotment = getClaimingContractDistribution("MultisigManager");
		uint256 nopClaimContractAllotment = getClaimingContractDistribution("ClaimNodeOp");
		uint256 daoClaimContractAllotment = getClaimingContractDistribution("ClaimProtocolDAO");
		if (daoClaimContractAllotment + nopClaimContractAllotment + multisigClaimContractAllotment > getRewardsCycleTotalAmt()) {
			revert IncorrectRewardsDistribution();
		}

		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		Vault vault = Vault(getContractAddress("Vault"));

		if (daoClaimContractAllotment > 0) {
			emit ProtocolDAORewardsTransferred(daoClaimContractAllotment);
			vault.transferToken("ClaimProtocolDAO", ggp, daoClaimContractAllotment);
		}

		if (multisigClaimContractAllotment > 0) {
			emit MultisigRewardsTransferred(multisigClaimContractAllotment);
			distributeMultisigAllotment(multisigClaimContractAllotment, vault, ggp);
		}

		if (nopClaimContractAllotment > 0) {
			emit ClaimNodeOpRewardsTransferred(nopClaimContractAllotment);
			ClaimNodeOp nopClaim = ClaimNodeOp(getContractAddress("ClaimNodeOp"));
			nopClaim.setRewardsCycleTotal(nopClaimContractAllotment);
			vault.transferToken("ClaimNodeOp", ggp, nopClaimContractAllotment);
		}
	}

	/// @notice The current cycle number for GGP rewards
	/// @return The number representing which rewards cycle the protocol is on
	function getRewardsCycleCount() public view returns (uint256) {
		return getUint(keccak256("RewardsPool.RewardsCycleCount"));
	}

	/// @notice The current rewards cycle start time
	/// @return timestamp of the rewards cycle start time
	function getRewardsCycleStartTime() public view returns (uint256) {
		return getUint(keccak256("RewardsPool.RewardsCycleStartTime"));
	}

	/// @notice The current rewards cycle total amount of GGP
	/// @return The total GGP available for distribution this rewards cycle
	function getRewardsCycleTotalAmt() public view returns (uint256) {
		return getUint(keccak256("RewardsPool.RewardsCycleTotalAmt"));
	}

	/// @notice The number of reward cycles that have elapsed
	/// @return Number representing the amount of rewards cycles that have passed
	function getRewardsCyclesElapsed() public view returns (uint256) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 startTime = getRewardsCycleStartTime();
		return (block.timestamp - startTime) / dao.getRewardsCycleSeconds();
	}

	/// @notice Get the approx amount of GGP rewards owed for this cycle per claiming contract
	/// @param claimingContract Name of the contract being claimed for
	/// @return GGP Rewards amount for current cycle per claiming contract
	function getClaimingContractDistribution(string memory claimingContract) public view returns (uint256) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 claimContractPct = dao.getClaimingContractPct(claimingContract);
		// How much rewards are available for this claim interval?
		uint256 currentCycleRewardsTotal = getRewardsCycleTotalAmt();

		// How much this claiming contract is entitled to in perc
		uint256 contractRewardsTotal = 0;
		if (claimContractPct > 0 && currentCycleRewardsTotal > 0) {
			// Calculate how much rewards this claimer will receive based on their claiming perc
			contractRewardsTotal = claimContractPct.mulWadDown(currentCycleRewardsTotal);
		}
		return contractRewardsTotal;
	}

	/// @notice Checking if enough time has passed since the last rewards cycle
	/// @return Boolean representing if the the next rewards cycle can start
	/// @dev Rialto calls this to see if at least one cycle has passed
	function canStartRewardsCycle() public view returns (bool) {
		if (getBool(keccak256(abi.encodePacked("contract.paused", "RewardsPool")))) {
			return false;
		}

		return getRewardsCyclesElapsed() > 0 && getInflationIntervalsElapsed() > 0;
	}

	/// @notice Increase the cycle number for GGP rewards
	function increaseRewardsCycleCount() internal {
		addUint(keccak256("RewardsPool.RewardsCycleCount"), 1);
	}

	/// @notice Distributes GGP to enabled Multisigs
	/// @param allotment Total GGP for Multisigs
	/// @param vault Vault contract
	/// @param ggp TokenGGP contract
	function distributeMultisigAllotment(uint256 allotment, Vault vault, TokenGGP ggp) internal {
		MultisigManager mm = MultisigManager(getContractAddress("MultisigManager"));

		uint256 enabledCount;
		uint256 count = mm.getCount();
		address[] memory enabledMultisigs = new address[](count);

		// there should never be more than a few multisigs, so a loop should be fine here
		for (uint256 i = 0; i < count; i++) {
			(address addr, bool enabled) = mm.getMultisig(i);
			if (enabled) {
				enabledMultisigs[enabledCount] = addr;
				enabledCount++;
			}
		}
		// If there are no enabled multisigs then the tokens will just sit under the multisig manager contract
		if (enabledCount == 0) {
			vault.transferToken("MultisigManager", ggp, allotment);
			return;
		}

		// Dirty hack to cut unused elements off end of return value (from RP)
		// solhint-disable-next-line no-inline-assembly
		assembly {
			mstore(enabledMultisigs, enabledCount)
		}

		uint256 tokensPerMultisig = allotment / enabledCount;
		for (uint256 i = 0; i < enabledMultisigs.length; i++) {
			vault.withdrawToken(enabledMultisigs[i], ggp, tokensPerMultisig);
		}
	}
}
