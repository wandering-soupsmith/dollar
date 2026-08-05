// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DLRS} from "../src/DLRS.sol";

/// @dev Unit tests for the DLRS receipt token in isolation. DLRS is immutable (not upgradeable) and
///      security-relevant (soulbound, mint/burn gated to the DollarStore proxy), so its invariants are
///      pinned here directly rather than only exercised indirectly through the hub/spoke suites.
contract DLRSTest is Test {
    DLRS internal dlrs;

    // This test contract plays the role of the DollarStore proxy (the sole mint/burn authority).
    address internal store;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        store = address(this);
        dlrs = new DLRS(store);
    }

    // ============ Construction / metadata ============

    function test_constructor_setsAuthorityAndMetadata() public view {
        assertEq(dlrs.dollarStore(), store, "dollarStore authority");
        assertEq(dlrs.name(), "Dollar Store Token", "name");
        assertEq(dlrs.symbol(), "DLRS", "symbol");
        assertEq(dlrs.decimals(), 6, "decimals match underlying stablecoins");
        assertEq(dlrs.totalSupply(), 0, "no supply at deploy");
    }

    function test_constructor_revertsOnZeroAuthority() public {
        vm.expectRevert(DLRS.ZeroAddress.selector);
        new DLRS(address(0));
    }

    // ============ Mint / burn authority ============

    function test_mint_onlyDollarStore() public {
        dlrs.mint(alice, 1_000e6);
        assertEq(dlrs.balanceOf(alice), 1_000e6, "alice minted");
        assertEq(dlrs.totalSupply(), 1_000e6, "supply reflects mint");
    }

    function test_mint_revertsForNonAuthority() public {
        vm.prank(alice);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        dlrs.mint(alice, 1_000e6);
    }

    function test_burn_onlyDollarStore() public {
        dlrs.mint(alice, 1_000e6);
        dlrs.burn(alice, 400e6);
        assertEq(dlrs.balanceOf(alice), 600e6, "alice balance after burn");
        assertEq(dlrs.totalSupply(), 600e6, "supply reflects burn");
    }

    function test_burn_revertsForNonAuthority() public {
        dlrs.mint(alice, 1_000e6);
        vm.prank(bob);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        dlrs.burn(alice, 1);
    }

    // ============ Soulbound: transfers and approvals are blocked ============

    function test_transfer_reverts() public {
        dlrs.mint(alice, 1_000e6);
        vm.prank(alice);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.transfer(bob, 1);
    }

    function test_approve_reverts() public {
        vm.prank(alice);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.approve(bob, 1);
    }

    function test_transferFrom_reverts() public {
        dlrs.mint(alice, 1_000e6);
        vm.prank(bob);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.transferFrom(alice, bob, 1);
    }

    function test_allowance_staysZero() public view {
        // approve reverts, so no allowance can ever be set.
        assertEq(dlrs.allowance(alice, bob), 0, "allowance always zero");
    }
}
