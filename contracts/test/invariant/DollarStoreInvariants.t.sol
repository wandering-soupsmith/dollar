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

/// @notice Core protocol invariants under randomized deposit/withdraw/swap/cancel/process sequences.
///   1. DLRS backing: total DLRS supply == sum of hub reserves (escrow is NOT backing).
///   2. Solvency: the contract's token balance covers reserves + queue escrow for every asset.
contract DollarStoreInvariants is StdInvariant, Test {
    DollarStore internal store;
    DLRS internal dlrs;
    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockAggregatorV3 internal feed;
    Handler internal handler;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        feed = new MockAggregatorV3(8, 1e8); // $1, fresh

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        vm.stopPrank();

        address[] memory actors = new address[](3);
        actors[0] = makeAddr("alice");
        actors[1] = makeAddr("bob");
        actors[2] = makeAddr("carol");

        handler = new Handler(store, dlrs, usdc, usdt, actors);
        targetContract(address(handler));
    }

    /// @notice DLRS is backed 1:1 by hub reserves; queue escrow does not back DLRS.
    function invariant_dlrsBackedByReserves() public view {
        uint256 reserveSum = store.getReserve(0, address(usdc)) + store.getReserve(0, address(usdt));
        assertEq(dlrs.totalSupply(), reserveSum, "DLRS supply must equal sum of hub reserves");
    }

    /// @notice The contract holds at least reserves + queue escrow of every asset (never insolvent).
    function invariant_solvency() public view {
        // escrow of an asset == depth of the single queue that offers it (2-asset hub).
        uint256 usdcEscrow = store.getQueueDepth(address(usdc), address(usdt));
        uint256 usdtEscrow = store.getQueueDepth(address(usdt), address(usdc));

        assertGe(
            usdc.balanceOf(address(store)),
            store.getReserve(0, address(usdc)) + usdcEscrow,
            "USDC balance covers reserves + escrow"
        );
        assertGe(
            usdt.balanceOf(address(store)),
            store.getReserve(0, address(usdt)) + usdtEscrow,
            "USDT balance covers reserves + escrow"
        );
    }
}
