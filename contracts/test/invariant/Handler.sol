// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {DollarStore} from "../../src/DollarStore.sol";
import {DLRS} from "../../src/DLRS.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Invariant handler: bounded, randomized hub + spoke actions against DollarStore. Reverts are
///         swallowed (fail_on_revert = false) so the fuzzer explores freely while the invariant
///         assertions run between calls. Hub assets are 6dp; the spoke asset (rlusd) is 18dp.
/// @dev Does NOT call impairment paths (syncReserves / haircut / deal) or lifecycle transitions - those
///      intentionally break backing conservation and are covered by unit tests.
contract Handler is Test {
    DollarStore internal store;
    DLRS internal dlrs;
    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockERC20 internal rlusd;
    uint16 internal spokeId;

    address[] internal actors;
    uint256[] internal positionIds; // best-effort tracking of created queue positions

    uint256 internal constant MAX_AMOUNT = 1_000_000e6; // hub assets (6dp)
    uint256 internal constant MAX_AMOUNT_18 = 1_000_000e18; // spoke asset (18dp)

    constructor(
        DollarStore _store,
        DLRS _dlrs,
        MockERC20 _usdc,
        MockERC20 _usdt,
        MockERC20 _rlusd,
        uint16 _spokeId,
        address[] memory _actors
    ) {
        store = _store;
        dlrs = _dlrs;
        usdc = _usdc;
        usdt = _usdt;
        rlusd = _rlusd;
        spokeId = _spokeId;
        actors = _actors;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _pair(bool aFirst) internal view returns (MockERC20 a, MockERC20 b) {
        return aFirst ? (usdc, usdt) : (usdt, usdc);
    }

    function _trackQueued(address actor, uint256 queued) internal {
        if (queued > 0) {
            uint256[] memory ps = store.getUserQueuePositions(actor);
            if (ps.length > 0) positionIds.push(ps[ps.length - 1]);
        }
    }

    // ============ Hub actions ============

    function deposit(uint256 actorSeed, bool useUsdc, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 t = useUsdc ? usdc : usdt;
        amount = bound(amount, 0, MAX_AMOUNT);
        t.mint(actor, amount);
        vm.startPrank(actor);
        t.approve(address(store), amount);
        try store.deposit(0, address(t), amount, type(uint256).max) {} catch {}
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, bool useUsdc, uint256 units) external {
        address actor = _actor(actorSeed);
        MockERC20 t = useUsdc ? usdc : usdt;
        units = bound(units, 0, dlrs.balanceOf(actor));
        vm.startPrank(actor);
        try store.withdraw(0, address(t), units, type(uint256).max) {} catch {}
        vm.stopPrank();
    }

    function swap(uint256 actorSeed, bool offerUsdc, uint256 amount) external {
        address actor = _actor(actorSeed);
        (MockERC20 offer, MockERC20 want) = _pair(offerUsdc);
        amount = bound(amount, 0, MAX_AMOUNT);
        offer.mint(actor, amount);
        vm.startPrank(actor);
        offer.approve(address(store), amount);
        try store.swap(address(offer), address(want), amount, 0, 0, type(uint256).max) returns (
            uint256, uint256 queued
        ) {
            _trackQueued(actor, queued);
        } catch {}
        vm.stopPrank();
    }

    // ============ Spoke actions ============

    function depositSpoke(uint256 actorSeed, uint256 amount) external {
        address actor = _actor(actorSeed);
        amount = bound(amount, 0, MAX_AMOUNT_18);
        rlusd.mint(actor, amount);
        vm.startPrank(actor);
        rlusd.approve(address(store), amount);
        try store.deposit(spokeId, address(rlusd), amount, type(uint256).max) {} catch {}
        vm.stopPrank();
    }

    function fundSpoke(uint256 actorSeed, bool useUsdc, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 t = useUsdc ? usdc : usdt;
        amount = bound(amount, 0, MAX_AMOUNT);
        t.mint(actor, amount);
        vm.startPrank(actor);
        t.approve(address(store), amount);
        try store.deposit(spokeId, address(t), amount, type(uint256).max) {} catch {}
        vm.stopPrank();
    }

    function withdrawSpoke(uint256 actorSeed, bool wantHub, bool useUsdc, uint256 shares) external {
        address actor = _actor(actorSeed);
        shares = bound(shares, 0, store.getReceiptShares(spokeId, actor));
        address want = wantHub ? (useUsdc ? address(usdc) : address(usdt)) : address(rlusd);
        vm.startPrank(actor);
        try store.withdraw(spokeId, want, shares, type(uint256).max) {} catch {}
        vm.stopPrank();
    }

    function swapHubToSpoke(uint256 actorSeed, bool useUsdc, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 offer = useUsdc ? usdc : usdt;
        amount = bound(amount, 0, MAX_AMOUNT);
        offer.mint(actor, amount);
        vm.startPrank(actor);
        offer.approve(address(store), amount);
        try store.swap(address(offer), address(rlusd), amount, 0, 0, type(uint256).max) returns (
            uint256, uint256 queued
        ) {
            _trackQueued(actor, queued);
        } catch {}
        vm.stopPrank();
    }

    function swapSpokeToHub(uint256 actorSeed, bool useUsdc, uint256 amount) external {
        address actor = _actor(actorSeed);
        MockERC20 want = useUsdc ? usdc : usdt;
        amount = bound(amount, 0, MAX_AMOUNT_18);
        rlusd.mint(actor, amount);
        vm.startPrank(actor);
        rlusd.approve(address(store), amount);
        try store.swap(address(rlusd), address(want), amount, 0, 0, type(uint256).max) returns (
            uint256, uint256 queued
        ) {
            _trackQueued(actor, queued);
        } catch {}
        vm.stopPrank();
    }

    // ============ Shared: cancel + process ============

    function cancel(uint256 posSeed) external {
        if (positionIds.length == 0) return;
        uint256 id = positionIds[posSeed % positionIds.length];
        (address owner,,,,) = store.getQueuePosition(id);
        if (owner == address(0)) return; // already filled/cancelled
        vm.startPrank(owner);
        try store.cancelQueue(id) {} catch {}
        vm.stopPrank();
    }

    function process(uint256 routeSeed, uint256 maxPositions) external {
        maxPositions = bound(maxPositions, 0, 50);
        address offer;
        address want;
        uint256 r = routeSeed % 4;
        if (r == 0) (offer, want) = (address(usdc), address(usdt));
        else if (r == 1) (offer, want) = (address(usdt), address(usdc));
        else if (r == 2) (offer, want) = (address(rlusd), address(usdc));
        else (offer, want) = (address(usdc), address(rlusd));
        try store.processQueue(offer, want, maxPositions) {} catch {}
    }
}
