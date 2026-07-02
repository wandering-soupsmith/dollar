// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M6: temporary launch exposure caps (hub cap == total DLRS supply). Queue escrow excluded.
contract LaunchCapsTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockERC20 internal usdc;
    MockERC20 internal usdt;
    MockAggregatorV3 internal feed;

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        usdt = new MockERC20("Tether", "USDT", 6);
        feed = new MockAggregatorV3(8, 1e8); // $1

        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(usdt), address(feed));
        vm.stopPrank();

        usdc.mint(alice, 1_000_000e6);
        usdt.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdt.mint(bob, 1_000_000e6);
    }

    function _deposit(address who, MockERC20 token, uint256 amt) internal {
        vm.startPrank(who);
        token.approve(address(store), amt);
        store.deposit(0, address(token), amt, block.timestamp);
        vm.stopPrank();
    }

    // ============ Defaults ============

    function test_noCapByDefault() public {
        assertEq(store.getLaunchCap(0), 0, "uncapped by default");
        _deposit(alice, usdc, 500_000e6); // large deposit works with no cap
        assertEq(store.getReserve(0, address(usdc)), 500_000e6);
    }

    // ============ Enforcement ============

    function test_cap_blocksOverLimitDeposit() public {
        vm.prank(governor);
        store.setLaunchCap(0, 1_000e6);

        _deposit(alice, usdc, 600e6); // exposure 600 <= 1000, ok

        vm.startPrank(alice);
        usdc.approve(address(store), 500e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDollarStore.LaunchCapExceeded.selector, uint16(0), uint256(1_100e6), uint256(1_000e6)
            )
        );
        store.deposit(0, address(usdc), 500e6, block.timestamp); // 600 + 500 = 1100 > 1000
        vm.stopPrank();
    }

    function test_cap_countsExistingExposureAcrossAssets() public {
        _deposit(alice, usdc, 800e6); // exposure 800 (DLRS supply)
        vm.prank(governor);
        store.setLaunchCap(0, 1_000e6);

        // A different asset still counts against the same hub cap.
        vm.startPrank(bob);
        usdt.approve(address(store), 300e6);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDollarStore.LaunchCapExceeded.selector, uint16(0), uint256(1_100e6), uint256(1_000e6)
            )
        );
        store.deposit(0, address(usdt), 300e6, block.timestamp);
        vm.stopPrank();
    }

    function test_cap_removeWithZero() public {
        vm.startPrank(governor);
        store.setLaunchCap(0, 1_000e6);
        store.setLaunchCap(0, 0); // remove
        vm.stopPrank();
        assertEq(store.getLaunchCap(0), 0);
        _deposit(alice, usdc, 500_000e6); // works again
    }

    // ============ Roles ============

    function test_setLaunchCap_onlyGovernor() public {
        vm.prank(guardian);
        vm.expectRevert(IDollarStore.OnlyGovernor.selector);
        store.setLaunchCap(0, 1_000e6);
    }

    function test_lowerLaunchCap_guardianTightens() public {
        vm.prank(governor);
        store.setLaunchCap(0, 1_000e6);

        vm.prank(guardian);
        store.lowerLaunchCap(0, 500e6);
        assertEq(store.getLaunchCap(0), 500e6);

        // Now 600 exceeds the tightened cap.
        vm.startPrank(alice);
        usdc.approve(address(store), 600e6);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.LaunchCapExceeded.selector, uint16(0), uint256(600e6), uint256(500e6))
        );
        store.deposit(0, address(usdc), 600e6, block.timestamp);
        vm.stopPrank();
    }

    function test_lowerLaunchCap_fromUncapped() public {
        // No cap set: guardian can impose one (stricter than "unlimited").
        vm.prank(guardian);
        store.lowerLaunchCap(0, 500e6);
        assertEq(store.getLaunchCap(0), 500e6);
    }

    function test_lowerLaunchCap_mustBeStricter() public {
        vm.prank(governor);
        store.setLaunchCap(0, 1_000e6);

        vm.startPrank(guardian);
        // Equal is not stricter.
        vm.expectRevert(IDollarStore.CapNotStricter.selector);
        store.lowerLaunchCap(0, 1_000e6);
        // Higher is looser.
        vm.expectRevert(IDollarStore.CapNotStricter.selector);
        store.lowerLaunchCap(0, 2_000e6);
        // Zero would remove.
        vm.expectRevert(IDollarStore.CapNotStricter.selector);
        store.lowerLaunchCap(0, 0);
        vm.stopPrank();
    }

    function test_lowerLaunchCap_onlyGuardian() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.OnlyGuardian.selector);
        store.lowerLaunchCap(0, 500e6);
    }

    // ============ Swaps are not capped ============

    function test_swap_notSubjectToCap() public {
        // Fill the hub to the cap with deposits, then swap (reserve-neutral, no new DLRS).
        _deposit(alice, usdc, 1_000e6); // exposure 1000
        vm.prank(governor);
        store.setLaunchCap(0, 1_000e6); // at the limit

        // bob swaps USDT->USDC: fills from USDC reserves, mints no DLRS -> exposure unchanged.
        vm.startPrank(bob);
        usdt.approve(address(store), 500e6);
        (uint256 filled,) = store.swap(address(usdt), address(usdc), 500e6, 0, 0, block.timestamp);
        vm.stopPrank();

        assertEq(filled, 500e6, "swap fills despite cap");
        assertEq(dlrs.totalSupply(), 1_000e6, "exposure unchanged by swap");
    }

    // ============ Invalid pool ============

    function test_getLaunchCap_invalidPool() public {
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.getLaunchCap(5);
    }

    function test_setLaunchCap_invalidPool() public {
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.setLaunchCap(5, 1_000e6);
    }

    function test_lowerLaunchCap_invalidPool() public {
        // cap != 0 so the bounds-check (not the CapNotStricter zero-guard) is what reverts.
        vm.prank(guardian);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(5)));
        store.lowerLaunchCap(5, 500e6);
    }
}
