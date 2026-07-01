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

    // ============ Hub Deposit / Withdraw (M3) ============

    /// @notice Emitted on a deposit. `nativeAmount` is what was actually pulled; `units` is the
    ///         normalized 6dp amount credited (and DLRS minted for the hub).
    event Deposit(
        address indexed user, uint16 indexed poolId, address indexed asset, uint256 nativeAmount, uint256 units
    );
    /// @notice Emitted on a withdrawal.
    event Withdraw(
        address indexed user, uint16 indexed poolId, address indexed asset, uint256 units, uint256 nativeAmount
    );

    /// @notice The transaction deadline has passed.
    error DeadlineExpired(uint256 deadline, uint256 timestamp);
    /// @notice A zero (or sub-unit) amount was supplied.
    error ZeroAmount();
    /// @notice The asset is not listed/supported.
    error AssetNotListed(address asset);
    /// @notice The asset does not belong to the given pool.
    error WrongPool(address asset, uint16 poolId);
    /// @notice The operation is not enabled yet (e.g., spoke deposits, deferred to a later milestone).
    error NotEnabled();
    /// @notice The pool's reserves are insufficient for the requested amount.
    error InsufficientReserves(address asset, uint256 requested, uint256 available);
    /// @notice The asset delivered less than expected (fee-on-transfer / non-standard); unsupported.
    error FeeOnTransferNotSupported(address asset);

    /// @notice Deposit `amount` (native units) of a hub asset and receive DLRS 1:1 in normalized
    ///         units. Sub-unit dust stays with the caller. Hub-only in this milestone.
    /// @return receiptUnits The normalized 6dp amount credited (DLRS minted).
    function deposit(uint16 poolId, address asset, uint256 amount, uint256 deadline)
        external
        returns (uint256 receiptUnits);

    /// @notice Burn `units` DLRS and withdraw a hub asset 1:1. Exit path — not blocked by pause.
    /// @return nativeAmountOut The native token amount sent to the caller.
    function withdraw(uint16 poolId, address asset, uint256 units, uint256 deadline)
        external
        returns (uint256 nativeAmountOut);

    /// @notice All assets in a pool and their reserves (normalized 6dp). Reverts InvalidPool if absent.
    function getReserves(uint16 poolId) external view returns (address[] memory assets, uint256[] memory amounts);

    // ============ Directed Swaps & Queues (M4) ============

    /// @notice Emitted on a swap. Amounts are normalized 6dp units.
    event Swap(
        address indexed user,
        address indexed offerAsset,
        address indexed wantAsset,
        uint256 amountIn,
        uint256 amountFilled,
        uint256 amountQueued
    );
    /// @notice Emitted when a new queue position is created.
    event QueueJoined(
        uint256 indexed positionId, address indexed owner, address offerAsset, address wantAsset, uint256 amount
    );
    /// @notice Emitted when a queued position is filled (partially or fully).
    event QueueFilled(uint256 indexed positionId, address indexed owner, uint256 filled, uint256 remaining);
    /// @notice Emitted when a queue position is cancelled and its escrow returned.
    event QueueCancelled(uint256 indexed positionId, address indexed owner, uint256 amountReturned);
    /// @notice Emitted when a fill/cancel transfer fails and the escrow is converted to a DLRS
    ///         claim (moved into hub reserves + DLRS minted to the owner) instead of bricking.
    event QueuePositionRefunded(uint256 indexed positionId, address indexed owner, address offerAsset, uint256 units);

    /// @notice offerAsset == wantAsset is not a valid swap.
    error SameAsset();
    /// @notice The (offerAsset, wantAsset) route is not supported (e.g., involves a spoke; deferred).
    error InvalidRoute(address offerAsset, address wantAsset);
    /// @notice A non-zero tip was supplied; priority tips are a post-launch upgrade (U1).
    error TipNotEnabled();
    /// @notice The directed queue is at capacity (MAX_QUEUE_POSITIONS).
    error QueueFull(address offerAsset, address wantAsset);
    /// @notice The queued remainder is below the minimum order size.
    error OrderTooSmall(uint256 provided, uint256 minimum);
    /// @notice The instantly-filled amount is below the caller's `minAmountOut`.
    error MinAmountNotMet(uint256 filled, uint256 required);
    /// @notice swapExactInput could not fill the full amount instantly.
    error InsufficientLiquidity(uint256 filled, uint256 requested);
    /// @notice No queue position exists with this id.
    error QueuePositionNotFound(uint256 positionId);
    /// @notice The caller does not own this queue position.
    error NotPositionOwner(uint256 positionId, address caller);

    /// @notice Swap `offerAsset` for `wantAsset` (1:1 in normalized units). Fills from the
    ///         exact-opposite queue then protocol reserves; queues any remainder.
    /// @param minAmountOut Minimum amount that must be filled instantly before queueing; set equal
    ///        to the normalized `amount` to require a full instant fill (else it reverts).
    /// @param tip Reserved for U1 priority queues; MUST be 0 in this version.
    /// @return amountFilled Instantly filled amount (normalized 6dp).
    /// @return amountQueued Amount escrowed into the queue (normalized 6dp).
    function swap(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 tip,
        uint256 deadline
    ) external returns (uint256 amountFilled, uint256 amountQueued);

    /// @notice All-or-nothing swap for routers/solvers: fills fully from opposite queue + reserves
    ///         or reverts. Never queues. `minAmountOut` is an interface-compatible floor.
    /// @return amountOut Amount of wantAsset delivered (native units of wantAsset).
    function swapExactInput(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut);

    /// @notice Cancel a queue position and return the escrowed offer asset (or DLRS fallback).
    function cancelQueue(uint256 positionId) external;

    /// @notice Permissionless bounded fallback: fill up to `maxPositions` of the (offerAsset ->
    ///         wantAsset) queue from available reserves, in FIFO order.
    /// @return positionsProcessed Number of positions filled or partially filled.
    /// @return amountFilled Total amount filled (normalized 6dp).
    function processQueue(address offerAsset, address wantAsset, uint256 maxPositions)
        external
        returns (uint256 positionsProcessed, uint256 amountFilled);

    /// @notice Total escrowed depth of the (offerAsset -> wantAsset) queue (normalized 6dp).
    function getQueueDepth(address offerAsset, address wantAsset) external view returns (uint256);
    /// @notice Details of a queue position (zeros if it does not exist).
    function getQueuePosition(uint256 positionId)
        external
        view
        returns (address owner, address offerAsset, address wantAsset, uint256 amount, uint256 timestamp);
    /// @notice All position ids owned by a user.
    function getUserQueuePositions(address user) external view returns (uint256[] memory);
    /// @notice Current minimum order size to queue into the (offerAsset -> wantAsset) queue.
    function getMinimumOrderSize(address offerAsset, address wantAsset) external view returns (uint256);
    /// @notice Instantly fillable amount for a swap (normalized 6dp), respecting FIFO availability
    ///         (returns 0 for a same-direction pair that already has a non-empty queue).
    function getSwapQuote(address offerAsset, address wantAsset, uint256 amount) external view returns (uint256);
}
