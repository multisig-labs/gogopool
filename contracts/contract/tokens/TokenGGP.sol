// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../Base.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {Storage} from "../Storage.sol";
import {Vault} from "../Vault.sol";

// GGP Governance and Utility Token
// Inflationary with rate determined by DAO

contract TokenGGP is ERC20, Base {
	uint256 private constant INITIAL_SUPPLY = 18_000_000 ether;
	uint256 public constant MAX_SUPPLY = 22_500_000 ether;

	error MaximumTokensReached();

	constructor(Storage storageAddress) ERC20("GoGoPool Protocol", "GGP", 18) Base(storageAddress) {
		// minting to GoGoPool Foundation address
		_mint(address(0xd98C0e8352352b3c486Cc9676F1b593F4cf28102), INITIAL_SUPPLY);
	}

	/// @notice Mint new GGP tokens
	/// @param amount Number of GGP tokens to be minted
	function mint(uint256 amount) external onlySpecificRegisteredContract("RewardsPool", msg.sender) {
		if (totalSupply + amount > MAX_SUPPLY) {
			revert MaximumTokensReached();
		}

		ERC20 ggp = ERC20(address(this));
		Vault vault = Vault(getContractAddress("Vault"));

		_mint(address(this), amount);
		ggp.approve(address(vault), amount);
		vault.depositToken("RewardsPool", ggp, amount);
	}
}
