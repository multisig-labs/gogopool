// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeTokenggAVAX is Script, EnvironmentConfig {
    function run() external {
        loadAddresses();
        loadUsers();
        address deployer = getUser("deployer");
        require(deployer.balance > 0.1 ether, "Insufficient funds to deploy");

        vm.startBroadcast(deployer);

        /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
        /*                DEPLOY TokenggAVAX V2 IMPL                  */
        /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/
        TokenggAVAX tokenggAVAXImplV2 = new TokenggAVAX();

        TransparentUpgradeableProxy proxy = TransparentUpgradeableProxy(payable(getAddress("TokenggAVAX")));

        // Get the WAVAX asset from the current proxy for reference
        TokenggAVAX currentToken = TokenggAVAX(payable(address(proxy)));
        address wavaxAsset = address(currentToken.asset());

        saveAddress("TokenggAVAXImpl", address(tokenggAVAXImplV2));

        console2.log("TokenggAVAX V2 implementation deployed at:", address(tokenggAVAXImplV2));
        console2.log("Proxy address:", address(proxy));
        console2.log("WAVAX asset:", wavaxAsset);

        // Generate the encoded data for upgradeAndCall
        bytes memory reinitializeData = abi.encodeWithSelector(TokenggAVAX.reinitialize.selector, wavaxAsset);

        console2.log("\n=== GOVERNANCE TRANSACTION DATA ===");
        console2.log("ProxyAdmin address:", getAddress("TokenggAVAXAdmin"));
        console2.log("Function: upgradeAndCall(address,address,bytes)");
        console2.log("Proxy (arg 1):", address(proxy));
        console2.log("New Implementation (arg 2):", address(tokenggAVAXImplV2));
        console2.log("Reinitialize Data (arg 3):");
        console2.logBytes(reinitializeData);

        // Generate complete Gnosis Safe transaction calldata
        bytes memory upgradeCallData = abi.encodeWithSignature(
            "upgradeAndCall(address,address,bytes)",
            address(proxy),
            address(tokenggAVAXImplV2),
            reinitializeData
        );

        console2.log("\n=== GNOSIS SAFE TRANSACTION ===");
        console2.log("To:", getAddress("TokenggAVAXAdmin"));
        console2.log("Value: 0");
        console2.log("Data:");
        console2.logBytes(upgradeCallData);


        vm.stopBroadcast();
    }
}
