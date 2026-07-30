// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockBlacklistERC20} from "./mocks/MockBlacklistERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P6: deposits into a spoke settle the queues the new liquidity can fill, and the
///         blacklist fallback is pool-aware (hub escrow -> DLRS, spoke escrow -> spoke shares).
contract SpokeQueueTriggerTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice"); // LP
    address internal bob = makeAddr("bob"); // queued trader

    MockBlacklistERC20 internal usdc; // 6dp hub
    MockBlacklistERC20 internal rlusd; // 18dp spoke asset
    MockAggregatorV3 internal feed;

    uint16 internal spoke;

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockBlacklistERC20("USD Coin", "USDC", 6);
        rlusd = new MockBlacklistERC20("Ripple USD", "RLUSD", 18);
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

    function _queue(address who, MockBlacklistERC20 offer, MockBlacklistERC20 want, uint256 amt)
        internal
        returns (uint256 queued)
    {
        vm.startPrank(who);
        offer.approve(address(store), amt);
        (, queued) = store.swap(address(offer), address(want), amt, 0, 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Deposit-triggered settlement ============

    function test_depositSpokeAsset_settlesHubToSpokeQueue() public {
        // Bob queues USDC->RLUSD with no spoke liquidity.
        uint256 q = _queue(bob, usdc, rlusd, 500e6);
        assertEq(q, 500e6, "bob queued");

        // Alice deposits the spoke asset; the new reserve settles bob's waiting hub->spoke order.
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        vm.stopPrank();

        assertEq(rlusd.balanceOf(bob), 1_000_000e18 + 500e18, "bob got RLUSD from the deposit");
        assertEq(store.getQueueDepth(address(usdc), address(rlusd)), 0, "queue settled");
        assertEq(store.getDlrsReserve(spoke), 500e6, "dlrsReserve grew (bob's USDC escrow backs it)");
        assertEq(store.getReserve(spoke, address(rlusd)), 500e6, "spoke reserve = 1000 - 500 paid out");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "bob's escrow moved into hub reserves");
        // Alice keeps her full value (settlement is pool-value-neutral).
        assertEq(store.getReceiptShares(spoke, alice), 1_000e6, "alice shares unchanged in value");
        assertEq(dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "conservation");
    }

    function test_fundingDeposit_settlesSpokeToHubQueue() public {
        // Bob queues RLUSD->USDC with no DLRS side.
        uint256 q = _queue(bob, rlusd, usdc, 500e18);
        assertEq(q, 500e6, "bob queued");

        // Alice funds the spoke with a hub asset; the new DLRS side settles bob's spoke->hub order.
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.deposit(spoke, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();

        assertEq(usdc.balanceOf(bob), 1_000_000e6 + 500e6, "bob got USDC from the funding deposit");
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 0, "queue settled");
        assertEq(store.getDlrsReserve(spoke), 500e6, "dlrsReserve = 1000 funded - 500 consumed");
        assertEq(store.getReserve(spoke, address(rlusd)), 500e6, "bob's RLUSD escrow entered the spoke");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "hub reserve = 1000 - 500 paid to bob");
    }

    // ============ Pool-aware blacklist fallback ============

    function test_fallback_spokeEscrow_convertsToSpokeShares() public {
        // Bob queues RLUSD->USDC (escrow = spoke asset), then is blocked from receiving USDC.
        _queue(bob, rlusd, usdc, 500e18);
        usdc.setBlocked(bob, true);

        // Alice funds USDC -> settlement pays bob USDC, which fails -> escrow becomes spoke shares.
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.deposit(spoke, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();

        assertEq(usdc.balanceOf(bob), 1_000_000e6, "bob received no USDC (blocked)");
        assertEq(store.getReceiptShares(spoke, bob), 500e6, "bob's escrow converted to spoke shares");
        assertEq(store.getReserve(spoke, address(rlusd)), 500e6, "escrowed RLUSD moved into the spoke reserve");
        assertEq(store.getQueueDepth(address(rlusd), address(usdc)), 0, "position ejected");
        assertEq(store.getReceiptTotalShares(spoke), 1_500e6, "alice 1000 + bob 500");
        // DLRS conservation intact (fallback did not touch the DLRS side).
        assertEq(dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "conservation");
    }

    function test_fallback_hubEscrow_mintsDlrs() public {
        // Bob queues USDC->RLUSD (escrow = hub asset), then is blocked from receiving RLUSD.
        _queue(bob, usdc, rlusd, 500e6);
        rlusd.setBlocked(bob, true);

        // Alice deposits RLUSD -> settlement pays bob RLUSD, which fails -> escrow becomes a DLRS claim.
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        vm.stopPrank();

        assertEq(rlusd.balanceOf(bob), 1_000_000e18, "bob received no RLUSD (blocked)");
        assertEq(dlrs.balanceOf(bob), 500e6, "bob's hub escrow converted to a DLRS claim");
        assertEq(store.getReserve(0, address(usdc)), 500e6, "escrowed USDC moved into hub reserves");
        assertEq(store.getQueueDepth(address(usdc), address(rlusd)), 0, "position ejected");
        assertEq(store.getReserve(spoke, address(rlusd)), 1_000e6, "spoke reserve untouched (payout failed)");
    }
}
