// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {Storage} from "./Storage.sol";

/// @title Settings for the Protocol
contract ProtocolDAO is Base {
	error ContractAlreadyRegistered();
	error ExistingContractNotRegistered();
	error InvalidContract();
	error ValueNotWithinRange();

	modifier valueNotGreaterThanOne(uint256 setterValue) {
		if (setterValue > 1 ether) {
			revert ValueNotWithinRange();
		}
		_;
	}

	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	function initialize() external onlyGuardian {
		if (getBool(keccak256("ProtocolDAO.initialized"))) {
			return;
		}
		setBool(keccak256("ProtocolDAO.initialized"), true);

		// ClaimNodeOp
		setUint(keccak256("ProtocolDAO.RewardsEligibilityMinSeconds"), 14 days);

		// RewardsPool
		setUint(keccak256("ProtocolDAO.RewardsCycleSeconds"), 28 days); // The time in which a claim period will span in seconds - 28 days by default
		setUint(keccak256("ProtocolDAO.ClaimingContractPct.MultisigManager"), 0.10 ether);
		setUint(keccak256("ProtocolDAO.ClaimingContractPct.ClaimNodeOp"), 0.70 ether);
		setUint(keccak256("ProtocolDAO.ClaimingContractPct.ClaimProtocolDAO"), 0.20 ether);

		// GGP Inflation
		setUint(keccak256("ProtocolDAO.InflationIntervalSeconds"), 1 days);
		setUint(keccak256("ProtocolDAO.InflationIntervalRate"), 1000133680617113500); // 5% annual calculated on a daily interval - Calculate in js example: let dailyInflation = web3.utils.toBN((1 + 0.05) ** (1 / (365)) * 1e18);

		// TokenGGAVAX
		setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.1 ether); // 10% collateral held in reserve

		// Minipool
		setUint(keccak256("ProtocolDAO.MinipoolMinAVAXStakingAmt"), 2_000 ether);
		setUint(keccak256("ProtocolDAO.MinipoolNodeCommissionFeePct"), 0.15 ether);
		setUint(keccak256("ProtocolDAO.MinipoolMinDuration"), 14 days);
		setUint(keccak256("ProtocolDAO.MinipoolMaxDuration"), 365 days);
		setUint(keccak256("ProtocolDAO.MinipoolCycleDuration"), 14 days);
		setUint(keccak256("ProtocolDAO.MinipoolCycleDelayTolerance"), 1 days);
		setUint(keccak256("ProtocolDAO.MinipoolMaxAVAXAssignment"), 1_000 ether);
		setUint(keccak256("ProtocolDAO.MinipoolMinAVAXAssignment"), 1_000 ether);
		setUint(keccak256("ProtocolDAO.ExpectedAVAXRewardsRate"), 0.1 ether); // Annual rate as pct of 1 avax
		setUint(keccak256("ProtocolDAO.MinipoolCancelMoratoriumSeconds"), 5 days);

		// Staking
		setUint(keccak256("ProtocolDAO.MaxCollateralizationRatio"), 1.5 ether);
		setUint(keccak256("ProtocolDAO.MinCollateralizationRatio"), 0.1 ether);
	}

	/// @notice Get if a contract is paused
	/// @param contractName The contract that is being checked
	/// @return boolean representing if the contract passed in is paused
	function getContractPaused(string memory contractName) public view returns (bool) {
		return getBool(keccak256(abi.encodePacked("contract.paused", contractName)));
	}

	/// @notice Pause a contract
	/// @param contractName The contract whose actions should be paused
	function pauseContract(string memory contractName) public onlySpecificRegisteredContract("Ocyticus", msg.sender) {
		setBool(keccak256(abi.encodePacked("contract.paused", contractName)), true);
	}

	/// @notice Unpause a contract
	/// @param contractName The contract whose actions should be resumed
	function resumeContract(string memory contractName) public onlySpecificRegisteredContract("Ocyticus", msg.sender) {
		setBool(keccak256(abi.encodePacked("contract.paused", contractName)), false);
	}

	// *** Rewards Pool ***

	/// @notice Get how many seconds a node must be registered for rewards to be eligible for the rewards cycle
	/// @return uint256 The min number of seconds to be considered eligible
	function getRewardsEligibilityMinSeconds() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.RewardsEligibilityMinSeconds"));
	}

	/// @notice Get how many seconds in a rewards cycle
	/// @return The setting for the rewards cycle length in seconds
	function getRewardsCycleSeconds() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.RewardsCycleSeconds"));
	}

	/// @notice The percentage a contract is owed for a rewards cycle
	/// @param claimingContract The name of the the claiming contract
	/// @return uint256 Rewards percentage the passed in contract will receive this cycle
	function getClaimingContractPct(string memory claimingContract) public view returns (uint256) {
		return getUint(keccak256(abi.encodePacked("ProtocolDAO.ClaimingContractPct.", claimingContract)));
	}

	/// @notice Set the percentage a contract is owed for a rewards cycle
	/// @param claimingContract The name of the claiming contract
	/// @param decimal A decimal representing a percentage of the rewards that the claiming contract is due
	function setClaimingContractPct(string memory claimingContract, uint256 decimal) public onlyGuardian valueNotGreaterThanOne(decimal) {
		setUint(keccak256(abi.encodePacked("ProtocolDAO.ClaimingContractPct.", claimingContract)), decimal);
	}

	// *** GGP Inflation ***

	/// @notice The current inflation rate per interval (eg 1000133680617113500 = 5% annual)
	/// @return uint256 The current inflation rate per interval (can never be < 1 ether)
	function getInflationIntervalRate() external view returns (uint256) {
		// Inflation rate controlled by the DAO
		uint256 rate = getUint(keccak256("ProtocolDAO.InflationIntervalRate"));
		return rate < 1 ether ? 1 ether : rate;
	}

	/// @notice How many seconds to calculate inflation at
	/// @return uint256 how many seconds to calculate inflation at
	function getInflationIntervalSeconds() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.InflationIntervalSeconds"));
	}

	// *** Minipool Settings ***

	/// @notice The min AVAX staking amount that is required for creating a minipool
	/// @return The protocol's setting for a minipool's min AVAX staking requirement
	function getMinipoolMinAVAXStakingAmt() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolMinAVAXStakingAmt"));
	}

	/// @notice The node commission fee for running the hardware for the minipool
	/// @return The protocol setting for a percentage that a minipool's node gets as a commission fee
	function getMinipoolNodeCommissionFeePct() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolNodeCommissionFeePct"));
	}

	/// @notice Maximum AVAX a Node Operator can be assigned from liquid staking funds
	/// @return The protocol setting for a minipool's max AVAX assignment from liquids staking funds
	function getMinipoolMaxAVAXAssignment() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolMaxAVAXAssignment"));
	}

	/// @notice Minimum AVAX a Node Operator can be assigned from liquid staking funds
	/// @return The protocol setting for a minipool's min AVAX assignment from liquids staking funds
	function getMinipoolMinAVAXAssignment() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolMinAVAXAssignment"));
	}

	/// @notice The user must wait this amount of time before they can cancel their minipool
	/// @return The protocol setting for the amount of time a user must wait before they can cancel a minipool in seconds
	function getMinipoolCancelMoratoriumSeconds() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolCancelMoratoriumSeconds"));
	}

	/// @notice Min duration a minipool can be live for
	/// @return The protocol setting for the min duration a minipool can stake in days
	function getMinipoolMinDuration() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolMinDuration"));
	}

	/// @notice Max duration a minipool can be live for
	/// @return The protocol setting for the max duration a minipool can stake in days
	function getMinipoolMaxDuration() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolMaxDuration"));
	}

	/// @notice The duration of a cycle for a minipool
	/// @return The protocol setting for length of time a minipool cycle is in days
	function getMinipoolCycleDuration() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolCycleDuration"));
	}

	/// @notice The duration of a minipool's cycle delay tolerance
	/// @return The protocol setting for length of time a minipool cycle can be delayed in days
	function getMinipoolCycleDelayTolerance() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinipoolCycleDelayTolerance"));
	}

	/// @notice Set the rewards rate for validating Avalanche's p-chain
	/// @param rate A percentage representing Avalanche's rewards rate
	/// @dev Used for testing
	function setExpectedAVAXRewardsRate(uint256 rate) public onlyMultisig valueNotGreaterThanOne(rate) {
		setUint(keccak256("ProtocolDAO.ExpectedAVAXRewardsRate"), rate);
	}

	/// @notice The expected rewards rate for validating Avalanche's P-chain
	/// @return The protocol setting for the average rewards rate a node receives for being a validator
	function getExpectedAVAXRewardsRate() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.ExpectedAVAXRewardsRate"));
	}

	//*** Staking ***

	/// @notice The target percentage of ggAVAX to hold in TokenggAVAX contract
	/// 	1 ether = 100%
	/// 	0.1 ether = 10%
	/// @return uint256 The protocol setting for the current target reserve rate
	function getTargetGGAVAXReserveRate() external view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"));
	}

	/// @notice The max collateralization ratio of GGP to Assigned AVAX eligible for rewards
	/// @return The protocol setting for the max collateralization ratio of GGP to assigned AVAX a user can be rewarded for
	function getMaxCollateralizationRatio() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MaxCollateralizationRatio"));
	}

	/// @notice The min collateralization ratio of GGP to Assigned AVAX eligible for rewards or minipool creation
	/// @return The protocol setting for the min collateralization ratio of GGP to assigned AVAX a user can borrow at
	function getMinCollateralizationRatio() public view returns (uint256) {
		return getUint(keccak256("ProtocolDAO.MinCollateralizationRatio"));
	}

	//*** Contract Registration ***

	/// @notice Upgrade a contract by registering a new address and name, and un-registering the existing address
	/// @param contractName Name of the new contract
	/// @param existingAddr Address of the existing contract to be deleted
	/// @param newAddr Address of the new contract
	function upgradeContract(string memory contractName, address existingAddr, address newAddr) external onlyGuardian {
		if (
			bytes(getString(keccak256(abi.encodePacked("contract.name", existingAddr)))).length == 0 ||
			getAddress(keccak256(abi.encodePacked("contract.address", contractName))) == address(0)
		) {
			revert ExistingContractNotRegistered();
		}

		if (newAddr == address(0)) {
			revert InvalidContract();
		}

		setAddress(keccak256(abi.encodePacked("contract.address", contractName)), newAddr);
		setString(keccak256(abi.encodePacked("contract.name", newAddr)), contractName);
		setBool(keccak256(abi.encodePacked("contract.exists", newAddr)), true);

		deleteString(keccak256(abi.encodePacked("contract.name", existingAddr)));
		deleteBool(keccak256(abi.encodePacked("contract.exists", existingAddr)));
	}

	/// @notice Register a new contract with Storage
	/// @param contractName Contract name to register
	/// @param contractAddr Contract address to register
	function registerContract(string memory contractName, address contractAddr) public onlyGuardian {
		if (getAddress(keccak256(abi.encodePacked("contract.address", contractName))) != address(0)) {
			revert ContractAlreadyRegistered();
		}

		if (bytes(contractName).length == 0 || contractAddr == address(0)) {
			revert InvalidContract();
		}

		setBool(keccak256(abi.encodePacked("contract.exists", contractAddr)), true);
		setAddress(keccak256(abi.encodePacked("contract.address", contractName)), contractAddr);
		setString(keccak256(abi.encodePacked("contract.name", contractAddr)), contractName);
	}

	/// @notice Unregister a contract with Storage
	/// @param name Name of contract to unregister
	function unregisterContract(string memory name) public onlyGuardian {
		address addr = getContractAddress(name);
		deleteAddress(keccak256(abi.encodePacked("contract.address", name)));
		deleteString(keccak256(abi.encodePacked("contract.name", addr)));
		deleteBool(keccak256(abi.encodePacked("contract.exists", addr)));
	}
}
