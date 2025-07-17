// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {console2} from "forge-std/console2.sol";

import {stdError} from "forge-std/StdError.sol";

contract TokenggAVAXTest is BaseTest, IWithdrawer {
	using FixedPointMathLib for uint256;

	// Events to test against
	event YieldDonated(string indexed source, address indexed caller, uint256 sharesBurnt, uint256 avaxEquivalent);
	event WithdrawnForStaking(bytes32 indexed purpose, address indexed caller, uint256 assets);
	event DepositedAdditionalYield(bytes32 indexed source, address indexed caller, uint256 baseAmount, uint256 rewardAmt);
	event FeeCollected(bytes32 indexed source, uint256 feeAmount);

	address private alice;
	address private bob;
	address private charlie;
	address private nodeID;
	uint256 private duration;
	uint256 private delegationFee;

	function setUp() public override {
		super.setUp();
		bytes memory pubkey = hex"8c11f8f09e15059611fa549ba0019e26570b7331a15b0283ab966cc51538fa98d955b0b699943ca5e4225034485b9743";
		bytes
			memory sig = hex"b8c820f854116b4916f64434732f9155cc4f2f8f31580b1cc8d831d5969dbda834f12c5028c7b17355d67ce6437616a60e67d7809699b99ddae7d91950547a3807a569d0f6fbcc9ec85e0ec3cb908d2d3d1d5ebd8f04424fe0dd9ff7b792e465";
		bytes memory blsPubkeyAndSig = abi.encodePacked(pubkey, sig);
		bytes32 hardwareProvider = keccak256(abi.encodePacked("provider"));

		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.1 ether);

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActor("bob");
		charlie = getActor("charlie");

		// Grant WITHDRAW_QUEUE_ROLE to test users for withdrawal function tests
		vm.startPrank(guardian);
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), alice);
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), bob);
		ggAVAX.grantRole(ggAVAX.WITHDRAW_QUEUE_ROLE(), charlie);
		vm.stopPrank();

		nodeID = randAddress();
		duration = 2 weeks;
		delegationFee = 20_000;
		uint256 avaxAssignmentRequest = 1000 ether;
		vm.startPrank(alice);
		ggp.approve(address(staking), 100 ether);
		staking.stakeGGP(100 ether);
		minipoolMgr.createMinipool{value: 1000 ether}(nodeID, duration, delegationFee, avaxAssignmentRequest, blsPubkeyAndSig, hardwareProvider);
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

	function testWithdrawForMinipoolStaking() public {
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
		grantWithdrawQueueRole(liqStaker);

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
		grantWithdrawQueueRole(liqStaker);

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
		grantWithdrawQueueRole(liqStaker);
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
		grantWithdrawQueueRole(liqStaker);

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
	function testRevert_RedeemWithdrawAllAssetsMidRewardsCycle() public {
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
		uint256 redeemAmount = ggAVAX.maxRedeem(liqStaker);
		vm.expectRevert(stdError.arithmeticError);
		ggAVAX.redeem(redeemAmount, liqStaker, liqStaker);

		// attempt to withdraw all assets, which fails
		vm.prank(liqStaker);
		uint256 withdrawAmount = ggAVAX.maxWithdraw(liqStaker);
		vm.expectRevert(stdError.arithmeticError);
		ggAVAX.withdraw(withdrawAmount, liqStaker, liqStaker);
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
		grantWithdrawQueueRole(staker);
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

	function testRedeemWhenNoLiquidityAvailable() public {
		// Scenario: Deposit AVAX, withdraw for staking, then try to redeem when no liquidity available
		uint128 depositAmount = 1000 ether;
		address liquidStaker = getActorWithTokens("liquidStaker", depositAmount, 0);
		grantWithdrawQueueRole(liquidStaker);

		// 1. Liquid staker deposits AVAX
		vm.prank(liquidStaker);
		ggAVAX.depositAVAX{value: depositAmount}();

		assertEq(ggAVAX.balanceOf(liquidStaker), depositAmount);
		assertEq(ggAVAX.totalAssets(), depositAmount);

		// 2. Set low reserve rate and withdraw almost all funds for staking
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.05 ether); // 5% reserve

		uint256 liquidityToWithdraw = ggAVAX.amountAvailableForStaking();

		// Withdraw most liquidity for staking
		vm.prank(address(minipoolMgr));
		ggAVAX.withdrawForStaking(liquidityToWithdraw);

		// 3. Verify most liquidity is now staked
		uint256 liquidityRemaining = ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets();
		assertLt(liquidityRemaining, depositAmount); // Most funds are staked

		// 4. Check what maxRedeem and maxWithdraw return when limited by liquidity
		uint256 maxRedeemable = ggAVAX.maxRedeem(liquidStaker);
		uint256 maxWithdrawable = ggAVAX.maxWithdraw(liquidStaker);

		// maxRedeem/maxWithdraw should be limited by available liquidity
		assertEq(maxRedeemable, ggAVAX.convertToShares(liquidityRemaining));
		assertEq(maxWithdrawable, liquidityRemaining);
		assertLt(maxRedeemable, ggAVAX.balanceOf(liquidStaker));
		assertLt(maxWithdrawable, uint256(depositAmount));

		// 5. Redeem/withdraw within limits should work
		vm.startPrank(liquidStaker);

		if (maxRedeemable > 0) {
			uint256 redeemed = ggAVAX.redeemAVAX(maxRedeemable);
			assertEq(redeemed, maxWithdrawable);
		}

		// 6. Trying to redeem more than available should fail
		if (ggAVAX.balanceOf(liquidStaker) > 0) {
			// Try to redeem remaining shares when no liquidity left
			vm.expectRevert(); // Should revert due to insufficient WAVAX in contract
			ggAVAX.redeemAVAX(1 ether); // Try to redeem even a small amount
		}

		vm.stopPrank();
	}

	function testWAVAXTransferEnablesRedemption() public {
		// 1. User deposits AVAX and gets ggAVAX
		uint256 depositAmount = 1000 ether;
		vm.startPrank(alice);
		ggAVAX.depositAVAX{value: depositAmount}();
		uint256 aliceShares = ggAVAX.balanceOf(alice);
		vm.stopPrank();

		// 2. Set reserve ratio to 0% so all funds can be withdrawn for staking
		vm.startPrank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		// Enable withdrawal for delegation
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		vm.stopPrank();

		// 3. Use rialto to withdraw almost all funds from ggAVAX to simulate staking
		uint256 withdrawAmount = ggAVAX.amountAvailableForStaking();

		vm.prank(address(rialto));
		rialto.withdrawForDelegation(withdrawAmount, randAddress());

		// Verify ggAVAX has no liquid funds available
		uint256 liquidFunds = ggAVAX.totalAssets() - ggAVAX.stakingTotalAssets();

		// 4. Try to redeem AVAX - should fail due to insufficient liquidity
		vm.startPrank(alice);
		vm.expectRevert(); // Should revert due to insufficient funds
		ggAVAX.redeemAVAX(100 ether);
		vm.stopPrank();

		// 5. Send WAVAX directly to TokenggAVAX to provide liquidity
		uint256 liquidityAmount = 200 ether;
		vm.deal(charlie, liquidityAmount);
		vm.startPrank(charlie);
		// Wrap AVAX to WAVAX and transfer to ggAVAX
		wavax.deposit{value: liquidityAmount}();
		wavax.transfer(address(ggAVAX), liquidityAmount);
		vm.stopPrank();

		// Verify ggAVAX now has WAVAX balance
		uint256 ggAVAXWAVAXBalance = wavax.balanceOf(address(ggAVAX));
		assertEq(ggAVAXWAVAXBalance, liquidityAmount);

		// 6. Try to redeem again - should work now with the liquidity
		vm.startPrank(alice);
		uint256 redeemAmount = 200 ether;
		uint256 aliceBalanceBefore = alice.balance;

		// This should succeed now
		ggAVAX.withdrawAVAX(redeemAmount);

		// Verify alice received the AVAX
		uint256 aliceBalanceAfter = alice.balance;
		assertEq(aliceBalanceAfter, aliceBalanceBefore + redeemAmount);

		// Verify alice's ggAVAX balance decreased
		uint256 aliceSharesAfter = ggAVAX.balanceOf(alice);
		assertLt(aliceSharesAfter, aliceShares);
		vm.stopPrank();

		// 7. Check what happens to ggAVAX totalAssets - it should NOT increase immediately
		// The WAVAX we sent is not reflected in totalAssets until syncRewards is called
		uint256 totalAssetsBefore = ggAVAX.totalAssets();

		// But the WAVAX balance shows the extra funds are there
		uint256 actualWAVAXBalance = wavax.balanceOf(address(ggAVAX));

		// The difference shows the "unrealized" funds waiting for syncRewards
		uint256 unrealizedFunds = actualWAVAXBalance + ggAVAX.stakingTotalAssets() - totalAssetsBefore;

		// get the exhcange rate here
		uint256 exchangeRate = ggAVAX.previewRedeem(1000 ether);
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();

		vm.warp(ggAVAX.rewardsCycleEnd());
		uint256 newExchangeRate = ggAVAX.previewRedeem(1000 ether);
		assertGt(newExchangeRate, exchangeRate);
	}

	function testDepositAdditionalYieldZeroFees() public {
		// set reserve rate to zero
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);

		uint128 depositAmt = 100 ether;
		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0 ether);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();
		assertEq(ggAVAX.amountAvailableForStaking(), depositAmt);
		assertEq(ggAVAX.totalAssets(), depositAmt);

		uint256 additionalYieldAmt = 5 ether;
		address mev = getActorWithTokens("mev", uint128(additionalYieldAmt), 0 ether);
		vm.startPrank(guardian);
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(mev));
		vm.stopPrank();

		vm.startPrank(mev);
		ggAVAX.depositFromStaking{value: additionalYieldAmt}(0, additionalYieldAmt, "MEV");
		vm.stopPrank();

		assertEq(vault.balanceOf("ClaimProtocolDAO"), 0);
		assertEq(wavax.balanceOf(address(ggAVAX)), depositAmt + additionalYieldAmt);
	}

	function testDepositAdditionalYieldNonZeroFees() public {
		// set reserve rate to zero
		vm.startPrank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 1000);
		vm.stopPrank();

		uint128 depositAmt = 100 ether;
		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0 ether);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();
		assertEq(ggAVAX.amountAvailableForStaking(), depositAmt);
		assertEq(ggAVAX.totalAssets(), depositAmt);

		uint256 additionalYieldAmt = 5 ether;
		uint256 feeAmt = additionalYieldAmt.mulDivDown(1000, 10000);
		address mev = getActorWithTokens("mev", uint128(additionalYieldAmt), 0 ether);

		vm.startPrank(guardian);
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(mev));
		vm.stopPrank();

		vm.startPrank(mev);
		ggAVAX.depositFromStaking{value: additionalYieldAmt}(0, additionalYieldAmt, "MEV");
		vm.stopPrank();

		assertEq(vault.balanceOf("ClaimProtocolDAO"), feeAmt);
		assertEq(wavax.balanceOf(address(ggAVAX)), depositAmt + additionalYieldAmt - feeAmt);
	}

	function testDepositAdditionalYieldWithBaseAmount() public {
		// Setup: Create scenario where base assets are returned from delegation
		vm.startPrank(guardian);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 500); // 5% fee
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		vm.stopPrank();

		uint128 depositAmt = 100 ether;
		address liqStaker = getActorWithTokens("liqStaker", depositAmt, 0 ether);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		// Simulate staking by increasing stakingTotalAssets
		address delegator = getActorWithTokens("delegator", uint128(depositAmt), 0 ether);
		vm.startPrank(guardian);
		ggAVAX.grantRole(ggAVAX.STAKER_ROLE(), address(delegator));
		vm.stopPrank();

		uint256 stakingAmount = 50 ether;
		vm.prank(delegator);
		ggAVAX.withdrawForStaking(stakingAmount, "DELEGATION");

		// Now we have 50 ether staked, simulate delegation returns with rewards
		uint256 baseAmt = 30 ether; // Partial base amount returned
		uint256 rewardAmt = 10 ether; // Reward amount
		uint256 totalAmt = baseAmt + rewardAmt;
		uint256 feeAmt = rewardAmt.mulDivDown(500, 10000); // 5% of rewards
		uint256 netRewardAmt = rewardAmt - feeAmt;

		uint256 stakingAssetsBefore = ggAVAX.stakingTotalAssets();
		uint256 vaultBalanceBefore = vault.balanceOf("ClaimProtocolDAO");

		vm.startPrank(delegator);
		ggAVAX.depositFromStaking{value: totalAmt}(baseAmt, rewardAmt, "DELEGATION");
		vm.stopPrank();

		// Verify stakingTotalAssets decreased by baseAmt
		assertEq(ggAVAX.stakingTotalAssets(), stakingAssetsBefore - baseAmt);
		// Verify fees were collected
		assertEq(vault.balanceOf("ClaimProtocolDAO"), vaultBalanceBefore + feeAmt);
		// Verify total WAVAX in contract increased by base + net rewards
		assertEq(wavax.balanceOf(address(ggAVAX)), depositAmt - stakingAmount + baseAmt + netRewardAmt);
	}

	function testDonateYield() public {
		// Setup: User has ggAVAX shares
		uint256 depositAmount = 1000 ether;
		address donor = getActorWithTokens("donor", uint128(depositAmount), 0);

		vm.prank(donor);
		ggAVAX.depositAVAX{value: depositAmount}();

		uint256 sharesToBurn = 100 ether;
		uint256 donorBalanceBefore = ggAVAX.balanceOf(donor);
		uint256 totalSupplyBefore = ggAVAX.totalSupply();

		// Test: Call donateYield to burn shares
		// Note: We don't check the exact avaxEquivalent as it can vary slightly due to rounding

		vm.prank(donor);
		ggAVAX.donateYield(sharesToBurn, "DONATION");

		// Verify: Shares burned, total supply reduced
		assertEq(ggAVAX.balanceOf(donor), donorBalanceBefore - sharesToBurn);
		assertEq(ggAVAX.totalSupply(), totalSupplyBefore - sharesToBurn);
	}

	function testDonateYieldZeroShares() public {
		// Test: Call donateYield with 0 shares should revert
		vm.expectRevert(TokenggAVAX.ZeroSharesToBurn.selector);
		ggAVAX.donateYield(0, "DONATION");
	}

	function testDonateYieldInsufficientShares() public {
		// Setup: User has some shares but tries to burn more
		uint256 depositAmount = 100 ether;
		address donor = getActorWithTokens("donor", uint128(depositAmount), 0);

		vm.prank(donor);
		ggAVAX.depositAVAX{value: depositAmount}();

		// Test: Try to burn more shares than user has
		uint256 sharesToBurn = depositAmount + 1; // More than balance

		vm.expectRevert(TokenggAVAX.InsufficientShares.selector);
		vm.prank(donor);
		ggAVAX.donateYield(sharesToBurn, "DONATION");
	}

	function testWithdrawForStaking() public {
		// Setup: Enable withdrawal for delegation and add multisig
		vm.startPrank(guardian);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.1 ether); // 10% reserve
		vm.stopPrank();

		// Add liquidity to the contract
		uint256 depositAmount = 1000 ether;
		address liquidStaker = getActorWithTokens("liquidStaker", uint128(depositAmount), 0);
		vm.prank(liquidStaker);
		ggAVAX.depositAVAX{value: depositAmount}();

		uint256 withdrawAmount = 100 ether;
		uint256 stakingAssetsBefore = ggAVAX.stakingTotalAssets();
		uint256 multisigBalanceBefore = address(rialto).balance;

		// Test: Multisig withdraws for delegation
		vm.expectEmit(true, false, false, true);
		emit WithdrawnForStaking(bytes32("DELEGATION"), address(rialto), withdrawAmount);

		vm.prank(address(rialto)); // rialto is a multisig
		ggAVAX.withdrawForStaking(withdrawAmount, bytes32("DELEGATION"));

		// Verify: stakingTotalAssets increased, AVAX transferred to multisig
		assertEq(ggAVAX.stakingTotalAssets(), stakingAssetsBefore + withdrawAmount);
		assertEq(address(rialto).balance, multisigBalanceBefore + withdrawAmount);
	}

	function testWithdrawForStakingDisabled() public {
		// Setup: Disable withdrawal for delegation
		vm.prank(guardian);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), false);

		// Test: Try to withdraw when disabled
		vm.expectRevert(TokenggAVAX.WithdrawForStakingDisabled.selector);
		vm.prank(address(rialto));
		ggAVAX.withdrawForStaking(100 ether, bytes32("DELEGATION"));
	}

	function testWithdrawForStakingAmountTooLarge() public {
		// Setup: Enable withdrawal but create scenario with limited available funds
		vm.startPrank(guardian);
		store.setBool(keccak256("ProtocolDAO.WithdrawForDelegationEnabled"), true);
		store.setUint(keccak256("ProtocolDAO.TargetGGAVAXReserveRate"), 0.5 ether); // 50% reserve
		vm.stopPrank();

		// Add limited liquidity
		uint256 depositAmount = 100 ether;
		address liquidStaker = getActorWithTokens("liquidStaker", uint128(depositAmount), 0);
		vm.prank(liquidStaker);
		ggAVAX.depositAVAX{value: depositAmount}();

		// With 50% reserve, only 50 ether should be available for staking
		uint256 availableForStaking = ggAVAX.amountAvailableForStaking();
		assertEq(availableForStaking, 50 ether);

		// Test: Try to withdraw more than available
		uint256 withdrawAmount = availableForStaking + 1;

		vm.expectRevert(TokenggAVAX.WithdrawAmountTooLarge.selector);
		vm.prank(address(rialto));
		ggAVAX.withdrawForStaking(withdrawAmount, bytes32("DELEGATION"));
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

	function testDepositYieldWithZeroFees() public {
		// Set up: Set fee to 0
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 0);

		// Set up initial deposit
		uint256 depositAmt = 100 ether;
		address liqStaker = getActorWithTokens("liqStaker", uint128(depositAmt), 0 ether);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		// Record initial state
		uint256 initialWAVAXBalance = wavax.balanceOf(address(ggAVAX));

		// Test depositYield
		uint256 yieldAmount = 10 ether;
		address yieldProvider = getActorWithTokens("yieldProvider", uint128(yieldAmount), 0 ether);
		bytes32 source = bytes32("TEST_YIELD");

		// When fee is 0, FeeCollected event should not be emitted
		vm.expectEmit(true, true, false, true);
		emit DepositedAdditionalYield(source, yieldProvider, yieldAmount, 0);

		vm.prank(yieldProvider);
		ggAVAX.depositYield{value: yieldAmount}(source);

		// Verify results
		assertEq(wavax.balanceOf(address(ggAVAX)), initialWAVAXBalance + yieldAmount);
		assertEq(vault.balanceOf("ClaimProtocolDAO"), 0);
	}

	function testDepositYieldWithNonZeroFees() public {
		// Set up: Set fee to 10% (1000 bips)
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 1000);

		// Set up initial deposit
		uint256 depositAmt = 100 ether;
		address liqStaker = getActorWithTokens("liqStaker", uint128(depositAmt), 0 ether);
		vm.startPrank(liqStaker);
		wavax.approve(address(ggAVAX), depositAmt);
		ggAVAX.deposit(depositAmt, liqStaker);
		vm.stopPrank();

		// Record initial state
		uint256 initialWAVAXBalance = wavax.balanceOf(address(ggAVAX));
		uint256 initialProtocolDAOBalance = vault.balanceOf("ClaimProtocolDAO");

		// Test depositYield
		uint256 yieldAmount = 10 ether;
		uint256 expectedFee = yieldAmount.mulDivDown(1000, 10000); // 10%
		address yieldProvider = getActorWithTokens("yieldProvider", uint128(yieldAmount), 0 ether);
		bytes32 source = bytes32("MEV_YIELD");

		// Expect events
		vm.expectEmit(true, false, false, true);
		emit FeeCollected(source, expectedFee);
		vm.expectEmit(true, true, false, true);
		emit DepositedAdditionalYield(source, yieldProvider, yieldAmount, expectedFee);

		vm.prank(yieldProvider);
		ggAVAX.depositYield{value: yieldAmount}(source);

		// Verify results
		assertEq(wavax.balanceOf(address(ggAVAX)), initialWAVAXBalance + yieldAmount - expectedFee);
		assertEq(vault.balanceOf("ClaimProtocolDAO"), initialProtocolDAOBalance + expectedFee);
	}

	function testDepositYieldMultipleSources() public {
		// Set up: Set fee to 5% (500 bips)
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 500);

		// Test multiple yield deposits from different sources
		uint256[] memory yieldAmounts = new uint256[](3);
		yieldAmounts[0] = 5 ether;
		yieldAmounts[1] = 8 ether;
		yieldAmounts[2] = 3 ether;

		bytes32[] memory sources = new bytes32[](3);
		sources[0] = bytes32("MEV");
		sources[1] = bytes32("ARBITRAGE");
		sources[2] = bytes32("LIQUIDATION");

		uint256 totalYield = 0;
		uint256 totalFees = 0;

		for (uint256 i = 0; i < yieldAmounts.length; i++) {
			address provider = getActorWithTokens(string(abi.encodePacked("provider", i)), uint128(yieldAmounts[i]), 0 ether);
			uint256 fee = yieldAmounts[i].mulDivDown(500, 10000);
			totalFees += fee;
			totalYield += yieldAmounts[i] - fee;

			vm.prank(provider);
			ggAVAX.depositYield{value: yieldAmounts[i]}(sources[i]);
		}

		// Verify total accumulated yield
		assertEq(wavax.balanceOf(address(ggAVAX)), totalYield);
		assertEq(vault.balanceOf("ClaimProtocolDAO"), totalFees);
	}

	function testDepositYieldZeroAmount() public {
		// When yield is 0, fee will also be 0 regardless of fee rate
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 1000); // 10% fee

		bytes32 source = bytes32("ZERO_TEST");

		// Should emit event with 0 amounts (0 * 10% = 0 fee)
		vm.expectEmit(true, true, false, true);
		emit DepositedAdditionalYield(source, alice, 0, 0);

		vm.prank(alice);
		ggAVAX.depositYield{value: 0}(source);

		// Should complete without reverting
		assertEq(wavax.balanceOf(address(ggAVAX)), 0);
		assertEq(vault.balanceOf("ClaimProtocolDAO"), 0);
	}

	function testDepositYieldZeroAmountZeroFee() public {
		// When both fee and yield are 0, it should work now that the fix is in place
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 0); // 0% fee

		bytes32 source = bytes32("ZERO_TEST");

		// Should emit event with 0 amounts
		vm.expectEmit(true, true, false, true);
		emit DepositedAdditionalYield(source, alice, 0, 0);

		vm.prank(alice);
		ggAVAX.depositYield{value: 0}(source);

		// Should complete without reverting
		assertEq(wavax.balanceOf(address(ggAVAX)), 0);
	}

	function testDepositYieldIncreasesValue() public {
		// Set up: Set fee to 10%
		vm.prank(guardian);
		store.setUint(keccak256("ProtocolDAO.FeeBips"), 1000);

		// Initial depositor
		uint256 depositAmt = 100 ether;
		address depositor1 = getActorWithTokens("depositor1", uint128(depositAmt), 0 ether);
		vm.startPrank(depositor1);
		wavax.approve(address(ggAVAX), depositAmt);
		uint256 shares1 = ggAVAX.deposit(depositAmt, depositor1);
		vm.stopPrank();

		// Record initial conversion rate
		uint256 initialAssetsPerShare = ggAVAX.convertToAssets(1 ether);
		assertEq(initialAssetsPerShare, 1 ether); // Should be 1:1 initially

		// Deposit yield
		uint256 yieldAmount = 20 ether;
		uint256 feeAmount = yieldAmount.mulDivDown(1000, 10000); // 10%
		uint256 netYield = yieldAmount - feeAmount;
		address yieldProvider = getActorWithTokens("yieldProvider", uint128(yieldAmount), 0 ether);

		vm.prank(yieldProvider);
		ggAVAX.depositYield{value: yieldAmount}(bytes32("YIELD_TEST"));

		// The yield is now in the contract but not yet reflected in totalAssets
		// We need to sync rewards to distribute it
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();

		// Now wait for rewards to be fully distributed
		vm.warp(ggAVAX.rewardsCycleEnd());

		// Check that assets per share increased
		uint256 newAssetsPerShare = ggAVAX.convertToAssets(1 ether);
		assertGt(newAssetsPerShare, initialAssetsPerShare);

		// Verify the yield was distributed correctly
		uint256 expectedTotalAssets = depositAmt + netYield;
		assertEq(ggAVAX.totalAssets(), expectedTotalAssets);

		// Verify depositor1's shares are now worth more
		uint256 depositor1Assets = ggAVAX.convertToAssets(shares1);
		assertGt(depositor1Assets, depositAmt);
		assertEq(depositor1Assets, expectedTotalAssets); // They own all shares

		// New depositor should get fewer shares for the same amount due to increased value
		address depositor2 = getActorWithTokens("depositor2", uint128(depositAmt), 0 ether);
		vm.startPrank(depositor2);
		wavax.approve(address(ggAVAX), depositAmt);
		uint256 shares2 = ggAVAX.deposit(depositAmt, depositor2);
		vm.stopPrank();

		// depositor2 should get fewer shares than depositor1 got initially
		assertLt(shares2, shares1);
	}
}
