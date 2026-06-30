// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title RegistryStorage - ERC-7201 namespaced storage for the asset registry, pools and reserves
/// @notice Single source of truth for "what assets/pools exist and how much each pool holds".
/// @dev Reserves and DLRS-side bookkeeping are tracked in normalized 6-decimal units.
///      The Pool struct carries ALL its fields from day one because Pool lives in a dynamic
///      array (Pool[]), and growing a struct stored in an array after deployment is unsafe.
///      Fields unused in early milestones (minDlrsReserve, launchCap, receiptToken) are
///      reserved here so spokes/caps slot in later without a storage migration.
/// @custom:security-contact admin@dollarstore.world
library RegistryStorage {
    /// @notice Pool kind. Hub = poolId 0 (USDC/USDT + DLRS). Spoke = poolId >= 1 (one challenger asset).
    enum PoolKind {
        Hub,
        Spoke
    }

    /// @notice Per-asset configuration. `decimals` is read once and frozen at listing.
    struct AssetConfig {
        /// @notice The canonical pool this asset belongs to (an asset belongs to exactly one pool).
        uint16 poolId;
        /// @notice Token decimals, frozen at listing (must be in [6, 18]).
        uint8 decimals;
        /// @notice 10**(decimals - 6); converts native amounts to/from normalized 6dp units.
        uint64 scalingFactor;
        /// @notice Chainlink price feed (required at listing; used by the peg check in M5).
        address priceFeed;
        /// @notice Whether the asset is listed/supported.
        bool listed;
        /// @notice Per-asset deposit pause (set by guardian in M5).
        bool depositPaused;
    }

    /// @notice A pool (hub or spoke). All fields declared now (array-stored struct, see @dev above).
    struct Pool {
        /// @notice Hub or Spoke.
        PoolKind kind;
        /// @notice Per-pool pause (M5).
        bool paused;
        /// @notice Assets that belong to this pool.
        address[] assets;
        /// @notice DLRS-side reserve internal to a spoke (normalized 6dp). Unused for the hub.
        uint256 dlrsReserve;
        /// @notice Protected minimum DLRS-side liquidity for a spoke (M6/U2).
        uint256 minDlrsReserve;
        /// @notice Temporary launch exposure cap (M6). 0 = no cap.
        uint256 launchCap;
        /// @notice Non-transferable LP receipt token for a spoke (U2). address(0) until set.
        address receiptToken;
    }

    /// @custom:storage-location erc7201:dollarstore.storage.registry
    struct Layout {
        /// @notice Asset address => its configuration.
        mapping(address => AssetConfig) assetConfig;
        /// @notice All pools. Index 0 is always the hub.
        Pool[] pools;
        /// @notice poolId => asset => active reserve (normalized 6dp).
        mapping(uint16 => mapping(address => uint256)) reserves;
    }

    /// @notice Precomputed ERC-7201 storage slot for namespace "dollarstore.storage.registry".
    /// @dev keccak256(abi.encode(uint256(keccak256("dollarstore.storage.registry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant REGISTRY_STORAGE_LOCATION =
        0xcd62d958bde512a10a72d01f1689da2c81a5ee45a5235501c7bc17aa3a0b8c00;

    /// @notice Returns a storage pointer to the registry layout at the namespaced slot.
    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := REGISTRY_STORAGE_LOCATION
        }
    }
}
