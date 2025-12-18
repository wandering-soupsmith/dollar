// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDollarStore - Interface for the Dollar Store protocol
/// @notice A minimalist stablecoin aggregator and 1:1 swap facility
interface IDollarStore {
    // ============ Events ============

    event Deposit(address indexed user, address indexed stablecoin, uint256 amount, uint256 dlrsMinted);
    event Withdraw(address indexed user, address indexed stablecoin, uint256 amount, uint256 dlrsBurned);
    event StablecoinAdded(address indexed stablecoin);
    event StablecoinRemoved(address indexed stablecoin);

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
    event QueueFilled(
        uint256 indexed positionId,
        address indexed user,
        address indexed stablecoin,
        uint256 amountFilled,
        uint256 amountRemaining
    );

    // Reward events
    event RewardsAccrued(uint256 feeAmount, uint256 rewardMinted, uint256 bankAmount, uint256 newRewardPerToken);
    event RewardsClaimed(address indexed user, uint256 dlrsAmount);
    event BankWithdrawal(address indexed stablecoin, address indexed to, uint256 amount);

    // ============ Errors ============

    error StablecoinNotSupported(address stablecoin);
    error StablecoinAlreadySupported(address stablecoin);
    error InsufficientReserves(address stablecoin, uint256 requested, uint256 available);
    error ZeroAmount();
    error ZeroAddress();
    error TransferFailed();

    // Queue errors
    error QueuePositionNotFound(uint256 positionId);
    error NotPositionOwner(uint256 positionId, address caller, address owner);
    error InsufficientDlrsBalance(uint256 required, uint256 available);

    // Swap errors
    error SameStablecoin();
    error InsufficientReservesNoQueue(address stablecoin, uint256 requested, uint256 available);

    // Reward errors
    error NoRewardsToClaim();

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
    /// @dev Locks DLRS in escrow until filled or cancelled
    /// @param stablecoin The stablecoin you want to receive
    /// @param dlrsAmount The amount of DLRS to lock (1:1 with desired stablecoin)
    /// @return positionId The unique ID for this queue position
    function joinQueue(address stablecoin, uint256 dlrsAmount) external returns (uint256 positionId);

    /// @notice Cancel a queue position and reclaim locked DLRS
    /// @param positionId The position ID to cancel
    /// @return dlrsReturned The amount of DLRS returned (may be less if partially filled)
    function cancelQueue(uint256 positionId) external returns (uint256 dlrsReturned);

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

    // ============ Reward Functions ============

    /// @notice Calculate pending rewards for a user
    /// @param user The user address to check
    /// @return pending The amount of DLRS rewards available to claim
    function pendingRewards(address user) external view returns (uint256 pending);

    /// @notice Claim accumulated DLRS rewards
    /// @return claimed The amount of DLRS transferred to caller
    function claimRewards() external returns (uint256 claimed);

    /// @notice Get the total DLRS held for reward distribution
    /// @return The amount of DLRS in the reward pool
    function getRewardPool() external view returns (uint256);

    /// @notice Get the bank balance for a specific stablecoin
    /// @param stablecoin The stablecoin to query
    /// @return The amount of stablecoin in the bank
    function getBankBalance(address stablecoin) external view returns (uint256);

    /// @notice Get all bank balances
    /// @return stablecoins Array of stablecoin addresses
    /// @return amounts Array of bank amounts for each stablecoin
    function getBankBalances() external view returns (address[] memory stablecoins, uint256[] memory amounts);
}
