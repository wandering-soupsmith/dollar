// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DollarStore} from "../src/DollarStore.sol";

/// @title Deploy - Deploys the DollarStore UUPS proxy + implementation
/// @notice Deploys the implementation, then an ERC1967Proxy initialized with
///         (upgrader, governor, guardian).
/// @dev Env vars:
///      - DEPLOYER_PRIVATE_KEY (required): broadcasting key.
///      This is the dev / staging deploy (roles are plain addresses). For the production topology
///      (two timelocks + Safe) use script/DeployGovernance.s.sol.
///      - UPGRADER (optional): upgrade authority; defaults to the deployer.
///      - GOVERNOR (optional): risk/registry/caps authority; defaults to the deployer.
///      - GUARDIAN (optional): emergency authority; defaults to the deployer.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address upgrader = vm.envOr("UPGRADER", deployer);
        address governor = vm.envOr("GOVERNOR", deployer);
        address guardian = vm.envOr("GUARDIAN", deployer);

        vm.startBroadcast(deployerKey);

        // 1. Deploy the implementation (constructor disables initializers on the impl).
        DollarStore implementation = new DollarStore();

        // 2. Deploy the ERC1967 proxy, initializing it in the same tx.
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        vm.stopBroadcast();

        // 3. Read back the DLRS deployed during initialize for logging.
        address dlrs = DollarStore(address(proxy)).dlrs();

        console2.log("DollarStore implementation:", address(implementation));
        console2.log("DollarStore proxy:         ", address(proxy));
        console2.log("DLRS token:                ", dlrs);
        console2.log("upgrader:                  ", upgrader);
        console2.log("governor:                  ", governor);
        console2.log("guardian:                  ", guardian);
    }
}
