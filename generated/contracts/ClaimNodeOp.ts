const ClaimNodeOp = [
  {
    inputs: [
      {
        internalType: 'contract Storage',
        name: 'storageAddress',
        type: 'address',
      },
    ],
    stateMutability: 'nonpayable',
    type: 'constructor',
  },
  {
    inputs: [],
    name: 'ContractNotFound',
    type: 'error',
  },
  {
    inputs: [],
    name: 'ContractPaused',
    type: 'error',
  },
  {
    inputs: [],
    name: 'InvalidAmount',
    type: 'error',
  },
  {
    inputs: [],
    name: 'InvalidOrOutdatedContract',
    type: 'error',
  },
  {
    inputs: [],
    name: 'MustBeGuardian',
    type: 'error',
  },
  {
    inputs: [],
    name: 'MustBeGuardianOrValidContract',
    type: 'error',
  },
  {
    inputs: [],
    name: 'MustBeMultisig',
    type: 'error',
  },
  {
    inputs: [],
    name: 'NoRewardsToClaim',
    type: 'error',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: '',
        type: 'address',
      },
    ],
    name: 'RewardsAlreadyDistributedToStaker',
    type: 'error',
  },
  {
    inputs: [],
    name: 'RewardsCycleNotStarted',
    type: 'error',
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: true,
        internalType: 'address',
        name: 'to',
        type: 'address',
      },
      {
        indexed: false,
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'GGPRewardsClaimed',
    type: 'event',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'stakerAddr',
        type: 'address',
      },
      {
        internalType: 'uint256',
        name: 'totalEligibleGGPStaked',
        type: 'uint256',
      },
    ],
    name: 'calculateAndDistributeRewards',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'uint256',
        name: 'claimAmt',
        type: 'uint256',
      },
    ],
    name: 'claimAndRestake',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'getRewardsCycleTotal',
    outputs: [
      {
        internalType: 'uint256',
        name: '',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'address',
        name: 'stakerAddr',
        type: 'address',
      },
    ],
    name: 'isEligible',
    outputs: [
      {
        internalType: 'bool',
        name: '',
        type: 'bool',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'uint256',
        name: 'amount',
        type: 'uint256',
      },
    ],
    name: 'setRewardsCycleTotal',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
  {
    inputs: [],
    name: 'version',
    outputs: [
      {
        internalType: 'uint8',
        name: '',
        type: 'uint8',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
] as const

export default ClaimNodeOp
