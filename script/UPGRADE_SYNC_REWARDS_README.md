# TokenggAVAX SYNC_REWARDS_ROLE Upgrade Script

This script upgrades the TokenggAVAX contract to add the `SYNC_REWARDS_ROLE` access control to the `syncRewards()` function.

## Overview

The upgrade adds a new role-based access control system to the `syncRewards()` function, which was previously public. Now only addresses with the `SYNC_REWARDS_ROLE` can call this function. Additionally, it adds guardian functions: `guardianWithdrawWAVAX()` for withdrawing excess WAVAX and `setLastReward()` for recovering from syncRewards issues.

## Changes Made

1. **Added SYNC_REWARDS_ROLE constant**: `bytes32 public constant SYNC_REWARDS_ROLE = keccak256("SYNC_REWARDS_ROLE");`
2. **Updated syncRewards() function**: Added `onlyRole(SYNC_REWARDS_ROLE)` modifier
3. **Updated function documentation**: Clarified that only addresses with the role can call the function
4. **Added guardianWithdrawWAVAX() function**: Allows Guardian to withdraw any amount of WAVAX from the contract without adjusting internal variables
5. **Added setLastReward() function**: Allows Guardian to manually adjust the `lastRewardsAmt` for recovery scenarios

## Prerequisites

Before running the upgrade script, ensure you have:

1. **Environment Variables Set**:

   ```bash
   export SYNC_REWARDS_ROLE_RECIPIENT=<address>
   export GUARDIAN=<guardian_address>
   ```

2. **Access to the deployment environment** with the necessary private keys and RPC endpoints

3. **Understanding of the upgrade process** and governance requirements

## Usage

### 1. Run the Upgrade Script

```bash
forge script script/upgrade-tokenggavax-sync-rewards.s.sol:UpgradeTokenggAVAXSyncRewards --rpc-url <RPC_URL> --broadcast --verify
```

### 2. Execute the Generated Transactions

The script will output several transactions that need to be executed:

1. **Upgrade Transaction**: Deploy the new implementation and upgrade the proxy
2. **Role Grant Transaction**: Grant `SYNC_REWARDS_ROLE` to the designated recipient

### 3. Verify the Upgrade

After the upgrade, verify that:

- The `syncRewards()` function now requires the `SYNC_REWARDS_ROLE`
- The designated recipient has the role and can call `syncRewards()`
- Other addresses without the role cannot call `syncRewards()`
- All existing functionality remains intact

## Environment Variables

| Variable                      | Description                                       | Required |
| ----------------------------- | ------------------------------------------------- | -------- |
| `SYNC_REWARDS_ROLE_RECIPIENT` | Address that should receive the SYNC_REWARDS_ROLE | Yes      |
| `GUARDIAN`                    | Guardian address for the protocol                 | Yes      |

## New Functions

### guardianWithdrawWAVAX(uint256 amount, address to)

This function allows the Guardian (admin) to withdraw any amount of WAVAX from the contract:

- **Access Control**: Only the Guardian can call this function
- **Purpose**: Remove excess WAVAX from the contract to prevent it from being counted as rewards
- **Safety**: Includes validation for zero address, zero amount, and sufficient balance
- **No State Changes**: This function only transfers WAVAX and does not adjust any internal variables

### setLastReward(uint192 newLastRewardsAmt)

This function allows the Guardian to manually adjust the `lastRewardsAmt` for recovery scenarios:

- **Access Control**: Only the Guardian can call this function
- **Purpose**: Recover from situations where `syncRewards` was called incorrectly or adjust rewards calculation
- **Use Cases**:
  - Recovery if `syncRewards` gets called inappropriately
  - Manual adjustment of rewards amount
  - Protocol maintenance scenarios
- **Parameters**: `newLastRewardsAmt` - The new value for `lastRewardsAmt`

## Security Considerations

1. **Role Management**: Only grant `SYNC_REWARDS_ROLE` to trusted addresses
2. **Access Control**: The role controls when rewards are synced, which affects all token holders
3. **Guardian Withdrawal**: The `guardianWithdrawWAVAX()` function should only be used to remove excess WAVAX, not for regular operations
4. **Guardian Recovery**: The `setLastReward()` function should only be used for recovery scenarios, not for regular operations
5. **Upgrade Safety**: Ensure the upgrade is executed through proper governance channels
6. **Testing**: Test the upgrade on a testnet before mainnet deployment

## Post-Upgrade Actions

After the upgrade is complete:

1. **Grant Additional Roles**: If needed, grant `SYNC_REWARDS_ROLE` to additional addresses
2. **Revoke Roles**: Remove the role from addresses that no longer need it
3. **Monitor**: Ensure the rewards syncing continues to work as expected
4. **Documentation**: Update any documentation that references the `syncRewards()` function

## Rollback Plan

If issues are discovered after the upgrade:

1. **Immediate**: Revoke `SYNC_REWARDS_ROLE` from problematic addresses
2. **Short-term**: Grant the role to a trusted address that can manage syncing
3. **Long-term**: Consider reverting to a previous implementation if necessary

## Testing

Before running on mainnet, test the upgrade on a testnet:

1. Deploy the upgrade script on Fuji testnet
2. Verify the role-based access control works correctly
3. Test that existing functionality is preserved
4. Ensure the upgrade process works smoothly

## Support

For questions or issues with the upgrade:

1. Check the test suite for examples of proper usage
2. Review the access control tests in `TokenggAVAXAccessControl.t.sol`
3. Consult the protocol documentation
4. Contact the development team
