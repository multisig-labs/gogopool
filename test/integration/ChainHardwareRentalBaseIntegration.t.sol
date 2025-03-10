// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "../unit/utils/BaseTest.sol";
import {SubnetHardwareRentalBase} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalBase.sol";
import {AvalancheHardwareRental} from "../../contracts/contract/hardwareProviders/AvalancheHardwareRental.sol";
import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import {ILBRouter} from "../../contracts/interface/ILBRouter.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

import {console2} from "forge-std/console2.sol";

contract SubnetHardwareRentalBaseIntegration is BaseTest {
	using FixedPointMathLib for uint256;

	SubnetHardwareRentalBase public baseContract;
	AvalancheHardwareRental public avalancheHardwareRental;
	CoqnetHardwareRental public coqnetHardwareRental;

	address admin;
	address renter;
	address public paymentReceiver;
	address chainlinkPriceFeed = 0x0A77230d17318075983913bC2145DB16C7366156; // Mainnet AVAX/USD
	address ggpAddr = 0x69260B9483F9871ca57f81A90D91E2F96c2Cd11d; // Mainnet GGP
	address wavaxAddr = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7; // Mainnet WAVAX
	address tjRouter = 0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30; // Mainnet TraderJoe Router

	bytes32 public constant AVALANCHE_SUBNET = 0x0000000000000000000000000000000000000000000000000000000000000000;
	bytes32 public constant COQNET_SUBNET = 0x0ad6355dc6b82cd375e3914badb3e2f8d907d0856f8e679b2db46f8938a2f012;
	bytes32 public constant MOCK_PROVIDER = keccak256("TestProvider");

	function setUp() public override {
		super.setUp();
		uint256 fork = vm.createFork(vm.envString("FORK_URL"));
		vm.selectFork(fork);

		admin = randAddress();
		renter = randAddress();
		paymentReceiver = randAddress();

		ProxyAdmin avalancheHardwareRentalProxyAdmin = new ProxyAdmin();
		AvalancheHardwareRental avalancheHardwareRentalImpl = new AvalancheHardwareRental();
		TransparentUpgradeableProxy avalancheHardwareRentalTransparentProxy = new TransparentUpgradeableProxy(
			address(avalancheHardwareRentalImpl),
			address(avalancheHardwareRentalProxyAdmin),
			abi.encodeWithSelector(
				AvalancheHardwareRental.initialize.selector,
				admin,
				address(chainlinkPriceFeed),
				1 days,
				1 ether,
				address(ggpAddr),
				address(wavaxAddr),
				address(tjRouter)
			)
		);
		avalancheHardwareRental = AvalancheHardwareRental(payable(avalancheHardwareRentalTransparentProxy));

		ProxyAdmin coqnetHardwareRentalProxyAdmin = new ProxyAdmin();
		CoqnetHardwareRental coqnetHardwareRentalImpl = new CoqnetHardwareRental();
		TransparentUpgradeableProxy coqnetHardwareRentalTransparentProxy = new TransparentUpgradeableProxy(
			address(coqnetHardwareRentalImpl),
			address(coqnetHardwareRentalProxyAdmin),
			abi.encodeWithSelector(
				CoqnetHardwareRental.initialize.selector,
				admin,
				address(chainlinkPriceFeed),
				1 days,
				1 ether,
				address(ggpAddr),
				address(wavaxAddr),
				address(tjRouter)
			)
		);
		coqnetHardwareRental = CoqnetHardwareRental(payable(coqnetHardwareRentalTransparentProxy));

		vm.startPrank(admin);
		avalancheHardwareRental.grantRole(avalancheHardwareRental.RENTER_ROLE(), renter);
		coqnetHardwareRental.grantRole(coqnetHardwareRental.RENTER_ROLE(), renter);

		// Add hardware provider to both contracts
		avalancheHardwareRental.addHardwareProvider(MOCK_PROVIDER, paymentReceiver);
		coqnetHardwareRental.addHardwareProvider(MOCK_PROVIDER, paymentReceiver);
		vm.stopPrank();
	}

	function testCrossSubnetRental() public {
		address user = randAddress();
		bytes memory nodeID = abi.encodePacked(randAddress());
		uint256 duration = 30 days;
		uint256 minTokenOut = 1 ether;

		// Calculate costs for both subnets
		uint256 avalancheCost = calculateHardwareCost(duration, address(avalancheHardwareRental));
		uint256 coqnetCost = calculateHardwareCost(duration, address(coqnetHardwareRental));

		vm.deal(renter, avalancheCost + coqnetCost);

		vm.startPrank(renter);

		// Rent hardware on Avalanche subnet
		avalancheHardwareRental.rentHardware{value: avalancheCost}(user, nodeID, duration, MOCK_PROVIDER, minTokenOut);

		// Rent hardware on Coqnet subnet
		coqnetHardwareRental.rentHardware{value: coqnetCost}(user, nodeID, duration, MOCK_PROVIDER, minTokenOut);

		vm.stopPrank();

		// Verify the rentals were successful by checking payment receiver balances
		assertTrue(renter.balance == 0);
		assertTrue(paymentReceiver.balance == avalancheCost);
		assertTrue(ERC20(ggpAddr).balanceOf(paymentReceiver) >= minTokenOut);
	}

	function calculateHardwareCost(uint256 duration, address rentalContract) internal view returns (uint256) {
		(, int256 answer, , , ) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
		uint8 decimals = AggregatorV3Interface(chainlinkPriceFeed).decimals();
		uint256 scalingFactor = 18 - decimals;
		uint256 avaxUsdPrice = uint256(answer) * 10 ** scalingFactor;

		uint256 payIncrementUsd = SubnetHardwareRentalBase(rentalContract).payIncrementUsd();
		uint256 payPeriod = SubnetHardwareRentalBase(rentalContract).payPeriod();
		uint256 payPeriods = duration / payPeriod;
		uint256 expectedPaymentUsd = payPeriods * payIncrementUsd;

		return expectedPaymentUsd.divWadDown(avaxUsdPrice).mulWadDown(1.01 ether); // Add 1% margin
	}

	function testVerifyInitialization() public {
		assertTrue(avalancheHardwareRental.getSubnetName() == keccak256(abi.encodePacked("Avalanche")));
		assertTrue(avalancheHardwareRental.getSubnetID() == AVALANCHE_SUBNET);
		assertTrue(avalancheHardwareRental.payPeriod() == 1 days);
		assertTrue(avalancheHardwareRental.payIncrementUsd() == 1 ether);

		assertTrue(coqnetHardwareRental.getSubnetName() == keccak256(abi.encodePacked("Coqnet")));
		assertTrue(coqnetHardwareRental.getSubnetID() == COQNET_SUBNET);
		assertTrue(coqnetHardwareRental.payPeriod() == 1 days);
		assertTrue(coqnetHardwareRental.payIncrementUsd() == 1 ether);
	}
}
