// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {IHardwareProvider} from "../interface/IHardwareProvider.sol";

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

import {AggregatorV3Interface} from "chainlink/interfaces/AggregatorV3Interface.sol";

contract ArtifactHardwareProvider is IHardwareProvider, AccessControl {
	using SafeTransferLib for address;
	using FixedPointMathLib for uint256;

	event PaymentReceiverUpdated(address oldPaymentReceiver, address newPaymentReceiver);

	error InsufficientPayment(uint256 expectedPayment, uint256 actualPayment);
	error ExcessivePayment(uint256 expectedPayment, uint256 actualPayment);
	error ZeroAddress();
	error ZeroNodeID();
	error ZeroDuration();

	address public avaxPriceFeed;

	uint256 public payIncrementUsd;
	uint256 public payPeriod;
	uint256 public payMargin;

	bytes32 public RENTER_ROLE = keccak256("RENTER_ROLE");

	constructor(address admin, address _paymentReceiver, address _avaxPriceFeed) {
		_grantRole(DEFAULT_ADMIN_ROLE, admin);
		paymentReceiver = _paymentReceiver;
		avaxPriceFeed = _avaxPriceFeed;

		payIncrementUsd = 60 ether;
		payPeriod = 15 days;
		payMargin = 0.05 ether;
	}

	/// @notice Only allow calls from addresses with RENTER_ROLE, i.e. MinipoolStreamliner
	modifier onlyRenter() {
		_checkRole(RENTER_ROLE, _msgSender());
		_;
	}

	/// @notice Only allow calls from address with DEFAULT_ADMIN_ROLE
	modifier onlyAdmin() {
		_checkRole(DEFAULT_ADMIN_ROLE, _msgSender());
		_;
	}

	/// @notice Initiate hardware rental with Artifact
	///
	/// @param user 		Address of the user to subscribe
	/// @param nodeID 	Id of node to be made a validator
	/// @param duration Subscription length
	function rentHardware(address user, address nodeID, uint256 duration) external payable override onlyRenter {
		if (user == address(0x0)) {
			revert ZeroAddress();
		}
		if (nodeID == address(0x0)) {
			revert ZeroNodeID();
		}
		if (duration == 0) {
			revert ZeroDuration();
		}
		uint256 avaxUsdPrice = getAvaxUsdPrice();
		uint256 expectedPaymentUsd = getExpectedPayment(duration);
		uint256 userUsdEquivalent = uint256(msg.value).mulWadDown(avaxUsdPrice);

		uint256 upperMargin = expectedPaymentUsd.mulWadDown(payMargin);

		if (userUsdEquivalent < expectedPaymentUsd) {
			revert InsufficientPayment(expectedPaymentUsd, userUsdEquivalent);
		}
		if (userUsdEquivalent > expectedPaymentUsd + upperMargin) {
			revert ExcessivePayment(expectedPaymentUsd, userUsdEquivalent);
		}

		paymentReceiver.safeTransferETH(msg.value);

		emit HardwareRented(user, nodeID, getHardwareProviderName(), duration, msg.value);
	}

	/// @notice Update address that receives hardware subscription payments
	/// @param newPaymentReceiver Address to receive payments
	function setPaymentReceiver(address newPaymentReceiver) external onlyAdmin {
		if (newPaymentReceiver == address(0x0)) {
			revert ZeroAddress();
		}
		address oldPaymentReceiver = paymentReceiver;
		paymentReceiver = newPaymentReceiver;
		emit PaymentReceiverUpdated(oldPaymentReceiver, newPaymentReceiver);
	}

	/// @notice Update length of each calculated pay period
	/// @param newPayPeriod Duration in seconds of pay period
	function setPayPeriod(uint256 newPayPeriod) external onlyAdmin {
		payPeriod = newPayPeriod;
	}

	/// @notice Update payment amount per pay period
	/// @param newPayIncrementUsd New usd amount per period
	function setPayIncrementUsd(uint256 newPayIncrementUsd) external onlyAdmin {
		payIncrementUsd = newPayIncrementUsd;
	}

	/// @notice Update amount of overpayment allowed
	/// @param newPayMargin percentage overpayment allowed in ether. 0.05 ether = 5%
	function setPayMargin(uint256 newPayMargin) external onlyAdmin {
		payMargin = newPayMargin;
	}

	/// @notice Set address of Chainlink AVAX / USD price feed
	/// @param newAvaxPriceFeed Address of new feed
	function setAvaxPriceFeed(address newAvaxPriceFeed) external onlyAdmin {
		avaxPriceFeed = newAvaxPriceFeed;
	}

	/// @notice Get expected payment amount in USD
	/// @return uint256 Amount to pay in USD
	function getExpectedPayment(uint256 duration) public view returns (uint256) {
		uint256 payPeriods = duration / payPeriod;
		return payPeriods * payIncrementUsd;
	}

	/// @notice Get expected payment amount in AVAX
	/// @return uint256 Amount to pay in AVAX
	function getExpectedPaymentAvax(uint256 duration) public view returns (uint256) {
		uint256 paymentInUsd = getExpectedPayment(duration);
		uint256 avaxUsdPrice = getAvaxUsdPrice();
		return paymentInUsd.divWadDown(avaxUsdPrice);
	}

	/// @notice Get chainlink AVAX / USD and return it in ether units
	/// @return uint256 AVAX price in USD
	function getAvaxUsdPrice() public view returns (uint256) {
		(, int256 answer, , , ) = AggregatorV3Interface(avaxPriceFeed).latestRoundData();
		uint8 decimals = AggregatorV3Interface(avaxPriceFeed).decimals();
		uint256 scalingFactor = 18 - decimals;
		return uint256(answer) * 10 ** scalingFactor;
	}

	/// @notice Get the bytes32 name of this hardware provider
	/// @return Bytes32 encoded name of the hardware provider
	function getHardwareProviderName() public pure override returns (bytes32) {
		return keccak256(abi.encodePacked("Artifact"));
	}
}
