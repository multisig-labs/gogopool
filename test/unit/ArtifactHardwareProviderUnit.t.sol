// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {MockChainlinkPriceFeed} from "./utils/MockChainlink.sol";
import {BaseAbstract} from "../../contracts/contract/BaseAbstract.sol";
import {Staking} from "../../contracts/contract/Staking.sol";
import {ArtifactHardwareProvider} from "../../contracts/contract/ArtifactHardwareProvider.sol";
import {IHardwareProvider} from "../../contracts/interface/IHardwareProvider.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

import {console2} from "forge-std/console2.sol";

contract ArtifactHardwareProviderUnitTest is BaseTest {
	using FixedPointMathLib for uint256;

	event HardwareRented(address user, address nodeID, bytes32 hardwareProviderName, uint256 duration, uint256 payment);

	ArtifactHardwareProvider public provider;
	address public admin;
	address public paymentReceiver;
	MockChainlinkPriceFeed public mockChainlink;

	uint256 public payIncrementUsd = 60 ether;
	uint256 public payPeriod = 15 days;

	function setUp() public override {
		super.setUp();

		admin = randAddress();
		paymentReceiver = randAddress();

		mockChainlink = new MockChainlinkPriceFeed(admin, 1 * 10 ** 8);
		provider = new ArtifactHardwareProvider(admin, paymentReceiver, address(mockChainlink));

		vm.startPrank(admin);
		provider.grantRole(provider.RENTER_ROLE(), admin);
		provider.setAvaxPriceFeed(address(mockChainlink));
		vm.stopPrank();
	}

	function testRentHardwareDefault() public {
		address user = randAddress();
		address nodeID = randAddress();
		uint256 duration = 30 days;

		uint256 hardwareCost = calculateHardwareCost(duration);

		vm.deal(admin, hardwareCost);

		uint256 balanceBefore = admin.balance;

		vm.startPrank(admin);
		vm.expectEmit(address(provider));
		emit HardwareRented(user, nodeID, provider.getHardwareProviderName(), duration, hardwareCost);
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);

		assertEq(admin.balance, balanceBefore - hardwareCost);
		assertEq(paymentReceiver.balance, hardwareCost);
	}

	function testRentHardwareOnlyRenter() public {
		address user = randAddress();

		vm.startPrank(user);
		vm.expectRevert();
		provider.rentHardware{value: 1 ether}(randAddress(), randAddress(), 30 days);
	}

	function testRentHardwareInsufficientPayment() public {
		address user = randAddress();
		address nodeID = randAddress();
		uint256 duration = 30 days;

		uint256 hardwareCost = calculateHardwareCost(duration).mulWadDown(0.5 ether);

		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(abi.encodeWithSelector(ArtifactHardwareProvider.InsufficientPayment.selector, calculateHardwareCost(duration), hardwareCost));
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);

		hardwareCost = calculateHardwareCost(duration) - 1;
		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(abi.encodeWithSelector(ArtifactHardwareProvider.InsufficientPayment.selector, calculateHardwareCost(duration), hardwareCost));
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);
	}

	function testRentHardwareExcessivePayment() public {
		address user = randAddress();
		address nodeID = randAddress();
		uint256 duration = 30 days;

		// default margin is 0.05% higher than actual cost
		uint256 hardwareCost = calculateHardwareCost(duration).mulWadDown(1.5 ether);

		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(abi.encodeWithSelector(ArtifactHardwareProvider.ExcessivePayment.selector, calculateHardwareCost(duration), hardwareCost));
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);
		vm.stopPrank();

		hardwareCost = calculateHardwareCost(duration).mulWadDown(1.06 ether);
		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(abi.encodeWithSelector(ArtifactHardwareProvider.ExcessivePayment.selector, calculateHardwareCost(duration), hardwareCost));
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);
		vm.stopPrank();

		hardwareCost = calculateHardwareCost(duration).mulWadDown(1.05 ether);
		vm.deal(admin, hardwareCost);

		vm.prank(admin);
		provider.rentHardware{value: hardwareCost}(user, nodeID, duration);
	}

	function testRentHardwareZeroUserAddress() public {
		uint256 duration = 30 days;
		uint256 hardwareCost = calculateHardwareCost(duration);
		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(ArtifactHardwareProvider.ZeroAddress.selector);
		provider.rentHardware{value: 1 ether}(address(0x0), randAddress(), 30 days);
		vm.stopPrank();
	}

	function testRentHardwareZeroNodeID() public {
		uint256 duration = 30 days;
		uint256 hardwareCost = calculateHardwareCost(duration);
		vm.deal(admin, hardwareCost);

		vm.startPrank(admin);
		vm.expectRevert(ArtifactHardwareProvider.ZeroNodeID.selector);
		provider.rentHardware{value: 1 ether}(randAddress(), address(0x0), 30 days);
		vm.stopPrank();
	}

	function testRentHardwareZeroDuration() public {
		uint256 duration = 30 days;
		uint256 hardwareCost = calculateHardwareCost(duration);
		vm.deal(admin, hardwareCost);
		vm.startPrank(admin);

		vm.expectRevert(ArtifactHardwareProvider.ZeroDuration.selector);
		provider.rentHardware{value: 1 ether}(randAddress(), randAddress(), 0 days);
		vm.stopPrank();
	}

	function testGetExpectedPayment() public {
		uint256 duration = 15 days;
		uint256 expectedAmount = (duration / provider.payPeriod()) * payIncrementUsd;

		uint256 actualAmount = provider.getExpectedPayment(duration);
		assertEq(expectedAmount, actualAmount);
	}

	function testGetHardwareProviderName() public {
		bytes32 expectedName = keccak256(abi.encodePacked("Artifact"));
		bytes32 name = provider.getHardwareProviderName();
		assertEq(expectedName, name);
	}

	function testSetPaymentReceiver() public {
		address newPaymentRecevier = randAddress();

		vm.expectRevert();
		provider.setPaymentReceiver(newPaymentRecevier);

		vm.prank(admin);
		provider.setPaymentReceiver(newPaymentRecevier);

		assertEq(newPaymentRecevier, provider.paymentReceiver());
	}

	function testSetPayPeriod() public {
		vm.prank(admin);
		provider.setPayIncrementUsd(1 ether);

		uint256 newPayPeriod = randUint(type(uint40).max);

		vm.expectRevert();
		provider.setPayPeriod(newPayPeriod);

		vm.prank(admin);
		provider.setPayPeriod(newPayPeriod);

		assertEq(newPayPeriod, provider.payPeriod());

		uint256 duration = 10 days;
		uint256 payment = provider.getExpectedPayment(duration);
		assertEq(payment, (duration / newPayPeriod) * 1 ether);
	}

	function testSetPayIncrement() public {
		uint256 period = randUint(type(uint128).max);
		vm.prank(admin);
		provider.setPayPeriod(period);

		uint256 newPayIncrementUsd = randUint(type(uint128).max);

		vm.expectRevert();
		provider.setPayIncrementUsd(newPayIncrementUsd);

		vm.prank(admin);
		provider.setPayIncrementUsd(newPayIncrementUsd);

		assertEq(newPayIncrementUsd, provider.payIncrementUsd());

		uint256 duration = 10 days;
		uint256 payment = provider.getExpectedPayment(duration);
		assertEq(payment, (duration / period) * newPayIncrementUsd);
	}

	function testSetPayMargin() public {
		uint256 newPayMargin = randUint(type(uint128).max);

		vm.expectRevert();
		provider.setPayMargin(newPayMargin);

		vm.prank(admin);
		provider.setPayMargin(newPayMargin);

		assertEq(newPayMargin, provider.payMargin());
	}

	function testSetAvaxPriceFeed() public {
		address newPriceFeed = randAddress();

		vm.expectRevert();
		provider.setAvaxPriceFeed(newPriceFeed);

		vm.prank(admin);
		provider.setAvaxPriceFeed(newPriceFeed);

		assertEq(newPriceFeed, provider.avaxPriceFeed());
	}

	function testGetAvaxPriceUsd() public {
		uint256 basePrice = 19;

		vm.prank(admin);
		mockChainlink.setPrice(basePrice * 10 ** 8);

		uint256 expectedAvaxUsdPrice = basePrice * 10 ** 18;
		assertEq(expectedAvaxUsdPrice, provider.getAvaxUsdPrice());
	}

	function calculateHardwareCost(uint256 duration) internal view returns (uint256) {
		(, int256 answer, , , ) = mockChainlink.latestRoundData();
		uint8 decimals = mockChainlink.decimals();
		uint256 scalingFactor = 18 - decimals;
		uint256 avaxUsdPrice = uint256(answer) * 10 ** scalingFactor;

		uint256 payPeriods = duration / payPeriod;
		uint256 expectedPaymentUsd = payPeriods * payIncrementUsd;

		return expectedPaymentUsd.divWadDown(avaxUsdPrice);
	}
}
