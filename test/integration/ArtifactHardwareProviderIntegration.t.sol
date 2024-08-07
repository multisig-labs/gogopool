// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../unit/utils/BaseTest.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {Staking} from "../../contracts/contract/Staking.sol";
import {ArtifactHardwareProvider} from "../../contracts/contract/ArtifactHardwareProvider.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

import {console2} from "forge-std/console2.sol";

contract ArtifactHardwareProviderIntegrationTest is BaseTest {
	using FixedPointMathLib for uint256;
	uint256 private constant TOTAL_INITIAL_SUPPLY = 22500000 ether;

	ArtifactHardwareProvider provider;
	address admin;
	address paymentReceiver;
	address chainlinkPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156;

	function setUp() public override {
		super.setUp();
		uint256 fork = vm.createFork(vm.envString("FORK_URL"));
		vm.selectFork(fork);

		admin = randAddress();
		paymentReceiver = randAddress();

		provider = new ArtifactHardwareProvider(admin, paymentReceiver, chainlinkPriceFeed);

		vm.startPrank(admin);
		provider.grantRole(provider.RENTER_ROLE(), admin);
		vm.stopPrank();
	}

	function testRentHardwareMainnet() public {
		address user = randAddress();
		address nodeID = randAddress();
		uint256 duration = 30 days;

		uint256 hardwareCost = calculateHardwareCost(duration).mulWadDown(1.01 ether);

		vm.deal(admin, hardwareCost);

		uint256 adminBalanceBefore = admin.balance;

		vm.prank(admin);
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);

		assertEq(admin.balance, adminBalanceBefore - hardwareCost);
		assertEq(paymentReceiver.balance, hardwareCost);
	}

	function calculateHardwareCost(uint256 duration) internal view returns (uint256) {
		(, int256 answer, , , ) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
		uint8 decimals = AggregatorV3Interface(chainlinkPriceFeed).decimals();
		uint256 scalingFactor = 18 - decimals;
		uint256 avaxUsdPrice = uint256(answer) * 10 ** scalingFactor;

		uint256 payPeriods = duration / provider.payPeriod();
		uint256 expectedPaymentUsd = payPeriods * provider.payIncrementUsd();

		return expectedPaymentUsd.divWadDown(avaxUsdPrice);
	}
}
