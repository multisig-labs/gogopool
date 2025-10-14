// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {Storage} from "./Storage.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {Vault} from "./Vault.sol";
import {IWithdrawer} from "../interface/IWithdrawer.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

/// @title Protocol DAO claiming GGP Rewards
contract ClaimProtocolDAO is Base {
	using SafeTransferLib for address;

	error InvalidAddress();
	error InvalidAmount();

	event GGPTokensSentByDAOProtocol(string invoiceID, address indexed from, address indexed to, uint256 amount);
	event AVAXTokensSentByDAOProtocol(string invoiceID, address indexed from, address indexed to, uint256 amount);

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

		if (recipientAddress == address(0)) {
			revert InvalidAddress();
		}

		if (amount == 0 || amount > vault.balanceOfToken("ClaimProtocolDAO", ggpToken)) {
			revert InvalidAmount();
		}

		emit GGPTokensSentByDAOProtocol(invoiceID, address(this), recipientAddress, amount);

		vault.withdrawToken(recipientAddress, ggpToken, amount);
	}

	/// @notice Spends the ProtocolDAO's AVAX rewards
	/// @param invoiceID The id of the invoice for the spend action
	/// @param recipientAddress The C-chain address the tokens should be sent to
	/// @param amount Number of AVAX tokens to spend
	function spendAVAX(string memory invoiceID, address recipientAddress, uint256 amount) external onlyGuardian {
		Vault vault = Vault(getContractAddress("Vault"));

		if (recipientAddress == address(0)) {
			revert InvalidAddress();
		}

		if (amount == 0 || amount > vault.balanceOf("ClaimProtocolDAO")) {
			revert InvalidAmount();
		}

		emit AVAXTokensSentByDAOProtocol(invoiceID, address(this), recipientAddress, amount);

		vault.withdrawAVAX(amount);

		address(recipientAddress).safeTransferETH(amount);
	}

	/// @dev Must implement IWithdrawer to receive funds from Vault.sol
	function receiveWithdrawalAVAX() external payable {}
}
