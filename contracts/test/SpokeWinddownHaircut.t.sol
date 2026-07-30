// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P8: spoke winding-down lifecycle and the guardian escrow-impairment haircut.
contract SpokeWinddownHaircutTest is Test {
    DollarStore internal store;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockERC20 internal usdc;
    MockERC20 internal rlusd; // 18dp spoke asset
    MockAggregatorV3 internal feed;

    uint16 internal spoke;

    event SpokeWindDownStarted(uint16 indexed poolId);
    event EscrowHaircut(address indexed asset, uint16 indexed poolId, uint256 oldEscrow, uint256 newEscrow);

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        feed = new MockAggregatorV3(8, 1e8);

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        spoke = store.createSpoke(address(rlusd), address(feed), 0);
        vm.stopPrank();

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        rlusd.mint(alice, 1_000_000e18);
        rlusd.mint(bob, 1_000_000e18);
    }

    function _depositSpokeAsset(address who, uint256 amt) internal {
        vm.startPrank(who);
        rlusd.approve(address(store), amt);
        store.deposit(spoke, address(rlusd), amt, block.timestamp);
        vm.stopPrank();
    }

    function _fund(address who, uint256 amt) internal {
        vm.startPrank(who);
        usdc.approve(address(store), amt);
        store.deposit(spoke, address(usdc), amt, block.timestamp);
        vm.stopPrank();
    }

    function _queueSpokeToHub(address who, uint256 amt) internal {
        vm.startPrank(who);
        rlusd.approve(address(store), amt);
        store.swap(address(rlusd), address(usdc), amt, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Winding down ============

    function test_windDownSpoke_starts() public {
        vm.expectEmit(true, false, false, false, address(store));
        emit SpokeWindDownStarted(spoke);
        vm.prank(governor);
        store.windDownSpoke(spoke);
        assertEq(store.getPoolStatus(spoke), 1, "status = WindingDown");
    }

    function test_windDownSpoke_blocksDeposits() public {
        vm.prank(governor);
        store.windDownSpoke(spoke);

        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.SpokeWindingDown.selector, spoke));
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.SpokeWindingDown.selector, spoke));
        store.deposit(spoke, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_windDownSpoke_blocksSpokeToHubButAllowsHubToSpoke() public {
        _depositSpokeAsset(alice, 1_000e18); // spoke reserve for hub->spoke
        _fund(alice, 1_000e6); // dlrs side for spoke->hub
        vm.prank(governor);
        store.windDownSpoke(spoke);

        // Risk-increasing spoke->hub is blocked.
        vm.startPrank(bob);
        rlusd.approve(address(store), 500e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.SpokeWindingDown.selector, spoke));
        store.swap(address(rlusd), address(usdc), 500e18, 0, 0, block.timestamp);

        // Risk-reducing hub->spoke stays live.
        usdc.approve(address(store), 500e6);
        (uint256 filled,) = store.swap(address(usdc), address(rlusd), 500e6, 0, 0, block.timestamp);
        vm.stopPrank();
        assertEq(filled, 500e6, "hub->spoke allowed during winddown");
    }

    function test_windDownSpoke_keepsWithdrawLive() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(governor);
        store.windDownSpoke(spoke);

        vm.prank(alice);
        uint256 out = store.withdraw(spoke, address(rlusd), 1_000e6, block.timestamp);
        assertEq(out, 1_000e18, "LP can still exit while winding down");
    }

    function test_windDownSpoke_quoteSpokeToHubZero() public {
        _fund(alice, 1_000e6);
        vm.prank(governor);
        store.windDownSpoke(spoke);
        assertEq(
            store.getSwapQuote(address(rlusd), address(usdc), 500e18), 0, "spoke->hub not quotable while winding down"
        );
    }

    function test_windDownSpoke_onlyGovernor() public {
        vm.prank(bob);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.windDownSpoke(spoke);
    }

    function test_windDownSpoke_revertsOnHub() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotSpoke.selector, uint16(0)));
        store.windDownSpoke(0);
    }

    function test_windDownSpoke_revertsIfAlready() public {
        vm.startPrank(governor);
        store.windDownSpoke(spoke);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.SpokeWindingDown.selector, spoke));
        store.windDownSpoke(spoke);
        vm.stopPrank();
    }

    function test_removePool_setsKilledStatus() public {
        vm.prank(governor);
        store.removePool(spoke);
        assertEq(store.getPoolStatus(spoke), 2, "status = Killed");
    }

    // ============ Escrow-impairment haircut ============

    function test_haircutEscrow_proRataReduction() public {
        _queueSpokeToHub(bob, 1_000e18); // escrow 1000 rlusd, no liquidity so it queues
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 1_000e6, "escrow queued");

        // Simulate a balance impairment: the contract loses 40% of its RLUSD.
        deal(address(rlusd), address(store), 600e18);

        vm.prank(guardian);
        store.pausePool(spoke);

        vm.expectEmit(true, true, false, true, address(store));
        emit EscrowHaircut(address(rlusd), spoke, 1_000e6, 600e6);
        vm.prank(guardian);
        uint256 removed = store.haircutEscrow(address(rlusd), 10);

        assertEq(removed, 400e6, "40% haircut removed");
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 600e6, "escrow reduced to surviving balance");
        // Solvency restored: reserves(0) + escrow(600) == actual(600).
        (,,, uint256 amt,) = store.getQueuePosition(store.getUserQueuePositions(bob)[0]);
        assertEq(amt, 600e6, "bob's position haircut pro-rata");
    }

    function test_haircutEscrow_fullImpairment_removesPositions() public {
        _queueSpokeToHub(bob, 1_000e18);
        deal(address(rlusd), address(store), 0); // total loss

        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(guardian);
        uint256 removed = store.haircutEscrow(address(rlusd), 10);

        assertEq(removed, 1_000e6, "all escrow removed");
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 0, "queue emptied");
        assertEq(store.getUserQueuePositions(bob).length, 0, "position ejected");
    }

    function test_haircutEscrow_revertsNotPaused() public {
        _queueSpokeToHub(bob, 1_000e18);
        deal(address(rlusd), address(store), 600e18);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotPaused.selector, spoke));
        store.haircutEscrow(address(rlusd), 10);
    }

    function test_haircutEscrow_revertsNotImpaired() public {
        _queueSpokeToHub(bob, 1_000e18); // full balance present, not impaired
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotImpaired.selector, address(rlusd)));
        store.haircutEscrow(address(rlusd), 10);
    }

    function test_haircutEscrow_onlyGuardian() public {
        _queueSpokeToHub(bob, 1_000e18);
        deal(address(rlusd), address(store), 600e18);
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(bob);
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.haircutEscrow(address(rlusd), 10);
    }

    function test_haircutEscrow_budgetExceeded() public {
        _queueSpokeToHub(bob, 1_000e18); // position 1
        _queueSpokeToHub(bob, 600e18); // position 2 (meets the 500 minimum)
        deal(address(rlusd), address(store), 800e18);

        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.HaircutBudgetExceeded.selector);
        store.haircutEscrow(address(rlusd), 1); // only 1 of 2 positions fits
    }

    // ============ Extra guard coverage ============

    function test_getPoolStatus_revertsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(999)));
        store.getPoolStatus(999);
    }

    function test_haircutEscrow_revertsAssetNotListed() public {
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(0xBEEF)));
        store.haircutEscrow(address(0xBEEF), 10);
    }

    function test_haircutEscrow_revertsNoEscrow() public {
        // Pool paused (required) but no queued escrow of the asset -> NoEscrowToHaircut.
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.NoEscrowToHaircut.selector, address(rlusd)));
        store.haircutEscrow(address(rlusd), 10);
    }

    function test_removePool_revertsWhenQueueDepthNonZero() public {
        // A queued spoke->hub position leaves escrow (not reserves/shares) on the spoke's route.
        _queueSpokeToHub(alice, 1_000e18);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotEmpty.selector, spoke));
        store.removePool(spoke);
    }
}
