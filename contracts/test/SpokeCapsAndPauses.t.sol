// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P7: per-spoke launch caps (exposure = spoke reserve + dlrsReserve) and pool-pause
///         semantics (pause blocks deposits/swaps/new-queue/processQueue for that spoke, leaves LP
///         withdrawals and queue cancellations live).
contract SpokeCapsAndPausesTest is Test {
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

    function _depositSpokeAsset(address who, uint256 nativeAmt) internal {
        vm.startPrank(who);
        rlusd.approve(address(store), nativeAmt);
        store.deposit(spoke, address(rlusd), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    function _fund(address who, uint256 nativeAmt) internal {
        vm.startPrank(who);
        usdc.approve(address(store), nativeAmt);
        store.deposit(spoke, address(usdc), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    // ============ Launch caps ============

    function test_spokeLaunchCap_blocksAboveExposure() public {
        vm.prank(governor);
        store.setLaunchCap(spoke, 1_000e6);

        _depositSpokeAsset(alice, 600e18); // exposure 600 <= 1000

        vm.startPrank(alice);
        rlusd.approve(address(store), 500e18);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.LaunchCapExceeded.selector, spoke, uint256(1_100e6), uint256(1_000e6))
        );
        store.deposit(spoke, address(rlusd), 500e18, block.timestamp); // 600 + 500 > 1000
        vm.stopPrank();
    }

    function test_spokeLaunchCap_countsDlrsReserve() public {
        vm.prank(governor);
        store.setLaunchCap(spoke, 1_000e6);

        _fund(alice, 600e6); // dlrsReserve 600 -> exposure 600

        // A spoke-asset deposit of 500 pushes exposure (spokeReserve + dlrsReserve) to 1100 > cap.
        vm.startPrank(bob);
        rlusd.approve(address(store), 500e18);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.LaunchCapExceeded.selector, spoke, uint256(1_100e6), uint256(1_000e6))
        );
        store.deposit(spoke, address(rlusd), 500e18, block.timestamp);
        vm.stopPrank();
    }

    function test_spokeLaunchCap_atExactCapPasses() public {
        vm.prank(governor);
        store.setLaunchCap(spoke, 1_000e6);
        _depositSpokeAsset(alice, 1_000e18); // exposure == cap, allowed
        assertEq(store.getReserve(spoke, address(rlusd)), 1_000e6, "deposit at exact cap allowed");
    }

    function test_spokeLaunchCap_lowerByGuardian() public {
        vm.prank(governor);
        store.setLaunchCap(spoke, 1_000e6);
        vm.prank(guardian);
        store.lowerLaunchCap(spoke, 400e6);
        assertEq(store.getLaunchCap(spoke), 400e6, "guardian lowered the spoke cap");
    }

    // ============ Pool pause: blocks ============

    function test_pausePool_blocksSpokeAssetDeposit() public {
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        vm.stopPrank();
    }

    function test_pausePool_blocksFundingDeposit() public {
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.deposit(spoke, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_pausePool_blocksSwapsBothDirections() public {
        _depositSpokeAsset(alice, 1_000e18); // give it liquidity so it is not a no-liquidity revert
        vm.prank(guardian);
        store.pausePool(spoke);

        vm.startPrank(bob);
        usdc.approve(address(store), 500e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.swap(address(usdc), address(rlusd), 500e6, 0, 0, block.timestamp);

        rlusd.approve(address(store), 500e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.swap(address(rlusd), address(usdc), 500e18, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    function test_pausePool_blocksProcessQueue() public {
        // Queue a spoke->hub order while live, then pause and try to process it.
        vm.startPrank(bob);
        rlusd.approve(address(store), 500e18);
        store.swap(address(rlusd), address(usdc), 500e18, 0, 0, block.timestamp); // queues
        vm.stopPrank();

        vm.prank(guardian);
        store.pausePool(spoke);

        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.processQueue(address(rlusd), address(usdc), 10);
    }

    // ============ Pool pause: leaves exits live ============

    function test_pausePool_leavesWithdrawLive() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(guardian);
        store.pausePool(spoke);

        vm.prank(alice);
        uint256 out = store.withdraw(spoke, address(rlusd), 1_000e6, block.timestamp);
        assertEq(out, 1_000e18, "LP can exit a paused spoke");
    }

    function test_pausePool_leavesCancelLive() public {
        vm.startPrank(bob);
        rlusd.approve(address(store), 500e18);
        store.swap(address(rlusd), address(usdc), 500e18, 0, 0, block.timestamp); // queues
        uint256 id = store.getUserQueuePositions(bob)[0];
        vm.stopPrank();

        vm.prank(guardian);
        store.pausePool(spoke);

        vm.prank(bob);
        store.cancelQueue(id);
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 0, "cancel works while pool paused");
        assertEq(rlusd.balanceOf(bob), 1_000_000e18, "escrow returned");
    }

    function test_unpausePool_restoresSwaps() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(guardian);
        store.pausePool(spoke);
        vm.prank(guardian);
        store.unpausePool(spoke);

        vm.startPrank(bob);
        usdc.approve(address(store), 500e6);
        (uint256 filled,) = store.swap(address(usdc), address(rlusd), 500e6, 0, 0, block.timestamp);
        vm.stopPrank();
        assertEq(filled, 500e6, "swaps work again after unpause");
    }
}
