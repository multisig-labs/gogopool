# GoGoGadget GoGoPool!

## First time setup

```
yarn
brew install just
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge install
just build
just test
```

## Justfile

Most commands used in the project are in the `Justfile`. To get a list of whats available type `just`

## Deployment

Contracts are deployed using Forge scripts. The main deployment commands are:

`just deploy` - Deploy contracts to the configured network
`just forge-script <script-name>` - Execute a specific Forge script

Key deployment scripts:
- `upgrade-liquid-staking-system.s.sol` - Upgrades TokenggAVAX, deploys WithdrawQueue and TokenpstAVAX

## Testing

Run all tests: `just test`
Run specific contract tests: `just test <ContractName>`
Run fork tests: `just test-fork`
Run tests with coverage: `npx hardhat coverage`

## Hardhat Tasks (Legacy)

The `tasks` directory contains legacy Hardhat tasks that can be run via:

`just task` - Show all available tasks
`just task <taskname> <args>` - Run a specific task

## Debugging

If you want to see into the matrix, you can say

`export DEBUG="*"`

before you run hardhat commands, and get detailed logs. To get just specific ones:

`export DEBUG=@openzeppelin:*` or `export DEBUG=hardhat:*`
