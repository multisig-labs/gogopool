// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {SubnetHardwareRentalMapping} from "../../contracts/contract/hardwareProviders/SubnetHardwareRentalMapping.sol";
import {AvalancheHardwareRental} from "../../contracts/contract/hardwareProviders/AvalancheHardwareRental.sol";
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
		uint256 initialPayPeriodAvalanche;
		uint256 initialPayIncrementUsdAvalanche;

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              SETUP CHAINS             	                    */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		if (block.chainid == 43113) {
			MockChainlinkPriceFeed mockChainlinkPriceFeed = new MockChainlinkPriceFeed(deployer, 1 ether);
			chainlinkPriceFeed = address(mockChainlinkPriceFeed);
			mockChainlinkPriceFeed.setPrice(1 * 10 ** 8);
			console2.log("MockChainlinkPriceFeed", address(mockChainlinkPriceFeed));

			initialPayPeriodAvalanche = 1 days;
			initialPayIncrementUsdAvalanche = 1 ether;
		}

		if (block.chainid == 43114) {
			initialPayPeriodAvalanche = 15 days;
			initialPayIncrementUsdAvalanche = 60 ether;
		}

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              DEPLOY SUBNET CONTRACTS                       */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		ProxyAdmin avalancheHardwareRentalProxyAdmin = new ProxyAdmin();

		AvalancheHardwareRental avalancheHardwareRentalImpl = new AvalancheHardwareRental();

		TransparentUpgradeableProxy avalancheHardwareRentalTransparentProxy = new TransparentUpgradeableProxy(
			address(avalancheHardwareRentalImpl),
			address(avalancheHardwareRentalProxyAdmin),
			abi.encodeWithSelector(
				AvalancheHardwareRental.initialize.selector,
				vm.envAddress("GUARDIAN"),
				chainlinkPriceFeed,
				initialPayPeriodAvalanche,
				initialPayIncrementUsdAvalanche,
				vm.envAddress("GGP"),
				vm.envAddress("WAVAX"),
				vm.envAddress("TJ_ROUTER")
			)
		);
		AvalancheHardwareRental avalancheHardwareRental = AvalancheHardwareRental(payable(avalancheHardwareRentalTransparentProxy));
		avalancheHardwareRentalProxyAdmin.transferOwnership(vm.envAddress("GUARDIAN"));

		SubnetHardwareRentalMapping subnetHardwareRentalMapping = SubnetHardwareRentalMapping(payable(getAddress("SubnetHardwareRentalMapping")));

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              SET HARDWARE PROVIDER PAYMENT CONFIGS         */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		if (block.chainid == 43113) {
			subnetHardwareRentalMapping.addSubnetRentalContract(
				0x0000000000000000000000000000000000000000000000000000000000000000,
				address(avalancheHardwareRental)
			);
			avalancheHardwareRental.addHardwareProvider(bytes32("Artifact"), deployer); // set here
		} else if (block.chainid == 43114) {
			avalancheHardwareRental.setAvaxPriceFeed(0x0A77230d17318075983913bC2145DB16C7366156);
			avalancheHardwareRental.addHardwareProvider(
				0x9e8a01bb951fb38ff9aa0ddecfcda59c7d92b7e1569928f14e6d7bd3cce2f860,
				address(0xba8Bcb4EB9a90D5A0eAe0098496703b49f909cB2)
			);
		}

		/*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
		/*              GRANT ROLES                                   */
		/*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
		// avalancheHardwareRental.grantRole(avalancheHardwareRental.DEFAULT_ADMIN_ROLE(), vm.envAddress("GUARDIAN"));

		saveAddress("AvalancheHardwareRental", address(avalancheHardwareRental));
		saveAddress("AvalancheHardwareRentalImpl", address(avalancheHardwareRentalImpl));
		saveAddress("AvalancheHardwareRentalAdmin", address(avalancheHardwareRentalProxyAdmin));

		vm.stopBroadcast();
	}
}
