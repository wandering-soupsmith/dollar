// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IDollarStore.sol";
import "./DLRS.sol";

/// @dev Minimal Chainlink AggregatorV3 interface for price feed reads
interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

/// @title DollarStore - A minimalist stablecoin aggregator and swap facility
/// @notice Deposit any supported stablecoin, receive DLRS. Redeem DLRS for any available stablecoin.
/// @dev Zero-fee, pure FIFO queue ordering.
/// @custom:security-contact admin@dollarstore.world
contract DollarStore is IDollarStore, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ Structs ============

    /// @notice A position in the swap queue
    struct QueuePosition {
        address owner; // Who owns this position
        address stablecoin; // Which stablecoin they want
        uint256 amount; // Remaining DLRS locked (decreases with partial fills)
        uint256 timestamp; // When position was created
        uint256 next; // Next position ID in the queue (0 = end of queue)
        uint256 prev; // Previous position ID (for efficient removal)
    }

    /// @notice Queue state for a specific stablecoin
    struct Queue {
        uint256 head; // First position ID in queue (0 = empty)
        uint256 tail; // Last position ID in queue
        uint256 totalDepth; // Total DLRS waiting in this queue
        uint256 positionCount; // Number of positions in this queue
    }

    // ============ Constants ============

    /// @notice Maximum number of positions allowed per stablecoin queue
    uint256 public constant MAX_QUEUE_POSITIONS = 150;
    /// @notice Base minimum order size for queue positions (100 DLRS)
    uint256 public constant MIN_ORDER_BASE = 100e6;
    /// @notice Number of queue positions per 10x minimum order increase
    uint256 public constant MIN_ORDER_SCALE_POSITIONS = 25;

    // ============ State Variables ============

    /// @notice The DLRS receipt token
    DLRS public immutable dlrs;

    /// @notice The governor address. Controls basket composition (addStablecoin, removeStablecoin) and role transfers.
    /// @dev Expected to be a TimelockController in production so governor actions have a public delay.
    address public governor;

    /// @notice The guardian address. Controls oracle wiring, peg parameters, emergency pause, and recovery operations.
    /// @dev Expected to be a multi-sig in production so guardian actions require N signatures and execute instantly.
    address public guardian;

    /// @notice Mapping of stablecoin address to whether it's supported
    mapping(address => bool) private _isSupported;

    /// @notice Mapping of stablecoin address to its reserve balance
    mapping(address => uint256) private _reserves;

    /// @notice Array of all supported stablecoin addresses
    address[] private _stablecoins;

    /// @notice Pending governor for two-step governor transfer
    address public pendingGovernor;

    /// @notice Pending guardian for two-step guardian transfer
    address public pendingGuardian;

    // Queue state
    /// @notice Counter for generating unique position IDs
    uint256 private _nextPositionId;

    /// @notice Mapping of position ID to position data
    mapping(uint256 => QueuePosition) private _positions;

    /// @notice Mapping of stablecoin to its queue
    mapping(address => Queue) private _queues;

    /// @notice Mapping of user to their position IDs
    mapping(address => uint256[]) private _userPositions;

    // Depeg protection state
    mapping(address => address) private _priceFeeds;
    mapping(address => bool) private _depositPaused;
    uint256 public pegTolerance;
    uint256 public maxStaleness;

    // ============ Events ============

    /// @notice Emitted when current governor initiates a two-step governor transfer
    event GovernorTransferInitiated(address indexed currentGovernor, address indexed pendingGovernor);
    /// @notice Emitted when the pending governor accepts the governor role
    event GovernorTransferCompleted(address indexed previousGovernor, address indexed newGovernor);
    /// @notice Emitted when governor initiates a two-step guardian transfer
    event GuardianTransferInitiated(address indexed currentGuardian, address indexed pendingGuardian);
    /// @notice Emitted when the pending guardian accepts the guardian role
    event GuardianTransferCompleted(address indexed previousGuardian, address indexed newGuardian);
    event ReservesSynced(address indexed stablecoin, uint256 previousReserves, uint256 actualBalance);
    event TokensRescued(address indexed stablecoin, address indexed to, uint256 amount);

    // ============ Errors ============

    error OnlyGovernor();
    error OnlyGuardian();
    error OnlyPendingGovernor();
    error OnlyPendingGuardian();
    error QueueFull(address stablecoin, uint256 currentCount);
    error OrderTooSmall(uint256 provided, uint256 minimum);
    error NoExcessTokens(address stablecoin);
    error ReservesNotDrifted(address stablecoin);
    error ArrayLengthMismatch();

    // ============ Modifiers ============

    modifier onlyGovernor() {
        if (msg.sender != governor) revert OnlyGovernor();
        _;
    }

    modifier onlyGuardian() {
        if (msg.sender != guardian) revert OnlyGuardian();
        _;
    }

    // ============ Constructor ============

    /// @notice Deploy a new DollarStore instance
    /// @param _governor Governor address (basket composition + role transfers; expected to be a TimelockController in production)
    /// @param _guardian Guardian address (oracle/peg setters + emergency pause + recovery; expected to be a multi-sig in production)
    /// @param initialStablecoins Array of stablecoin addresses to support initially
    /// @param initialPriceFeeds Parallel array of Chainlink price feed addresses, one per initial stablecoin
    constructor(
        address _governor,
        address _guardian,
        address[] memory initialStablecoins,
        address[] memory initialPriceFeeds
    ) {
        if (_governor == address(0)) revert ZeroAddress();
        if (_guardian == address(0)) revert ZeroAddress();
        if (initialStablecoins.length != initialPriceFeeds.length) revert ArrayLengthMismatch();

        governor = _governor;
        guardian = _guardian;
        dlrs = new DLRS(address(this));
        _nextPositionId = 1; // Start at 1 so 0 can mean "no position"
        pegTolerance = 50; // 0.5% default
        maxStaleness = 3600; // 1 hour default

        for (uint256 i = 0; i < initialStablecoins.length; i++) {
            if (initialPriceFeeds[i] == address(0)) revert ZeroAddress();
            _addStablecoin(initialStablecoins[i]);
            _priceFeeds[initialStablecoins[i]] = initialPriceFeeds[i];
            emit PriceFeedSet(initialStablecoins[i], initialPriceFeeds[i]);
        }
    }

    // ============ Core Functions ============

    /// @inheritdoc IDollarStore
    function deposit(address stablecoin, uint256 amount) external nonReentrant whenNotPaused returns (uint256 dlrsMinted) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);
        _checkPeg(stablecoin);

        // Transfer stablecoin from user to this contract
        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);

        // Process queue first - fill waiting positions in FIFO order
        uint256 remaining = _processQueue(stablecoin, amount);

        // Add remaining to reserves
        if (remaining > 0) {
            _reserves[stablecoin] += remaining;
        }

        // Mint DLRS 1:1 to depositor
        dlrsMinted = amount;
        dlrs.mint(msg.sender, dlrsMinted);

        emit Deposit(msg.sender, stablecoin, amount, dlrsMinted);
    }

    /// @inheritdoc IDollarStore
    /// @dev v2 pause semantics: withdraw is an exit path and is NOT blocked by pause(). Users can always exit.
    function withdraw(address stablecoin, uint256 amount) external nonReentrant returns (uint256 stablecoinReceived) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        uint256 available = _reserves[stablecoin];
        if (available < amount) revert InsufficientReserves(stablecoin, amount, available);

        // Burn DLRS from user
        dlrs.burn(msg.sender, amount);

        // Update reserves
        _reserves[stablecoin] -= amount;

        // Transfer stablecoin to user (1:1, no fee)
        stablecoinReceived = amount;
        IERC20(stablecoin).safeTransfer(msg.sender, stablecoinReceived);

        emit Withdraw(msg.sender, stablecoin, stablecoinReceived, amount);
    }

    // ============ Queue Functions ============

    /// @inheritdoc IDollarStore
    function joinQueue(address stablecoin, uint256 dlrsAmount) external nonReentrant whenNotPaused returns (uint256 positionId) {
        if (dlrsAmount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        Queue storage queue = _queues[stablecoin];

        // Check queue capacity
        if (queue.positionCount >= MAX_QUEUE_POSITIONS) {
            revert QueueFull(stablecoin, queue.positionCount);
        }

        // Check minimum order size
        uint256 minOrder = getMinimumOrderSize(stablecoin);
        if (dlrsAmount < minOrder) {
            revert OrderTooSmall(dlrsAmount, minOrder);
        }

        // Check user has enough DLRS
        uint256 userBalance = dlrs.balanceOf(msg.sender);
        if (userBalance < dlrsAmount) revert InsufficientDlrsBalance(dlrsAmount, userBalance);

        // Burn DLRS from user (held in escrow as "burned" until filled or cancelled)
        dlrs.burn(msg.sender, dlrsAmount);

        // Create position
        positionId = _nextPositionId++;
        _positions[positionId] = QueuePosition({
            owner: msg.sender,
            stablecoin: stablecoin,
            amount: dlrsAmount,
            timestamp: block.timestamp,
            next: 0,
            prev: 0
        });

        // Add to queue at tail (FIFO)
        if (queue.head == 0) {
            queue.head = positionId;
            queue.tail = positionId;
        } else {
            _positions[queue.tail].next = positionId;
            _positions[positionId].prev = queue.tail;
            queue.tail = positionId;
        }
        queue.totalDepth += dlrsAmount;
        queue.positionCount++;

        // Track user's positions
        _userPositions[msg.sender].push(positionId);

        emit QueueJoined(positionId, msg.sender, stablecoin, dlrsAmount, block.timestamp);
    }

    /// @inheritdoc IDollarStore
    /// @dev v2 pause semantics: cancelQueue is an exit path and is NOT blocked by pause(). Users can always recover queued DLRS.
    function cancelQueue(uint256 positionId) external nonReentrant returns (uint256 dlrsReturned) {
        QueuePosition storage position = _positions[positionId];

        // Validate position exists and caller owns it
        if (position.owner == address(0)) revert QueuePositionNotFound(positionId);
        if (position.owner != msg.sender) revert NotPositionOwner(positionId, msg.sender, position.owner);

        dlrsReturned = position.amount;

        // Remove from queue linked list
        _removeFromQueue(positionId, position.stablecoin);

        // Update queue stats
        _queues[position.stablecoin].totalDepth -= dlrsReturned;
        _queues[position.stablecoin].positionCount--;

        // Return DLRS to user (mint back since we burned on join)
        if (dlrsReturned > 0) {
            dlrs.mint(msg.sender, dlrsReturned);
        }

        // Clear position data
        delete _positions[positionId];

        // Remove from user's position list
        _removeUserPosition(msg.sender, positionId);

        emit QueueCancelled(positionId, msg.sender, dlrsReturned);
    }

    // ============ View Functions ============

    /// @inheritdoc IDollarStore
    function getReserves() external view returns (address[] memory stablecoins, uint256[] memory amounts) {
        uint256 length = _stablecoins.length;
        stablecoins = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            stablecoins[i] = _stablecoins[i];
            amounts[i] = _reserves[_stablecoins[i]];
        }
    }

    /// @inheritdoc IDollarStore
    function getReserve(address stablecoin) external view returns (uint256) {
        return _reserves[stablecoin];
    }

    /// @inheritdoc IDollarStore
    function supportedStablecoins() external view returns (address[] memory) {
        return _stablecoins;
    }

    /// @inheritdoc IDollarStore
    function isSupported(address stablecoin) external view returns (bool) {
        return _isSupported[stablecoin];
    }

    /// @inheritdoc IDollarStore
    function dlrsToken() external view returns (address) {
        return address(dlrs);
    }

    /// @inheritdoc IDollarStore
    function getQueueDepth(address stablecoin) external view returns (uint256) {
        return _queues[stablecoin].totalDepth;
    }

    /// @notice Get the number of positions in a queue
    function getQueuePositionCount(address stablecoin) external view returns (uint256) {
        return _queues[stablecoin].positionCount;
    }

    /// @inheritdoc IDollarStore
    function getQueuePosition(uint256 positionId)
        external
        view
        returns (address owner, address stablecoin, uint256 amount, uint256 timestamp)
    {
        QueuePosition storage position = _positions[positionId];
        owner = position.owner;
        stablecoin = position.stablecoin;
        amount = position.amount;
        timestamp = position.timestamp;
    }

    /// @inheritdoc IDollarStore
    function getUserQueuePositions(address user) external view returns (uint256[] memory positionIds) {
        positionIds = _userPositions[user];
    }

    /// @notice Get minimum order size for a queue based on current depth
    /// @param stablecoin The stablecoin queue to check
    /// @return Minimum order size in stablecoin units (6 decimals)
    function getMinimumOrderSize(address stablecoin) public view returns (uint256) {
        uint256 positionCount = _queues[stablecoin].positionCount;

        // minOrder = 100 * (10 ^ (positionCount / 25))
        // Using integer math: multiply by 10 for each 25 positions
        uint256 multiplier = 1;
        uint256 tiers = (positionCount + 1) / MIN_ORDER_SCALE_POSITIONS;

        for (uint256 i = 0; i < tiers; i++) {
            multiplier *= 10;
        }

        return MIN_ORDER_BASE * multiplier;
    }

    // ============ Swap Functions ============

    /// @inheritdoc IDollarStore
    function swap(
        address fromStablecoin,
        address toStablecoin,
        uint256 amount,
        bool queueIfUnavailable
    ) external nonReentrant whenNotPaused returns (uint256 received, uint256 positionId) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[fromStablecoin]) revert StablecoinNotSupported(fromStablecoin);
        if (!_isSupported[toStablecoin]) revert StablecoinNotSupported(toStablecoin);
        if (fromStablecoin == toStablecoin) revert SameStablecoin();
        _checkPeg(fromStablecoin);

        // Step 1: Transfer fromStablecoin from user
        IERC20(fromStablecoin).safeTransferFrom(msg.sender, address(this), amount);

        // Step 2: Process queue for fromStablecoin (FIFO)
        uint256 remaining = _processQueue(fromStablecoin, amount);

        // Add remaining to reserves
        if (remaining > 0) {
            _reserves[fromStablecoin] += remaining;
        }

        // Step 3: Try to withdraw toStablecoin
        uint256 available = _reserves[toStablecoin];

        if (available >= amount) {
            // Full instant swap
            _reserves[toStablecoin] -= amount;
            IERC20(toStablecoin).safeTransfer(msg.sender, amount);
            received = amount;
            positionId = 0;
        } else if (available > 0) {
            // Partial fill available
            received = available;
            _reserves[toStablecoin] = 0;
            IERC20(toStablecoin).safeTransfer(msg.sender, received);

            uint256 remaining_ = amount - received;
            if (queueIfUnavailable) {
                positionId = _createQueuePosition(toStablecoin, remaining_);
            } else {
                revert InsufficientReservesNoQueue(toStablecoin, amount, available);
            }
        } else {
            if (queueIfUnavailable) {
                positionId = _createQueuePosition(toStablecoin, amount);
                received = 0;
            } else {
                revert InsufficientReservesNoQueue(toStablecoin, amount, 0);
            }
        }

        uint256 amountQueued = positionId > 0 ? amount - received : 0;
        emit Swap(msg.sender, fromStablecoin, toStablecoin, amount, received, amountQueued);
    }

    /// @inheritdoc IDollarStore
    /// @dev v2 pause semantics: swapFromDLRS is an exit path (burns existing DLRS for stablecoin) and is NOT blocked by pause().
    ///      The queue-fallback case during pause produces a position that sits unfilled until unpause; user can recover via cancelQueue.
    function swapFromDLRS(
        address toStablecoin,
        uint256 dlrsAmount,
        bool queueIfUnavailable
    ) external nonReentrant returns (uint256 received, uint256 positionId) {
        if (dlrsAmount == 0) revert ZeroAmount();
        if (!_isSupported[toStablecoin]) revert StablecoinNotSupported(toStablecoin);

        uint256 userBalance = dlrs.balanceOf(msg.sender);
        if (userBalance < dlrsAmount) revert InsufficientDlrsBalance(dlrsAmount, userBalance);

        uint256 available = _reserves[toStablecoin];

        if (available >= dlrsAmount) {
            dlrs.burn(msg.sender, dlrsAmount);
            _reserves[toStablecoin] -= dlrsAmount;
            IERC20(toStablecoin).safeTransfer(msg.sender, dlrsAmount);
            received = dlrsAmount;
            positionId = 0;
        } else if (available > 0) {
            received = available;
            dlrs.burn(msg.sender, received);
            _reserves[toStablecoin] = 0;
            IERC20(toStablecoin).safeTransfer(msg.sender, received);

            uint256 remaining = dlrsAmount - received;
            if (queueIfUnavailable) {
                dlrs.burn(msg.sender, remaining);
                positionId = _createQueuePosition(toStablecoin, remaining);
            } else {
                revert InsufficientReservesNoQueue(toStablecoin, dlrsAmount, available);
            }
        } else {
            if (queueIfUnavailable) {
                dlrs.burn(msg.sender, dlrsAmount);
                positionId = _createQueuePosition(toStablecoin, dlrsAmount);
                received = 0;
            } else {
                revert InsufficientReservesNoQueue(toStablecoin, dlrsAmount, 0);
            }
        }

        uint256 amountQueued = positionId > 0 ? dlrsAmount - received : 0;
        emit Swap(msg.sender, address(dlrs), toStablecoin, dlrsAmount, received, amountQueued);
    }

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
    ) external view returns (uint256) {
        // Return 0 for unsupported stablecoins
        if (!_isSupported[fromStablecoin] || !_isSupported[toStablecoin]) {
            return 0;
        }
        // Return 0 for same stablecoin (no-op not allowed)
        if (fromStablecoin == toStablecoin) {
            return 0;
        }

        // Only return full amount if reserves can cover it entirely
        uint256 available = _reserves[toStablecoin];
        return available >= amountIn ? amountIn : 0;
    }

    /// @notice Execute a swap optimized for aggregator integration
    /// @dev Never queues. Reverts if insufficient reserves. Supports custom recipient and deadline.
    /// @param fromStablecoin Input stablecoin address
    /// @param toStablecoin Output stablecoin address
    /// @param amountIn Amount of input stablecoin to swap
    /// @param minAmountOut Unused; included for router interface compatibility. Swaps are always 1:1 by design.
    /// @param recipient Address to receive output tokens
    /// @param deadline Unix timestamp after which the transaction reverts
    /// @return amountOut Actual amount of output stablecoin received (always equals amountIn for 1:1)
    function swapExactInput(
        address fromStablecoin,
        address toStablecoin,
        uint256 amountIn,
        uint256 minAmountOut,
        address recipient,
        uint256 deadline
    ) external nonReentrant whenNotPaused returns (uint256 amountOut) {
        // Check deadline
        if (block.timestamp > deadline) {
            revert DeadlineExpired(deadline, block.timestamp);
        }

        // Validate inputs
        if (amountIn == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAddress();
        if (recipient == address(this)) revert InvalidRecipient();
        if (!_isSupported[fromStablecoin]) revert StablecoinNotSupported(fromStablecoin);
        if (!_isSupported[toStablecoin]) revert StablecoinNotSupported(toStablecoin);
        if (fromStablecoin == toStablecoin) revert SameStablecoin();
        _checkPeg(fromStablecoin);

        // Check output reserves BEFORE any transfers (fail fast)
        uint256 available = _reserves[toStablecoin];
        if (available < amountIn) {
            revert InsufficientReservesNoQueue(toStablecoin, amountIn, available);
        }

        // Transfer input stablecoin from caller
        IERC20(fromStablecoin).safeTransferFrom(msg.sender, address(this), amountIn);

        // Process queue for input stablecoin (fills waiting orders)
        uint256 remaining = _processQueue(fromStablecoin, amountIn);

        // Add remainder to reserves
        if (remaining > 0) {
            _reserves[fromStablecoin] += remaining;
        }

        // Execute output transfer (1:1)
        amountOut = amountIn;
        _reserves[toStablecoin] -= amountOut;
        IERC20(toStablecoin).safeTransfer(recipient, amountOut);

        emit Swap(msg.sender, fromStablecoin, toStablecoin, amountIn, amountOut, 0);
    }

    // ============ Admin Functions ============

    /// @notice Add a new supported stablecoin to the protocol
    /// @dev Governor-gated. Production governor is a TimelockController, so this action carries a public delay window.
    /// @param stablecoin Address of the ERC-20 stablecoin to add
    function addStablecoin(address stablecoin) external onlyGovernor {
        _addStablecoin(stablecoin);
    }

    /// @notice Remove a supported stablecoin from the protocol
    /// @dev Governor-gated. Reverts if the stablecoin still has reserves or active queue positions.
    /// @param stablecoin Address of the stablecoin to remove
    function removeStablecoin(address stablecoin) external onlyGovernor {
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);
        if (_reserves[stablecoin] > 0) revert InsufficientReserves(stablecoin, 0, _reserves[stablecoin]);
        if (_queues[stablecoin].totalDepth > 0) revert ActiveQueuePositions(stablecoin);

        _isSupported[stablecoin] = false;

        for (uint256 i = 0; i < _stablecoins.length; i++) {
            if (_stablecoins[i] == stablecoin) {
                _stablecoins[i] = _stablecoins[_stablecoins.length - 1];
                _stablecoins.pop();
                break;
            }
        }

        emit StablecoinRemoved(stablecoin);
    }

    /// @notice Initiate a two-step governor transfer
    /// @dev Governor-gated. The new governor must subsequently call acceptGovernor to take the role.
    /// @param newGovernor Address of the proposed new governor
    function transferGovernor(address newGovernor) external onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        pendingGovernor = newGovernor;
        emit GovernorTransferInitiated(governor, newGovernor);
    }

    /// @notice Accept the governor role (must be called by the pending governor)
    function acceptGovernor() external {
        if (msg.sender != pendingGovernor) revert OnlyPendingGovernor();
        address previousGovernor = governor;
        governor = pendingGovernor;
        pendingGovernor = address(0);
        emit GovernorTransferCompleted(previousGovernor, governor);
    }

    /// @notice Initiate a two-step guardian transfer
    /// @dev Governor-gated (NOT guardian-gated). Reasoning: if guardian could rotate itself, a compromised
    ///      guardian could lock out the legitimate one. The governor's slower path is the protection mechanism
    ///      for the role that holds the emergency-response power.
    /// @param newGuardian Address of the proposed new guardian
    function transferGuardian(address newGuardian) external onlyGovernor {
        if (newGuardian == address(0)) revert ZeroAddress();
        pendingGuardian = newGuardian;
        emit GuardianTransferInitiated(guardian, newGuardian);
    }

    /// @notice Accept the guardian role (must be called by the pending guardian)
    function acceptGuardian() external {
        if (msg.sender != pendingGuardian) revert OnlyPendingGuardian();
        address previousGuardian = guardian;
        guardian = pendingGuardian;
        pendingGuardian = address(0);
        emit GuardianTransferCompleted(previousGuardian, guardian);
    }

    /// @notice Sync _reserves down to match actual balance after external events (e.g., seizure)
    /// @dev Guardian-gated (instant). Only decreases reserves. If actual balance >= recorded reserves, reverts.
    /// @param stablecoin The stablecoin to sync
    function syncReserves(address stablecoin) external onlyGuardian {
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        uint256 actualBalance = IERC20(stablecoin).balanceOf(address(this));
        uint256 currentReserves = _reserves[stablecoin];

        if (actualBalance >= currentReserves) revert ReservesNotDrifted(stablecoin);

        _reserves[stablecoin] = actualBalance;

        emit ReservesSynced(stablecoin, currentReserves, actualBalance);
    }

    /// @notice Rescue excess tokens sent directly to the contract outside protocol flows
    /// @dev Guardian-gated (instant). Only sweeps the difference between actual balance and recorded reserves.
    /// @param stablecoin The stablecoin to rescue
    /// @param to The address to send rescued tokens to
    function rescueTokens(address stablecoin, address to) external onlyGuardian {
        if (to == address(0)) revert ZeroAddress();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        uint256 actualBalance = IERC20(stablecoin).balanceOf(address(this));
        uint256 currentReserves = _reserves[stablecoin];

        if (actualBalance <= currentReserves) revert NoExcessTokens(stablecoin);

        uint256 excess = actualBalance - currentReserves;
        IERC20(stablecoin).safeTransfer(to, excess);

        emit TokensRescued(stablecoin, to, excess);
    }

    /// @notice Pause new-exposure protocol operations (deposit, swap, joinQueue). Exit paths remain open.
    /// @dev Guardian-gated (instant). With v2 pause semantics, withdraw / cancelQueue / swapFromDLRS continue to work.
    function pause() external onlyGuardian {
        _pause();
    }

    /// @notice Unpause all protocol operations
    function unpause() external onlyGuardian {
        _unpause();
    }

    // ============ Depeg Protection Admin Functions ============

    /// @inheritdoc IDollarStore
    function pauseDeposits(address stablecoin) external onlyGuardian {
        _depositPaused[stablecoin] = true;
        emit DepositPauseToggled(stablecoin, true);
    }

    /// @inheritdoc IDollarStore
    function unpauseDeposits(address stablecoin) external onlyGuardian {
        _depositPaused[stablecoin] = false;
        emit DepositPauseToggled(stablecoin, false);
    }

    /// @inheritdoc IDollarStore
    function setPriceFeed(address stablecoin, address feed) external onlyGuardian {
        if (feed == address(0)) revert ZeroAddress();
        _priceFeeds[stablecoin] = feed;
        emit PriceFeedSet(stablecoin, feed);
    }

    /// @inheritdoc IDollarStore
    function setPegTolerance(uint256 _tolerance) external onlyGuardian {
        if (_tolerance > 500) revert InvalidTolerance();
        pegTolerance = _tolerance;
        emit PegToleranceSet(_tolerance);
    }

    /// @inheritdoc IDollarStore
    function setMaxStaleness(uint256 _staleness) external onlyGuardian {
        if (_staleness == 0 || _staleness > 86400) revert InvalidStaleness();
        maxStaleness = _staleness;
        emit MaxStalenessSet(_staleness);
    }

    // ============ Depeg Protection View Functions ============

    /// @inheritdoc IDollarStore
    function isDepositPaused(address stablecoin) external view returns (bool) {
        return _depositPaused[stablecoin];
    }

    /// @inheritdoc IDollarStore
    function getPriceFeed(address stablecoin) external view returns (address) {
        return _priceFeeds[stablecoin];
    }
    /// @notice Admin force-cancel a queue position, returning DLRS to the position owner
    /// @dev Guardian-gated (instant). Function name retained for ABI compatibility with v1 indexers.
    /// @param positionId The position ID to cancel
    /// @return dlrsReturned The amount of DLRS returned to the position owner
    function adminCancelQueue(uint256 positionId) external onlyGuardian returns (uint256 dlrsReturned) {
        QueuePosition storage position = _positions[positionId];

        if (position.owner == address(0)) revert QueuePositionNotFound(positionId);

        dlrsReturned = position.amount;
        address positionOwner = position.owner;

        _removeFromQueue(positionId, position.stablecoin);

        _queues[position.stablecoin].totalDepth -= dlrsReturned;
        _queues[position.stablecoin].positionCount--;

        if (dlrsReturned > 0) {
            dlrs.mint(positionOwner, dlrsReturned);
        }

        delete _positions[positionId];

        _removeUserPosition(positionOwner, positionId);

        emit QueueCancelled(positionId, positionOwner, dlrsReturned);
    }

    // ============ Internal Functions ============

    function _createQueuePosition(address stablecoin, uint256 amount) internal returns (uint256 positionId) {
        Queue storage queue = _queues[stablecoin];

        // Check capacity and minimum order
        if (queue.positionCount >= MAX_QUEUE_POSITIONS) {
            revert QueueFull(stablecoin, queue.positionCount);
        }

        uint256 minOrder = getMinimumOrderSize(stablecoin);
        if (amount < minOrder) {
            revert OrderTooSmall(amount, minOrder);
        }

        positionId = _nextPositionId++;
        _positions[positionId] = QueuePosition({
            owner: msg.sender,
            stablecoin: stablecoin,
            amount: amount,
            timestamp: block.timestamp,
            next: 0,
            prev: 0
        });

        if (queue.head == 0) {
            queue.head = positionId;
            queue.tail = positionId;
        } else {
            _positions[queue.tail].next = positionId;
            _positions[positionId].prev = queue.tail;
            queue.tail = positionId;
        }
        queue.totalDepth += amount;
        queue.positionCount++;

        _userPositions[msg.sender].push(positionId);

        emit QueueJoined(positionId, msg.sender, stablecoin, amount, block.timestamp);
    }

    function _addStablecoin(address stablecoin) internal {
        if (stablecoin == address(0)) revert ZeroAddress();
        if (_isSupported[stablecoin]) revert StablecoinAlreadySupported(stablecoin);

        _isSupported[stablecoin] = true;
        _stablecoins.push(stablecoin);

        emit StablecoinAdded(stablecoin);
    }

    /// @dev Process queue in FIFO order (first in, first out)
    /// @dev Uses try-pattern for transfers: if a transfer fails (e.g. blacklisted recipient),
    ///      the position is ejected and the owner is refunded DLRS instead of bricking the queue.
    function _processQueue(address stablecoin, uint256 amount) internal returns (uint256 remaining) {
        Queue storage queue = _queues[stablecoin];
        uint256 remaining = amount;

        if (queue.head == 0) return remaining;

        uint256 current = queue.head;

        while (current != 0 && remaining > 0) {
            QueuePosition storage position = _positions[current];
            address positionOwner = position.owner;
            uint256 next = position.next;

            if (position.amount <= remaining) {
                // Full fill
                uint256 fillAmount = position.amount;

                if (_tryTransfer(stablecoin, positionOwner, fillAmount)) {
                    // Success: normal fill
                    remaining -= fillAmount;
                    emit QueueFilled(current, positionOwner, stablecoin, fillAmount, 0);
                } else {
                    // Transfer failed (e.g. blacklisted): eject position, refund DLRS
                    dlrs.mint(positionOwner, fillAmount);
                    emit QueuePositionRefunded(current, positionOwner, stablecoin, fillAmount);
                }

                // In both cases: remove position from queue
                _removeFromQueue(current, stablecoin);
                queue.totalDepth -= fillAmount;
                queue.positionCount--;
                _removeUserPosition(positionOwner, current);
                delete _positions[current];
            } else {
                // Partial fill
                uint256 fillAmount = remaining;

                if (_tryTransfer(stablecoin, positionOwner, fillAmount)) {
                    // Success: normal partial fill
                    position.amount -= fillAmount;
                    remaining = 0;
                    emit QueueFilled(current, positionOwner, stablecoin, fillAmount, position.amount);
                    queue.totalDepth -= fillAmount;
                } else {
                    // Transfer failed: eject ENTIRE position, refund ALL as DLRS
                    uint256 totalRefund = position.amount;
                    dlrs.mint(positionOwner, totalRefund);
                    emit QueuePositionRefunded(current, positionOwner, stablecoin, totalRefund);

                    // remaining unchanged (fillAmount was never consumed)
                    _removeFromQueue(current, stablecoin);
                    queue.totalDepth -= totalRefund;
                    queue.positionCount--;
                    _removeUserPosition(positionOwner, current);
                    delete _positions[current];
                }
            }

            current = next;
        }

        return remaining;
    }

    /// @dev Attempt an ERC-20 transfer, returning false instead of reverting on failure
    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool) {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        return success && (data.length == 0 || abi.decode(data, (bool)));
    }

    function _removeFromQueue(uint256 positionId, address stablecoin) internal {
        Queue storage queue = _queues[stablecoin];
        QueuePosition storage position = _positions[positionId];

        if (position.prev != 0) {
            _positions[position.prev].next = position.next;
        } else {
            queue.head = position.next;
        }

        if (position.next != 0) {
            _positions[position.next].prev = position.prev;
        } else {
            queue.tail = position.prev;
        }
    }

    function _removeUserPosition(address user, uint256 positionId) internal {
        uint256[] storage positions = _userPositions[user];
        for (uint256 i = 0; i < positions.length; i++) {
            if (positions[i] == positionId) {
                positions[i] = positions[positions.length - 1];
                positions.pop();
                break;
            }
        }
    }

    /// @dev Check peg status for a stablecoin before accepting deposits
    function _checkPeg(address stablecoin) internal view {
        if (_depositPaused[stablecoin]) revert DepositsPaused(stablecoin);

        address feed = _priceFeeds[stablecoin];
        if (feed == address(0)) revert NoPriceFeed(stablecoin);

        AggregatorV3Interface priceFeed = AggregatorV3Interface(feed);
        (, int256 price,, uint256 updatedAt,) = priceFeed.latestRoundData();

        if (block.timestamp - updatedAt > maxStaleness) {
            revert PriceStale(stablecoin, updatedAt);
        }

        // Normalize price to 18 decimals for comparison
        uint8 feedDecimals = priceFeed.decimals();
        uint256 normalizedPrice = uint256(price > 0 ? price : int256(0)) * (10 ** (18 - feedDecimals));
        uint256 target = 1e18;
        uint256 lower = target - (target * pegTolerance / 10000);
        uint256 upper = target + (target * pegTolerance / 10000);

        if (normalizedPrice < lower || normalizedPrice > upper) {
            revert PriceOutOfBounds(stablecoin, normalizedPrice, lower, upper);
        }
    }
}
