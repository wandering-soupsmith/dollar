// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M5: pauses (asset/pool), oracle peg check, syncReserves/rescueTokens, adminCancelQueue.
contract RiskControlsTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockAggregatorV3 internal feed;

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

        usdc.mint(alice, 1_000_000e6);
        usdt.mint(alice, 1_000_000e6);
    }

    function _deposit(address who, MockERC20 token, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(store), amt);
        store.deposit(0, address(token), amt, block.timestamp);
        vm.stopPrank();
    }

    // ============ Defaults ============

    function test_defaults() public view {
        assertEq(store.pegTolerance(), 50, "0.5%");
        assertEq(store.maxStaleness(), 3600, "1h");
    }

    // ============ Per-asset deposit pause ============

    function test_pauseDeposits_blocksDepositButNotExit() public {
        _deposit(alice, usdc, 1_000e6);

        vm.prank(guardian);
        store.pauseDeposits(address(usdc));
        assertTrue(store.isDepositPaused(address(usdc)));

        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DepositsPaused.selector, address(usdc)));
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();

        // Exit path still works.
        vm.prank(alice);
        store.withdraw(0, address(usdc), 500e6, block.timestamp);
        assertEq(store.getReserve(0, address(usdc)), 500e6, "withdraw works while paused");
    }

    function test_pauseDeposits_onlyGuardian() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.pauseDeposits(address(usdc));
    }

    // ============ Per-pool pause ============

    function test_pausePool_blocksInflows() public {
        vm.prank(guardian);
        store.pausePool(0);
        assertTrue(store.isPoolPaused(0));

        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, uint16(0)));
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    // ============ Peg check ============

    function test_peg_blocksDepeggedDeposit() public {
        feed.setAnswer(9.9e7); // $0.99, outside 0.5% band
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        // expectPartialRevert: in Foundry 1.7.1, expectRevert(bytes4) only matches errors with NO
        // args; a parametrized error (PriceOutOfBounds carries data) needs selector-prefix matching
        // via expectPartialRevert (or the full abi.encodeWithSelector). The contract reverts
        // correctly — only the test's match mode needed updating for this forge version.
        vm.expectPartialRevert(IDollarStore.PriceOutOfBounds.selector);
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    function test_peg_allowsWithinBand() public {
        feed.setAnswer(1.004e8); // $1.004, within 0.5%
        _deposit(alice, usdc, 100e6);
        assertEq(store.getReserve(0, address(usdc)), 100e6, "deposit ok within band");
    }

    function test_peg_revertsInvalidPrice() public {
        feed.setAnswer(0);
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        // Parametrized error -> selector-prefix match (see note in test_peg_blocksDepeggedDeposit).
        vm.expectPartialRevert(IDollarStore.InvalidPrice.selector);
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    function test_peg_revertsStaleRound() public {
        feed.setRound(5, 4); // answeredInRound < roundId
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectPartialRevert(IDollarStore.StaleRound.selector);
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    function test_peg_revertsStalePrice() public {
        vm.warp(100_000);
        feed.setUpdatedAt(100_000 - 3601); // older than maxStaleness (3600)
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectPartialRevert(IDollarStore.PriceStale.selector);
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    function test_peg_blocksDepeggedSwap() public {
        // Give USDT reserves so the swap would otherwise fill.
        usdt.mint(bob, 1_000e6);
        vm.startPrank(bob);
        usdt.approve(address(store), 1_000e6);
        store.deposit(0, address(usdt), 1_000e6, block.timestamp);
        vm.stopPrank();

        feed.setAnswer(9.9e7); // offer asset depegged
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectPartialRevert(IDollarStore.PriceOutOfBounds.selector);
        store.swap(address(usdc), address(usdt), 100e6, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ setters ============

    function test_setPegTolerance() public {
        vm.prank(governor);
        store.setPegTolerance(100);
        assertEq(store.pegTolerance(), 100);
    }

    function test_setPegTolerance_boundsAndAuth() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.InvalidTolerance.selector);
        store.setPegTolerance(501);

        // Now governor-gated: even the guardian is rejected.
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setPegTolerance(100);
    }

    function test_setMaxStaleness_bounds() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.InvalidStaleness.selector);
        store.setMaxStaleness(2 days);
    }

    function test_setPriceFeed() public {
        MockAggregatorV3 f2 = new MockAggregatorV3(8, 1e8);
        vm.prank(governor);
        store.setPriceFeed(address(usdc), address(f2));
        assertEq(store.assetPriceFeed(address(usdc)), address(f2));
    }

    // ============ syncReserves ============

    function test_syncReserves_afterBalanceLoss() public {
        _deposit(alice, usdc, 1_000e6); // reserve 1000, balance 1000
        usdc.burn(address(store), 300e6); // simulate a seizure: balance -> 700

        vm.prank(governor);
        store.syncReserves(0, address(usdc));
        assertEq(store.getReserve(0, address(usdc)), 700e6, "reserves synced down");
    }

    function test_syncReserves_revertsNotDrifted() public {
        _deposit(alice, usdc, 1_000e6);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.ReservesNotDrifted.selector, address(usdc)));
        store.syncReserves(0, address(usdc));
    }

    // ============ rescueTokens ============

    function test_rescueTokens_excessOnly() public {
        _deposit(alice, usdc, 1_000e6); // accounted 1000
        usdc.mint(address(store), 500e6); // accidental extra

        vm.prank(governor);
        store.rescueTokens(address(usdc), bob);
        assertEq(usdc.balanceOf(bob), 500e6, "only excess rescued");
        assertEq(usdc.balanceOf(address(store)), 1_000e6, "accounted balance kept");
    }

    function test_rescueTokens_unlistedFullBalance() public {
        MockERC20 rando = new MockERC20("Rando", "RND", 18);
        rando.mint(address(store), 42e18); // sent by mistake

        vm.prank(governor);
        store.rescueTokens(address(rando), bob);
        assertEq(rando.balanceOf(bob), 42e18, "full balance rescued");
    }

    function test_rescueTokens_revertsNoExcess() public {
        _deposit(alice, usdc, 1_000e6);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.NoExcessTokens.selector, address(usdc)));
        store.rescueTokens(address(usdc), bob);
    }

    // ============ adminCancelQueue ============

    function test_adminCancelQueue_returnsEscrow() public {
        // Alice queues USDC->USDT (no USDT reserves).
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.swap(address(usdc), address(usdt), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();

        uint256 id = store.getUserQueuePositions(alice)[0];
        vm.prank(guardian);
        store.adminCancelQueue(id);

        assertEq(store.getQueueDepth(address(usdc), address(usdt)), 0, "queue emptied");
        assertEq(usdc.balanceOf(alice), 1_000_000e6, "escrow returned to owner");
    }

    function test_adminCancelQueue_onlyGuardian() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.swap(address(usdc), address(usdt), 1_000e6, 0, 0, block.timestamp);
        uint256 id = store.getUserQueuePositions(alice)[0];
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.adminCancelQueue(id);
        vm.stopPrank();
    }

    function test_adminCancelQueue_revertsNotFound() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.QueuePositionNotFound.selector, uint256(999)));
        store.adminCancelQueue(999);
    }

    // ============ Unpause (deposits / pool) ============

    function test_unpauseDeposits_restoresInflow() public {
        vm.prank(guardian);
        store.pauseDeposits(address(usdc));
        assertTrue(store.isDepositPaused(address(usdc)));

        vm.prank(guardian);
        store.unpauseDeposits(address(usdc));
        assertFalse(store.isDepositPaused(address(usdc)), "unpaused");

        _deposit(alice, usdc, 100e6); // inflow works again
        assertEq(store.getReserve(0, address(usdc)), 100e6, "deposit ok after unpause");
    }

    function test_unpausePool_restoresInflow() public {
        vm.prank(guardian);
        store.pausePool(0);
        assertTrue(store.isPoolPaused(0));

        vm.prank(guardian);
        store.unpausePool(0);
        assertFalse(store.isPoolPaused(0), "unpaused");

        _deposit(alice, usdc, 100e6);
        assertEq(store.getReserve(0, address(usdc)), 100e6, "deposit ok after unpause");
    }

    // ============ Pause / view revert paths ============

    function test_pauseDeposits_revertsUnlisted() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.pauseDeposits(address(0xBEEF));
    }

    function test_unpauseDeposits_revertsUnlisted() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.unpauseDeposits(address(0xBEEF));
    }

    function test_pausePool_revertsInvalidPool() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(99)));
        store.pausePool(99);
    }

    function test_unpausePool_revertsInvalidPool() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(99)));
        store.unpausePool(99);
    }

    function test_isPoolPaused_revertsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(99)));
        store.isPoolPaused(99);
    }

    // ============ Peg: above-band + setter happy paths ============

    function test_peg_blocksAboveBand() public {
        feed.setAnswer(1.01e8); // $1.01, above the 0.5% upper bound
        vm.startPrank(alice);
        usdc.approve(address(store), 100e6);
        vm.expectPartialRevert(IDollarStore.PriceOutOfBounds.selector);
        store.deposit(0, address(usdc), 100e6, block.timestamp);
        vm.stopPrank();
    }

    function test_setMaxStaleness_happyPath() public {
        vm.prank(governor);
        store.setMaxStaleness(2 hours);
        assertEq(store.maxStaleness(), 2 hours, "staleness updated");
    }

    // ============ setPriceFeed revert paths ============

    function test_setPriceFeed_revertsZeroFeed() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.setPriceFeed(address(usdc), address(0));
    }

    function test_setPriceFeed_revertsUnlisted() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.setPriceFeed(address(0xBEEF), address(feed));
    }

    // ============ syncReserves / rescueTokens revert paths ============

    function test_syncReserves_revertsUnlisted() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.syncReserves(0, address(0xBEEF));
    }

    function test_syncReserves_revertsWrongPool() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.WrongPool.selector, address(usdc), uint16(1)));
        store.syncReserves(1, address(usdc));
    }

    /// @notice actual balance below escrow -> EscrowImpaired (deep-haircut path deferred).
    function test_syncReserves_revertsEscrowImpaired() public {
        // Alice queues USDC->USDT (no reserves): escrows 1000 USDC into the store.
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.swap(address(usdc), address(usdt), 1_000e6, 0, 0, block.timestamp);
        vm.stopPrank();

        usdc.burn(address(store), 400e6); // balance 600 < escrow 1000

        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.EscrowImpaired.selector, address(usdc)));
        store.syncReserves(0, address(usdc));
    }

    function test_rescueTokens_revertsZeroTo() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.rescueTokens(address(usdc), address(0));
    }

    // ============ Re-gated to governor: guardian is rejected ============
    // These are fund-touching / peg-defining powers. They live behind the governor
    // (timelock), not the fast guardian. The guardian only has fail-safe brakes.

    function test_setPriceFeed_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setPriceFeed(address(usdc), address(feed));
    }

    function test_setPegTolerance_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setPegTolerance(100);
    }

    function test_setMaxStaleness_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setMaxStaleness(2 hours);
    }

    function test_syncReserves_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.syncReserves(0, address(usdc));
    }

    function test_rescueTokens_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.rescueTokens(address(usdc), bob);
    }
}
