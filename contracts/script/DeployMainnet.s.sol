// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DollarStore.sol";

/// @notice Mainnet v2 deploy script.
/// @dev Initial deployment uses the deployer EOA as both governor and guardian.
///      After deployment, roles are migrated:
///        - Guardian: transferGuardian(Safe) from deployer; Safe calls acceptGuardian.
///        - Governor: transferGovernor(TimelockController) from deployer; Safe schedules acceptGovernor()
///          through the TimelockController, waits 7 days, then anyone calls execute().
///      See docs/admin-migration-plan.md for the full sequence.
contract DeployMainnetScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=================================");
        console.log("MAINNET DEPLOYMENT (v2)");
        console.log("=================================");
        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);

        address USDC_MAINNET = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address USDT_MAINNET = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

        address USDC_USD_FEED = 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6;
        address USDT_USD_FEED = 0x3E7d1eAB13ad0104d2750B8863b489D65364e32D;

        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = USDC_MAINNET;
        initialStablecoins[1] = USDT_MAINNET;

        address[] memory initialPriceFeeds = new address[](2);
        initialPriceFeeds[0] = USDC_USD_FEED;
        initialPriceFeeds[1] = USDT_USD_FEED;

        vm.startBroadcast(deployerPrivateKey);

        DollarStore dollarStore = new DollarStore(deployer, deployer, initialStablecoins, initialPriceFeeds);

        vm.stopBroadcast();

        console.log("=================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("=================================");
        console.log("DollarStore deployed to:", address(dollarStore));
        console.log("DLRS token deployed to:", address(dollarStore.dlrs()));
        console.log("Governor:", dollarStore.governor());
        console.log("Guardian:", dollarStore.guardian());
        console.log("=================================");
        console.log("Supported stablecoins:");
        console.log("  USDC:", USDC_MAINNET);
        console.log("  USDT:", USDT_MAINNET);
        console.log("Price feeds:");
        console.log("  USDC/USD:", USDC_USD_FEED);
        console.log("  USDT/USD:", USDT_USD_FEED);
        console.log("=================================");
        console.log("Next steps: migrate roles per docs/admin-migration-plan.md");
        console.log("=================================");
    }
}
