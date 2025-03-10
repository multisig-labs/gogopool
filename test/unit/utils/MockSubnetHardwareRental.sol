// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.17;

import {SubnetHardwareRentalBase} from "../../../contracts/contract/hardwareProviders/SubnetHardwareRentalBase.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MockSubnetHardwareRental is SubnetHardwareRentalBase {
	mapping(address => bool) public hasHardware;

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
	) public override initializer {
		super.initialize(admin, _avaxPriceFeed, _initialPayPeriod, _initialPayIncrementUsd, _ggpAddr, _wavaxAddr, _joeLbRouter);

		subnetName = keccak256(abi.encodePacked("MockSubnet"));
		subnetID = bytes32(0);
		payMargin = 0.05 ether;
		paymentCurrency = keccak256(abi.encodePacked("AVAX"));
	}

	function rentHardware(
		address user,
		bytes calldata nodeID,
		uint256 duration,
		bytes32 hardwareProviderName,
		uint256 minTokenAmountOut
	) external payable override {
		if (hardwareProviderName == bytes32(0) || approvedHardwareProviders[hardwareProviderName] == address(0x0)) {
			revert InvalidHardwareProvider(hardwareProviderName);
		}
		uint256 expectedPayment = getExpectedPaymentAVAX(duration);
		if (msg.value < expectedPayment) {
			revert InsufficientAVAXPayment(expectedPayment, msg.value);
		}

		uint256 tokensPurchased = swapAvaxForGGP(msg.value, minTokenAmountOut);
		hasHardware[user] = true;
		emit HardwareRented(user, nodeID, hardwareProviderName, duration, paymentCurrency, tokensPurchased, subnetID);
	}

	function exposed_swapAvaxForGGP(uint256 avaxAmount, uint256 minTokenAmountOut) external returns (uint256) {
		return swapAvaxForGGP(avaxAmount, minTokenAmountOut);
	}
}
