pragma solidity ^0.8.0;

// SPDX-License-Identifier: GPL-3.0-only

// Represents a delegation node's status within the network
// Don't change the order of these or remove any. Only add to the end.
enum DelegationNodeStatus {
	Prelaunch, // The node has enough AVAX to begin delegation and is awaiting assignFunds/launch by Rialto
	Launched, // Rialto has claimed the funds and will send the delegation tx
	Delegated, // The node is currently being delegated to
	Withdrawable, // The node has finished staking period and all funds / rewards have been moved back to c-chain by Rialto
	Finished, // The node has withdrawn all funds
	Canceled, // The delegation has been canceled before ever starting validation
	Error // An error occured at some point in the process
}
