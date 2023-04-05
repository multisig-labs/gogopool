# Full Cycle One Staker, One Minipool

```sh

# Start a hardhat node
just node

# Setup environment from scratch
# Deploy contracts, set protocol settings, and fill ggAVAX with liquid staker funds
just setup-evm

# Create random node id and set as environment variable
export NODE=`just task debug:node_ids --name mynode | jq -r '.nodeID'`
echo $NODE

# Stake GGP
just task staking:stake_ggp --actor nodeOp1 --amt 300
just task staking:info
just task staking:staker_info --actor nodeOp1

# Create Minipool
just task minipool:create --actor nodeOp1 --node $NODE --duration 2m --avax 1000
just task minipool:list

# Rialto withdraws funds and starts
just task minipool:list_claimable --actor rialto1
just task minipool:claim_one --actor rialto1 --node $NODE
just task minipool:recordStakingStart --actor rialto1 --node $NODE

just task debug:skip --duration 2m

# Finish Minipool
just task minipool:recordStakingEnd --actor rialto1 --node $NODE --reward 300
just task minipool:withdrawMinipoolFunds --actor nodeOp1 --node $NODE
just task debug:list_actor_balances

# GGP Rewards Cycle
just task debug:skip --duration 14d
just task inflation:canCycleStart --actor rialto1
just task inflation:startRewardsCycle --actor rialto1
just task nopClaim:distributeRewards
just task nopClaim:claimAndRestakeHalf --actor nodeOp1
just task staking:list

# ggAVAX Rewards cycle
just task ggavax:sync_rewards --actor rialto1

# ggAVAX Rewards cycle
just task ggavax:liqstaker_redeem_ggavax --actor alice --amt 1000
just task ggavax:liqstaker_redeem_ggavax --actor bob --amt 1000
just task debug:list_actor_balances
```
