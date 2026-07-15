// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockBlacklistERC20} from "./mocks/MockBlacklistERC20.sol";
import {MockReentrantERC20} from "./mocks/MockReentrantERC20.sol";
import {MockFeeOnTransferERC20} from "./mocks/MockFeeOnTransferERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M4 edge coverage: failed-transfer (blacklist) fallbacks, linked-list surgery on
///         middle/multi removals, partial opposite-queue consumption, multi-position matching,
///         userPositions swap-and-pop, reentrancy blocking, cross-decimal swaps, and views.
/// @dev Complements HubSwapQueue.t.sol (happy paths). Assets use MockBlacklistERC20 so any owner
///      can be frozen mid-flow to trigger the escrow -> DLRS-claim fallbacks. usdc/usdt are 6dp
///      (units == native); dai is 18dp for the cross-decimal cases.
contract HubSwapFallbackTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    MockBlacklistERC20 internal usdc; // 6dp
    MockBlacklistERC20 internal usdt; // 6dp
    MockBlacklistERC20 internal dai; //  18dp
    MockAggregatorV3 internal feed; // $1 mock oracle

    event QueuePositionRefunded(uint256 indexed positionId, address indexed owner, address offerAsset, uint256 units);

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockBlacklistERC20("USD Coin", "USDC", 6);
        usdt = new MockBlacklistERC20("Tether", "USDT", 6);
        dai = new MockBlacklistERC20("Dai", "DAI", 18);
        feed = new MockAggregatorV3(8, 1e8); // $1

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        store.addHubAsset(address(dai), address(feed));
        vm.stopPrank();

        address[3] memory users = [alice, bob, carol];
        for (uint256 i; i < 3; i++) {
            usdc.mint(users[i], 1_000_000e6);
            usdt.mint(users[i], 1_000_000e6);
            dai.mint(users[i], 1_000_000e18);
        }
    }

    // ============ Helpers ============

    function _deposit(address who, MockBlacklistERC20 token, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(store), amt);
        store.deposit(0, address(token), amt, block.timestamp);
        vm.stopPrank();
    }

    function _swap(address who, MockBlacklistERC20 offer, MockBlacklistERC20 want, uint256 amt, uint256 minOut)
        internal
        returns (uint256 filled, uint256 queued)
    {
        vm.startPrank(who);
        offer.approve(address(store), amt);
        (filled, queued) = store.swap(address(offer), address(want), amt, minOut, 0, block.timestamp);
        vm.stopPrank();
    }

    function _reserveSum() internal view returns (uint256) {
        return
            store.getReserve(0, address(usdc)) + store.getReserve(0, address(usdt)) + store.getReserve(0, address(dai));
    }

    // ============ Failed-transfer fallbacks (escrow -> DLRS claim) ============

    /// @notice _fillDirected: paying a matched opposite-queue owner fails -> eject + mint DLRS,
    ///         and the swapper still gets filled from the reserves the ejection created.
    function test_swap_matchFallback_whenOppositeOwnerBlacklisted() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues USDC->USDT (escrows 1000 USDC)
        uint256 aliceId = store.getUserQueuePositions(alice)[0];

        usdt.setBlocked(alice, true); // alice can no longer receive USDT

        // bob swaps USDT->USDC: the protocol tries to pay alice in USDT (bob's offer) and fails.
        // Inline the approve BEFORE expectEmit so the next event is QueuePositionRefunded, not the
        // Approval that the _swap() helper would emit first.
        vm.startPrank(bob);
        usdt.approve(address(store), 1_000e6);
        vm.expectEmit(true, true, false, true, address(store));
        emit QueuePositionRefunded(aliceId, alice, address(usdc), 1_000e6);
        (uint256 filled, uint256 queued) = store.swap(address(usdt), address(usdc), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();

        // Alice's escrow became a DLRS claim; bob still filled fully from the freed reserves.
        assertEq(filled, 1_000e6, "bob filled from freed reserves");
        assertEq(queued, 0, "bob nothing queued");
        assertEq(usdt.balanceOf(alice), 1_000_000e6, "alice received no USDT (blocked)");
        assertEq(dlrs.balanceOf(alice), 1_000e6, "alice got a DLRS claim instead");
        assertEq(store.getUserQueuePositions(alice).length, 0, "alice position ejected");
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 1_000e6, "bob got USDC");
        assertEq(dlrs.totalSupply(), _reserveSum(), "invariant: DLRS supply == sum reserves");
    }

    /// @notice cancelQueue: refunding the owner's escrow fails -> escrow -> reserves + mint DLRS.
    function test_cancelQueue_fallback_whenOwnerBlacklisted() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // escrows 1000 USDC
        uint256 id = store.getUserQueuePositions(alice)[0];

        usdc.setBlocked(alice, true); // alice can no longer receive USDC

        vm.expectEmit(true, true, false, true, address(store));
        emit QueuePositionRefunded(id, alice, address(usdc), 1_000e6);
        vm.prank(alice);
        store.cancelQueue(id);

        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 1_000e6, "escrow NOT returned as tokens");
        assertEq(dlrs.balanceOf(alice), 1_000e6, "escrow converted to DLRS claim");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "escrow moved into reserves");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "position removed");
        assertEq(dlrs.totalSupply(), _reserveSum(), "invariant: DLRS supply == sum reserves");
    }

    /// @notice processQueue: paying the queued owner fails -> eject + mint DLRS, reserves preserved.
    function test_processQueue_fallback_whenOwnerBlacklisted() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues USDC->USDT (escrows 1000 USDC)
        uint256 id = store.getUserQueuePositions(alice)[0];
        _deposit(bob, usdt, 1_000e6); // USDT reserves for the queue to settle against

        usdt.setBlocked(alice, true); // alice can no longer receive USDT

        vm.expectEmit(true, true, false, true, address(store));
        emit QueuePositionRefunded(id, alice, address(usdc), 1_000e6);
        vm.prank(carol);
        (uint256 processed, uint256 amountFilled) = store.processQueue(address(usdc), address(usdt), 10);

        assertEq(processed, 1, "one position processed");
        assertEq(amountFilled, 0, "nothing paid out (owner frozen)");
        assertEq(usdt.balanceOf(alice), 1_000_000e6, "alice received no USDT");
        assertEq(dlrs.balanceOf(alice), 1_000e6, "alice got a DLRS claim");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "escrowed USDC moved to reserves");
        assertEq(store.getReserve(0, address(usdt)), 1_000e6, "USDT reserves untouched");
        assertEq(dlrs.totalSupply(), _reserveSum(), "invariant: DLRS supply == sum reserves");
    }

    // ============ Linked-list surgery (non-head removals) ============

    /// @notice Removing the MIDDLE node of a 3-position queue must relink prev<->next correctly.
    function test_queue_middleRemoval_relinksList() public {
        _swap(alice, usdc, usdt, 500e6, 0); // head
        _swap(bob, usdc, usdt, 500e6, 0); //   middle
        _swap(carol, usdc, usdt, 500e6, 0); //  tail
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 1_500e6, "three queued");

        uint256 bobId = store.getUserQueuePositions(bob)[0];
        vm.prank(bob);
        store.cancelQueue(bobId); // remove the middle -> exercises prev.next / next.prev relink

        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 1_000e6, "middle removed");
        assertEq(usdc.balanceOf(bob), 1_000_000e6, "bob refunded escrow");

        // Integrity: with reserves present, the relinked list settles alice then carol (FIFO), not bob.
        _deposit(alice, usdt, 1_000e6);
        vm.prank(carol);
        (uint256 processed,) = store.processQueue(address(usdc), address(usdt), 10);
        assertEq(processed, 2, "alice + carol remain and settle; bob is gone");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue fully drained");
    }

    /// @notice A single swap consuming MULTIPLE opposite positions iterates the fill loop.
    function test_swap_matchesMultipleOppositePositions() public {
        _swap(alice, usdc, usdt, 500e6, 0); // opposite pos 1
        _swap(bob, usdc, usdt, 500e6, 0); //   opposite pos 2

        (uint256 filled, uint256 queued) = _swap(carol, usdt, usdc, 1_000e6, 0);

        assertEq(filled, 1_000e6, "consumed both opposite positions");
        assertEq(queued, 0, "nothing queued");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "both removed");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 500e6, "alice paid in USDT");
        assertEq(usdt.balanceOf(bob), 1_000_000e6 + 500e6, "bob paid in USDT");
        assertEq(usdc.balanceOf(carol), 1_000_000e6 + 1_000e6, "carol got USDC");
    }

    /// @notice An opposite match that only PARTIALLY consumes a resting position (reduce, not remove).
    function test_swap_partiallyConsumesOppositePosition() public {
        _swap(alice, usdc, usdt, 1_000e6, 0); // alice queues 1000

        (uint256 filled, uint256 queued) = _swap(bob, usdt, usdc, 400e6, 0); // bob only 400

        assertEq(filled, 400e6, "bob filled 400 by partial match");
        assertEq(queued, 0, "bob nothing queued");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 600e6, "alice reduced to 600");
        assertEq(store.getUserQueuePositions(alice).length, 1, "alice position still live");
        assertEq(usdt.balanceOf(alice), 1_000_000e6 + 400e6, "alice got 400 USDT");
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 400e6, "bob got 400 USDC");
    }

    /// @notice Cancelling a non-last position of a user with multiple positions swap-and-pops the id.
    function test_cancelQueue_multiPosition_swapAndPop() public {
        _swap(alice, usdc, usdt, 500e6, 0); // pos 1 (first in queue)
        _swap(alice, usdc, usdt, 600e6, 0); // pos 2 (meets 500 minimum)
        assertEq(store.getUserQueuePositions(alice).length, 2, "two positions");

        uint256 first = store.getUserQueuePositions(alice)[0];
        vm.prank(alice);
        store.cancelQueue(first); // remove non-last from the user array -> swap-and-pop

        uint256[] memory left = store.getUserQueuePositions(alice);
        assertEq(left.length, 1, "one position left");
        assertTrue(left[0] != first, "the surviving id is the other position");
        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 600e6, "only the 600 remains");
    }

    // ============ Reentrancy ============

    /// @notice A token that reenters on payout must be stopped by the nonReentrant guard.
    function test_reentrancy_blockedOnWithdraw() public {
        MockReentrantERC20 evil = new MockReentrantERC20("Evil", "EVIL", 6);
        vm.prank(governor);
        store.addHubAsset(address(evil), address(feed));
        evil.mint(alice, 1_000e6);

        vm.startPrank(alice);
        evil.approve(address(store), 1_000e6);
        store.deposit(0, address(evil), 1_000e6, block.timestamp);
        vm.stopPrank();

        evil.arm(address(store)); // next payout reenters store.withdraw

        vm.prank(alice);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        store.withdraw(0, address(evil), 100e6, block.timestamp);
    }

    // ============ Cross-decimal swaps ============

    /// @notice Swap 6dp offer -> 18dp want, filled from reserves, exercises scaling in the swap path.
    function test_swap_crossDecimals_reservesFill() public {
        _deposit(bob, dai, 1_000e18); // 1000e18 native -> 1000e6 units reserve

        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        (uint256 filled, uint256 queued) = store.swap(address(usdc), address(dai), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();

        assertEq(filled, 1_000e6, "1000 units filled");
        assertEq(queued, 0, "nothing queued");
        assertEq(dai.balanceOf(alice), 1_000_000e18 + 1_000e18, "alice received 1000 DAI native");
        assertEq(store.getReserve(0, address(dai)), 0, "DAI reserve drained");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "USDC reserve grew (6dp units)");
    }

    /// @notice Cross-decimal exact-opposite match: 18dp escrow paid out against a 6dp offer.
    function test_swap_crossDecimals_oppositeMatch() public {
        // alice queues DAI(18dp)->USDC(6dp), escrowing 1000 DAI == 1000 units.
        vm.startPrank(alice);
        dai.approve(address(store), 1_000e18);
        store.swap(address(dai), address(usdc), 1_000e18, 0, 0, block.timestamp);
        vm.stopPrank();

        // bob swaps USDC->DAI: matched against alice; alice receives USDC, bob receives DAI.
        (uint256 filled, uint256 queued) = _swap(bob, usdc, dai, 1_000e6, 0);

        assertEq(filled, 1_000e6, "bob fully matched");
        assertEq(queued, 0, "nothing queued");
        assertEq(usdc.balanceOf(alice), 1_000_000e6 + 1_000e6, "alice got USDC (6dp)");
        assertEq(dai.balanceOf(bob), 1_000_000e18 + 1_000e18, "bob got DAI (18dp)");
        assertEq(store.getQueueDepth(address(dai), address(usdc)), 0, "queue emptied");
    }

    // ============ Views ============

    function test_view_getQueuePosition() public {
        _swap(alice, usdc, usdt, 1_000e6, 0);
        uint256 id = store.getUserQueuePositions(alice)[0];

        (address owner, address offerAsset, address wantAsset, uint256 amount, uint256 timestamp) =
            store.getQueuePosition(id);
        assertEq(owner, alice, "owner");
        assertEq(offerAsset, address(usdc), "offerAsset");
        assertEq(wantAsset, address(usdt), "wantAsset");
        assertEq(amount, 1_000e6, "amount");
        assertEq(timestamp, block.timestamp, "timestamp");
    }

    function test_view_getQueuePosition_zeroForMissing() public view {
        (address owner,,, uint256 amount,) = store.getQueuePosition(999);
        assertEq(owner, address(0), "missing -> zero owner");
        assertEq(amount, 0, "missing -> zero amount");
    }

    function test_view_getMinimumOrderSize_base() public view {
        assertEq(store.getMinimumOrderSize(address(usdc), address(usdt)), 500e6, "base min on empty queue");
    }

    function test_view_getSwapQuote_invalidRoute_returnsZero() public view {
        assertEq(store.getSwapQuote(address(usdc), address(usdc), 1_000e6), 0, "same asset -> 0");
        assertEq(store.getSwapQuote(address(usdc), address(0xBEEF), 1_000e6), 0, "unlisted want -> 0");
        assertEq(store.getSwapQuote(address(0xBEEF), address(usdc), 1_000e6), 0, "unlisted offer -> 0");
    }

    // ============ Input-validation reverts (negative paths) ============

    function test_swap_revertsExpiredDeadline() public {
        vm.warp(1000);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DeadlineExpired.selector, uint256(999), uint256(1000)));
        store.swap(address(usdc), address(usdt), 1_000e6, 0, 0, 999);
        vm.stopPrank();
    }

    function test_swap_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.swap(address(usdc), address(usdt), 0, 0, 0, block.timestamp);
    }

    function test_swap_revertsAssetNotListed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.swap(address(0xBEEF), address(usdt), 1_000e6, 0, 0, block.timestamp);
    }

    function test_swapExactInput_revertsExpiredDeadline() public {
        vm.warp(1000);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DeadlineExpired.selector, uint256(999), uint256(1000)));
        store.swapExactInput(address(usdc), address(usdt), 1_000e6, 0, 999);
        vm.stopPrank();
    }

    function test_swapExactInput_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.swapExactInput(address(usdc), address(usdt), 0, 0, block.timestamp);
    }

    function test_swapExactInput_revertsMinAmountNotMet() public {
        _deposit(bob, usdt, 1_000e6);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.MinAmountNotMet.selector, uint256(1_000e6), uint256(2_000e6))
        );
        store.swapExactInput(address(usdc), address(usdt), 1_000e6, 2_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_withdraw_revertsAssetNotListed() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.withdraw(0, address(0xBEEF), 1e6, block.timestamp);
    }

    function test_withdraw_revertsWrongPool() public {
        // usdc is listed in the hub (pool 0); requesting it from pool 1 is a WrongPool.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.WrongPool.selector, address(usdc), uint16(1)));
        store.withdraw(1, address(usdc), 1e6, block.timestamp);
    }

    function test_swap_revertsWantNotListed() public {
        // offer listed, want not: _validateRoute rejects on the want side.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.swap(address(usdc), address(0xBEEF), 1_000e6, 0, 0, block.timestamp);
    }

    function test_swap_revertsFeeOnTransfer() public {
        // The swap pull path (_pullExact) must reject fee-on-transfer tokens too.
        MockFeeOnTransferERC20 fee = new MockFeeOnTransferERC20("Fee", "FEE", 6, 100); // 1%
        vm.prank(governor);
        store.addHubAsset(address(fee), address(feed));
        fee.mint(alice, 1_000e6);

        vm.startPrank(alice);
        fee.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.FeeOnTransferNotSupported.selector, address(fee)));
        store.swap(address(fee), address(usdt), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_getSwapQuote_zeroUnits() public view {
        // A valid route whose amount normalizes to 0 units quotes 0.
        assertEq(store.getSwapQuote(address(usdc), address(usdt), 0), 0, "zero amount -> 0 units -> 0");
    }

    function test_getReserves_revertsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.getReserves(5);
    }
}
