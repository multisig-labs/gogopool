// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {TokenlstAVAX} from "../../contracts/contract/tokens/TokenlstAVAX.sol";
import {WithdrawQueue} from "../../contracts/contract/WithdrawQueue.sol";
import {console2} from "forge-std/console2.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract TokenlstAVAXTest is BaseTest {
	using FixedPointMathLib for uint256;

	TokenlstAVAX lstAVAX;
	WithdrawQueue withdrawQueue;
	address alice;
	address bob;
	address cam;
	address treasury;

	function setUp() public virtual override {
		super.setUp();

		alice = getActorWithTokens("alice", MAX_AMT, MAX_AMT);
		bob = getActorWithTokens("bob", MAX_AMT, MAX_AMT);
		cam = getActorWithTokens("cam", MAX_AMT, MAX_AMT);
		treasury = getActor("treasury");

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
		TokenlstAVAX lstAVAXImpl = new TokenlstAVAX();
		bytes memory initData = abi.encodeWithSelector(TokenlstAVAX.initialize.selector, address(ggAVAX), address(withdrawQueue), address(treasury));
		TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(address(lstAVAXImpl), address(proxyAdmin), initData);
		lstAVAX = TokenlstAVAX(payable(address(proxy)));
	}

	function testSetup() public {
		assertEq(lstAVAX.vault(), address(ggAVAX));
		assertEq(lstAVAX.underlyingAsset(), address(ggAVAX.asset()));
		assertEq(lstAVAX.withdrawQueue(), address(withdrawQueue));
		assertEq(lstAVAX.treasury(), address(treasury));
	}

	function testDeposit() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();
		assertEq(lstAVAX.balanceOf(alice), assets);
		assertEq(lstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), assets);

		vm.prank(alice);
		lstAVAX.withdraw(assets);
		assertEq(lstAVAX.balanceOf(alice), 0);
		assertEq(lstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), 0);
		assertEq(ggAVAX.balanceOf(alice), assets);
	}

	function testDepositWithReceive() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		(bool sent, ) = payable(address(lstAVAX)).call{value: assets}("");
		require(sent, "Failed to send AVAX");
		assertEq(lstAVAX.balanceOf(alice), assets);
		assertEq(lstAVAX.totalSupply(), assets);
		assertEq(address(lstAVAX).balance, 0);
	}

	function testStripYieldWithggAVAXHolder() public {
		uint256 assets = 1000 ether;
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();
		uint256 excessShares = lstAVAX.getExcessShares();
		assertEq(excessShares, 0);

		skip(ggAVAX.rewardsCycleLength());

		// now deposit more WAVAX as rewards
		vm.deal(address(ggAVAX), 50 ether);
		vm.prank(address(ggAVAX));
		wavax.deposit{value: 50 ether}();

		ggAVAX.syncRewards();
		skip(ggAVAX.rewardsCycleLength());

		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(lstAVAX))), 1000 ether + 50 ether);

		excessShares = lstAVAX.stripYield();
		assertEq(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(lstAVAX))), 1000 ether);
		assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(treasury))), 50 ether, 1);

		// // // Bob gets 50% of the yield, lstAVAX gets 0%, treasury gets 50%
		// assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(bob)), assets.mulWadDown(newSharePrice), 1000);
		// assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(lstAVAX))), 1000 ether, 1);

		// assertApproxEqAbs(ggAVAX.convertToAssets(ggAVAX.balanceOf(address(lstAVAX))), lstAVAX.totalSupply(), 1);

		// // Alice withdraws her 1000 lstAVAX tokens
		// vm.prank(alice);
		// uint256 sharesReceived = lstAVAX.withdraw(1000 ether);
		// uint256 aliceValueReceived = ggAVAX.convertToAssets(sharesReceived);
		// assertApproxEqAbs(aliceValueReceived, 1000 ether, 1);

		// uint256 assetsLeft = ggAVAX.convertToAssets(ggAVAX.balanceOf(address(lstAVAX)));
		// assertApproxEqAbs(assetsLeft, 0, 2);
	}

	// Additional deposit tests
	function testDepositWAVAX() public {
		uint256 assets = 2 ether;

		vm.startPrank(alice);
		wavax.deposit{value: assets}();
		wavax.approve(address(lstAVAX), assets);
		lstAVAX.deposit(assets);
		vm.stopPrank();

		assertEq(lstAVAX.balanceOf(alice), assets);
		assertEq(lstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), assets);
	}

	function testDepositZeroAmount() public {
		vm.expectRevert(TokenlstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		lstAVAX.depositAVAX{value: 0}();

		vm.expectRevert(TokenlstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		lstAVAX.deposit(0);
	}

	function testMultipleDeposits() public {
		uint256 assets1 = 1 ether;
		uint256 assets2 = 2 ether;

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets1}();

		vm.prank(bob);
		lstAVAX.depositAVAX{value: assets2}();

		assertEq(lstAVAX.balanceOf(alice), assets1);
		assertEq(lstAVAX.balanceOf(bob), assets2);
		assertEq(lstAVAX.totalSupply(), assets1 + assets2);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), assets1 + assets2);
	}

	function testInitializeWithZeroVault() public {
		TokenlstAVAX lstAVAXImpl = new TokenlstAVAX();
		bytes memory initData = abi.encodeWithSelector(TokenlstAVAX.initialize.selector, address(0), address(withdrawQueue), address(treasury));

		vm.expectRevert(TokenlstAVAX.ZeroAddress.selector);
		new TransparentUpgradeableProxy(address(lstAVAXImpl), address(proxyAdmin), initData);
	}

	function testInitializeWithNonERC4626Contract() public {
		TokenlstAVAX lstAVAXImpl = new TokenlstAVAX();
		address nonERC4626 = address(new MockContract());
		bytes memory initData = abi.encodeWithSelector(TokenlstAVAX.initialize.selector, nonERC4626, address(withdrawQueue), address(treasury));

		vm.expectRevert();
		new TransparentUpgradeableProxy(address(lstAVAXImpl), address(proxyAdmin), initData);
	}

	function testSetPaused() public {
		assertFalse(lstAVAX.paused());

		lstAVAX.setPaused(true);
		assertTrue(lstAVAX.paused());

		lstAVAX.setPaused(false);
		assertFalse(lstAVAX.paused());
	}

	function testSetPausedOnlyOwner() public {
		vm.expectRevert("Ownable: caller is not the owner");
		vm.prank(alice);
		lstAVAX.setPaused(true);
	}

	function testDepositWhenPaused() public {
		lstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		lstAVAX.depositAVAX{value: 1 ether}();

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		lstAVAX.deposit(1 ether);
	}

	function testWithdrawWhenPaused() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		lstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		lstAVAX.withdraw(assets);
	}

	function testStripYieldWhenPaused() public {
		uint256 assets = 1 ether;
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		lstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		lstAVAX.stripYield();
	}

	function testReceiveWhenPaused() public {
		lstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		payable(address(lstAVAX)).call{value: 1 ether}("");
	}

	function testRecoverERC20Safe() public {
		// Deploy a mock ERC20 token
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);
		uint256 amount = 100 ether;
		mockToken.mint(address(lstAVAX), amount);

		uint256 ownerBalanceBefore = mockToken.balanceOf(lstAVAX.owner());

		lstAVAX.recoverERC20Safe(address(mockToken), amount);

		assertEq(mockToken.balanceOf(address(lstAVAX)), 0);
		assertEq(mockToken.balanceOf(lstAVAX.owner()), ownerBalanceBefore + amount);
	}

	function testRecoverERC20SafeZeroAmount() public {
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);
		uint256 amount = 100 ether;
		mockToken.mint(address(lstAVAX), amount);

		uint256 ownerBalanceBefore = mockToken.balanceOf(lstAVAX.owner());

		// Pass 0 to recover all tokens
		lstAVAX.recoverERC20Safe(address(mockToken), 0);

		assertEq(mockToken.balanceOf(address(lstAVAX)), 0);
		assertEq(mockToken.balanceOf(lstAVAX.owner()), ownerBalanceBefore + amount);
	}

	function testRecoverERC20SafeOnlyOwner() public {
		MockERC20 mockToken = new MockERC20("Mock", "MOCK", 18);

		vm.expectRevert("Ownable: caller is not the owner");
		vm.prank(alice);
		lstAVAX.recoverERC20Safe(address(mockToken), 100 ether);
	}

	function testCannotRecoverUnderlyingAsset() public {
		vm.expectRevert("Cannot recover underlying asset");
		lstAVAX.recoverERC20Safe(address(wavax), 100 ether);
	}

	function testCannotRecoverVaultShares() public {
		vm.expectRevert("Cannot recover vault shares");
		lstAVAX.recoverERC20Safe(address(ggAVAX), 100 ether);
	}

	// Withdraw error tests
	function testWithdrawZeroAmount() public {
		vm.expectRevert(TokenlstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		lstAVAX.withdraw(0);
	}

	function testWithdrawInsufficientBalance() public {
		vm.expectRevert(TokenlstAVAX.InsufficientBalance.selector);
		vm.prank(alice);
		lstAVAX.withdraw(1 ether);
	}

	function testStripYieldNoYield() public {
		uint256 excessShares = lstAVAX.stripYield();
		assertEq(excessShares, 0);
	}

	function testDepositEvent() public {
		uint256 assets = 1 ether;

		vm.expectEmit(true, false, false, true, address(lstAVAX));
		emit Deposited(alice, assets, assets);

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();
	}

	function testWithdrawEvent() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		uint256 expectedShares = ggAVAX.convertToShares(assets);

		vm.expectEmit(true, false, false, true, address(lstAVAX));
		emit Withdrawn(alice, assets, expectedShares);

		vm.prank(alice);
		lstAVAX.withdraw(assets);
	}

	function testWithdrawViaQueue() public {
		uint256 assets = 100 ether;

		// Deposit first
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		uint256 aliceBalanceBefore = lstAVAX.balanceOf(alice);
		uint256 expectedVaultShares = ggAVAX.convertToShares(assets);

		// Withdraw via queue
		vm.prank(alice);
		(uint256 vaultShares, uint256 requestId) = lstAVAX.withdrawViaQueue(assets, 0);

		// Check return values
		assertEq(vaultShares, expectedVaultShares);

		// Check lstAVAX balance was burned
		assertEq(lstAVAX.balanceOf(alice), aliceBalanceBefore - assets);
		assertEq(lstAVAX.totalSupply(), 0);

		// Check that request was created in WithdrawQueue
		WithdrawQueue.UnstakeRequest memory request = withdrawQueue.getRequestInfo(requestId);
		assertEq(request.requester, alice);
		assertEq(request.shares, vaultShares);
		assertEq(request.expectedAssets, ggAVAX.convertToAssets(vaultShares));

		// Check that WithdrawQueue has the ggAVAX shares
		assertEq(ggAVAX.balanceOf(address(withdrawQueue)), vaultShares);
	}

	function testWithdrawViaQueueZeroAmount() public {
		vm.expectRevert(TokenlstAVAX.ZeroAmount.selector);
		vm.prank(alice);
		lstAVAX.withdrawViaQueue(0, 0);
	}

	function testWithdrawViaQueueInsufficientBalance() public {
		vm.expectRevert(TokenlstAVAX.InsufficientBalance.selector);
		vm.prank(alice);
		lstAVAX.withdrawViaQueue(1 ether, 0);
	}

	function testWithdrawViaQueueWhenPaused() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		lstAVAX.setPaused(true);

		vm.expectRevert("Pausable: paused");
		vm.prank(alice);
		lstAVAX.withdrawViaQueue(assets, 0);
	}

	function testWithdrawViaQueueEvent() public {
		uint256 assets = 1 ether;

		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		uint256 expectedVaultShares = ggAVAX.convertToShares(assets);
		uint256 expectedRequestId = 0;

		vm.expectEmit(true, false, false, true, address(lstAVAX));
		emit WithdrawnViaQueue(alice, assets, expectedVaultShares, expectedRequestId);

		vm.prank(alice);
		lstAVAX.withdrawViaQueue(assets, 0);
	}

	function testWithdrawViaQueueMultipleUsers() public {
		uint256 assets1 = 1 ether;
		uint256 assets2 = 2 ether;

		// Both users deposit
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets1}();

		vm.prank(bob);
		lstAVAX.depositAVAX{value: assets2}();

		// Both users withdraw via queue
		vm.prank(alice);
		(uint256 vaultShares1, uint256 requestId1) = lstAVAX.withdrawViaQueue(assets1, 0);

		vm.prank(bob);
		(uint256 vaultShares2, uint256 requestId2) = lstAVAX.withdrawViaQueue(assets2, 0);

		assertGt(requestId2, requestId1);

		// Check both requests exist and are for correct users
		WithdrawQueue.UnstakeRequest memory request1 = withdrawQueue.getRequestInfo(requestId1);
		WithdrawQueue.UnstakeRequest memory request2 = withdrawQueue.getRequestInfo(requestId2);

		assertEq(request1.requester, alice);
		assertEq(request2.requester, bob);
		assertEq(request1.shares, vaultShares1);
		assertEq(request2.shares, vaultShares2);

		// Check that lstAVAX supply is now zero
		assertEq(lstAVAX.totalSupply(), 0);
		assertEq(lstAVAX.balanceOf(alice), 0);
		assertEq(lstAVAX.balanceOf(bob), 0);
	}

	function testNoggAVAXHoldersBeforeRewards() public virtual {
		assertEq(lstAVAX.totalSupply(), 0);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), 0);
		assertEq(ggAVAX.totalSupply(), 0);
		assertEq(ggAVAX.totalAssets(), 0);

		uint256 assets = 10 ether;
		vm.prank(alice);
		lstAVAX.depositAVAX{value: assets}();

		assertEq(lstAVAX.balanceOf(alice), assets);
		assertEq(lstAVAX.totalSupply(), assets);
		assertEq(ggAVAX.balanceOf(address(lstAVAX)), assets);

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

		// Because there are no other ggAVAX share holders, lstAVAX assumes it can strip
		// all yield. This is a known issue when there are no ggAVAX holders
		uint256 excessShares = lstAVAX.stripYield();
		uint256 sharesStripped = excessShares;
		assertEq(sharesStripped, assets);

		// Because all yield was stripped, this call will revert attempting to send
		// alice an appropraite number of ggAVAX shares
		vm.startPrank(alice);
		vm.expectRevert();
		uint256 sharesWithdrawn = lstAVAX.withdraw(assets);
		vm.stopPrank();
	}

	/// @notice Calculate expected share price after stripYield
	/// @param totalAssetsBefore Total assets in ggAVAX before stripYield
	/// @param totalSharesBefore Total shares in ggAVAX before stripYield
	function calculateExpectedSharePrice(uint256 totalAssetsBefore, uint256 totalSharesBefore) internal view returns (uint256 expectedSharePrice) {
		uint256 excessShares = lstAVAX.getExcessShares();

		uint256 newTotalShares = totalSharesBefore - excessShares;
		expectedSharePrice = totalAssetsBefore.mulDivDown(1e18, newTotalShares);
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
