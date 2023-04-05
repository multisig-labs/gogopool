pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import {MinipoolManager} from "../MinipoolManager.sol";
import {ClaimNodeOp} from "../ClaimNodeOp.sol";
import {RewardsPool} from "../RewardsPool.sol";
import {Staking} from "../Staking.sol";
import {Oracle} from "../Oracle.sol";
import {TokenggAVAX} from "../tokens/TokenggAVAX.sol";

// import {console} from "forge-std/console.sol";

// This contract will simulate the contract calls that the Rialto multisig makes when
// performing the GoGoPool protocol. Rialto will also do things like move funds between
// C and P chains, and issue validation txs, but by using this contract we can operate the
// protocol entirely on HardHat and not have to care about the Avalanche-specific aspects.

// This contract address is registered as a valid multisig in the tests

contract RialtoSimulator {
	error UnableToClaim();

	MinipoolManager internal minipoolMgr;
	ClaimNodeOp internal nopClaim;
	RewardsPool internal rewardsPool;
	Staking internal staking;
	Oracle internal oracle;
	TokenggAVAX internal ggAVAX;

	constructor(MinipoolManager minipoolMgr_, ClaimNodeOp nopClaim_, RewardsPool rewardsPool_, Staking staking_, Oracle oracle_, TokenggAVAX ggAVAX_) {
		minipoolMgr = minipoolMgr_;
		nopClaim = nopClaim_;
		rewardsPool = rewardsPool_;
		staking = staking_;
		oracle = oracle_;
		ggAVAX = ggAVAX_;
	}

	receive() external payable {}

	function depositggAVAX(uint256 amount) public {
		ggAVAX.depositAVAX{value: amount}();
	}

	function setGGPPriceInAVAX(uint256 price, uint256 timestamp) external {
		oracle.setGGPPriceInAVAX(price, timestamp);
	}

	// Claim a minipool and simulate creating a validator node
	function processMinipoolStart(address nodeID) public returns (MinipoolManager.Minipool memory) {
		bool canClaim = minipoolMgr.canClaimAndInitiateStaking(nodeID);
		if (!canClaim) {
			revert UnableToClaim();
		}
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		minipoolMgr.claimAndInitiateStaking(nodeID);
		// Funds are now moved to this Rialto EOA
		// Rialto moves funds from C-chain to P-chain
		// Rialto issues AddValidatorTx on the P-chain and gets the txID
		// We simulate a random txID here
		bytes32 txID = keccak256(abi.encodePacked(nodeID, blockhash(block.timestamp)));

		minipoolMgr.recordStakingStart(nodeID, txID, block.timestamp);
		return mp;
	}

	// After a validation period has elapsed, finish the protocol by paying validation rewards
	function processMinipoolEndWithRewards(address nodeID) public returns (MinipoolManager.Minipool memory) {
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		uint256 totalAvax = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		// Rialto queries Avalanche node to verify that validation period was successful
		uint256 rewards = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, totalAvax);
		// Send the funds plus rewards back to MinipoolManager
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalAvax + rewards}(mp.nodeID, block.timestamp, rewards);
		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		return mp;
	}

	function processMinipoolEndWithoutRewards(address nodeID) public returns (MinipoolManager.Minipool memory) {
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		uint256 totalAvax = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = 0;
		// Send the funds plus NO rewards back to MinipoolManager
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalAvax + rewards}(mp.nodeID, block.timestamp, rewards);
		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		return mp;
	}

	//  Every dao.getRewardsCycleSeconds(), this loop runs which distributes GGP rewards to eligible stakers
	function processGGPRewards() public {
		rewardsPool.startRewardsCycle();

		Staking.Staker[] memory allStakers = staking.getStakers(0, 0);
		uint256 totalEligibleStakedGGP = 0;

		for (uint256 i = 0; i < allStakers.length; i++) {
			if (nopClaim.isEligible(allStakers[i].stakerAddr)) {
				uint256 effectiveGGPStaked = staking.getEffectiveGGPStaked(allStakers[i].stakerAddr);
				if (isInvestor(allStakers[i].stakerAddr)) {
					// their staked ggp will be cut in half for the effective ggp staked
					effectiveGGPStaked = staking.getEffectiveGGPStaked(allStakers[i].stakerAddr) / 2;
				}
				totalEligibleStakedGGP = totalEligibleStakedGGP + effectiveGGPStaked;
			}
		}

		for (uint256 i = 0; i < allStakers.length; i++) {
			if (nopClaim.isEligible(allStakers[i].stakerAddr)) {
				if (isInvestor(allStakers[i].stakerAddr)) {
					// the effective ggp staked will be doubled to make sure they only get half rewards
					nopClaim.calculateAndDistributeRewards(allStakers[i].stakerAddr, (totalEligibleStakedGGP * 2));
				} else {
					nopClaim.calculateAndDistributeRewards(allStakers[i].stakerAddr, totalEligibleStakedGGP);
				}
			}
		}
	}

	function isInvestor(address addr) public pure returns (bool) {
		return uint160(addr) > uint160(0x60000);
	}
}
