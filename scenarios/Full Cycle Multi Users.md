### Select hardhat network

```sh
just node

# Create random node id and set as environment variable
export NODE=`just task debug:node_ids --name mynode | jq -r '.nodeID'`
echo $NODE

# Alice and Bob both stake 10,000 AVAX
# 20,000 avax total in liquid staker fund
just setup-evm
just task ggp:deal --recip nodeOp2 --amt 800

# View state of system
just task debug:list_actor_balances
just task debug:list_vars

# Two GGP Stakers
just task staking:stake_ggp --actor nodeOp1 --amt 300
just task staking:stake_ggp --actor nodeOp2 --amt 300
just task staking:list

# To show the concept, note Alice and Bob have staked 10000 AVAX in setup
just task ggavax:liqstaker_deposit_avax --actor alice --amt 2000
just task ggavax:liqstaker_deposit_avax --actor cam --amt 3000

# One GGP staker can create multiple minipools
just task minipool:create --actor nodeOp1 --node nodeOp1node1 --duration 14d
just task minipool:create --actor nodeOp1 --node nodeOp1node2 --duration 56d
just task minipool:create --actor nodeOp1 --node nodeOp1node3 --duration 84d
just task minipool:create --actor nodeOp2 --node nodeOp2node1 --duration 28d
just task minipool:create --actor nodeOp2 --node nodeOp2node2 --duration 56d

# To make sure we have enough liquid staking funds to match these minipools
just task ggavax:available_for_staking

just task minipool:list
just task minipool:list_claimable --actor rialto1
just task minipool:claim --actor rialto1
just task ggavax:available_for_staking

# 1. sync rewards
# 2. skip forward
# 3. sync rewards
# 4. make sure total assets are still 0.
# 5. preview withdraw

just task ggavax:sync_rewards --actor rialto1
just task debug:skip --duration 14d
just task ggavax:sync_rewards --actor rialto1
just task ggavax:available_for_staking
just task ggavax:total_assets
just task ggavax:preview_withdraw --amt 2000

just task minipool:recordStakingStart --actor rialto1 --node nodeOp1node1
just task minipool:recordStakingStart --actor rialto1 --node nodeOp1node2
just task minipool:recordStakingStart --actor rialto1 --node nodeOp1node3
just task minipool:recordStakingStart --actor rialto1 --node nodeOp2node1
just task minipool:recordStakingStart --actor rialto1 --node nodeOp2node2
just task minipool:list

just task debug:skip --duration 14d
just task inflation:canCycleStart --actor rialto1
just task inflation:startRewardsCycle --actor rialto1
just task nopClaim:distributeRewards
just task staking:list

# 14d since staking start has passed, one minipool has ended
just task minipool:recordStakingEnd --actor rialto1 --node nodeOp1node1 --reward 300
just task minipool:withdrawMinipoolFunds --actor nodeOp1 --node nodeOp1node1

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

just task debug:skip --duration 14d

# 28d since staking start has passed, one minipool has ended
just task minipool:recordStakingEnd --actor rialto1 --node nodeOp2node1 --reward 300
just task minipool:withdrawMinipoolFunds --actor nodeOp2 --node nodeOp2node1

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

just task debug:skip --duration 14d

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

# Day 56, Round two of ggp rewards:
just task inflation:canCycleStart --actor rialto1
just task inflation:startRewardsCycle --actor rialto1
just task nopClaim:distributeRewards
just task staking:list
just task nopClaim:claimAndRestakeHalf --actor nodeOp1
just task nopClaim:claimAndRestakeHalf --actor nodeOp2
just task staking:list
just task debug:list_actor_balances


just task debug:skip --duration 14d

# 56 days since staking start, some minipools end
just task minipool:recordStakingEnd --actor rialto1 --node nodeOp1node2 --reward 300
just task minipool:recordStakingEnd --actor rialto1 --node nodeOp2node2 --reward 300
just task minipool:withdrawMinipoolFunds --actor nodeOp1 --node nodeOp1node2
just task minipool:withdrawMinipoolFunds --actor nodeOp2 --node nodeOp2node2

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

just task debug:skip --duration 14d

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

# Day 84, Round three of ggp rewards:
just task inflation:canCycleStart --actor rialto1
just task inflation:startRewardsCycle --actor rialto1
just task nopClaim:distributeRewards
just task staking:list
just task debug:list_actor_balances
just task nopClaim:claimAndRestakeHalf --actor nodeOp1
just task nopClaim:claimAndRestakeHalf --actor nodeOp2
just task staking:list

just task debug:skip --duration 14d

# 84 days since staking start, some minipools end
just task minipool:recordStakingEnd --actor rialto1 --node nodeOp1node3 --reward 300
just task minipool:withdrawMinipoolFunds --actor nodeOp1 --node nodeOp1node3

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

just task debug:skip --duration 14d

# Day 112, Round four of ggp rewards:
just task inflation:canCycleStart --actor rialto1
just task inflation:startRewardsCycle --actor rialto1
just task nopClaim:distributeRewards
just task staking:list
just task debug:list_actor_balances
just task nopClaim:claimAndRestakeHalf --actor nodeOp1
just task nopClaim:claimAndRestakeHalf --actor nodeOp2
just task staking:list

# ggavax rewards cycle every 14d
just task ggavax:sync_rewards --actor rialto1

just task ggavax:liqstaker_redeem_ggavax --actor alice --amt 2000 &
just task ggavax:liqstaker_redeem_ggavax --actor bob --amt 3000 &

just task debug:list_actor_balances

```
