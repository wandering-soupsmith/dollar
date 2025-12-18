// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DollarStore.sol";
import "../src/DLRS.sol";

/// @title DollarStore Fork Tests
/// @notice Tests using real mainnet USDC and USDT
/// @dev Run with: forge test --fork-url $MAINNET_RPC_URL --match-contract DollarStoreForkTest
contract DollarStoreForkTest is Test {
    DollarStore public dollarStore;
    DLRS public dlrs;

    // Mainnet stablecoin addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    // Whale addresses for impersonation (these hold large balances)
    address constant USDC_WHALE = 0x37305B1cD40574E4C5Ce33f8e8306Be057fD7341;
    address constant USDT_WHALE = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

    address public admin = address(0xAD);
    address public alice = address(0xA11CE);

    function setUp() public {
        // Deploy DollarStore with mainnet stablecoins
        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = USDC;
        initialStablecoins[1] = USDT;

        vm.prank(admin);
        dollarStore = new DollarStore(admin, initialStablecoins);
        dlrs = dollarStore.dlrs();

        // Fund alice with stablecoins from whales
        _fundAlice();
    }

    function _fundAlice() internal {
        // Transfer USDC from whale
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(alice, 100_000e6);

        // Transfer USDT from whale (USDT uses non-standard transfer)
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", alice, 100_000e6));
        require(success, "USDT transfer failed");

        // Approve DollarStore
        vm.startPrank(alice);
        IERC20(USDC).approve(address(dollarStore), type(uint256).max);
        // USDT requires resetting approval to 0 first
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        vm.stopPrank();
    }

    // ============ USDC Tests (6 decimals) ============

    function test_fork_depositUSDC() public {
        uint256 depositAmount = 10_000e6; // 10k USDC

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(USDC, depositAmount);

        assertEq(minted, depositAmount);
        assertEq(dlrs.balanceOf(alice), depositAmount);
        assertEq(dollarStore.getReserve(USDC), depositAmount);
    }

    function test_fork_withdrawUSDC() public {
        uint256 depositAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        vm.startPrank(alice);
        dollarStore.deposit(USDC, depositAmount);

        uint256 balanceBefore = IERC20(USDC).balanceOf(alice);
        dollarStore.withdraw(USDC, withdrawAmount);
        vm.stopPrank();

        assertEq(IERC20(USDC).balanceOf(alice), balanceBefore + withdrawAmount);
        assertEq(dollarStore.getReserve(USDC), depositAmount - withdrawAmount);
    }

    // ============ USDT Tests (6 decimals, non-standard ERC20) ============

    function test_fork_depositUSDT() public {
        uint256 depositAmount = 10_000e6; // 10k USDT

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(USDT, depositAmount);

        assertEq(minted, depositAmount);
        assertEq(dlrs.balanceOf(alice), depositAmount);
        assertEq(dollarStore.getReserve(USDT), depositAmount);
    }

    function test_fork_withdrawUSDT() public {
        uint256 depositAmount = 10_000e6;
        uint256 withdrawAmount = 5_000e6;

        vm.startPrank(alice);
        dollarStore.deposit(USDT, depositAmount);

        uint256 balanceBefore = IERC20(USDT).balanceOf(alice);
        dollarStore.withdraw(USDT, withdrawAmount);
        vm.stopPrank();

        assertEq(IERC20(USDT).balanceOf(alice), balanceBefore + withdrawAmount);
    }

    // ============ Cross-Stablecoin Tests ============

    function test_fork_depositUSDC_withdrawUSDT() public {
        // Alice deposits USDC
        vm.prank(alice);
        dollarStore.deposit(USDC, 10_000e6);

        // Fund reserves with USDT from whale directly
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", address(this), 5_000e6));
        require(success, "USDT transfer failed");

        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 5_000e6);

        // Alice can withdraw USDT even though she deposited USDC
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(alice);

        vm.prank(alice);
        dollarStore.withdraw(USDT, 5_000e6);

        assertEq(IERC20(USDT).balanceOf(alice), usdtBalanceBefore + 5_000e6);
    }

    function test_fork_mixedDepositsAndWithdrawals() public {
        // Deposit both stablecoins
        vm.startPrank(alice);
        dollarStore.deposit(USDC, 25_000e6);
        dollarStore.deposit(USDT, 15_000e6);
        vm.stopPrank();

        // Total DLRS should be sum of all deposits
        uint256 expectedDlrs = 25_000e6 + 15_000e6;
        assertEq(dlrs.balanceOf(alice), expectedDlrs);

        // Check reserves
        assertEq(dollarStore.getReserve(USDC), 25_000e6);
        assertEq(dollarStore.getReserve(USDT), 15_000e6);

        // Withdraw some of each
        vm.startPrank(alice);
        dollarStore.withdraw(USDC, 10_000e6);
        dollarStore.withdraw(USDT, 5_000e6);
        vm.stopPrank();

        // Check remaining reserves
        assertEq(dollarStore.getReserve(USDC), 15_000e6);
        assertEq(dollarStore.getReserve(USDT), 10_000e6);

        // Check remaining DLRS
        uint256 burnedDlrs = 10_000e6 + 5_000e6;
        assertEq(dlrs.balanceOf(alice), expectedDlrs - burnedDlrs);
    }

    // ============ Edge Cases ============

    function test_fork_withdrawExceedsReserves_reverts() public {
        vm.prank(alice);
        dollarStore.deposit(USDC, 1_000e6);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReserves.selector, USDC, 2_000e6, 1_000e6)
        );
        dollarStore.withdraw(USDC, 2_000e6);
    }

    function test_fork_getReserves_returnsCorrectData() public {
        vm.startPrank(alice);
        dollarStore.deposit(USDC, 100e6);
        dollarStore.deposit(USDT, 200e6);
        vm.stopPrank();

        (address[] memory stablecoins, uint256[] memory amounts) = dollarStore.getReserves();

        assertEq(stablecoins.length, 2);

        for (uint256 i = 0; i < stablecoins.length; i++) {
            if (stablecoins[i] == USDC) {
                assertEq(amounts[i], 100e6);
            } else if (stablecoins[i] == USDT) {
                assertEq(amounts[i], 200e6);
            }
        }
    }

    // ============ Queue Fork Tests ============

    function test_fork_joinQueueUSDT() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 10_000e6);

        // Alice joins queue for USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(USDT, 5_000e6);

        assertEq(positionId, 1);
        assertEq(dollarStore.getQueueDepth(USDT), 5_000e6);
        assertEq(dlrs.balanceOf(alice), 5_000e6); // 10k - 5k queued

        (address owner, address stablecoin, uint256 amount,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, alice);
        assertEq(stablecoin, USDT);
        assertEq(amount, 5_000e6);
    }

    function test_fork_cancelQueueReturnsUSDT() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 10_000e6);

        // Alice joins queue for USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(USDT, 5_000e6);

        // Cancel the position
        vm.prank(alice);
        uint256 returned = dollarStore.cancelQueue(positionId);

        assertEq(returned, 5_000e6);
        assertEq(dlrs.balanceOf(alice), 10_000e6); // Full DLRS back
        assertEq(dollarStore.getQueueDepth(USDT), 0);
    }

    function test_fork_queueAutoSettlement() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 10_000e6);

        // Alice joins queue for USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(USDT, 5_000e6);

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Bob deposits USDT - this should fill Alice's queue
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 10_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 8_000e6);
        vm.stopPrank();

        // Alice should have received 5k USDT (her queue position was filled)
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 5_000e6);

        // Position should be deleted
        (address owner,,,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, address(0));

        // Queue should be empty
        assertEq(dollarStore.getQueueDepth(USDT), 0);

        // Remaining 3k USDT goes to reserves
        assertEq(dollarStore.getReserve(USDT), 3_000e6);
    }

    function test_fork_queuePartialFill() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 20_000e6);

        // Alice joins queue for 15k USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(USDT, 15_000e6);

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Bob deposits only 5k USDT
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 5_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 5_000e6);
        vm.stopPrank();

        // Alice should have received 5k USDT (partial fill)
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 5_000e6);

        // Position should show 10k remaining
        (, , uint256 remaining,) = dollarStore.getQueuePosition(positionId);
        assertEq(remaining, 10_000e6);

        // Queue depth should be 10k
        assertEq(dollarStore.getQueueDepth(USDT), 10_000e6);

        // No reserves (all went to queue)
        assertEq(dollarStore.getReserve(USDT), 0);
    }

    function test_fork_crossStablecoinQueue() public {
        // Alice deposits USDC, wants USDT
        vm.prank(alice);
        dollarStore.deposit(USDC, 10_000e6);

        vm.prank(alice);
        dollarStore.joinQueue(USDT, 5_000e6);

        // Bob deposits USDC (not USDT) - should NOT fill Alice's queue
        address bob = address(0xB0B);
        vm.prank(USDC_WHALE);
        IERC20(USDC).transfer(bob, 10_000e6);

        vm.startPrank(bob);
        IERC20(USDC).approve(address(dollarStore), type(uint256).max);
        dollarStore.deposit(USDC, 10_000e6);
        vm.stopPrank();

        // Alice's USDT queue should be unchanged
        assertEq(dollarStore.getQueueDepth(USDT), 5_000e6);

        // USDC goes to reserves
        assertEq(dollarStore.getReserve(USDC), 20_000e6);
    }

    // ============ Swap Fork Tests ============

    function test_fork_swap_instantUSDCtoUSDT() public {
        // Bob deposits USDT to create reserves
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 50_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 50_000e6);
        vm.stopPrank();

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Alice swaps USDC for USDT
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(USDC, USDT, 10_000e6, false);

        assertEq(received, 10_000e6);
        assertEq(positionId, 0);
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 10_000e6);
    }

    function test_fork_swap_queueWhenNoReserves() public {
        // No USDT reserves
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(USDC, USDT, 10_000e6, true);

        assertEq(received, 0);
        assertEq(positionId, 1);
        assertEq(dollarStore.getQueueDepth(USDT), 10_000e6);
        assertEq(dollarStore.getReserve(USDC), 10_000e6);
    }

    function test_fork_swap_partialFillThenQueue() public {
        // Bob deposits only 3k USDT
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 3_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 3_000e6);
        vm.stopPrank();

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Alice swaps 10k USDC for USDT
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(USDC, USDT, 10_000e6, true);

        assertEq(received, 3_000e6);
        assertEq(positionId, 1);
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 3_000e6);
        assertEq(dollarStore.getQueueDepth(USDT), 7_000e6);
    }

    function test_fork_swapFromDLRS_instant() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 20_000e6);

        // Bob deposits USDT
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 10_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 10_000e6);
        vm.stopPrank();

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Alice swaps DLRS for USDT
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(USDT, 5_000e6, false);

        assertEq(received, 5_000e6);
        assertEq(positionId, 0);
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 5_000e6);
        assertEq(dlrs.balanceOf(alice), 15_000e6); // 20k - 5k
    }

    function test_fork_swapFromDLRS_queue() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(USDC, 20_000e6);

        // No USDT reserves

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(USDT, 5_000e6, true);

        assertEq(received, 0);
        assertEq(positionId, 1);
        assertEq(dlrs.balanceOf(alice), 15_000e6); // 20k - 5k burned
        assertEq(dollarStore.getQueueDepth(USDT), 5_000e6);
    }

    function test_fork_swap_fillsQueueOnDeposit() public {
        // Alice swaps USDC for USDT and enters queue
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(USDC, USDT, 10_000e6, true);

        assertEq(received, 0);
        assertEq(positionId, 1);

        uint256 aliceUsdtBefore = IERC20(USDT).balanceOf(alice);

        // Bob deposits USDT - should fill Alice's queue
        address bob = address(0xB0B);
        vm.prank(USDT_WHALE);
        (bool success,) = USDT.call(abi.encodeWithSignature("transfer(address,uint256)", bob, 15_000e6));
        require(success, "USDT transfer failed");

        vm.startPrank(bob);
        (success,) = USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), 0));
        (success,) =
            USDT.call(abi.encodeWithSignature("approve(address,uint256)", address(dollarStore), type(uint256).max));
        dollarStore.deposit(USDT, 15_000e6);
        vm.stopPrank();

        // Alice should have received USDT from queue
        assertEq(IERC20(USDT).balanceOf(alice), aliceUsdtBefore + 10_000e6);
        assertEq(dollarStore.getQueueDepth(USDT), 0);
        assertEq(dollarStore.getReserve(USDT), 5_000e6); // Excess goes to reserves
    }
}
