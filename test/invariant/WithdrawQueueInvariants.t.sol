// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../unit/utils/BaseTest.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {WithdrawQueueHandler} from "./WithdrawQueueHandler.sol";
import {IWAVAX} from "../../contracts/interface/IWAVAX.sol";
import {console2} from "forge-std/console2.sol";

contract WithdrawQueueInvariants is BaseTest {
	using FixedPointMathLib for uint256;

	WithdrawQueue private withdrawQueue;
	WithdrawQueueHandler private handler;

	address private alice;
	address private bob;
	address private charlie;

	uint48 private constant UNSTAKE_DELAY = 7 days;
	uint48 private constant EXPIRATION_DELAY = 14 days;

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);
		charlie = getActorWithTokens("charlie", MAX_AMT, MAX_AMT);

		// Deploy WithdrawQueue
		vm.startPrank(guardian);
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory initData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), UNSTAKE_DELAY, EXPIRATION_DELAY);

		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(withdrawQueueImpl), address(proxyAdmin), initData);
		withdrawQueue = WithdrawQueue(payable(address(proxy)));

		// Grant required roles
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(withdrawQueue));
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), charlie);
		withdrawQueue.grantRole(withdrawQueue.DEPOSITOR_ROLE(), charlie);

		// Set max pending requests limit for testing
		withdrawQueue.setMaxPendingRequestsLimit(25);

		// Set reserve ratio to 0% so all funds can be withdrawn for staking
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		vm.stopPrank();

		// Deploy and configure handler
		handler = new WithdrawQueueHandler(withdrawQueue, ggAVAX, IWAVAX(address(wavax)));
		handler.addActor(alice);
		handler.addActor(bob);
		handler.addActor(charlie);

		// Set handler as the target contract for invariant testing
		targetContract(address(handler));
	}

	// ============ FUND CONSERVATION INVARIANTS ============

	/// @notice I1: Total System Balance Conservation
	/// System must always have enough funds to cover all obligations
	function invariant_totalSystemBalanceConservation() external view {
		uint256 systemAssets = address(withdrawQueue).balance + ggAVAX.totalAssets();
		uint256 systemObligations = withdrawQueue.totalAllocatedFunds() + _calculateTotalPendingExpectedAssets();
		
		if (systemAssets < systemObligations) {
			console2.log("INVARIANT VIOLATION: Total System Balance Conservation");
			console2.log("System Assets:", systemAssets);
			console2.log("System Obligations:", systemObligations);
			console2.log("Deficit:", systemObligations - systemAssets);
		}
		
		assert(systemAssets >= systemObligations);
	}

	/// @notice I2: Allocated Funds Accounting
	/// Total allocated funds equals sum of individual request allocations
	function invariant_allocatedFundsAccounting() external view {
		uint256 totalAllocated = withdrawQueue.totalAllocatedFunds();
		uint256 sumOfFulfilledAllocations = _calculateSumOfFulfilledAllocations();
		
		if (totalAllocated != sumOfFulfilledAllocations) {
			console2.log("INVARIANT VIOLATION: Allocated Funds Accounting");
			console2.log("Total Allocated:", totalAllocated);
			console2.log("Sum of Fulfilled Allocations:", sumOfFulfilledAllocations);
		}
		
		assert(totalAllocated == sumOfFulfilledAllocations);
	}

	/// @notice I3: Share Conservation
	/// WithdrawQueue holds exactly the shares from all active requests
	function invariant_shareConservation() external view {
		uint256 withdrawQueueShares = ggAVAX.balanceOf(address(withdrawQueue));
		uint256 totalRequestShares = _calculateTotalRequestShares();
		
		if (withdrawQueueShares != totalRequestShares) {
			console2.log("INVARIANT VIOLATION: Share Conservation");
			console2.log("WithdrawQueue Shares:", withdrawQueueShares);
			console2.log("Total Request Shares:", totalRequestShares);
		}
		
		assert(withdrawQueueShares == totalRequestShares);
	}

	// ============ REQUEST STATE INVARIANTS ============

	/// @notice I4: Request State Exclusivity
	/// Every request is in exactly one state: pending, fulfilled, or non-existent
	function invariant_requestStateExclusivity() external view {
		for (uint256 i = 0; i < withdrawQueue.nextRequestId(); i++) {
			bool isPending = withdrawQueue.isRequestPending(i);
			bool isFulfilled = withdrawQueue.isFulfilledRequest(i);
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(i);
			bool exists = req.requester != address(0);
			
			if (isPending && isFulfilled) {
				console2.log("INVARIANT VIOLATION: Request State Exclusivity - Request is both pending and fulfilled");
				console2.log("Request ID:", i);
			}
			
			if ((isPending || isFulfilled) && !exists) {
				console2.log("INVARIANT VIOLATION: Request State Exclusivity - Request in set but doesn't exist");
				console2.log("Request ID:", i);
				console2.log("Is Pending:", isPending);
				console2.log("Is Fulfilled:", isFulfilled);
			}
			
			assert(!(isPending && isFulfilled));
			assert(!(isPending && !exists));
			assert(!(isFulfilled && !exists));
		}
	}

	/// @notice I5: Request Ownership Consistency
	/// User ownership mapping is consistent with request data
	function invariant_requestOwnershipConsistency() external view {
		address[] memory users = handler.getUsers();
		for (uint256 j = 0; j < users.length; j++) {
			address user = users[j];
			uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(user);
			for (uint256 k = 0; k < userRequests.length; k++) {
				WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(userRequests[k]);
				
				if (req.requester != user) {
					console2.log("INVARIANT VIOLATION: Request Ownership Consistency");
					console2.log("User:", user);
					console2.log("Request ID:", userRequests[k]);
					console2.log("Actual Requester:", req.requester);
				}
				
				assert(req.requester == user);
			}
		}
	}

	/// @notice I6: Queue Ordering Consistency (Corrected)
	/// All pending requests must be present in the queue
	function invariant_queueOrderingConsistency() external view {
		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		for (uint256 i = 0; i < pendingRequests.length; i++) {
			bool isPending = withdrawQueue.isRequestPending(pendingRequests[i]);
			
			if (!isPending) {
				console2.log("INVARIANT VIOLATION: Queue Ordering Consistency");
				console2.log("Request ID in pending array but not in pending set:", pendingRequests[i]);
			}
			
			assert(isPending);
		}
	}

	// ============ TEMPORAL INVARIANTS ============

	/// @notice I7: Time Progression
	/// Request timestamps are in logical order
	function invariant_timeProgression() external view {
		for (uint256 i = 0; i < withdrawQueue.nextRequestId(); i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(i);
			if (req.requester != address(0)) {
				
				if (req.requestTime > req.claimableTime) {
					console2.log("INVARIANT VIOLATION: Time Progression - requestTime > claimableTime");
					console2.log("Request ID:", i);
					console2.log("Request Time:", req.requestTime);
					console2.log("Claimable Time:", req.claimableTime);
				}
				
				if (req.claimableTime > req.expirationTime) {
					console2.log("INVARIANT VIOLATION: Time Progression - claimableTime > expirationTime");
					console2.log("Request ID:", i);
					console2.log("Claimable Time:", req.claimableTime);
					console2.log("Expiration Time:", req.expirationTime);
				}
				
				assert(req.requestTime <= req.claimableTime);
				assert(req.claimableTime <= req.expirationTime);
			}
		}
	}

	/// @notice I8: Delay Consistency
	/// Delays are applied consistently
	function invariant_delayConsistency() external view {
		uint48 unstakeDelay = withdrawQueue.unstakeDelay();
		uint48 expirationDelay = withdrawQueue.expirationDelay();
		
		for (uint256 i = 0; i < withdrawQueue.nextRequestId(); i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(i);
			if (req.requester != address(0)) {
				
				if (req.claimableTime != req.requestTime + unstakeDelay) {
					console2.log("INVARIANT VIOLATION: Delay Consistency - claimableTime incorrect");
					console2.log("Request ID:", i);
					console2.log("Expected claimableTime:", req.requestTime + unstakeDelay);
					console2.log("Actual claimableTime:", req.claimableTime);
				}
				
				if (req.expirationTime != req.claimableTime + expirationDelay) {
					console2.log("INVARIANT VIOLATION: Delay Consistency - expirationTime incorrect");
					console2.log("Request ID:", i);
					console2.log("Expected expirationTime:", req.claimableTime + expirationDelay);
					console2.log("Actual expirationTime:", req.expirationTime);
				}
				
				assert(req.claimableTime == req.requestTime + unstakeDelay);
				assert(req.expirationTime == req.claimableTime + expirationDelay);
			}
		}
	}

	// ============ ECONOMIC INVARIANTS ============

	/// @notice I9: Expected Assets Validity
	/// Expected assets are positive and reasonable
	function invariant_expectedAssetsValidity() external view {
		for (uint256 i = 0; i < withdrawQueue.nextRequestId(); i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(i);
			if (req.requester != address(0)) {
				
				if (req.expectedAssets == 0) {
					console2.log("INVARIANT VIOLATION: Expected Assets Validity - expectedAssets is zero");
					console2.log("Request ID:", i);
				}
				
				if (req.shares == 0) {
					console2.log("INVARIANT VIOLATION: Expected Assets Validity - shares is zero");
					console2.log("Request ID:", i);
				}
				
				assert(req.expectedAssets > 0);
				assert(req.shares > 0);
			}
		}
	}

	/// @notice I10: No Negative Balances
	/// System cannot have negative allocated funds or insufficient balance
	function invariant_noNegativeBalances() external view {
		uint256 totalAllocated = withdrawQueue.totalAllocatedFunds();
		uint256 contractBalance = address(withdrawQueue).balance;
		
		if (contractBalance < totalAllocated) {
			console2.log("INVARIANT VIOLATION: No Negative Balances - insufficient balance");
			console2.log("Contract Balance:", contractBalance);
			console2.log("Total Allocated:", totalAllocated);
		}
		
		assert(contractBalance >= totalAllocated);
	}

	// ============ FULFILLMENT INVARIANTS ============

	/// @notice I13: Fulfilled Request Completeness
	/// Fulfilled requests have funds allocated
	function invariant_fulfilledRequestCompleteness() external view {
		uint256[] memory fulfilledRequests = withdrawQueue.getAllFulfilledRequests();
		for (uint256 i = 0; i < fulfilledRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(fulfilledRequests[i]);
			
			if (req.allocatedFunds == 0) {
				console2.log("INVARIANT VIOLATION: Fulfilled Request Completeness");
				console2.log("Request ID:", fulfilledRequests[i]);
				console2.log("Allocated Funds:", req.allocatedFunds);
			}
			
			assert(req.allocatedFunds > 0);
		}
	}

	/// @notice I14: FIFO Processing
	/// Queue processes requests in order of request time
	function invariant_fifoProcessing() external view {
		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		for (uint256 i = 1; i < pendingRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory prevReq = withdrawQueue.getRequestInfo(pendingRequests[i-1]);
			WithdrawQueue.UnstakeRequest memory currReq = withdrawQueue.getRequestInfo(pendingRequests[i]);
			
			if (prevReq.requestTime > currReq.requestTime) {
				console2.log("INVARIANT VIOLATION: FIFO Processing");
				console2.log("Previous Request ID:", pendingRequests[i-1]);
				console2.log("Previous Request Time:", prevReq.requestTime);
				console2.log("Current Request ID:", pendingRequests[i]);
				console2.log("Current Request Time:", currReq.requestTime);
			}
			
			assert(prevReq.requestTime <= currReq.requestTime);
		}
	}

	// ============ HELPER FUNCTIONS ============

	/// @notice Calculate total expected assets for all pending requests
	function _calculateTotalPendingExpectedAssets() internal view returns (uint256 total) {
		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		for (uint256 i = 0; i < pendingRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(pendingRequests[i]);
			total += req.expectedAssets;
		}
	}

	/// @notice Calculate sum of all fulfilled request allocations
	function _calculateSumOfFulfilledAllocations() internal view returns (uint256 total) {
		uint256[] memory fulfilledRequests = withdrawQueue.getAllFulfilledRequests();
		for (uint256 i = 0; i < fulfilledRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(fulfilledRequests[i]);
			total += req.allocatedFunds;
		}
	}

	/// @notice Calculate total shares held by all active requests
	function _calculateTotalRequestShares() internal view returns (uint256 total) {
		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		uint256[] memory fulfilledRequests = withdrawQueue.getAllFulfilledRequests();
		
		for (uint256 i = 0; i < pendingRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(pendingRequests[i]);
			total += req.shares;
		}
		
		for (uint256 i = 0; i < fulfilledRequests.length; i++) {
			WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(fulfilledRequests[i]);
			total += req.shares;
		}
	}
}