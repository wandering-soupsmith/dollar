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
/// @dev Everything is 1:1. No fees. No yield. No governance token.
/// @dev Security: Uses ReentrancyGuard, Pausable, SafeERC20, and follows CEI pattern.
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
    }

    /// @notice Queue state for a specific stablecoin
    struct Queue {
        uint256 head; // First position ID in queue (0 = empty)
        uint256 tail; // Last position ID in queue
        uint256 totalDepth; // Total DLRS waiting in this queue
    }

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

    event AdminTransferInitiated(address indexed currentAdmin, address indexed pendingAdmin);
    event AdminTransferCompleted(address indexed previousAdmin, address indexed newAdmin);

    // ============ Errors ============

    error OnlyAdmin();
    error OnlyPendingAdmin();

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

        // Process queue first - fill waiting positions before adding to reserves
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

        // Transfer stablecoin to user
        stablecoinReceived = amount;
        IERC20(stablecoin).safeTransfer(msg.sender, stablecoinReceived);

        emit Withdraw(msg.sender, stablecoin, stablecoinReceived, amount);
    }

    // ============ Queue Functions ============

    /// @inheritdoc IDollarStore
    function joinQueue(address stablecoin, uint256 dlrsAmount) external nonReentrant whenNotPaused returns (uint256 positionId) {
        if (dlrsAmount == 0) revert ZeroAmount();
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);

        // Check user has enough DLRS
        uint256 userBalance = dlrs.balanceOf(msg.sender);
        if (userBalance < dlrsAmount) revert InsufficientDlrsBalance(dlrsAmount, userBalance);

        // Transfer DLRS to this contract (escrow)
        // We burn from user and track internally - simpler than transferring
        dlrs.burn(msg.sender, dlrsAmount);

        // Create position
        positionId = _nextPositionId++;
        _positions[positionId] = QueuePosition({
            owner: msg.sender,
            stablecoin: stablecoin,
            amount: dlrsAmount,
            timestamp: block.timestamp,
            next: 0
        });

        // Add to queue
        Queue storage queue = _queues[stablecoin];
        if (queue.head == 0) {
            // Empty queue
            queue.head = positionId;
            queue.tail = positionId;
        } else {
            // Append to tail
            _positions[queue.tail].next = positionId;
            queue.tail = positionId;
        }
        queue.totalDepth += dlrsAmount;

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

        // Update queue depth
        _queues[position.stablecoin].totalDepth -= dlrsReturned;

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

        // Step 2: Process queue for fromStablecoin (in case anyone is waiting for it)
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
                // Queue the rest
                positionId = _createQueuePosition(toStablecoin, remaining_);
            } else {
                // Mint DLRS for the unfilled amount so user doesn't lose funds
                dlrs.mint(msg.sender, remaining_);
            }
        } else {
            // No reserves available
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

        // Check user has enough DLRS
        uint256 userBalance = dlrs.balanceOf(msg.sender);
        if (userBalance < dlrsAmount) revert InsufficientDlrsBalance(dlrsAmount, userBalance);

        uint256 available = _reserves[toStablecoin];

        if (available >= dlrsAmount) {
            // Full instant swap - burn DLRS and transfer stablecoin
            dlrs.burn(msg.sender, dlrsAmount);
            _reserves[toStablecoin] -= dlrsAmount;
            IERC20(toStablecoin).safeTransfer(msg.sender, dlrsAmount);
            received = dlrsAmount;
            positionId = 0;
        } else if (available > 0) {
            // Partial fill available
            received = available;
            dlrs.burn(msg.sender, received);
            _reserves[toStablecoin] = 0;
            IERC20(toStablecoin).safeTransfer(msg.sender, received);

            uint256 remaining = dlrsAmount - received;
            if (queueIfUnavailable) {
                // Burn remaining DLRS and queue
                dlrs.burn(msg.sender, remaining);
                positionId = _createQueuePosition(toStablecoin, remaining);
            }
            // If not queueing, user keeps their remaining DLRS
        } else {
            // No reserves available
            if (queueIfUnavailable) {
                // Burn all DLRS and queue
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

    /// @notice Add a new supported stablecoin
    /// @param stablecoin The stablecoin address to add
    function addStablecoin(address stablecoin) external onlyAdmin {
        _addStablecoin(stablecoin);
    }

    /// @notice Remove a supported stablecoin
    /// @dev Can only remove if reserves are zero (to prevent stranded funds)
    /// @param stablecoin The stablecoin address to remove
    function removeStablecoin(address stablecoin) external onlyAdmin {
        if (!_isSupported[stablecoin]) revert StablecoinNotSupported(stablecoin);
        if (_reserves[stablecoin] > 0) revert InsufficientReserves(stablecoin, 0, _reserves[stablecoin]);

        _isSupported[stablecoin] = false;

        // Remove from array
        for (uint256 i = 0; i < _stablecoins.length; i++) {
            if (_stablecoins[i] == stablecoin) {
                _stablecoins[i] = _stablecoins[_stablecoins.length - 1];
                _stablecoins.pop();
                break;
            }
        }

        emit StablecoinRemoved(stablecoin);
    }

    /// @notice Initiate admin transfer to a new address
    /// @param newAdmin The address to transfer admin rights to
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        pendingAdmin = newAdmin;
        emit AdminTransferInitiated(admin, newAdmin);
    }

    /// @notice Accept admin transfer (must be called by pending admin)
    function acceptAdmin() external {
        if (msg.sender != pendingAdmin) revert OnlyPendingAdmin();
        address previousAdmin = admin;
        admin = pendingAdmin;
        pendingAdmin = address(0);
        emit AdminTransferCompleted(previousAdmin, admin);
    }

    /// @notice Pause the contract - disables deposits, withdrawals, swaps, and queue operations
    /// @dev Only callable by admin. Emits Paused event (from Pausable).
    function pause() external onlyAdmin {
        _pause();
    }

    /// @notice Unpause the contract - re-enables all operations
    /// @dev Only callable by admin. Emits Unpaused event (from Pausable).
    function unpause() external onlyAdmin {
        _unpause();
    }

    // ============ Internal Functions ============

    /// @dev Create a queue position (used by swap functions)
    /// @param stablecoin The stablecoin to queue for
    /// @param amount The amount to queue
    /// @return positionId The new position ID
    function _createQueuePosition(address stablecoin, uint256 amount) internal returns (uint256 positionId) {
        positionId = _nextPositionId++;
        _positions[positionId] = QueuePosition({
            owner: msg.sender,
            stablecoin: stablecoin,
            amount: amount,
            timestamp: block.timestamp,
            next: 0
        });

        // Add to queue
        Queue storage queue = _queues[stablecoin];
        if (queue.head == 0) {
            queue.head = positionId;
            queue.tail = positionId;
        } else {
            _positions[queue.tail].next = positionId;
            queue.tail = positionId;
        }
        queue.totalDepth += amount;

        // Track user's positions
        _userPositions[msg.sender].push(positionId);

        emit QueueJoined(positionId, msg.sender, stablecoin, amount, block.timestamp);
    }

    /// @dev Add a stablecoin to the supported list
    /// @param stablecoin The stablecoin address to add
    function _addStablecoin(address stablecoin) internal {
        if (stablecoin == address(0)) revert ZeroAddress();
        if (_isSupported[stablecoin]) revert StablecoinAlreadySupported(stablecoin);

        _isSupported[stablecoin] = true;
        _stablecoins.push(stablecoin);

        emit StablecoinAdded(stablecoin);
    }

    /// @dev Process the queue for a stablecoin, filling positions FIFO
    /// @param stablecoin The stablecoin being deposited
    /// @param amount The amount available to fill positions
    /// @return remaining The amount not used to fill positions (goes to reserves)
    function _processQueue(address stablecoin, uint256 amount) internal returns (uint256 remaining) {
        Queue storage queue = _queues[stablecoin];
        remaining = amount;

        // Process positions from head until amount exhausted or queue empty
        while (remaining > 0 && queue.head != 0) {
            uint256 positionId = queue.head;
            QueuePosition storage position = _positions[positionId];

            uint256 fillAmount;
            if (position.amount <= remaining) {
                // Full fill
                fillAmount = position.amount;
                remaining -= fillAmount;

                // Move head to next position
                queue.head = position.next;
                if (queue.head == 0) {
                    queue.tail = 0; // Queue is now empty
                }

                // Transfer stablecoin to position owner
                IERC20(stablecoin).safeTransfer(position.owner, fillAmount);

                emit QueueFilled(positionId, position.owner, stablecoin, fillAmount, 0);

                // Remove from user's position list
                _removeUserPosition(position.owner, positionId);

                // Clear position
                delete _positions[positionId];
            } else {
                // Partial fill
                fillAmount = remaining;
                position.amount -= fillAmount;
                remaining = 0;

                // Transfer partial amount to position owner
                IERC20(stablecoin).safeTransfer(position.owner, fillAmount);

                emit QueueFilled(positionId, position.owner, stablecoin, fillAmount, position.amount);
            }

            queue.totalDepth -= fillAmount;
        }
    }

    /// @dev Remove a position from the queue linked list
    /// @param positionId The position ID to remove
    /// @param stablecoin The stablecoin queue to remove from
    function _removeFromQueue(uint256 positionId, address stablecoin) internal {
        Queue storage queue = _queues[stablecoin];

        if (queue.head == positionId) {
            // Removing head
            queue.head = _positions[positionId].next;
            if (queue.head == 0) {
                queue.tail = 0;
            }
        } else {
            // Find previous position
            uint256 current = queue.head;
            while (current != 0 && _positions[current].next != positionId) {
                current = _positions[current].next;
            }

            if (current != 0) {
                _positions[current].next = _positions[positionId].next;
                if (queue.tail == positionId) {
                    queue.tail = current;
                }
            }
        }
    }

    /// @dev Remove a position ID from a user's position list
    /// @param user The user address whose list to modify
    /// @param positionId The position ID to remove
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
