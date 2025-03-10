// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

abstract contract IHardwareProvider {
	address public paymentReceiver;

	event HardwareRented(address user, address nodeID, bytes32 hardwareProviderName, uint256 duration, uint256 payment);

	/// @notice Initiate hardware rental with provider
	///
	/// @param user 		Address of the user to subscribe
	/// @param nodeID 	Id of node to be made a validator
	/// @param duration Subscription length
	function rentHardware(address user, address nodeID, uint256 duration) external payable virtual;

	function getHardwareProviderName() public virtual returns (bytes32);
}
