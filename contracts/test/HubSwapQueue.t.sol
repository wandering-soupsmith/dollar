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
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockAggregatorV3 internal feed; // $1 mock oracle

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (governor, guardian));
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

    // ============ FIFO availability + processQueue ============

    function test_fifoRule_newSwapCannotSkipQueue_thenProcess() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues (no reserves)
        _deposit(bob, usdt, 500e6); // reserves appear but do NOT auto-fill the queue

        // Carol's same-direction swap cannot take the reserves — they belong to Alice's queue.
        (uint256 filled, uint256 queued) = _swap(carol, usdc, usdt, 500e6, 0);
        assertEq(filled, 0, "carol cannot skip FIFO");
        assertEq(queued, 500e6, "carol queued behind alice");

        // The permissionless fallback fills Alice (head) from reserves.
        vm.prank(carol);
        (uint256 processed, uint256 amountFilled) = store.processQueue(address(usdc), address(usdt), 10);
        assertEq(processed, 1, "one position touched");
        assertEq(amountFilled, 500e6, "filled from reserves");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 500e6, "alice got 500 USDT");
        assertEq(store.getReserve(0, address(usdt)), 0, "reserves drained");
        // Alice reduced to 500, Carol still 500 => total 1000.
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 1_000e6, "remaining depth");
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
