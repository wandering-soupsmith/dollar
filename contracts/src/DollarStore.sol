// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IDollarStore.sol";
import "./DLRS.sol";
import "./CENTS.sol";

/// @title DollarStore - A minimalist stablecoin aggregator and swap facility
/// @notice Deposit any supported stablecoin, receive DLRS. Redeem DLRS for any available stablecoin.
/// @dev Integrates CENTS token for fee discounts and queue priority.
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

    uint256 public constant REDEMPTION_FEE_BPS = 0; // No fee
    uint256 public constant BPS_DENOMINATOR = 10000;

    // Queue limits
    uint256 public constant MAX_QUEUE_POSITIONS = 150;
    uint256 public constant MIN_ORDER_BASE = 100e6; // $100 with 6 decimals
    uint256 public constant MIN_ORDER_SCALE_POSITIONS = 25; // Positions per 10x increase

    // ============ State Variables ============

    /// @notice The DLRS receipt token
    DLRS public immutable dlrs;

    /// @notice The CENTS utility token
    CENTS public cents;

    /// @notice The admin address that can add/remove supported stablecoins
    address public admin;

    /// @notice Mapping of stablecoin address to whether it's supported
    mapping(address => bool) private _isSupported;

    /// @notice Mapping of stablecoin address to its reserve balance
    mapping(address => uint256) private _reserves;

    /// @notice Array of all supported stablecoin addresses
    address[] private _stablecoins;

    /// @notice Pending admin for two-step admin transfer
    address public pendingAdmin;

    // Queue state
    /// @notice Counter for generating unique position IDs
    uint256 private _nextPositionId;

    /// @notice Mapping of position ID to position data
    mapping(uint256 => QueuePosition) private _positions;

    /// @notice Mapping of stablecoin to its queue
    mapping(address => Queue) private _queues;

    /// @notice Mapping of user to their position IDs
    mapping(address => uint256[]) private _userPositions;

    /// @notice Operator's accumulated fee revenue per stablecoin
    mapping(address => uint256) private _bank;

    // ============ Events ============

    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferCompleted(address indexed previousAdmin, address indexed newAdmin);
    event FeeCollected(address indexed stablecoin, uint256 feeAmount);
    event CentsTokenSet(address indexed centsToken);

    // ============ Errors ============

    error OnlyAdmin();
    error OnlyPendingAdmin();
    error QueueFull(address stablecoin, uint256 currentCount);
    error OrderTooSmall(uint256 provided, uint256 minimum);
    error CentsNotSet();

    // ============ Modifiers ============

    modifier onlyAdmin() {
        if (msg.sender != admin) revert OnlyAdmin();
        _;
    }

    // ============ Constructor ============

    /// @notice Deploy a new DollarStore instance
    /// @param _admin The admin address that can manage stablecoins and pause the contract
    /// @param initialStablecoins Array of stablecoin addresses to support initially
    constructor(address _admin, address[] memory initialStablecoins) {
        if (_admin == address(0)) revert ZeroAddress();

        admin = _admin;
        dlrs = new DLRS(address(this));
        _nextPositionId = 1; // Start at 1 so 0 can mean "no position"

        for (uint256 i = 0; i < initialStablecoins.length; i++) {
            _addStablecoin(initialStablecoins[i]);
        }
    }

    // ============ Admin: CENTS Setup ============

    /// @notice Set the CENTS token address (one-time setup)
    /// @param _cents The CENTS token contract address
    function setCentsToken(address _cents) external onlyAdmin {
        if (address(cents) != address(0)) revert(); // Already set
        if (_cents == address(0)) revert ZeroAddress();
        cents = CENTS(_cents);
        emit CentsTokenSet(_cents);
    }

    // ============ Core Functions ============

    /// @inheritdoc IDollarStore
    function deposit(address stablecoin, uint256 amount) external nonReentrant whenNotPaused returns (uint256 dlrsMinted) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        // Transfer stablecoin from user to this contract
        IERC20(stablecoin).safeTransferFrom(msg.sender, address(this), amount);

        // Track how much queue we clear for taker rewards
        uint256 queueClearedAmount = 0;
        uint256 queueDepthBefore = _queues[stablecoin].totalDepth;

        // Process queue first - fill waiting positions by fill score order
        uint256 remaining = _processQueue(stablecoin, amount);

        // Calculate how much queue was cleared
        if (queueDepthBefore > 0) {
            queueClearedAmount = queueDepthBefore - _queues[stablecoin].totalDepth;
        }

        // Add remaining to reserves
        if (remaining > 0) {
            _reserves[stablecoin] += remaining;
        }

        // Mint DLRS 1:1 to depositor
        dlrsMinted = amount;
        dlrs.mint(msg.sender, dlrsMinted);

        // Mint taker rewards if queue was cleared and CENTS is set
        if (queueClearedAmount > 0 && address(cents) != address(0)) {
            uint256 feeGenerated = (queueClearedAmount * REDEMPTION_FEE_BPS) / BPS_DENOMINATOR;
            cents.mintTakerRewards(msg.sender, queueClearedAmount, feeGenerated);
        }

        emit Deposit(msg.sender, stablecoin, amount, dlrsMinted);
    }

    /// @inheritdoc IDollarStore
    function withdraw(address stablecoin, uint256 amount) external nonReentrant whenNotPaused returns (uint256 stablecoinReceived) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        // Calculate fee with CENTS discount
        (uint256 netOutput, ) = _collectFeeWithDiscount(stablecoin, amount, msg.sender);

        uint256 available = _reserves[stablecoin];
        if (available < netOutput) revert InsufficientReserves(stablecoin, netOutput, available);

        // Burn DLRS from user (full amount including fee portion)
        dlrs.burn(msg.sender, amount);

        // Update reserves (only decrease by netOutput, fee portion stays)
        _reserves[stablecoin] -= netOutput;

        // Transfer stablecoin to user (net of fee)
        stablecoinReceived = netOutput;
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

        // Add to queue (at tail - will be sorted by fill score when processing)
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
    function cancelQueue(uint256 positionId) external nonReentrant whenNotPaused returns (uint256 dlrsReturned) {
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

    /// @notice Get the CENTS token address
    function centsToken() external view returns (address) {
        return address(cents);
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
        return (position.owner, position.stablecoin, position.amount, position.timestamp);
    }

    /// @inheritdoc IDollarStore
    function getUserQueuePositions(address user) external view returns (uint256[] memory positionIds) {
        return _userPositions[user];
    }

    /// @notice Get position info including fill score ranking
    /// @param positionId The position ID to check
    /// @return amountAhead Total DLRS amount that will be filled before this position
    /// @return positionNumber The 1-indexed position number in the queue
    function getQueuePositionInfo(uint256 positionId) external view returns (uint256 amountAhead, uint256 positionNumber) {
        QueuePosition storage position = _positions[positionId];
        if (position.owner == address(0)) return (0, 0);

        address stablecoin = position.stablecoin;

        // Get sorted positions by fill score
        (uint256[] memory sortedIds, ) = _getSortedQueuePositions(stablecoin);

        // Find this position in the sorted list
        uint256 accumulated = 0;
        for (uint256 i = 0; i < sortedIds.length; i++) {
            if (sortedIds[i] == positionId) {
                return (accumulated, i + 1);
            }
            accumulated += _positions[sortedIds[i]].amount;
        }

        return (0, 0);
    }

    /// @notice Get minimum order size for a queue based on current depth
    /// @param stablecoin The stablecoin queue to check
    /// @return Minimum order size in stablecoin units (6 decimals)
    function getMinimumOrderSize(address stablecoin) public view returns (uint256) {
        uint256 positionCount = _queues[stablecoin].positionCount;

        // minOrder = 100 * (10 ^ (positionCount / 25))
        // Using integer math: multiply by 10 for each 25 positions
        uint256 multiplier = 1;
        uint256 tiers = positionCount / MIN_ORDER_SCALE_POSITIONS;

        for (uint256 i = 0; i < tiers; i++) {
            multiplier *= 10;
        }

        return MIN_ORDER_BASE * multiplier;
    }

    /// @notice Get the bank balance for a specific stablecoin
    function getBankBalance(address stablecoin) external view returns (uint256) {
        return _bank[stablecoin];
    }

    /// @notice Get all bank balances
    function getBankBalances() external view returns (address[] memory stablecoins, uint256[] memory amounts) {
        uint256 length = _stablecoins.length;
        stablecoins = new address[](length);
        amounts = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            stablecoins[i] = _stablecoins[i];
            amounts[i] = _bank[_stablecoins[i]];
        }
    }

    /// @notice Calculate fill score for a queue position
    /// @param positionId The position to calculate score for
    /// @return score The fill score (higher = filled first)
    function getFillScore(uint256 positionId) public view returns (uint256 score) {
        QueuePosition storage position = _positions[positionId];
        if (position.owner == address(0)) return 0;

        uint256 secondsInQueue = block.timestamp - position.timestamp;
        uint256 fillSize = position.amount;

        // Get stake power from CENTS (0 if CENTS not set)
        uint256 stakePower = 0;
        if (address(cents) != address(0)) {
            stakePower = cents.getStakePower(position.owner);
        }

        // fillScore = (basePower + stakePower / sqrt(fillSize)) * secondsInQueue
        // basePower = 1e6 (scaled for precision)
        uint256 basePower = 1e6;

        // stakePower / sqrt(fillSize) - need to handle sqrt
        uint256 stakeBoost = 0;
        if (stakePower > 0 && fillSize > 0) {
            // Convert fillSize from 6 decimals to whole units for sqrt
            uint256 fillSizeWhole = fillSize / 1e6;
            if (fillSizeWhole == 0) fillSizeWhole = 1;
            uint256 sqrtFillSize = _sqrt(fillSizeWhole);
            if (sqrtFillSize == 0) sqrtFillSize = 1;
            stakeBoost = stakePower / sqrtFillSize;
        }

        score = (basePower + stakeBoost) * secondsInQueue;
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

        // Step 1: Transfer fromStablecoin from user
        IERC20(fromStablecoin).safeTransferFrom(msg.sender, address(this), amount);

        // Track queue cleared for taker rewards
        uint256 queueDepthBefore = _queues[fromStablecoin].totalDepth;

        // Step 2: Process queue for fromStablecoin
        uint256 remaining = _processQueue(fromStablecoin, amount);

        // Calculate queue cleared
        uint256 queueCleared = queueDepthBefore - _queues[fromStablecoin].totalDepth;

        // Add remaining to reserves
        if (remaining > 0) {
            _reserves[fromStablecoin] += remaining;
        }

        // Mint taker rewards if queue was cleared
        if (queueCleared > 0 && address(cents) != address(0)) {
            uint256 feeGenerated = (queueCleared * REDEMPTION_FEE_BPS) / BPS_DENOMINATOR;
            cents.mintTakerRewards(msg.sender, queueCleared, feeGenerated);
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
                dlrs.mint(msg.sender, remaining_);
            }
        } else {
            if (queueIfUnavailable) {
                positionId = _createQueuePosition(toStablecoin, amount);
                received = 0;
            } else {
                revert InsufficientReservesNoQueue(toStablecoin, amount, 0);
            }
        }

        emit Swap(msg.sender, fromStablecoin, toStablecoin, amount, received, amount - received);
    }

    /// @inheritdoc IDollarStore
    function swapFromDLRS(
        address toStablecoin,
        uint256 dlrsAmount,
        bool queueIfUnavailable
    ) external nonReentrant whenNotPaused returns (uint256 received, uint256 positionId) {
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

        emit Swap(msg.sender, address(dlrs), toStablecoin, dlrsAmount, received, dlrsAmount - received);
    }

    // ============ Admin Functions ============

    function addStablecoin(address stablecoin) external onlyAdmin {
        _addStablecoin(stablecoin);
    }

    function removeStablecoin(address stablecoin) external onlyAdmin {
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);
        if (_reserves[stablecoin] > 0) revert InsufficientReserves(stablecoin, 0, _reserves[stablecoin]);

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

    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(admin, newAdmin);
    }

    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert OnlyPendingAdmin();
        address previousAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit AdminTransferCompleted(previousAdmin, admin);
    }

    function pause() external onlyAdmin {
        _pause();
    }

    function unpause() external onlyAdmin {
        _unpause();
    }

    function withdrawBank(address stablecoin, address to) external onlyAdmin nonReentrant returns (uint256 amount) {
        if (to == address(0)) revert ZeroAddress();

        amount = _bank[stablecoin];
        if (amount == 0) revert ZeroAmount();

        _bank[stablecoin] = 0;
        IERC20(stablecoin).safeTransfer(to, amount);

        emit BankWithdrawal(stablecoin, to, amount);
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

    /// @dev Process queue by fill score order (highest first)
    function _processQueue(address stablecoin, uint256 amount) internal returns (uint256 remaining) {
        Queue storage queue = _queues[stablecoin];
        remaining = amount;

        if (queue.head == 0) return remaining;

        // Get positions sorted by fill score
        (uint256[] memory sortedIds, uint256 count) = _getSortedQueuePositions(stablecoin);

        // Fill in order of fill score (highest first)
        for (uint256 i = 0; i < count && remaining > 0; i++) {
            uint256 positionId = sortedIds[i];
            QueuePosition storage position = _positions[positionId];

            if (position.amount == 0) continue; // Already fully filled

            address positionOwner = position.owner;
            uint256 fillAmount;
            uint256 secondsQueued = block.timestamp - position.timestamp;

            if (position.amount <= remaining) {
                // Full fill
                fillAmount = position.amount;
                remaining -= fillAmount;

                // Collect fee
                (uint256 netOutput, ) = _collectFee(stablecoin, fillAmount);

                // Transfer stablecoin to position owner
                IERC20(stablecoin).safeTransfer(positionOwner, netOutput);

                // Mint maker rewards
                if (address(cents) != address(0)) {
                    cents.mintMakerRewards(positionOwner, fillAmount, secondsQueued);
                }

                emit QueueFilled(positionId, positionOwner, stablecoin, netOutput, 0);

                // Remove from queue
                _removeFromQueue(positionId, stablecoin);
                queue.totalDepth -= fillAmount;
                queue.positionCount--;
                _removeUserPosition(positionOwner, positionId);
                delete _positions[positionId];
            } else {
                // Partial fill
                fillAmount = remaining;
                position.amount -= fillAmount;
                remaining = 0;

                // Collect fee on partial
                (uint256 netOutput, ) = _collectFee(stablecoin, fillAmount);

                // Transfer partial amount
                IERC20(stablecoin).safeTransfer(positionOwner, netOutput);

                // Mint maker rewards for filled portion
                if (address(cents) != address(0)) {
                    cents.mintMakerRewards(positionOwner, fillAmount, secondsQueued);
                }

                emit QueueFilled(positionId, positionOwner, stablecoin, netOutput, position.amount);

                queue.totalDepth -= fillAmount;
            }
        }
    }

    /// @dev Get queue positions sorted by fill score (descending)
    function _getSortedQueuePositions(address stablecoin) internal view returns (uint256[] memory sortedIds, uint256 count) {
        Queue storage queue = _queues[stablecoin];
        count = queue.positionCount;

        if (count == 0) return (new uint256[](0), 0);

        // Collect all position IDs and their scores
        sortedIds = new uint256[](count);
        uint256[] memory scores = new uint256[](count);

        uint256 current = queue.head;
        uint256 index = 0;
        while (current != 0 && index < count) {
            sortedIds[index] = current;
            scores[index] = getFillScore(current);
            current = _positions[current].next;
            index++;
        }
        count = index;

        // Simple insertion sort (fine for <= 150 elements)
        for (uint256 i = 1; i < count; i++) {
            uint256 key = sortedIds[i];
            uint256 keyScore = scores[i];
            uint256 j = i;

            // Sort descending (highest score first)
            while (j > 0 && scores[j - 1] < keyScore) {
                sortedIds[j] = sortedIds[j - 1];
                scores[j] = scores[j - 1];
                j--;
            }
            sortedIds[j] = key;
            scores[j] = keyScore;
        }
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

    /// @dev Collect fee with CENTS discount
    function _collectFeeWithDiscount(address stablecoin, uint256 dlrsAmount, address user) internal returns (uint256 netOutput, uint256 fee) {
        // Check CENTS discount
        uint256 feeFreePortion = 0;
        if (address(cents) != address(0)) {
            uint256 stakePower = cents.getStakePower(user);
            if (stakePower > 0) {
                // Get remaining daily cap
                uint256 feeFreeCap = cents.getDailyFeeFreeCap(user);
                feeFreePortion = dlrsAmount > feeFreeCap ? feeFreeCap : dlrsAmount;

                // Record usage
                if (feeFreePortion > 0) {
                    cents.recordRedemption(user, feeFreePortion);
                }
            }
        }

        // Calculate actual fee (only on non-discounted portion)
        uint256 feePortion = dlrsAmount - feeFreePortion;
        fee = (feePortion * REDEMPTION_FEE_BPS) / BPS_DENOMINATOR;
        netOutput = dlrsAmount - fee;

        if (fee > 0) {
            _bank[stablecoin] += fee;
            emit FeeCollected(stablecoin, fee);
        }
    }

    /// @dev Collect fee without discount (for queue fills)
    function _collectFee(address stablecoin, uint256 dlrsAmount) internal returns (uint256 netOutput, uint256 fee) {
        fee = (dlrsAmount * REDEMPTION_FEE_BPS) / BPS_DENOMINATOR;
        netOutput = dlrsAmount - fee;

        if (fee > 0) {
            _bank[stablecoin] += fee;
            emit FeeCollected(stablecoin, fee);
        }
    }

    /// @dev Babylonian square root
    function _sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }
}
