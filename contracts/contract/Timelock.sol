// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Timelock is Ownable {
	error Timelocked();
	error ExecutionFailed();
	error TransactionNotFound();

	event TransactionQueued(address indexed target, bytes32 indexed id);
	event TransactionAborted(address indexed target, bytes32 indexed id);
	event TransactionExecuted(address indexed target, bytes32 indexed id);

	struct TimedAction {
		address target;
		uint256 eta;
		bytes data;
	}

	uint256 public delay = 24 hours;
	mapping(bytes32 => TimedAction) public actions;

	function queueTransaction(address target, bytes memory data) external onlyOwner returns (bytes32) {
		uint256 eta = block.timestamp + delay;
		bytes32 id = keccak256(abi.encode(target, eta, data));
		emit TransactionQueued(target, id);
		actions[id] = TimedAction(target, eta, data);
		return id;
	}

	function abortTransaction(bytes32 id) external onlyOwner {
		TimedAction storage action = actions[id];
		emit TransactionAborted(action.target, id);
		delete actions[id];
	}

	function executeTransaction(bytes32 id) external {
		TimedAction storage action = actions[id];
		if (action.target == address(0)) {
			revert TransactionNotFound();
		}
		if (block.timestamp < action.eta) {
			revert Timelocked();
		}
		(bool success, ) = action.target.call(action.data);
		if (!success) {
			revert ExecutionFailed();
		}
		emit TransactionExecuted(action.target, id);
		delete actions[id];
	}
}
