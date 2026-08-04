// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";

/// @notice Mock "next version" implementation used to exercise the UUPS upgrade path.
/// @dev Inherits the full M1 contract, adds a new feature and a reinitializer(2) hook.
contract DollarStoreMockUpgrade is DollarStore {
    /// @notice New behaviour available only after upgrading.
    function newFeature() external pure returns (uint256) {
        return 42;
    }

    /// @notice Optional post-upgrade initialization. reinitializer(2) runs at most once.
    /// @dev No-op in M1; present to validate the reinitializer pattern.
    function initializeV2() external reinitializer(2) {}
}

contract DollarStoreM1Test is Test {
    DollarStore internal impl;
    DollarStore internal store; // proxy, typed as DollarStore

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Mirror of the events for expectEmit checks.
    event GovernorTransferInitiated(address indexed currentGovernor, address indexed pendingGovernor);
    event GovernorTransferCompleted(address indexed previousGovernor, address indexed newGovernor);
    event GuardianTransferInitiated(address indexed currentGuardian, address indexed pendingGuardian);
    event GuardianTransferCompleted(address indexed previousGuardian, address indexed newGuardian);
    event UpgraderTransferInitiated(address indexed currentUpgrader, address indexed pendingUpgrader);
    event UpgraderTransferCompleted(address indexed previousUpgrader, address indexed newUpgrader);

    function setUp() public {
        impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        store = DollarStore(address(proxy));
    }

    // ============ Initialization ============

    function test_initialize_setsRolesAndDeploysDLRS() public {
        assertEq(store.upgrader(), upgrader, "upgrader");
        assertEq(store.governor(), governor, "governor");
        assertEq(store.guardian(), guardian, "guardian");
        assertEq(store.pendingUpgrader(), address(0), "pendingUpgrader");
        assertEq(store.pendingGovernor(), address(0), "pendingGovernor");
        assertEq(store.pendingGuardian(), address(0), "pendingGuardian");

        address dlrsAddr = store.dlrs();
        assertTrue(dlrsAddr != address(0), "dlrs deployed");

        DLRS token = DLRS(dlrsAddr);
        assertEq(token.dollarStore(), address(store), "dlrs bound to proxy");
        assertEq(token.decimals(), 6, "dlrs decimals");
        assertEq(token.name(), "Dollar Store Token", "dlrs name");
        assertEq(token.symbol(), "DLRS", "dlrs symbol");

        assertEq(store.version(), "0.9.2-U2", "version");
    }

    function test_initialize_revertsOnSecondCall() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        store.initialize(alice, alice, bob);
    }

    function test_initialize_revertsOnZeroUpgrader() public {
        DollarStore freshImpl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (address(0), governor, guardian));
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        new ERC1967Proxy(address(freshImpl), initData);
    }

    function test_initialize_revertsOnZeroGovernor() public {
        DollarStore freshImpl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, address(0), guardian));
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        new ERC1967Proxy(address(freshImpl), initData);
    }

    function test_initialize_revertsOnZeroGuardian() public {
        DollarStore freshImpl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, address(0)));
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        new ERC1967Proxy(address(freshImpl), initData);
    }

    function test_implementation_disablesInitializers() public {
        // Calling initialize directly on the implementation must revert.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(upgrader, governor, guardian);
    }

    // ============ Upgrade ============

    function test_upgrade_byUpgrader_persistsState() public {
        address dlrsBefore = store.dlrs();

        DollarStoreMockUpgrade newImpl = new DollarStoreMockUpgrade();

        vm.prank(upgrader);
        store.upgradeToAndCall(address(newImpl), "");

        // State preserved across upgrade.
        assertEq(store.upgrader(), upgrader, "upgrader preserved");
        assertEq(store.governor(), governor, "governor preserved");
        assertEq(store.guardian(), guardian, "guardian preserved");
        assertEq(store.dlrs(), dlrsBefore, "dlrs preserved");

        // New behaviour available.
        assertEq(DollarStoreMockUpgrade(address(store)).newFeature(), 42, "newFeature");
    }

    function test_upgrade_revertsForNonUpgrader() public {
        DollarStoreMockUpgrade newImpl = new DollarStoreMockUpgrade();
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyUpgrader.selector);
        store.upgradeToAndCall(address(newImpl), "");

        // Separation of powers: even the governor cannot upgrade.
        vm.prank(governor);
        vm.expectRevert(IDollarStore.OnlyUpgrader.selector);
        store.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgrade_reinitializerV2Runs() public {
        DollarStoreMockUpgrade newImpl = new DollarStoreMockUpgrade();
        bytes memory call = abi.encodeCall(DollarStoreMockUpgrade.initializeV2, ());

        vm.prank(upgrader);
        store.upgradeToAndCall(address(newImpl), call);

        // A second reinitializer(2) call must revert.
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        DollarStoreMockUpgrade(address(store)).initializeV2();
    }

    // ============ Governor two-step ============

    function test_transferGovernor_twoStep() public {
        vm.expectEmit(true, true, false, false, address(store));
        emit GovernorTransferInitiated(governor, alice);
        vm.prank(governor);
        store.transferGovernor(alice);
        assertEq(store.pendingGovernor(), alice, "pending set");
        assertEq(store.governor(), governor, "governor unchanged until accept");

        vm.expectEmit(true, true, false, false, address(store));
        emit GovernorTransferCompleted(governor, alice);
        vm.prank(alice);
        store.acceptGovernor();
        assertEq(store.governor(), alice, "governor rotated");
        assertEq(store.pendingGovernor(), address(0), "pending cleared");
    }

    function test_transferGovernor_revertsForNonGovernor() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.transferGovernor(alice);
    }

    function test_transferGovernor_revertsOnZero() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.transferGovernor(address(0));
    }

    function test_acceptGovernor_revertsForNonPending() public {
        vm.prank(governor);
        store.transferGovernor(alice);

        vm.prank(bob);
        vm.expectRevert(IDollarStore.OnlyPendingGovernor.selector);
        store.acceptGovernor();
    }

    // ============ Guardian two-step ============

    function test_transferGuardian_twoStep() public {
        // transferGuardian is governor-gated, NOT guardian-gated.
        vm.expectEmit(true, true, false, false, address(store));
        emit GuardianTransferInitiated(guardian, alice);
        vm.prank(governor);
        store.transferGuardian(alice);
        assertEq(store.pendingGuardian(), alice, "pending set");
        assertEq(store.guardian(), guardian, "guardian unchanged until accept");

        vm.expectEmit(true, true, false, false, address(store));
        emit GuardianTransferCompleted(guardian, alice);
        vm.prank(alice);
        store.acceptGuardian();
        assertEq(store.guardian(), alice, "guardian rotated");
        assertEq(store.pendingGuardian(), address(0), "pending cleared");
    }

    function test_transferGuardian_revertsForNonGovernor() public {
        // Even the current guardian cannot initiate its own rotation.
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.transferGuardian(alice);
    }

    function test_transferGuardian_revertsOnZero() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.transferGuardian(address(0));
    }

    function test_acceptGuardian_revertsForNonPending() public {
        vm.prank(governor);
        store.transferGuardian(alice);

        vm.prank(bob);
        vm.expectRevert(IDollarStore.OnlyPendingGuardian.selector);
        store.acceptGuardian();
    }

    // ============ Upgrader two-step ============

    function test_transferUpgrader_twoStep() public {
        vm.expectEmit(true, true, false, false, address(store));
        emit UpgraderTransferInitiated(upgrader, alice);
        vm.prank(upgrader);
        store.transferUpgrader(alice);
        assertEq(store.pendingUpgrader(), alice, "pending set");
        assertEq(store.upgrader(), upgrader, "upgrader unchanged until accept");

        vm.expectEmit(true, true, false, false, address(store));
        emit UpgraderTransferCompleted(upgrader, alice);
        vm.prank(alice);
        store.acceptUpgrader();
        assertEq(store.upgrader(), alice, "upgrader rotated");
        assertEq(store.pendingUpgrader(), address(0), "pending cleared");
    }

    function test_transferUpgrader_selfManaged_notGovernor() public {
        // Upgrader rotation is upgrader-gated: neither the governor nor anyone else can seize it.
        vm.prank(governor);
        vm.expectRevert(IDollarStore.OnlyUpgrader.selector);
        store.transferUpgrader(alice);
    }

    function test_transferUpgrader_revertsOnZero() public {
        vm.prank(upgrader);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.transferUpgrader(address(0));
    }

    function test_acceptUpgrader_revertsForNonPending() public {
        vm.prank(upgrader);
        store.transferUpgrader(alice);

        vm.prank(bob);
        vm.expectRevert(IDollarStore.OnlyPendingUpgrader.selector);
        store.acceptUpgrader();
    }

    // ============ Pause / Unpause ============

    function test_pause_unpause_onlyGuardian() public {
        // Non-guardian cannot pause.
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.pause();

        // Guardian pauses.
        vm.prank(guardian);
        store.pause();
        assertTrue(store.paused(), "paused");

        // Non-guardian cannot unpause.
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.unpause();

        // Guardian unpauses.
        vm.prank(guardian);
        store.unpause();
        assertFalse(store.paused(), "unpaused");
    }

    // ============ DLRS soulbound behaviour ============

    function test_dlrs_isSoulbound() public {
        DLRS token = DLRS(store.dlrs());

        vm.expectRevert(DLRS.NonTransferable.selector);
        token.transfer(bob, 1);

        vm.expectRevert(DLRS.NonTransferable.selector);
        token.approve(bob, 1);

        vm.expectRevert(DLRS.NonTransferable.selector);
        token.transferFrom(alice, bob, 1);
    }

    function test_dlrs_mintBurn_onlyDollarStore() public {
        DLRS token = DLRS(store.dlrs());

        vm.prank(alice);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        token.mint(alice, 1);

        vm.prank(alice);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        token.burn(alice, 1);
    }

    function test_dlrs_constructor_revertsOnZeroStore() public {
        vm.expectRevert(DLRS.ZeroAddress.selector);
        new DLRS(address(0));
    }

    // ============ Governance continuity ============

    /// @notice After a governor rotation, the OLD governor can no longer act.
    function test_oldGovernor_cannotActAfterRotation() public {
        vm.prank(governor);
        store.transferGovernor(alice);
        vm.prank(alice);
        store.acceptGovernor();

        // Old governor is now powerless.
        vm.prank(governor);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.transferGovernor(bob);

        // New governor can act on a governor-gated function (upgrades are a separate role).
        vm.prank(alice);
        store.setPegTolerance(123);
        assertEq(store.pegTolerance(), 123, "new governor controls params");
    }

    /// @notice A pending role transfer survives an upgrade (it lives in namespaced storage).
    function test_pendingTransfer_persistsAcrossUpgrade() public {
        vm.prank(governor);
        store.transferGovernor(alice);
        assertEq(store.pendingGovernor(), alice, "pending set");

        DollarStoreMockUpgrade newImpl = new DollarStoreMockUpgrade();
        vm.prank(upgrader);
        store.upgradeToAndCall(address(newImpl), "");

        // Pending governor still there; can still accept after the upgrade.
        assertEq(store.pendingGovernor(), alice, "pending preserved");
        vm.prank(alice);
        store.acceptGovernor();
        assertEq(store.governor(), alice, "accept works post-upgrade");
    }

    /// @notice Paused state survives an upgrade.
    function test_pausedState_persistsAcrossUpgrade() public {
        vm.prank(guardian);
        store.pause();
        assertTrue(store.paused(), "paused before upgrade");

        DollarStoreMockUpgrade newImpl = new DollarStoreMockUpgrade();
        vm.prank(upgrader);
        store.upgradeToAndCall(address(newImpl), "");

        assertTrue(store.paused(), "paused preserved across upgrade");
        vm.prank(guardian);
        store.unpause();
        assertFalse(store.paused(), "unpause still works");
    }

    // NOTE (M8): The full governor-via-TimelockController rehearsal (queue + delay + execute
    //            of an upgrade) is covered in the M8 governance milestone. Here the governor
    //            is a plain EOA exercised with vm.prank.
}
