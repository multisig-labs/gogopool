// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX as TokenggAVAXV1} from "../contracts/contract/previousVersions/TokenggAVAXV1.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {Timelock} from "../contracts/contract/Timelock.sol";
import {ProtocolDAO} from "../contracts/contract/ProtocolDAO.sol";

import {WAVAX} from "../contracts/contract/utils/WAVAX.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

contract DeployTokenggAVAX is Script, EnvironmentConfig {
	function run() external {
		vm.startBroadcast();
		if (block.chainid != 43113) {
			revert("Not supported on this network");
		}

		loadAddresses();

		address existingTokenggAVAX = vm.envAddress("TOKEN_GG_AVAX");
		address storageAddr = getAddress("Storage");
		address wavaxAddr = getAddress("WAVAX");
		WAVAX wavax = WAVAX(payable(wavaxAddr));

		Timelock timelock = new Timelock();
		console2.log("Timelock deployed at", address(timelock));

		ProxyAdmin proxyAdmin = new ProxyAdmin();
		console2.log("ProxyAdmin deployed at", address(proxyAdmin));

		TokenggAVAX ggAVAXImpl = new TokenggAVAX();
		console2.log("TokenggAVAXImpl deployed at", address(ggAVAXImpl));

		TransparentUpgradeableProxy ggAVAXProxy = new TransparentUpgradeableProxy(
			address(ggAVAXImpl),
			address(proxyAdmin),
			abi.encodeWithSelector(ggAVAXImpl.initialize.selector, storageAddr, wavax, 0)
		);

		TokenggAVAX ggAVAX = TokenggAVAX(payable(ggAVAXProxy));
		console2.log("TokenggAVAX deployed at", address(ggAVAX));

		ProtocolDAO dao = ProtocolDAO(getAddress("ProtocolDAO"));
		dao.upgradeContract("TokenggAVAX", existingTokenggAVAX, address(ggAVAX));
		console2.log("TokenggAVAX upgraded to", address(ggAVAX));

		ggAVAX.depositAVAX{value: 1 ether}();
		ggAVAX.syncRewards();

		proxyAdmin.transferOwnership(address(timelock));
		console2.log("ProxyAdmin ownership transferred to Timelock");

		saveAddress("TokenggAVAX", address(ggAVAX));
		saveAddress("TokenggAVAXAdmin", address(proxyAdmin));
		saveAddress("TokenggAVAXImpl", address(ggAVAXImpl));

		saveAddress("Timelock", address(timelock));
		vm.stopBroadcast();
	}
}
