// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {console2} from "forge-std/console2.sol";

contract WithdrawQueueFixForkTest is Test {
	TokenggAVAX public ggAVAX;
	WithdrawQueue public withdrawQueue;
	ProxyAdmin public withdrawQueueProxyAdmin;
	Storage public store;

	// Deployed contract addresses on Avalanche mainnet
	address constant DEPLOYED_TOKENGGAVAX = 0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3;
	address constant DEPLOYED_WITHDRAW_QUEUE = 0x61f908D4992a790A2792D3C36850B4b9eB5849A3;
	address constant DEPLOYED_STORAGE = 0x1cEa17F9dE4De28FeB6A102988E12D4B90DfF1a9;
	address constant DEPLOYED_WITHDRAW_QUEUE_PROXY_ADMIN = 0x6e8fd36d51d159209054dADda7f87Aa4e1aED940;

	// Guardian address (from deployed addresses)
	address constant GUARDIAN = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;

	// Fork at specific block to test the fix scenario
	uint256 constant FORK_BLOCK = 69342397;

	function setUp() public {
		// Create fork at specific block
		// Fork right before depositing 100k avax to withdraw queue
		vm.createSelectFork("https://nd-058-850-167.p2pify.com/4e4706b8fc3a3bb4a5559c84671a1cf4/ext/bc/C/rpc", FORK_BLOCK);

		// Use deployed contracts
		ggAVAX = TokenggAVAX(payable(DEPLOYED_TOKENGGAVAX));
		withdrawQueue = WithdrawQueue(payable(DEPLOYED_WITHDRAW_QUEUE));
		store = Storage(DEPLOYED_STORAGE);
		withdrawQueueProxyAdmin = ProxyAdmin(DEPLOYED_WITHDRAW_QUEUE_PROXY_ADMIN);
	}

	function test_WithdrawQueueDeposits() public {
		logState();

		// alright so now what do I want to test
		// so from here a deposit of 0 shouldn't change anyt of the state
		console2.log("\nDepositing 0");
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 0}(0, 0, bytes32("TEST_YIELD"));

		logState();

		deal(address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D), 100000 ether);
		console2.log("\nDepositing 100k");
		console2.log("Balance of depositor", address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D).balance / 1e18, address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D).balance);
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 100000 ether}(100000 ether, 0, bytes32("TEST_YIELD"));

		logState();

		console2.log("\nDepositing 0 to recreate issue");
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 0}(0, 0, bytes32("TEST_YIELD"));
		logState();
	}

	function test_getState() public {
		logState();

		console2.log("\n=== All Unstake Requests Analysis ===");

		// Get all pending requests
		uint256[] memory pendingRequests = withdrawQueue.getAllPendingRequests();
		console2.log("\nPending Requests Count:", pendingRequests.length);

		uint256 totalPendingAllocated = 0;
		uint256 totalPendingExpected = 0;

		for (uint256 i = 0; i < pendingRequests.length; i++) {
			uint256 requestId = pendingRequests[i];

			// Get request info using the public mapping
			(address requester, uint256 shares, uint256 expectedAssets, uint48 requestTime, uint48 claimableTime, uint48 expirationTime, uint256 allocatedFunds) = withdrawQueue.requests(requestId);

			console2.log("\nPending Request ID:", requestId);
			console2.log("  Requester:", requester);
			console2.log("  Shares:", shares / 1e18, "AVAX", shares);
			console2.log("  Expected Assets:", expectedAssets / 1e18, "AVAX, expectedAssets, ", expectedAssets);
			console2.log("  Allocated Funds:", allocatedFunds / 1e18, "AVAX, allocatedFunds, ", allocatedFunds);
			console2.log("  Request Time:", requestTime);
			console2.log("  Claimable Time:", claimableTime);
			console2.log("  Expiration Time:", expirationTime);

			totalPendingAllocated += allocatedFunds;
			totalPendingExpected += expectedAssets;
		}

		// Get all fulfilled requests
		uint256[] memory fulfilledRequests = withdrawQueue.getAllFulfilledRequests();
		console2.log("\nFulfilled Requests Count:", fulfilledRequests.length);

		uint256 totalFulfilledAllocated = 0;
		uint256 totalFulfilledExpected = 0;

		for (uint256 i = 0; i < fulfilledRequests.length; i++) {
			uint256 requestId = fulfilledRequests[i];

			(address requester, uint256 shares, uint256 expectedAssets, uint48 requestTime, uint48 claimableTime, uint48 expirationTime, uint256 allocatedFunds) = withdrawQueue.requests(requestId);


			totalFulfilledAllocated += allocatedFunds;
			totalFulfilledExpected += expectedAssets;
		}

		console2.log("\n=== Summary ===");
		console2.log("Total Pending Requests:", pendingRequests.length);
		console2.log("Total Pending Expected Assets:", totalPendingExpected / 1e18, "AVAX");
		console2.log("Total Pending Allocated Funds:", totalPendingAllocated / 1e18, "AVAX");
		console2.log("\nTotal Fulfilled Requests:", fulfilledRequests.length);
		console2.log("Total Fulfilled Expected Assets:", totalFulfilledExpected / 1e18, "AVAX");
		console2.log("Total Fulfilled Allocated Funds:", totalFulfilledAllocated / 1e18, "AVAX");
		console2.log("\nGrand Total Expected Assets:", (totalPendingExpected + totalFulfilledExpected) / 1e18, "AVAX");
		console2.log("Grand Total Allocated Funds:", (totalPendingAllocated + totalFulfilledAllocated) / 1e18, "AVAX");

		// Check if allocations match expectations
		console2.log("\n=== Allocation Analysis ===");
		console2.log("WithdrawQueue totalAllocatedFunds():", withdrawQueue.totalAllocatedFunds() / 1e18, "AVAX");
		console2.log("Sum of individual allocations:", (totalPendingAllocated + totalFulfilledAllocated) / 1e18, "AVAX");
		console2.log("Allocation difference:", (withdrawQueue.totalAllocatedFunds() - (totalPendingAllocated + totalFulfilledAllocated)) / 1e18, "AVAX");
	}

	function test_WithdrawQueueFix() public {
		logState();

		// so now I want to deploy a new withdraw queue
		WithdrawQueue newWithdrawQueue = new WithdrawQueue();

		vm.prank(GUARDIAN);
		withdrawQueueProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(withdrawQueue))), address(newWithdrawQueue));
		withdrawQueue = WithdrawQueue(payable(address(withdrawQueue)));

		// alright so now what do I want to test
		// so from here a deposit of 0 shouldn't change anyt of the state
		console2.log("\nDepositing 0");
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 0}(0, 0, bytes32("TEST_YIELD"));

		logState();

		deal(address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D), 100000 ether);
		console2.log("\nDepositing 100k");
		console2.log("Balance of depositor", address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D).balance / 1e18, address(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D).balance);
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 100000 ether}(100000 ether, 0, bytes32("TEST_YIELD"));

		logState();

		console2.log("\nDepositing 0 to recreate issue");
		vm.prank(0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D);
		withdrawQueue.depositFromStaking{value: 0}(0, 0, bytes32("TEST_YIELD"));
		logState();

	}

	function logState() public {
		console2.log("\n=== System State ===");
		console2.log("\n--- withdraw queue ---");
		console2.log("WithdrawQueue Balance:",  address(withdrawQueue).balance / 1e18, address(withdrawQueue).balance);
		console2.log("Total Allocated Funds:", withdrawQueue.totalAllocatedFunds() / 1e18, withdrawQueue.totalAllocatedFunds());
		console2.log("Pending Requests:", withdrawQueue.getPendingRequestsCount());
		console2.log("Fulfilled Requests:", withdrawQueue.getFulfilledRequestsCount());

		console2.log("Next request amount", withdrawQueue.getNextPendingRequestAmount() / 1e18, withdrawQueue.getNextPendingRequestAmount());

		console2.log("\n--- ggAVAX ---");
		console2.log("WAVAX Balance:", ggAVAX.asset().balanceOf(address(ggAVAX)) / 1e18, ggAVAX.asset().balanceOf(address(ggAVAX)));
		console2.log("Total Assets:", ggAVAX.totalAssets() / 1e18, ggAVAX.totalAssets());
		console2.log("Total Supply:", ggAVAX.totalSupply() / 1e18, ggAVAX.totalSupply());
		console2.log("Exchange Rate:", (ggAVAX.totalAssets() * 1e18) / ggAVAX.totalSupply());
		console2.log("Staking Total Assets:", ggAVAX.stakingTotalAssets() / 1e18, ggAVAX.stakingTotalAssets());
		console2.log("Amount Available for Staking:", ggAVAX.amountAvailableForStaking() / 1e18, ggAVAX.amountAvailableForStaking());

		uint256 totalAssets = ggAVAX.totalAssets();
		uint256 stakingTotal = ggAVAX.stakingTotalAssets();
		console2.log("Liquid Balance in ggAVAX:", totalAssets > stakingTotal ? totalAssets - stakingTotal : 0);
	}
}
