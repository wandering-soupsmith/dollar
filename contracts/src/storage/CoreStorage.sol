// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title CoreStorage - ERC-7201 namespaced storage for the DollarStore core module
/// @notice Holds the governance/upgrade roles and the DLRS token address.
/// @dev Uses the ERC-7201 namespaced storage pattern to keep the storage layout stable
///      across UUPS upgrades and to avoid collisions with future modules
///      (hub, queue, spoke namespaces are reserved for later milestones).
/// @custom:security-contact admin@dollarstore.world
library CoreStorage {
    /// @custom:storage-location erc7201:dollarstore.storage.core
    struct Layout {
        /// @notice The governor address: controls structure + holds upgrade authority.
        ///         Expected to be a TimelockController in production.
        address governor;
        /// @notice The guardian address: emergency authority (pause/unpause).
        ///         Expected to be a multi-sig in production.
        address guardian;
        /// @notice Pending governor for the two-step governor transfer.
        address pendingGovernor;
        /// @notice Pending guardian for the two-step guardian transfer.
        address pendingGuardian;
        /// @notice Address of the DLRS receipt token, deployed at initialize() time.
        ///         Set once during initialize and never changed.
        address dlrs;
        /// @notice Peg tolerance in basis points for the depeg check (e.g., 50 = 0.5%). (M5)
        ///         Appended after v0.1 fields; safe because this is a fixed-slot namespaced struct.
        uint256 pegTolerance;
        /// @notice Max age (seconds) of a price feed answer before it is considered stale. (M5)
        uint256 maxStaleness;
    }

    /// @notice Precomputed ERC-7201 storage slot for namespace "dollarstore.storage.core".
    /// @dev Formula:
    ///      keccak256(abi.encode(uint256(keccak256("dollarstore.storage.core")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant CORE_STORAGE_LOCATION =
        0xc72eb56e05ced7e0a40e05cca6aa6995ee70ea8f0f95a16f21cb4c65ab532d00;

    /// @notice Returns a storage pointer to the core layout at the namespaced slot.
    /// @return $ A storage reference to the CoreStorage.Layout struct.
    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := CORE_STORAGE_LOCATION
        }
    }
}
