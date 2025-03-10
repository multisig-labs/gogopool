// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import "./utils/BaseTest.sol";
import {MockChainlinkPriceFeed} from "./utils/MockChainlink.sol";
import {SubnetHardwareRentalBase} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalBase.sol";
import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {MockTraderJoeRouter} from "./utils/MockTraderJoeRouter.sol";
import {MockSubnetHardwareRental} from "./utils/MockSubnetHardwareRental.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";

contract SubnetHardwareRentalBaseTest is BaseTest {
	using FixedPointMathLib for uint256;

	MockSubnetHardwareRental public rentalContract;
	SubnetHardwareRentalMapping public rentalMapping;
	MockChainlinkPriceFeed public priceFeed;
	MockTraderJoeRouter public tjRouter;

	address public admin;
	address public renter;
	address public paymentReceiver;

	bytes32 public constant MOCK_PROVIDER = keccak256("MockProvider");
	bytes32 public constant MOCK_SUBNET = keccak256("MockSubnet");

	event HardwareProviderAdded(bytes32 indexed hardwareProviderName, address indexed paymentReceiver);
	event HardwareProviderRemoved(bytes32 indexed hardwareProviderName, address indexed paymentReceiver);
	event SubnetHardwareRentalContractAdded(bytes32 indexed subnetId, address indexed subnetHardwareRentalContract);
	event SubnetHardwareRentalContractRemoved(bytes32 indexed subnetId, address indexed subnetHardwareRentalContract);
	event HardwareRented(
		address user,
		bytes nodeID,
		bytes32 hardwareProviderName,
		uint256 duration,
		bytes32 paymentCurrency,
		uint256 paymentAmount,
		bytes32 subnetID
	);

	function setUp() public override {
		super.setUp();

		renter = randAddress();
		paymentReceiver = randAddress();

		// Setup price feed
		priceFeed = new MockChainlinkPriceFeed(admin, 1 ether);

		// Initialize the mock router
		tjRouter = new MockTraderJoeRouter();
		tjRouter.setToken(address(ggp));

		// Deploy and initialize rental contract
		ProxyAdmin rentalContractProxyAdmin = new ProxyAdmin();
		MockSubnetHardwareRental rentalContractImpl = new MockSubnetHardwareRental();
		TransparentUpgradeableProxy rentalContractTransparentProxy = new TransparentUpgradeableProxy(
			address(rentalContractImpl),
			address(rentalContractProxyAdmin),
			abi.encodeWithSelector(
				MockSubnetHardwareRental.initialize.selector,
				admin,
				address(priceFeed),
				15 days,
				60 ether,
				address(ggp),
				address(wavax),
				address(tjRouter)
			)
		);
		rentalContract = MockSubnetHardwareRental(payable(rentalContractTransparentProxy));

		// Deploy and initialize rental contract
		ProxyAdmin rentalMappingProxyAdmin = new ProxyAdmin();
		SubnetHardwareRentalMapping rentalMappingImpl = new SubnetHardwareRentalMapping();
		TransparentUpgradeableProxy rentalMappingTransparentProxy = new TransparentUpgradeableProxy(
			address(rentalMappingImpl),
			address(rentalMappingProxyAdmin),
			abi.encodeWithSelector(SubnetHardwareRentalMapping.initialize.selector, admin)
		);
		rentalMapping = SubnetHardwareRentalMapping(payable(rentalMappingTransparentProxy));

		vm.startPrank(admin);
		priceFeed.setPrice(1 * 10 ** 8);
		// Grant renter role to renter (which in deployment would be the minipool streamliner)
		rentalContract.grantRole(rentalContract.RENTER_ROLE(), renter);
		vm.stopPrank();
	}

	function testAddHardwareProvider() public {
		vm.startPrank(admin);

		vm.expectEmit(address(rentalContract));
		emit HardwareProviderAdded(MOCK_PROVIDER, paymentReceiver);
		rentalContract.addHardwareProvider(MOCK_PROVIDER, paymentReceiver);

		assertEq(rentalContract.approvedHardwareProviders(MOCK_PROVIDER), paymentReceiver);
		vm.stopPrank();
	}

	function testRemoveHardwareProvider() public {
		vm.startPrank(admin);

		// First add a provider
		rentalContract.addHardwareProvider(MOCK_PROVIDER, paymentReceiver);

		// Then remove it
		vm.expectEmit(address(rentalContract));
		emit HardwareProviderRemoved(MOCK_PROVIDER, paymentReceiver);
		rentalContract.removeHardwareProvider(MOCK_PROVIDER, paymentReceiver);

		assertEq(rentalContract.approvedHardwareProviders(MOCK_PROVIDER), address(0));
		vm.stopPrank();
	}

	function testAddSubnetRentalContract() public {
		vm.startPrank(admin);

		address newSubnetContract = makeAddr("newSubnetContract");
		bytes32 subnetId = keccak256("TestSubnet");

		vm.expectEmit(address(rentalMapping));
		emit SubnetHardwareRentalContractAdded(subnetId, newSubnetContract);
		rentalMapping.addSubnetRentalContract(subnetId, newSubnetContract);

		assertEq(rentalMapping.subnetHardwareRentalContracts(subnetId), newSubnetContract);
		vm.stopPrank();
	}

	function testCannotAddZeroAddressSubnetContract() public {
		vm.startPrank(admin);

		bytes32 subnetId = keccak256("TestSubnet");

		vm.expectRevert(SubnetHardwareRentalMapping.InvalidSubnetContract.selector);
		rentalMapping.addSubnetRentalContract(subnetId, address(0));

		vm.stopPrank();
	}

	function testCannotAddDuplicateSubnetContract() public {
		vm.startPrank(admin);

		address newSubnetContract = makeAddr("newSubnetContract");
		bytes32 subnetId = keccak256("TestSubnet");

		rentalMapping.addSubnetRentalContract(subnetId, newSubnetContract);

		vm.expectRevert(SubnetHardwareRentalMapping.SubnetAlreadyRegistered.selector);
		rentalMapping.addSubnetRentalContract(subnetId, newSubnetContract);

		vm.stopPrank();
	}

	function testRemoveSubnetRentalContract() public {
		vm.startPrank(admin);

		address subnetContract = makeAddr("subnetContract");
		bytes32 subnetId = keccak256("TestSubnet");

		// First add the contract
		rentalMapping.addSubnetRentalContract(subnetId, subnetContract);

		// Then remove it
		vm.expectEmit(address(rentalMapping));
		emit SubnetHardwareRentalContractRemoved(subnetId, subnetContract);
		rentalMapping.removeSubnetRentalContract(subnetId, subnetContract);

		assertEq(rentalMapping.subnetHardwareRentalContracts(subnetId), address(0));
		vm.stopPrank();
	}

	function testCannotRemoveInvalidSubnetContract() public {
		vm.startPrank(admin);

		bytes32 subnetId = keccak256("TestSubnet");
		address invalidContract = makeAddr("invalidContract");

		vm.expectRevert(SubnetHardwareRentalMapping.InvalidSubnetContract.selector);
		rentalMapping.removeSubnetRentalContract(subnetId, invalidContract);

		vm.stopPrank();
	}

	function testSetPayMargin() public {
		vm.startPrank(admin);
		uint256 newMargin = 0.1 ether;
		rentalContract.setPayMargin(newMargin);
		assertEq(rentalContract.payMargin(), newMargin);
		vm.stopPrank();
	}

	function testSetAvaxPriceFeed() public {
		vm.startPrank(admin);
		address newPriceFeed = makeAddr("newPriceFeed");
		rentalContract.setAvaxPriceFeed(newPriceFeed);
		assertEq(rentalContract.avaxPriceFeed(), newPriceFeed);
		vm.stopPrank();
	}

	function testSetPaymentIncrementUsd() public {
		vm.startPrank(admin);
		uint256 newIncrement = 100 ether;
		rentalContract.setPaymentIncrementUsd(newIncrement);
		assertEq(rentalContract.payIncrementUsd(), newIncrement);
		vm.stopPrank();
	}

	function testSetPaymentPeriod() public {
		vm.startPrank(admin);
		uint256 newPeriod = 30 days;
		rentalContract.setPaymentPeriod(newPeriod);
		assertEq(rentalContract.payPeriod(), newPeriod);
		vm.stopPrank();
	}

	function testSetPaymentCurrency() public {
		vm.startPrank(admin);
		bytes32 newCurrency = keccak256(abi.encodePacked("USD"));
		rentalContract.setPaymentCurrency(newCurrency);
		assertEq(rentalContract.paymentCurrency(), newCurrency);
		vm.stopPrank();
	}

	function testGetExpectedPaymentUSD() public {
		uint256 duration = 30 days;
		uint256 expectedPayment = (duration / rentalContract.payPeriod()) * rentalContract.payIncrementUsd();
		assertEq(rentalContract.getExpectedPaymentUSD(duration), expectedPayment);
	}

	function testGetExpectedPaymentAVAX() public {
		uint256 duration = 30 days;
		uint256 paymentUsd = rentalContract.getExpectedPaymentUSD(duration);
		uint256 avaxPrice = rentalContract.getAvaxUsdPrice();
		uint256 expectedAvax = paymentUsd.divWadDown(avaxPrice);
		assertEq(rentalContract.getExpectedPaymentAVAX(duration), expectedAvax);
	}

	function testGetAvaxUsdPrice() public {
		uint256 expectedPrice = 1 ether; // From setUp where we set price to 1 * 10**8 with 8 decimals
		assertEq(rentalContract.getAvaxUsdPrice(), expectedPrice);
	}

	function testCannotGetExpectedPaymentUSDWithZeroPeriod() public {
		vm.startPrank(admin);
		rentalContract.setPaymentPeriod(0);
		vm.stopPrank();

		vm.expectRevert(SubnetHardwareRentalBase.PaymentPeriodNotSet.selector);
		rentalContract.getExpectedPaymentUSD(30 days);
	}

	function testOnlyAdminCanSetParameters() public {
		address nonAdmin = makeAddr("nonAdmin");
		vm.startPrank(nonAdmin);

		vm.expectRevert(
			"AccessControl: account 0x78852e5e959ca1746863fd61273c85f213cf2bff is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
		);
		rentalContract.setPayMargin(1 ether);

		vm.expectRevert(
			"AccessControl: account 0x78852e5e959ca1746863fd61273c85f213cf2bff is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
		);
		rentalContract.setAvaxPriceFeed(address(0));

		vm.expectRevert(
			"AccessControl: account 0x78852e5e959ca1746863fd61273c85f213cf2bff is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
		);
		rentalContract.setPaymentIncrementUsd(1 ether);

		vm.expectRevert(
			"AccessControl: account 0x78852e5e959ca1746863fd61273c85f213cf2bff is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
		);
		rentalContract.setPaymentPeriod(1 days);

		vm.stopPrank();
	}

	function testSwapAvaxForGGP() public {
		uint256 avaxAmount = 1 ether;
		uint256 minTokenOut = 0.5 ether;

		// Fund the contract with AVAX
		vm.deal(address(rentalContract), avaxAmount);

		uint256 tokensPurchased = rentalContract.exposed_swapAvaxForGGP(avaxAmount, minTokenOut);
		assertEq(tokensPurchased, minTokenOut);
		assertEq(ggp.balanceOf(address(rentalContract)), tokensPurchased);
	}

	function testRentHardwareWithGGP() public {
		address user = makeAddr("user");
		bytes memory nodeID = abi.encodePacked(randAddress());
		uint256 duration = 30 days;
		uint256 minTokenOut = 1 ether;
		uint256 expectedGGP = 5 ether;
		bytes32 hardwareProviderName = keccak256("TestProvider");

		// Add hardware provider
		vm.startPrank(admin);
		rentalContract.addHardwareProvider(hardwareProviderName, paymentReceiver);
		vm.stopPrank();

		uint256 hardwareCost = rentalContract.getExpectedPaymentAVAX(duration);
		vm.deal(renter, hardwareCost);

		// Set up the mock router
		tjRouter.setToken(address(ggp));
		tjRouter.setCustomAmount(expectedGGP);

		vm.startPrank(renter);
		vm.expectEmit(address(rentalContract));
		emit HardwareRented(user, nodeID, hardwareProviderName, duration, rentalContract.getPaymentCurrency(), expectedGGP, rentalContract.getSubnetID());
		rentalContract.rentHardware{value: hardwareCost}(user, nodeID, duration, hardwareProviderName, minTokenOut);
		vm.stopPrank();
	}

	function testRentHardwareGGPSwapFailed() public {
		address user = makeAddr("user");
		bytes memory nodeID = abi.encodePacked(randAddress());
		uint256 duration = 30 days;
		uint256 minTokenOut = 1 ether;
		bytes32 hardwareProviderName = keccak256("TestProvider");

		// Add hardware provider
		vm.startPrank(admin);
		rentalContract.addHardwareProvider(hardwareProviderName, paymentReceiver);
		vm.stopPrank();

		uint256 hardwareCost = rentalContract.getExpectedPaymentAVAX(duration);
		vm.deal(renter, hardwareCost);

		// Set up mock router to return less than minTokenOut
		tjRouter.setToken(address(ggp));
		tjRouter.setCustomAmount(minTokenOut - 1);

		vm.startPrank(renter);
		vm.expectRevert(SubnetHardwareRentalBase.SwapFailed.selector);
		rentalContract.rentHardware{value: hardwareCost}(user, nodeID, duration, hardwareProviderName, minTokenOut);
		vm.stopPrank();
	}

	function testRentHardwareInvalidHardwareProvider() public {
		address user = makeAddr("user");
		bytes memory nodeID = abi.encodePacked(randAddress());
		uint256 duration = 30 days;
		uint256 minTokenOut = 1 ether;
		bytes32 hardwareProviderName = keccak256("NonexistentProvider");

		uint256 hardwareCost = rentalContract.getExpectedPaymentAVAX(duration);
		vm.deal(renter, hardwareCost);

		vm.startPrank(renter);
		vm.expectRevert(abi.encodeWithSelector(SubnetHardwareRentalBase.InvalidHardwareProvider.selector, hardwareProviderName));
		rentalContract.rentHardware{value: hardwareCost}(user, nodeID, duration, hardwareProviderName, minTokenOut);
		vm.stopPrank();
	}

	function testRentHardwareInsufficientPayment() public {
		address user = makeAddr("user");
		bytes memory nodeID = abi.encodePacked(randAddress());
		uint256 duration = 30 days;
		uint256 minTokenOut = 1 ether;
		bytes32 hardwareProviderName = keccak256("TestProvider");

		// Add hardware provider
		vm.startPrank(admin);
		rentalContract.addHardwareProvider(hardwareProviderName, paymentReceiver);
		vm.stopPrank();

		uint256 hardwareCost = rentalContract.getExpectedPaymentAVAX(duration);
		uint256 insufficientPayment = hardwareCost - 0.1 ether;
		vm.deal(renter, insufficientPayment);

		vm.startPrank(renter);
		vm.expectRevert(abi.encodeWithSelector(SubnetHardwareRentalBase.InsufficientAVAXPayment.selector, hardwareCost, insufficientPayment));
		rentalContract.rentHardware{value: insufficientPayment}(user, nodeID, duration, hardwareProviderName, minTokenOut);
		vm.stopPrank();
	}
}
