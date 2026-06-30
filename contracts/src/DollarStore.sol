// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
// NOTE (M2+): import {ReentrancyGuardUpgradeable} from
//      "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
//      Reentrancy protection will be added once token-moving paths (deposit/withdraw/swap)
//      are introduced. It is intentionally omitted in M1 since there are no transfers yet.

import {IDollarStore} from "./interfaces/IDollarStore.sol";
import {CoreStorage} from "./storage/CoreStorage.sol";
import {DLRS} from "./DLRS.sol";

/// @title DollarStore - Upgradeable (UUPS) base + governance skeleton (Milestone M1)
/// @notice Establishes the upgradeable core: ERC-7201 namespaced storage, two-step
///         governor/guardian roles, pause/unpause, and governor-gated UUPS upgrades.
/// @dev Swap/queue/reserve logic is added in later milestones. This is the M1 foundation.
/// @dev Storage is held in CoreStorage's ERC-7201 namespaced slot, NOT in contract state
///      variables, so the layout is stable across upgrades.
/// @custom:security-contact admin@dollarstore.world
contract DollarStore is Initializable, UUPSUpgradeable, PausableUpgradeable, IDollarStore {
    // ============ Modifiers ============

    /// @dev Restricts to the current governor (read from namespaced core storage).
    modifier onlyGovernor() {
        if (msg.sender != CoreStorage.layout().governor) revert OnlyGovernor();
        _;
    }

    /// @dev Restricts to the current guardian (read from namespaced core storage).
    modifier onlyGuardian() {
        if (msg.sender != CoreStorage.layout().guardian) revert OnlyGuardian();
        _;
    }

    // ============ Constructor ============

    /// @notice Locks the implementation contract so it can never be initialized directly.
    /// @dev All state lives behind the proxy; the implementation must stay uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initialize the proxy: set roles, init bases, and deploy the DLRS token.
    /// @dev Deploys a fresh DLRS bound to this proxy (address(this)) and stores its address.
    /// @param governor_ The governor address (structure + upgrade authority).
    /// @param guardian_ The guardian address (emergency authority).
    function initialize(address governor_, address guardian_) external initializer {
        if (governor_ == address(0)) revert ZeroAddress();
        if (guardian_ == address(0)) revert ZeroAddress();

        __Pausable_init();
        // NOTE (M2+): __ReentrancyGuard_init();  // add alongside token-moving paths.

        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.governor = governor_;
        $.guardian = guardian_;
        $.dlrs = address(new DLRS(address(this)));
    }

    // ============ Getters ============

    /// @inheritdoc IDollarStore
    function governor() external view override returns (address) {
        return CoreStorage.layout().governor;
    }

    /// @inheritdoc IDollarStore
    function guardian() external view override returns (address) {
        return CoreStorage.layout().guardian;
    }

    /// @inheritdoc IDollarStore
    function pendingGovernor() external view override returns (address) {
        return CoreStorage.layout().pendingGovernor;
    }

    /// @inheritdoc IDollarStore
    function pendingGuardian() external view override returns (address) {
        return CoreStorage.layout().pendingGuardian;
    }

    /// @inheritdoc IDollarStore
    function dlrs() external view override returns (address) {
        return CoreStorage.layout().dlrs;
    }

    /// @inheritdoc IDollarStore
    function version() external pure override returns (string memory) {
        return "0.1.0-M1";
    }

    // ============ Two-step Role Transfers ============

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated. The new governor must call acceptGovernor to take the role.
    function transferGovernor(address newGovernor) external override onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.pendingGovernor = newGovernor;
        emit GovernorTransferInitiated($.governor, newGovernor);
    }

    /// @inheritdoc IDollarStore
    /// @dev Callable only by the pending governor.
    function acceptGovernor() external override {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        if (msg.sender != $.pendingGovernor) revert OnlyPendingGovernor();
        address previousGovernor = $.governor;
        $.governor = $.pendingGovernor;
        $.pendingGovernor = address(0);
        emit GovernorTransferCompleted(previousGovernor, $.governor);
    }

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated (NOT guardian-gated): if the guardian could rotate itself, a
    ///      compromised guardian could lock out the legitimate one. The governor's slower
    ///      path protects the emergency role. Same rationale as the prior design.
    function transferGuardian(address newGuardian) external override onlyGovernor {
        if (newGuardian == address(0)) revert ZeroAddress();
        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.pendingGuardian = newGuardian;
        emit GuardianTransferInitiated($.guardian, newGuardian);
    }

    /// @inheritdoc IDollarStore
    /// @dev Callable only by the pending guardian.
    function acceptGuardian() external override {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        if (msg.sender != $.pendingGuardian) revert OnlyPendingGuardian();
        address previousGuardian = $.guardian;
        $.guardian = $.pendingGuardian;
        $.pendingGuardian = address(0);
        emit GuardianTransferCompleted(previousGuardian, $.guardian);
    }

    // ============ Emergency ============

    /// @inheritdoc IDollarStore
    /// @dev Guardian-gated (instant).
    function pause() external override onlyGuardian {
        _pause();
    }

    /// @inheritdoc IDollarStore
    /// @dev Guardian-gated (instant).
    function unpause() external override onlyGuardian {
        _unpause();
    }

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorize a UUPS upgrade. Governor-gated.
    /// @dev In production the governor is a TimelockController, so upgrades carry a public delay.
    /// @param newImplementation The address of the new implementation (validated by UUPS machinery).
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}
}
