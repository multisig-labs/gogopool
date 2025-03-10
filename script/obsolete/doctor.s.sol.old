// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {Storage} from "../contracts/contract/Storage.sol";
import {MultisigManager} from "../contracts/contract/MultisigManager.sol";

// After a mainnet deploy, check the protocol settings
contract Doctor is Script, EnvironmentConfig {
	function run() external onlyDev {
		loadAddresses();

		Storage s = Storage(getAddress("Storage"));
		verifyContracts();

		require(checkContractRegistration(s) == true);

		require(s.getAddress(keccak256("Oracle.OneInch")) == getAddress("OneInchMock"), "Oracle not set");
		// require(s.getUint(keccak256("MinipoolManager.TotalAVAXLiquidStakerAmt"));
		// getUint(keccak256("NOPClaim.RewardsCycleTotal"));
		require(s.getBool(keccak256("ProtocolDAO.initialized")) == true, "ProtocolDAO.initialized");
		require(s.getUint(keccak256("ProtocolDAO.ExpectedAVAXRewardsRate")) == 0.1 ether, "ProtocolDAO.ExpectedAVAXRewardsRate");
		require(s.getUint(keccak256("ProtocolDAO.InflationIntervalRate")) == 1000133680617113500, "ProtocolDAO.InflationIntervalRate");
		require(s.getUint(keccak256("ProtocolDAO.InflationIntervalSeconds")) == 1 days, "ProtocolDAO.InflationIntervalSeconds");
		require(s.getUint(keccak256("ProtocolDAO.MaxCollateralizationRatio")) == 1.5 ether, "ProtocolDAO.MaxCollateralizationRatio");
		require(s.getUint(keccak256("ProtocolDAO.MinCollateralizationRatio")) == 0.1 ether, "ProtocolDAO.MinCollateralizationRatio");
		// require(s.getUint(keccak256("ProtocolDAO.MinipoolCancelMoratoriumSeconds")) == 5 days, "ProtocolDAO.MinipoolCancelMoratoriumSeconds");
		// require(s.getUint(keccak256("ProtocolDAO.MinipoolMaxAVAXAssignment")) == 1_000 ether, "ProtocolDAO.MinipoolMaxAVAXAssignment");
		// require(s.getUint(keccak256("ProtocolDAO.MinipoolMinAVAXAssignment")) == 1_000 ether, "ProtocolDAO.MinipoolMinAVAXAssignment");
		// require(s.getUint(keccak256("ProtocolDAO.MinipoolMinAVAXStakingAmt")) == 2_000 ether, "ProtocolDAO.MinipoolMinAVAXStakingAmt");
		require(s.getUint(keccak256("ProtocolDAO.MinipoolNodeCommissionFeePct")) == 0.15 ether, "ProtocolDAO.MinipoolNodeCommissionFeePct");
		require(s.getUint(keccak256("ProtocolDAO.RewardsCycleSeconds")) == 28 days, "ProtocolDAO.RewardsCycleSeconds");
		require(s.getUint(keccak256("ProtocolDAO.RewardsEligibilityMinSeconds")) == 14 days, "ProtocolDAO.RewardsEligibilityMinSeconds");
		require(s.getUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate")) == 0.1 ether, "ProtocolDAO.TargetGGAVAXReserveRate");
		require(s.getUint(keccak256("ProtocolDAO.ClaimingContractPct.MultisigManager")) == 0.20 ether, "ProtocolDAO.ClaimingContractPct.MultisigManager");
		require(s.getUint(keccak256("ProtocolDAO.ClaimingContractPct.ClaimNodeOp")) == 0.70 ether, "ProtocolDAO.ClaimingContractPct.ClaimNodeOp");
		require(
			s.getUint(keccak256("ProtocolDAO.ClaimingContractPct.ClaimProtocolDAO")) == 0.10 ether,
			"ProtocolDAO.ClaimingContractPct.ClaimProtocolDAO"
		);

		require(s.getBool(keccak256("RewardsPool.initialized")) == true, "RewardsPool.initialized");
		// require(s.getUint(keccak256("RewardsPool.InflationIntervalStartTime"));
		// require(s.getUint(keccak256("RewardsPool.RewardsCycleCount"));
		// require(s.getUint(keccak256("RewardsPool.RewardsCycleStartTime"));
		// require(s.getUint(keccak256("RewardsPool.RewardsCycleTotalAmt"));

		MultisigManager multisigManager = MultisigManager(getAddress("MultisigManager"));
		try multisigManager.requireNextActiveMultisig() returns (address) {} catch (bytes memory) {
			require(false, "No enabled Multisigs");
		}

		require(s.getBool(keccak256(abi.encodePacked("contract.paused", "TokenggAVAX"))) == false, "Contract paused");
		require(s.getBool(keccak256(abi.encodePacked("contract.paused", "MinipoolManager"))) == false, "Contract paused");
		require(s.getBool(keccak256(abi.encodePacked("contract.paused", "Staking"))) == false, "Contract paused");
	}
}
