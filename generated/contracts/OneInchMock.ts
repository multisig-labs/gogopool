const OneInchMock = [
  {
    inputs: [],
    name: 'NotAuthorized',
    type: 'error',
  },
  {
    inputs: [],
    name: 'authorizedSetter',
    outputs: [
      {
        internalType: 'address',
        name: '',
        type: 'address',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [
      {
        internalType: 'contract IERC20',
        name: 'srcToken',
        type: 'address',
      },
      {
        internalType: 'bool',
        name: 'useSrcWrappers',
        type: 'bool',
      },
    ],
    name: 'getRateToEth',
    outputs: [
      {
        internalType: 'uint256',
        name: 'weightedRate',
        type: 'uint256',
      },
    ],
    stateMutability: 'view',
    type: 'function',
  },
  {
    inputs: [],
    name: 'rateToEth',
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
        internalType: 'uint256',
        name: 'rate',
        type: 'uint256',
      },
    ],
    name: 'setRateToEth',
    outputs: [],
    stateMutability: 'nonpayable',
    type: 'function',
  },
] as const

export default OneInchMock
