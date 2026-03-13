// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {IWAVAX} from "../interface/IWAVAX.sol";
import {TokenggAVAX} from "./tokens/TokenggAVAX.sol";
import {Storage} from "./Storage.sol";

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
	bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

	uint48 public constant MIN_EXPIRATION_DELAY = 3 days;

	uint256 public nextRequestId;
	uint256 public totalAllocatedFunds;

	EnumerableSet.UintSet private pendingRequests; // Requests waiting for fulfillment
	DoubleEndedQueue.Bytes32Deque pendingRequestsQueue; // Queue of requests to maintain ordering

	EnumerableSet.UintSet private fulfilledRequests; // Requests fulfilled, waiting for claim

	mapping(uint256 => UnstakeRequest) public requests;
	mapping(address => EnumerableSet.UintSet) private requestsByOwner;

	uint48 public unstakeDelay;
	uint48 public maxExpirationDelay;
	TokenggAVAX public tokenggAVAX;
	Storage public store;

	uint256 private maxRequestsPerStakingDeposit;
	uint256 private minUnstakeOnBehalfOfAmt;

	bool public paused;

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
	event InsufficientLiquidity(uint256 availableAssets, uint256 requiredAssets);
	event PendingRequestsNotProcesses(uint256 pendingRequests);
	event ContractPaused(address indexed pauser);
	event ContractUnpaused(address indexed unpauser);
	event DepositedFromStaking(uint256 baseAmt, uint256 rewardAmt, bytes32 source, uint256 value);
	event YieldDeposited(uint256 value);

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
	error TooLateToCancelRequest();
	error ZeroShares();
	error InvalidRedemptionAmount();
	error InvalidYieldAmounts();
	error MinimumSharesNotMet();
	error InvalidExpirationDelay();
	error ContractPausedError();

	/// @dev Verify contract is not paused
	modifier whenNotPaused() {
		if (paused) {
			revert ContractPausedError();
		}
		_;
	}

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	/// @notice Initialize the WithdrawQueue contract with required parameters
	/// @param tokenggAVAXAddress The address of the stAVAX token contract
	/// @param storageAddress The address of the storage contract
	/// @param _unstakeDelay How long (seconds) users must wait before they can claim their AVAX
	/// @param _maxExpirationDelay How long (seconds) after claiming period before requests expire
	function initialize(
		address payable tokenggAVAXAddress,
		address storageAddress,
		uint48 _unstakeDelay,
		uint48 _maxExpirationDelay
	) public initializer {
		__ReentrancyGuard_init();
		__AccessControl_init();
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

		tokenggAVAX = TokenggAVAX(payable(tokenggAVAXAddress));
		unstakeDelay = _unstakeDelay;
		maxExpirationDelay = _maxExpirationDelay;
		store = Storage(storageAddress);

		maxRequestsPerStakingDeposit = 50;
		minUnstakeOnBehalfOfAmt = 0.01 ether;
		maxExpirationDelay = _maxExpirationDelay;

		emit ContractInitialized(tokenggAVAXAddress, _unstakeDelay, _maxExpirationDelay);
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
	/// @param expirationDelay How long after claiming period before requests expire
	/// @return requestId Your unique request ID for tracking
	function requestUnstake(uint256 shares, uint48 expirationDelay) external whenNotPaused returns (uint256 requestId) {
		return _requestUnstake(shares, msg.sender, msg.sender, expirationDelay);
	}

	/// @notice Request to unstake stAVAX tokens on behalf of another user
	/// @param shares How many stAVAX tokens you want to unstake
	/// @param expirationDelay How long after claiming period before requests expire
	/// @return requestId Your unique request ID for tracking
	function requestUnstakeOnBehalfOf(uint256 shares, address requester, uint48 expirationDelay) external whenNotPaused returns (uint256 requestId) {
		if (shares < minUnstakeOnBehalfOfAmt) {
			revert MinimumSharesNotMet();
		}
		return _requestUnstake(shares, msg.sender, requester, expirationDelay);
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

		if (block.timestamp >= req.expirationTime) {
			revert RequestExpired();
		}

		if (req.allocatedFunds == 0) {
			revert NoFundsAllocated();
		}

		uint256 amount = req.allocatedFunds;

		// Clean up all request data
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
			totalAllocatedFunds -= avaxAmount;

			// Remove from fulfilled queue BEFORE external call
			fulfilledRequests.remove(requestId);

			// Clean up request data BEFORE external call
			requestsByOwner[msg.sender].remove(requestId);
			delete requests[requestId];

			// Deposit AVAX back to get stAVAX shares (external call)
			sharesToReturn = tokenggAVAX.depositAVAX{value: avaxAmount}();

			// Emit event after we know sharesToReturn
			emit RequestCancelled(requestId, msg.sender, sharesToReturn);
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
	/// @dev Deposits all AVAX to ggAVAX first for safety, then withdraws as needed to fulfill requests
	function depositFromStaking(uint256 baseAmt, uint256 rewardAmt, bytes32 source) external payable onlyRole(DEPOSITOR_ROLE) {
		// Validate that the sum of baseAmt and rewardAmt equals msg.value
		if (baseAmt + rewardAmt != msg.value) {
			revert InvalidYieldAmounts();
		}

		// Immediately deposit all AVAX to ggAVAX for safety - ensures funds are always deposited correctly
		if (msg.value > 0) {
			_depositToGGAVAX(baseAmt, rewardAmt, source, msg.value);
			emit StakeDeposited(source, msg.sender, msg.value);
		}

		uint256 excessAVAX = 0;
		uint256 ggAVAXAvailableAssets = _getGGAVAXAvailableAssets();

		// Process pending requests from front of queue, withdrawing from ggAVAX as needed
		uint256 requestsProcessed = 0;
		while (pendingRequests.length() > 0 && requestsProcessed < maxRequestsPerStakingDeposit) {
			requestsProcessed++;

			uint256 requestId = uint256(pendingRequestsQueue.front());
			if (!pendingRequests.contains(requestId)) {
				pendingRequestsQueue.popFront();
				emit QueueCleaned(bytes32("REQUEST_NOT_IN_PENDING_SET"), requestId);
				continue;
			}

			UnstakeRequest storage req = requests[requestId];

			if (ggAVAXAvailableAssets < req.expectedAssets) {
				emit InsufficientLiquidity(ggAVAXAvailableAssets, req.expectedAssets);
				break;
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

				// Track available assets locally
				ggAVAXAvailableAssets -= assetsReturned;

				// record accumulated excess to send back later
				if (assetsReturned > req.expectedAssets) {
					excessAVAX += assetsReturned - req.expectedAssets;
				}
			} catch (bytes memory reason) {
				// Check if this is specifically an insufficient liquidity error
				if (reason.length >= 4 && bytes4(reason) == TokenggAVAX.InsufficientLiquidity.selector) {
					// stAVAX doesn't have enough liquidity for this request, stop processing
					// Leave this request in the pending set for next time
					break;
				}
				// For other errors, bubble up rather than assuming liquidity issue
				// This preserves the original error for debugging
				assembly {
					revert(add(reason, 0x20), mload(reason))
				}
			}
		}

		if (excessAVAX > 0) {
			_depositYield(excessAVAX);
		}

		if (pendingRequests.length() != 0) {
			emit PendingRequestsNotProcesses(pendingRequests.length());
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
	function getMaxRequestsPerStakingDeposit() external view returns (uint256) {
		return maxRequestsPerStakingDeposit;
	}

	/// @notice Set the max pending requests limit (admin only)
	/// @param newLimit The new max pending requests limit
	function setMaxRequestsPerStakingDeposit(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
		maxRequestsPerStakingDeposit = newLimit;
	}

	/// @notice Set the minimum unstake amount on behalf of (admin only)
	/// @param newMinUnstakeOnBehalfOfAmt The new minimum unstake amount on behalf of
	function setMinUnstakeOnBehalfOfAmt(uint256 newMinUnstakeOnBehalfOfAmt) external onlyRole(DEFAULT_ADMIN_ROLE) {
		minUnstakeOnBehalfOfAmt = newMinUnstakeOnBehalfOfAmt;
	}

	/// @notice Get the minimum unstake amount on behalf of
	/// @return The minimum unstake amount on behalf of
	function getMinUnstakeOnBehalfOfAmt() external view returns (uint256) {
		return minUnstakeOnBehalfOfAmt;
	}

	/// @notice Set the unstake delay(admin only)
	/// @param newUnstakeDelay The new unstake delay in seconds
	function setUnstakeDelay(uint48 newUnstakeDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
		unstakeDelay = newUnstakeDelay;
	}

	/// @notice Set the max expiration delay (admin only)
	/// @param newMaxExpirationDelay The new expiration delay in seconds
	function setMaxExpirationDelay(uint48 newMaxExpirationDelay) external onlyRole(DEFAULT_ADMIN_ROLE) {
		if (newMaxExpirationDelay < MIN_EXPIRATION_DELAY) {
			revert InvalidExpirationDelay();
		}

		maxExpirationDelay = newMaxExpirationDelay;
	}

	/// @notice Pause the contract (pauser only)
	function pause() external onlyRole(PAUSER_ROLE) {
		paused = true;
		emit ContractPaused(msg.sender);
	}

	/// @notice Unpause the contract (pauser only)
	function unpause() external onlyRole(PAUSER_ROLE) {
		paused = false;
		emit ContractUnpaused(msg.sender);
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
		return block.timestamp < req.expirationTime;
	}

	/// @notice Get unstake request IDs for a user, paginated
	/// @param user   The address of the user
	/// @param offset How many entries to skip (0-based)
	/// @param limit  Max number of entries to return; if 0, returns all after offset
	/// @return ids   Array of request IDs in the requested slice
	function getRequestsByOwner(address user, uint256 offset, uint256 limit) external view returns (uint256[] memory ids) {
		uint256 total = requestsByOwner[user].length();

		if (offset >= total) {
			return new uint256[](0);
		}

		// if limit==0, return everything from offset; otherwise cap at total
		uint256 end = limit == 0 ? total : offset + limit;
		if (end > total) {
			end = total;
		}

		uint256 count = end - offset;
		ids = new uint256[](count);
		for (uint256 i = 0; i < count; i++) {
			ids[i] = requestsByOwner[user].at(offset + i);
		}
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

	/// @notice Emergency function to deposit stuck AVAX back to ggAVAX
	/// @dev Only callable by admin when AVAX is stuck in contract beyond allocated funds
	/// @param baseAmt The portion of stuck AVAX that was originally base (principal)
	/// @param rewardAmt The portion of stuck AVAX that was originally reward (yield)
	function rescueStuckAVAX(uint256 baseAmt, uint256 rewardAmt) external onlyRole(DEPOSITOR_ROLE) {
		uint256 stuckAVAX = address(this).balance - totalAllocatedFunds;
		if (baseAmt + rewardAmt != stuckAVAX) {
			revert InvalidYieldAmounts();
		}
		if (stuckAVAX > 0) {
			_depositToGGAVAX(baseAmt, rewardAmt, bytes32("RESCUE"), stuckAVAX);
		}
	}

	/// @notice Deposit AVAX to ggAVAX
	/// @param baseAmt The amount of base assets to deposit
	/// @param rewardAmt The amount of reward assets to deposit
	/// @param source The source of the deposit
	/// @param value The amount of AVAX to deposit
	function _depositToGGAVAX(uint256 baseAmt, uint256 rewardAmt, bytes32 source, uint256 value) internal {
		emit DepositedFromStaking(baseAmt, rewardAmt, source, value);
		tokenggAVAX.depositFromStaking{value: value}(baseAmt, rewardAmt, source);
	}

	/// @notice Deposit AVAX to ggAVAX via yield method
	/// @param value The amount of AVAX to deposit
	function _depositYield(uint256 value) internal {
		emit YieldDeposited(value);
		tokenggAVAX.depositYield{value: value}(bytes32("WITHDRAW_QUEUE"));
	}

	/// @notice Get the amount of AVAX available in ggAVAX for redemption
	/// @return The amount of AVAX available in ggAVAX for redemption
	function _getGGAVAXAvailableAssets() internal view returns (uint256) {
		uint256 totalAssets = tokenggAVAX.totalAssets();
		uint256 stakingTotal = tokenggAVAX.stakingTotalAssets();
		return totalAssets > stakingTotal ? totalAssets - stakingTotal : 0;
	}

	/// @dev Internal function implementing the core unstake request logic
	/// @param shares The number of shares to unstake
	/// @param shareProvider The address that provides the shares (caller)
	/// @param requester The address that will own the request and receive the funds
	/// @param expirationDelay How long after claiming period before requests expire
	/// @return requestId The unique identifier for the created request
	function _requestUnstake(uint256 shares, address shareProvider, address requester, uint48 expirationDelay) internal returns (uint256 requestId) {
		if (shares == 0) {
			revert ZeroShares();
		}

		if (expirationDelay > maxExpirationDelay) {
			revert InvalidExpirationDelay();
		}

		if (expirationDelay < MIN_EXPIRATION_DELAY) {
			expirationDelay = MIN_EXPIRATION_DELAY;
		}

		if (tokenggAVAX.balanceOf(shareProvider) < shares) {
			revert InsufficientTokenBalance();
		}

		uint256 expectedAssets = tokenggAVAX.convertToAssets(shares);

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

		ERC20(address(tokenggAVAX)).safeTransferFrom(shareProvider, address(this), shares);

		emit UnstakeRequested(requestId, requester, shares, expectedAssets, currentTime + unstakeDelay);
	}

	/// @dev Storage gap for future upgrades
	uint256[50] private __gap;
}
