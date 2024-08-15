const MinipoolStreamliner = [
  {
    inputs: [],
    stateMutability: "nonpayable",
    type: "constructor",
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
    inputs: [
      {
        internalType: "bytes32",
        name: "providerName",
        type: "bytes32",
      },
    ],
    name: "InvalidHardwareProvider",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidOrOutdatedContract",
    type: "error",
  },
  {
    inputs: [],
    name: "MismatchedFunds",
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
    name: "OnlyOwner",
    type: "error",
  },
  {
    inputs: [],
    name: "SwapFailed",
    type: "error",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "uint8",
        name: "version",
        type: "uint8",
      },
    ],
    name: "Initialized",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "address",
        name: "nodeID",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "owner",
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
        name: "avaxForNodeRental",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "duration",
        type: "uint256",
      },
    ],
    name: "MinipoolRelaunched",
    type: "event",
  },
  {
    anonymous: false,
    inputs: [
      {
        indexed: false,
        internalType: "address",
        name: "nodeID",
        type: "address",
      },
      {
        indexed: false,
        internalType: "address",
        name: "owner",
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
        name: "avaxForNodeRental",
        type: "uint256",
      },
      {
        indexed: false,
        internalType: "uint256",
        name: "duration",
        type: "uint256",
      },
    ],
    name: "NewStreamlinedMinipoolMade",
    type: "event",
  },
  {
    inputs: [
      {
        internalType: "bytes32",
        name: "providerName",
        type: "bytes32",
      },
      {
        internalType: "address",
        name: "providerContract",
        type: "address",
      },
    ],
    name: "addHardwareProvider",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "bytes32",
        name: "",
        type: "bytes32",
      },
    ],
    name: "approvedHardwareProviders",
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
        components: [
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
          {
            internalType: "uint256",
            name: "duration",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxForMinipool",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxForGGP",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "minGGPAmountOut",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "avaxForNodeRental",
            type: "uint256",
          },
          {
            internalType: "uint256",
            name: "ggpStakeAmount",
            type: "uint256",
          },
          {
            internalType: "bytes32",
            name: "hardwareProvider",
            type: "bytes32",
          },
        ],
        internalType: "struct MinipoolStreamliner.StreamlinedMinipool",
        name: "newMinipool",
        type: "tuple",
      },
    ],
    name: "createOrRelaunchStreamlinedMinipool",
    outputs: [],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "contract Storage",
        name: "storageAddress",
        type: "address",
      },
      {
        internalType: "address",
        name: "wavax",
        type: "address",
      },
      {
        internalType: "address",
        name: "tjRouter",
        type: "address",
      },
    ],
    name: "initialize",
    outputs: [],
    stateMutability: "nonpayable",
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
        internalType: "bytes32",
        name: "providerName",
        type: "bytes32",
      },
    ],
    name: "removeHardwareProvider",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "user",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "avaxForGGP",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "minGGPAmountOut",
        type: "uint256",
      },
    ],
    name: "swapAndStakeGGPOnBehalfOf",
    outputs: [
      {
        internalType: "uint256",
        name: "ggpPurchased",
        type: "uint256",
      },
    ],
    stateMutability: "payable",
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

export default MinipoolStreamliner;
