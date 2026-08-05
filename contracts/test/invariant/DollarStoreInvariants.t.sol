// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../../src/DollarStore.sol";
import {DLRS} from "../../src/DLRS.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockAggregatorV3} from "../mocks/MockAggregatorV3.sol";
import {Handler} from "./Handler.sol";

/// @notice Core protocol invariants under randomized hub + spoke sequences (U2).
///   1. DLRS backing conservation: total DLRS supply + sum of spoke dlrsReserve == sum of hub reserves.
///      (Queue escrow is NOT backing; spoke assets never back the hub.)
///   2. Solvency: the contract's token balance covers reserves + queue escrow for every asset.
/// @dev The handler never triggers the impairment paths (syncReserves / haircut), which intentionally
///      break backing conservation, so both invariants hold across the explored space.
contract DollarStoreInvariants is StdInvariant, Test {
    DollarStore internal store;
    DLRS internal dlrs;
    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockERC20 internal rlusd; // 18dp spoke asset
    MockAggregatorV3 internal feed;
    Handler internal handler;

    uint16 internal spoke;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
        feed = new MockAggregatorV3(8, 1e8); // $1, fresh

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        spoke = store.createSpoke(address(rlusd), address(feed), 0);
        vm.stopPrank();

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("alice");
        actors[1] = makeAddr("bob");
        actors[2] = makeAddr("carol");

        handler = new Handler(store, dlrs, usdc, usdt, rlusd, spoke, actors);
        targetContract(address(handler));
    }

    /// @notice Every DLRS-denominated claim (wallet DLRS + each spoke's dlrsReserve) is backed 1:1 by
    ///         hub reserves. Queue escrow and spoke-asset reserves are NOT part of this backing.
    function invariant_dlrsBackingConservation() public view {
        uint256 hubReserves = store.getReserve(0, address(usdc)) + store.getReserve(0, address(usdt));
        uint256 dlrsClaims = dlrs.totalSupply() + store.getDlrsReserve(spoke);
        assertEq(dlrsClaims, hubReserves, "DLRS supply + spoke dlrsReserve must equal hub reserves");
    }

    /// @notice The contract holds at least reserves + queue escrow of every asset (never insolvent).
    function invariant_solvency() public view {
        _assertSolvent(usdc, 0, 1); // 6dp -> scaling 1
        _assertSolvent(usdt, 0, 1);
        _assertSolvent(rlusd, spoke, 1e12); // 18dp -> scaling 1e12
    }

    function _assertSolvent(MockERC20 asset, uint16 poolId, uint256 scaling) internal view {
        uint256 escrowUnits = _escrowUnits(address(asset));
        uint256 accountedNative = (store.getReserve(poolId, address(asset)) + escrowUnits) * scaling;
        assertGe(asset.balanceOf(address(store)), accountedNative, "balance covers reserves + escrow");
    }

    /// @dev Total queue escrow of `asset` = sum of the depths of every queue where it is the offer.
    function _escrowUnits(address asset) internal view returns (uint256) {
        address[3] memory all = [address(usdc), address(usdt), address(rlusd)];
        uint256 total;
        for (uint256 i; i < all.length; ++i) {
            if (all[i] == asset) continue;
            total += store.getQueueDepth(asset, all[i]);
        }
        return total;
    }
}
