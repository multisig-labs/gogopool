pragma solidity 0.8.17;

// SPDX-License-Identifier: GPL-3.0-only

import {Base} from "./Base.sol";
import {Vault} from "./Vault.sol";
import {Storage} from "./Storage.sol";
import {MultisigManager} from "./MultisigManager.sol";
import {DelegationNodeStatus} from "../types/DelegationNodeStatus.sol";
import {TokenggAVAX} from "./tokens/TokenggAVAX.sol";
import {TokenGGP} from "./tokens/TokenGGP.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "@rari-capital/solmate/src/mixins/ERC4626.sol";
import {MinipoolManager} from "./MinipoolManager.sol";
import {MinipoolStatus} from "../types/MinipoolStatus.sol";
import {IWithdrawer} from "../interface/IWithdrawer.sol";
import {Oracle} from "./Oracle.sol";
import {ProtocolDAO} from "./dao/ProtocolDAO.sol";

/*
	Data Storage Schema
	(nodeIDs are 20 bytes so can use Solidity 'address' as storage type for them)
	NodeIDs can be added, but never removed. If a nodeID submits another validation request,
	it will overwrite the old one (only allowed for specific statuses).
	delegationNode.count = Starts at 0 and counts up by 1 after a node is added.
	delegationNode.index<nodeID> = <index> of nodeID
	delegationNode.item<index>.nodeID = nodeID used as primary key (NOT the ascii "Node-blah" but the actual 20 bytes)
	delegationNode.item<index>.exists = boolean
	delegationNode.item<index>.duration = requested validation duration in seconds
	delegationNode.item<index>.owner = owner address
	delegationNode.item<index>.delegationFee = node operator specified fee
	delegationNode.item<index>.avaxAmt = avax deposited by node op (1000 avax for now)
	delegationNode.item<index>.ggpBondAmt = amt ggp deposited by node op for bond
*/

