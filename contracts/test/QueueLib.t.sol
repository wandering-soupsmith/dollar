// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {QueueLib} from "../src/libraries/QueueLib.sol";

contract QueueLibTest is Test {
    function test_minimumOrderSize_tiers() public {
        assertEq(QueueLib.minimumOrderSize(0), 500e6, "tier 0");
        assertEq(QueueLib.minimumOrderSize(24), 500e6, "still tier 0");
        assertEq(QueueLib.minimumOrderSize(25), 5_000e6, "tier 1");
        assertEq(QueueLib.minimumOrderSize(49), 5_000e6, "still tier 1");
        assertEq(QueueLib.minimumOrderSize(50), 50_000e6, "tier 2");
        assertEq(QueueLib.minimumOrderSize(125), 50_000_000e6, "tier 5");
    }
}
