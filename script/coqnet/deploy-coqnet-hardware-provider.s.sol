// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {CoqnetHardwareRental} from "../../contracts/contract/hardwareProviders/CoqnetHardwareRental.sol";
import {EnvironmentConfig} from "../EnvironmentConfig.s.sol";

import {MockChainlinkPriceFeed} from "../../test/unit/utils/MockChainlink.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployMultipleHWPUpgrades is Script, EnvironmentConfig {
	function run() external {
		loadAddresses();
		loadUsers();
		address deployer = getUser("deployer");
		require(deployer.balance > 0.5 ether, "Insufficient funds to deploy");

		vm.startBroadcast(deployer);

		address chainlinkPriceFeed;
		uint256 initialPayPeriodCoqnet;
		uint256 initialPayIncrementUsdCoqnet;

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              SETUP CHAINS             	                    */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		if (block.chainid == 43113) {
			MockChainlinkPriceFeed mockChainlinkPriceFeed = new MockChainlinkPriceFeed(deployer, 1 ether);
			chainlinkPriceFeed = address(mockChainlinkPriceFeed);
			mockChainlinkPriceFeed.setPrice(1 * 10 ** 8);
			console2.log("MockChainlinkPriceFeed", address(mockChainlinkPriceFeed));

			initialPayPeriodCoqnet = 1 days;
			initialPayIncrementUsdCoqnet = 1 ether;
		}
		// double check these addys
		if (block.chainid == 43114) {
			initialPayPeriodCoqnet = 30 days;
			initialPayIncrementUsdCoqnet = 40 ether;
		}

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              DEPLOY SUBNET CONTRACTS                       */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		ProxyAdmin coqnetHardwareRentalProxyAdmin = new ProxyAdmin();

		CoqnetHardwareRental coqnetHardwareRentalImpl = new CoqnetHardwareRental();

		TransparentUpgradeableProxy coqnetHardwareRentalTransparentProxy = new TransparentUpgradeableProxy(
			address(coqnetHardwareRentalImpl),
			address(coqnetHardwareRentalProxyAdmin),
			abi.encodeWithSelector(
				CoqnetHardwareRental.initialize.selector,
				vm.envAddress("GUARDIAN"),
				chainlinkPriceFeed,
				initialPayPeriodCoqnet,
				initialPayIncrementUsdCoqnet,
				vm.envAddress("GGP"),
				vm.envAddress("WAVAX"),
				vm.envAddress("TJ_ROUTER")
			)
		);
		CoqnetHardwareRental coqnetHardwareRental = CoqnetHardwareRental(payable(coqnetHardwareRentalTransparentProxy));

		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(payable(getAddress("SubnetHardwareRentalMapping")));

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              SET HARDWARE PROVIDER PAYMENT CONFIGS         */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		if (block.chainid == 43113) {
			subnetHardwareRentalMapping.addSubnetRentalContract(
				0x080fa7727ac2b73292de264684f469732687b61977ae5e95d79727a2e8dd7c54,
				address(coqnetHardwareRental)
			);
			coqnetHardwareRental.addHardwareProvider(bytes32("Artifact"), deployer);
		} else if (block.chainid == 43114) {
			//  *******ALERT ALERT****** SET THE STUPID AVAX PRICE FEED: 0x0A77230d17318075983913bC2145DB16C7366156
			coqnetHardwareRental.setAvaxPriceFeed(0x0A77230d17318075983913bC2145DB16C7366156);
			// coqnetHardwareRental.addHardwareProvider(
			// 	0x9e8a01bb951fb38ff9aa0ddecfcda59c7d92b7e1569928f14e6d7bd3cce2f860,
			// 	address(0xba8Bcb4EB9a90D5A0eAe0098496703b49f909cB2)
			// ); // ARTIFACT
		}

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              GRANT ROLES                                   */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		// coqnetHardwareRental.grantRole(coqnetHardwareRental.DEFAULT_ADMIN_ROLE(), vm.envAddress("GUARDIAN"));
		coqnetHardwareRentalProxyAdmin.transferOwnership(vm.envAddress("GUARDIAN"));

		saveAddress("CoqnetHardwareRental", address(coqnetHardwareRental));
		saveAddress("CoqnetHardwareRentalImpl", address(coqnetHardwareRentalImpl));
		saveAddress("CoqnetHardwareRentalAdmin", address(coqnetHardwareRentalProxyAdmin));

		vm.stopBroadcast();
	}
}
