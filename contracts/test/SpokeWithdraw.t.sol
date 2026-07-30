// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P4: spoke withdrawals. LPs burn receipt shares for pro-rata value in a chosen asset
///         (spoke asset, or a hub asset via dlrsReserve). Exits stay live under pause and are never
///         blocked by minDlrsReserve.
contract SpokeWithdrawTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockERC20 internal usdc;
    MockERC20 internal rlusd; // 18dp spoke asset
    MockAggregatorV3 internal feed;

    uint16 internal spoke;

    event SpokeLiquidityRemoved(
        uint16 indexed poolId,
        address indexed provider,
        address indexed asset,
        uint256 sharesBurned,
        uint256 valueUnits,
        uint256 nativeAmount
    );

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        rlusd = new MockERC20("Ripple USD", "RLUSD", 18);
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

    function _depositSpokeAsset(address who, uint256 nativeAmt) internal returns (uint256 shares) {
        vm.startPrank(who);
        rlusd.approve(address(store), nativeAmt);
        shares = store.deposit(spoke, address(rlusd), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    function _fundWithHub(address who, uint256 nativeAmt) internal returns (uint256 shares) {
        vm.startPrank(who);
        usdc.approve(address(store), nativeAmt);
        shares = store.deposit(spoke, address(usdc), nativeAmt, block.timestamp);
        vm.stopPrank();
    }

    // ============ Withdraw the spoke asset ============

    function test_withdrawSpokeAsset_roundTrip() public {
        _depositSpokeAsset(alice, 1_000e18); // 1000e6 shares

        vm.expectEmit(true, true, true, true, address(store));
        emit SpokeLiquidityRemoved(spoke, alice, address(rlusd), 1_000e6, 1_000e6, 1_000e18);
        vm.prank(alice);
        uint256 outNative = store.withdraw(spoke, address(rlusd), 1_000e6, block.timestamp);

        assertEq(outNative, 1_000e18, "got native back");
        assertEq(rlusd.balanceOf(alice), 1_000_000e18, "full round-trip");
        assertEq(store.getReceiptShares(spoke, alice), 0, "shares burned");
        assertEq(store.getReceiptTotalShares(spoke), 0, "total shares 0");
        assertEq(store.getReserve(spoke, address(rlusd)), 0, "reserve drained");
    }

    function test_withdrawSpokeAsset_partial() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(alice);
        uint256 outNative = store.withdraw(spoke, address(rlusd), 400e6, block.timestamp);
        assertEq(outNative, 400e18, "partial native");
        assertEq(store.getReceiptShares(spoke, alice), 600e6, "600 shares left");
        assertEq(store.getReserve(spoke, address(rlusd)), 600e6, "600 reserve left");
    }

    // ============ Withdraw a hub asset (via dlrsReserve) ============

    function test_withdrawHubAsset_fromDlrsReserve() public {
        _fundWithHub(alice, 1_000e6); // dlrsReserve 1000, hub reserve 1000, shares 1000

        vm.prank(alice);
        uint256 outNative = store.withdraw(spoke, address(usdc), 1_000e6, block.timestamp);

        assertEq(outNative, 1_000e6, "paid in usdc");
        assertEq(usdc.balanceOf(alice), 1_000_000e6, "full round-trip in usdc");
        assertEq(store.getDlrsReserve(spoke), 0, "dlrsReserve consumed");
        assertEq(store.getReserve(0, address(usdc)), 0, "hub reserve reduced");
        assertEq(store.getReceiptTotalShares(spoke), 0, "shares burned");
        // DLRS conservation still holds.
        assertEq(dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "conservation");
    }

    // ============ Exit stays live under pause and ignores minDlrsReserve ============

    function test_withdraw_liveUnderGlobalPause() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(guardian);
        store.pause();

        vm.prank(alice);
        uint256 outNative = store.withdraw(spoke, address(rlusd), 1_000e6, block.timestamp);
        assertEq(outNative, 1_000e18, "exit works while globally paused");
    }

    function test_withdraw_notBlockedByMinDlrsReserve() public {
        vm.prank(governor);
        store.setMinDlrsReserve(spoke, 5_000e6); // high floor
        _fundWithHub(alice, 1_000e6); // dlrsReserve 1000 (already below the 5000 floor)

        // Withdrawing takes dlrsReserve to 0, far below the floor, but LP exits are never blocked.
        vm.prank(alice);
        uint256 outNative = store.withdraw(spoke, address(usdc), 1_000e6, block.timestamp);
        assertEq(outNative, 1_000e6, "min floor does not block LP exit");
        assertEq(store.getDlrsReserve(spoke), 0, "dlrsReserve drained below the floor");
    }

    // ============ Reverts ============

    function test_withdraw_revertsInsufficientShares() public {
        _depositSpokeAsset(alice, 1_000e18); // 1000 shares
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReceiptShares.selector, uint256(2_000e6), uint256(1_000e6))
        );
        store.withdraw(spoke, address(rlusd), 2_000e6, block.timestamp);
    }

    function test_withdrawSpokeAsset_revertsWhenReserveShort() public {
        _depositSpokeAsset(alice, 500e18); // spokeReserve 500, shares 500
        _fundWithHub(bob, 1_500e6); // dlrsReserve 1500, shares 1500; pool value 2000, total 2000

        // Bob burns 1000 shares asking for the SPOKE asset: value 1000 > spokeReserve 500 -> revert.
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDollarStore.InsufficientReserves.selector, address(rlusd), uint256(1_000e6), uint256(500e6)
            )
        );
        store.withdraw(spoke, address(rlusd), 1_000e6, block.timestamp);
    }

    function test_withdrawHubAsset_revertsWhenNoDlrsSide() public {
        _depositSpokeAsset(alice, 1_000e18); // dlrsReserve 0

        // Alice asks for usdc but the spoke has no DLRS side yet: value 1000 > available 0.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IDollarStore.InsufficientReserves.selector, address(usdc), uint256(1_000e6), uint256(0)
            )
        );
        store.withdraw(spoke, address(usdc), 1_000e6, block.timestamp);
    }

    function test_withdraw_revertsWrongSpokeAsset() public {
        MockERC20 pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        vm.prank(governor);
        store.createSpoke(address(pyusd), address(feed), 0);
        _depositSpokeAsset(alice, 1_000e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.WrongPool.selector, address(pyusd), spoke));
        store.withdraw(spoke, address(pyusd), 100e6, block.timestamp);
    }

    function test_withdraw_revertsZeroShares() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.withdraw(spoke, address(rlusd), 0, block.timestamp);
    }

    /// @dev Impairs the spoke pool so poolValue << totalShares (via a simulated seizure + syncReserves),
    ///      then burning 1 share redeems to 0 value. The ZeroAmount guard must protect the LP from
    ///      burning shares for nothing. Covers both exit assets.
    function _impairSpokeToDust() internal {
        _depositSpokeAsset(alice, 1_000e18); // spokeReserve 1000e6, total 1000e6 shares
        rlusd.burn(address(store), 999e18); // seizure: store now holds 1e18 rlusd (1e6 units)
        vm.prank(governor);
        store.syncReserves(spoke, address(rlusd)); // reserve 1000e6 -> 1e6 (impaired)
    }

    function test_withdrawSpokeAsset_revertsZeroValueOnImpairment() public {
        _impairSpokeToDust();
        // 1 share against poolValue 1e6 / total 1000e6 rounds to 0.
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.withdraw(spoke, address(rlusd), 1, block.timestamp);
    }

    function test_withdrawHubAsset_revertsZeroValueOnImpairment() public {
        _impairSpokeToDust();
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.withdraw(spoke, address(usdc), 1, block.timestamp);
    }

    function test_withdrawHubAsset_revertsInsufficientShares() public {
        _depositSpokeAsset(alice, 1_000e18); // 1000 shares, dlrsReserve 0
        // Hub-asset exit path (_withdrawSpokeHubAsset) share check, distinct from the spoke-asset path.
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReceiptShares.selector, uint256(2_000e6), uint256(1_000e6))
        );
        store.withdraw(spoke, address(usdc), 2_000e6, block.timestamp);
    }

    function test_withdraw_revertsSpokeAssetFromHub() public {
        // Withdrawing the spoke asset from the hub (poolId 0) is a WrongPool (hub-path branch).
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.WrongPool.selector, address(rlusd), uint16(0)));
        store.withdraw(0, address(rlusd), 100e6, block.timestamp);
    }

    // ============ Hub withdraw unchanged (regression) ============

    function test_hubWithdraw_stillWorks() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        store.deposit(0, address(usdc), 1_000e6, block.timestamp); // hub deposit, mints DLRS
        uint256 outNative = store.withdraw(0, address(usdc), 400e6, block.timestamp);
        vm.stopPrank();
        assertEq(outNative, 400e6, "hub withdraw pays 1:1");
        assertEq(dlrs.balanceOf(alice), 600e6, "DLRS burned on hub withdraw");
    }
}
