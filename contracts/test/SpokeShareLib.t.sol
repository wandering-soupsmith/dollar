// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SpokeShareLib} from "../src/libraries/SpokeShareLib.sol";

/// @dev External wrapper around the INTERNAL library functions. vm.expectRevert only matches a revert
///      that happens in a call at a depth BELOW the cheatcode; an inlined internal library call reverts
///      at the test's own depth, so revert cases must cross an external boundary via this harness.
contract SpokeShareLibHarness {
    function sharesForDeposit(uint256 valueIn, uint256 poolValueBefore, uint256 totalShares)
        external
        pure
        returns (uint256)
    {
        return SpokeShareLib.sharesForDeposit(valueIn, poolValueBefore, totalShares);
    }

    function valueForShares(uint256 sharesIn, uint256 poolValue, uint256 totalShares) external pure returns (uint256) {
        return SpokeShareLib.valueForShares(sharesIn, poolValue, totalShares);
    }
}

/// @notice U2 P1: pure share math for non-transferable spoke LP receipts. Rounding is always against
///         the caller, so no deposit/withdraw round-trip can extract more value than it put in.
contract SpokeShareLibTest is Test {
    uint256 internal constant CAP = 1e30; // keep fuzz inputs in a realistic, meaningful range

    SpokeShareLibHarness internal h; // external wrapper, only needed for the revert cases

    function setUp() public {
        h = new SpokeShareLibHarness();
    }

    // ============ First deposit ============

    function test_firstDeposit_mints1to1() public {
        assertEq(SpokeShareLib.sharesForDeposit(1_000e6, 0, 0), 1_000e6, "empty pool mints 1:1");
    }

    function testFuzz_firstDeposit_1to1(uint256 valueIn) public {
        valueIn = bound(valueIn, 1, CAP);
        assertEq(SpokeShareLib.sharesForDeposit(valueIn, 0, 0), valueIn, "first LP is 1:1");
    }

    // ============ Core safety: a deposit+withdraw round-trip can never gain ============

    function testFuzz_roundTrip_neverGains(uint256 valueIn, uint256 poolValue, uint256 totalShares) public {
        valueIn = bound(valueIn, 1, CAP);
        poolValue = bound(poolValue, 1, CAP);
        totalShares = bound(totalShares, 1, CAP);
        vm.assume(Math.mulDiv(valueIn, totalShares, poolValue) > 0); // otherwise DepositTooSmall

        uint256 shares = SpokeShareLib.sharesForDeposit(valueIn, poolValue, totalShares);
        // Redeem those exact shares against the post-deposit pool.
        uint256 out = SpokeShareLib.valueForShares(shares, poolValue + valueIn, totalShares + shares);

        assertLe(out, valueIn, "round-trip must never return more than deposited");
    }

    // ============ No holder set can extract more than the pool holds ============

    function testFuzz_noOverExtraction(uint256 s1, uint256 s2, uint256 poolValue) public {
        s1 = bound(s1, 1, CAP);
        s2 = bound(s2, 1, CAP);
        poolValue = bound(poolValue, 1, CAP);
        uint256 total = s1 + s2;

        uint256 v1 = SpokeShareLib.valueForShares(s1, poolValue, total);
        uint256 v2 = SpokeShareLib.valueForShares(s2, poolValue, total);

        assertLe(v1 + v2, poolValue, "sum of redemptions cannot exceed pool value");
    }

    // ============ Monotonicity: a larger deposit never mints fewer shares ============

    function testFuzz_monotonic_moreValueMoreShares(uint256 v1, uint256 v2, uint256 poolValue, uint256 totalShares)
        public
    {
        poolValue = bound(poolValue, 1, CAP);
        totalShares = bound(totalShares, 1, CAP);
        v1 = bound(v1, 1, CAP);
        v2 = bound(v2, v1, CAP); // v2 >= v1
        vm.assume(Math.mulDiv(v1, totalShares, poolValue) > 0);

        uint256 s1 = SpokeShareLib.sharesForDeposit(v1, poolValue, totalShares);
        uint256 s2 = SpokeShareLib.sharesForDeposit(v2, poolValue, totalShares);
        assertGe(s2, s1, "more value -> at least as many shares");
    }

    // ============ Value impairment is shared pro-rata ============

    function test_impairment_sharesLoseValue() public {
        // Pool value written down to half of the outstanding shares: each share redeems 0.5.
        uint256 total = 100e6;
        uint256 impairedValue = 50e6;
        assertEq(SpokeShareLib.valueForShares(total, impairedValue, total), 50e6, "full burn pays impaired value");
        assertEq(SpokeShareLib.valueForShares(40e6, impairedValue, total), 20e6, "partial burn is pro-rata of loss");
    }

    // ============ sharesForDepositOrZero (fallback variant: returns 0 instead of reverting) ============

    function test_sharesForDepositOrZero_zeroValue() public pure {
        assertEq(SpokeShareLib.sharesForDepositOrZero(0, 1_000e6, 1_000e6), 0, "zero value -> 0 shares");
    }

    function test_sharesForDepositOrZero_firstLP() public pure {
        assertEq(SpokeShareLib.sharesForDepositOrZero(1_000e6, 0, 0), 1_000e6, "first LP into empty pool is 1:1");
    }

    function test_sharesForDepositOrZero_proportional() public pure {
        assertEq(SpokeShareLib.sharesForDepositOrZero(500e6, 1_000e6, 1_000e6), 500e6, "pro-rata against pool value");
    }

    /// @notice The whole point of the OrZero variant: extreme dust that would revert DepositTooSmall in
    ///         sharesForDeposit returns 0 here, so the blacklist-eject fallback never bricks the queue.
    function test_sharesForDepositOrZero_extremeDustReturnsZero() public pure {
        // valueIn * totalShares < poolValue -> floor is 0. sharesForDeposit would revert here.
        assertEq(SpokeShareLib.sharesForDepositOrZero(1, 1_000e6, 1), 0, "extreme dust -> 0 shares, no revert");
    }

    // ============ Reverts ============

    function test_sharesForDeposit_revertsZeroValue() public {
        vm.expectRevert(SpokeShareLib.ZeroValue.selector);
        h.sharesForDeposit(0, 1_000e6, 1_000e6);
    }

    function test_sharesForDeposit_revertsDepositTooSmall() public {
        // valueIn * totalShares < poolValue => floor is 0 => DepositTooSmall.
        vm.expectRevert(SpokeShareLib.DepositTooSmall.selector);
        h.sharesForDeposit(1, 1_000e6, 1);
    }

    function test_valueForShares_revertsZeroShares() public {
        vm.expectRevert(SpokeShareLib.ZeroShares.selector);
        h.valueForShares(0, 1_000e6, 1_000e6);
    }

    function test_valueForShares_revertsInsufficientShares() public {
        vm.expectRevert(
            abi.encodeWithSelector(SpokeShareLib.InsufficientShares.selector, uint256(1_001e6), uint256(1_000e6))
        );
        h.valueForShares(1_001e6, 1_000e6, 1_000e6);
    }
}
