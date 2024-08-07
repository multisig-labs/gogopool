pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {MinipoolStatus} from "../contracts/types/MinipoolStatus.sol";
import {MinipoolManager} from "../contracts/contract/MinipoolManager.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {Staking} from "../contracts/contract/Staking.sol";
import {RewardsPool} from "../contracts/contract/RewardsPool.sol";
import {ClaimNodeOp} from "../contracts/contract/ClaimNodeOp.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";

contract RunRialto is Script, EnvironmentConfig {
	error UnableToClaim();

	function run() external {
		loadAddresses();
		loadUsers();

		address nodeID = 0x6760F9fceeb4DcA40532761D79A242fAA13bCab7;

		address deployer = getUser("deployer");
		address rialto = deployer;

		Storage store = Storage(getAddress("Storage"));
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));

		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);

		vm.startBroadcast(rialto);
		store.setAddress(keccak256(abi.encodePacked("minipool.item", mp.index, ".multisigAddr")), deployer);

		processMinipoolStart(nodeID);

		vm.stopBroadcast();
	}

	function processMinipoolStart(address nodeID) public returns (MinipoolManager.Minipool memory) {
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
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
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
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
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		uint256 totalAvax = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = 0;
		// Send the funds plus NO rewards back to MinipoolManager
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalAvax + rewards}(mp.nodeID, block.timestamp, rewards);
		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		return mp;
	}

	function processErroredMinipoolEndWithRewards(address nodeID) public returns (MinipoolManager.Minipool memory) {
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		uint256 totalAvax = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		// Rialto queries Avalanche node to verify that validation period was successful
		uint256 rewards = minipoolMgr.getExpectedAVAXRewardsAmt(mp.duration, totalAvax);
		// Send the funds plus rewards back to MinipoolManager
		minipoolMgr.recordStakingEnd{value: totalAvax + rewards}(mp.nodeID, block.timestamp, rewards);
		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		return mp;
	}

	function processErroredMinipoolEndWithoutRewards(address nodeID) public returns (MinipoolManager.Minipool memory) {
		MinipoolManager minipoolMgr = MinipoolManager(getAddress("MinipoolManager"));
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipoolByNodeID(nodeID);
		uint256 totalAvax = mp.avaxNodeOpAmt + mp.avaxLiquidStakerAmt;
		uint256 rewards = 0;
		// Send the funds plus NO rewards back to MinipoolManager
		minipoolMgr.recordStakingEnd{value: totalAvax + rewards}(mp.nodeID, block.timestamp, rewards);
		mp = minipoolMgr.getMinipoolByNodeID(mp.nodeID);
		return mp;
	}

	//  Every dao.getRewardsCycleSeconds(), this loop runs which distributes GGP rewards to eligible stakers
	function processGGPRewards() public {
		RewardsPool rewardsPool = RewardsPool(getAddress("RewardsPool"));
		Staking staking = Staking(getAddress("Staking"));
		ClaimNodeOp nopClaim = ClaimNodeOp(getAddress("ClaimNodeOp"));

		rewardsPool.startRewardsCycle();

		Staking.Staker[] memory allStakers = staking.getStakers(0, 0);
		uint256 totalEligibleStakedGGP = 0;

		for (uint256 i = 0; i < allStakers.length; i++) {
			if (nopClaim.isEligible(allStakers[i].stakerAddr)) {
				uint256 effectiveGGPStaked = staking.getEffectiveGGPStaked(allStakers[i].stakerAddr);
				totalEligibleStakedGGP = totalEligibleStakedGGP + effectiveGGPStaked;
			}
		}

		for (uint256 i = 0; i < allStakers.length; i++) {
			if (nopClaim.isEligible(allStakers[i].stakerAddr)) {
				nopClaim.calculateAndDistributeRewards(allStakers[i].stakerAddr, totalEligibleStakedGGP);
			}
		}
	}
}
