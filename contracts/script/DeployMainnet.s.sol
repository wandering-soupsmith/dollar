// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DollarStore.sol";

contract DeployMainnetScript is Script {
    function run() external {
        // Get deployer private key from environment
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=================================");
        console.log("MAINNET DEPLOYMENT");
        console.log("=================================");
        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);

        // Mainnet stablecoin addresses
        address USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = USDC_MAINNET;
        initialStablecoins[1] = USDT_MAINNET;

        vm.startBroadcast(deployerPrivateKey);

        // Deploy DollarStore with deployer as admin
        DollarStore dollarStore = new DollarStore(deployer, initialStablecoins);

        vm.stopBroadcast();

        // Log deployed addresses
        console.log("=================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("=================================");
        console.log("DollarStore deployed to:", address(dollarStore));
        console.log("DLRS token deployed to:", address(dollarStore.dlrs()));
        console.log("Admin:", dollarStore.admin());
        console.log("=================================");
        console.log("Supported stablecoins:");
        console.log("  USDC:", USDC_MAINNET);
        console.log("  USDT:", USDT_MAINNET);
        console.log("=================================");
    }
}
