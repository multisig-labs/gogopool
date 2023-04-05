// file for testing erc20upgradeable upgrades

pragma solidity 0.8.17;

import "./utils/BaseTest.sol";

import {MockTokenggAVAXV2} from "./utils/MockTokenggAVAXV2.sol";
import {MockTokenggAVAXV2Dangerous} from "./utils/MockTokenggAVAXV2Dangerous.sol";
import {MockTokenggAVAXV2Safe} from "./utils/MockTokenggAVAXV2Safe.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

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
}
