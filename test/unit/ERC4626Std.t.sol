// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "lib/erc4626-tests/ERC4626.test.sol";
import {MockERC20} from "lib/solmate/src/test/utils/mocks/MockERC20.sol";
import {Storage} from "../../contracts/contract/Storage.sol";
import {TokenggAVAX} from "../../contracts/contract/tokens/TokenggAVAX.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

// From https://github.com/a16z/erc4626-tests/
// https://a16zcrypto.com/generalized-property-tests-for-erc4626-vaults

contract ERC4626StdTest is ERC4626Test {
	function setUp() public override {
		address guardian = address(0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84);
		vm.label(guardian, "guardian");
		// Construct all contracts as Guardian
		vm.startPrank(guardian, guardian);

		// Using mock so it has public mint and burn, required for the tests
		MockERC20 wavax = new MockERC20("WAVAX", "WAVAX", 18);
		_underlying_ = address(wavax);

		// Get our token all set up with storage etc
		Storage store = new Storage();
		TokenggAVAX ggAVAXImpl = new TokenggAVAX();
		TokenggAVAX ggAVAX = TokenggAVAX(deployProxy(address(ggAVAXImpl), address(1)));
		registerContract(store, "TokenggAVAX", address(ggAVAX));

		ggAVAX.initialize(store, wavax, 0);
		ggAVAX.syncRewards();

		_vault_ = address(ggAVAX);
		_delta_ = 0;
		_vaultMayBeEmpty = false;
		_unlimitedAmount = false;
		vm.stopPrank();
	}

	// NOTE: The following test is relaxed to consider only smaller values (of type uint120),
	// since maxWithdraw/Redeem() fails with large values (due to overflow).
	// From https://github.com/daejunpark/solmate/pull/1/files

	function test_maxWithdraw(Init memory init) public override {
		init = clamp(init, type(uint120).max);
		super.test_maxWithdraw(init);
	}

	function test_maxRedeem(Init memory init) public override {
		init = clamp(init, type(uint120).max);
		super.test_maxRedeem(init);
	}

	function clamp(Init memory init, uint256 max) internal pure returns (Init memory) {
		for (uint256 i = 0; i < N; i++) {
			init.share[i] = init.share[i] % max;
			init.asset[i] = init.asset[i] % max;
		}
		init.yield = init.yield % int256(max);
		return init;
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
