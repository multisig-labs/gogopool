// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {TokenGGP} from "../../contract/tokens/TokenGGP.sol";
import {IERC20} from "../../interface/IERC20.sol";
import {ILBRouter} from "../../interface/ILBRouter.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";
import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

abstract contract SubnetHardwareRentalBase is Initializable, AccessControlUpgradeable {
	using SafeTransferLib for address;
	using SafeTransferLib for TokenGGP;
	using FixedPointMathLib for uint256;

	address public GGP_ADDR;
	address public WAVAX_ADDR;
	address public JOE_LB_ROUTER;
	address public avaxPriceFeed;
	uint256 public payMargin;
	bytes32 public RENTER_ROLE;
	bytes32 public subnetName;
	bytes32 public subnetID;

	bytes32 public paymentCurrency;
	uint256 public payPeriod;
	uint256 public payIncrementUsd;

	//mapping of hardware provider name to payment receiver - data lives in inherited contract
	mapping(bytes32 => address) public approvedHardwareProviders;

	error SwapFailed();
	error InsufficientAVAXPayment(uint256 expectedPaymentAVAX, uint256 userPaymentAVAX);
	error InsufficientPayment(uint256 expectedPayment, uint256 actualPayment);
	error ExcessivePayment(uint256 expectedPayment, uint256 actualPayment);
	error ZeroAddress();
	error ZeroNodeID();
	error ZeroDuration();
	error PaymentPeriodNotSet();
	error InvalidSubnetContract();
	error SubnetAlreadyRegistered();
	error InvalidPaymentReceiver();
	error InvalidHardwareProvider(bytes32 hardwareProviderName);

	event HardwareRented(
		address user,
		bytes nodeID,
		bytes32 hardwareProviderName,
		uint256 duration,
		bytes32 paymentCurrency,
		uint256 paymentAmount,
		bytes32 subnetID
	);
	event HardwareProviderAdded(bytes32 indexed hardwareProviderName, address indexed paymentReceiver);
	event HardwareProviderRemoved(bytes32 indexed hardwareProviderName, address indexed paymentReceiver);
	event SubnetHardwareRentalContractAdded(bytes32 indexed subnetId, address indexed contractAddress);
	event SubnetHardwareRentalContractRemoved(bytes32 indexed subnetId, address indexed contractAddress);

	/// @custom:oz-upgrades-unsafe-allow constructor
	constructor() {
		_disableInitializers();
	}

	function initialize(
		address admin,
		address _avaxPriceFeed,
		uint256 _initialPayPeriod,
		uint256 _initialPayIncrementUsd,
		address _ggpAddr,
		address _wavaxAddr,
		address _joeLbRouter
	) public virtual initializer {
		__AccessControl_init();

		GGP_ADDR = _ggpAddr;
		WAVAX_ADDR = _wavaxAddr;
		JOE_LB_ROUTER = _joeLbRouter;
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		avaxPriceFeed = _avaxPriceFeed;
		RENTER_ROLE = keccak256("RENTER_ROLE");

		payPeriod = _initialPayPeriod;
		payIncrementUsd = _initialPayIncrementUsd;
	}

	modifier onlyRenter() {
		_checkRole(RENTER_ROLE, _msgSender());
		_;
	}

	modifier onlyAdmin() {
		_checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_;
	}

	/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
	/*              INHERITED SUBNET SPECIFIC DETAILS             */
	/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

	/// @notice Initiate hardware rental with provider
	/// @param user 		Address of the user to subscribe
	/// @param nodeID 	Id of node to be made a validator
	/// @param duration Subscription length
	/// @param minTokenAmountOut Minimum amount of token that is expected from the swap to pay hw provider - best calculated off chain
	function rentHardware(
		address user,
		bytes calldata nodeID,
		uint256 duration,
		bytes32 hardwareProviderName,
		uint256 minTokenAmountOut
	) external payable virtual {}

	function getSubnetName() public view virtual returns (bytes32) {
		return subnetName;
	}

	/// @dev This is the subnetID converted to bytes32
	function getSubnetID() public view virtual returns (bytes32) {
		return subnetID;
	}

	function getPaymentCurrency() public view virtual returns (bytes32) {
		return paymentCurrency;
	}

	function getHardwareProviderPaymentAddress(bytes32 hardwareProviderName) public view returns (address) {
		return approvedHardwareProviders[hardwareProviderName];
	}

	/// @notice Add an approved hardware provider with payment address
	/// @param providerName Bytes32 name of the hardware provider
	/// @param paymentReceiver Hardware Provider contract address
	function addHardwareProvider(bytes32 providerName, address paymentReceiver) external onlyAdmin {
		approvedHardwareProviders[providerName] = paymentReceiver;
		emit HardwareProviderAdded(providerName, paymentReceiver);
	}

	/// @notice Remove an approved hardware provider
	/// @param providerName Name of the hardware provider
	/// @param paymentReceiver Address of the current payment receiver for that hardware provider
	function removeHardwareProvider(bytes32 providerName, address paymentReceiver) external onlyAdmin {
		if (approvedHardwareProviders[providerName] != paymentReceiver) {
			revert InvalidPaymentReceiver();
		}
		approvedHardwareProviders[providerName] = address(0x0);
		emit HardwareProviderRemoved(providerName, paymentReceiver);
	}

	/// @notice Set the payment margin, a percentage in ether
	/// @param newPayMargin The new payment margin
	function setPayMargin(uint256 newPayMargin) external onlyAdmin {
		payMargin = newPayMargin;
	}

	/// @notice Set the AVAX price feed
	/// @param newAvaxPriceFeed The new AVAX price feed
	function setAvaxPriceFeed(address newAvaxPriceFeed) external onlyAdmin {
		avaxPriceFeed = newAvaxPriceFeed;
	}

	/// @notice Set the payment increment in USD
	/// @param newPaymentIncrementUsd The new payment increment in USD
	function setPaymentIncrementUsd(uint256 newPaymentIncrementUsd) external onlyAdmin {
		payIncrementUsd = newPaymentIncrementUsd;
	}

	/// @notice Set the payment period
	/// @param newPaymentPeriod The new payment period (denominated in seconds)
	function setPaymentPeriod(uint256 newPaymentPeriod) external onlyAdmin {
		payPeriod = newPaymentPeriod;
	}

	/// @notice Set the payment currency
	/// @param newPaymentCurrency The new payment currency
	function setPaymentCurrency(bytes32 newPaymentCurrency) external onlyAdmin {
		paymentCurrency = newPaymentCurrency;
	}

	/// @notice Get the expected payment in USD
	/// @param duration The duration of the subscription
	/// @return paymentInUsd The expected payment in USD
	function getExpectedPaymentUSD(uint256 duration) public view returns (uint256) {
		if (payPeriod <= 0) {
			revert PaymentPeriodNotSet();
		}

		uint256 payPeriods = duration / payPeriod;
		return payPeriods * payIncrementUsd;
	}

	/// @notice Get the expected payment in AVAX
	/// @param duration The duration of the subscription
	/// @return paymentInAvax The expected payment in AVAX
	function getExpectedPaymentAVAX(uint256 duration) public view returns (uint256) {
		uint256 paymentInUsd = getExpectedPaymentUSD(duration);
		uint256 avaxUsdPrice = getAvaxUsdPrice();
		return paymentInUsd.divWadDown(avaxUsdPrice);
	}

	/// @notice Get the price of AVAX in USD
	/// @return price The price of AVAX in USD
	function getAvaxUsdPrice() public view returns (uint256) {
		(, int256 answer, , , ) = AggregatorV3Interface(avaxPriceFeed).latestRoundData();
		uint8 decimals = AggregatorV3Interface(avaxPriceFeed).decimals();
		uint256 scalingFactor = 18 - decimals;
		return uint256(answer) * 10 ** scalingFactor;
	}

	/// @notice Swaps AVAX for GGP
	/// @dev The tokens stay in the inherited contract
	/// @param avaxForToken The amount of avax the user has sent to be swapped for the desired token
	/// @param minTokenOut Minimum amount of the token amount that is expected from the swap - best calculated off chain
	/// @return tokenPurchased The amount of the token obtained from the swap
	function swapAvaxForGGP(uint256 avaxForToken, uint256 minTokenOut) internal returns (uint256 tokenPurchased) {
		TokenGGP ggp = TokenGGP(GGP_ADDR);

		// Get balance before swap
		uint256 balanceBefore = ggp.balanceOf(address(this));

		IERC20[] memory tokenPath = new IERC20[](2);
		uint256[] memory pairBinSteps = new uint256[](1);
		ILBRouter.Version[] memory versions = new ILBRouter.Version[](1);

		tokenPath[0] = IERC20(WAVAX_ADDR);
		tokenPath[1] = IERC20(address(ggp));

		// ggp specific
		pairBinSteps[0] = 0; // Bin step of 0 points to the Joe V1 pair
		versions[0] = ILBRouter.Version.V1;

		ILBRouter.Path memory path;
		path.pairBinSteps = pairBinSteps;
		path.versions = versions;
		path.tokenPath = tokenPath;

		tokenPurchased = ILBRouter(JOE_LB_ROUTER).swapExactNATIVEForTokens{value: avaxForToken}(minTokenOut, path, address(this), block.timestamp + 1);

		// Compare balance difference in the contract
		uint256 balanceAfter = ggp.balanceOf(address(this));
		if (balanceAfter - balanceBefore < tokenPurchased || tokenPurchased < minTokenOut) {
			revert SwapFailed();
		}

		return tokenPurchased;
	}
}
