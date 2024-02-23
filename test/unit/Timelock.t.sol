// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Timelock} from "../../contracts/contract/Timelock.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {MockTokenggAVAXV2} from "./utils/MockTokenggAVAXV2.sol";

contract TimelockTest is Test {
	uint256 public mainnetFork;
	address public guardian;
	Timelock public timelock;
	ProxyAdmin public proxyAdmin;
	TransparentUpgradeableProxy public ggAVAXProxy;
	TokenggAVAX public ggAVAX;
	TokenggAVAX public ggAVAXImpl;
	MockTokenggAVAXV2 public ggAVAXImplV2;

	function setUp() public {
		// Mainnet addrs
		mainnetFork = vm.createFork("https://api.avax.network/ext/bc/C/rpc");
		vm.selectFork(mainnetFork);
		guardian = 0x6C104D5b914931BA179168d63739A297Dc29bCF3;
		proxyAdmin = ProxyAdmin(0x5313c309CD469B751Ad3947568D65d4a70B247cF);
		ggAVAX = TokenggAVAX(payable(0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3));
		ggAVAXProxy = TransparentUpgradeableProxy(payable(0xA25EaF2906FA1a3a13EdAc9B9657108Af7B703e3));
		ggAVAXImpl = TokenggAVAX(payable(0xf80Eb498bBfD45f5E2d123DFBdb752677757843E));
		ggAVAXImplV2 = new MockTokenggAVAXV2();
		timelock = Timelock(address(0xcd385F1947D532186f3F6aaa93966E3e9C14af41));
	}

	function testMainnetAssumptions() public {
		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImpl));
		assertEq(proxyAdmin.getProxyAdmin(ggAVAXProxy), address(proxyAdmin));
		assertEq(proxyAdmin.owner(), address(timelock));

		// Only proxyAdmin can call fns on the proxy
		vm.expectRevert();
		ggAVAXProxy.admin();
		vm.prank(address(proxyAdmin));
		assertEq(ggAVAXProxy.admin(), address(proxyAdmin));
	}

	// Make the Timelock contract the owner of the ProxyAdmin contract, and ensure upgrades work
	function testTimelockUpgrade() public {
		uint256 stakingTotalAssets = ggAVAX.stakingTotalAssets();

		// Guardian can't upgrade anymore
		vm.prank(guardian);
		vm.expectRevert("Ownable: caller is not the owner");
		proxyAdmin.upgrade(ggAVAXProxy, address(ggAVAXImplV2));

		// Submit proposal to timelock
		bytes memory data = abi.encodeCall(proxyAdmin.upgrade, (ggAVAXProxy, address(ggAVAXImplV2)));
		vm.expectRevert("Ownable: caller is not the owner");
		timelock.queueTransaction(address(proxyAdmin), data);

		vm.prank(guardian);
		bytes32 id = timelock.queueTransaction(address(proxyAdmin), data);

		vm.expectRevert(Timelock.Timelocked.selector);
		timelock.executeTransaction(id);

		// After timelock, anyone can execute
		skip(24 hours);
		timelock.executeTransaction(id);
		assertEq(proxyAdmin.getProxyImplementation(ggAVAXProxy), address(ggAVAXImplV2));

		// Accessing impl directly should be zero
		assertEq(ggAVAXImplV2.stakingTotalAssets(), 0);
		// Accessing through proxy should have the actual amounts
		assertEq(ggAVAX.stakingTotalAssets(), stakingTotalAssets);

		// Test that deposit/redeem functions correctly
		address alice = address(0x5000);
		vm.startPrank(alice);
		assertEq(ggAVAX.balanceOf(alice), 0);
		vm.deal(alice, 1 ether);
		uint256 shares = ggAVAX.depositAVAX{value: 1 ether}();
		assertEq(ggAVAX.balanceOf(alice), shares);
		ggAVAX.redeemAVAX(shares);
		assertEq(ggAVAX.balanceOf(alice), 0);
		assertGt(alice.balance, 0);
	}

	function testTimelockChangeProxyAdmin() public {
		// Guardian cant upgrade anymore, because timelock is now the admin on mainnet
		vm.prank(guardian);
		vm.expectRevert();
		proxyAdmin.upgrade(ggAVAXProxy, address(ggAVAXImplV2));

		// Submit proposal to timelock to change owner of ProxyAdmin back to guardian
		bytes memory data = abi.encodeCall(proxyAdmin.transferOwnership, (guardian));
		vm.prank(guardian);
		bytes32 id = timelock.queueTransaction(address(proxyAdmin), data);

		vm.expectRevert(Timelock.Timelocked.selector);
		timelock.executeTransaction(id);

		// After delay, anyone can execute
		skip(24 hours);
		timelock.executeTransaction(id);

		assertEq(proxyAdmin.owner(), guardian);
	}

	function testTimelockAbort() public {
		bytes memory data = "woot";
		vm.startPrank(guardian);
		bytes32 id = timelock.queueTransaction(address(1), data);
		timelock.abortTransaction(id);
		skip(24 hours);
		vm.expectRevert(Timelock.TransactionNotFound.selector);
		timelock.executeTransaction(id);
	}
}
