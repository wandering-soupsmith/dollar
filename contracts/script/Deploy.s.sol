// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DollarStore.sol";

contract DeployScript is Script {
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);

        // Sepolia testnet stablecoin addresses
        // Using well-known test tokens on Sepolia
        address USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238; // Circle's USDC on Sepolia
        address USDT_SEPOLIA = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0; // USDT on Sepolia

        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = USDC_SEPOLIA;
        initialStablecoins[1] = USDT_SEPOLIA;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DollarStore with deployer as admin
        DollarStore dollarStore = new DollarStore(deployer, initialStablecoins);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("=================================");
        console.log("DollarStore deployed to:", address(dollarStore));
        console.log("DLRS token deployed to:", address(dollarStore.dlrs()));
        console.log("Admin:", dollarStore.admin());
        console.log("=================================");
        console.log("Supported stablecoins:");
        console.log("  USDC:", USDC_SEPOLIA);
        console.log("  USDT:", USDT_SEPOLIA);
    }
}
