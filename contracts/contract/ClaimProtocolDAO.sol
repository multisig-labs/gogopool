// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {Vault} from "./Vault.sol";

/// @title Protocol DAO claiming GGP Rewards
contract ClaimProtocolDAO is Base {
	error InvalidAmount();

	event GGPTokensSentByDAOProtocol(string invoiceID, address indexed from, address indexed to, uint256 amount);

	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	/// @notice Spends the ProtocolDAO's GGP rewards
	/// @param invoiceID The id of the invoice for the spend action
	/// @param recipientAddress The C-chain address the tokens should be sent to
	/// @param amount Number of GGP tokens to spend
	function spend(string memory invoiceID, address recipientAddress, uint256 amount) external onlyGuardian {
		Vault vault = Vault(getContractAddress("Vault"));
		TokenGGP ggpToken = TokenGGP(getContractAddress("TokenGGP"));

		if (amount == 0 || amount > vault.balanceOfToken("ClaimProtocolDAO", ggpToken)) {
			revert InvalidAmount();
		}

		vault.withdrawToken(recipientAddress, ggpToken, amount);

		emit GGPTokensSentByDAOProtocol(invoiceID, address(this), recipientAddress, amount);
	}
}
