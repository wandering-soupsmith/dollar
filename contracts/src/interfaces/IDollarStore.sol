// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDollarStore - Interface for the Dollar Store protocol
/// @notice A minimalist stablecoin aggregator and 1:1 swap facility
/// @dev Zero-fee, pure FIFO queue ordering
interface IDollarStore {
    // ============ Events ============

    event Deposit(address indexed user, address indexed stablecoin, uint256 amount, uint256 dlrsMinted);
    event Withdraw(address indexed user, address indexed stablecoin, uint256 amount, uint256 dlrsBurned);
    event StablecoinAdded(address indexed stablecoin);
    event StablecoinRemoved(address indexed stablecoin);

    // Depeg protection events
    event DepositPauseToggled(address indexed stablecoin, bool paused);
    event PriceFeedSet(address indexed stablecoin, address indexed feed);
    event PegToleranceSet(uint256 tolerance);
    event MaxStalenessSet(uint256 staleness);

    // Swap events
    event Swap(
        address indexed user,
        address indexed fromStablecoin,
        address indexed toStablecoin,
        uint256 amountIn,
        uint256 amountOut,
        uint256 amountQueued
    );

    // Queue events
    event QueueJoined(
        uint256 indexed positionId,
        address indexed user,
        address indexed stablecoin,
        uint256 amount,
        uint256 timestamp
    );
    event QueueCancelled(uint256 indexed positionId, address indexed user, uint256 amountReturned);
    event QueuePositionRefunded(
        uint256 indexed positionId,
        address indexed user,
        address indexed stablecoin,
        uint256 dlrsRefunded
    );
    event QueueFilled(
        uint256 indexed positionId,
        address indexed user,
        address indexed stablecoin,
        uint256 amountFilled,
        uint256 amountRemaining
    );

    // ============ Errors ============

    error StablecoinNotSupported(address stablecoin);
    error StablecoinAlreadySupported(address stablecoin);
    error InsufficientReserves(address stablecoin, uint256 requested, uint256 available);
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    // Queue errors
    error ActiveQueuePositions(address stablecoin);
    error QueuePositionNotFound(uint256 positionId);
    error NotPositionOwner(uint256 positionId, address caller, address owner);
    error InsufficientDlrsBalance(uint256 required, uint256 available);

    // Swap errors
    error SameStablecoin();
    error InsufficientReservesNoQueue(address stablecoin, uint256 requested, uint256 available);

    // Aggregator errors
    error DeadlineExpired(uint256 deadline, uint256 currentTime);
    error InvalidRecipient();

    // Depeg protection errors
    error DepositsPaused(address stablecoin);
    error PriceStale(address stablecoin, uint256 updatedAt);
    error PriceOutOfBounds(address stablecoin, uint256 price, uint256 lower, uint256 upper);
    error InvalidTolerance();
    error InvalidStaleness();
    error NoPriceFeed(address stablecoin);

    // ============ Core Functions ============

    /// @notice Deposit a supported stablecoin and receive DLRS at 1:1 ratio
    /// @param stablecoin The address of the stablecoin to deposit
    /// @param amount The amount of stablecoin to deposit
    /// @return dlrsMinted The amount of DLRS tokens minted
    function deposit(address stablecoin, uint256 amount) external returns (uint256 dlrsMinted);

    /// @notice Burn DLRS and withdraw a stablecoin at 1:1 ratio
    /// @param stablecoin The address of the stablecoin to withdraw
    /// @param amount The amount of stablecoin to withdraw (and DLRS to burn)
    /// @return stablecoinReceived The amount of stablecoin received
    function withdraw(address stablecoin, uint256 amount) external returns (uint256 stablecoinReceived);

    // ============ Queue Functions ============

    /// @notice Join the queue for a specific stablecoin
    /// @dev Locks DLRS in escrow until filled or cancelled. Minimum order size applies based on queue depth.
    /// @param stablecoin The stablecoin you want to receive
    /// @param dlrsAmount The amount of DLRS to lock (1:1 with desired stablecoin)
    /// @return positionId The unique ID for this queue position
    function joinQueue(address stablecoin, uint256 dlrsAmount) external returns (uint256 positionId);

    /// @notice Cancel a queue position and reclaim locked DLRS
    /// @param positionId The position ID to cancel
    /// @return dlrsReturned The amount of DLRS returned (may be less if partially filled)
    function cancelQueue(uint256 positionId) external returns (uint256 dlrsReturned);

    /// @notice Admin force-cancel a queue position, returning DLRS to the position owner
    /// @param positionId The position ID to cancel
    /// @return dlrsReturned The amount of DLRS returned to the position owner
    function adminCancelQueue(uint256 positionId) external returns (uint256 dlrsReturned);

    // ============ Swap Functions ============

    /// @notice Swap one stablecoin for another in a single transaction
    /// @dev Deposits fromStablecoin, then withdraws toStablecoin (instant) or queues (if insufficient)
    /// @param fromStablecoin The stablecoin to swap from
    /// @param toStablecoin The stablecoin to swap to
    /// @param amount The amount to swap
    /// @param queueIfUnavailable If true, queue any amount that can't be filled instantly
    /// @return received The amount received instantly
    /// @return positionId The queue position ID (0 if no queue, or if queueIfUnavailable=false)
    function swap(
        address fromStablecoin,
        address toStablecoin,
        uint256 amount,
        bool queueIfUnavailable
    ) external returns (uint256 received, uint256 positionId);

