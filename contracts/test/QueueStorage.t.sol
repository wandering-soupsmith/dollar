// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {QueueStorage} from "../src/storage/QueueStorage.sol";

/// @notice Harness exercising the QueueStorage library against the harness's own storage.
/// @dev QueueStorage is reserved scaffolding for M4 (no live logic yet); these tests pin the
///      directed-key convention, the constants, the ERC-7201 slot, and a storage round-trip.
contract QueueStorageHarness {
    function key(address o, address w) external pure returns (bytes32) {
        return QueueStorage.queueKey(o, w);
    }

    function setNextId(uint256 v) external {
        QueueStorage.layout().nextPositionId = v;
    }

    function getNextId() external view returns (uint256) {
        return QueueStorage.layout().nextPositionId;
    }

    function writePosition(uint256 id, address owner, address offerAsset, address wantAsset, uint256 amount) external {
        QueueStorage.layout().positions[id] = QueueStorage.QueuePosition({
            owner: owner,
            offerAsset: offerAsset,
            wantAsset: wantAsset,
            offerAmount: amount,
            tip: 0,
            timestamp: block.timestamp,
            next: 0,
            prev: 0
        });
    }

    function readOwner(uint256 id) external view returns (address) {
        return QueueStorage.layout().positions[id].owner;
    }

    function readOffer(uint256 id) external view returns (uint256) {
        return QueueStorage.layout().positions[id].offerAmount;
    }

    function readTip(uint256 id) external view returns (uint256) {
        return QueueStorage.layout().positions[id].tip;
    }

    function bumpQueue(bytes32 k, uint256 depth) external {
        QueueStorage.Queue storage q = QueueStorage.layout().queues[k];
        q.totalDepth += depth;
        q.positionCount += 1;
    }

    function queueDepth(bytes32 k) external view returns (uint256) {
        return QueueStorage.layout().queues[k].totalDepth;
    }

    function bumpEscrow(address asset, uint256 amount) external {
        QueueStorage.layout().totalEscrowedByAsset[asset] += amount;
    }

    function escrow(address asset) external view returns (uint256) {
        return QueueStorage.layout().totalEscrowedByAsset[asset];
    }
}

contract QueueStorageTest is Test {
    QueueStorageHarness internal h;

    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function setUp() public {
        h = new QueueStorageHarness();
    }

    /// @notice The queue key is DIRECTED: (offer->want) and (want->offer) are different queues.
    function test_queueKey_isDirectional() public {
        bytes32 ab = h.key(USDC, USDT);
        bytes32 ba = h.key(USDT, USDC);
        assertTrue(ab != ba, "directed: key(A,B) != key(B,A)");
        assertEq(ab, h.key(USDC, USDT), "deterministic");
        assertEq(ab, keccak256(abi.encode(USDC, USDT)), "matches keccak(offer,want)");
    }

    /// @notice Guards the hardcoded slot against transcription errors.
    function test_storageSlot_matchesFormula() public {
        bytes32 expected =
            keccak256(abi.encode(uint256(keccak256("dollarstore.storage.queue")) - 1)) & ~bytes32(uint256(0xff));
        assertEq(QueueStorage.QUEUE_STORAGE_LOCATION, expected, "queue slot mismatch");
    }

    function test_constants() public {
        assertEq(QueueStorage.MAX_QUEUE_POSITIONS, 150, "max positions");
        assertEq(QueueStorage.MIN_ORDER_BASE, 500e6, "min order base");
        assertEq(QueueStorage.MIN_ORDER_SCALE_POSITIONS, 25, "scale positions");
    }

    /// @notice layout() round-trips positions, queues, escrow and the id counter.
    function test_layout_roundTrip() public {
        h.setNextId(7);
        assertEq(h.getNextId(), 7, "nextId persisted");

        h.writePosition(1, address(0xBEEF), USDC, USDT, 1_000e6);
        assertEq(h.readOwner(1), address(0xBEEF), "owner");
        assertEq(h.readOffer(1), 1_000e6, "offerAmount");
        assertEq(h.readTip(1), 0, "tip reserved = 0");

        bytes32 k = h.key(USDC, USDT);
        h.bumpQueue(k, 500e6);
        assertEq(h.queueDepth(k), 500e6, "queue depth");

        h.bumpEscrow(USDC, 1_000e6);
        assertEq(h.escrow(USDC), 1_000e6, "escrow tracked per asset");
    }
}
