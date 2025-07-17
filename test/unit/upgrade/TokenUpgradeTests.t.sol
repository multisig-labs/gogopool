// file for testing erc20upgradeable upgrades

pragma solidity 0.8.17;

import "../utils/BaseTest.sol";

import {MockTokenggAVAXV2} from "../utils/MockTokenggAVAXV2.sol";
import {MockTokenggAVAXV2Dangerous} from "../utils/MockTokenggAVAXV2Dangerous.sol";
import {MockTokenggAVAXV2Safe} from "../utils/MockTokenggAVAXV2Safe.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {TokenggAVAX as TokenggAVAXV1} from "../../../contracts/contract/previousVersions/TokenggAVAXV1.sol";
import {TokenggAVAX as TokenggAVAXV2} from "../../../contracts/contract/previousVersions/TokenggAVAXV2.sol";
import {TokenggAVAX} from "../../../contracts/contract/tokens/TokenggAVAX.sol";
import {ERC20} from "@rari-capital/solmate/src/tokens/ERC20.sol";
import {Timelock} from "../../../contracts/contract/Timelock.sol";

contract TokenUpgradeTests is BaseTest {
	address public constant DEPLOYER = address(12345);

	function setUp() public override {
		super.setUp();
	}

	function testDeployTransparentProxy() public {
		// deploy token contract
		vm.startPrank(DEPLOYER);

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAX ggAVAXImpl = new TokenggAVAX();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImpl.initialize.selector, store, wavax, 0)
		);
		TokenggAVAX token = TokenggAVAX(payable(address(ggAVAXProxy)));

		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImpl));

		// Xfer admin of proxy to guardian from deployer
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();
		assertEq(proxyAdmin.owner(), guardian);

		// verify token works
		address alice = getActorWithTokens("alice", 100 ether, 0);
		vm.deal(alice, MAX_AMT);
		vm.startPrank(alice);
		uint256 shareAmount = token.depositAVAX{value: 100 ether}();
		assertEq(shareAmount, 100 ether);
		assertEq(token.totalAssets(), 100 ether);
		assertEq(token.balanceOf(alice), 100 ether);
		vm.stopPrank();
		assertEq(proxyAdmin.owner(), guardian);

		// upgrade contract
		vm.prank(DEPLOYER);
		MockTokenggAVAXV2 ggAVAXImplV2 = new MockTokenggAVAXV2();

		vm.prank(guardian);
		proxyAdmin.upgrade(ggAVAXProxy, address(ggAVAXImplV2));

		// Verify data is still there
		assertEq(shareAmount, 100 ether);
		assertEq(token.totalAssets(), 100 ether);
		assertEq(token.balanceOf(alice), 100 ether);

		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImplV2));
	}

	function testDomainSeparatorBetweenVersions() public {
		// initialize token
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAX impl = new TokenggAVAX();

		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(impl),
			address(proxyAdmin),
			abi.encodeWithSelector(impl.initialize.selector, store, wavax, 0)
		);

		TokenggAVAX proxy = TokenggAVAX(payable(address(transparentProxy)));

		// Xfer admin of proxy to guardian from deployer
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();

		bytes32 oldSeparator = proxy.DOMAIN_SEPARATOR();
		address oldAddress = address(proxy);
		string memory oldName = proxy.name();

		// upgrade implementation
		vm.prank(DEPLOYER);
		MockTokenggAVAXV2 impl2 = new MockTokenggAVAXV2();

		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(transparentProxy, address(impl2), abi.encodeWithSelector(impl2.initialize.selector, store, wavax, 0));

		assertFalse(proxy.DOMAIN_SEPARATOR() == oldSeparator);
		assertEq(address(proxy), oldAddress);
		assertEq(proxy.name(), oldName);
	}

	function testStorageGapDangerouslySet() public {
		// initialize token
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAX impl = new TokenggAVAX();

		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(impl),
			address(proxyAdmin),
			abi.encodeWithSelector(impl.initialize.selector, store, wavax, 0)
		);

		TokenggAVAX proxy = TokenggAVAX(payable(address(transparentProxy)));

		// Xfer admin of proxy to guardian from deployer
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();

		// add some rewards to make sure error error occurs
		address alice = getActorWithTokens("alice", 1000 ether, 0 ether);
		vm.prank(alice);
		wavax.transfer(address(proxy), 1000 ether);
		proxy.syncRewards();

		uint256 oldLastSync = proxy.lastSync();
		bytes32 oldDomainSeparator = proxy.DOMAIN_SEPARATOR();

		// upgrade implementation
		vm.prank(DEPLOYER);
		MockTokenggAVAXV2Dangerous impl2 = new MockTokenggAVAXV2Dangerous();

		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(transparentProxy, address(impl2), abi.encodeWithSelector(impl2.initialize.selector, store, wavax, 0));

		// now lastSync is reading four bytes of lastRewardsAmt
		assertFalse(proxy.lastSync() == oldLastSync);

		// domain separator also does not change but should during regular upgrade
		assertEq(proxy.DOMAIN_SEPARATOR(), oldDomainSeparator);
	}

	function testStorageGapSafe() public {
		// initialize token
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAX impl = new TokenggAVAX();

		TransparentUpgradeableProxy transparentProxy = new TransparentUpgradeableProxy(
			address(impl),
			address(proxyAdmin),
			abi.encodeWithSelector(impl.initialize.selector, store, wavax, 0)
		);

		TokenggAVAX proxy = TokenggAVAX(payable(address(transparentProxy)));

		// Xfer admin of proxy to guardian from deployer
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();

		proxy.syncRewards();
		uint256 oldLastSync = proxy.lastSync();
		bytes32 oldDomainSeparator = proxy.DOMAIN_SEPARATOR();

		// upgrade implementation
		vm.prank(DEPLOYER);
		MockTokenggAVAXV2Safe impl2 = new MockTokenggAVAXV2Safe();
		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(transparentProxy, address(impl2), abi.encodeWithSelector(impl2.initialize.selector, store, wavax, 0));

		// verify that lastSync is not overwritten during upgrade
		assertEq(proxy.lastSync(), oldLastSync);
		// verify domain separator changes
		assertFalse(proxy.DOMAIN_SEPARATOR() == oldDomainSeparator);
	}

	function testDeployInitializeAndBadAddress() public {
		// deploy token contract
		vm.startPrank(DEPLOYER);

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAX ggAVAXImpl = new TokenggAVAX();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImpl.initialize.selector, store, wavax, 0)
		);
		TokenggAVAX token = TokenggAVAX(payable(address(ggAVAXProxy)));

		vm.expectRevert("Initializable: contract is already initialized");
		ggAVAX.initialize(store, wavax, 0);

		// Xfer admin of proxy to guardian from deployer
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();
		assertEq(proxyAdmin.owner(), guardian);

		// verify token works
		address alice = getActorWithTokens("alice", 100 ether, 0);
		vm.deal(alice, MAX_AMT);
		vm.startPrank(alice);
		uint256 shareAmount = token.depositAVAX{value: 100 ether}();
		assertEq(shareAmount, 100 ether);
		assertEq(token.totalAssets(), 100 ether);
		assertEq(token.balanceOf(alice), 100 ether);
		vm.stopPrank();
		assertEq(proxyAdmin.owner(), guardian);

		// upgrade contract, unprivileged users deploys new implementation
		vm.prank(DEPLOYER);
		MockTokenggAVAXV2 ggAVAXImplV2 = new MockTokenggAVAXV2();

		vm.expectRevert("Initializable: contract is already initialized");
		ggAVAXImplV2.initialize(store, wavax, 0);

		vm.expectRevert("Ownable: caller is not the owner");
		proxyAdmin.upgrade(ggAVAXProxy, address(ggAVAXImplV2));

		vm.startPrank(guardian);
		vm.expectRevert("ERC1967: new implementation is not a contract");
		proxyAdmin.upgrade(ggAVAXProxy, address(0));

		// Check that we can recover from a bad address
		proxyAdmin.upgrade(ggAVAXProxy, address(wavax));
		proxyAdmin.upgrade(ggAVAXProxy, address(ggAVAXImplV2));
		vm.stopPrank();

		// Verify data is still there
		assertEq(shareAmount, 100 ether);
		assertEq(token.totalAssets(), 100 ether);
		assertEq(token.balanceOf(alice), 100 ether);

		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImplV2));
	}

	function testUpgradeToStAVAXNaming() public {
		// Deploy and initialize the original token
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAXV1 ggAVAXImplV1 = new TokenggAVAXV1();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImplV1),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImplV1.initialize.selector, store, wavax, 0)
		);
		TokenggAVAX tokenProxy = TokenggAVAX(payable(address(ggAVAXProxy)));

		// Transfer admin to guardian
		proxyAdmin.transferOwnership(guardian);
		vm.stopPrank();
		assertEq(proxyAdmin.owner(), guardian);

		// Verify initial state - should be version 1 with ggAVAX naming
		assertEq(tokenProxy.name(), "GoGoPool Liquid Staking Token");
		assertEq(tokenProxy.symbol(), "ggAVAX");
		assertEq(tokenProxy.version(), 1);

		// Add some state to verify preservation during upgrade
		address alice = getActorWithTokens("alice", 100 ether, 0);
		vm.deal(alice, 100 ether);
		vm.startPrank(alice);
		uint256 shareAmount = tokenProxy.depositAVAX{value: 100 ether}();
		assertEq(shareAmount, 100 ether);
		assertEq(tokenProxy.totalAssets(), 100 ether);
		assertEq(tokenProxy.balanceOf(alice), 100 ether);
		vm.stopPrank();

		// Store pre-upgrade values
		uint256 preTotalAssets = tokenProxy.totalAssets();
		uint256 preAliceBalance = tokenProxy.balanceOf(alice);
		uint256 preAliceShares = tokenProxy.convertToShares(preAliceBalance);
		address assetAddress = address(tokenProxy.asset());

		// Deploy new implementation
		vm.prank(DEPLOYER);
		TokenggAVAXV2 ggAVAXImplV2 = new TokenggAVAXV2();

		// Upgrade using reinitialize to change name/symbol to stAVAX
		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(ggAVAXProxy, address(ggAVAXImplV2), abi.encodeWithSelector(ggAVAXImplV2.reinitialize.selector, ERC20(assetAddress)));

		// Verify upgrade was successful
		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImplV2));

				// Verify name and symbol changed to stAVAX branding
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		// Note: version remains 1 since reinitialize doesn't update the version field

		// Verify all existing state is preserved
		assertEq(tokenProxy.totalAssets(), preTotalAssets);
		assertEq(tokenProxy.balanceOf(alice), preAliceBalance);
		assertEq(tokenProxy.convertToShares(preAliceBalance), preAliceShares);
		assertEq(address(tokenProxy.asset()), assetAddress);

		// Verify token functionality still works after upgrade
		vm.deal(alice, 50 ether);
		vm.startPrank(alice);
		uint256 newShareAmount = tokenProxy.depositAVAX{value: 50 ether}();
		assertEq(newShareAmount, 50 ether);
		assertEq(tokenProxy.totalAssets(), 150 ether);
		assertEq(tokenProxy.balanceOf(alice), 150 ether);

		vm.stopPrank();

		// Verify rewards functionality still works
		tokenProxy.syncRewards();
		assertTrue(tokenProxy.lastSync() > 0);
	}

	function testUpgradeToStAVAXTimelockScenario() public {
		// Test upgrade V1 -> V2 through actual timelock with queue/execute flow (simulating the mainnet governance structure)
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAXV1 ggAVAXImplV1 = new TokenggAVAXV1();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImplV1),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImplV1.initialize.selector, store, wavax, 0)
		);
		TokenggAVAXV2 tokenProxy = TokenggAVAXV2(payable(address(ggAVAXProxy)));

		// Deploy actual timelock contract
		Timelock timelock = new Timelock();

		// Transfer ownership of proxy admin to timelock (like mainnet)
		proxyAdmin.transferOwnership(address(timelock));

		// Set guardian as owner of timelock (like mainnet where multisig owns timelock)
		timelock.transferOwnership(guardian);
		vm.stopPrank();

		assertEq(proxyAdmin.owner(), address(timelock));
		assertEq(timelock.owner(), guardian);

		// Verify initial state
		assertEq(tokenProxy.name(), "GoGoPool Liquid Staking Token");
		assertEq(tokenProxy.symbol(), "ggAVAX");
		assertEq(tokenProxy.version(), 1);

		// Add liquidity
		address alice = getActorWithTokens("alice", 1000 ether, 0);
		vm.deal(alice, 1000 ether);
		vm.prank(alice);
		tokenProxy.depositAVAX{value: 1000 ether}();

		// Deploy TokenggAVAXV2 implementation (from previous versions)
		vm.prank(DEPLOYER);
		TokenggAVAXV2 ggAVAXImplV2 = new TokenggAVAXV2();

		// Prepare upgrade transaction data
		bytes memory upgradeCalldata = abi.encodeWithSelector(
			proxyAdmin.upgradeAndCall.selector,
			ggAVAXProxy,
			address(ggAVAXImplV2),
			abi.encodeWithSelector(ggAVAXImplV2.reinitialize.selector, ERC20(address(wavax)))
		);

		// Queue transaction through timelock (guardian acting as multisig)
		vm.prank(guardian);
		bytes32 transactionId = timelock.queueTransaction(address(proxyAdmin), upgradeCalldata);

		// Verify transaction is queued but cannot execute yet
		vm.expectRevert(Timelock.Timelocked.selector);
		timelock.executeTransaction(transactionId);

		// Verify token still has old branding while queued
		assertEq(tokenProxy.name(), "GoGoPool Liquid Staking Token");
		assertEq(tokenProxy.symbol(), "ggAVAX");

		// Fast forward past the timelock delay (24 hours)
		skip(24 hours + 1 seconds);

		// Execute the transaction (anyone can execute after delay)
		timelock.executeTransaction(transactionId);

		// Verify successful upgrade with new branding
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		assertEq(tokenProxy.version(), 2);

		// Verify functionality preserved
		assertEq(tokenProxy.totalAssets(), 1000 ether);
		assertEq(tokenProxy.balanceOf(alice), 1000 ether);

		// Test new deposits still work with new branding
		vm.deal(alice, 500 ether);
		vm.prank(alice);
		tokenProxy.depositAVAX{value: 500 ether}();
		assertEq(tokenProxy.balanceOf(alice), 1500 ether);

		// Verify transaction is removed from timelock after execution
		vm.expectRevert(Timelock.TransactionNotFound.selector);
		timelock.executeTransaction(transactionId);
	}

	function testUpgradeToLatestVersionTimelockScenario() public {
		// Test upgrade V2 -> V3 through actual timelock with queue/execute flow (testing latest version)
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAXV2 ggAVAXImplV2 = new TokenggAVAXV2();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImplV2),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImplV2.initialize.selector, store, wavax, 0)
		);
		TokenggAVAX tokenProxy = TokenggAVAX(payable(address(ggAVAXProxy)));

		// Upgrade to V2 first
		proxyAdmin.upgradeAndCall(ggAVAXProxy, address(ggAVAXImplV2), abi.encodeWithSelector(ggAVAXImplV2.reinitialize.selector, ERC20(address(wavax))));

		// Deploy actual timelock contract
		Timelock timelock = new Timelock();

		// Transfer ownership of proxy admin to timelock (like mainnet)
		proxyAdmin.transferOwnership(address(timelock));

		// Set guardian as owner of timelock (like mainnet where multisig owns timelock)
		timelock.transferOwnership(guardian);
		vm.stopPrank();

		assertEq(proxyAdmin.owner(), address(timelock));
		assertEq(timelock.owner(), guardian);

		// Verify initial state (should be V2)
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		assertEq(tokenProxy.version(), 2);

		// Add liquidity
		address alice = getActorWithTokens("alice", 1000 ether, 0);
		vm.deal(alice, 1000 ether);
		vm.prank(alice);
		tokenProxy.depositAVAX{value: 1000 ether}();

		// Deploy latest implementation (V3)
		vm.prank(DEPLOYER);
		TokenggAVAX ggAVAXImplV3 = new TokenggAVAX();

		// Prepare upgrade transaction data
		bytes memory upgradeCalldata = abi.encodeWithSelector(
			proxyAdmin.upgradeAndCall.selector,
			ggAVAXProxy,
			address(ggAVAXImplV3),
			abi.encodeWithSelector(ggAVAXImplV3.reinitialize.selector, guardian)
		);

		// Queue transaction through timelock (guardian acting as multisig)
		vm.prank(guardian);
		bytes32 transactionId = timelock.queueTransaction(address(proxyAdmin), upgradeCalldata);

		// Verify transaction is queued but cannot execute yet
		vm.expectRevert(Timelock.Timelocked.selector);
		timelock.executeTransaction(transactionId);

		// Fast forward past the timelock delay (24 hours)
		skip(24 hours + 1 seconds);

		// Execute the transaction (anyone can execute after delay)
		timelock.executeTransaction(transactionId);

		// Verify successful upgrade to V3
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		assertEq(tokenProxy.version(), 3);

		// Verify functionality preserved
		assertEq(tokenProxy.totalAssets(), 1000 ether);
		assertEq(tokenProxy.balanceOf(alice), 1000 ether);

		// Test new deposits still work
		vm.deal(alice, 500 ether);
		vm.prank(alice);
		tokenProxy.depositAVAX{value: 500 ether}();
		assertEq(tokenProxy.balanceOf(alice), 1500 ether);

		// Test that contract is still usable - verify access control works
		vm.startPrank(alice);
		vm.expectRevert(abi.encodeWithSelector(TokenggAVAX.AccessControlUnauthorizedAccount.selector, alice, tokenProxy.WITHDRAW_QUEUE_ROLE()));
		tokenProxy.withdrawAVAX(25 ether);
		vm.stopPrank();

		// Grant withdrawal role and test it works
		vm.startPrank(guardian);
		tokenProxy.grantRole(tokenProxy.WITHDRAW_QUEUE_ROLE(), alice);
		vm.stopPrank();

		vm.prank(alice);
		tokenProxy.withdrawAVAX(25 ether);
		assertEq(tokenProxy.balanceOf(alice), 1475 ether);
		assertEq(alice.balance, 25 ether);

		// Test rewards functionality
		tokenProxy.syncRewards();
		assertTrue(tokenProxy.lastSync() > 0);

		// Verify transaction is removed from timelock after execution
		vm.expectRevert(Timelock.TransactionNotFound.selector);
		timelock.executeTransaction(transactionId);
	}

	function testCannotReinitializeAfterUpgrade() public {
		// Deploy and upgrade V1 -> V2 -> V3
		vm.startPrank(DEPLOYER);
		ProxyAdmin proxyAdmin = new ProxyAdmin();
		TokenggAVAXV1 ggAVAXImplV1 = new TokenggAVAXV1();

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImplV1),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImplV1.initialize.selector, store, wavax, 0)
		);
		TokenggAVAX tokenProxy = TokenggAVAX(payable(address(ggAVAXProxy)));

		proxyAdmin.transferOwnership(guardian);

		// Deploy V2 implementation and upgrade to set "Hypha Staked AVAX" name
		TokenggAVAXV2 ggAVAXImplV2 = new TokenggAVAXV2();
		vm.stopPrank();

		// First upgrade V1 -> V2 to set proper name/symbol
		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(ggAVAXProxy, address(ggAVAXImplV2), abi.encodeWithSelector(ggAVAXImplV2.reinitialize.selector, ERC20(address(wavax))));

		// Verify V2 upgrade worked and name is set
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		assertEq(tokenProxy.version(), 2);

		// Deploy V3 implementation and upgrade
		vm.prank(DEPLOYER);
		TokenggAVAX ggAVAXImplV3 = new TokenggAVAX();

		vm.prank(guardian);
		proxyAdmin.upgradeAndCall(ggAVAXProxy, address(ggAVAXImplV3), abi.encodeWithSelector(ggAVAXImplV3.reinitialize.selector, guardian));

		// Verify V3 upgrade worked and name is preserved
		assertEq(tokenProxy.name(), "Hypha Staked AVAX");
		assertEq(tokenProxy.symbol(), "stAVAX");
		assertEq(tokenProxy.version(), 3);

		// Attempt to reinitialize again should fail
		vm.expectRevert("Initializable: contract is already initialized");
		tokenProxy.reinitialize(guardian);

		// Also test that original initialize cannot be called
		vm.expectRevert("Initializable: contract is already initialized");
		tokenProxy.initialize(store, wavax, 0);
	}
}
