// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Base} from "./Base.sol";
import {Storage} from "./Storage.sol";
import {Vault} from "./Vault.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";

/*
	Data Storage Schema
	multisig.count = Starts at 0 and counts up by 1 after an addr is added.

	multisig.index<address> = <index> + 1 of multisigAddress
	multisig.item<index>.address = C-chain address used as primary key
	multisig.item<index>.enabled = bool
*/

/// @title Multisig address creation and management for the protocol
contract MultisigManager is Base {
	uint256 public constant MULTISIG_LIMIT = 10;

	error MultisigAlreadyRegistered();
	error MultisigLimitReached();
	error MultisigMustBeEnabled();
	error MultisigNotFound();
	error NoEnabledMultisigFound();

	event DisabledMultisig(address indexed multisig, address actor);
	event EnabledMultisig(address indexed multisig, address actor);
	event GGPClaimed(address indexed multisig, uint256 amount);
	event RegisteredMultisig(address indexed multisig, address actor);

	/// @notice Verifies the multisig trying is enabled
	modifier onlyEnabledMultisig() {
		int256 multisigIndex = getIndexOf(msg.sender);

		if (multisigIndex == -1) {
			revert MultisigNotFound();
		}

		(, bool isEnabled) = getMultisig(uint256(multisigIndex));

		if (!isEnabled) {
			revert MultisigMustBeEnabled();
		}
		_;
	}

	constructor(Storage storageAddress) Base(storageAddress) {
		version = 1;
	}

	/// @notice Register a multisig. Defaults to disabled when first registered.
	/// @param addr Address of the multisig that is being registered
	function registerMultisig(address addr) external onlyGuardian {
		int256 multisigIndex = getIndexOf(addr);
		if (multisigIndex != -1) {
			revert MultisigAlreadyRegistered();
		}
		uint256 index = getUint(keccak256("multisig.count"));
		if (index >= MULTISIG_LIMIT) {
			revert MultisigLimitReached();
		}

		setAddress(keccak256(abi.encodePacked("multisig.item", index, ".address")), addr);

		// The index is stored 1 greater than the actual value. The 1 is subtracted in getIndexOf().
		setUint(keccak256(abi.encodePacked("multisig.index", addr)), index + 1);
		addUint(keccak256("multisig.count"), 1);
		emit RegisteredMultisig(addr, msg.sender);
	}

	/// @notice Enabling a registered multisig
	/// @param addr Address of the multisig that is being enabled
	function enableMultisig(address addr) external onlyGuardian {
		int256 multisigIndex = getIndexOf(addr);
		if (multisigIndex == -1) {
			revert MultisigNotFound();
		}

		setBool(keccak256(abi.encodePacked("multisig.item", multisigIndex, ".enabled")), true);
		emit EnabledMultisig(addr, msg.sender);
	}

	/// @notice Disabling a registered multisig
	/// @param addr Address of the multisig that is being disabled
	/// @dev this will prevent the multisig from completing validations. The minipool will need to be manually reassigned to a new multisig
	function disableMultisig(address addr) external guardianOrSpecificRegisteredContract("Ocyticus", msg.sender) {
		int256 multisigIndex = getIndexOf(addr);
		if (multisigIndex == -1) {
			revert MultisigNotFound();
		}

		setBool(keccak256(abi.encodePacked("multisig.item", multisigIndex, ".enabled")), false);
		emit DisabledMultisig(addr, msg.sender);
	}

	/// @notice Gets the next registered and enabled Multisig, revert if none found
	/// @return Address of the next active multisig
	/// @dev There will never be more than 10 total multisigs. If we grow beyond that we will redesign this contract.
	function requireNextActiveMultisig() external view returns (address) {
		uint256 total = getUint(keccak256("multisig.count"));
		address addr;
		bool enabled;
		for (uint256 i = 0; i < total; i++) {
			(addr, enabled) = getMultisig(i);
			if (enabled) {
				return addr;
			}
		}
		revert NoEnabledMultisigFound();
	}

	/// @notice The index of a multisig. Returns -1 if the multisig is not found
	/// @param addr Address of the multisig that is being searched for
	/// @return The index for the given multisig
	function getIndexOf(address addr) public view returns (int256) {
		return int256(getUint(keccak256(abi.encodePacked("multisig.index", addr)))) - 1;
	}

	/// @notice Get the total count of the multisigs in the protocol
	/// @return Count of all multisigs
	function getCount() public view returns (uint256) {
		return getUint(keccak256("multisig.count"));
	}

	/// @notice Gets the multisig information using the multisig's index
	/// @param index Index of the multisig
	/// @return addr and enabled. The address and the enabled status of the multisig
	function getMultisig(uint256 index) public view returns (address addr, bool enabled) {
		addr = getAddress(keccak256(abi.encodePacked("multisig.item", index, ".address")));
		enabled = (addr != address(0)) && getBool(keccak256(abi.encodePacked("multisig.item", index, ".enabled")));
	}

	/// @notice Allows an enabled multisig to withdraw the unclaimed GGP rewards
	function withdrawUnclaimedGGP() external onlyEnabledMultisig {
		Vault vault = Vault(getContractAddress("Vault"));
		TokenGGP ggp = TokenGGP(getContractAddress("TokenGGP"));
		uint256 totalGGP = vault.balanceOfToken("MultisigManager", ggp);

		emit GGPClaimed(msg.sender, totalGGP);

		vault.withdrawToken(msg.sender, ggp, totalGGP);
	}
}
