// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {QueueStorage} from "../storage/QueueStorage.sol";

/// @title QueueLib - Directed FIFO queue mechanics (linked-list only)
/// @notice Pure bookkeeping for the directed queues: enqueue at tail, reduce (partial fill),
///         remove (full fill / cancel), and the escalating minimum order size. Keeps the queue
///         counters, the doubly-linked list, `totalEscrowedByAsset`, and `userPositions` in sync.
/// @dev Does NOT move tokens, validate routes, or touch reserves — the contract orchestrates those.
///      `totalEscrowedByAsset[asset]` always equals the sum of `offerAmount` over live positions
///      whose `offerAsset == asset`, because it is updated atomically here.
/// @custom:security-contact admin@dollarstore.world
library QueueLib {
    /// @notice Minimum queued order size given `positionCount` existing positions in the queue.
    /// @dev Grows 10x every MIN_ORDER_SCALE_POSITIONS positions: 500, 5_000, 50_000, ...
    function minimumOrderSize(uint256 positionCount) internal pure returns (uint256) {
        uint256 tier = positionCount / QueueStorage.MIN_ORDER_SCALE_POSITIONS;
        uint256 mult = 1;
        for (uint256 i = 0; i < tier; i++) {
            mult *= 10;
        }
        return QueueStorage.MIN_ORDER_BASE * mult;
    }

    /// @notice Append a new position at the tail of the (offerAsset -> wantAsset) queue.
    /// @return positionId The id of the newly created position.
    function enqueue(
        QueueStorage.Layout storage qs,
        address offerAsset,
        address wantAsset,
        address owner,
        uint256 amount
    ) internal returns (uint256 positionId) {
        bytes32 key = QueueStorage.queueKey(offerAsset, wantAsset);
        QueueStorage.Queue storage q = qs.queues[key];

        positionId = ++qs.nextPositionId; // first id == 1 (0 means "no position")
        QueueStorage.QueuePosition storage p = qs.positions[positionId];
        p.owner = owner;
        p.offerAsset = offerAsset;
        p.wantAsset = wantAsset;
        p.offerAmount = amount;
        p.tip = 0; // reserved; enabling tips is a post-launch upgrade (U1)
        p.timestamp = block.timestamp;
        p.prev = q.tail;
        p.next = 0;

        if (q.tail == 0) {
            q.head = positionId;
        } else {
            qs.positions[q.tail].next = positionId;
        }
        q.tail = positionId;
        q.positionCount += 1;
        q.totalDepth += amount;

        qs.totalEscrowedByAsset[offerAsset] += amount;
        qs.userPositions[owner].push(positionId);
    }

    /// @notice Reduce a live position's amount by `delta` (partial fill). Requires delta < amount.
    function reduce(QueueStorage.Layout storage qs, uint256 positionId, uint256 delta) internal {
        QueueStorage.QueuePosition storage p = qs.positions[positionId];
        bytes32 key = QueueStorage.queueKey(p.offerAsset, p.wantAsset);
        p.offerAmount -= delta;
        qs.queues[key].totalDepth -= delta;
        qs.totalEscrowedByAsset[p.offerAsset] -= delta;
    }

    /// @notice Remove a position entirely (full fill or cancel), unlinking it from its queue.
    /// @return owner The position owner.
    /// @return offerAsset The escrowed asset.
    /// @return amount The remaining amount that was removed (still escrowed at call time).
    function remove(QueueStorage.Layout storage qs, uint256 positionId)
        internal
        returns (address owner, address offerAsset, uint256 amount)
    {
        QueueStorage.QueuePosition storage p = qs.positions[positionId];
        owner = p.owner;
        offerAsset = p.offerAsset;
        amount = p.offerAmount;
        address wantAsset = p.wantAsset;

        bytes32 key = QueueStorage.queueKey(offerAsset, wantAsset);
        QueueStorage.Queue storage q = qs.queues[key];

        // Unlink from the doubly-linked list.
        if (p.prev == 0) {
            q.head = p.next;
        } else {
            qs.positions[p.prev].next = p.next;
        }
        if (p.next == 0) {
            q.tail = p.prev;
        } else {
            qs.positions[p.next].prev = p.prev;
        }

        q.positionCount -= 1;
        q.totalDepth -= amount;
        qs.totalEscrowedByAsset[offerAsset] -= amount;

        _removeUserPosition(qs, owner, positionId);
        delete qs.positions[positionId];
    }

    /// @dev Swap-and-pop a position id out of the owner's position array.
    function _removeUserPosition(QueueStorage.Layout storage qs, address owner, uint256 positionId) private {
        uint256[] storage arr = qs.userPositions[owner];
        uint256 len = arr.length;
        for (uint256 i = 0; i < len; i++) {
            if (arr[i] == positionId) {
                arr[i] = arr[len - 1];
                arr.pop();
                break;
            }
        }
    }
}
