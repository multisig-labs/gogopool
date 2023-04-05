// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {MultisigManager} from "./MultisigManager.sol";
import {ProtocolDAO} from "./ProtocolDAO.sol";
import {Storage} from "./Storage.sol";

/// @title Methods to pause the protocol
contract Ocyticus is Base {
	error NotAllowed();

	mapping(address => bool) public defenders;

	modifier onlyDefender() {
		if (!defenders[msg.sender]) {
			revert NotAllowed();
		}
		_;
	}

	constructor(Storage storageAddress) Base(storageAddress) {
		defenders[msg.sender] = true;
	}

	/// @notice Add an address to the defender list
	/// @param defender Address to add
	function addDefender(address defender) external onlyGuardian {
		defenders[defender] = true;
	}

	/// @notice Remove an address from the defender list
	/// @param defender address to remove
	function removeDefender(address defender) external onlyGuardian {
		delete defenders[defender];
	}

	/// @notice Restrict actions in important contracts
	function pauseEverything() external onlyDefender {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		dao.pauseContract("MinipoolManager");
		dao.pauseContract("RewardsPool");
		dao.pauseContract("Staking");
		dao.pauseContract("TokenggAVAX");
		disableAllMultisigs();
	}

	/// @notice Reestablish all contract's abilities
	/// @dev Multisigs will need to be enabled separately, we don't know which ones to enable
	function resumeEverything() external onlyDefender {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		dao.resumeContract("MinipoolManager");
		dao.resumeContract("RewardsPool");
		dao.resumeContract("Staking");
		dao.resumeContract("TokenggAVAX");
	}

	/// @notice Disable every multisig in the protocol
	function disableAllMultisigs() public onlyDefender {
		MultisigManager mm = MultisigManager(getContractAddress("MultisigManager"));
		uint256 count = mm.getCount();

		address addr;
		bool enabled;
		for (uint256 i = 0; i < count; i++) {
			(addr, enabled) = mm.getMultisig(i);
			if (enabled) {
				mm.disableMultisig(addr);
			}
		}
	}
}
