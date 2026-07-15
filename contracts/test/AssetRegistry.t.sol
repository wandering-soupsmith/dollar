// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {NormalizationLib} from "../src/libraries/NormalizationLib.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M2 behaviour: hub pool creation at init + hub asset registry + decimal normalization.
contract AssetRegistryTest is Test {
    DollarStore internal store;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");

    MockERC20 internal usdc; // 6 decimals
    MockERC20 internal dai; //  18 decimals
    address internal FEED; // a live $1 mock feed (addHubAsset now reads feed.decimals())

    event PoolCreated(uint16 indexed poolId, uint8 kind);
    event AssetListed(address indexed asset, uint16 indexed poolId, uint8 decimals, address priceFeed);

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));

        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai", "DAI", 18);
        FEED = address(new MockAggregatorV3(8, 1e8)); // $1, 8 decimals
    }

    // ============ Hub pool ============

    function test_hubPool_createdAtInit() public {
        assertEq(store.poolCount(), 1, "exactly the hub pool");
        assertEq(store.getPoolAssets(0).length, 0, "hub starts with no assets");
    }

    // ============ addHubAsset ============

    function test_addHubAsset_listsAndConfigures() public {
        vm.expectEmit(true, true, false, true, address(store));
        emit AssetListed(address(usdc), 0, 6, FEED);

        vm.prank(governor);
        store.addHubAsset(address(usdc), FEED);

        assertTrue(store.isAssetListed(address(usdc)), "listed");
        assertEq(store.assetDecimals(address(usdc)), 6, "decimals frozen");
        assertEq(store.assetScalingFactor(address(usdc)), 1, "scaling 6dp");
        assertEq(store.assetPoolId(address(usdc)), 0, "hub pool");
        assertEq(store.assetPriceFeed(address(usdc)), FEED, "feed");

        address[] memory assets = store.getPoolAssets(0);
        assertEq(assets.length, 1, "asset added to hub");
        assertEq(assets[0], address(usdc), "asset addr");
    }

    function test_addHubAsset_18decimals_scaling() public {
        vm.prank(governor);
        store.addHubAsset(address(dai), FEED);
        assertEq(store.assetDecimals(address(dai)), 18, "18 dp");
        assertEq(store.assetScalingFactor(address(dai)), 1e12, "scaling 18dp");
    }

    function test_addHubAsset_revertsForNonGovernor() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.addHubAsset(address(usdc), FEED);
    }

    function test_addHubAsset_revertsOnZeroAsset() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.addHubAsset(address(0), FEED);
    }

    function test_addHubAsset_revertsOnZeroFeed() public {
        vm.prank(governor);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        store.addHubAsset(address(usdc), address(0));
    }

    function test_addHubAsset_revertsOnDuplicate() public {
        vm.startPrank(governor);
        store.addHubAsset(address(usdc), FEED);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetAlreadyListed.selector, address(usdc)));
        store.addHubAsset(address(usdc), FEED);
        vm.stopPrank();
    }

    function test_addHubAsset_revertsOnUnsupportedDecimals() public {
        MockERC20 weird = new MockERC20("Weird", "WRD", 19);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(NormalizationLib.UnsupportedDecimals.selector, uint8(19)));
        store.addHubAsset(address(weird), FEED);
    }

    function test_addHubAsset_revertsOnHighFeedDecimals() public {
        // Valid 6dp asset, but a feed reporting > 18 decimals must be rejected (would DoS _checkPeg).
        address badFeed = address(new MockAggregatorV3(19, 1e18));
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(NormalizationLib.UnsupportedDecimals.selector, uint8(19)));
        store.addHubAsset(address(usdc), badFeed);
    }

    function test_addHubAsset_multipleAssets() public {
        vm.startPrank(governor);
        store.addHubAsset(address(usdc), FEED);
        store.addHubAsset(address(dai), FEED);
        vm.stopPrank();
        assertEq(store.getPoolAssets(0).length, 2, "two hub assets");
    }

    // ============ Views ============

    function test_getReserve_zeroInitially() public {
        vm.prank(governor);
        store.addHubAsset(address(usdc), FEED);
        assertEq(store.getReserve(0, address(usdc)), 0, "no reserves until M3 deposits");
    }

    function test_getPoolAssets_revertsInvalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.getPoolAssets(5);
    }

    function test_unlistedAsset_views() public {
        assertFalse(store.isAssetListed(address(usdc)), "not listed");
        assertEq(store.assetDecimals(address(usdc)), 0, "default decimals");
        assertEq(store.assetScalingFactor(address(usdc)), 0, "default scaling");
    }
}
