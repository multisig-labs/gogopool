const MinipoolManager = [
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
		name: "CancellationTooEarly",
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
		name: "DelegationFeeOutOfBounds",
		type: "error",
	},
	{
		inputs: [],
		name: "DurationOutOfBounds",
		type: "error",
	},
	{
		inputs: [],
		name: "InsufficientAVAXForMinipoolCreation",
		type: "error",
	},
	{
		inputs: [],
		name: "InsufficientGGPCollateralization",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidAVAXAssignmentRequest",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidAmount",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidEndTime",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidMultisigAddress",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidNodeID",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidOrOutdatedContract",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidStartTime",
		type: "error",
	},
	{
		inputs: [],
		name: "InvalidStateTransition",
		type: "error",
	},
	{
		inputs: [],
		name: "MinipoolDurationExceeded",
		type: "error",
	},
	{
		inputs: [],
		name: "MinipoolNotFound",
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
		name: "NegativeCycleDuration",
		type: "error",
	},
	{
		inputs: [],
		name: "OnlyOwner",
		type: "error",
	},
	{
		inputs: [],
		name: "OnlyRole",
		type: "error",
	},
	{
		inputs: [],
		name: "WithdrawAmountTooLarge",
		type: "error",
	},
	{
		inputs: [],
		name: "WithdrawForDelegationDisabled",
		type: "error",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: false,
				internalType: "bytes",
				name: "blsPubkeyAndSig",
				type: "bytes",
			},
		],
		name: "BLSKeysAdded",
		type: "event",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: false,
				internalType: "uint256",
				name: "amount",
				type: "uint256",
			},
			{
				indexed: false,
				internalType: "uint256",
				name: "rewardsAmount",
				type: "uint256",
			},
		],
		name: "DepositFromDelegation",
		type: "event",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: false,
				internalType: "uint256",
				name: "ggp",
				type: "uint256",
			},
		],
		name: "GGPSlashed",
		type: "event",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: false,
				internalType: "bytes32",
				name: "hardwareProvider",
				type: "bytes32",
			},
			{
				indexed: false,
				internalType: "uint256",
				name: "duration",
				type: "uint256",
			},
		],
		name: "MinipoolLaunched",
		type: "event",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: true,
				internalType: "enum MinipoolStatus",
				name: "status",
				type: "uint8",
			},
		],
		name: "MinipoolStatusChanged",
		type: "event",
	},
	{
		anonymous: false,
		inputs: [
			{
				indexed: true,
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				indexed: false,
				internalType: "uint256",
				name: "amount",
				type: "uint256",
			},
		],
		name: "WithdrawForDelegation",
		type: "event",
	},
	{
		inputs: [
			{
				internalType: "uint256",
				name: "avaxRewardAmt",
				type: "uint256",
			},
		],
		name: "calculateGGPSlashAmt",
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
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "canClaimAndInitiateStaking",
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
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "cancelMinipool",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "bytes32",
				name: "errorCode",
				type: "bytes32",
			},
		],
		name: "cancelMinipoolByMultisig",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "claimAndInitiateStaking",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "uint256",
				name: "duration",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "delegationFee",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "avaxAssignmentRequest",
				type: "uint256",
			},
			{
				internalType: "bytes",
				name: "blsPubkeyAndSig",
				type: "bytes",
			},
			{
				internalType: "bytes32",
				name: "hardwareProvider",
				type: "bytes32",
			},
		],
		name: "createMinipool",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "owner",
				type: "address",
			},
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "uint256",
				name: "duration",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "delegationFee",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "avaxAssignmentRequest",
				type: "uint256",
			},
			{
				internalType: "bytes",
				name: "blsPubkeyAndSig",
				type: "bytes",
			},
			{
				internalType: "bytes32",
				name: "hardwareProvider",
				type: "bytes32",
			},
		],
		name: "createMinipoolOnBehalfOf",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "uint256",
				name: "rewards",
				type: "uint256",
			},
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "depositFromDelegation",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "uint256",
				name: "duration",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "avaxAmt",
				type: "uint256",
			},
		],
		name: "getExpectedAVAXRewardsAmt",
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
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "getIndexOf",
		outputs: [
			{
				internalType: "int256",
				name: "",
				type: "int256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "int256",
				name: "index",
				type: "int256",
			},
		],
		name: "getMinipool",
		outputs: [
			{
				components: [
					{
						internalType: "int256",
						name: "index",
						type: "int256",
					},
					{
						internalType: "address",
						name: "nodeID",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "status",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "duration",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "delegationFee",
						type: "uint256",
					},
					{
						internalType: "address",
						name: "owner",
						type: "address",
					},
					{
						internalType: "address",
						name: "multisigAddr",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpInitialAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerAmt",
						type: "uint256",
					},
					{
						internalType: "bytes",
						name: "blsPubkeyAndSig",
						type: "bytes",
					},
					{
						internalType: "bytes32",
						name: "txID",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "creationTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "initialStartTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "startTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "endTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxTotalRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "errorCode",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "ggpSlashAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpRewardAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "hardwareProvider",
						type: "bytes32",
					},
				],
				internalType: "struct MinipoolManager.Minipool",
				name: "mp",
				type: "tuple",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "getMinipoolByNodeID",
		outputs: [
			{
				components: [
					{
						internalType: "int256",
						name: "index",
						type: "int256",
					},
					{
						internalType: "address",
						name: "nodeID",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "status",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "duration",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "delegationFee",
						type: "uint256",
					},
					{
						internalType: "address",
						name: "owner",
						type: "address",
					},
					{
						internalType: "address",
						name: "multisigAddr",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpInitialAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerAmt",
						type: "uint256",
					},
					{
						internalType: "bytes",
						name: "blsPubkeyAndSig",
						type: "bytes",
					},
					{
						internalType: "bytes32",
						name: "txID",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "creationTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "initialStartTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "startTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "endTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxTotalRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "errorCode",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "ggpSlashAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpRewardAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "hardwareProvider",
						type: "bytes32",
					},
				],
				internalType: "struct MinipoolManager.Minipool",
				name: "mp",
				type: "tuple",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getMinipoolCount",
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
				internalType: "enum MinipoolStatus",
				name: "status",
				type: "uint8",
			},
			{
				internalType: "uint256",
				name: "offset",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "limit",
				type: "uint256",
			},
		],
		name: "getMinipools",
		outputs: [
			{
				components: [
					{
						internalType: "int256",
						name: "index",
						type: "int256",
					},
					{
						internalType: "address",
						name: "nodeID",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "status",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "duration",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "delegationFee",
						type: "uint256",
					},
					{
						internalType: "address",
						name: "owner",
						type: "address",
					},
					{
						internalType: "address",
						name: "multisigAddr",
						type: "address",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpInitialAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerAmt",
						type: "uint256",
					},
					{
						internalType: "bytes",
						name: "blsPubkeyAndSig",
						type: "bytes",
					},
					{
						internalType: "bytes32",
						name: "txID",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "creationTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "initialStartTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "startTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "endTime",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxTotalRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "errorCode",
						type: "bytes32",
					},
					{
						internalType: "uint256",
						name: "ggpSlashAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxNodeOpRewardAmt",
						type: "uint256",
					},
					{
						internalType: "uint256",
						name: "avaxLiquidStakerRewardAmt",
						type: "uint256",
					},
					{
						internalType: "bytes32",
						name: "hardwareProvider",
						type: "bytes32",
					},
				],
				internalType: "struct MinipoolManager.Minipool[]",
				name: "minipools",
				type: "tuple[]",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [],
		name: "getTotalAVAXLiquidStakerAmt",
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
		name: "minStakingDuration",
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
		name: "receiveWithdrawalAVAX",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "uint256",
				name: "endTime",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "avaxTotalRewardAmt",
				type: "uint256",
			},
		],
		name: "recordStakingEnd",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "uint256",
				name: "endTime",
				type: "uint256",
			},
			{
				internalType: "uint256",
				name: "avaxTotalRewardAmt",
				type: "uint256",
			},
		],
		name: "recordStakingEndThenMaybeCycle",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "bytes32",
				name: "errorCode",
				type: "bytes32",
			},
		],
		name: "recordStakingError",
		outputs: [],
		stateMutability: "payable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "bytes32",
				name: "txID",
				type: "bytes32",
			},
			{
				internalType: "uint256",
				name: "startTime",
				type: "uint256",
			},
		],
		name: "recordStakingStart",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "requireValidMinipool",
		outputs: [
			{
				internalType: "int256",
				name: "",
				type: "int256",
			},
		],
		stateMutability: "view",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "bytes",
				name: "blsPubkeyAndSig",
				type: "bytes",
			},
		],
		name: "setBLSKeys",
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
	{
		inputs: [
			{
				internalType: "uint256",
				name: "amount",
				type: "uint256",
			},
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "withdrawForDelegation",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
		],
		name: "withdrawMinipoolFunds",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
	{
		inputs: [
			{
				internalType: "address",
				name: "nodeID",
				type: "address",
			},
			{
				internalType: "uint256",
				name: "duration",
				type: "uint256",
			},
			{
				internalType: "bytes32",
				name: "hardwareProvider",
				type: "bytes32",
			},
		],
		name: "withdrawRewardsAndRelaunchMinipool",
		outputs: [],
		stateMutability: "nonpayable",
		type: "function",
	},
] as const;

export default MinipoolManager;
