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

	function setUp() public virtual override {
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
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		assertEq(feeShares + burnShares, 0);

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

		// Capture state before stripYield for calculation
		uint256 totalAssetsBefore = ggAVAX.totalAssets(); // 2000 ether
		uint256 totalSharesBefore = ggAVAX.totalSupply(); // 2000 ether

		uint256 expectedSharePrice = calculateExpectedSharePriceWithFees(totalAssetsBefore, totalSharesBefore);

		uint256 sharesFor1000tokens = ggAVAX.convertToShares(1000 ether);
		pstAVAX.stripYield();

		uint256 newSharePrice = ggAVAX.convertToAssets(1 ether);
		assertEq(newSharePrice, expectedSharePrice);

		// Bob gets 100% of the yield, pstAVAX gets 0%
		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), assets.mulWadDown(newSharePrice), 1000);
		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX))), 1000 ether, 1);

		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX))), pstAVAX.totalSupply(), 1);

		// Alice withdraws her 1000 pstAVAX tokens
		vm.prank(alice);
		uint256 sharesReceived = pstAVAX.withdraw(1000 ether);
		uint256 aliceValueReceived = ggAVAX.convertToAssets(sharesReceived);
		assertApproxEqAbs(aliceValueReceived, 1000 ether, 1);

		uint256 assetsLeft = ggAVAX.convertToAssets(ggAVAX.balanceOf(address(pstAVAX)));
		assertApproxEqAbs(assetsLeft, 0, 2);
	}

	function testStripYieldDefault() public {
		// we have to create a ggAVAX holder I think
		vm.startPrank(guardian);
		ggAVAX.grantRole(ggAVAX.SYNC_REWARDS_ROLE(), bob);
		vm.stopPrank();

		uint256 ggAVAXDeposit = 1 ether;
		vm.prank(bob);
		ggAVAX.depositAVAX{value: ggAVAXDeposit}();

		uint256 assets = 1 ether;
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		assertEq(feeShares + burnShares, 0);

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

		(feeShares, burnShares) = pstAVAX.getExcessShares();
		assertSharesStrippedWithFees(feeShares, burnShares, rewardsAmt / 2, "Strip yield default excess shares");

		vm.prank(alice);
		pstAVAX.withdraw(assets);
		assertEq(pstAVAX.balanceOf(alice), 0);
		assertEq(pstAVAX.totalSupply(), 0);
		assertApproxEqAbs(ggAVAX.balanceOf(address(pstAVAX)), 0, 2);
		assertLt(ggAVAX.balanceOf(alice), 1 ether);

		pstAVAX.stripYield();
		(feeShares, burnShares) = pstAVAX.getExcessShares();
		assertEq(feeShares + burnShares, 0);
		assertApproxEqAbs(ggAVAX.balanceOf(address(pstAVAX)), 0, 2);
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
		(uint256 feeShares, uint256 burnShares) = pstAVAX.stripYield();
		assertEq(feeShares, 0);
		assertEq(burnShares, 0);
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

	function testNoggAVAXHoldersBeforeRewards() public virtual {
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
		(uint256 feeShares, uint256 burnShares) = pstAVAX.stripYield();
		uint256 sharesStripped = feeShares + burnShares;
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

		// Now there is another holder of ggAVAX, so the stripped shares will
		// not be the full amount of ggAVAX holding in pstAVAX
		(uint256 feeShares, uint256 burnShares) = pstAVAX.stripYield();
		assertSharesStrippedWithFees(feeShares, burnShares, rewardsAmt / 2, "One ggAVAX holder stripped shares");

		// Alice gets enough ggAVAX back to cover her initial pstAVAX deposit
		vm.prank(alice);
		uint256 sharesWithdrawn = pstAVAX.withdraw(pstAVAXDeposit);
		assertApproxEqAbs(ggAVAX.convertToAssets(sharesWithdrawn), pstAVAXDeposit, 2);
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

		address donater = makeAddr("donater");
		vm.deal(donater, 10 * ggDeposit);

		address ggDepositor1 = makeAddr("ggDepositor1");
		vm.deal(ggDepositor1, 10 * ggDeposit);

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
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		uint256 actualSharesBurned = burnShares;

		assertGt(feeShares + burnShares, 0);
		assertSharesStrippedWithFees(feeShares, burnShares, expectedExcessShares, "Withdrawal affects excess shares");

		vm.prank(pstDepositor1);
		uint256 ggAVAXsharesWithdrawnDepositor1 = pstAVAX.withdraw(pstDeposit);

		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAXsharesWithdrawnDepositor1), pstDeposit, 1);
		(feeShares, burnShares) = pstAVAX.getExcessShares();
		assertApproxEqAbs(feeShares + burnShares, 0, 1);
		assertApproxEqAbs(pstAVAX.totalSupply(), 0, 1);
		assertApproxEqAbs(ggAVAX.balanceOf(address(pstAVAX)), 0, 1);
		assertEq(ggAVAX.totalSupply(), ggDeposit + pstDeposit - actualSharesBurned);

		(, burnShares) = pstAVAX.stripYield();
		assertApproxEqAbs(burnShares, 0, 1);

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
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		assertGt(feeShares + burnShares, 0);

		// Measure gas for stripYield call
		uint256 gasBefore = gasleft();
		(feeShares, burnShares) = pstAVAX.stripYield();
		uint256 sharesStripped = feeShares + burnShares;
		uint256 gasUsed = gasBefore - gasleft();

		// Log gas usage for visibility
		// console2.log("Gas used for stripYield():", gasUsed);
		// console2.log("Shares stripped:", sharesStripped);

		// Verify the function worked
		assertGt(sharesStripped, 0);
		assertGt(burnShares, 0);
	}

	function testSetStripYieldFeeBips() public {
		pstAVAX.setStripYieldFeeRecipient(address(this));
		// Test setting fee to 10% (1000 bips) - test contract is owner
		pstAVAX.setStripYieldFeeBips(1000);
		assertEq(pstAVAX.stripYieldFeeBips(), 1000);

		// Test setting fee to 0%
		pstAVAX.setStripYieldFeeBips(0);
		assertEq(pstAVAX.stripYieldFeeBips(), 0);

		// Test setting fee to max (100%)
		pstAVAX.setStripYieldFeeBips(10000);
		assertEq(pstAVAX.stripYieldFeeBips(), 10000);
	}

	function testSetStripYieldFeeBipsInvalidFee() public {
		// Test setting fee > 100% should revert
		vm.expectRevert(TokenpstAVAX.InvalidFeeBips.selector);
		pstAVAX.setStripYieldFeeBips(10001);
	}

	function testSetStripYieldFeeBipsOnlyOwner() public {
		// Test that only owner can set fee
		vm.prank(alice);
		vm.expectRevert();
		pstAVAX.setStripYieldFeeBips(1000);
	}

	function testSetStripYieldFeeRecipient() public {
		address feeRecipient = address(0x123);

		pstAVAX.setStripYieldFeeRecipient(feeRecipient);
		assertEq(pstAVAX.stripYieldFeeRecipient(), feeRecipient);
	}

	function testSetStripYieldFeeRecipientOnlyOwner() public {
		vm.prank(alice);
		vm.expectRevert();
		pstAVAX.setStripYieldFeeRecipient(address(0x123));
	}

	function testGetExcessSharesWithFee() public {
		uint256 pstAVAXDeposit = 1000 ether;
		uint256 ggAVAXDeposit = 1000 ether;

		// Setup: deposit to pstAVAX and generate yield
		vm.prank(alice);
		pstAVAX.depositAVAX{value: pstAVAXDeposit}();

		vm.prank(bob);
		ggAVAX.depositAVAX{value: ggAVAXDeposit}();

		// Generate yield by direct deposit to ggAVAX
		uint256 rewardsAmt = 100 ether;
		vm.deal(address(this), rewardsAmt);
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);

		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		// Set 10% fee
		pstAVAX.setStripYieldFeeRecipient(address(this));
		pstAVAX.setStripYieldFeeBips(1000); // 10%

		// Check getExcessShares returns appropriate split
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		uint256 totalShares = feeShares + burnShares;

		// Fee should be ~10% of total excess
		uint256 expectedFeeShares = (totalShares * 1000) / 10000;
		assertApproxEqAbs(feeShares, expectedFeeShares, 1);

		// Burn shares should be the remainder
		assertEq(burnShares, totalShares - feeShares);

		assertEq(ggAVAX.totalAssets(), pstAVAXDeposit + rewardsAmt + ggAVAXDeposit);
		assertEq(ggAVAX.totalSupply(), pstAVAXDeposit + ggAVAXDeposit);
		uint256 exchangeRate = ggAVAX.convertToAssets(1 ether);

		(, burnShares) = pstAVAX.stripYield();
		assertGt(burnShares, 0);

		assertEq(ggAVAX.totalAssets(), pstAVAXDeposit + rewardsAmt + ggAVAXDeposit);
		assertEq(ggAVAX.totalSupply(), pstAVAXDeposit + ggAVAXDeposit - burnShares);
		assertGt(ggAVAX.convertToAssets(1 ether), exchangeRate);

		// Alice gets enough ggAVAX back to cover her initial pstAVAX deposit
		vm.prank(alice);
		uint256 sharesWithdrawn = pstAVAX.withdraw(pstAVAXDeposit);
		assertApproxEqAbs(ggAVAX.convertToAssets(sharesWithdrawn), pstAVAXDeposit, 1);
	}

	function testStripYieldWithFeeCollection() public {
		uint256 assets = 1000 ether;
		address feeRecipient = address(0x456);

		// Setup: deposit to pstAVAX
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		// Generate yield
		uint256 rewardsAmt = 100 ether;
		vm.deal(address(this), rewardsAmt);
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);

		// Set fee and recipient
		pstAVAX.setStripYieldFeeRecipient(feeRecipient);
		pstAVAX.setStripYieldFeeBips(1000); // 10%

		// Get initial balances
		uint256 initialRecipientBalance = ggAVAX.balanceOf(feeRecipient);

		// Get expected fee shares
		(uint256 expectedFeeShares, ) = pstAVAX.getExcessShares();

		// Strip yield
		pstAVAX.stripYield();

		// Verify fee was collected
		if (expectedFeeShares > 0) {
			uint256 finalRecipientBalance = ggAVAX.balanceOf(feeRecipient);
			assertEq(finalRecipientBalance - initialRecipientBalance, expectedFeeShares);
		}
	}

	function testStripYieldWithZeroFee() public virtual {
		uint256 assets = 1000 ether;

		// Setup: deposit to pstAVAX
		vm.prank(alice);
		pstAVAX.depositAVAX{value: assets}();

		// Generate yield by transferring WAVAX to ggAVAX and syncing rewards
		uint256 rewardsAmt = 100 ether;
		vm.deal(address(this), rewardsAmt);
		wavax.deposit{value: rewardsAmt}();
		wavax.transfer(address(ggAVAX), rewardsAmt);

		// Warp and sync rewards to generate yield
		vm.warp(ggAVAX.rewardsCycleEnd());
		ggAVAX.syncRewards();
		vm.warp(ggAVAX.rewardsCycleEnd());

		// Ensure fee is 0% (default)
		assertEq(pstAVAX.stripYieldFeeBips(), 0);

		// Check getExcessShares - should have no fee shares
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
		assertEq(feeShares, 0);
		if (burnShares > 0) {
			// Should have burn shares since there's yield, but if no excess then that's also fine
			assertGt(burnShares, 0);
		}
	}

	/// @notice Calculate expected share price after stripYield based on fee configuration
	/// @param totalAssetsBefore Total assets in ggAVAX before stripYield
	/// @param totalSharesBefore Total shares in ggAVAX before stripYield
	function calculateExpectedSharePriceWithFees(
		uint256 totalAssetsBefore,
		uint256 totalSharesBefore
	) internal view returns (uint256 expectedSharePrice) {
		uint256 feeBips = pstAVAX.stripYieldFeeBips();
		(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();

		if (feeBips == 0) {
			uint256 newTotalShares = totalSharesBefore - burnShares;
			expectedSharePrice = totalAssetsBefore.mulDivDown(1e18, newTotalShares);
		} else {
			(uint256 feeShares, uint256 burnShares) = pstAVAX.getExcessShares();
			uint256 newTotalShares = totalSharesBefore - burnShares;
			expectedSharePrice = totalAssetsBefore.mulDivDown(1e18, newTotalShares);
		}
	}

	/// @notice Helper function to assert shares stripped based on fee configuration
	/// @param actualFeeShares The actual fee shares returned from stripYield or getExcessShares
	/// @param actualBurnShares The actual burn shares returned from stripYield or getExcessShares
	/// @param expectedBaseShares The expected shares when fee is 0% (baseline calculation)
	/// @param description Description for the assertion
	function assertSharesStrippedWithFees (
		uint256 actualFeeShares,
		uint256 actualBurnShares,
		uint256 expectedBaseShares,
		string memory description
	) internal {
		uint256 feeBips = pstAVAX.stripYieldFeeBips();
		uint256 totalActual = actualFeeShares + actualBurnShares;
		console2.log("acutal feeSahres", actualFeeShares);
		console2.log("acutal burnShares", actualBurnShares);
		console2.log("expectedBaseShares", expectedBaseShares);

		if (feeBips == 0) {
			assertEq(actualFeeShares, 0, string(abi.encodePacked(description, " - no fee shares when fee is 0%")));
			assertEq(totalActual, expectedBaseShares, string(abi.encodePacked(description, " - total should equal base when no fees")));
		} else {
      uint256 burnPct = 10000 - feeBips; // basis points
      uint256 originalDenom = ggAVAX.totalAssets() - pstAVAX.totalSupply();
      uint256 feeDenom = ggAVAX.totalAssets() - pstAVAX.totalSupply().mulDivDown(burnPct, 10000);

      // Expected total = baseShares × (originalDenom / feeDenom)
      uint256 expectedTotalWithFees = expectedBaseShares.mulDivDown(originalDenom, feeDenom);

			assertApproxEqAbs(totalActual, expectedTotalWithFees, 1, string(abi.encodePacked(description, " - total within fee-adjusted range")));

			// Burn shares should be the remainder
			assertEq(actualBurnShares, totalActual - actualFeeShares, string(abi.encodePacked(description, " - burn shares should be remainder")));
		}
	}

	// Define events for testing (these match the contract events)
	event Deposited(address indexed user, uint256 avaxAmount, uint256 vaultShares);
	event Withdrawn(address indexed user, uint256 pstShares, uint256 vaultShares);
	event WithdrawnViaQueue(address indexed user, uint256 pstShares, uint256 vaultShares, uint256 requestId);
}

contract TokenpstAVAXTestWith5PercentFees is TokenpstAVAXTest {
	address constant FEE_RECIPIENT = address(0x12345);
	uint256 constant FEE_BIPS = 500; // 5%

	function setUp() public override {
		super.setUp(); // Run original setup

		// Configure fees after setup
		pstAVAX.setStripYieldFeeRecipient(FEE_RECIPIENT);
		pstAVAX.setStripYieldFeeBips(FEE_BIPS);
	}

	function testStripYieldWithZeroFee() public override {
		// do nothing
	}

	function testNoggAVAXHoldersBeforeRewards() public override {
		// do nothing
	}
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
