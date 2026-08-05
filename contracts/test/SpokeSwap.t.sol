// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P5: hub<>spoke routing. hub->spoke pays the spoke asset from the spoke reserve and grows
///         dlrsReserve; spoke->hub pays a hub asset from hub reserves and consumes dlrsReserve, gated by
///         minDlrsReserve. Spoke->spoke is rejected. Exact-opposite queue matches stay peer-to-peer.
contract SpokeSwapTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice"); // LP
    address internal bob = makeAddr("bob"); // trader
    address internal carol = makeAddr("carol"); // trader

    MockERC20 internal usdc;
    MockERC20 internal rlusd; // 18dp spoke asset
    MockAggregatorV3 internal feed;

    uint16 internal spoke;

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        feed = new MockAggregatorV3(8, 1e8);

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        spoke = store.createSpoke(address(rlusd), address(feed), 0);
        vm.stopPrank();

        for (uint256 i; i < 3; i++) {
            address who = [alice, bob, carol][i];
            usdc.mint(who, 1_000_000e6);
            rlusd.mint(who, 1_000_000e18);
        }
    }

    function _seedSpokeAsset(uint256 nativeAmt) internal {
        vm.startPrank(alice);
        rlusd.approve(address(store), nativeAmt);
        store.deposit(spoke, address(rlusd), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    function _seedDlrsSide(uint256 nativeAmt) internal {
        vm.startPrank(alice);
        usdc.approve(address(store), nativeAmt);
        store.deposit(spoke, address(usdc), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    function _swap(address who, MockERC20 offer, MockERC20 want, uint256 amt)
        internal
        returns (uint256 filled, uint256 queued)
    {
        vm.startPrank(who);
        offer.approve(address(store), amt);
        (filled, queued) = store.swap(address(offer), address(want), amt, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ hub -> spoke ============

    function test_hubToSpoke_fillsFromSpokeReserve() public {
        _seedSpokeAsset(1_000e18); // spoke reserve 1000 rlusd

        (uint256 filled, uint256 queued) = _swap(carol, usdc, rlusd, 500e6);

        assertEq(filled, 500e6, "filled");
        assertEq(queued, 0, "nothing queued");
        assertEq(rlusd.balanceOf(carol), 1_000_000e18 + 500e18, "carol got RLUSD");
        assertEq(usdc.balanceOf(carol), 1_000_000e6 - 500e6, "carol paid USDC");
        assertEq(store.getReserve(spoke, address(rlusd)), 500e6, "spoke reserve down");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "hub usdc reserve up");
        assertEq(store.getDlrsReserve(spoke), 500e6, "dlrsReserve grew");
        // DLRS conservation: wallet supply + dlrsReserve == hub reserves.
        assertEq(dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "conservation");
    }

    // ============ spoke -> hub ============

    function test_spokeToHub_fillsFromHubReserveConsumingDlrs() public {
        _seedDlrsSide(1_000e6); // dlrsReserve 1000, hub usdc reserve 1000

        (uint256 filled, uint256 queued) = _swap(bob, rlusd, usdc, 500e18);

        assertEq(filled, 500e6, "filled");
        assertEq(queued, 0, "nothing queued");
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 500e6, "bob got USDC");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "hub usdc reserve down");
        assertEq(store.getReserve(spoke, address(rlusd)), 500e6, "spoke reserve up (offer absorbed)");
        assertEq(store.getDlrsReserve(spoke), 500e6, "dlrsReserve consumed");
        assertEq(dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "conservation");
    }

    // ============ minDlrsReserve gates spoke -> hub ============

    function test_spokeToHub_boundedByMinDlrsReserve() public {
        _seedDlrsSide(1_000e6); // dlrsReserve 1000, hub usdc 1000
        vm.prank(governor);
        store.setMinDlrsReserve(spoke, 800e6); // only 200 exitable

        (uint256 filled, uint256 queued) = _swap(bob, rlusd, usdc, 500e18);

        assertEq(filled, 200e6, "only the exitable dlrs (1000-800) fills");
        assertEq(queued, 300e6, "remainder queues");
        assertEq(store.getDlrsReserve(spoke), 800e6, "dlrsReserve stops at the floor");
        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 200e6, "bob got 200 USDC");
    }

    function test_spokeToHub_exactInput_revertsWhenAboveExitableDlrs() public {
        _seedDlrsSide(1_000e6);
        vm.prank(governor);
        store.setMinDlrsReserve(spoke, 800e6); // 200 exitable

        vm.startPrank(bob);
        rlusd.approve(address(store), 500e18);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientLiquidity.selector, uint256(200e6), uint256(500e6))
        );
        store.swapExactInput(address(rlusd), address(usdc), 500e18, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ exact-opposite queue match is peer-to-peer (route-independent) ============

    function test_hubToSpoke_matchesSpokeToHubQueue_peerToPeer() public {
        // Alice queues RLUSD->USDC with no protocol liquidity (spoke has no dlrs side, hub no usdc).
        (uint256 aFilled, uint256 aQueued) = _swap(alice, rlusd, usdc, 1_000e18);
        assertEq(aFilled, 0, "no liquidity, fully queued");
        assertEq(aQueued, 1_000e6, "alice queued");

        // Bob swaps USDC->RLUSD: matched directly against Alice's escrow, no reserves/dlrs touched.
        (uint256 bFilled, uint256 bQueued) = _swap(bob, usdc, rlusd, 1_000e6);
        assertEq(bFilled, 1_000e6, "bob fully matched by the opposite queue");
        assertEq(bQueued, 0, "nothing queued");

        assertEq(usdc.balanceOf(alice), 1_000_000e6 + 1_000e6, "alice got USDC from bob");
        assertEq(rlusd.balanceOf(bob), 1_000_000e18 + 1_000e18, "bob got RLUSD from alice's escrow");
        assertEq(store.getDlrsReserve(spoke), 0, "dlrsReserve untouched by a peer match");
        assertEq(store.getReserve(0, address(usdc)), 0, "no hub reserve involved");
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 0, "alice's queue cleared");
    }

    // ============ rejects & pause ============

    function test_spokeToSpoke_rejected() public {
        MockERC20 pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        vm.prank(governor);
        store.createSpoke(address(pyusd), address(feed), 0);

        vm.startPrank(bob);
        rlusd.approve(address(store), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidRoute.selector, address(rlusd), address(pyusd)));
        store.swap(address(rlusd), address(pyusd), 1_000e18, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_swap_intoPausedSpoke_reverts() public {
        _seedSpokeAsset(1_000e18);
        vm.prank(guardian);
        store.pausePool(spoke);

        vm.startPrank(carol);
        usdc.approve(address(store), 500e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.swap(address(usdc), address(rlusd), 500e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ quote ============

    function test_getSwapQuote_hubToSpoke() public {
        _seedSpokeAsset(1_000e18);
        assertEq(store.getSwapQuote(address(usdc), address(rlusd), 500e6), 500e18, "quote in native rlusd");
    }

    function test_getSwapQuote_spokeToHub_respectsMin() public {
        _seedDlrsSide(1_000e6);
        vm.prank(governor);
        store.setMinDlrsReserve(spoke, 800e6);
        // Only 200 exitable; a 500 quote caps at 200.
        assertEq(store.getSwapQuote(address(rlusd), address(usdc), 500e18), 200e6, "quote bounded by exitable dlrs");
    }

    function test_getSwapQuote_spokeToSpoke_zero() public {
        MockERC20 pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        vm.prank(governor);
        store.createSpoke(address(pyusd), address(feed), 0);
        assertEq(store.getSwapQuote(address(rlusd), address(pyusd), 1_000e18), 0, "spoke->spoke not quotable");
    }

    /// @notice A route into a paused spoke is not quotable: _classifyRoute returns invalid, quote 0.
    ///         Mirrors the swap-side PoolPaused revert on the view path.
    function test_getSwapQuote_pausedSpoke_zero() public {
        _seedSpokeAsset(1_000e18);
        vm.prank(guardian);
        store.pausePool(spoke);
        assertEq(store.getSwapQuote(address(usdc), address(rlusd), 500e6), 0, "paused spoke not quotable");
    }
}