    /// @notice Swap DLRS for a stablecoin in a single transaction
    /// @dev For users who already hold DLRS and want to convert to a specific stablecoin
    /// @param toStablecoin The stablecoin to receive
    /// @param dlrsAmount The amount of DLRS to swap
    /// @param queueIfUnavailable If true, queue any amount that can't be filled instantly
    /// @return received The amount received instantly
    /// @return positionId The queue position ID (0 if no queue, or if queueIfUnavailable=false)
    function swapFromDLRS(
        address toStablecoin,
        uint256 dlrsAmount,
        bool queueIfUnavailable
    ) external returns (uint256 received, uint256 positionId);

    // ============ View Functions ============

    /// @notice Get the current reserves for all supported stablecoins
    /// @return stablecoins Array of supported stablecoin addresses
    /// @return amounts Array of reserve amounts for each stablecoin
    function getReserves() external view returns (address[] memory stablecoins, uint256[] memory amounts);

    /// @notice Get the reserve amount for a specific stablecoin
    /// @param stablecoin The stablecoin address to query
    /// @return The reserve amount
    function getReserve(address stablecoin) external view returns (uint256);

    /// @notice Get all supported stablecoin addresses
    /// @return Array of supported stablecoin addresses
    function supportedStablecoins() external view returns (address[] memory);

    /// @notice Check if a stablecoin is supported
    /// @param stablecoin The stablecoin address to check
    /// @return True if the stablecoin is supported
    function isSupported(address stablecoin) external view returns (bool);

    /// @notice Get the DLRS token address
    /// @return The DLRS token contract address
    function dlrsToken() external view returns (address);

    // ============ Queue View Functions ============

    /// @notice Get total DLRS locked waiting for a specific stablecoin
    /// @param stablecoin The stablecoin to query
    /// @return Total DLRS amount in queue for this stablecoin
    function getQueueDepth(address stablecoin) external view returns (uint256);

    /// @notice Get details of a specific queue position
    /// @param positionId The position ID to query
    /// @return owner The address that owns this position
    /// @return stablecoin The stablecoin being waited for
    /// @return amount The remaining DLRS amount (decreases with partial fills)
    /// @return timestamp When the position was created
    function getQueuePosition(uint256 positionId)
        external
        view
        returns (address owner, address stablecoin, uint256 amount, uint256 timestamp);

    /// @notice Get all queue position IDs for a user
    /// @param user The user address to query
    /// @return positionIds Array of position IDs owned by this user
    function getUserQueuePositions(address user) external view returns (uint256[] memory positionIds);

    // ============ Aggregator Functions ============

    /// @notice Get expected output for a stablecoin swap (view function for aggregators)
    /// @dev Returns amountIn if reserves are sufficient, 0 otherwise. Never returns partial amounts.
    /// @param fromStablecoin The input stablecoin
    /// @param toStablecoin The output stablecoin
    /// @param amountIn Amount of input stablecoin
    /// @return Amount of output stablecoin (amountIn if fillable, 0 if not)
    function getSwapQuote(
        address fromStablecoin,
        address toStablecoin,
        uint256 amountIn
    ) external view returns (uint256);

    /// @notice Execute a swap optimized for aggregator integration
    /// @dev Never queues. Reverts if insufficient reserves. Supports custom recipient and deadline.
    /// @param fromStablecoin Input stablecoin address
    /// @param toStablecoin Output stablecoin address
    /// @param amountIn Amount of input stablecoin to swap
    /// @param minAmountOut Unused; included for router interface compatibility. Swaps are always 1:1 by design.
    /// @param recipient Address to receive output tokens
    /// @param deadline Unix timestamp after which the transaction reverts
    /// @return amountOut Actual amount of output stablecoin received
    function swapExactInput(
        address fromStablecoin,
        address toStablecoin,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external returns (uint256 amountOut);

    // ============ Depeg Protection Functions ============

    function pauseDeposits(address stablecoin) external;
    function unpauseDeposits(address stablecoin) external;
    function setPriceFeed(address stablecoin, address feed) external;
    function setPegTolerance(uint256 _tolerance) external;
    function setMaxStaleness(uint256 _staleness) external;
    function isDepositPaused(address stablecoin) external view returns (bool);
    function getPriceFeed(address stablecoin) external view returns (address);
    // ============ Admin Functions ============

    /// @notice Sync _reserves down to match actual balance after external events (e.g., seizure)
    /// @dev Only decreases reserves. Reverts if actual balance >= recorded reserves.
    /// @param stablecoin The stablecoin to sync
    function syncReserves(address stablecoin) external;

    /// @notice Rescue excess tokens sent directly to the contract outside protocol flows
    /// @dev Only sweeps the difference between actual balance and recorded reserves
    /// @param stablecoin The stablecoin to rescue
    /// @param to The address to send rescued tokens to
    function rescueTokens(address stablecoin, address to) external;
}
