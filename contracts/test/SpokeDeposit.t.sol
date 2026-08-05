// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {DollarStore} from "../src/DollarStore.sol";
import {IDollarStore} from "../src/interfaces/IDollarStore.sol";
import {DLRS} from "../src/DLRS.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAggregatorV3} from "./mocks/MockAggregatorV3.sol";

/// @notice U2 P3: spoke deposits. Spoke-asset LP enters the spoke reserve; hub-asset LP funds the
///         spoke's dlrsReserve. Both mint pro-rata receipt shares. No wallet DLRS for spoke LPs.
contract SpokeDepositTest is Test {
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

    event SpokeLiquidityAdded(
        uint16 indexed poolId,
        address indexed provider,
        address indexed asset,
        uint256 nativeAmount,
        uint256 valueUnits,
        uint256 sharesMinted
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

    // ============ Spoke-asset LP ============

    function test_depositSpokeAsset_firstLP_1to1() public {
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        vm.expectEmit(true, true, true, true, address(store));
        emit SpokeLiquidityAdded(spoke, alice, address(rlusd), 1_000e18, 1_000e6, 1_000e6);
        uint256 shares = store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        vm.stopPrank();

        assertEq(shares, 1_000e6, "first LP mints shares 1:1 with value");
        assertEq(store.getReceiptShares(spoke, alice), 1_000e6, "alice shares");
        assertEq(store.getReceiptTotalShares(spoke), 1_000e6, "total shares");
        assertEq(store.getReserve(spoke, address(rlusd)), 1_000e6, "spoke reserve credited (6dp units)");
        assertEq(store.getDlrsReserve(spoke), 0, "no dlrs side yet");
        assertEq(dlrs.balanceOf(alice), 0, "spoke LP gets NO wallet DLRS");
        assertEq(dlrs.totalSupply(), 0, "no DLRS minted");
    }

    function test_depositSpokeAsset_secondLP_proportional() public {
        _depositSpokeAsset(alice, 1_000e18); // 1000 value, 1000 shares
        uint256 bobShares = _depositSpokeAsset(bob, 500e18); // pool value 1000 -> 500*1000/1000 = 500
        assertEq(bobShares, 500e6, "proportional shares");
        assertEq(store.getReceiptTotalShares(spoke), 1_500e6, "total shares");
        assertEq(store.getReserve(spoke, address(rlusd)), 1_500e6, "reserve");
    }

    // ============ Hub-asset LP (funds dlrsReserve) ============

    function test_depositSpokeFunding_creditsHubAndDlrsReserve() public {
        uint256 shares = _fundWithHub(alice, 1_000e6);

        assertEq(shares, 1_000e6, "first LP 1:1");
        assertEq(store.getDlrsReserve(spoke), 1_000e6, "dlrsReserve credited");
        assertEq(store.getReserve(0, address(usdc)), 1_000e6, "hub reserve holds the funding asset");
        assertEq(store.getReserve(spoke, address(usdc)), 0, "funding asset does NOT sit in the spoke reserve");
        assertEq(dlrs.balanceOf(alice), 0, "no wallet DLRS to the spoke LP");
        // DLRS conservation: wallet supply + spoke dlrsReserve == hub reserves.
        assertEq(
            dlrs.totalSupply() + store.getDlrsReserve(spoke), store.getReserve(0, address(usdc)), "DLRS conservation"
        );
    }

    function test_deposit_mixed_valueIsSpokePlusDlrs() public {
        _depositSpokeAsset(alice, 1_000e18); // spokeReserve 1000, dlrs 0, shares 1000
        uint256 bobShares = _fundWithHub(bob, 1_000e6); // poolValueBefore = 1000, shares = 1000
        assertEq(bobShares, 1_000e6, "shares vs full pool value (spoke + dlrs)");
        assertEq(store.getReserve(spoke, address(rlusd)), 1_000e6, "spoke reserve");
        assertEq(store.getDlrsReserve(spoke), 1_000e6, "dlrs reserve");
        assertEq(store.getReceiptTotalShares(spoke), 2_000e6, "total shares");
    }

    // ============ Guards ============

    function test_deposit_revertsWrongSpokeAsset() public {
        MockERC20 pyusd = new MockERC20("PayPal USD", "PYUSD", 6);
        vm.prank(governor);
        store.createSpoke(address(pyusd), address(feed), 0); // spoke B (poolId 2)

        // Depositing spoke B's asset into spoke A must revert WrongPool.
        pyusd.mint(alice, 1_000e6);
        vm.startPrank(alice);
        pyusd.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.WrongPool.selector, address(pyusd), spoke));
        store.deposit(spoke, address(pyusd), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_revertsZeroAmount() public {
        vm.startPrank(alice);
        rlusd.approve(address(store), 1);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.deposit(spoke, address(rlusd), 0, block.timestamp);
        vm.stopPrank();
    }

    /// @notice ZeroAmount guard on the hub-asset funding path (_depositSpokeFunding), distinct from the
    ///         spoke-asset path above.
    function test_depositSpokeFunding_revertsZeroAmount() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        store.deposit(spoke, address(usdc), 0, block.timestamp);
        vm.stopPrank();
    }

    // ============ Pool-aware launch cap (spoke exposure = spokeReserve + dlrsReserve) ============

    function test_spokeLaunchCap_capsSpokeExposure() public {
        vm.prank(governor);
        store.setLaunchCap(spoke, 1_000e6); // cap the spoke's exposure

        // At the cap (exposure 1000 == cap) is allowed.
        _depositSpokeAsset(alice, 1_000e18);
        assertEq(store.getReserve(spoke, address(rlusd)), 1_000e6, "at-cap spoke deposit allowed");

        // One more unit pushes spoke exposure (reserve + dlrsReserve) over the cap.
        vm.startPrank(bob);
        rlusd.approve(address(store), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.LaunchCapExceeded.selector, spoke, uint256(1_001e6), uint256(1_000e6))
        );
        store.deposit(spoke, address(rlusd), 1e18, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_intoKilledSpoke_reverts() public {
        vm.prank(governor);
        store.removePool(spoke); // paused + assets unlisted

        // Spoke asset is now unlisted.
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.AssetNotListed.selector, address(rlusd)));
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        // Hub-asset funding into a killed (paused) spoke is blocked by the pool-pause check.
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolPaused.selector, spoke));
        store.deposit(spoke, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_invalidSpoke_reverts() public {
        vm.startPrank(alice);
        usdc.approve(address(store), 1_000e6);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InvalidPool.selector, uint16(9)));
        store.deposit(9, address(usdc), 1_000e6, block.timestamp);
        vm.stopPrank();
    }

    function test_deposit_globalPause_blocksSpokeDeposit() public {
        vm.prank(guardian);
        store.pause();
        vm.startPrank(alice);
        rlusd.approve(address(store), 1_000e18);
        vm.expectRevert(); // EnforcedPause
        store.deposit(spoke, address(rlusd), 1_000e18, block.timestamp);
        vm.stopPrank();
    }

    // ============ removePool now blocked when the spoke has state (deferred from P2) ============

    function test_removePool_revertsWhenNotEmpty() public {
        _depositSpokeAsset(alice, 1_000e18);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotEmpty.selector, spoke));
        store.removePool(spoke);
    }

    function test_removePool_revertsWhenDlrsReserveNonZero() public {
        _fundWithHub(alice, 1_000e6);
        vm.prank(governor);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.PoolNotEmpty.selector, spoke));
        store.removePool(spoke);
    }
}
