// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IWAVAX} from "../interface/IWAVAX.sol";
import {TokenggAVAX} from "./tokens/TokenggAVAX.sol";

import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract WithdrawQueue is Initializable, ReentrancyGuardUpgradeable, AccessControlUpgradeable {
	using SafeTransferLib for address;
	using SafeTransferLib for ERC20;
	using EnumerableSet for EnumerableSet.UintSet;
	using FixedPointMathLib for uint256;
	using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

	struct UnstakeRequest {
		address requester;
		uint256 shares;
		uint256 expectedAssets;
		uint48 requestTime;
		uint48 claimableTime;
		uint48 expirationTime;
		uint256 allocatedFunds;
	}

	bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

	uint256 public nextRequestId;
	uint256 public totalAllocatedFunds;

	EnumerableSet.UintSet private pendingRequests; // Requests waiting for fulfillment
	DoubleEndedQueue.Bytes32Deque pendingRequestsQueue; // Queue of requests to maintain ordering

	EnumerableSet.UintSet private fulfilledRequests; // Requests fulfilled, waiting for claim

	mapping(uint256 => UnstakeRequest) public requests;
	mapping(address => EnumerableSet.UintSet) private requestsByOwner;

	uint48 public unstakeDelay;
	uint48 public expirationDelay;
	TokenggAVAX public tokenggAVAX;

	uint256 private maxPendingRequestsLimit;

	event UnstakeRequested(uint256 indexed requestId, address indexed requester, uint256 shares, uint256 expectedAssets, uint48 claimableTime);
	event RequestFulfilled(bytes32 indexed source, uint256 indexed requestId, uint256 assets);
	event StakeDeposited(bytes32 indexed source, address indexed depositor, uint256 amount);
	event UnstakeClaimed(uint256 indexed requestId, address indexed claimer, uint256 amount);
	event ExpiredFundsReclaimed(uint256 indexed requestId, uint256 amount);
	event ExpiredSharesReturned(uint256 indexed requestId, address indexed requester, uint256 shares);
	event RequestCancelled(uint256 indexed requestId, address indexed requester, uint256 shares);
	event ExcessSharesBurnt(uint256 indexed requestId, uint256 sharesBurnt);
	event BatchExpiredFundsReclaimed(address indexed requester, uint256 totalAmount, uint256 requestsProcessed);
	event QueueCleaned(bytes32 indexed reason, uint256 indexed requestId);
	event ContractInitialized(address indexed tokenggAVAX, uint48 unstakeDelay, uint48 expirationDelay);

	error DirectAVAXDepositsNotSupported();
	error InsufficientAVAXBalance();
	error InsufficientTokenBalance();
	error NotYourRequest();
	error NoFundsAllocated();
	error RequestNotFulfilled();
	error RequestNotFound();
	error RequestExpired();
	error RequestNotExpired();
	error RequestNotPending();
	error RequestNotFulfilledOrPending();
	error TooEarlyToClaim();
	error TooLateToCancelRequest();
	error ZeroShares();
	error InvalidRedemptionAmount();
	error InvalidYieldAmounts();

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Initialize the WithdrawQueue contract with required parameters
	/// @param tokenggAVAXAddress The address of the stAVAX token contract
	/// @param _unstakeDelay How long users must wait before they can claim their AVAX
	/// @param _expirationDelay How long after claiming period before requests expire
	function initialize(address payable tokenggAVAXAddress, uint48 _unstakeDelay, uint48 _expirationDelay) public initializer {
		__ReentrancyGuard_init();
		__AccessControl_init();
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		tokenggAVAX = TokenggAVAX(payable(tokenggAVAXAddress));
		unstakeDelay = _unstakeDelay;
		expirationDelay = _expirationDelay;

		emit ContractInitialized(tokenggAVAXAddress, _unstakeDelay, _expirationDelay);
	}

	/// @notice Accept AVAX deposits from external sources
	/// @dev Automatically deposits the AVAX as yield to fulfill pending unstake requests
	receive() external payable {
		if (msg.sender != address(tokenggAVAX) && msg.sender != address(tokenggAVAX.asset())) {
			revert DirectAVAXDepositsNotSupported();
		}
	}

	/// @notice Request to unstake your stAVAX tokens
	/// @param shares How many stAVAX tokens you want to unstake
	/// @return requestId Your unique request ID for tracking
	function requestUnstake(uint256 shares) external returns (uint256 requestId) {
		if (shares == 0) {
			revert ZeroShares();
		}

		if (tokenggAVAX.balanceOf(msg.sender) < shares) {
			revert InsufficientTokenBalance();
		}

		uint256 expectedAssets = tokenggAVAX.convertToAssets(shares);

		ERC20(address(tokenggAVAX)).safeTransferFrom(msg.sender, address(this), shares);

		requestId = nextRequestId++;
		uint48 currentTime = uint48(block.timestamp);

		requests[requestId] = UnstakeRequest({
			requester: msg.sender,
			shares: shares,
			expectedAssets: expectedAssets,
			requestTime: currentTime,
			claimableTime: currentTime + unstakeDelay,
			expirationTime: currentTime + unstakeDelay + expirationDelay,
			allocatedFunds: 0
		});

		requestsByOwner[msg.sender].add(requestId);
		pendingRequests.add(requestId);
		pendingRequestsQueue.pushBack(bytes32(requestId));

		emit UnstakeRequested(requestId, msg.sender, shares, expectedAssets, currentTime + unstakeDelay);
	}

	function requestUnstakeOnBehalfOf(uint256 shares, address requester) external returns (uint256 requestId) {
		if (shares == 0) {
			revert ZeroShares();
		}

		// We want to transfer shares from caller (NOT requester) to this contract
		if (tokenggAVAX.balanceOf(msg.sender) < shares) {
			revert InsufficientTokenBalance();
		}

		uint256 expectedAssets = tokenggAVAX.convertToAssets(shares);

		// We want to transfer shares from caller (NOT requester) to this contract
		ERC20(address(tokenggAVAX)).safeTransferFrom(msg.sender, address(this), shares);

		requestId = nextRequestId++;
		uint48 currentTime = uint48(block.timestamp);

		requests[requestId] = UnstakeRequest({
			requester: requester,
			shares: shares,
			expectedAssets: expectedAssets,
			requestTime: currentTime,
			claimableTime: currentTime + unstakeDelay,
			expirationTime: currentTime + unstakeDelay + expirationDelay,
			allocatedFunds: 0
		});

		requestsByOwner[requester].add(requestId);
		pendingRequests.add(requestId);
		pendingRequestsQueue.pushBack(bytes32(requestId));

		emit UnstakeRequested(requestId, requester, shares, expectedAssets, currentTime + unstakeDelay);
	}

	/// @notice Claim your AVAX after your unstake request is fulfilled
	/// @param requestId The ID of your unstake request
	function claimUnstake(uint256 requestId) external {
		UnstakeRequest storage req = requests[requestId];
		if (req.requester == address(0)) {
			revert RequestNotFound();
		}

		if (req.requester != msg.sender) {
			revert NotYourRequest();
		}

		if (!fulfilledRequests.contains(requestId)) {
			revert RequestNotFulfilled();
		}

		if (block.timestamp < req.claimableTime) {
			revert TooEarlyToClaim();
		}

		if (block.timestamp >= req.expirationTime) {
			revert RequestExpired();
		}

		if (req.allocatedFunds == 0) {
			revert NoFundsAllocated();
		}

		uint256 amount = req.allocatedFunds;

		// Clean up all request data
		req.allocatedFunds = 0;
		totalAllocatedFunds -= amount;
		fulfilledRequests.remove(requestId);

		requestsByOwner[msg.sender].remove(requestId);
		delete requests[requestId];

		if (address(this).balance < amount) {
			revert InsufficientAVAXBalance();
		}

		emit UnstakeClaimed(requestId, msg.sender, amount);

		msg.sender.safeTransferETH(amount);
	}

	/// @notice Cancel an unstake request before it becomes claimable and get stAVAX back
	/// @param requestId The ID of the request to cancel
	function cancelRequest(uint256 requestId) public nonReentrant {
		UnstakeRequest storage req = requests[requestId];
		if (req.requester == address(0)) {
			revert RequestNotFound();
		}

		if (req.requester != msg.sender) {
			revert NotYourRequest();
		}

		uint256 sharesToReturn;

		// Handle pending requests
		if (pendingRequests.contains(requestId)) {
			// For pending requests, calculate how much stAVAX to return based on current rate
			// User gets less stAVAX back if the exchange rate has improved
			sharesToReturn = tokenggAVAX.convertToShares(req.expectedAssets);

			// Store original shares before deletion
			uint256 originalShares = req.shares;

			// Remove from pending queue
			pendingRequests.remove(requestId);

			// Clean up request data
			requestsByOwner[msg.sender].remove(requestId);
			delete requests[requestId];

			// If user gets back less shares than originally provided,
			// burn the difference to maintain protocol balance
			if (originalShares > sharesToReturn) {
				uint256 sharesToBurn = originalShares - sharesToReturn;
				// Burn the excess shares by sending to dead address
				tokenggAVAX.donateYield(sharesToBurn, bytes32("WITHDRAW_QUEUE"));
				emit ExcessSharesBurnt(requestId, sharesToBurn);
			}

			// Emit cancellation event
			emit RequestCancelled(requestId, msg.sender, sharesToReturn);
		}
		// Handle fulfilled requests - but only before they become claimable
		else if (fulfilledRequests.contains(requestId)) {
			// Check if request has become claimable - if so, cannot cancel
			if (block.timestamp >= req.claimableTime) {
				revert TooLateToCancelRequest();
			}

			// For fulfilled requests, use allocated AVAX to buy back stAVAX
			uint256 avaxAmount = req.allocatedFunds;

			// Update accounting BEFORE external call (checks-effects-interactions)
			req.allocatedFunds = 0;
			totalAllocatedFunds -= avaxAmount;

			// Remove from fulfilled queue BEFORE external call
			fulfilledRequests.remove(requestId);

			// Store necessary data before cleanup
			address requester = req.requester;

			// Clean up request data BEFORE external call
			requestsByOwner[msg.sender].remove(requestId);
			delete requests[requestId];

			// Deposit AVAX back to get stAVAX shares (external call)
			sharesToReturn = tokenggAVAX.depositAVAX{value: avaxAmount}();

			// Emit event after we know sharesToReturn
			emit RequestCancelled(requestId, requester, sharesToReturn);
		} else {
			revert RequestNotPending();
		}

		// Transfer shares to user
		ERC20(address(tokenggAVAX)).safeTransfer(msg.sender, sharesToReturn);
	}

	/// @notice Cancel multiple requests for a user (both pending and fulfilled)
	/// @param maxRequests Maximum number of requests to cancel
	/// @return cancelledCount Number of requests that were cancelled
	function cancelRequests(uint256 maxRequests) external returns (uint256 cancelledCount) {
		uint256[] memory requestIds = requestsByOwner[msg.sender].values();

		if (maxRequests == 0) {
			maxRequests = requestIds.length;
		}

		for (uint256 i = 0; i < requestIds.length && cancelledCount < maxRequests; i++) {
			// Check if request is either pending or fulfilled
			if (pendingRequests.contains(requestIds[i]) || fulfilledRequests.contains(requestIds[i])) {
				cancelRequest(requestIds[i]);
				cancelledCount++;
			}
		}
	}

	/// @notice Deposit AVAX to help fulfill pending unstake requests
	/// @dev Uses the deposited AVAX to fulfill waiting requests, sends excess back to stAVAX
	function depositFromStaking(uint256 baseAmt, uint256 rewardAmt, bytes32 source) public payable onlyRole(DEPOSITOR_ROLE) {
		// Validate that the sum of baseAmt and rewardAmt equals msg.value
		if (baseAmt + rewardAmt != msg.value) {
			revert InvalidYieldAmounts();
		}

		emit StakeDeposited(source, msg.sender, msg.value);

		// Record reward to base ratio for fractional deposits
		uint256 rewardToBaseRatio;
		if (rewardAmt == 0) {
			rewardToBaseRatio = 0;
		} else {
			rewardToBaseRatio = rewardAmt.divWadDown(baseAmt + rewardAmt);
		}

		uint256 excessAVAX = 0;
		uint256 ggAVAXAvailableAssets = 0;

		// Process pending requests from front of queue, removing fulfilled requests and then leave the money in the contract if still more to process
		uint256 requestsProcessed = 0;
		while (pendingRequests.length() > 0 && requestsProcessed < maxPendingRequestsLimit) {
			uint256 requestId = uint256(pendingRequestsQueue.front());
			if (!pendingRequests.contains(requestId)) {
				pendingRequestsQueue.popFront();
				emit QueueCleaned(bytes32("REQUEST_NOT_IN_PENDING_SET"), requestId);
				continue;
			}

			UnstakeRequest storage req = requests[requestId];

			ggAVAXAvailableAssets = _getGGAVAXAvailableAssets();

			uint256 withdrawQueueAvailableAssets = address(this).balance > totalAllocatedFunds ? address(this).balance - totalAllocatedFunds : 0;
			if (withdrawQueueAvailableAssets + ggAVAXAvailableAssets < req.expectedAssets) {
				return;
			}

			// Determine if we need to deposit additional assets to ggAVAX
			if (ggAVAXAvailableAssets < req.expectedAssets) {
				uint256 amountToDeposit = req.expectedAssets - ggAVAXAvailableAssets;
				uint256 proRatedRewardAmt = amountToDeposit.mulWadDown(rewardToBaseRatio);
				uint256 proRatedBaseAmt = amountToDeposit - proRatedRewardAmt;

				if (baseAmt > 0) {
					baseAmt -= proRatedBaseAmt;
				}
				if (rewardAmt > 0) {
					rewardAmt -= proRatedRewardAmt;
				}

				_depositToGGAVAX(proRatedBaseAmt, proRatedRewardAmt, source, amountToDeposit);
			}

			// Try to redeem all shares from initial request
			// if there's any additional avax returned from an improved exchange rate
			// send it back to TokenggAVAX for continued yield generation
			try tokenggAVAX.redeemAVAX(req.shares) returns (uint256 assetsReturned) {
				// verify that the amount returned is the expected amount
				if (assetsReturned < req.expectedAssets) {
					revert InvalidRedemptionAmount();
				}

				req.allocatedFunds = req.expectedAssets;
				totalAllocatedFunds += req.allocatedFunds;

				pendingRequests.remove(requestId);
				pendingRequestsQueue.popFront();
				fulfilledRequests.add(requestId);
				emit RequestFulfilled(source, requestId, req.expectedAssets);

				// record accumulated excess to send back later
				if (assetsReturned > req.expectedAssets) {
					excessAVAX += assetsReturned - req.expectedAssets;
				}
				requestsProcessed++;
			} catch {
				// stAVAX doesn't have enough liquidity for this request, stop processing
				// Leave this request in the pending set for next time
				break;
			}
		}

		if (pendingRequests.length() != 0) {
			return;
		}

		if (excessAVAX > 0) {
			tokenggAVAX.depositYield{value: excessAVAX}(bytes32("WITHDRAW_QUEUE"));
		}

		// Handle any remaining amounts after processing all pending requests
		if (baseAmt > 0 || rewardAmt > 0) {
			uint256 remainingTotal = baseAmt + rewardAmt;
			_depositToGGAVAX(baseAmt, rewardAmt, source, remainingTotal);
		}

		// Handle any unallocated AVAX remaining in the contract after processing all pending requests
		uint256 unallocatedAVAX = address(this).balance - totalAllocatedFunds;
		if (unallocatedAVAX > 0) {
			_depositToGGAVAX(0, unallocatedAVAX, bytes32("WITHDRAW_QUEUE"), unallocatedAVAX);
		}
	}

	/// @notice Reclaim AVAX from a single expired request and return ggAVAX to the user
	/// @param requestId The ID of the expired request to reclaim
	/// @return reclaimedAmount Amount of AVAX reclaimed from this request
	function reclaimExpiredRequest(uint256 requestId) public returns (uint256 reclaimedAmount) {
		UnstakeRequest storage req = requests[requestId];

		// Check state first - if not in either set, it's either claimed or never existed
		// Handle fulfilled requests
		if (fulfilledRequests.contains(requestId)) {
			if (req.requester == address(0)) {
				revert RequestNotFound();
			}

			if (block.timestamp < req.expirationTime) {
				revert RequestNotExpired();
			}

			address requester = req.requester;

			if (req.allocatedFunds == 0) {
				revert NoFundsAllocated();
			}

			reclaimedAmount = req.allocatedFunds;

			// Clean up all request data
			req.allocatedFunds = 0;
			totalAllocatedFunds -= reclaimedAmount;
			fulfilledRequests.remove(requestId);
			requestsByOwner[requester].remove(requestId);
			delete requests[requestId];

			// Convert AVAX back to ggAVAX shares and return to user
			if (address(this).balance < reclaimedAmount) {
				revert InsufficientAVAXBalance();
			}

			emit ExpiredFundsReclaimed(requestId, reclaimedAmount);

			uint256 shares = tokenggAVAX.depositAVAX{value: reclaimedAmount}();

			emit ExpiredSharesReturned(requestId, requester, shares);

			ERC20(address(tokenggAVAX)).safeTransfer(requester, shares);
		}
		// Handle pending requests
		else if (pendingRequests.contains(requestId)) {
			if (req.requester == address(0)) {
				revert RequestNotFound();
			}

			if (block.timestamp < req.expirationTime) {
				revert RequestNotExpired();
			}

			address requester = req.requester;

			// For pending requests, give them back the original shares

			// Save values before deleting the request
			uint256 sharesToReturn = req.shares;
			uint256 expectedAssets = req.expectedAssets;

			// Clean up request data
			pendingRequests.remove(requestId);
			requestsByOwner[requester].remove(requestId);
			delete requests[requestId];

			// For pending requests, reclaimedAmount represents the expected assets value
			reclaimedAmount = expectedAssets;

			emit ExpiredFundsReclaimed(requestId, reclaimedAmount);
			emit ExpiredSharesReturned(requestId, requester, sharesToReturn);

			ERC20(address(tokenggAVAX)).safeTransfer(requester, sharesToReturn);
		} else {
			// If request is not in either set, check if it has ever existed
			if (requestId >= nextRequestId) {
				revert RequestNotFound();
			}
			revert RequestNotFulfilledOrPending();
		}
	}

	/// @notice Reclaim AVAX from old requests that were never claimed
	/// @param maxRequests Maximum number of old requests to process in one transaction
	/// @return reclaimedAmount Total AVAX reclaimed and returned to the protocol
	/// @return processedCount Number of expired requests that were processed
	function reclaimExpiredFunds(uint256 maxRequests) external returns (uint256 reclaimedAmount, uint256 processedCount) {
		uint256 currentTime = block.timestamp;
		processedCount = 0;
		reclaimedAmount = 0;

		// Calculate total requests to process if maxRequests is 0
		if (maxRequests == 0) {
			maxRequests = fulfilledRequests.length() + pendingRequests.length();
		}

		// Process fulfilled requests first to find expired ones
		uint256 fulfilledCount = fulfilledRequests.length();
		uint256 i = 0;

		while (i < fulfilledCount && processedCount < maxRequests) {
			uint256 requestId = fulfilledRequests.at(i);
			UnstakeRequest storage req = requests[requestId];

			// Check if request has expired (past expirationTime)
			if (currentTime >= req.expirationTime) {
				// Use the single request method to reclaim this expired request
				uint256 amount = reclaimExpiredRequest(requestId);

				reclaimedAmount += amount;
				processedCount++;

				// Note: Don't increment i since we removed an element
				fulfilledCount = fulfilledRequests.length();
			} else {
				i++;
			}
		}

		// Process pending requests to find expired ones
		uint256 pendingCount = pendingRequests.length();
		i = 0;

		while (i < pendingCount && processedCount < maxRequests) {
			uint256 requestId = pendingRequests.at(i);
			UnstakeRequest storage req = requests[requestId];

			// Check if request has expired (past expirationTime)
			if (currentTime >= req.expirationTime) {
				// Use the single request method to reclaim this expired request
				uint256 amount = reclaimExpiredRequest(requestId);

				reclaimedAmount += amount;
				processedCount++;

				// Note: Don't increment i since we removed an element
				pendingCount = pendingRequests.length();
			} else {
				i++;
			}
		}

		// Emit batch summary event
		if (processedCount > 0) {
			emit BatchExpiredFundsReclaimed(msg.sender, reclaimedAmount, processedCount);
		}
	}

	/// @notice Get the current max pending requests limit
	/// @return The current max pending requests limit
	function getMaxPendingRequestsLimit() external view returns (uint256) {
		return maxPendingRequestsLimit;
	}

	/// @notice Set the max pending requests limit (admin only)
	/// @param newLimit The new max pending requests limit
	function setMaxPendingRequestsLimit(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
		maxPendingRequestsLimit = newLimit;
	}

	/// @notice Set the unstake delay (admin only)
	/// @param newUnstakeDelay The new unstake delay in seconds
	function setUnstakeDelay(uint48 newUnstakeDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
		unstakeDelay = newUnstakeDelay;
	}

	/// @notice Set the expiration delay (admin only)
	/// @param newExpirationDelay The new expiration delay in seconds
	function setExpirationDelay(uint48 newExpirationDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
		expirationDelay = newExpirationDelay;
	}

	/// @notice Get detailed information about an unstake request
	/// @param requestId The ID of the request to look up
	/// @return The complete request details including status and amounts
	function getRequestInfo(uint256 requestId) external view returns (UnstakeRequest memory) {
		return requests[requestId];
	}

	/// @notice Check if an unstake request is ready to be claimed
	/// @param requestId The ID of the request to check
	/// @return True if the request can be claimed now, false otherwise
	function canClaimRequest(uint256 requestId) external view returns (bool) {
		if (!fulfilledRequests.contains(requestId)) {
			return false;
		}
		UnstakeRequest storage req = requests[requestId];
		return block.timestamp >= req.claimableTime && block.timestamp < req.expirationTime;
	}

	/// @notice Get all unstake request IDs for a specific user
	/// @param user The address of the user
	/// @return Array of all request IDs belonging to that user
	function getRequestsByOwner(address user) external view returns (uint256[] memory) {
		return requestsByOwner[user].values();
	}

	/// @notice Get how many unstake requests are still waiting to be fulfilled
	/// @return Number of requests waiting for AVAX to become available
	function getPendingRequestsCount() external view returns (uint256) {
		return pendingRequests.length();
	}

	/// @notice Get the AVAX amount needed to fulfill the next waiting request
	/// @return Amount of AVAX needed for the oldest pending request
	function getNextPendingRequestAmount() external returns (uint256) {
		if (pendingRequests.length() == 0) {
			return 0;
		}
		uint256 requestId = uint256(pendingRequestsQueue.front());
		if (!pendingRequests.contains(requestId)) {
			pendingRequestsQueue.popFront();
			emit QueueCleaned(bytes32("REQUEST_NOT_IN_PENDING_SET_QUERY"), requestId);
			return 0;
		}
		return requests[requestId].expectedAssets;
	}

	/// @notice Get all request IDs that are waiting to be fulfilled
	/// @return Array of request IDs still waiting for AVAX
	function getAllPendingRequests() external view returns (uint256[] memory) {
		return pendingRequests.values();
	}

	/// @notice Check if a specific request is still waiting to be fulfilled
	/// @param requestId The request ID to check
	/// @return True if the request is still waiting, false otherwise
	function isRequestPending(uint256 requestId) external view returns (bool) {
		return pendingRequests.contains(requestId);
	}

	/// @notice Get how many requests have been fulfilled but not yet claimed
	/// @return Number of requests ready to be claimed by users
	function getFulfilledRequestsCount() external view returns (uint256) {
		return fulfilledRequests.length();
	}

	/// @notice Get all request IDs that have been fulfilled and are ready to claim
	/// @return Array of request IDs that users can claim
	function getAllFulfilledRequests() external view returns (uint256[] memory) {
		return fulfilledRequests.values();
	}

	/// @notice Check if a specific request has been fulfilled and is ready to claim
	/// @param requestId The request ID to check
	/// @return True if the request is fulfilled and claimable, false otherwise
	function isFulfilledRequest(uint256 requestId) external view returns (bool) {
		return fulfilledRequests.contains(requestId);
	}

	/// @notice Get how many old requests have expired and can be reclaimed
	/// @return count Number of requests (both pending and fulfilled) that have expired and can be reclaimed
	function getExpiredRequestsCount() external view returns (uint256 count) {
		uint256 currentTime = block.timestamp;

		// Count expired fulfilled requests
		uint256 fulfilledCount = fulfilledRequests.length();
		for (uint256 i = 0; i < fulfilledCount; i++) {
			uint256 requestId = fulfilledRequests.at(i);
			UnstakeRequest storage req = requests[requestId];

			if (currentTime >= req.expirationTime) {
				count++;
			}
		}

		// Count expired pending requests
		uint256 pendingCount = pendingRequests.length();
		for (uint256 i = 0; i < pendingCount; i++) {
			uint256 requestId = pendingRequests.at(i);
			UnstakeRequest storage req = requests[requestId];

			if (currentTime >= req.expirationTime) {
				count++;
			}
		}
	}

	/// @notice Deposit AVAX to ggAVAX
	/// @param baseAmt The amount of base assets to deposit
	/// @param rewardAmt The amount of reward assets to deposit
	/// @param source The source of the deposit
	/// @param value The amount of AVAX to deposit
	function _depositToGGAVAX(uint256 baseAmt, uint256 rewardAmt, bytes32 source, uint256 value) internal {
		tokenggAVAX.depositFromStaking{value: value}(baseAmt, rewardAmt, source);
	}

	/// @notice Get the amount of AVAX available in ggAVAX for redemption
	/// @return The amount of AVAX available in ggAVAX for redemption
	function _getGGAVAXAvailableAssets() internal view returns (uint256) {
		uint256 totalAssets = tokenggAVAX.totalAssets();
		uint256 stakingTotal = tokenggAVAX.stakingTotalAssets();
		return totalAssets > stakingTotal ? totalAssets - stakingTotal : 0;
	}

	/// @dev Storage gap for future upgrades
	uint256[50] private __gap;
}
