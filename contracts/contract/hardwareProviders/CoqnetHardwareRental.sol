// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {SubnetHardwareRentalBase} from "./SubnetHardwareRentalBase.sol";
import {TokenGGP} from "../tokens/TokenGGP.sol";
import {FixedPointMathLib} from "@rari-capital/solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@rari-capital/solmate/src/utils/SafeTransferLib.sol";

contract CoqnetHardwareRental is SubnetHardwareRentalBase {
	using FixedPointMathLib for uint256;
	using SafeTransferLib for address;
	using SafeTransferLib for TokenGGP;

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
		address _tjRouter
	) public override initializer {
		super.initialize(admin, _avaxPriceFeed, _initialPayPeriod, _initialPayIncrementUsd, _ggpAddr, _wavaxAddr, _tjRouter);

		subnetName = keccak256(abi.encodePacked("Coqnet"));
		subnetID = 0x0ad6355dc6b82cd375e3914badb3e2f8d907d0856f8e679b2db46f8938a2f012; //mainnet
		payMargin = 0.05 ether;
		paymentCurrency = keccak256(abi.encodePacked("GGP"));
	}

	/// @notice Initiate hardware rental for Avalanche
	/// @param user 		Address of the user to subscribe
	/// @param nodeID 	Id of node to be made a validator
	/// @param duration Subscription length
	/// @param hardwareProviderName Name of the hardware provider to use
	/// @param minTokenOut Minimum amount of the token amount that is expected from the swap - best calculated off chain
	function rentHardware(
		address user,
		bytes calldata nodeID,
		uint256 duration,
		bytes32 hardwareProviderName,
		uint256 minTokenOut
	) external payable override onlyRenter {
		if (user == address(0x0)) {
			revert ZeroAddress();
		}
		if (nodeID.length == 0) {
			revert ZeroNodeID();
		}
		if (duration == 0) {
			revert ZeroDuration();
		}
		if (hardwareProviderName == bytes32(0) || approvedHardwareProviders[hardwareProviderName] == address(0x0)) {
			revert InvalidHardwareProvider(hardwareProviderName);
		}

		// Verify enough AVAX was sent
		if (msg.value < getExpectedPaymentAVAX(duration)) {
			revert InsufficientAVAXPayment(getExpectedPaymentAVAX(duration), msg.value);
		}

		uint256 avaxUsdPrice = getAvaxUsdPrice();
		uint256 expectedPaymentUsd = getExpectedPaymentUSD(duration);
		uint256 userUsdEquivalent = uint256(msg.value).mulWadDown(avaxUsdPrice);

		uint256 upperMargin = expectedPaymentUsd.mulWadDown(payMargin);

		if (userUsdEquivalent < expectedPaymentUsd) {
			revert InsufficientPayment(expectedPaymentUsd, userUsdEquivalent);
		}
		if (userUsdEquivalent > expectedPaymentUsd + upperMargin) {
			revert ExcessivePayment(expectedPaymentUsd, userUsdEquivalent);
		}

		address paymentReceiver = approvedHardwareProviders[hardwareProviderName];

		//For Coqnet, hardware providers are paid in GGP
		uint256 ggpPurchased = swapAvaxForGGP(msg.value, minTokenOut);
		TokenGGP ggp = TokenGGP(GGP_ADDR);
		ggp.safeTransfer(paymentReceiver, ggpPurchased);

		emit HardwareRented(user, nodeID, hardwareProviderName, duration, paymentCurrency, ggpPurchased, subnetID);
	}
}
