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

## Hardhat Deploy

A deploy scripts in `scripts/` can be used to deploy and register all of the GoGo contracts.

`just deploy-base`
`just deploy`

## Hardhat Tasks

The `tasks` directory is automatically loaded, and all defined tasks can be run from the command line.

`just task` will show you all the available tasks with a description

`just task <taskname> <args>`

`just task help <taskname>`

## Debugging

If you want to see into the matrix, you can say

`export DEBUG="*"`

before you run hardhat commands, and get detailed logs. To get just specific ones:

`export DEBUG=@openzeppelin:*` or `export DEBUG=hardhat:*`
