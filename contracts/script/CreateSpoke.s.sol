// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DollarStore} from "../src/DollarStore.sol";

/// @title CreateSpoke - schedule/execute a `createSpoke` governor action through the governor timelock.
/// @notice `createSpoke` is governor-gated, and in production the governor is the governor
///         TimelockController (proposed by the governor Safe). This script builds the timelock
///         operation and either schedules it (proposer) or, after the delay, executes it (open
///         executor). In production the governor Safe schedules/executes via its own tooling; this
///         script is the reference/testnet path when the proposer key is an EOA.
/// @dev Env vars:
///      - DEPLOYER_PRIVATE_KEY (required): broadcasting key. For `schedule` it must hold PROPOSER on
///        the governor timelock; `execute` is open (executors = [address(0)]).
///      - STORE_PROXY (required): the DollarStore proxy address (the timelock's call target).
///      - GOVERNOR_TIMELOCK (required): the governor TimelockController address.
///      - SPOKE_ASSET (required): the challenger stablecoin to list as a spoke.
///      - SPOKE_FEED (required): its Chainlink price feed.
///      - SPOKE_MIN_DLRS (optional): initial protected minimum DLRS-side reserve (6dp). Default 0.
///      - SALT (optional): timelock operation salt. Default 0. Must match between schedule and execute.
///      - ACTION (optional): "schedule" (default) or "execute".
contract CreateSpoke is Script {
    function _params()
        internal
        view
        returns (address store, TimelockController tl, bytes memory data, uint256 delay, bytes32 salt)
    {
        store = vm.envAddress("STORE_PROXY");
        tl = TimelockController(payable(vm.envAddress("GOVERNOR_TIMELOCK")));
        address spokeAsset = vm.envAddress("SPOKE_ASSET");
        address priceFeed = vm.envAddress("SPOKE_FEED");
        uint256 minDlrs = vm.envOr("SPOKE_MIN_DLRS", uint256(0));
        data = abi.encodeCall(DollarStore.createSpoke, (spokeAsset, priceFeed, minDlrs));
        delay = tl.getMinDelay();
        salt = bytes32(vm.envOr("SALT", uint256(0)));
    }

    /// @notice Queue the createSpoke operation on the governor timelock (proposer key required).
    function schedule() public {
        (address store, TimelockController tl, bytes memory data, uint256 delay, bytes32 salt) = _params();
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        tl.schedule(store, 0, data, bytes32(0), salt, delay);
        vm.stopBroadcast();
        console2.log("scheduled createSpoke on:", store);
        console2.log("executable after (s):    ", delay);
        console2.log("operation id:");
        console2.logBytes32(tl.hashOperation(store, 0, data, bytes32(0), salt));
    }

    /// @notice Execute the queued createSpoke operation once the timelock delay has elapsed.
    function execute() public {
        (address store, TimelockController tl, bytes memory data,, bytes32 salt) = _params();
        uint256 key = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(key);
        tl.execute(store, 0, data, bytes32(0), salt);
        vm.stopBroadcast();
        console2.log("executed createSpoke on:", store);
    }

    function run() external {
        string memory action = vm.envOr("ACTION", string("schedule"));
        if (keccak256(bytes(action)) == keccak256(bytes("execute"))) {
            execute();
        } else {
            schedule();
        }
    }
}
