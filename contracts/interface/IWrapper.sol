// SPDX-License-Identifier: BSL-1.1
pragma solidity ^0.8.17;

interface IWrapper {
	function oneTransactionSubscription(
		address customer,
		uint16 countryOfResidence,
		uint16 duration,
		bool bestRate,
		string memory currencySymbol,
		bool withdrawalRightWaiver
	) external returns (address);
}
