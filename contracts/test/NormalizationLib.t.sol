// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {NormalizationLib} from "../src/libraries/NormalizationLib.sol";

/// @dev External wrapper so `vm.expectRevert` works on a real call boundary (internal library
///      calls are inlined and would not be caught by expectRevert).
contract NormLibHarness {
    function scalingFactor(uint8 d) external pure returns (uint64) {
        return NormalizationLib.scalingFactor(d);
    }

    function toUnits(uint256 n, uint64 s) external pure returns (uint256, uint256) {
        return NormalizationLib.toUnits(n, s);
    }

    function toNative(uint256 u, uint64 s) external pure returns (uint256) {
        return NormalizationLib.toNative(u, s);
    }
}

contract NormalizationLibTest is Test {
    NormLibHarness internal n;

    function setUp() public {
        n = new NormLibHarness();
    }

    function test_scalingFactor_values() public {
        assertEq(n.scalingFactor(6), 1, "6dp");
        assertEq(n.scalingFactor(8), 100, "8dp");
        assertEq(n.scalingFactor(18), 1e12, "18dp");
    }

    function test_scalingFactor_revertsBelowMin() public {
        vm.expectRevert(abi.encodeWithSelector(NormalizationLib.UnsupportedDecimals.selector, uint8(5)));
        n.scalingFactor(5);
    }

    function test_scalingFactor_revertsAboveMax() public {
        vm.expectRevert(abi.encodeWithSelector(NormalizationLib.UnsupportedDecimals.selector, uint8(19)));
        n.scalingFactor(19);
    }

    function test_toUnits_6dp_identity() public {
        (uint256 units, uint256 pulled) = n.toUnits(1_000e6, 1);
        assertEq(units, 1_000e6, "units");
        assertEq(pulled, 1_000e6, "pulled");
    }

    /// @notice An 18dp deposit with sub-unit dust: dust below 1e12 wei cannot be represented at
    ///         6dp and must stay with the user (round down).
    function test_toUnits_18dp_dustStaysWithUser() public {
        uint64 sf = 1e12;
        uint256 native = 15e17 + 7; // 1.5 tokens (18dp) + 7 wei dust
        (uint256 units, uint256 pulled) = n.toUnits(native, sf);
        assertEq(units, 15e5, "1.5 in 6dp = 1_500_000");
        assertEq(pulled, 15e17, "pulled drops the dust");
        assertEq(native - pulled, 7, "7 wei dust stays with user");
    }

    function test_toNative_roundTrip() public {
        assertEq(n.toNative(1_500_000, 1e12), 15e17, "6dp -> 18dp native");
    }

    /// @notice Property: the protocol never pulls more than provided, and re-expanding the
    ///         normalized units reproduces exactly the pulled native amount (no value created).
    function testFuzz_roundTripNoInflation(uint256 native, uint8 decimals_) public {
        decimals_ = uint8(bound(decimals_, 6, 18));
        uint64 sf = n.scalingFactor(decimals_);
        native = bound(native, 0, 1e30);

        (uint256 units, uint256 pulled) = n.toUnits(native, sf);
        assertLe(pulled, native, "never pull more than provided");
        assertEq(n.toNative(units, sf), pulled, "round-trip is exact");
    }
}
