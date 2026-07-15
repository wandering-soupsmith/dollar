// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DollarStore} from "../src/DollarStore.sol";

/// @title Upgrade - Template for upgrading the DollarStore UUPS proxy
/// @notice Deploys a new DollarStore implementation and points the proxy at it.
/// @dev In production, _authorizeUpgrade is upgrader-gated (separate from the governor), so the
///      upgrade call MUST come from the upgrader (a long-delay TimelockController). This script
///      broadcasts with a single key for convenience in dev/staging; the full Timelock rehearsal
///      lands in M8.
/// @dev Env vars:
///      - DEPLOYER_PRIVATE_KEY (required): broadcasting key (must be / act as upgrader).
///      - PROXY (required): address of the existing ERC1967 proxy to upgrade.
contract Upgrade is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address proxy = vm.envAddress("PROXY");

        vm.startBroadcast(deployerKey);

        // Deploy the new implementation.
        DollarStore newImplementation = new DollarStore();

        // Point the proxy at the new implementation. Empty calldata = no reinitializer call.
        // If the new implementation needs a reinitializer, replace "" with
        // abi.encodeCall(NewImpl.initializeVX, (...)).
        UUPSUpgradeable(proxy).upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        console2.log("Upgraded proxy:        ", proxy);
        console2.log("New implementation:    ", address(newImplementation));
    }
}
