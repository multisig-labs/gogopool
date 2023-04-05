// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

/// @dev Must implement this interface to receive funds from Vault.sol
interface IWithdrawer {
	function receiveWithdrawalAVAX() external payable;
}
