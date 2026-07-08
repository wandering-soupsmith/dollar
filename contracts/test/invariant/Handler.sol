// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {DollarStore} from "../../src/DollarStore.sol";
import {DLRS} from "../../src/DLRS.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Invariant handler: performs bounded, randomized deposit/withdraw/swap/cancel/process
///         actions against DollarStore. Reverts are swallowed (fail_on_revert = false) so the
///         fuzzer explores freely while the invariant assertions run between calls.
/// @dev Both assets are 6-decimal (scaling 1), so normalized units == native amounts.
contract Handler is Test {
    DollarStore internal store;
    DLRS internal dlrs;
    MockERC20 internal usdc;
    MockERC20 internal usdt;

    address[] internal actors;
    uint256[] internal positionIds; // best-effort tracking of created queue positions

    uint256 internal constant MAX_AMOUNT = 1_000_000e6; // 1M tokens

    constructor(DollarStore _store, DLRS _dlrs, MockERC20 _usdc, MockERC20 _usdt, address[] memory _actors) {
        store = _store;
        dlrs = _dlrs;
        usdc = _usdc;
        usdt = _usdt;
        actors = _actors;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _pair(bool aFirst) internal view returns (MockERC20 a, MockERC20 b) {
        return aFirst ? (usdc, usdt) : (usdt, usdc);
    }

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
            if (queued > 0) {
                uint256[] memory ps = store.getUserQueuePositions(actor);
                if (ps.length > 0) positionIds.push(ps[ps.length - 1]);
            }
        } catch {}
        vm.stopPrank();
    }

    function cancel(uint256 posSeed) external {
        if (positionIds.length == 0) return;
        uint256 id = positionIds[posSeed % positionIds.length];
        (address owner,,,,) = store.getQueuePosition(id);
        if (owner == address(0)) return; // already filled/cancelled
        vm.startPrank(owner);
        try store.cancelQueue(id) {} catch {}
        vm.stopPrank();
    }

    function process(bool offerUsdc, uint256 maxPositions) external {
        (MockERC20 offer, MockERC20 want) = _pair(offerUsdc);
        maxPositions = bound(maxPositions, 0, 50);
        try store.processQueue(address(offer), address(want), maxPositions) {} catch {}
    }
}
