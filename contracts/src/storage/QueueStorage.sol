// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title QueueStorage - ERC-7201 namespaced storage for the directed FIFO queue module
/// @notice Holds the directed-queue bookkeeping (positions, linked lists, escrow totals).
/// @dev Reserved layout for M4 (queue logic). Declared early so the storage layout is fixed
///      and the difference from the old single-asset v2 queue is explicit.
///
/// ---- What changed vs the v2 queue (key differences) -------------------------------------
///  v2: queue keyed by ONE asset (the stablecoin you wait for); a position escrowed *DLRS*.
///        struct QueuePosition { owner, stablecoin, amount(DLRS), timestamp, next, prev }
///        mapping(address => Queue) _queues;            // key = wanted stablecoin
///  v3: queue keyed by a DIRECTED PAIR (offerAsset -> wantAsset); a position escrows the
///      user's actual *offerAsset* (NOT DLRS). DLRS is never a public queue offer asset.
///        struct QueuePosition { owner, offerAsset, wantAsset, offerAmount, tip, ... }
///        mapping(bytes32 => Queue) queues;             // key = keccak256(offerAsset, wantAsset)
///      Plus `totalEscrowedByAsset` for the 3-bucket solvency accounting, and a reserved
///      `tip` field for the deferred priority feature (U1).
/// -----------------------------------------------------------------------------------------
/// @custom:security-contact admin@dollarstore.world
library QueueStorage {
    // ============ Constants (queue behaviour shape; applied by M4 logic) ============

    /// @notice Max positions allowed per directed queue.
    uint256 internal constant MAX_QUEUE_POSITIONS = 150;
    /// @notice Base minimum queued order size, in normalized 6-decimal units (500).
    /// @dev v2 used 100e6; v3 raises the base to 500e6.
    uint256 internal constant MIN_ORDER_BASE = 500e6;
    /// @notice Minimum order size grows 10x every this many positions.
    uint256 internal constant MIN_ORDER_SCALE_POSITIONS = 25;

    // ============ Structs ============

    /// @notice Per-directed-queue head/tail and aggregate counters.
    struct Queue {
        /// @notice First position id in the queue (0 = empty).
        uint256 head;
        /// @notice Last position id in the queue (0 = empty).
        uint256 tail;
        /// @notice Number of positions currently in this queue.
        uint256 positionCount;
        /// @notice Sum of `offerAmount` across positions (normalized 6dp).
        uint256 totalDepth;
    }

    /// @notice A single position in a directed FIFO queue.
    /// @dev Escrows the user's `offerAsset` (normalized units), NOT DLRS. Filled in FIFO order
    ///      (and, once U1 ships, by `tip` rate then FIFO). Linked-list pointers enable O(1) removal.
    struct QueuePosition {
        /// @notice Owner of the position.
        address owner;
        /// @notice Asset the user is offering (escrowed by the protocol).
        address offerAsset;
        /// @notice Asset the user wants to receive.
        address wantAsset;
        /// @notice Remaining escrowed offerAsset (normalized 6dp); decreases on partial fills.
        uint256 offerAmount;
        /// @notice RESERVED for U1 (priority queue). MUST be 0 until TIP logic ships in U1;
        ///         M4 enforces tip == 0. Reserved now so enabling tips later is purely additive.
        uint256 tip;
        /// @notice Creation time; FIFO tiebreak.
        uint256 timestamp;
        /// @notice Next position id in the queue (0 = end).
        uint256 next;
        /// @notice Previous position id in the queue (0 = head).
        uint256 prev;
    }

    // ============ Namespaced Layout ============

    /// @custom:storage-location erc7201:dollarstore.storage.queue
    struct Layout {
        /// @notice Monotonic id generator. Starts at 1 so 0 can mean "no position".
        uint256 nextPositionId;
        /// @notice Directed queue state, keyed by queueKey(offerAsset, wantAsset).
        mapping(bytes32 => Queue) queues;
        /// @notice Position data, keyed by position id.
        mapping(uint256 => QueuePosition) positions;
        /// @notice Position ids owned by each user.
        mapping(address => uint256[]) userPositions;
        /// @notice Total escrowed amount per asset (normalized 6dp). Distinguishes queue escrow
        ///         from active pool reserves for the solvency check in M5+.
        mapping(address => uint256) totalEscrowedByAsset;
    }

    /// @notice Precomputed ERC-7201 storage slot for namespace "dollarstore.storage.queue".
    /// @dev keccak256(abi.encode(uint256(keccak256("dollarstore.storage.queue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant QUEUE_STORAGE_LOCATION =
        0xfbabd0aa65a6bff5e4ec944816eb089ff547bf5b8c1c45635a7a10ce2c5cc500;

    /// @notice Returns a storage pointer to the queue layout at the namespaced slot.
    function layout() internal pure returns (Layout storage $) {
        assembly {
            $.slot := QUEUE_STORAGE_LOCATION
        }
    }

    /// @notice Canonical key for a directed queue.
    /// @param offerAsset The asset the user offers (escrowed).
    /// @param wantAsset The asset the user wants.
    /// @return The keccak256 key used to index `queues`.
    function queueKey(address offerAsset, address wantAsset) internal pure returns (bytes32) {
        return keccak256(abi.encode(offerAsset, wantAsset));
    }
}
