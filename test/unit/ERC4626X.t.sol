// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "lib/forge-std/src/Test.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// Adapted from https://github.com/fei-protocol/ERC4626/blob/main/src/test/xERC4626.t.sol
// Changed to use `skip` and work with our rewards cycle

contract xERC4626Test is Test {
	TokenggAVAX public xToken;
	MockERC20 public token;

	function setUp() public {
		// Using mock so it has public mint and burn, required for the tests
		token = new MockERC20("WAVAX", "WAVAX", 18);

		address guardian = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
		vm.label(guardian, "guardian");
		// We are using create2 for production deploy so must also prank tx.origin
		vm.startPrank(guardian, guardian);
		// Get our token all set up with storage etc
		Storage store = new Storage();
		TokenggAVAX xTokenImpl = new TokenggAVAX();
		xToken = TokenggAVAX(deployProxy(address(xTokenImpl), address(1)));
		registerContract(store, "TokenggAVAX", address(xToken));

		xToken.initialize(store, token, 0);

		// Grant WITHDRAW_QUEUE_ROLE to the test contract for withdraw function testing
		xToken.grantRole(xToken.WITHDRAW_QUEUE_ROLE(), address(this));

		vm.stopPrank();
	}

	/// @dev test totalAssets call before, during, and after a reward distribution that starts on cycle start
	function testTotalAssetsDuringRewardDistribution(uint128 seed, uint128 reward) public {
		uint256 combined = uint256(seed) + uint256(reward);

		unchecked {
			vm.assume(seed != 0 && reward != 0 && combined < type(uint128).max);
		}

		token.mint(address(this), combined);
		token.approve(address(xToken), combined);

		// first seed pool
		xToken.deposit(seed, address(this));
		require(xToken.totalAssets() == seed, "seed");

		// mint rewards to pool
		token.mint(address(xToken), reward);
		require(xToken.lastRewardsAmt() == 0, "reward");
		require(xToken.totalAssets() == seed, "totalassets");
		require(xToken.convertToAssets(seed) == seed); // 1:1 still

		xToken.syncRewards();
		// after sync, everything same except lastRewardsAmt
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == seed);
		require(xToken.convertToAssets(seed) == seed); // 1:1 still

		// // accrue half the rewards
		skip(xToken.rewardsCycleLength() / 2);
		uint256 partialRewards = 0;
		if (block.timestamp > xToken.rewardsCycleEnd()) {
			partialRewards = reward;
		} else {
			partialRewards = (reward * (block.timestamp - xToken.lastSync())) / (xToken.rewardsCycleEnd() - xToken.lastSync());
		}
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == uint256(seed) + partialRewards);
		require(xToken.convertToAssets(seed) == uint256(seed) + partialRewards); // half rewards added
		require(xToken.convertToShares(uint256(seed) + partialRewards) == seed); // half rewards added

		// // accrue remaining rewards
		skip(xToken.rewardsCycleLength());
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == combined);
		assertEq(xToken.convertToAssets(seed), combined); // all rewards added
		assertEq(xToken.convertToShares(combined), seed);

		// accrue all and warp ahead 1 cycle
		skip(xToken.rewardsCycleLength() * 2);
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == combined);
		assertEq(xToken.convertToAssets(seed), combined); // all rewards added
		assertEq(xToken.convertToShares(combined), seed);
	}

	/// @dev test totalAssets call before, during, and after a reward distribution that starts on cycle start
	function testTotalAssetsDuringDelayedRewardDistribution(uint128 seed, uint128 reward) public {
		uint256 combined = uint256(seed) + uint256(reward);

		unchecked {
			vm.assume(seed != 0 && reward != 0 && combined < type(uint128).max);
		}

		token.mint(address(this), combined);
		token.approve(address(xToken), combined);

		// first seed pool
		xToken.deposit(seed, address(this));
		require(xToken.totalAssets() == seed, "seed");

		// mint rewards to pool
		token.mint(address(xToken), reward);
		assertEq(xToken.lastRewardsAmt(), 0, "after mint lastRewardsAmt");
		assertEq(xToken.totalAssets(), seed, "after mint totalAssets");
		assertEq(xToken.convertToAssets(seed), seed, "after mint convertToAssets"); // 1:1 still

		skip(xToken.rewardsCycleLength() / 2); // start midway

		xToken.syncRewards();
		assertEq(xToken.lastRewardsAmt(), reward, "after sync lastRewardsAmt");
		assertEq(xToken.totalAssets(), seed, "after sync totalAssets");
		assertEq(xToken.convertToAssets(seed), seed, "after sync convertToAssets"); // 1:1 still

		uint256 halfOfRemainingCycle = (xToken.rewardsCycleEnd() - block.timestamp) / 2;

		// accrue half the rewards
		skip(halfOfRemainingCycle);
		uint256 partialRewards = (xToken.lastRewardsAmt() * (block.timestamp - xToken.lastSync())) / (xToken.rewardsCycleEnd() - xToken.lastSync());
		assertEq(xToken.lastRewardsAmt(), reward, "mid cycle lastRewardsAmt");
		assertEq(xToken.totalAssets(), seed + partialRewards, "mid cycle totalAssets");
		assertEq(xToken.convertToAssets(seed), uint256(seed) + partialRewards, "mid cycle convertToAssets"); // half rewards added

		// accrue remaining rewards
		skip(halfOfRemainingCycle + 1);
		assertEq(xToken.lastRewardsAmt(), reward, "cycle end lastRewardsAmt");
		assertEq(xToken.totalAssets(), combined, "cycle end totalAssets");
		assertEq(xToken.convertToAssets(seed), combined, "cycle end convertToAssets"); // all rewards added
		assertEq(xToken.convertToShares(combined), seed, "cycle end convertToShares");

		// accrue all and warp ahead 1 cycle
		skip(xToken.rewardsCycleLength());
		assertEq(xToken.lastRewardsAmt(), reward, "one cycle after lastRewardsAmt");
		assertEq(xToken.totalAssets(), combined, "one cycle after totalAssets");
		assertEq(xToken.convertToAssets(seed), combined, "one cycle after convertToAssets"); // all rewards added
		assertEq(xToken.convertToShares(combined), seed, "one cycle after convertToShares");
	}

	function testTotalAssetsAfterDeposit(uint128 deposit1, uint128 deposit2) public {
		vm.assume(deposit1 != 0 && deposit2 != 0);

		uint256 combined = uint256(deposit1) + uint256(deposit2);
		token.mint(address(this), combined);
		token.approve(address(xToken), combined);
		xToken.deposit(deposit1, address(this));
		require(xToken.totalAssets() == deposit1);

		xToken.deposit(deposit2, address(this));
		assertEq(xToken.totalAssets(), combined);
	}

	function testTotalAssetsAfterWithdraw(uint128 deposit, uint128 withdraw) public {
		vm.assume(deposit != 0 && withdraw != 0 && withdraw <= deposit);

		token.mint(address(this), deposit);
		token.approve(address(xToken), deposit);

		xToken.deposit(deposit, address(this));
		require(xToken.totalAssets() == deposit);

		xToken.withdraw(withdraw, address(this), address(this));
		require(xToken.totalAssets() == deposit - withdraw);
	}

	function testSyncRewardsFailsDuringCycle(uint128 seed, uint128 reward, uint256 warp) public {
		uint256 combined = uint256(seed) + uint256(reward);

		unchecked {
			vm.assume(seed != 0 && reward != 0 && combined < type(uint128).max);
		}

		token.mint(address(this), seed);
		token.approve(address(xToken), seed);

		xToken.deposit(seed, address(this));
		token.mint(address(xToken), reward);
		xToken.syncRewards();
		warp = bound(warp, 0, 999);
		skip(warp);

		vm.expectRevert(abi.encodeWithSignature("SyncError()"));
		xToken.syncRewards();
	}

	function testSyncRewardsAfterEmptyCycle(uint128 seed, uint128 reward) public {
		uint256 combined = uint256(seed) + uint256(reward);

		unchecked {
			vm.assume(seed != 0 && reward != 0 && combined < type(uint128).max);
		}

		token.mint(address(this), seed);
		token.approve(address(xToken), seed);

		xToken.deposit(seed, address(this));
		require(xToken.totalAssets() == seed, "seed");
		skip(xToken.rewardsCycleLength() / 10);

		// sync with no new rewards
		xToken.syncRewards();
		require(xToken.lastRewardsAmt() == 0);
		require(xToken.lastSync() == block.timestamp);
		require(xToken.totalAssets() == seed);
		require(xToken.convertToShares(seed) == seed);

		// fast forward to next cycle and add rewards
		skip(xToken.rewardsCycleLength());
		token.mint(address(xToken), reward); // seed new rewards

		xToken.syncRewards();
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == seed);
		require(xToken.convertToShares(seed) == seed);

		skip(xToken.rewardsCycleLength() * 2);

		require(xToken.lastRewardsAmt() == reward);
		require(xToken.totalAssets() == combined);
		require(xToken.convertToAssets(seed) == combined);
		assertEq(xToken.convertToShares(combined), seed);
	}

	function testSyncRewardsAfterFullCycle(uint128 seed, uint128 reward, uint128 reward2) public {
		uint256 combined1 = uint256(seed) + uint256(reward);
		uint256 combined2 = uint256(seed) + uint256(reward) + reward2;

		unchecked {
			vm.assume(seed != 0 && reward != 0 && reward2 != 0 && combined2 < type(uint128).max);
		}

		token.mint(address(this), seed);
		token.approve(address(xToken), seed);

		xToken.deposit(seed, address(this));
		require(xToken.totalAssets() == seed, "seed");
		skip(xToken.rewardsCycleLength() / 10);

		token.mint(address(xToken), reward); // seed new rewards
		// sync with new rewards
		xToken.syncRewards();
		require(xToken.lastRewardsAmt() == reward);
		require(xToken.lastSync() == block.timestamp);
		require(xToken.totalAssets() == seed);
		require(xToken.convertToShares(seed) == seed); // 1:1 still

		// // fast forward to next cycle and add rewards
		skip(xToken.rewardsCycleLength());
		token.mint(address(xToken), reward2); // seed new rewards

		xToken.syncRewards();
		require(xToken.lastRewardsAmt() == reward2);
		require(xToken.totalAssets() == combined1);
		require(xToken.convertToAssets(seed) == combined1);

		skip(xToken.rewardsCycleLength() * 2);

		require(xToken.lastRewardsAmt() == reward2);
		require(xToken.totalAssets() == combined2);
		require(xToken.convertToAssets(seed) == combined2);
	}

	function deployProxy(address impl, address deployer) internal returns (address payable) {
		bytes memory data;
		TransparentUpgradeableProxy uups = new TransparentUpgradeableProxy(address(impl), deployer, data);
		return payable(uups);
	}

	function registerContract(Storage s, bytes memory name, address addr) internal {
		s.setBool(keccak256(abi.encodePacked("contract.exists", addr)), true);
		s.setAddress(keccak256(abi.encodePacked("contract.address", name)), addr);
		s.setString(keccak256(abi.encodePacked("contract.name", addr)), string(name));
	}
}
