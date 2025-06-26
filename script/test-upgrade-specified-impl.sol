// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import {EnvironmentConfig} from "./EnvironmentConfig.s.sol";
import {TokenggAVAX} from "../contracts/contract/tokens/TokenggAVAX.sol";
import {ERC20} from "@rari-capital/solmate/src/mixins/ERC4626.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract TestSpecificImplementation is Script, EnvironmentConfig {
    function run() external {
        // Get implementation address from environment variable
        address implementationAddress = vm.envAddress("IMPLEMENTATION_ADDRESS");

        loadAddresses();

        address tokenggAVAXProxy = getAddress("TokenggAVAX");
        address proxyAdmin = 0x5313c309CD469B751Ad3947568D65d4a70B247cF;
        address timelock = 0xcd385F1947D532186f3F6aaa93966E3e9C14af41;

        console2.log("=== TESTING SPECIFIC IMPLEMENTATION ===");
        console2.log("Implementation to test:", implementationAddress);
        console2.log("Proxy address:", tokenggAVAXProxy);

        // Get current state before upgrade
        TokenggAVAX currentToken = TokenggAVAX(payable(tokenggAVAXProxy));
        string memory oldName = currentToken.name();
        string memory oldSymbol = currentToken.symbol();
        address wavaxAsset = address(currentToken.asset());
        uint256 totalAssetsBefore = currentToken.totalAssets();
        uint256 totalSupplyBefore = currentToken.totalSupply();

        console2.log("=== PRE-UPGRADE STATE ===");
        console2.log("Current name:", oldName);
        console2.log("Current symbol:", oldSymbol);
        console2.log("WAVAX asset:", wavaxAsset);
        console2.log("Total assets:", totalAssetsBefore);
        console2.log("Total supply:", totalSupplyBefore);

        // Generate reinitialize data
        bytes memory reinitializeData = abi.encodeWithSelector(TokenggAVAX.reinitialize.selector, wavaxAsset);

        console2.log("=== EXECUTING UPGRADE ===");
        console2.log("Impersonating timelock:", timelock);

        // Impersonate the timelock to execute the upgrade
        vm.startPrank(timelock);

        // Execute the upgrade through ProxyAdmin
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            TransparentUpgradeableProxy(payable(tokenggAVAXProxy)), implementationAddress, reinitializeData
        );

        vm.stopPrank();

        console2.log("Upgrade executed successfully!");

        // Verify the upgrade worked
        TokenggAVAX upgradedToken = TokenggAVAX(payable(tokenggAVAXProxy));
        uint256 totalAssetsAfter = upgradedToken.totalAssets();
        uint256 totalSupplyAfter = upgradedToken.totalSupply();

        console2.log("=== POST-UPGRADE STATE ===");
        console2.log("New name:", upgradedToken.name());
        console2.log("New symbol:", upgradedToken.symbol());
        console2.log("Total assets:", totalAssetsAfter);
        console2.log("Total supply:", totalSupplyAfter);

        // Verify changes
        require(
            keccak256(bytes(upgradedToken.name())) == keccak256(bytes("Hypha Staked AVAX")),
            "Name not updated correctly"
        );
        require(keccak256(bytes(upgradedToken.symbol())) == keccak256(bytes("stAVAX")), "Symbol not updated correctly");
        require(totalAssetsAfter == totalAssetsBefore, "Total assets changed unexpectedly");
        require(totalSupplyAfter == totalSupplyBefore, "Total supply changed unexpectedly");

        console2.log("=== VERIFICATION COMPLETE ===");
        console2.log("Check! Name changed from", oldName, "to", upgradedToken.name());
        console2.log("Check! Symbol changed from", oldSymbol, "to", upgradedToken.symbol());
        console2.log("Check! Assets preserved:", totalAssetsAfter);
        console2.log("Check! Supply preserved:", totalSupplyAfter);

        console2.log("=== TEST SUMMARY ===");
        console2.log("Tested implementation:", implementationAddress);
        console2.log("Proxy address:", tokenggAVAXProxy);
        console2.log("All tests passed! Check!");
    }
}
