// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {MinipoolManager} from "./MinipoolManager.sol";
import {ProtocolDAO} from "./ProtocolDAO.sol";
import {RewardsPool} from "./RewardsPool.sol";
import {Staking} from "./Staking.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {Vault} from "./Vault.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

/// @title Node Operators claiming GGP Rewards
contract ClaimNodeOp is Base {
	using FixedPointMathLib for uint256;

	error InvalidAmount();
	error NoRewardsToClaim();
	error RewardsAlreadyDistributedToStaker(address);
	error RewardsCycleNotStarted();

	event GGPRewardsClaimed(address indexed to, uint256 amount);

	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	/// @notice Determines if a staker is eligible for the upcoming rewards cycle
	/// @param stakerAddr The C-chain address of a GGP staker in the protocol
	/// @return A boolean representing if the staker is eligible for rewards this cycle
	/// @dev Eligibility: time in protocol (secs) > RewardsEligibilityMinSeconds. Rialto will call this.
	function isEligible(address stakerAddr) external view returns (bool) {
		Staking staking = Staking(getContractAddress("Staking"));
		uint256 rewardsStartTime = staking.getRewardsStartTime(stakerAddr);
		uint256 elapsedSecs = (block.timestamp - rewardsStartTime);
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		return (rewardsStartTime != 0 && elapsedSecs >= dao.getRewardsEligibilityMinSeconds() && staking.getAVAXValidatingHighWater(stakerAddr) > 0);
	}

	/// @notice Set the share of rewards for a staker as a fraction of 1 ether
	/// @param stakerAddr The C-chain address of a GGP staker in the protocol
	/// @param totalEligibleGGPStaked The total amount of eligible GGP staked in the protocol used for this staker
	/// @dev Rialto will call this
	function calculateAndDistributeRewards(address stakerAddr, uint256 totalEligibleGGPStaked) external onlyMultisig {
		Staking staking = Staking(getContractAddress("Staking"));
		staking.requireValidStaker(stakerAddr);

		RewardsPool rewardsPool = RewardsPool(getContractAddress("RewardsPool"));
		if (rewardsPool.getRewardsCycleCount() == 0) {
			revert RewardsCycleNotStarted();
		}

		if (staking.getLastRewardsCycleCompleted(stakerAddr) == rewardsPool.getRewardsCycleCount()) {
			revert RewardsAlreadyDistributedToStaker(stakerAddr);
		}
		staking.setLastRewardsCycleCompleted(stakerAddr, rewardsPool.getRewardsCycleCount());
		uint256 ggpEffectiveStaked = staking.getEffectiveGGPStaked(stakerAddr);
		uint256 percentage = ggpEffectiveStaked.divWadDown(totalEligibleGGPStaked);
		uint256 rewardsCycleTotal = getRewardsCycleTotal();
		uint256 rewardsAmt = percentage.mulWadDown(rewardsCycleTotal);
		if (rewardsAmt > rewardsCycleTotal) {
			revert InvalidAmount();
		}

		uint256 currAVAXValidating = staking.getAVAXValidating(stakerAddr);
		staking.setAVAXValidatingHighWater(stakerAddr, currAVAXValidating);
		staking.increaseGGPRewards(stakerAddr, rewardsAmt);

		// check if their rewards time should be reset
		if (staking.getAVAXAssigned(stakerAddr) == 0) {
			staking.setRewardsStartTime(stakerAddr, 0);
		}
	}

	/// @notice Claim GGP and automatically restake the remaining unclaimed rewards
	/// @param claimAmt The amount of GGP the staker would like to withdraw from the protocol
	function claimAndRestake(uint256 claimAmt) external {
		Staking staking = Staking(getContractAddress("Staking"));
		uint256 ggpRewards = staking.getGGPRewards(msg.sender);
		if (ggpRewards == 0) {
			revert NoRewardsToClaim();
		}
		if (claimAmt > ggpRewards) {
			revert InvalidAmount();
		}

		staking.decreaseGGPRewards(msg.sender, ggpRewards);

		Vault vault = Vault(getContractAddress("Vault"));
		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		uint256 restakeAmt = ggpRewards - claimAmt;
		if (restakeAmt > 0) {
			vault.withdrawToken(address(this), ggp, restakeAmt);
			ggp.approve(address(staking), restakeAmt);
			staking.restakeGGP(msg.sender, restakeAmt);
		}

		if (claimAmt > 0) {
			vault.withdrawToken(msg.sender, ggp, claimAmt);
		}

		emit GGPRewardsClaimed(msg.sender, claimAmt);
	}

	/// @notice Get the total rewards for the most recent cycle
	/// @return This reward's cycle total in GGP
	function getRewardsCycleTotal() public view returns (uint256) {
		return getUint(keccak256("NOPClaim.RewardsCycleTotal"));
	}

	/// @notice Set the total amount of GGP that will be distributed this rewards cycle
	/// @param amount The total amount of GGP for this cycle's rewards
	/// @dev Sets the total rewards for the most recent cycle
	function setRewardsCycleTotal(uint256 amount) public onlySpecificRegisteredContract("RewardsPool", msg.sender) {
		setUint(keccak256("NOPClaim.RewardsCycleTotal"), amount);
	}
}
