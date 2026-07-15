// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {MockStableERC20} from "./MockStableERC20.sol";

/// @title DeployMockStables - Deploys mock USDC + USDT for testnet (Sepolia)
/// @notice Deploys two faucet ERC20s with public mint, matching the real assets' decimals
///         (USDC and USDT are both 6 decimals). For testnet rehearsal only.
/// @dev Env vars:
///      - DEPLOYER_PRIVATE_KEY (required): broadcasting key.
///      Run with `--broadcast --verify` to deploy and verify on Etherscan in one shot.
contract DeployMockStables is Script {
    // Real-asset decimals: both USDC and USDT use 6 on Ethereum.
    uint8 internal constant USDC_DECIMALS = 6;
    uint8 internal constant USDT_DECIMALS = 6;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        vm.startBroadcast(deployerKey);

        MockStableERC20 usdc = new MockStableERC20("USD Coin (Mock)", "USDC", USDC_DECIMALS);
        MockStableERC20 usdt = new MockStableERC20("Tether USD (Mock)", "USDT", USDT_DECIMALS);

        vm.stopBroadcast();

        console2.log("Mock USDC:", address(usdc));
        console2.log("  decimals:", usdc.decimals());
        console2.log("Mock USDT:", address(usdt));
        console2.log("  decimals:", usdt.decimals());
    }
}
