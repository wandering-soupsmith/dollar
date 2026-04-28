// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/DollarStore.sol";

/// @dev Minimal stub returning a fixed price. Used only for Sepolia testbed deploys
///      where Chainlink stablecoin feeds may not be available for chosen test tokens.
contract MockAggregator {
    int256 public immutable answer;
    uint8 public constant decimals = 8;

    constructor(int256 _answer) {
        answer = _answer;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 _answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, answer, block.timestamp, block.timestamp, 1);
    }
}

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying from:", deployer);
        console.log("Balance:", deployer.balance);

        address USDC_SEPOLIA = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
        address USDT_SEPOLIA = 0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0;

        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = USDC_SEPOLIA;
        initialStablecoins[1] = USDT_SEPOLIA;

        vm.startBroadcast(deployerPrivateKey);

        MockAggregator usdcFeed = new MockAggregator(1e8);
        MockAggregator usdtFeed = new MockAggregator(1e8);

        address[] memory initialPriceFeeds = new address[](2);
        initialPriceFeeds[0] = address(usdcFeed);
        initialPriceFeeds[1] = address(usdtFeed);

        DollarStore dollarStore = new DollarStore(deployer, deployer, initialStablecoins, initialPriceFeeds);

        vm.stopBroadcast();

        console.log("=================================");
        console.log("DollarStore deployed to:", address(dollarStore));
        console.log("DLRS token deployed to:", address(dollarStore.dlrs()));
        console.log("Governor:", dollarStore.governor());
        console.log("Guardian:", dollarStore.guardian());
        console.log("=================================");
        console.log("Supported stablecoins:");
        console.log("  USDC:", USDC_SEPOLIA, "feed:", address(usdcFeed));
        console.log("  USDT:", USDT_SEPOLIA, "feed:", address(usdtFeed));
    }
}
