const ProtocolDAO = [
	{
		inputs: [
			{
				internalType: "contract Storage",
				name: "storageAddress",
				type: "address",
			},
		],
		stateMutability: "nonpayable",
		type: "constructor",
	},
	{
		inputs: [],
		name: "ContractAlreadyRegistered",
		type: "error",
	},
	{
		inputs: [],
		name: "ContractNotFound",
		type: "error",
	},
	{
		inputs: [],
		name: "ContractPaused",
		type: "error",
	},
	{
		inputs: [],
		name: "ExistingContractNotRegistered",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidContract",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidOrOutdatedContract",
		type: "error",
	},
	{
		inputs: [],
		name: "MustBeGuardian",
		type: "error",
	},
	{
		inputs: [],
		name: "MustBeGuardianOrValidContract",
		type: "error",
	},
	{
		inputs: [],
		name: "MustBeMultisig",
		type: "error",
	},
	{
		inputs: [],
		name: "ValueNotWithinRange",
		type: "error",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "claimingContract",
				type: "string",
			},
		],
		name: "getClaimingContractPct",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "contractName",
				type: "string",
			},
		],
		name: "getContractPaused",
		outputs: [
			{
				internalType: "bool",
				name: "",
				type: "bool",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getExpectedAVAXRewardsRate",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getInflationIntervalRate",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getInflationIntervalSeconds",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMaxCollateralizationRatio",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinCollateralizationRatio",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolCancelMoratoriumSeconds",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolCycleDelayTolerance",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolCycleDuration",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolMaxAVAXAssignment",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolMaxDuration",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolMinAVAXAssignment",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolMinAVAXStakingAmt",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolMinDuration",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolNodeCommissionFeePct",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getRewardsCycleSeconds",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getRewardsEligibilityMinSeconds",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getTargetGGAVAXReserveRate",
		outputs: [
			{
				internalType: "uint256",
				name: "",
				type: "uint256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getWithdrawForDelegationEnabled",
		outputs: [
			{
				internalType: "bool",
				name: "",
				type: "bool",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "roleName",
				type: "string",
			},
			{
				internalType: "address",
				name: "addr",
				type: "address",
			},
		],
		name: "hasRole",
		outputs: [
			{
				internalType: "bool",
				name: "",
				type: "bool",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "initialize",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "contractName",
				type: "string",
			},
		],
		name: "pauseContract",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "contractName",
				type: "string",
			},
			{
				internalType: "address",
				name: "contractAddr",
				type: "address",
			},
		],
		name: "registerContract",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "contractName",
				type: "string",
			},
		],
		name: "resumeContract",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "claimingContract",
				type: "string",
			},
			{
				internalType: "uint256",
				name: "decimal",
				type: "uint256",
			},
		],
		name: "setClaimingContractPct",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "uint256",
				name: "rate",
				type: "uint256",
			},
		],
		name: "setExpectedAVAXRewardsRate",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "roleName",
				type: "string",
			},
			{
				internalType: "address",
				name: "addr",
				type: "address",
			},
			{
				internalType: "bool",
				name: "isEnabled",
				type: "bool",
			},
		],
		name: "setRole",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "bool",
				name: "b",
				type: "bool",
			},
		],
		name: "setWithdrawForDelegationEnabled",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "name",
				type: "string",
			},
		],
		name: "unregisterContract",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "string",
				name: "contractName",
				type: "string",
			},
			{
				internalType: "address",
				name: "existingAddr",
				type: "address",
			},
			{
				internalType: "address",
				name: "newAddr",
				type: "address",
			},
		],
		name: "upgradeContract",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [],
		name: "version",
		outputs: [
			{
				internalType: "uint8",
				name: "",
				type: "uint8",
			},
		],
		stateMutability: "view",
		type: "function",
	},
] as const;

export default ProtocolDAO;
