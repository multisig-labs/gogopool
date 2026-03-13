// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {console2} from "forge-std/console2.sol";

/*
Bug Analysis Summary

  The Bug (WithdrawQueue.sol lines 403-406)

  if (pendingRequests.length() != 0) {
      emit PendingRequestsNotProcesses(pendingRequests.length());
      return;  // BUG: Early return without depositing remaining baseAmt/rewardAmt to ggAVAX
  }

  When there are still pending requests after the processing loop (limited by maxRequestsPerStakingDeposit = 50), the function returns early without depositing the remaining baseAmt and rewardAmt to ggAVAX. The AVAX stays stuck
   in the WithdrawQueue contract.

  Transaction Analysis

  Input Parameters:
  ┌───────────────────┬─────────────────────────────────┬────────────┐
  │     Parameter     │               Wei               │    AVAX    │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ baseAmt           │ 324,753,000,000,000,000,000,000 │ 324,753.00 │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ rewardAmt         │ 684,990,363,095,000,000,000     │ 684.99     │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ msg.value (total) │ 325,437,990,363,095,000,000,000 │ 325,437.99 │
  └───────────────────┴─────────────────────────────────┴────────────┘
  What happened:
  1. 20 requests were fulfilled (IDs 391-410), allocating 555.44 AVAX from redemptions
  2. ggAVAX had sufficient liquidity for all requests, so no deposits were made to ggAVAX during the loop (baseAmt/rewardAmt unchanged)
  3. Excess from improved exchange rate (0.0659 AVAX) was deposited as yield
  4. 54 pending requests remained (per Log 86)
  5. Early return triggered - baseAmt and rewardAmt never deposited

  Stuck AVAX Amounts
  ┌───────────────────┬─────────────────────────────────┬────────────┐
  │       Type        │               Wei               │    AVAX    │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ baseAmt (stuck)   │ 324,753,000,000,000,000,000,000 │ 324,753.00 │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ rewardAmt (stuck) │ 684,990,363,095,000,000,000     │ 684.99     │
  ├───────────────────┼─────────────────────────────────┼────────────┤
  │ Total Stuck       │ 325,437,990,363,095,000,000,000 │ 325,437.99 │
  └───────────────────┴─────────────────────────────────┴────────────┘
  The current WithdrawQueue contract balance is 330,485.12 AVAX, which includes these stuck funds plus allocated funds for fulfilled requests waiting to be claimed.
*/

contract WithdrawQueueFixForkTest2 is Test {
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

  address constant DEPOSITOR = 0x56400ab86f80925F9b1FA1dC93e14Fc11CFA420D;

	function setUp() public {
		// Use deployed contracts
		ggAVAX = TokenggAVAX(payable(DEPLOYED_TOKENGGAVAX));
		withdrawQueue = WithdrawQueue(payable(DEPLOYED_WITHDRAW_QUEUE));
		store = Storage(DEPLOYED_STORAGE);
		withdrawQueueProxyAdmin = ProxyAdmin(DEPLOYED_WITHDRAW_QUEUE_PROXY_ADMIN);
	}

	function test_WithdrawQueueFix() public {
		string memory url = vm.envString("ETH_RPC_URL");
		vm.createSelectFork(url);
		logState();

		// so now I want to deploy a new withdraw queue
		// WithdrawQueue newWithdrawQueue = new WithdrawQueue();

		// vm.prank(GUARDIAN);
		// withdrawQueueProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(withdrawQueue))), address(newWithdrawQueue));
		// withdrawQueue = WithdrawQueue(payable(address(withdrawQueue)));

		console2.log("\nRescuing stuck AVAX");
		uint256 stuckAVAX = address(withdrawQueue).balance - withdrawQueue.totalAllocatedFunds();
		console2.log("Stuck AVAX:", stuckAVAX / 1e18, stuckAVAX);
		vm.prank(DEPOSITOR);
		withdrawQueue.rescueStuckAVAX(0, stuckAVAX);

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
