// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {DollarStore} from "../src/DollarStore.sol";

/// @title DeployGovernance - Full production deploy: two timelocks + DollarStore, wired at genesis.
/// @notice Deploys an upgrader timelock (long delay) and a governor timelock (short delay), each
///         proposed/cancelled by its own operator Safe, then deploys the DollarStore proxy
///         initialized with (upgraderTimelock, governorTimelock, guardianSafe). No two-step handoff
///         is needed: the roles are set to their production holders at initialize() time.
/// @dev Topology (3 operator Safes; you may point them at the same address for the simple case):
///      - upgraderSafe: proposer/canceller of the upgrader timelock.
///      - governorSafe: proposer/canceller of the governor timelock.
///      - guardianSafe: the `guardian` directly (no timelock; must be instant).
///      The upgrader/governor timelocks are the on-chain `upgrader`/`governor` roles; each is a
///      thin delay wrapper around its operator Safe. Execution is open (`executors = [address(0)]`).
///      The guardian Safe is granted CANCELLER on both timelocks at deploy (so it can abort a
///      malicious queued op even if a proposer Safe is compromised); the deployer holds a temporary
///      admin only to grant that role and renounces it in the same run, leaving no external admin.
///      Each proposer Safe also keeps cancel of its own queue (OZ constructor default).
/// @dev Env vars (run):
///      - DEPLOYER_PRIVATE_KEY (required): broadcasting key.
///      - UPGRADER_SAFE (required): operator Safe of the upgrader timelock.
///      - GOVERNOR_SAFE (optional): operator Safe of the governor timelock. Default = UPGRADER_SAFE.
///      - GUARDIAN_SAFE (optional): the guardian Safe. Default = UPGRADER_SAFE.
///      - UPGRADER_DELAY (optional, seconds): upgrader timelock minDelay. Default 604800 (7d).
///      - GOVERNOR_DELAY (optional, seconds): governor timelock minDelay. Default 172800 (2d).
contract DeployGovernance is Script {
    /// @notice Addresses produced by a governance deploy.
    struct Deployed {
        DollarStore store; // the ERC1967 proxy, typed as DollarStore
        TimelockController upgraderTimelock;
        TimelockController governorTimelock;
    }

    /// @notice Pure-deployment logic (no cheatcodes / no broadcast), so it is unit-testable.
    /// @param admin        Temporary timelock admin (the deployer): grants the guardian its canceller
    ///                     role, then is renounced in the same call. Must equal the caller.
    /// @param upgraderSafe Operator Safe (proposer + self-canceller) of the upgrader timelock.
    /// @param governorSafe Operator Safe (proposer + self-canceller) of the governor timelock.
    /// @param guardianSafe The guardian address (used directly, no timelock; also canceller on both).
    /// @param upgraderDelay minDelay (seconds) of the upgrader timelock.
    /// @param governorDelay minDelay (seconds) of the governor timelock.
    function deploy(
        address admin,
        address upgraderSafe,
        address governorSafe,
        address guardianSafe,
        uint256 upgraderDelay,
        uint256 governorDelay
    ) public returns (Deployed memory d) {
        require(upgraderSafe != address(0), "upgraderSafe = zero");
        require(governorSafe != address(0), "governorSafe = zero");
        require(guardianSafe != address(0), "guardianSafe = zero");

        address[] memory executors = new address[](1);
        executors[0] = address(0); // open executor role

        address[] memory upProposers = new address[](1);
        upProposers[0] = upgraderSafe;
        address[] memory govProposers = new address[](1);
        govProposers[0] = governorSafe;

        // `admin` is a TEMPORARY admin (the deployer) used only to grant the guardian the canceller
        // role; it is renounced below, leaving no external admin.
        d.upgraderTimelock = new TimelockController(upgraderDelay, upProposers, executors, admin);
        d.governorTimelock = new TimelockController(governorDelay, govProposers, executors, admin);

        _wireGuardianCanceller(d.upgraderTimelock, guardianSafe, admin);
        _wireGuardianCanceller(d.governorTimelock, guardianSafe, admin);

        DollarStore implementation = new DollarStore();
        bytes memory initData = abi.encodeCall(
            DollarStore.initialize, (address(d.upgraderTimelock), address(d.governorTimelock), guardianSafe)
        );
        d.store = DollarStore(address(new ERC1967Proxy(address(implementation), initData)));
    }

    /// @dev Grant the guardian Safe CANCELLER on a timelock, then renounce the temporary admin.
    ///      renounceRole requires callerConfirmation == msg.sender, so `admin` must be the caller.
    function _wireGuardianCanceller(TimelockController tl, address guardianSafe, address admin) internal {
        tl.grantRole(tl.CANCELLER_ROLE(), guardianSafe);
        tl.renounceRole(tl.DEFAULT_ADMIN_ROLE(), admin);
    }

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address upgraderSafe = vm.envAddress("UPGRADER_SAFE");
        address governorSafe = vm.envOr("GOVERNOR_SAFE", upgraderSafe);
        address guardianSafe = vm.envOr("GUARDIAN_SAFE", upgraderSafe);
        uint256 upgraderDelay = vm.envOr("UPGRADER_DELAY", uint256(7 days));
        uint256 governorDelay = vm.envOr("GOVERNOR_DELAY", uint256(2 days));

        vm.startBroadcast(deployerKey);
        Deployed memory d =
            deploy(vm.addr(deployerKey), upgraderSafe, governorSafe, guardianSafe, upgraderDelay, governorDelay);
        vm.stopBroadcast();

        console2.log("DollarStore proxy:  ", address(d.store));
        console2.log("DLRS token:         ", d.store.dlrs());
        console2.log("upgrader timelock:  ", address(d.upgraderTimelock));
        console2.log("governor timelock:  ", address(d.governorTimelock));
        console2.log("upgrader Safe:      ", upgraderSafe);
        console2.log("governor Safe:      ", governorSafe);
        console2.log("guardian (Safe):    ", guardianSafe);
        console2.log("upgrader delay (s): ", upgraderDelay);
        console2.log("governor delay (s): ", governorDelay);
    }
}