contract DelegationManager is Base, IWithdrawer {
	using SafeTransferLib for ERC20;
	using SafeTransferLib for address;
	ERC20 public immutable ggp;
	TokenggAVAX public immutable ggAVAX;
	uint256 public immutable MIN_DELEGATION_AMT = 25;
	uint256 public immutable MIN_STAKING_AMT = 2000 ether;
	uint256 public immutable MAX_NODE_AMT = 3000000 ether;

	struct DelegationNode {
		address nodeID;
		uint256 status;
		uint256 ggpBondAmt;
		uint256 requestedDelegationAmt;
		bool isMinipool;
		uint256 startTime;
		uint256 endTime;
		uint256 duration;
		uint256 avaxDelegatorRewardAmt;
		uint256 avaxValidatorRewardAmt;
		address owner;
		address multisigAddr;
		uint256 ggpSlashAmt;
	}

	/// @notice Delegation end time is incorrect.
	error InvalidEndTime();

	/// @notice The requested delegation amt is not within the limits
	error InvalidRequestedDelegationAmt();

	/// @notice Validation ggp bond amount must be atleast 10% of the min staked amount.
	error InvalidGGPBondAmt();

	/// @notice Validation node id already exists as a delegator?
	error InvalidNodeId();

	/// @notice Only the multisig assigned to a delegation node can interact with it
	error InvalidMultisigAddress();

	/// @notice A delegation node with this nodeid has not been registered
	error DelegationNodeNotFound();

	/// @notice Only node owners can withdraw node reward funds
	error OnlyOwnerCanWithdraw();

	/// @notice Invalid state transition
	error InvalidStateTransition();

	/// @notice Invalid duration
	error InvalidDuration();

	/// @notice Error sending the avax due to the user
	error ErrorSendingAvax();

	/// @notice Only node owners can cancel a delegation request before delegation starts
	error OnlyOwnerCanCancel();

	/// @notice The amount that is being returned is incorrect
	error InvalidEndingDelegationAmount();

	event DelegationNodeStatusChanged(address indexed nodeID, DelegationNodeStatus indexed status);

	constructor(
		Storage storageAddress,
		ERC20 ggp_,
		TokenggAVAX ggAVAX_
	) Base(storageAddress) {
		version = 1;
		ggp = ggp_;
		ggAVAX = ggAVAX_;
	}

	function registerNode(
		address nodeID,
		uint256 requestedDelegationAmt,
		uint256 ggpBondAmt,
		uint256 duration
	) external payable {
		//TODO: check that node registration is enabled in the protocol

		requireRequestedDelegationAmt(requestedDelegationAmt);
		requireGGPBondAmt(ggpBondAmt, requestedDelegationAmt);
		requireDuration(duration);

		// GGP will be stored in the Vault contract
		Vault vault = Vault(getContractAddress("Vault"));
		if (ggpBondAmt > 0) {
			// Move the GGP funds (assume allowance has been set properly beforehand by the front end)
			// TODO switch to error objects
			require(ggp.transferFrom(msg.sender, address(this), ggpBondAmt), "Could not transfer GGP to Delegation contract");
			require(ggp.approve(address(vault), ggpBondAmt), "Could not approve vault GGP deposit");
			// depositToken reverts if not successful
			vault.depositToken("DelegationManager", ggp, ggpBondAmt);
		}

		// getIndexOf returns -1 if node does not exist, so have to use signed type int256 here
		int256 index = getIndexOf(nodeID);
		if (index != -1) {
			// Existing nodeID
			requireValidStateTransition(index, DelegationNodeStatus.Prelaunch);
			// Zero out any left over data from a previous validation
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".startTime")), 0);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".endTime")), 0);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxUserAmt")), 0);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxDelegatorRewardAmt")), 0);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxValidatorRewardAmt")), 0);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpSlashAmt")), 0);
		} else {
			// new nodeID
			index = int256(getUint(keccak256("delegationNode.count")));
		}

		// Get a Rialto multisig to assign for this delegation node
		MultisigManager multisigManager = MultisigManager(getContractAddress("MultisigManager"));
		address multisigAddr = multisigManager.requireNextActiveMultisig();

		// Initialise node data
		setAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")), nodeID);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Prelaunch));
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".duration")), duration);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".requestedDelegationAmt")), requestedDelegationAmt);
		setAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".multisigAddr")), multisigAddr);
		setAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")), msg.sender);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")), ggpBondAmt);

		//should check if the node is validating through us or not.
		//call the minipool manager index to see if the nodeid is a minipool
		//maybe do some additional check here like that they are actively staking

		bool isMinipool = checkIfIsMinipool(nodeID);

		setBool(keccak256(abi.encodePacked("delegationNode.item", index, ".isMinipool")), isMinipool);

		// NOTE the index is actually 1 more than where it is actually stored. The 1 is subtracted in getIndexOf().
		// Copied from RP, probably so they can use "-1" to signify that something doesnt exist
		setUint(keccak256(abi.encodePacked("delegationNode.index", nodeID)), uint256(index + 1));
		addUint(keccak256("delegationNode.count"), 1);

		//should we return or emit back to FE?
		emit DelegationNodeStatusChanged(nodeID, DelegationNodeStatus.Prelaunch);
	}

	// TODO This forces a node into a specific state. Do we need this? For tests? For guardian?
	function updateDelegationNodeStatus(address nodeID, DelegationNodeStatus status) external {
		int256 index = getIndexOf(nodeID);
		if (index == -1) {
			revert DelegationNodeNotFound();
		}
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(status));
	}

	function checkIfIsMinipool(address nodeID) public view returns (bool) {
		MinipoolManager minipoolMgr = MinipoolManager(getContractAddress("MinipoolManager"));
		int256 minipoolIndex = minipoolMgr.getIndexOf(nodeID);

		if (minipoolIndex != -1) {
			MinipoolManager.Minipool memory mp;
			mp = minipoolMgr.getMinipool(minipoolIndex);
			// only if they are staking are they considered a minipool
			// Rialto will be checking that they are a valid validator
			if (mp.status == uint256(MinipoolStatus.Staking)) {
				return true;
			}
		}
		return false;
	}

	// Node op calls this to withdraw all funds they are due (ggp bond plus any rewards) at the end of the delegation period
	function withdrawRewardAndBondFunds(address nodeID) external {
		int256 index = getIndexOf(nodeID);
		if (index == -1) {
			revert DelegationNodeNotFound();
		}
		address owner = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		if (msg.sender != owner) {
			revert OnlyOwnerCanWithdraw();
		}
		requireValidStateTransition(index, DelegationNodeStatus.Finished);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Finished));

		Vault vault = Vault(getContractAddress("Vault"));
		uint256 ggpBondAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		uint256 ggpSlashAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpSlashAmt")));
		uint256 ggpAmtDue = ggpBondAmt - ggpSlashAmt;

		//node op gets their ggp bond back
		//All nodes will have their ggp bond and their ggp rewards given back
		if (ggpAmtDue > 0) {
			vault.withdrawToken(owner, ggp, ggpAmtDue);
		}

		//If it is a minipool node then we will have to give them their delegation fee
		// native validators should get their fees from the native avalanche system
		bool isMinipool = getBool(keccak256(abi.encodePacked("delegationNode.item", index, ".isMinipool")));
		uint256 avaxValidatorRewardAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxValidatorRewardAmt")));

		if (isMinipool && avaxValidatorRewardAmt > 0) {
			vault.withdrawAVAX(avaxValidatorRewardAmt);
			(bool sent, ) = payable(owner).call{value: avaxValidatorRewardAmt}("");
			if (!sent) {
				revert ErrorSendingAvax();
			}
		}
	}

	// Owner of a node can call this to cancel the delegation
	// Can only be called before Rialto picks it up. Delegation cannot be canceled once registered with avalanche
	// TODO Should DAO also be able to cancel? Or guardian? or Rialto?
	function cancelDelegation(address nodeID) external {
		int256 index = getIndexOf(nodeID);
		if (index == -1) {
			revert DelegationNodeNotFound();
		}
		address owner = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		if (msg.sender != owner) {
			revert OnlyOwnerCanCancel();
		}
		_cancelDelegationAndReturnFunds(nodeID, index);
	}

	function _cancelDelegationAndReturnFunds(address nodeID, int256 index) private {
		requireValidStateTransition(index, DelegationNodeStatus.Canceled);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Canceled));

		Vault vault = Vault(getContractAddress("Vault"));
		address owner = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		uint256 ggpBondAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));

		//the node op will get their ggp bond amt back
		if (ggpBondAmt > 0) {
			vault.withdrawToken(owner, ggp, ggpBondAmt);
		}

		emit DelegationNodeStatusChanged(nodeID, DelegationNodeStatus.Canceled);
	}

	function receiveWithdrawalAVAX() external payable {}

	//
	// RIALTO FUNCTIONS
	//

	// Rialto calls this to see if a claim would succeed. Does not change state.
	function canClaimAndInitiateDelegation(address nodeID) external view returns (bool) {
		// TODO Ugh is this OK for the front end if we revert instead of returning false?
		int256 index = requireValidMultisig(nodeID);
		requireValidStateTransition(index, DelegationNodeStatus.Launched);

		uint256 requestedDelegationAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".requestedDelegationAmt")));

		if (requestedDelegationAmt < MIN_DELEGATION_AMT) {
			revert InvalidRequestedDelegationAmt();
		}

		// Make sure we have enough liq staker funds
		if (requestedDelegationAmt > ggAVAX.amountAvailableForStaking()) {
			return false;
		}
		return true;
	}

	// If correct multisig calls this, xfer funds from vault to their address
	// For Rialto
	function claimAndInitiateDelegation(address nodeID) external {
		int256 index = requireValidMultisig(nodeID);
		requireValidStateTransition(index, DelegationNodeStatus.Launched);

		uint256 requestedDelegationAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".requestedDelegationAmt")));
		// TODO get max delegation amount from DAO setting? Or do we enforce that when we match funds?
		if (requestedDelegationAmt < MIN_DELEGATION_AMT) {
			revert InvalidRequestedDelegationAmt();
		}

		// Transfer the user funds to this contract
		ggAVAX.withdrawForStaking(requestedDelegationAmt);

		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Launched));
		emit DelegationNodeStatusChanged(nodeID, DelegationNodeStatus.Launched);
		msg.sender.safeTransferETH(requestedDelegationAmt);
	}

	// Rialto calls this after a successful delegation node launch
	// TODO Is it worth it to validate startTime? Or just depend on rialto to do the right thing?
	function recordDelegationStart(address nodeID, uint256 startTime) external {
		int256 index = requireValidMultisig(nodeID);

		requireValidStateTransition(index, DelegationNodeStatus.Delegated);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Delegated));
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".startTime")), startTime);
		emit DelegationNodeStatusChanged(nodeID, DelegationNodeStatus.Delegated);
	}

	// Rialto calls this when validation period ends
	// Rialto will also xfer back all avax rewards to vault
	// the delegation end transaction will show the amt of rewards to be paid to the delegator and the validator
	//TODO: figure this out more
	function recordDelegationEnd(
		address nodeID,
		uint256 endTime,
		uint256 avaxDelegatorRewardAmt,
		uint256 avaxValidatorRewardAmt
	) external payable {
		int256 index = requireValidMultisig(nodeID);
		requireValidStateTransition(index, DelegationNodeStatus.Withdrawable);

		uint256 startTime = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".startTime")));
		uint256 duration = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".duration")));
		if (endTime <= startTime || endTime > block.timestamp || (endTime - startTime) < duration) {
			revert InvalidEndTime();
		}

		//will need to return the users delegated amt and rewards back to the ggavax contract
		// the node op rewards if they are minipool node back to the vault
		uint256 requestedDelegationAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".requestedDelegationAmt")));
		bool isMinipool = getBool(keccak256(abi.encodePacked("delegationNode.item", index, ".isMinipool")));

		//if the node is a validator thorugh us then Rialto will send us the validator reward too. If it is not then the reward will go to the validators wallet automatically.
		if (isMinipool) {
			if (msg.value != requestedDelegationAmt + avaxDelegatorRewardAmt + avaxValidatorRewardAmt) {
				revert InvalidEndingDelegationAmount();
			}
		} else {
			if (msg.value != requestedDelegationAmt + avaxDelegatorRewardAmt) {
				revert InvalidEndingDelegationAmount();
			}
		}

		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")), uint256(DelegationNodeStatus.Withdrawable));
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".endTime")), endTime);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxDelegatorRewardAmt")), avaxDelegatorRewardAmt);
		setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxValidatorRewardAmt")), avaxValidatorRewardAmt);

		//if the total rewards is 0 then validation preiod failed. Slash ggp.
		//should it be that any of these are 0 or that the total is 0?
		//both should have a number given by the avalanche system even if we arent recieving the amt
		if ((avaxDelegatorRewardAmt + avaxValidatorRewardAmt) == 0) {
			uint256 expectedAmt = expectedRewardAmt(duration, requestedDelegationAmt);
			uint256 slashAmt = calculateSlashAmt(expectedAmt);
			setUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpSlashAmt")), slashAmt);
			ggAVAX.depositFromStaking{value: requestedDelegationAmt}(requestedDelegationAmt, 0);
			//the taking of their ggp happens in the withdraw function
		} else {
			// avalanche records the delegator and validator rewards in the delegation ending transaction.
			// liquid staking funds + rewards go to ggavax
			ggAVAX.depositFromStaking{value: requestedDelegationAmt + avaxDelegatorRewardAmt}(requestedDelegationAmt, avaxDelegatorRewardAmt);

			// Send the nodeOps rewards to vault so they can claim later
			if (isMinipool) {
				Vault vault = Vault(getContractAddress("Vault"));
				vault.depositAvax{value: avaxValidatorRewardAmt}();
			}
		}
		emit DelegationNodeStatusChanged(nodeID, DelegationNodeStatus.Withdrawable);
	}

	// taken from MinipoolMgr
	// Calculate how much GGP should be slashed given an expectedRewardAmt
	function calculateSlashAmt(uint256 avaxRewardAmt) public view returns (uint256) {
		Oracle oracle = Oracle(getContractAddress("Oracle"));
		(uint256 ggpPriceInAvax, ) = oracle.getGGPPriceInAVAX();
		return (1 ether * avaxRewardAmt) / ggpPriceInAvax;
	}

	// taken from MinipoolMgr
	// Given a duration and an avax amt, calculate how much avax should be earned via staking rewards
	function expectedRewardAmt(uint256 duration, uint256 avaxAmt) public view returns (uint256) {
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 rate = dao.getExpectedRewardRate();
		return (avaxAmt * ((duration * rate) / 365 days)) / 1 ether;
	}

	function getDelegationNode(int256 index) public view returns (DelegationNode memory dn) {
		dn.nodeID = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".nodeID")));
		dn.status = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".status")));
		dn.isMinipool = getBool(keccak256(abi.encodePacked("delegationNode.item", index, ".isMinipool")));
		dn.duration = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".duration")));
		dn.startTime = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".startTime")));
		dn.endTime = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".endTime")));
		dn.ggpBondAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpBondAmt")));
		dn.requestedDelegationAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".requestedDelegationAmt")));
		dn.avaxValidatorRewardAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxValidatorRewardAmt")));
		dn.avaxDelegatorRewardAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".avaxDelegatorRewardAmt")));
		dn.multisigAddr = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".multisigAddr")));
		dn.owner = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".owner")));
		dn.ggpSlashAmt = getUint(keccak256(abi.encodePacked("delegationNode.item", index, ".ggpSlashAmt")));
	}

	// The index of an item
	// Returns -1 if the value is not found
	function getIndexOf(address nodeID) public view returns (int256) {
		return int256(getUint(keccak256(abi.encodePacked("delegationNode.index", nodeID)))) - 1;
	}

	// Get delegation nodes in a certain status (limit=0 means no pagination)
	function getDelegationNodes(
		DelegationNodeStatus status,
		uint256 offset,
		uint256 limit
	) external view returns (DelegationNode[] memory nodes) {
		uint256 totalNodes = getUint(keccak256("delegationNode.count"));
		uint256 max = offset + limit;
		if (max > totalNodes || limit == 0) {
			max = totalNodes;
		}
		nodes = new DelegationNode[](max - offset);
		uint256 total = 0;
		for (uint256 i = offset; i < max; i++) {
			DelegationNode memory dn = getDelegationNode(int256(i));
			if (dn.status == uint256(status)) {
				nodes[total] = dn;
				total++;
			}
		}
		// Dirty hack to cut unused elements off end of return value (from RP)
		// solhint-disable-next-line no-inline-assembly
		assembly {
			mstore(nodes, total)
		}
	}

	function getDelegationNodesCount() external view returns (uint256) {
		return getUint(keccak256("delegationNode.count"));
	}

	// Get the number of nodes in each status.
	function getDelegationNodeCountPerStatus(uint256 offset, uint256 limit)
		external
		view
		returns (
			uint256 prelaunchCount,
			uint256 launchedCount,
			uint256 delegatedCount,
			uint256 withdrawableCount,
			uint256 finishedCount,
			uint256 canceledCount
		)
	{
		// Iterate over the requested node range
		uint256 totalNodes = getUint(keccak256("delegationNode.count"));
		uint256 max = offset + limit;
		if (max > totalNodes || limit == 0) {
			max = totalNodes;
		}
		for (uint256 i = offset; i < max; i++) {
			// Get the nodes at index i
			DelegationNode memory dn = getDelegationNode(int256(i));
			// Get the nodes's status, and update the appropriate counter
			if (dn.status == uint256(DelegationNodeStatus.Prelaunch)) {
				prelaunchCount++;
			} else if (dn.status == uint256(DelegationNodeStatus.Launched)) {
				launchedCount++;
			} else if (dn.status == uint256(DelegationNodeStatus.Delegated)) {
				delegatedCount++;
			} else if (dn.status == uint256(DelegationNodeStatus.Withdrawable)) {
				withdrawableCount++;
			} else if (dn.status == uint256(DelegationNodeStatus.Finished)) {
				finishedCount++;
			} else if (dn.status == uint256(DelegationNodeStatus.Canceled)) {
				canceledCount++;
			}
		}
	}

	function requireRequestedDelegationAmt(uint256 requestedDelegationAmt) private pure {
		if (requestedDelegationAmt < MIN_DELEGATION_AMT) {
			revert InvalidRequestedDelegationAmt();
		}
	}

	function requireGGPBondAmt(uint256 ggpBondAmt, uint256 requestedDelegationAmt) private pure {
		if (ggpBondAmt < ((requestedDelegationAmt * 10) / 100)) {
			revert InvalidGGPBondAmt();
		}
	}

	function requireDuration(uint256 duration) private view {
		// min delegation period is 2 weeks per avalanche rules
		// check in seconds
		ProtocolDAO dao = ProtocolDAO(getContractAddress("ProtocolDAO"));
		uint256 maxDuration = dao.getDelegationDurationLimit();
		if (duration < 1209600 || duration > maxDuration) {
			revert InvalidDuration();
		}
	}

	function requireValidMultisig(address nodeID) private view returns (int256) {
		int256 index = getIndexOf(nodeID);
		if (index == -1) {
			revert DelegationNodeNotFound();
		}

		address assignedMultisig = getAddress(keccak256(abi.encodePacked("delegationNode.item", index, ".multisigAddr")));
		if (msg.sender != assignedMultisig) {
			revert InvalidMultisigAddress();
		}
		return index;
	}

	// TODO how to handle error when Rialto is issuing validation tx? error status? or set to withdrawable with an error note or something?
	function requireValidStateTransition(int256 index, DelegationNodeStatus to) private view {
		bytes32 statusKey = keccak256(abi.encodePacked("delegationNode.item", index, ".status"));
		DelegationNodeStatus currentStatus = DelegationNodeStatus(getUint(statusKey));
		bool isValid;

		if (currentStatus == DelegationNodeStatus.Prelaunch) {
			isValid = (to == DelegationNodeStatus.Launched || to == DelegationNodeStatus.Canceled);
		} else if (currentStatus == DelegationNodeStatus.Launched) {
			isValid = (to == DelegationNodeStatus.Delegated || to == DelegationNodeStatus.Canceled);
		} else if (currentStatus == DelegationNodeStatus.Delegated) {
			isValid = (to == DelegationNodeStatus.Withdrawable);
		} else if (currentStatus == DelegationNodeStatus.Withdrawable) {
			isValid = (to == DelegationNodeStatus.Finished);
		} else if (currentStatus == DelegationNodeStatus.Finished || currentStatus == DelegationNodeStatus.Canceled) {
			// Once a node is finished or canceled, if they re-validate they go back to beginning state
			isValid = (to == DelegationNodeStatus.Prelaunch);
		} else {
			isValid = false;
		}

		if (!isValid) {
			revert InvalidStateTransition();
		}
	}
}
