// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P2: spoke lifecycle - createSpoke, ownership enforcement, setMinDlrsReserve, removePool.
contract SpokeLifecycleTest is Test {
    DollarStore internal store;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal stranger = makeAddr("stranger");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockERC20 internal rlusd; // 18dp challenger asset for a spoke
    MockAggregatorV3 internal feed;

    event PoolCreated(uint16 indexed poolId, uint8 kind);
    event AssetListed(address indexed asset, uint16 indexed poolId, uint8 decimals, address priceFeed);
    event MinDlrsReserveSet(uint16 indexed poolId, uint256 oldMin, uint256 newMin);
    event PoolRemoved(uint16 indexed poolId);

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        feed = new MockAggregatorV3(8, 1e8); // $1

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        vm.stopPrank();
    }

    function _createRlusdSpoke(uint256 minDlrs) internal returns (uint16 poolId) {
        vm.prank(governor);
        poolId = store.createSpoke(address(rlusd), address(feed), minDlrs);
    }

    // ============ createSpoke ============

    function test_createSpoke_success() public {
        vm.expectEmit(true, false, false, true, address(store));
        emit PoolCreated(1, 1);
        vm.expectEmit(true, true, false, true, address(store));
        emit AssetListed(address(rlusd), 1, 18, address(feed));
        vm.expectEmit(true, false, false, true, address(store));
        emit MinDlrsReserveSet(1, 0, 1_000e6);

        uint16 poolId = _createRlusdSpoke(1_000e6);

        assertEq(poolId, 1, "first spoke is poolId 1");
        assertEq(store.poolCount(), 2, "hub + one spoke");
        assertEq(store.poolKind(1), 1, "kind = Spoke");
        assertTrue(store.isAssetListed(address(rlusd)), "spoke asset listed");
        assertEq(store.assetPoolId(address(rlusd)), 1, "asset canonical pool = 1");
        assertEq(store.assetScalingFactor(address(rlusd)), 1e12, "18dp scaling");
        assertEq(store.getMinDlrsReserve(1), 1_000e6, "min set");
        assertEq(store.getDlrsReserve(1), 0, "dlrsReserve starts 0");
        assertEq(store.getReceiptTotalShares(1), 0, "no shares yet");
        address[] memory assets = store.getPoolAssets(1);
        assertEq(assets.length, 1, "one asset");
        assertEq(assets[0], address(rlusd), "the spoke asset");
    }

    function test_createSpoke_onlyGovernor() public {
        vm.prank(stranger);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.createSpoke(address(rlusd), address(feed), 0);
    }

    function test_createSpoke_revertsIfAssetAlreadyHub() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetAlreadyListed.selector, address(usdc)));
        store.createSpoke(address(usdc), address(feed), 0);
    }

    function test_addHubAsset_revertsIfAssetAlreadySpoke() public {
        _createRlusdSpoke(0);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetAlreadyListed.selector, address(rlusd)));
        store.addHubAsset(address(rlusd), address(feed));
    }

    function test_createSpoke_revertsSameAssetTwice() public {
        _createRlusdSpoke(0);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetAlreadyListed.selector, address(rlusd)));
        store.createSpoke(address(rlusd), address(feed), 0);
    }

    function test_createSpoke_revertsZeroAddress() public {
        vm.startPrank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.createSpoke(address(0), address(feed), 0);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.createSpoke(address(rlusd), address(0), 0);
        vm.stopPrank();
    }

    function test_createSpoke_revertsFeedDecimalsTooHigh() public {
        MockAggregatorV3 badFeed = new MockAggregatorV3(19, 1e19);
        vm.prank(governor);
        vm.expectRevert();
        store.createSpoke(address(rlusd), address(badFeed), 0);
    }

    function test_createSpoke_secondSpokeGetsNextId() public {
        _createRlusdSpoke(0);
        MockERC20 pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        vm.prank(governor);
        uint16 poolId = store.createSpoke(address(pyusd), address(feed), 500e6);
        assertEq(poolId, 2, "second spoke is poolId 2");
        assertEq(store.poolCount(), 3, "hub + two spokes");
    }

    // ============ setMinDlrsReserve ============

    function test_setMinDlrsReserve_success() public {
        _createRlusdSpoke(1_000e6);
        vm.expectEmit(true, false, false, true, address(store));
        emit MinDlrsReserveSet(1, 1_000e6, 2_500e6);
        vm.prank(governor);
        store.setMinDlrsReserve(1, 2_500e6);
        assertEq(store.getMinDlrsReserve(1), 2_500e6, "updated");
    }

    function test_setMinDlrsReserve_onlyGovernor() public {
        _createRlusdSpoke(0);
        vm.prank(stranger);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setMinDlrsReserve(1, 100e6);
    }

    function test_setMinDlrsReserve_revertsOnHub() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotSpoke.selector, uint16(0)));
        store.setMinDlrsReserve(0, 100e6);
    }

    function test_setMinDlrsReserve_revertsInvalidPool() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(9)));
        store.setMinDlrsReserve(9, 100e6);
    }

    // ============ removePool ============

    function test_removePool_emptySpoke_kills() public {
        _createRlusdSpoke(1_000e6);

        vm.expectEmit(true, false, false, false, address(store));
        emit PoolRemoved(1);
        vm.prank(governor);
        store.removePool(1);

        assertFalse(store.isAssetListed(address(rlusd)), "spoke asset unlisted");
        assertTrue(store.isPoolPaused(1), "pool paused");
        assertEq(store.poolCount(), 2, "tombstone stays in the array (poolId not reused)");
    }

    function test_removePool_thenRecreateSameAsset() public {
        _createRlusdSpoke(0);
        vm.prank(governor);
        store.removePool(1);

        // The asset is free again; recreating gives a fresh poolId (the killed pool is a tombstone).
        vm.prank(governor);
        uint16 poolId = store.createSpoke(address(rlusd), address(feed), 0);
        assertEq(poolId, 2, "recreated spoke gets a new id");
        assertTrue(store.isAssetListed(address(rlusd)), "listed again");
        assertEq(store.assetPoolId(address(rlusd)), 2, "canonical pool updated");
    }

    function test_removePool_onlyGovernor() public {
        _createRlusdSpoke(0);
        vm.prank(stranger);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.removePool(1);
    }

    function test_removePool_revertsOnHub() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotSpoke.selector, uint16(0)));
        store.removePool(0);
    }

    function test_removePool_revertsInvalidPool() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.removePool(5);
    }

    // ============ getters revert on invalid pool ============

    function test_getters_revertInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(3)));
        store.getMinDlrsReserve(3);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(3)));
        store.getDlrsReserve(3);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(3)));
        store.poolKind(3);
    }
}
