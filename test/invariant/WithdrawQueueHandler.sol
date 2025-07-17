// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {IWAVAX} from "../../contracts/interface/IWAVAX.sol";
import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";

contract WithdrawQueueHandler {
	WithdrawQueue public immutable withdrawQueue;
	TokenggAVAX public immutable ggAVAX;
	IWAVAX public immutable wavax;
	Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

	address[] public actors;
	mapping(address => bool) public isActor;

	// Track ghost variables for invariant testing
	uint256 public totalDepositsToGGAVAX;
	uint256 public totalWithdrawsFromGGAVAX;
	uint256 public totalYieldDeposits;

	// Bounded values for fuzzing
	uint256 private constant MAX_DEPOSIT_AMOUNT = 100_000_000 ether;
	uint256 private constant MAX_TIME_SKIP = 30 days;
	uint256 private constant MIN_DEPOSIT_AMOUNT = 1 wei;

	constructor(WithdrawQueue _withdrawQueue, TokenggAVAX _ggAVAX, IWAVAX _wavax) {
		withdrawQueue = _withdrawQueue;
		ggAVAX = _ggAVAX;
		wavax = _wavax;
	}

	modifier useActor(uint256 actorIndexSeed) {
		address currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
		vm.startPrank(currentActor);
		_;
		vm.stopPrank();
	}

	modifier countCall(string memory key) {
		// Could be used for tracking call counts
		_;
	}

	function addActor(address actor) external {
		if (!isActor[actor]) {
			actors.push(actor);
			isActor[actor] = true;
		}
	}

	function getUsers() external view returns (address[] memory) {
		return actors;
	}

	function getUserCount() external view returns (uint256) {
		return actors.length;
	}

	function getUser(uint256 index) external view returns (address) {
		return actors[index];
	}

	// ============ CORE ACTIONS ============

	/// @notice User deposits AVAX to ggAVAX
	function depositToGGAVAX(uint256 actorSeed, uint256 amount) external useActor(actorSeed) countCall("depositToGGAVAX") {
		amount = bound(amount, MIN_DEPOSIT_AMOUNT, MAX_DEPOSIT_AMOUNT);

		// Ensure actor has enough balance
		if (msg.sender.balance < amount) {
			vm.deal(msg.sender, amount);
		}

		try ggAVAX.depositAVAX{value: amount}() {
			totalDepositsToGGAVAX += amount;
		} catch {
			// Ignore failed deposits
		}
	}

	/// @notice User requests unstaking of their ggAVAX
	function requestUnstake(uint256 actorSeed, uint256 sharesSeed) external useActor(actorSeed) countCall("requestUnstake") {
		uint256 userBalance = ggAVAX.balanceOf(msg.sender);
		if (userBalance == 0) return;

		uint256 shares = bound(sharesSeed, 1, userBalance);

		try ggAVAX.approve(address(withdrawQueue), shares) {
			try withdrawQueue.requestUnstake(shares) {
				// Success - shares moved to withdrawQueue
			} catch {
				// Ignore failed requests
			}
		} catch {
			// Ignore failed approvals
		}
	}

	/// @notice Protocol deposits yield to fulfill requests
	function depositFromStaking(uint256 baseAmountSeed, uint256 rewardAmountSeed) external countCall("depositFromStaking") {
		uint256 baseAmount = bound(baseAmountSeed, 0, MAX_DEPOSIT_AMOUNT);
		uint256 rewardAmount = bound(rewardAmountSeed, 0, MAX_DEPOSIT_AMOUNT);
		uint256 totalAmount = baseAmount + rewardAmount;

		if (totalAmount == 0) return;

		// Get a depositor role actor (charlie in our setup)
		address depositor = actors[actors.length - 1]; // Assume last actor has depositor role

		vm.startPrank(depositor);
		vm.deal(depositor, totalAmount);

		try withdrawQueue.depositFromStaking{value: totalAmount}(baseAmount, rewardAmount, bytes32("HANDLER")) {
			totalYieldDeposits += totalAmount;
		} catch {
			// Ignore failed deposits
		}

		vm.stopPrank();
	}

	/// @notice User claims their fulfilled unstake request
	function claimUnstake(uint256 actorSeed, uint256 requestIdSeed) external useActor(actorSeed) countCall("claimUnstake") {
		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(msg.sender);
		if (userRequests.length == 0) return;

		uint256 requestId = userRequests[bound(requestIdSeed, 0, userRequests.length - 1)];

		// Check if request is fulfilled and claimable
		if (!withdrawQueue.isFulfilledRequest(requestId)) return;
		if (!withdrawQueue.canClaimRequest(requestId)) return;

		try withdrawQueue.claimUnstake(requestId) {
			// Success - user received AVAX
		} catch {
			// Ignore failed claims
		}
	}

	/// @notice User cancels their pending or fulfilled request
	function cancelRequest(uint256 actorSeed, uint256 requestIdSeed) external useActor(actorSeed) countCall("cancelRequest") {
		uint256[] memory userRequests = withdrawQueue.getRequestsByOwner(msg.sender);
		if (userRequests.length == 0) return;

		uint256 requestId = userRequests[bound(requestIdSeed, 0, userRequests.length - 1)];

		// Check if request is pending or fulfilled (and not expired)
		bool isPending = withdrawQueue.isRequestPending(requestId);
		bool isFulfilled = withdrawQueue.isFulfilledRequest(requestId);

		if (!isPending && !isFulfilled) return;

		WithdrawQueue.UnstakeRequest memory req = withdrawQueue.getRequestInfo(requestId);

		// Don't cancel if it's too late (fulfilled and claimable)
		if (isFulfilled && block.timestamp >= req.claimableTime) return;

		try withdrawQueue.cancelRequest(requestId) {
			// Success - user got shares back
		} catch {
			// Ignore failed cancellations
		}
	}

	/// @notice Skip time forward to test temporal invariants
	function advanceTime(uint256 timeSeed) external countCall("advanceTime") {
		uint256 timeSkip = bound(timeSeed, 1 hours, MAX_TIME_SKIP);
		vm.warp(block.timestamp + timeSkip);
	}

	/// @notice Reclaim expired funds
	function reclaimExpiredFunds(uint256 maxRequestsSeed) external countCall("reclaimExpiredFunds") {
		uint256 maxRequests = bound(maxRequestsSeed, 1, 10);

		try withdrawQueue.reclaimExpiredFunds(maxRequests) {
			// Success - expired funds reclaimed
		} catch {
			// Ignore failed reclaims
		}
	}

	/// @notice Cancel multiple requests for a user
	function cancelMultipleRequests(uint256 actorSeed, uint256 maxRequestsSeed) external useActor(actorSeed) countCall("cancelMultipleRequests") {
		uint256 maxRequests = bound(maxRequestsSeed, 1, 5);

		try withdrawQueue.cancelRequests(maxRequests) {
			// Success - requests cancelled
		} catch {
			// Ignore failed cancellations
		}
	}

	/// @notice Simulate rewards by sending WAVAX to ggAVAX
	function simulateRewards(uint256 rewardAmountSeed) external countCall("simulateRewards") {
		uint256 rewardAmount = bound(rewardAmountSeed, 0.1 ether, 100 ether);

		// Get any actor to send rewards
		address rewardSender = actors[0];

		vm.startPrank(rewardSender);
		vm.deal(rewardSender, rewardAmount);

		try wavax.deposit{value: rewardAmount}() {
			try wavax.transfer(address(ggAVAX), rewardAmount) {
				// Advance time and sync rewards
				vm.warp(ggAVAX.rewardsCycleEnd());
				try ggAVAX.syncRewards() {
					vm.warp(ggAVAX.rewardsCycleEnd());
				} catch {
					// Ignore failed sync
				}
			} catch {
				// Ignore failed transfer
			}
		} catch {
			// Ignore failed WAVAX deposit
		}

		vm.stopPrank();
	}

	/// @notice Withdraw funds from ggAVAX for staking (simulates protocol operations)
	function withdrawForStaking(uint256 amountSeed) external countCall("withdrawForStaking") {
		uint256 availableAmount = ggAVAX.amountAvailableForStaking();
		if (availableAmount == 0) return;

		uint256 amount = bound(amountSeed, 0.1 ether, availableAmount);

		// This would need to be called by rialto or similar staking contract
		// For testing, we'll simulate this
		try ggAVAX.withdrawForStaking(amount) {
			// Success - funds withdrawn for staking
		} catch {
			// Ignore failed withdrawals
		}
	}

	// ============ BOUNDARY TESTING ============

	/// @notice Test edge case: zero amount deposits
	function testZeroAmountDeposit(uint256 actorSeed) external useActor(actorSeed) countCall("testZeroAmountDeposit") {
		try ggAVAX.depositAVAX{value: 0}() {
			// Should revert
		} catch {
			// Expected
		}
	}

	/// @notice Test edge case: request with zero shares
	function testZeroSharesRequest(uint256 actorSeed) external useActor(actorSeed) countCall("testZeroSharesRequest") {
		try withdrawQueue.requestUnstake(0) {
			// Should revert
		} catch {
			// Expected
		}
	}

	/// @notice Test edge case: claim non-existent request
	function testClaimNonExistentRequest(uint256 actorSeed, uint256 requestIdSeed) external useActor(actorSeed) countCall("testClaimNonExistentRequest") {
		uint256 requestId = bound(requestIdSeed, withdrawQueue.nextRequestId(), withdrawQueue.nextRequestId() + 100);

		try withdrawQueue.claimUnstake(requestId) {
			// Should revert
		} catch {
			// Expected
		}
	}

	// ============ UTILITY FUNCTIONS ============

	/// @notice Get current system state for debugging
	function getSystemState() external view returns (
		uint256 ggAVAXBalance,
		uint256 withdrawQueueBalance,
		uint256 totalAllocated,
		uint256 pendingCount,
		uint256 fulfilledCount,
		uint256 nextRequestId
	) {
		ggAVAXBalance = ggAVAX.totalAssets();
		withdrawQueueBalance = address(withdrawQueue).balance;
		totalAllocated = withdrawQueue.totalAllocatedFunds();
		pendingCount = withdrawQueue.getPendingRequestsCount();
		fulfilledCount = withdrawQueue.getFulfilledRequestsCount();
		nextRequestId = withdrawQueue.nextRequestId();
	}

	/// @notice Helper function to bound values
	function bound(uint256 x, uint256 min, uint256 max) internal pure returns (uint256) {
		if (min > max) {
			(min, max) = (max, min);
		}
		if (x < min) return min;
		if (x > max) return max;
		return x;
	}
}
