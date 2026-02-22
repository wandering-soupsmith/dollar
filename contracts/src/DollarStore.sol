// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "./interfaces/IDollarStore.sol";
import "./DLRS.sol";

/// @title DollarStore - A minimalist stablecoin aggregator and swap facility
/// @notice Deposit any supported stablecoin, receive DLRS. Redeem DLRS for any available stablecoin.
/// @dev Zero-fee, pure FIFO queue ordering.
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

    // ============ Events ============

    /// @notice Emitted when admin initiates a two-step admin transfer
    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    /// @notice Emitted when the pending admin accepts the admin role
    event AdminTransferCompleted(address indexed previousAdmin, address indexed newAdmin);

    // ============ Errors ============

    error OnlyAdmin();
    error OnlyPendingAdmin();
    error QueueFull(address stablecoin, uint256 currentCount);
    error OrderTooSmall(uint256 provided, uint256 minimum);

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

    // ============ Core Functions ============

    /// @inheritdoc IDollarStore
    function deposit(address stablecoin, uint256 amount) external nonReentrant whenNotPaused returns (uint256 dlrsMinted) {
        if (amount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

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
    function withdraw(address stablecoin, uint256 amount) external nonReentrant whenNotPaused returns (uint256 stablecoinReceived) {
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

    // ============ Aggregator Functions ============

    /// @notice Get expected output for a stablecoin swap (view function for aggregators)
    /// @dev Returns amountIn if reserves are sufficient, 0 otherwise. Never returns partial amounts.
    /// @param fromStablecoin The input stablecoin
    /// @param toStablecoin The output stablecoin
    /// @param amountIn Amount of input stablecoin
    /// @return amountOut Amount of output stablecoin (amountIn if fillable, 0 if not)
    function getSwapQuote(
        address fromStablecoin,
        address toStablecoin,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
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
    /// @param minAmountOut Minimum acceptable output (slippage protection, typically same as amountIn for 1:1)
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
        if (!_isSupported[fromStablecoin]) revert StablecoinNotSupported(fromStablecoin);
        if (!_isSupported[toStablecoin]) revert StablecoinNotSupported(toStablecoin);
        if (fromStablecoin == toStablecoin) revert SameStablecoin();

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
    /// @param stablecoin Address of the ERC-20 stablecoin to add
    function addStablecoin(address stablecoin) external onlyAdmin {
        _addStablecoin(stablecoin);
    }

    /// @notice Remove a supported stablecoin from the protocol
    /// @dev Reverts if the stablecoin still has reserves
    /// @param stablecoin Address of the stablecoin to remove
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

    /// @notice Initiate a two-step admin transfer
    /// @param newAdmin Address of the proposed new admin
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(admin, newAdmin);
    }

    /// @notice Accept the admin role (must be called by the pending admin)
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert OnlyPendingAdmin();
        address previousAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit AdminTransferCompleted(previousAdmin, admin);
    }

    /// @notice Pause all protocol operations
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpause all protocol operations
    function unpause() external onlyAdmin {
        _unpause();
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
    function _processQueue(address stablecoin, uint256 amount) internal returns (uint256 remaining) {
        Queue storage queue = _queues[stablecoin];
        remaining = amount;

        if (queue.head == 0) return remaining;

        uint256 current = queue.head;

        while (current != 0 && remaining > 0) {
            QueuePosition storage position = _positions[current];
            address positionOwner = position.owner;
            uint256 next = position.next;

            if (position.amount <= remaining) {
                // Full fill
                uint256 fillAmount = position.amount;
                remaining -= fillAmount;

                // Transfer stablecoin to position owner (1:1, no fee)
                IERC20(stablecoin).safeTransfer(positionOwner, fillAmount);

                emit QueueFilled(current, positionOwner, stablecoin, fillAmount, 0);

                // Remove from queue
                _removeFromQueue(current, stablecoin);
                queue.totalDepth -= fillAmount;
                queue.positionCount--;
                _removeUserPosition(positionOwner, current);
                delete _positions[current];
            } else {
                // Partial fill
                uint256 fillAmount = remaining;
                position.amount -= fillAmount;
                remaining = 0;

                // Transfer partial amount (1:1, no fee)
                IERC20(stablecoin).safeTransfer(positionOwner, fillAmount);

                emit QueueFilled(current, positionOwner, stablecoin, fillAmount, position.amount);

                queue.totalDepth -= fillAmount;
            }

            current = next;
        }

        return remaining;
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
}
