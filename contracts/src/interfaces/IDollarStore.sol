// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDollarStore - Milestone M1 interface for DollarStore
/// @notice Minimal surface for the upgradeable (UUPS) base + governance skeleton.
/// @dev Swap/queue/reserve logic lands in later milestones; M1 is roles + upgrade plumbing.
/// @custom:security-contact admin@dollarstore.world
interface IDollarStore {
    // ============ Events ============

    /// @notice Emitted when the current governor initiates a two-step governor transfer.
    event GovernorTransferInitiated(address indexed currentGovernor, address indexed pendingGovernor);
    /// @notice Emitted when the pending governor accepts the governor role.
    event GovernorTransferCompleted(address indexed previousGovernor, address indexed newGovernor);
    /// @notice Emitted when the governor initiates a two-step guardian transfer.
    event GuardianTransferInitiated(address indexed currentGuardian, address indexed pendingGuardian);
    /// @notice Emitted when the pending guardian accepts the guardian role.
    event GuardianTransferCompleted(address indexed previousGuardian, address indexed newGuardian);

    // ============ Errors ============

    /// @notice Caller is not the governor.
    error OnlyGovernor();
    /// @notice Caller is not the guardian.
    error OnlyGuardian();
    /// @notice Caller is not the pending governor.
    error OnlyPendingGovernor();
    /// @notice Caller is not the pending guardian.
    error OnlyPendingGuardian();
    /// @notice A zero address was supplied where a non-zero address is required.
    error ZeroAddress();

    // ============ Role / State Getters ============

    /// @notice The current governor address.
    function governor() external view returns (address);
    /// @notice The current guardian address.
    function guardian() external view returns (address);
    /// @notice The pending governor (zero if no transfer in progress).
    function pendingGovernor() external view returns (address);
    /// @notice The pending guardian (zero if no transfer in progress).
    function pendingGuardian() external view returns (address);
    /// @notice The DLRS receipt token address.
    function dlrs() external view returns (address);
    /// @notice The semantic version of this implementation.
    function version() external pure returns (string memory);

    // ============ Two-step Role Transfers ============

    /// @notice Initiate a two-step governor transfer. Governor-gated.
    function transferGovernor(address newGovernor) external;
    /// @notice Accept the governor role. Callable only by the pending governor.
    function acceptGovernor() external;
    /// @notice Initiate a two-step guardian transfer. Governor-gated (not guardian-gated).
    function transferGuardian(address newGuardian) external;
    /// @notice Accept the guardian role. Callable only by the pending guardian.
    function acceptGuardian() external;

    // ============ Emergency ============

    /// @notice Pause the protocol. Guardian-gated.
    function pause() external;
    /// @notice Unpause the protocol. Guardian-gated.
    function unpause() external;

    // ============ Asset Registry (M2) ============

    /// @notice Emitted when a pool is created. `kind`: 0 = Hub, 1 = Spoke.
    event PoolCreated(uint16 indexed poolId, uint8 kind);
    /// @notice Emitted when an asset is listed into a pool.
    event AssetListed(address indexed asset, uint16 indexed poolId, uint8 decimals, address priceFeed);

    /// @notice The asset is already listed.
    error AssetAlreadyListed(address asset);
    /// @notice The referenced pool does not exist.
    error InvalidPool(uint16 poolId);

    /// @notice List a hub asset (poolId 0). Governor-gated. Freezes decimals, computes the
    ///         scaling factor, and requires a Chainlink price feed. Reverts if decimals are
    ///         outside [6, 18] or the asset is already listed.
    function addHubAsset(address asset, address priceFeed) external;

    /// @notice Whether an asset is listed/supported.
    function isAssetListed(address asset) external view returns (bool);
    /// @notice Frozen decimals of a listed asset (0 if not listed).
    function assetDecimals(address asset) external view returns (uint8);
    /// @notice Scaling factor 10**(decimals-6) of a listed asset.
    function assetScalingFactor(address asset) external view returns (uint64);
    /// @notice Canonical pool id of a listed asset.
    function assetPoolId(address asset) external view returns (uint16);
    /// @notice Chainlink price feed of a listed asset.
    function assetPriceFeed(address asset) external view returns (address);

    /// @notice Active reserve of `asset` in `poolId`, in normalized 6dp units.
    function getReserve(uint16 poolId, address asset) external view returns (uint256);
    /// @notice Number of pools (index 0 is the hub).
    function poolCount() external view returns (uint256);
    /// @notice Assets that belong to a pool. Reverts InvalidPool if it does not exist.
    function getPoolAssets(uint16 poolId) external view returns (address[] memory);
}
