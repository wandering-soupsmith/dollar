// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFeeOnTransferERC20} from "./mocks/MockFeeOnTransferERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice M3: hub deposit/withdraw, DLRS mint/burn, decimal normalization, pause exit-path.
contract HubDepositWithdrawTest is Test {
    DollarStore internal store;
    DLRS internal dlrs;

    address internal governor = makeAddr("governor");
    address internal guardian = makeAddr("guardian");
    address internal upgrader = makeAddr("upgrader");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    MockERC20 internal usdc; // 6 decimals
    MockERC20 internal dai; //  18 decimals
    MockAggregatorV3 internal feed; // $1 mock oracle

    event Deposit(
        address indexed user, uint16 indexed poolId, address indexed asset, uint256 nativeAmount, uint256 units
    );
    event Withdraw(
        address indexed user, uint16 indexed poolId, address indexed asset, uint256 units, uint256 nativeAmount
    );

    function setUp() public {
        DollarStore impl = new DollarStore();
        bytes memory initData = abi.encodeCall(DollarStore.initialize, (upgrader, governor, guardian));
        store = DollarStore(address(new ERC1967Proxy(address(impl), initData)));
        dlrs = DLRS(store.dlrs());

        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai", "DAI", 18);

        feed = new MockAggregatorV3(8, 1e8); // $1
        vm.startPrank(governor);
        store.addHubAsset(address(usdc), address(feed));
        store.addHubAsset(address(dai), address(feed));
        vm.stopPrank();

        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        dai.mint(alice, 1_000_000e18);
        dai.mint(bob, 1_000_000e18);
    }

    function _deposit(address who, MockERC20 token, uint256 amount) internal returns (uint256 units) {
        vm.startPrank(who);
        token.approve(address(store), amount);
        units = store.deposit(0, address(token), amount, block.timestamp);
        vm.stopPrank();
    }

    // ============ deposit ============

    function test_deposit_6dp_mintsDlrsAndUpdatesReserve() public {
        // NOTE: cannot use the _deposit() helper here. It calls token.approve() before
        // store.deposit(), and approve emits an Approval event. expectEmit asserts on the
        // NEXT emitted log, so it would match Approval instead of Deposit ("Approval !=
        // expected Deposit"). Inline the approve first, then set expectEmit right before
        // the deposit call so Deposit is the next event emitted.
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);

        vm.expectEmit(true, true, true, true, address(store));
        emit Deposit(alice, 0, address(usdc), 1_000e6, 1_000e6);
        uint256 units = store.deposit(0, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();

        assertEq(units, 1_000e6, "receiptUnits");
        assertEq(dlrs.balanceOf(alice), 1_000e6, "DLRS minted 1:1");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "reserve credited");
        assertEq(usdc.balanceOf(address(store)), 1_000e6, "tokens custodied");
    }

    function test_deposit_18dp_normalizesAndKeepsDust() public {
        uint256 amount = 15e17 + 7; // 1.5 DAI + 7 wei dust
        uint256 aliceBefore = dai.balanceOf(alice);

        uint256 units = _deposit(alice, dai, amount);

        assertEq(units, 15e5, "1.5 in 6dp");
        assertEq(dlrs.balanceOf(alice), 15e5, "DLRS in 6dp");
        assertEq(store.getReserve(0, address(dai)), 15e5, "reserve 6dp");
        assertEq(dai.balanceOf(alice), aliceBefore - 15e17, "only 1.5 pulled, dust kept");
        assertEq(dai.balanceOf(address(store)), 15e17, "native pulled");
    }

    // ============ L-01: swapExactInput minAmountOut is in normalized units ============

    function test_swapExactInput_minAmountOut_isNormalizedUnits() public {
        // Seed DAI (18dp) reserves so a usdc -> dai swap can fill fully from reserves.
        _deposit(bob, dai, 1_000e18); // dai reserve = 1_000e6 (normalized 6dp)

        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);

        // filled is 1_000e6 in normalized 6dp units, and minAmountOut uses the SAME units as swap().
        // A floor just above the normalized fill must revert. Under the old native-unit comparison
        // (amountOut = 1_000e18) this would have wrongly passed.
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.MinAmountNotMet.selector, uint256(1_000e6), uint256(1_000e6 + 1))
        );
        store.swapExactInput(address(usdc), address(dai), 1_000e6, 1_000e6 + 1, block.timestamp);

        // The exact normalized fill as the floor proceeds and delivers native DAI (1_000e18).
        uint256 out = store.swapExactInput(address(usdc), address(dai), 1_000e6, 1_000e6, block.timestamp);
        vm.stopPrank();
        assertEq(out, 1_000e18, "delivers native DAI, floor met in normalized units");
    }

    function test_deposit_revertsZeroUnits() public {
        vm.startPrank(alice);
        dai.approve(address(store), 1e11); // below 1 unit at 18dp (< 1e12)
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.deposit(0, address(dai), 1e11, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_revertsNotListed() public {
        MockERC20 other = new MockERC20("X", "X", 6);
        other.mint(alice, 1e6);
        vm.startPrank(alice);
        other.approve(address(store), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(other)));
        store.deposit(0, address(other), 1e6, block.timestamp);
        vm.stopPrank();
    }

    // U2 (spoke deposit dispatch): depositing into a non-existent pool now reverts InvalidPool, not
    // WrongPool. A hub asset targeted at poolId 1 is no longer inherently "wrong" — if pool 1 were a
    // live spoke it would route to spoke funding (_depositSpokeFunding). It only fails here because
    // pool 1 does not exist, so InvalidPool is the correct error. The WrongPool path (asset of another
    // pool into an existing spoke) is covered in SpokeDeposit.t.sol. Hub deposits (poolId 0) unchanged.
    function test_deposit_revertsInvalidPool_nonexistentPool() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(1)));
        store.deposit(1, address(usdc), 1e6, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_revertsExpiredDeadline() public {
        vm.warp(1000);
        vm.startPrank(alice);
        usdc.approve(address(store), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DeadlineExpired.selector, uint256(999), uint256(1000)));
        store.deposit(0, address(usdc), 1e6, 999);
        vm.stopPrank();
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(guardian);
        store.pause();
        vm.startPrank(alice);
        usdc.approve(address(store), 1e6);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        store.deposit(0, address(usdc), 1e6, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_revertsFeeOnTransfer() public {
        MockFeeOnTransferERC20 fee = new MockFeeOnTransferERC20("Fee", "FEE", 6, 100); // 1%
        vm.prank(governor);
        store.addHubAsset(address(fee), address(feed));
        fee.mint(alice, 1_000e6);

        vm.startPrank(alice);
        fee.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.FeeOnTransferNotSupported.selector, address(fee)));
        store.deposit(0, address(fee), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    // ============ withdraw ============

    function test_withdraw_burnsDlrsAndReturnsAsset() public {
        _deposit(alice, usdc, 1_000e6);

        vm.expectEmit(true, true, true, true, address(store));
        emit Withdraw(alice, 0, address(usdc), 400e6, 400e6);
        vm.prank(alice);
        uint256 out = store.withdraw(0, address(usdc), 400e6, block.timestamp);

        assertEq(out, 400e6, "native out");
        assertEq(dlrs.balanceOf(alice), 600e6, "DLRS burned");
        assertEq(store.getReserve(0, address(usdc)), 600e6, "reserve reduced");
        assertEq(usdc.balanceOf(alice), 1_000_000e6 - 1_000e6 + 400e6, "tokens returned");
    }

    function test_withdraw_18dp_toNative() public {
        _deposit(alice, dai, 2e18); // 2 DAI -> 2e6 units
        vm.prank(alice);
        uint256 out = store.withdraw(0, address(dai), 15e5, block.timestamp); // 1.5 units
        assertEq(out, 15e17, "1.5 DAI native");
        assertEq(store.getReserve(0, address(dai)), 5e5, "0.5 unit left");
    }

    /// @notice DLRS is a claim on the hub basket: deposit one asset, withdraw another.
    function test_withdraw_crossAsset_basketClaim() public {
        _deposit(alice, usdc, 1_000e6); // alice: 1000e6 DLRS, USDC reserve 1000e6
        _deposit(bob, dai, 1_000e18); //  bob:   1000e6 DLRS, DAI reserve 1000e6

        vm.prank(alice);
        uint256 out = store.withdraw(0, address(dai), 500e6, block.timestamp);

        assertEq(out, 500e18, "alice gets DAI she never deposited");
        assertEq(dlrs.balanceOf(alice), 500e6, "alice DLRS down");
        assertEq(store.getReserve(0, address(dai)), 500e6, "DAI reserve down");
    }

    function test_withdraw_revertsInsufficientReserves() public {
        _deposit(alice, usdc, 1_000e6); // alice has DLRS, but DAI reserve is 0
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReserves.selector, address(dai), uint256(100e6), uint256(0))
        );
        store.withdraw(0, address(dai), 100e6, block.timestamp);
    }

    function test_withdraw_revertsInsufficientDlrs() public {
        _deposit(bob, usdc, 1_000e6); // reserve exists; alice has no DLRS
        vm.prank(alice);
        vm.expectRevert(); // ERC20InsufficientBalance from DLRS.burn
        store.withdraw(0, address(usdc), 100e6, block.timestamp);
    }

    function test_withdraw_revertsZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.withdraw(0, address(usdc), 0, block.timestamp);
    }

    /// @notice Withdraw is an exit path: it must keep working while paused.
    function test_withdraw_worksWhenPaused() public {
        _deposit(alice, usdc, 1_000e6);
        vm.prank(guardian);
        store.pause();

        vm.prank(alice);
        uint256 out = store.withdraw(0, address(usdc), 1_000e6, block.timestamp);
        assertEq(out, 1_000e6, "exit works while paused");
        assertEq(dlrs.balanceOf(alice), 0, "fully exited");
    }

    // ============ Invariants / views ============

    /// @notice DLRS total supply equals the sum of hub reserves (1:1 backing) after ops.
    function test_dlrsConservation() public {
        _deposit(alice, usdc, 1_000e6);
        _deposit(bob, dai, 1_000e18);
        vm.prank(alice);
        store.withdraw(0, address(dai), 300e6, block.timestamp);

        uint256 reserveSum = store.getReserve(0, address(usdc)) + store.getReserve(0, address(dai));
        assertEq(dlrs.totalSupply(), reserveSum, "DLRS supply == sum of reserves");
    }

    function test_getReserves_returnsAllHubReserves() public {
        _deposit(alice, usdc, 700e6);
        _deposit(bob, dai, 2e18); // 2e6 units

        (address[] memory assets, uint256[] memory amounts) = store.getReserves(0);
        assertEq(assets.length, 2, "two hub assets");
        assertEq(assets[0], address(usdc));
        assertEq(amounts[0], 700e6, "usdc reserve");
        assertEq(assets[1], address(dai));
        assertEq(amounts[1], 2e6, "dai reserve (6dp)");
    }
}
