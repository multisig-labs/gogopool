# Deployment

Forge scripts for deploying the protocol in a dev environment (HardHat/Anvil) as well as Fuji or Mainnet.

HH / Anvil are configured to look more like Avalanche C-Chain for convenience:

- Chainid 43112
- use MNEMONIC env var for users
- Hardhat Network defaults to "custom"

## Development

Start HH with `just node`, in another terminal say `just deploy-dev`. This should get you up and running such that the HH tasks will work.

## Fuji

First, set up your .env file like so:

```
ETH_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
MNEMONIC="<GoGoDeployer Mnemonic>"
# First private key from MNEMONIC
PRIVATE_KEY="0x123..."
```

### Deploy Contracts

```
just forge-script deploy
just forge-script init-fuji
```
