// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

// Represents a minipool's status within the network
// Don't change the order of these or remove any. Only add to the end.
enum MinipoolStatus {
	Prelaunch, // The minipool has NodeOp AVAX and is awaiting assignFunds/launch by Rialto
	Launched, // Rialto has claimed the funds and will send the validator tx
	Staking, // The minipool node is currently staking
	Withdrawable, // The minipool has finished staking period and all funds / rewards have been moved back to c-chain by Rialto
	Finished, // The minipool node has withdrawn all funds
	Canceled, // The minipool has been canceled before ever starting validation
	Error // An error occurred at some point in the process
}
