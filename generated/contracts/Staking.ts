const Staking = [
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
    name: "CannotWithdrawUnder150CollateralizationRatio",
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
    name: "GGPLocked",
    type: "error",
  },
  {
    inputs: [],
    name: "InsufficientBalance",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidOrOutdatedContract",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidRewardsStartTime",
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
    name: "NotAuthorized",
    type: "error",
  },
  {
    inputs: [],
    name: "StakerNotFound",
    type: "error",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "from",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "GGPStaked",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: "address",
        name: "to",
        type: "address",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "GGPWithdrawn",
    type: "event",
  },
  {
    inputs: [],
    name: "authorizedStaker",
    outputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "decreaseAVAXAssigned",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "decreaseAVAXStake",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "decreaseAVAXValidating",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "decreaseGGPRewards",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getAVAXAssigned",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getAVAXStake",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getAVAXValidating",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getAVAXValidatingHighWater",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getCollateralizationRatio",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getEffectiveGGPStaked",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getEffectiveRewardsRatio",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getGGPRewards",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getGGPStake",
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
        name: "stakerAddr",
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
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getLastRewardsCycleCompleted",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getMinimumGGPStake",
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
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "getRewardsStartTime",
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
        internalType: "int256",
        name: "stakerIndex",
        type: "int256",
      },
    ],
    name: "getStaker",
    outputs: [
      {
        components: [
          {
            internalType: "address",
            name: "stakerAddr",
            type: "address",
          },
          {
            internalType: "uint256",
            name: "avaxAssigned",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxStaked",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxValidating",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxValidatingHighWater",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpRewards",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpStaked",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "lastRewardsCycleCompleted",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "rewardsStartTime",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpLockedUntil",
            type: "uint256",
          },
        ],
        internalType: "struct Staking.Staker",
        name: "staker",
        type: "tuple",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getStakerCount",
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
    name: "getStakers",
    outputs: [
      {
        components: [
          {
            internalType: "address",
            name: "stakerAddr",
            type: "address",
          },
          {
            internalType: "uint256",
            name: "avaxAssigned",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxStaked",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxValidating",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxValidatingHighWater",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpRewards",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpStaked",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "lastRewardsCycleCompleted",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "rewardsStartTime",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpLockedUntil",
            type: "uint256",
          },
        ],
        internalType: "struct Staking.Staker[]",
        name: "stakers",
        type: "tuple[]",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "getTotalGGPStake",
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
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseAVAXAssigned",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseAVAXStake",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseAVAXValidating",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "increaseGGPRewards",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
    ],
    name: "requireValidStaker",
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
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "restakeGGP",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "setAVAXValidatingHighWater",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "cycleNumber",
        type: "uint256",
      },
    ],
    name: "setLastRewardsCycleCompleted",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "time",
        type: "uint256",
      },
    ],
    name: "setRewardsStartTime",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "ggpAmt",
        type: "uint256",
      },
    ],
    name: "slashGGP",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "stakeGGP",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
    ],
    name: "stakeGGPOnBehalfOf",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "stakerAddr",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "amount",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "ggpLockedUntil",
        type: "uint256",
      },
    ],
    name: "stakeGGPOnBehalfOfWithLock",
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
    ],
    name: "withdrawGGP",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
] as const;

export default Staking;
