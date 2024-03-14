// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";

import {stdError} from "forge-std/StdError.sol";

contract TokenggAVAXTest is BaseTest, IWithdrawer {
	using FixedPointMathLib for uint256;

	address private alice;
	address private bob;
	address private nodeID;
	uint256 private duration;
	uint256 private delegationFee;

	function setUp() public override {
		super.setUp();
		bytes memory pubkey = hex"8c11f8f09e15059611fa549ba0019e26570b7331a15b0283ab966cc51538fa98d955b0b699943ca5e4225034485b9743";
		bytes
			memory sig = hex"b8c820f854116b4916f64434732f9155cc4f2f8f31580b1cc8d831d5969dbda834f12c5028c7b17355d67ce6437616a60e67d7809699b99ddae7d91950547a3807a569d0f6fbcc9ec85e0ec3cb908d2d3d1d5ebd8f04424fe0dd9ff7b792e465";
		bytes memory blsPubkeyAndSig = abi.encodePacked(pubkey, sig);

		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.1 ether);

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActor("bob");

		nodeID = randAddress();
		duration = 2 weeks;
		delegationFee = 20_000;
		uint256 avaxAssignmentRequest = 1000 ether;
		vm.startPrank(alice);
		ggp.approve(address(staking), 100 ether);
		staking.stakeGGP(100 ether);
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig);
		vm.stopPrank();
	}

	function testTokenSetup() public {
		assertEq(ggAVAX.name(), "GoGoPool Liquid Staking Token");
		assertEq(ggAVAX.decimals(), uint8(18));
		assertEq(ggAVAX.symbol(), "ggAVAX");
	}

	function testReinitialization() public {
		vm.expectRevert(bytes("Initializable: contract is already initialized"));
		ggAVAX.initialize(store, wavax, 0);
	}

	function testSingleDepositWithdrawWAVAX(uint128 amount) public {
		vm.assume(amount != 0 && amount < MAX_AMT);

		uint256 aliceUnderlyingAmount = amount;

		uint256 alicePreDepositBal = wavax.balanceOf(alice);

		vm.startPrank(alice);
		wavax.approve(address(ggAVAX), aliceUnderlyingAmount);
		uint256 aliceShareAmount = ggAVAX.deposit(aliceUnderlyingAmount, alice);
		vm.stopPrank();

		// Expect exchange rate to be 1:1 on initial deposit.
		assertEq(aliceUnderlyingAmount, aliceShareAmount);
		assertEq(ggAVAX.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
		assertEq(ggAVAX.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
		assertEq(ggAVAX.totalSupply(), aliceShareAmount);
		assertEq(ggAVAX.totalAssets(), aliceUnderlyingAmount);
		assertEq(ggAVAX.balanceOf(alice), aliceShareAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), aliceUnderlyingAmount);
		assertEq(wavax.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

		vm.startPrank(alice);
		wavax.approve(address(ggAVAX), aliceUnderlyingAmount);
		ggAVAX.withdraw(aliceUnderlyingAmount, alice, alice);
		vm.stopPrank();

		assertEq(ggAVAX.totalAssets(), 0);
		assertEq(ggAVAX.balanceOf(alice), 0);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), 0);
		assertEq(wavax.balanceOf(alice), alicePreDepositBal);
	}

	function testSingleDepositWithdrawAVAX(uint128 amount) public {
		vm.assume(amount != 0 && amount < MAX_AMT);

		uint256 aliceUnderlyingAmount = amount;
		uint256 alicePreDepositBal = alice.balance;
		vm.deal(alice, alicePreDepositBal + aliceUnderlyingAmount);

		vm.prank(alice);
		uint256 aliceShareAmount = ggAVAX.depositAVAX{value: aliceUnderlyingAmount}();

		// Expect exchange rate to be 1:1 on initial deposit.
		assertEq(aliceUnderlyingAmount, aliceShareAmount);
		assertEq(ggAVAX.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
		assertEq(ggAVAX.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
		assertEq(ggAVAX.totalSupply(), aliceShareAmount);
		assertEq(ggAVAX.totalAssets(), aliceUnderlyingAmount);
		assertEq(ggAVAX.balanceOf(alice), aliceShareAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), aliceUnderlyingAmount);
		assertEq(alice.balance, alicePreDepositBal);

		vm.prank(alice);
		ggAVAX.withdrawAVAX(aliceUnderlyingAmount);

		assertEq(ggAVAX.totalAssets(), 0);
		assertEq(ggAVAX.balanceOf(alice), 0);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), 0);
		assertEq(alice.balance, alicePreDepositBal + aliceUnderlyingAmount);
	}

	function testSingleMintRedeem(uint128 amount) public {
		vm.assume(amount != 0 && amount < MAX_AMT);

		uint256 aliceShareAmount = amount;

		uint256 alicePreDepositBal = wavax.balanceOf(alice);

		vm.startPrank(alice);
		wavax.approve(address(ggAVAX), aliceShareAmount);
		uint256 aliceUnderlyingAmount = ggAVAX.mint(aliceShareAmount, alice);
		vm.stopPrank();

		// Expect exchange rate to be 1:1 on initial mint.
		assertEq(aliceShareAmount, aliceUnderlyingAmount);
		assertEq(ggAVAX.previewWithdraw(aliceShareAmount), aliceUnderlyingAmount);
		assertEq(ggAVAX.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
		assertEq(ggAVAX.totalSupply(), aliceShareAmount);
		assertEq(ggAVAX.totalAssets(), aliceUnderlyingAmount);
		assertEq(ggAVAX.balanceOf(alice), aliceUnderlyingAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), aliceUnderlyingAmount);
		assertEq(wavax.balanceOf(alice), alicePreDepositBal - aliceUnderlyingAmount);

		vm.prank(alice);
		ggAVAX.redeem(aliceShareAmount, alice, alice);

		assertEq(ggAVAX.totalAssets(), 0);
		assertEq(ggAVAX.balanceOf(alice), 0);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(alice)), 0);
		assertEq(wavax.balanceOf(alice), alicePreDepositBal);
	}

	function testDepositStakingRewards() public {
		// Scenario:
		// 1. Bob mints 2000 shares (costs 2000 tokens)
		// 2. 1000 tokens are withdrawn for staking
		// 3. 1000 rewards deposited
		// 4. 1 rewards cycle pass, no rewards are distributed to
		// 		totalReleasedAssets
		// 5. Sync rewards
		// 6. Skip ahead 1/3 a cycle, bob's 4000 shares convert to
		//		4333 assets.
		// 7. Skip ahead remaining 2/3 of the rewards cycle,
		//		all rewards should be distributed

		uint256 depositAmount = 2000 ether;
		uint256 stakingWithdrawAmount = 1000 ether;
		uint256 totalStakedAmount = 2000 ether;

		uint256 rewardsAmount = 100 ether;
		uint256 liquidStakerRewards = 50 ether - ((50 ether * 15) / 100);

		uint256 rialtoInitBal = address(rialto).balance;

		// 1. Bob mints 1000 shares
		vm.deal(bob, depositAmount);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: depositAmount}();

		assertEq(bob.balance, 0);
		assertEq(wavax.balanceOf(address(ggAVAX)), depositAmount);
		assertEq(ggAVAX.balanceOf(bob), depositAmount);
		assertEq(ggAVAX.convertToShares(ggAVAX.balanceOf(bob)), depositAmount);
		assertEq(ggAVAX.amountAvailableForStaking(), depositAmount - depositAmount.mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether));

		// 2. 1000 tokens are withdrawn for staking
		vm.prank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(nodeID);

		assertEq(address(rialto).balance, rialtoInitBal + totalStakedAmount);
		assertEq(ggAVAX.totalAssets(), depositAmount);
		assertEq(ggAVAX.stakingTotalAssets(), stakingWithdrawAmount);

		// 3. 1000 rewards are deposited
		// None of these rewards should be distributed yet
		vm.deal(address(rialto), address(rialto).balance + rewardsAmount);
		vm.startPrank(address(rialto));
		bytes32 txID = keccak256("txid");
		minipoolMgr.recordStakingStart(nodeID, txID, block.timestamp);
		int256 idx = minipoolMgr.getIndexOf(nodeID);
		MinipoolManager.Minipool memory mp = minipoolMgr.getMinipool(idx);
		uint256 endTime = block.timestamp + mp.duration;

		skip(mp.duration);
		minipoolMgr.recordStakingEndThenMaybeCycle{value: totalStakedAmount + rewardsAmount}(nodeID, endTime, rewardsAmount);
		vm.stopPrank();

		assertEq(address(rialto).balance, rialtoInitBal);
		assertEq(ggAVAX.totalAssets(), depositAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), depositAmount);

		// 4. Skip ahead one rewards cycle
		// Still no rewards should be distributed
		vm.warp(ggAVAX.rewardsCycleEnd());
		assertEq(ggAVAX.totalAssets(), depositAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), depositAmount);

		// 5. Sync rewards and see an update to half the rewards
		ggAVAX.syncRewards();
		assertEq(ggAVAX.totalAssets(), depositAmount);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), depositAmount);
		assertEq(ggAVAX.lastRewardsAmt(), liquidStakerRewards);

		// 6. Skip 1/3 of rewards length and see 1/3 rewards in totalReleasedAssets
		skip(ggAVAX.rewardsCycleLength() / 3);

		uint256 partialRewards = (liquidStakerRewards * (block.timestamp - ggAVAX.lastSync())) / (ggAVAX.rewardsCycleEnd() - ggAVAX.lastSync());
		assertEq(uint256(ggAVAX.totalAssets()), uint256(depositAmount) + partialRewards);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), depositAmount + partialRewards);
		assertEq(ggAVAX.lastRewardsAmt(), liquidStakerRewards);

		// 7. Skip 2/3 of rewards length
		// Rewards should be fully distributed
		skip((ggAVAX.rewardsCycleLength() * 2) / 3);
		assertEq(ggAVAX.totalAssets(), depositAmount + liquidStakerRewards);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), depositAmount + liquidStakerRewards);
	}

	function testAmountAvailableForStaking() public {
		uint256 depositAmount = 10_000 ether;

		// deposit avax
		vm.deal(bob, depositAmount);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: depositAmount}();

		assertEq(bob.balance, 0);
		assertEq(wavax.balanceOf(address(ggAVAX)), depositAmount);
		assertEq(ggAVAX.balanceOf(bob), depositAmount);
		assertEq(ggAVAX.convertToShares(ggAVAX.balanceOf(bob)), depositAmount);

		// verify amountAvailableForStaking
		uint256 reservedAssets = ggAVAX.totalAssets().mulWadDown(dao.getTargetGGAVAXReserveRate());
		uint256 amountAvailableForStaking = ggAVAX.amountAvailableForStaking();
		assertEq(amountAvailableForStaking, depositAmount - reservedAssets);

		// withdraw max for staking
		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(amountAvailableForStaking);

		// withdraw avax from reserve
		vm.prank(bob);
		ggAVAX.withdraw(1000 ether, bob, bob);

		// verify no underflow
		assertEq(ggAVAX.amountAvailableForStaking(), 0);
	}

	function testWithdrawForStaking() public {
		// Deposit liquid staker funds
		uint256 depositAmount = 1200 ether;
		uint256 nodeAmt = 2000 ether;
		uint128 ggpStakeAmt = 200 ether;

		vm.deal(bob, depositAmount);
		vm.prank(bob);
		ggAVAX.depositAVAX{value: depositAmount}();

		assertEq(ggAVAX.previewWithdraw(depositAmount), depositAmount);
		assertEq(ggAVAX.maxWithdraw(bob), depositAmount);
		assertEq(ggAVAX.previewRedeem(depositAmount), depositAmount);
		assertEq(ggAVAX.maxRedeem(bob), depositAmount);

		// Create and claim minipool
		address nodeOp = getActorWithTokens("nodeOp", uint128(depositAmount), ggpStakeAmt);

		vm.startPrank(nodeOp);
		ggp.approve(address(staking), ggpStakeAmt);
		staking.stakeGGP(ggpStakeAmt);
		MinipoolManager.Minipool memory mp = createMinipool(nodeAmt / 2, nodeAmt / 2, duration);
		vm.stopPrank();

		vm.startPrank(address(rialto));
		minipoolMgr.claimAndInitiateStaking(mp.nodeID);
		minipoolMgr.recordStakingStart(mp.nodeID, randHash(), block.timestamp);
		vm.stopPrank();

		assertEq(ggAVAX.previewWithdraw(depositAmount), depositAmount);
		assertEq(ggAVAX.maxWithdraw(bob), ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets());
		assertEq(ggAVAX.previewRedeem(depositAmount), depositAmount);
		assertEq(ggAVAX.maxRedeem(bob), ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets());

		skip(mp.duration);

		uint256 rewardsAmt = nodeAmt.mulDivDown(0.1 ether, 1 ether);

		vm.deal(address(rialto), address(rialto).balance + rewardsAmt);
		vm.prank(address(rialto));
		minipoolMgr.recordStakingEndThenMaybeCycle{value: nodeAmt + rewardsAmt}(mp.nodeID, block.timestamp, rewardsAmt);

		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());

		// Now that rewards are added, maxRedeem = depositAmt (because shares haven't changed), and maxWithdraw > depositAmt
		assertGt(ggAVAX.maxWithdraw(bob), depositAmount);
		assertEq(ggAVAX.maxRedeem(bob), depositAmount);

		// If we withdraw same number of assets, we will get less shares since they are worth more now
		assertLt(ggAVAX.previewWithdraw(depositAmount), depositAmount);
		// If we redeem all our shares we get more assets
		assertGt(ggAVAX.previewRedeem(depositAmount), depositAmount);
	}

	function testWithdrawForStakingOverdrawn() public {
		assertEq(ggAVAX.totalAssets(), 0);

		vm.startPrank(address(minipoolMgr));
		vm.expectRevert(stdError.arithmeticError);
		ggAVAX.withdrawForStaking(1000 ether);
		vm.stopPrank();
	}

	function testDepositFromStakingInvalid() public {
		uint256 totalAmt = 100 ether;
		uint256 baseAmt = 0;
		uint256 rewardAmt = 0;

		vm.deal(address(minipoolMgr), totalAmt);

		vm.startPrank(address(minipoolMgr));
		vm.expectRevert(TokenggAVAX.InvalidStakingDeposit.selector);
		ggAVAX.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt);

		totalAmt = ggAVAX.stakingTotalAssets() + 1;
		baseAmt = ggAVAX.stakingTotalAssets() + 1;
		rewardAmt = 0;
		vm.expectRevert(TokenggAVAX.InvalidStakingDeposit.selector);
		ggAVAX.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt);
	}

	function testDepositPause() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		bytes memory customError = abi.encodeWithSignature("ContractPaused()");
		vm.expectRevert(customError);
		ggAVAX.deposit(100 ether, alice);

		vm.expectRevert(bytes("ZERO_SHARES"));
		ggAVAX.deposit(0 ether, alice);
	}

	function testPreviewDepositPaused() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		ggAVAX.previewDeposit(100 ether);

		uint256 shares = ggAVAX.previewDeposit(0 ether);
		assertEq(shares, 0);
	}

	function testDepositAVAXPaused() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		ggAVAX.depositAVAX{value: 100 ether}();

		vm.expectRevert(TokenggAVAX.ZeroShares.selector);
		ggAVAX.depositAVAX{value: 0 ether}();
	}

	function testMintPause() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		ggAVAX.mint(100 ether, alice);

		uint256 assets = ggAVAX.mint(0 ether, alice);
		assertEq(assets, 0);
	}

	function testPreviewMintPaused() public {
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		vm.expectRevert(BaseAbstract.ContractPaused.selector);
		ggAVAX.previewMint(100 ether);

		uint256 assets = ggAVAX.previewMint(0 ether);
		assertEq(assets, 0);
	}

	function testWithdrawPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);

		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		assertEq(wavax.balanceOf(liqStaker), 0);

		// pause contract
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		// verify withdraw still works
		vm.prank(liqStaker);
		ggAVAX.withdraw(100 ether, liqStaker, liqStaker);

		assertEq(wavax.balanceOf(liqStaker), depositAmt);
	}

	function testWithdrawAVAXPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);

		vm.prank(liqStaker);
		ggAVAX.depositAVAX{value: depositAmt}();

		assertEq(liqStaker.balance, 0);

		// pause contract
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		// verify withdrawAVAX still works
		vm.prank(liqStaker);
		ggAVAX.withdrawAVAX(100 ether);

		assertEq(liqStaker.balance, depositAmt);
	}

	function testRedeemPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		assertEq(wavax.balanceOf(liqStaker), 0);

		// pause contract
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		// verify redeem still works
		vm.prank(liqStaker);
		ggAVAX.redeem(100 ether, liqStaker, liqStaker);

		assertEq(wavax.balanceOf(liqStaker), depositAmt);
	}

	function testRedeemAVAXPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);

		vm.prank(liqStaker);
		ggAVAX.depositAVAX{value: depositAmt}();

		assertEq(liqStaker.balance, 0);

		// pause contract
		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		// verify redeemAVAX still works
		vm.prank(liqStaker);
		ggAVAX.redeemAVAX(100 ether);

		assertEq(liqStaker.balance, depositAmt);
	}

	function testMaxMint() public {
		address liqStaker = getActor("liqStaker");
		assertEq(ggAVAX.maxMint(liqStaker), type(uint256).max);

		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		assertEq(ggAVAX.maxMint(liqStaker), 0);
	}

	function testMaxDeposit() public {
		address liqStaker = getActor("liqStaker");
		assertEq(ggAVAX.maxDeposit(liqStaker), type(uint256).max);

		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		assertEq(ggAVAX.maxDeposit(liqStaker), 0);
	}

	function testMaxWithdrawPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		uint256 assets = ggAVAX.maxWithdraw(liqStaker);
		assertEq(assets, depositAmt);
	}

	function testMaxRedeemPaused() public {
		uint128 depositAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		vm.prank(address(ocyticus));
		dao.pauseContract("TokenggAVAX");

		uint256 shares = ggAVAX.maxRedeem(liqStaker);
		assertEq(shares, depositAmt);
	}

	function testMaxRedeem() public {
		uint128 depositAmt = 1000 ether;
		uint128 rewardAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0 ether);
		address rewarder = getActorWithTokens("rewarder", rewardAmt, 0 ether);

		// deposit
		vm.prank(liqStaker);
		ggAVAX.depositAVAX{value: depositAmt}();

		assertEq(ggAVAX.maxRedeem(liqStaker), depositAmt);

		// transfer rewards without syncing
		vm.prank(rewarder);
		wavax.transfer(address(ggAVAX), rewardAmt);

		assertEq(ggAVAX.maxRedeem(liqStaker), depositAmt);

		// sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();

		// skip halfway through rewards cycle
		skip(ggAVAX.rewardsCycleLength() / 2);

		assertEq(ggAVAX.maxRedeem(liqStaker), depositAmt);
	}

	function testMaxWithdraw() public {
		uint128 depositAmt = 1000 ether;
		uint128 rewardAmt = 100 ether;

		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0 ether);
		address rewarder = getActorWithTokens("rewarder", rewardAmt, 0 ether);

		// deposit
		vm.prank(liqStaker);
		ggAVAX.depositAVAX{value: depositAmt}();

		assertEq(ggAVAX.maxWithdraw(liqStaker), depositAmt);

		// transfer rewards without syncing
		vm.prank(rewarder);
		wavax.transfer(address(ggAVAX), rewardAmt);

		assertEq(ggAVAX.maxWithdraw(liqStaker), depositAmt);

		// sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();

		// skip halfway through rewards cycle
		skip(ggAVAX.rewardsCycleLength() / 2);

		assertEq(ggAVAX.maxWithdraw(liqStaker), depositAmt + (rewardAmt / 2));
	}

	/// @dev Test redeem shares mid rewards cycle
	///      There is an issue that causes redeem or withdraw to revert
	///      when a liquid staker is able to withdraw all contract assets
	///      mid rewards cycle. This is unlikely to happen in production
	///      when the protocol has a larger number of stakers
	function testFailRedeemWithdrawAllAssetsMidRewardsCycle() public {
		uint128 seed = 1000;
		uint128 reward = 100;

		// start at fresh rewards cycle
		vm.warp(ggAVAX.rewardsCycleEnd());

		address liqStaker = getActorWithTokens("liqStaker", seed, 0 ether);

		vm.prank(liqStaker);

		// first seed pool
		ggAVAX.depositAVAX{value: seed}();
		assertEq(ggAVAX.totalAssets(), seed);

		// mint rewards to pool
		vm.prank(liqStaker);
		wavax.transfer(address(ggAVAX), reward);
		assertEq(ggAVAX.lastRewardsAmt(), 0);
		assertEq(ggAVAX.totalAssets(), seed);
		assertEq(ggAVAX.convertToAssets(seed), seed); // 1:1 still

		// sync rewards
		ggAVAX.syncRewards();
		assertEq(ggAVAX.lastRewardsAmt(), reward);
		assertEq(ggAVAX.totalAssets(), seed);
		assertEq(ggAVAX.convertToAssets(seed), seed); // 1:1 still

		// skip half a rewards cycle
		skip(ggAVAX.rewardsCycleLength() / 2);
		assertEq(ggAVAX.lastRewardsAmt(), reward);
		assertEq(ggAVAX.totalAssets(), uint256(seed) + (reward / 2));
		assertEq(ggAVAX.convertToAssets(seed), uint256(seed) + (reward / 2)); // half rewards added
		assertEq(ggAVAX.convertToShares(uint256(seed) + (reward / 2)), seed); // half rewards added

		assertEq(ggAVAX.balanceOf(liqStaker), seed);

		// attempt to redeem all shares, which fails
		vm.prank(liqStaker);
		ggAVAX.redeem(ggAVAX.maxRedeem(liqStaker), liqStaker, liqStaker);

		// attempt to withdraw all assets, which fails
		vm.prank(liqStaker);
		ggAVAX.withdraw(ggAVAX.maxWithdraw(liqStaker), liqStaker, liqStaker);
	}

	function testReserveLowerThanExpected() public {
		uint128 depositAmt = 10_000 ether;
		// liquid staker deposit 10,000 total assets
		// set collateral rate to 30%,
		// 		Total Assets 	-> 10,000
		// 		Reserve 			-> 3,000

		// withdraw for staking 7000
		// liquid staker withdraws 1000
		// 		Total Assets 		-> 9000
		// 		Reserve 				-> 2700

		// now `amountAvailableForStaking` is -700 but returns 0
		address staker = getActorWithTokens("staker", depositAmt, 0 ether);
		vm.startPrank(staker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, staker);
		vm.stopPrank();

		// set reserve rate
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.3 ether); // 10% collateral held in reserve

		assertEq(ggAVAX.amountAvailableForStaking(), 7000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 3000 ether);

		// withdraw 7000 ether for staking artificially
		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(7000 ether);

		// liquid staker withdraws assets
		vm.prank(staker);
		ggAVAX.withdraw(1000 ether, staker, staker);
		assertEq(ggAVAX.totalAssets(), 9000 ether);
		assertEq(ggAVAX.stakingTotalAssets(), 7000 ether);
		assertEq(ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether), 2700 ether);
		assertEq(ggAVAX.amountAvailableForStaking(), 0);
	}

	function receiveWithdrawalAVAX() external payable {}

	function printState(string memory message) internal view {
		uint256 reservedAssets = ggAVAX.totalAssets().mulDivDown(dao.getTargetGGAVAXReserveRate(), 1 ether);

		console.log("");
		console.log("STEP", message);
		console.log("---timestamps---");
		console.log("block timestamp", block.timestamp);
		console.log("rewardsCycleEnd", ggAVAX.rewardsCycleEnd());
		console.log("lastSync", ggAVAX.lastSync());

		console.log("---assets---");
		console.log("totalAssets", ggAVAX.totalAssets() / 1 ether);
		console.log("amountAvailableForStaking", ggAVAX.amountAvailableForStaking() / 1 ether);
		console.log("reserved", reservedAssets / 1 ether);
		console.log("stakingTotalAssets", ggAVAX.stakingTotalAssets() / 1 ether);

		console.log("---rewards---");
		console.log("lastRewardsAmt", ggAVAX.lastRewardsAmt() / 1 ether);
	}
}
