// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M4: directed swaps, exact-opposite matching, FIFO queues, cancel, processQueue.
/// @dev Both assets use 6 decimals so normalized units == native (scaling 1), keeping asserts clean.
contract HubSwapQueueTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockAggregatorV3 internal feed; // $1 mock oracle

    // Mirror of IDollarStore.QueueFilled so tests can assert it via expectEmit.
    event QueueFilled(uint256 indexed positionId, address indexed owner, uint256 filled, uint256 remaining);

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);

        feed = new MockAggregatorV3(8, 1e8); // $1
        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        vm.stopPrank();

        address[3] memory users = [alice, bob, carol];
        for (uint256 i; i < 3; i++) {
            usdc.mint(users[i], 1_000_000e6);
            usdt.mint(users[i], 1_000_000e6);
        }
    }

    function _deposit(address who, MockERC20 token, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(store), amt);
        store.deposit(0, address(token), amt, block.timestamp);
        vm.stopPrank();
    }

    function _swap(address who, MockERC20 offer, MockERC20 want, uint256 amt, uint256 minOut)
        internal
        returns (uint256 filled, uint256 queued)
    {
        vm.startPrank(who);
        offer.approve(address(store), amt);
        (filled, queued) = store.swap(address(offer), address(want), amt, minOut, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Reserve fills ============

    function test_swap_fillsFromReserves() public {
        _deposit(bob, usdt, 1_000e6); // creates USDT reserves

        (uint256 filled, uint256 queued) = _swap(alice, usdc, usdt, 1_000e6, 0);

        assertEq(filled, 1_000e6, "filled");
        assertEq(queued, 0, "queued");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 1_000e6, "alice got USDT");
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 1_000e6, "alice paid USDC");
        assertEq(store.getReserve(0, address(usdt)), 0, "USDT reserve drained");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "USDC reserve grew");
    }

    // ============ Queue remainder ============

    function test_swap_queuesWhenNoLiquidity() public {
        (uint256 filled, uint256 queued) = _swap(alice, usdc, usdt, 1_000e6, 0);

        assertEq(filled, 0, "nothing filled");
        assertEq(queued, 1_000e6, "all queued");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 1_000e6, "queue depth");
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 1_000e6, "USDC escrowed");
        assertEq(store.getUserQueuePositions(alice).length, 1, "one position");
    }

    // ============ Exact-opposite matching ============

    function test_swap_exactOppositeMatch() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues USDC->USDT

        (uint256 filled, uint256 queued) = _swap(bob, usdt, usdc, 1_000e6, 0); // bob matches

        assertEq(filled, 1_000e6, "bob fully filled by match");
        assertEq(queued, 0, "nothing queued");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue emptied");
        // alice received USDT from bob's offer; bob received USDC from alice's escrow.
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 1_000e6, "alice got USDT");
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 1_000e6, "bob got USDC");
        assertEq(usdt.balanceOf(bob), 1_000_000e6 - 1_000e6, "bob paid USDT");
        assertEq(store.getUserQueuePositions(alice).length, 0, "alice position gone");
    }

    function test_swap_partialFillThenQueue() public {
        _deposit(bob, usdt, 400e6);

        (uint256 filled, uint256 queued) = _swap(alice, usdc, usdt, 1_000e6, 0);

        assertEq(filled, 400e6, "partial from reserves");
        assertEq(queued, 600e6, "remainder queued");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 400e6, "got partial USDT");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 600e6, "queue depth");
    }

    // ============ FIFO availability + inline settle (M-01) ============

    /// @notice M-01: a same-direction swap must not jump ahead of a queued position, but it also must
    ///         not leave reserves stranded behind it. Before touching reserves the swap settles the
    ///         queue head (Alice) from those reserves in FIFO order. Alice is only partially cleared,
    ///         so the queue stays non-empty and Carol still cannot take reserves — she queues behind.
    function test_fifoRule_swapSettlesQueueHeadFromReserves() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues (no reserves)
        _deposit(bob, usdt, 500e6); // reserves appear behind alice's queued position

        (uint256 filled, uint256 queued) = _swap(carol, usdc, usdt, 500e6, 0);
        assertEq(filled, 0, "carol cannot skip FIFO");
        assertEq(queued, 500e6, "carol queued behind alice");

        // M-01: the reserves were paid to Alice (head) inline by Carol's swap, not stranded.
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 500e6, "alice settled from reserves by the swap");
        assertEq(store.getReserve(0, address(usdt)), 0, "reserves consumed by inline settle");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "alice's escrow moved into reserves");
        // Alice reduced 1000->500, Carol 500 => total 1000.
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 1_000e6, "remaining depth");
    }

    /// @notice M-01 (audit scenario): a below-minimum first queue position must not strand reserve
    ///         fills. Before the fix the dust head kept `positionCount != 0`, so no swap could ever
    ///         pull from reserves on that route (liveness DoS, no fund loss). Now a swap settles the
    ///         dust head from reserves first, and since the queue then empties, fills itself too.
    function test_m01_dustFirstPosition_doesNotStrandReserves() public {
        // Alice opens a dust first position (below the 500 minimum, allowed only as the first).
        (, uint256 aliceQueued) = _swap(alice, usdc, usdt, 1e6, 0);
        assertEq(aliceQueued, 1e6, "dust first position queued");

        _deposit(bob, usdt, 1_000e6); // reserves appear behind the dust head

        // Carol's swap clears the dust head from reserves, then fills itself from the remainder.
        (uint256 filled, uint256 queued) = _swap(carol, usdc, usdt, 500e6, 0);
        assertEq(filled, 500e6, "carol fills from reserves once the dust head is cleared");
        assertEq(queued, 0, "nothing queued");

        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 1e6, "alice's dust settled from reserves");
        assertEq(usdt.balanceOf(carol), 1_000_000e6 + 500e6, "carol filled from reserves");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue fully cleared");
        // reserves[usdt] = 1000 - 1 (alice) - 500 (carol) = 499.
        assertEq(store.getReserve(0, address(usdt)), 499e6, "remaining reserves after inline settle + fill");
    }

    /// @notice The permissionless processQueue still settles a queued head from reserves when no swap
    ///         has triggered the inline path (e.g. reserves arrived via a plain deposit).
    function test_processQueue_settlesFromReserves() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues (no reserves)
        _deposit(bob, usdt, 500e6); // reserves appear via deposit, no swap

        vm.prank(carol);
        (uint256 processed, uint256 amountFilled) = store.processQueue(address(usdc), address(usdt), 10);
        assertEq(processed, 1, "one position touched");
        assertEq(amountFilled, 500e6, "filled from reserves");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 500e6, "alice got 500 USDT");
        assertEq(store.getReserve(0, address(usdt)), 0, "reserves drained");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 500e6, "alice reduced to 500");
    }

    /// @notice M-01 bound: the inline settle is capped at MAX_INLINE_SETTLE (8) positions per swap so
    ///         one call cannot iterate an unbounded queue. With 9 queued positions and ample reserves,
    ///         a single swap settles exactly 8; the queue stays non-empty (9th survives), so the swapper
    ///         does NOT self-fill and queues its remainder. FIFO order is preserved and no reserves are
    ///         lost — the tail is settled by the next swap or a permissionless processQueue call.
    function test_m01_deepQueue_settlesOnlyUpToCap() public {
        // Queue 9 same-direction positions (usdc -> usdt), 500 each (>= the 500 minimum). No reserves.
        for (uint256 i; i < 9; i++) {
            address u = makeAddr(string(abi.encodePacked("q", i)));
            usdc.mint(u, 500e6);
            vm.startPrank(u);
            usdc.approve(address(store), 500e6);
            store.swap(address(usdc), address(usdt), 500e6, 0, 0, block.timestamp);
            vm.stopPrank();
        }
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 9 * 500e6, "9 positions queued");

        _deposit(bob, usdt, 10_000e6); // enough reserves to fill all 9

        // A single swap settles only 8 (MAX_INLINE_SETTLE); the 9th remains, so the swapper queues.
        (uint256 filled, uint256 queued) = _swap(carol, usdc, usdt, 500e6, 0);
        assertEq(filled, 0, "swapper does not self-fill: queue still non-empty after the capped settle");
        assertEq(queued, 500e6, "swapper queues behind the un-settled tail");

        // Exactly 8 positions paid from reserves; the 9th (500) + the swapper (500) remain queued.
        assertEq(store.getReserve(0, address(usdt)), 10_000e6 - 8 * 500e6, "only 8 positions settled this call");
        assertEq(store.getReserve(0, address(usdc)), 8 * 500e6, "settled positions' escrow moved to reserves");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 2 * 500e6, "9th + swapper remain queued");
    }

    /// @notice M-01 for the router path: swapExactInput must also reach reserves stranded behind a dust
    ///         head. It settles the dust head first, then fills itself fully. Before the fix the dust
    ///         head kept positionCount != 0, so this would have reverted InsufficientLiquidity.
    function test_m01_swapExactInput_reachesLiquidityBehindDustHead() public {
        (, uint256 dust) = _swap(alice, usdc, usdt, 1e6, 0); // below-min dust first position
        assertEq(dust, 1e6, "dust head queued");

        _deposit(bob, usdt, 1_000e6); // reserves behind the dust head

        vm.startPrank(carol);
        usdc.approve(address(store), 500e6);
        uint256 out = store.swapExactInput(address(usdc), address(usdt), 500e6, 0, block.timestamp);
        vm.stopPrank();

        assertEq(out, 500e6, "swapExactInput fills fully from reserves behind the dust head");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 1e6, "dust head settled from reserves");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue cleared");
    }

    // ============ minAmountOut exact boundary (acceptance S3-iii) ============

    /// @notice S3 exact boundary: minAmountOut == the instantly-available fill must PROCEED and queue
    ///         the remainder. The gate is `filled < minAmountOut`, so equality passes. Complements
    ///         test_swap_revertsMinAmountNotMet (the `filled < minAmountOut` revert side).
    function test_swap_minAmountOut_exactBoundary_proceeds() public {
        _deposit(bob, usdt, 400e6); // only 400 instantly available in reserves

        // Demand exactly 400 instant (== available); 600 queues. Must not revert.
        (uint256 filled, uint256 queued) = _swap(alice, usdc, usdt, 1_000e6, 400e6);

        assertEq(filled, 400e6, "boundary: filled == minAmountOut proceeds");
        assertEq(queued, 600e6, "remainder queued");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 400e6, "received the boundary fill");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 600e6, "remainder in queue");
    }

    // ============ QueueFilled event assertions (acceptance S2) ============

    /// @notice S2a: an exact-opposite swap that fully consumes a queued position must emit
    ///         QueueFilled(positionId, owner, filled, remaining == 0).
    function test_swap_exactOppositeMatch_emitsQueueFilled() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues USDC->USDT
        uint256 aliceId = store.getUserQueuePositions(alice)[0];

        // Inline bob's approve BEFORE expectEmit so the asserted event is QueueFilled, not Approval.
        vm.startPrank(bob);
        usdt.approve(address(store), 1_000e6);
        vm.expectEmit(true, true, false, true, address(store));
        emit QueueFilled(aliceId, alice, 1_000e6, 0);
        store.swap(address(usdt), address(usdc), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    /// @notice S2b: processQueue settling a queued head from reserves must emit QueueFilled with the
    ///         partial amount and the non-zero remaining (500 of 1000 filled, 500 left).
    function test_processQueue_emitsQueueFilled() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues (no reserves yet)
        uint256 aliceId = store.getUserQueuePositions(alice)[0];
        _deposit(bob, usdt, 500e6); // reserves appear; processQueue settles FIFO from them

        vm.expectEmit(true, true, false, true, address(store));
        emit QueueFilled(aliceId, alice, 500e6, 500e6);
        vm.prank(carol);
        store.processQueue(address(usdc), address(usdt), 10);
    }

    // ============ swapExactInput ============

    function test_swapExactInput_success() public {
        _deposit(bob, usdt, 1_000e6);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        uint256 out = store.swapExactInput(address(usdc), address(usdt), 1_000e6, 0, block.timestamp);
        vm.stopPrank();
        assertEq(out, 1_000e6, "full output");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 1_000e6, "received");
    }

    function test_swapExactInput_revertsInsufficient() public {
        _deposit(bob, usdt, 500e6);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientLiquidity.selector, uint256(500e6), uint256(1_000e6))
        );
        store.swapExactInput(address(usdc), address(usdt), 1_000e6, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Reverts ============

    function test_swap_revertsTipNotZero() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(IDollarStore.TipNotEnabled.selector);
        store.swap(address(usdc), address(usdt), 1_000e6, 0, 1, block.timestamp);
        vm.stopPrank();
    }

    function test_swap_revertsSameAsset() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(IDollarStore.SameAsset.selector);
        store.swap(address(usdc), address(usdc), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_swap_revertsMinAmountNotMet() public {
        _deposit(bob, usdt, 400e6);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.MinAmountNotMet.selector, uint256(400e6), uint256(800e6)));
        store.swap(address(usdc), address(usdt), 1_000e6, 800e6, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ cancelQueue ============

    function test_cancelQueue_returnsEscrow() public {
        _swap(alice, usdc, usdt, 1_000e6, 0);
        uint256 id = store.getUserQueuePositions(alice)[0];

        vm.prank(alice);
        store.cancelQueue(id);

        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue empty");
        assertEq(usdc.balanceOf(alice), 1_000_000e6, "USDC returned");
        assertEq(store.getUserQueuePositions(alice).length, 0, "no positions");
    }

    function test_cancelQueue_revertsNotOwner() public {
        _swap(alice, usdc, usdt, 1_000e6, 0);
        uint256 id = store.getUserQueuePositions(alice)[0];
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.NotPositionOwner.selector, id, bob));
        store.cancelQueue(id);
    }

    function test_cancelQueue_revertsNotFound() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.QueuePositionNotFound.selector, uint256(999)));
        store.cancelQueue(999);
    }

    // ============ Minimum order size (with first-position exception) ============

    function test_belowMinFirstPosition_allowedThenReverts() public {
        // First position in an empty queue may be below the 500 minimum (Q2 exception).
        (, uint256 queued) = _swap(alice, usdc, usdt, 300e6, 0);
        assertEq(queued, 300e6, "below-min first position allowed");

        // A second position must meet the minimum.
        vm.startPrank(bob);
        usdc.approve(address(store), 300e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.OrderTooSmall.selector, uint256(300e6), uint256(500e6)));
        store.swap(address(usdc), address(usdt), 300e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Invariants / quote ============

    function test_dlrsConservation_acrossSwaps() public {
        _deposit(bob, usdt, 1_000e6);
        _deposit(alice, usdc, 1_000e6);
        // carol swaps: reserve-neutral, no DLRS change.
        _swap(carol, usdc, usdt, 500e6, 0);

        uint256 reserveSum = store.getReserve(0, address(usdc)) + store.getReserve(0, address(usdt));
        assertEq(dlrs.totalSupply(), reserveSum, "DLRS supply == sum of reserves");
        assertEq(dlrs.totalSupply(), 2_000e6, "unchanged by swap");
    }

    function test_getSwapQuote() public {
        _deposit(bob, usdt, 1_000e6);
        assertEq(store.getSwapQuote(address(usdc), address(usdt), 500e6), 500e6, "fillable from reserves");

        // With a non-empty same-direction queue, instant quote is 0 (FIFO).
        _swap(carol, usdc, usdt, 2_000e6, 0); // partially fills 1000, queues 1000 -> same-dir queue non-empty
        assertEq(store.getSwapQuote(address(usdc), address(usdt), 500e6), 0, "FIFO blocks instant quote");
    }
}
