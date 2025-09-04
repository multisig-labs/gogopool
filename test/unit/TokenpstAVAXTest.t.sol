// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {TokenpstAVAX} from "../../contracts/contract/tokens/TokenpstAVAX.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {console2} from "forge-std/console2.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract TokenpstAVAXTest is BaseTest {
	using FixedPointMathLib for uint256;

	TokenpstAVAX pstAVAX;
	WithdrawQueue withdrawQueue;
	address alice;
	address bob;
	address cam;

	function setUp() public override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);
		cam = getActorWithTokens("cam", MAX_AMT, MAX_AMT);

		// Deploy WithdrawQueue
		WithdrawQueue withdrawQueueImpl = new WithdrawQueue();
		bytes memory withdrawQueueInitData = abi.encodeWithSelector(WithdrawQueue.initialize.selector, address(ggAVAX), address(store), 7 days, 14 days);
		TransparentUpgradeableProxy withdrawQueueProxy = new TransparentUpgradeableProxy(
			address(withdrawQueueImpl),
			address(proxyAdmin),
			withdrawQueueInitData
		);
		withdrawQueue = WithdrawQueue(payable(address(withdrawQueueProxy)));

		// Deploy
		TokenpstAVAX pstAVAXImpl = new TokenpstAVAX();
		bytes memory initData = abi.encodeWithSelector(TokenpstAVAX.initialize.selector, address(ggAVAX), address(withdrawQueue));
		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(pstAVAXImpl), address(proxyAdmin), initData);
		pstAVAX = TokenpstAVAX(payable(address(proxy)));
	}

	function testSetup() public {
		assertEq(pstAVAX.vault(), address(ggAVAX));
		assertEq(pstAVAX.underlyingAsset(), address(ggAVAX.asset()));
	}

	function testDeposit() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), assets);

		vm.prank(alice);
		pstAVAX.withdraw(assets);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertEq(ggAVAX.balanceOf(alice), assets);
	}

	function testDepositWithReceive() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		(bool sent, ) = payable(address(pstAVAX)).call{value: assets}("");
		require(sent, "Failed to send AVAX");
		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(address(pstAVAX).balance, 0);
	}

	function testStripYieldWithstAVAXHolder() public {
		uint256 assets = 1000 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		assertEq(pstAVAX.getExcessShares(), 0);

		vm.prank(bob);
		ggAVAX.depositAVAX{value: assets}();

		assertEq(ggAVAX.balanceOf(bob), assets);

		// bob and pstAVAX have equal shares

		skip(ggAVAX.rewardsCycleLength());

		// now deposit more WAVAX as rewards
		vm.deal(address(ggAVAX), 1000 ether);
		vm.prank(address(ggAVAX));
		wavax.deposit{value: 1000 ether}();

		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());

		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), 1000 ether + 500 ether);
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX))), 1000 ether + 500 ether);

		uint256 sharesFor1000tokens = ggAVAX.convertToShares(1000 ether);
		pstAVAX.stripYield();

		uint256 newSharePrice = ggAVAX.convertToAssets(1 ether);
		assertEq(newSharePrice, 2 ether);

		// Bob gets 100% of the yield, pstAVAX gets 0%
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), 1000 ether + 1000 ether);
		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX))), 1000 ether, 1);

		assertApproxEqAbs(ggAVAX.balanceOf(address(pstAVAX)), 500 ether, 1);

		// Alice withdraws her 1000 pstAVAX tokens
		vm.prank(alice);
		uint256 sharesReceived = pstAVAX.withdraw(1000 ether);
		uint256 aliceValueReceived = ggAVAX.convertToAssets(sharesReceived);
		assertApproxEqAbs(aliceValueReceived, 1000 ether, 1);

		uint256 assetsLeft = ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX)));
		assertEq(assetsLeft, 0);
	}

	function testStripYieldDefault() public {
		// we have to create a ggAVAX holder I think
		uint256 ggAVAXDeposit = 1 ether;
		vm.prank(bob);
		ggAVAX.depositAVAX{value: ggAVAXDeposit}();

		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		assertEq(pstAVAX.getExcessShares(), 0);

		// Send WAVAX directly to TokenggAVAX as rewards
		vm.startPrank(bob);
		uint256 rewardsAmt = 1 ether;
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);

		// Warp and sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		vm.stopPrank();

		assertEq(pstAVAX.getExcessShares(), rewardsAmt / 2);

		vm.prank(alice);
		pstAVAX.withdraw(assets);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertLt(ggAVAX.balanceOf(alice), 1 ether);

		pstAVAX.stripYield();
		assertEq(pstAVAX.getExcessShares(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
	}

	// Additional deposit tests
	function testDepositWAVAX() public {
		uint256 assets = 2 ether;

		vm.startPrank(alice);
		wavax.deposit{value: assets}();
		wavax.approve(address(pstAVAX), assets);
		pstAVAX.deposit(assets);
		vm.stopPrank();

		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), assets);
	}

	function testDepositZeroAmount() public {
		vm.expectRevert(TokenpstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		pstAVAX.depositAVAX{value: 0}();

		vm.expectRevert(TokenpstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		pstAVAX.deposit(0);
	}

	function testMultipleDeposits() public {
		uint256 assets1 = 1 ether;
		uint256 assets2 = 2 ether;

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets1}();

		vm.prank(bob);
		pstAVAX.depositAVAX{value: assets2}();

		assertEq(pstAVAX.balanceOf(alice), assets1);
		assertEq(pstAVAX.balanceOf(bob), assets2);
		assertEq(pstAVAX.totalSupply(), assets1 + assets2);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), assets1 + assets2);
	}

	function testInitializeWithZeroVault() public {
		TokenpstAVAX pstAVAXImpl = new TokenpstAVAX();
		bytes memory initData = abi.encodeWithSelector(TokenpstAVAX.initialize.selector, address(0), address(withdrawQueue));

		vm.expectRevert(TokenpstAVAX.InvalidVault.selector);
		new TransparentUpgradeableProxy(address(pstAVAXImpl), address(proxyAdmin), initData);
	}

	function testInitializeWithNonERC4626Contract() public {
		TokenpstAVAX pstAVAXImpl = new TokenpstAVAX();
		address nonERC4626 = address(new MockContract());
		bytes memory initData = abi.encodeWithSelector(TokenpstAVAX.initialize.selector, nonERC4626, address(withdrawQueue));

		vm.expectRevert();
		new TransparentUpgradeableProxy(address(pstAVAXImpl), address(proxyAdmin), initData);
	}

	function testSetPaused() public {
		assertFalse(pstAVAX.paused());

		pstAVAX.setPaused(true);
		assertTrue(pstAVAX.paused());

		pstAVAX.setPaused(false);
		assertFalse(pstAVAX.paused());
	}

	function testSetPausedOnlyOwner() public {
		vm.expectRevert("Ownable: caller is not the owner");
		vm.prank(alice);
		pstAVAX.setPaused(true);
	}

	function testDepositWhenPaused() public {
		pstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		pstAVAX.depositAVAX{value: 1 ether}();

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		pstAVAX.deposit(1 ether);
	}

	function testWithdrawWhenPaused() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		pstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		pstAVAX.withdraw(assets);
	}

	function testStripYieldWhenPaused() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		pstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		pstAVAX.stripYield();
	}

	function testReceiveWhenPaused() public {
		pstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		payable(address(pstAVAX)).call{value: 1 ether}("");
	}

	function testRecoverERC20Safe() public {
		// Deploy a mock ERC20 token
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);
		uint256 amount = 100 ether;
		mockToken.mint(address(pstAVAX), amount);

		uint256 ownerBalanceBefore = mockToken.balanceOf(pstAVAX.owner());

		pstAVAX.recoverERC20Safe(address(mockToken), amount);

		assertEq(mockToken.balanceOf(address(pstAVAX)), 0);
		assertEq(mockToken.balanceOf(pstAVAX.owner()), ownerBalanceBefore + amount);
	}

	function testRecoverERC20SafeZeroAmount() public {
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);
		uint256 amount = 100 ether;
		mockToken.mint(address(pstAVAX), amount);

		uint256 ownerBalanceBefore = mockToken.balanceOf(pstAVAX.owner());

		// Pass 0 to recover all tokens
		pstAVAX.recoverERC20Safe(address(mockToken), 0);

		assertEq(mockToken.balanceOf(address(pstAVAX)), 0);
		assertEq(mockToken.balanceOf(pstAVAX.owner()), ownerBalanceBefore + amount);
	}

	function testRecoverERC20SafeOnlyOwner() public {
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);

		vm.expectRevert("Ownable: caller is not the owner");
		vm.prank(alice);
		pstAVAX.recoverERC20Safe(address(mockToken), 100 ether);
	}

	function testCannotRecoverUnderlyingAsset() public {
		vm.expectRevert("Cannot recover underlying asset");
		pstAVAX.recoverERC20Safe(address(wavax), 100 ether);
	}

	function testCannotRecoverVaultShares() public {
		vm.expectRevert("Cannot recover vault shares");
		pstAVAX.recoverERC20Safe(address(ggAVAX), 100 ether);
	}

	// Withdraw error tests
	function testWithdrawZeroAmount() public {
		vm.expectRevert(TokenpstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		pstAVAX.withdraw(0);
	}

	function testWithdrawInsufficientBalance() public {
		vm.expectRevert(TokenpstAVAX.InsufficientBalance.selector);
		vm.prank(alice);
		pstAVAX.withdraw(1 ether);
	}

	function testStripYieldNoYield() public {
		uint256 excessShares = pstAVAX.stripYield();
		assertEq(excessShares, 0);
	}

	function testDepositEvent() public {
		uint256 assets = 1 ether;

		vm.expectEmit(true, false, false, true, address(pstAVAX));
		emit Deposited(alice, assets, assets);

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
	}

	function testWithdrawEvent() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		uint256 expectedShares = ggAVAX.convertToShares(assets);

		vm.expectEmit(true, false, false, true, address(pstAVAX));
		emit Withdrawn(alice, assets, expectedShares);

		vm.prank(alice);
		pstAVAX.withdraw(assets);
	}

	function testWithdrawViaQueue() public {
		uint256 assets = 100 ether;

		// Deposit first
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		uint256 aliceBalanceBefore = pstAVAX.balanceOf(alice);
		uint256 expectedVaultShares = ggAVAX.convertToShares(assets);

		// Withdraw via queue
		vm.prank(alice);
		(uint256 vaultShares, uint256 requestId) = pstAVAX.withdrawViaQueue(assets, 0);

		// Check return values
		assertEq(vaultShares, expectedVaultShares);

		// Check pstAVAX balance was burned
		assertEq(pstAVAX.balanceOf(alice), aliceBalanceBefore - assets);
		assertEq(pstAVAX.totalSupply(), 0);

		// Check that request was created in WithdrawQueue
		WithdrawQueue.UnstakeRequest memory request = withdrawQueue.getRequestInfo(requestId);
		assertEq(request.requester, alice);
		assertEq(request.shares, vaultShares);
		assertEq(request.expectedAssets, ggAVAX.convertToAssets(vaultShares));

		// Check that WithdrawQueue has the ggAVAX shares
		assertEq(ggAVAX.balanceOf(address(withdrawQueue)), vaultShares);
	}

	function testWithdrawViaQueueZeroAmount() public {
		vm.expectRevert(TokenpstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		pstAVAX.withdrawViaQueue(0, 0);
	}

	function testWithdrawViaQueueInsufficientBalance() public {
		vm.expectRevert(TokenpstAVAX.InsufficientBalance.selector);
		vm.prank(alice);
		pstAVAX.withdrawViaQueue(1 ether, 0);
	}

	function testWithdrawViaQueueWhenPaused() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		pstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		pstAVAX.withdrawViaQueue(assets, 0);
	}

	function testWithdrawViaQueueEvent() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		uint256 expectedVaultShares = ggAVAX.convertToShares(assets);
		uint256 expectedRequestId = 0;

		vm.expectEmit(true, false, false, true, address(pstAVAX));
		emit WithdrawnViaQueue(alice, assets, expectedVaultShares, expectedRequestId);

		vm.prank(alice);
		pstAVAX.withdrawViaQueue(assets, 0);
	}

	function testWithdrawViaQueueMultipleUsers() public {
		uint256 assets1 = 1 ether;
		uint256 assets2 = 2 ether;

		// Both users deposit
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets1}();

		vm.prank(bob);
		pstAVAX.depositAVAX{value: assets2}();

		// Both users withdraw via queue
		vm.prank(alice);
		(uint256 vaultShares1, uint256 requestId1) = pstAVAX.withdrawViaQueue(assets1, 0);

		vm.prank(bob);
		(uint256 vaultShares2, uint256 requestId2) = pstAVAX.withdrawViaQueue(assets2, 0);

		assertGt(requestId2, requestId1);

		// Check both requests exist and are for correct users
		WithdrawQueue.UnstakeRequest memory request1 = withdrawQueue.getRequestInfo(requestId1);
		WithdrawQueue.UnstakeRequest memory request2 = withdrawQueue.getRequestInfo(requestId2);

		assertEq(request1.requester, alice);
		assertEq(request2.requester, bob);
		assertEq(request1.shares, vaultShares1);
		assertEq(request2.shares, vaultShares2);

		// Check that pstAVAX supply is now zero
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.balanceOf(bob), 0);
	}

	function testNoggAVAXHoldersBeforeRewards() public {
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertEq(ggAVAX.totalSupply(), 0);
		assertEq(ggAVAX.totalAssets(), 0);

		uint256 assets = 10 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		assertEq(pstAVAX.balanceOf(alice), assets);
		assertEq(pstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), assets);

		// vm.startPrank(cam);
		// ggAVAX.depositAVAX{value: assets}();
		// vm.stopPrank();

		// Deposit some rewards to ggAVAX
		vm.startPrank(bob);
		uint256 rewardsAmt = 10 ether;
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);
		vm.stopPrank();

		// Warp and sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		assertEq(ggAVAX.totalAssets(), assets + rewardsAmt);
		assertEq(ggAVAX.totalSupply(), assets);
		assertEq(ggAVAX.convertToShares(1 ether), 0.5 ether);

		// Because there are no other ggAVAX share holders, pstAVAX assumes it can strip
		// all yield. This is a known issue when there are no ggAVAX holders
		uint256 sharesStripped = pstAVAX.stripYield();
		assertEq(sharesStripped, assets);

		// Because all yield was stripped, this call will revert attempting to send
		// alice an appropraite number of ggAVAX shares
		vm.startPrank(alice);
		vm.expectRevert();
		uint256 sharesWithdrawn = pstAVAX.withdraw(assets);
		vm.stopPrank();
	}

	function testOneggAVAXHolderBeforeRewards() public {
		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertEq(ggAVAX.totalSupply(), 0);
		assertEq(ggAVAX.totalAssets(), 0);

		uint256 pstAVAXDeposit = 10 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: pstAVAXDeposit}();

		assertEq(pstAVAX.balanceOf(alice), pstAVAXDeposit);
		assertEq(pstAVAX.totalSupply(), pstAVAXDeposit);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), pstAVAXDeposit);

		vm.startPrank(cam);
		ggAVAX.depositAVAX{value: pstAVAXDeposit}();
		vm.stopPrank();

		// Deposit some rewards to ggAVAX
		vm.startPrank(bob);
		uint256 rewardsAmt = 10 ether;
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);
		vm.stopPrank();

		// Warp and sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		assertEq(ggAVAX.totalAssets(), pstAVAXDeposit + rewardsAmt + pstAVAXDeposit);
		assertEq(ggAVAX.totalSupply(), pstAVAXDeposit + pstAVAXDeposit);
		assertEq(ggAVAX.convertToShares(1 ether), ggAVAX.totalSupply().divWadDown(ggAVAX.totalAssets()));

		// Now there is another holder of ggAVAX, so the stippedShares will
		// not be the full amount of ggAVAX holding in pstAVAX
		uint256 sharesStripped = pstAVAX.stripYield();
		assertEq(sharesStripped, rewardsAmt / 2);

		// Alice gets enough ggAVAX back to cover her initial pstAVAX deposit
		vm.prank(alice);
		uint256 sharesWithdrawn = pstAVAX.withdraw(pstAVAXDeposit);
		assertEq(sharesWithdrawn, rewardsAmt / 2);
		assertEq(ggAVAX.convertToAssets(sharesWithdrawn), pstAVAXDeposit);
	}

	function testWithdrawalAffectsonExcessShares() public {
		// Test setup
		uint256 pstDeposit = 1000 ether;
		uint256 ggDeposit = 1000 ether;
		uint256 donation = 100 ether;

		address pstDepositor1 = makeAddr("pstDepositor1");
		vm.deal(pstDepositor1, 10 * ggDeposit);

		address pstDepositor2 = makeAddr("pstDepositor2");
		vm.deal(pstDepositor2, 10 * ggDeposit);

		address pstDepositor3 = makeAddr("pstDepositor3");
		vm.deal(pstDepositor3, 10 * ggDeposit);

		address donater = makeAddr("donater");
		vm.deal(donater, 10 * ggDeposit);

		address ggDepositor1 = makeAddr("ggDepositor1");
		vm.deal(ggDepositor1, 10 * ggDeposit);

		address ggDepositor2 = makeAddr("ggDepositor2");
		vm.deal(ggDepositor2, 10 * ggDeposit);

		assertEq(pstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(pstAVAX)), 0);
		assertEq(ggAVAX.totalSupply(), 0);
		assertEq(ggAVAX.totalAssets(), 0);

		vm.prank(pstDepositor1);
		pstAVAX.depositAVAX{value: pstDeposit}();
		assertEq(pstAVAX.balanceOf(pstDepositor1), pstDeposit);

		// Deposit avax into ggAVAX
		vm.prank(ggDepositor1);
		uint256 ggDepositor1Shares = ggAVAX.depositAVAX{value: ggDeposit}();

		assertEq(ggDepositor1Shares, ggDeposit);
		assertEq(ggAVAX.totalSupply(), ggDeposit + pstDeposit);

		// Donate some amout of rewards to ggAVAX
		vm.startPrank(donater);
		wavax.deposit{value: donation}();
		wavax.transfer(address(ggAVAX), donation);
		vm.stopPrank();

		// Warp and sync rewards
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		assertEq(ggAVAX.totalAssets(), ggDeposit + pstDeposit + donation);
		assertEq(ggAVAX.previewRedeem(1 ether), ggAVAX.totalAssets().divWadDown(ggAVAX.totalSupply()));

		uint256 expectedExcessShares = 90909090909090909090;
		assertGt(pstAVAX.getExcessShares(), 0);
		assertEq(pstAVAX.getExcessShares(), expectedExcessShares);

		vm.prank(pstDepositor1);
		uint256 ggAVAXsharesWithdrawnDepositor1 = pstAVAX.withdraw(pstDeposit);

		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAXsharesWithdrawnDepositor1), pstDeposit, 1);
		assertApproxEqAbs(pstAVAX.getExcessShares(), 0, 1);
		assertApproxEqAbs(pstAVAX.totalSupply(), 0, 1);
		assertApproxEqAbs(ggAVAX.balanceOf(address(pstAVAX)), 0, 1);
		assertEq(ggAVAX.totalSupply(), ggDeposit + pstDeposit - expectedExcessShares);

		uint256 sharesStripped = pstAVAX.stripYield();
		assertApproxEqAbs(sharesStripped, 0, 1);

		vm.prank(pstDepositor2);
		pstAVAX.depositAVAX{value: pstDeposit}();

		assertEq(pstAVAX.balanceOf(pstDepositor2), pstDeposit);
		assertEq(pstAVAX.totalSupply(), pstDeposit);
	}

	function testStripYieldGasMeasurement() public {
		// Setup scenario with yield to be stripped
		uint256 assets = 1000 ether;

		// Alice deposits into pstAVAX
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		// Bob deposits directly into ggAVAX (creates another holder)
		vm.prank(bob);
		ggAVAX.depositAVAX{value: assets}();

		// Skip time to allow for rewards
		skip(ggAVAX.rewardsCycleLength());

		// Add rewards to ggAVAX (simulate yield generation)
		vm.deal(address(ggAVAX), 1000 ether);
		vm.prank(address(ggAVAX));
		wavax.deposit{value: 1000 ether}();

		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());

		// Verify there are excess shares to strip
		uint256 excessShares = pstAVAX.getExcessShares();
		assertGt(excessShares, 0);

		// Measure gas for stripYield call
		uint256 gasBefore = gasleft();
		uint256 sharesStripped = pstAVAX.stripYield();
		uint256 gasUsed = gasBefore - gasleft();

		// Log gas usage for visibility
		// console2.log("Gas used for stripYield():", gasUsed);
		// console2.log("Shares stripped:", sharesStripped);

		// Verify the function worked
		assertEq(sharesStripped, excessShares);
		assertGt(sharesStripped, 0);
	}

	// Define events for testing (these match the contract events)
	event Deposited(address indexed user, uint256 avaxAmount, uint256 vaultShares);
	event Withdrawn(address indexed user, uint256 pstShares, uint256 vaultShares);
	event WithdrawnViaQueue(address indexed user, uint256 pstShares, uint256 vaultShares, uint256 requestId);
}

// Mock contract for testing invalid vault
contract MockContract {
	// Empty contract that doesn't implement IERC4626
}

// Mock ERC20 for testing recovery
contract MockERC20 {
	string public name;
	string public symbol;
	uint8 public decimals;
	uint256 public totalSupply;
	mapping(address => uint256) public balanceOf;
	mapping(address => mapping(address => uint256)) public allowance;

	constructor(string memory _name, string memory _symbol, uint8 _decimals) {
		name = _name;
		symbol = _symbol;
		decimals = _decimals;
	}

	function mint(address to, uint256 amount) external {
		balanceOf[to] += amount;
		totalSupply += amount;
	}

	function transfer(address to, uint256 amount) external returns (bool) {
		balanceOf[msg.sender] -= amount;
		balanceOf[to] += amount;
		return true;
	}

	function transferFrom(address from, address to, uint256 amount) external returns (bool) {
		allowance[from][msg.sender] -= amount;
		balanceOf[from] -= amount;
		balanceOf[to] += amount;
		return true;
	}

	function approve(address spender, uint256 amount) external returns (bool) {
		allowance[msg.sender][spender] = amount;
		return true;
	}
}
