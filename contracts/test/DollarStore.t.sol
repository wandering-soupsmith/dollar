// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DollarStore.sol";
import "../src/DLRS.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Mock stablecoin for testing
contract MockStablecoin is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract DollarStoreTest is Test {
    DollarStore public dollarStore;
    DLRS public dlrs;

    MockStablecoin public usdc;
    MockStablecoin public usdt;

    address public admin = address(0xAD);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    uint256 constant INITIAL_BALANCE = 1_000_000e6;

    function setUp() public {
        // Deploy mock stablecoins
        usdc = new MockStablecoin("USD Coin", "USDC", 6);
        usdt = new MockStablecoin("Tether USD", "USDT", 6);

        // Deploy DollarStore with initial stablecoins
        address[] memory initialStablecoins = new address[](2);
        initialStablecoins[0] = address(usdc);
        initialStablecoins[1] = address(usdt);

        vm.prank(admin);
        dollarStore = new DollarStore(admin, initialStablecoins);
        dlrs = dollarStore.dlrs();

        // Mint tokens to test users
        usdc.mint(alice, INITIAL_BALANCE);
        usdt.mint(alice, INITIAL_BALANCE);

        usdc.mint(bob, INITIAL_BALANCE);
        usdt.mint(bob, INITIAL_BALANCE);

        // Approve DollarStore to spend tokens
        vm.startPrank(alice);
        usdc.approve(address(dollarStore), type(uint256).max);
        usdt.approve(address(dollarStore), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(dollarStore), type(uint256).max);
        usdt.approve(address(dollarStore), type(uint256).max);
        vm.stopPrank();
    }

    // ============ Constructor Tests ============

    function test_constructor_setsAdmin() public view {
        assertEq(dollarStore.admin(), admin);
    }

    function test_constructor_deploysDLRS() public view {
        assertTrue(address(dlrs) != address(0));
        assertEq(dlrs.name(), "Dollar Store Token");
        assertEq(dlrs.symbol(), "DLRS");
        assertEq(dlrs.decimals(), 18);
    }

    function test_constructor_setsInitialStablecoins() public view {
        assertTrue(dollarStore.isSupported(address(usdc)));
        assertTrue(dollarStore.isSupported(address(usdt)));

        address[] memory supported = dollarStore.supportedStablecoins();
        assertEq(supported.length, 2);
    }

    function test_constructor_revertsOnZeroAdmin() public {
        address[] memory stablecoins = new address[](0);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        new DollarStore(address(0), stablecoins);
    }

    // ============ Deposit Tests ============

    function test_deposit_mintsCorrectDLRS() public {
        uint256 depositAmount = 1000e6;

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(address(usdc), depositAmount);

        assertEq(minted, depositAmount);
        assertEq(dlrs.balanceOf(alice), depositAmount);
    }

    function test_deposit_updatesReserves() public {
        uint256 depositAmount = 1000e6;

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        assertEq(dollarStore.getReserve(address(usdc)), depositAmount);
    }

    function test_deposit_transfersStablecoin() public {
        uint256 depositAmount = 1000e6;
        uint256 balanceBefore = usdc.balanceOf(alice);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        assertEq(usdc.balanceOf(alice), balanceBefore - depositAmount);
        assertEq(usdc.balanceOf(address(dollarStore)), depositAmount);
    }

    function test_deposit_emitsEvent() public {
        uint256 depositAmount = 1000e6;

        vm.expectEmit(true, true, false, true);
        emit IDollarStore.Deposit(alice, address(usdc), depositAmount, depositAmount);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
    }

    function test_deposit_revertsOnUnsupportedStablecoin() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);
        unsupported.mint(alice, 1000e18);

        vm.startPrank(alice);
        unsupported.approve(address(dollarStore), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.deposit(address(unsupported), 1000e18);
        vm.stopPrank();
    }

    function test_deposit_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.deposit(address(usdc), 0);
    }

    function test_deposit_multipleStablecoins() public {
        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), 500e6);
        dollarStore.deposit(address(usdt), 1000e6);
        vm.stopPrank();

        assertEq(dollarStore.getReserve(address(usdc)), 500e6);
        assertEq(dollarStore.getReserve(address(usdt)), 1000e6);
        assertEq(dlrs.balanceOf(alice), 500e6 + 1000e6);
    }

    // ============ Withdraw Tests ============

    function test_withdraw_burnsCorrectDLRS() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        uint256 dlrsBalanceBefore = dlrs.balanceOf(alice);
        dollarStore.withdraw(address(usdc), depositAmount);
        vm.stopPrank();

        assertEq(dlrs.balanceOf(alice), dlrsBalanceBefore - depositAmount);
    }

    function test_withdraw_updatesReserves() public {
        uint256 depositAmount = 1000e6;

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
        dollarStore.withdraw(address(usdc), 400e6);
        vm.stopPrank();

        assertEq(dollarStore.getReserve(address(usdc)), 600e6);
    }

    function test_withdraw_transfersStablecoin() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
        uint256 balanceAfterDeposit = usdc.balanceOf(alice);
        dollarStore.withdraw(address(usdc), withdrawAmount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(alice), balanceAfterDeposit + withdrawAmount);
    }

    function test_withdraw_emitsEvent() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        vm.expectEmit(true, true, false, true);
        emit IDollarStore.Withdraw(alice, address(usdc), withdrawAmount, withdrawAmount);

        vm.prank(alice);
        dollarStore.withdraw(address(usdc), withdrawAmount);
    }

    function test_withdraw_revertsOnInsufficientReserves() public {
        uint256 depositAmount = 1000e6;

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReserves.selector, address(usdc), 2000e6, 1000e6)
        );
        dollarStore.withdraw(address(usdc), 2000e6);
    }

    function test_withdraw_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.withdraw(address(usdc), 0);
    }

    function test_withdraw_differentStablecoinThanDeposited() public {
        // Alice deposits USDC
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob deposits USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        // Alice can withdraw USDT (not what she deposited)
        vm.prank(alice);
        dollarStore.withdraw(address(usdt), 500e6);

        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + 500e6);
        assertEq(dlrs.balanceOf(alice), 1000e6 - 500e6);
    }

    // ============ View Functions Tests ============

    function test_getReserves_returnsAllReserves() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        (address[] memory stablecoins, uint256[] memory amounts) = dollarStore.getReserves();

        assertEq(stablecoins.length, 2);
        assertEq(amounts.length, 2);

        // Find and verify each stablecoin's reserve
        for (uint256 i = 0; i < stablecoins.length; i++) {
            if (stablecoins[i] == address(usdc)) {
                assertEq(amounts[i], 100e6);
            } else if (stablecoins[i] == address(usdt)) {
                assertEq(amounts[i], 500e6);
            }
        }
    }

    function test_dlrsToken_returnsCorrectAddress() public view {
        assertEq(dollarStore.dlrsToken(), address(dlrs));
    }

    // ============ Admin Tests ============

    function test_addStablecoin_addsNewStablecoin() public {
        MockStablecoin newCoin = new MockStablecoin("New Coin", "NEW", 18);

        vm.prank(admin);
        dollarStore.addStablecoin(address(newCoin));

        assertTrue(dollarStore.isSupported(address(newCoin)));
    }

    function test_addStablecoin_revertsForNonAdmin() public {
        MockStablecoin newCoin = new MockStablecoin("New Coin", "NEW", 18);

        vm.prank(alice);
        vm.expectRevert(DollarStore.OnlyAdmin.selector);
        dollarStore.addStablecoin(address(newCoin));
    }

    function test_addStablecoin_revertsOnDuplicate() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinAlreadySupported.selector, address(usdc)));
        dollarStore.addStablecoin(address(usdc));
    }

    function test_removeStablecoin_removesStablecoin() public {
        // First ensure reserves are empty
        vm.prank(admin);
        dollarStore.removeStablecoin(address(usdt));

        assertFalse(dollarStore.isSupported(address(usdt)));
        assertEq(dollarStore.supportedStablecoins().length, 1);
    }

    function test_removeStablecoin_revertsWithNonZeroReserves() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientReserves.selector, address(usdc), 0, 100e6));
        dollarStore.removeStablecoin(address(usdc));
    }

    function test_transferAdmin_twoStepProcess() public {
        address newAdmin = address(0x1234);

        vm.prank(admin);
        dollarStore.transferAdmin(newAdmin);

        assertEq(dollarStore.pendingAdmin(), newAdmin);
        assertEq(dollarStore.admin(), admin); // Still old admin

        vm.prank(newAdmin);
        dollarStore.acceptAdmin();

        assertEq(dollarStore.admin(), newAdmin);
        assertEq(dollarStore.pendingAdmin(), address(0));
    }

    function test_acceptAdmin_revertsForNonPendingAdmin() public {
        vm.prank(admin);
        dollarStore.transferAdmin(bob);

        vm.prank(alice);
        vm.expectRevert(DollarStore.OnlyPendingAdmin.selector);
        dollarStore.acceptAdmin();
    }

    // ============ DLRS Token Tests ============

    function test_dlrs_onlyDollarStoreCanMint() public {
        vm.prank(alice);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        dlrs.mint(alice, 1000e6);
    }

    function test_dlrs_onlyDollarStoreCanBurn() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        vm.expectRevert(DLRS.OnlyDollarStore.selector);
        dlrs.burn(alice, 1000e6);
    }

    // ============ Fuzz Tests ============

    function testFuzz_deposit_anyAmount(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(address(usdc), amount);

        assertEq(minted, amount);
        assertEq(dlrs.balanceOf(alice), amount);
        assertEq(dollarStore.getReserve(address(usdc)), amount);
    }

    function testFuzz_depositAndWithdraw_preservesInvariants(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
        dollarStore.withdraw(address(usdc), withdrawAmount);
        vm.stopPrank();

        uint256 expectedDlrs = depositAmount - withdrawAmount;
        uint256 expectedReserve = depositAmount - withdrawAmount;

        assertEq(dlrs.balanceOf(alice), expectedDlrs);
        assertEq(dollarStore.getReserve(address(usdc)), expectedReserve);
    }

    // ============ Queue Tests - joinQueue ============

    function test_joinQueue_createsPosition() public {
        // First deposit to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Join queue for USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        assertEq(positionId, 1); // First position ID is 1

        (address owner, address stablecoin, uint256 amount, uint256 timestamp) =
            dollarStore.getQueuePosition(positionId);

        assertEq(owner, alice);
        assertEq(stablecoin, address(usdt));
        assertEq(amount, 500e6);
        assertEq(timestamp, block.timestamp);
    }

    function test_joinQueue_burnsDLRS() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        uint256 dlrsBefore = dlrs.balanceOf(alice);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        assertEq(dlrs.balanceOf(alice), dlrsBefore - 500e6);
    }

    function test_joinQueue_updatesQueueDepth() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);
    }

    function test_joinQueue_tracksUserPositions() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        uint256[] memory positions = dollarStore.getUserQueuePositions(alice);
        assertEq(positions.length, 1);
        assertEq(positions[0], positionId);
    }

    function test_joinQueue_emitsEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueueJoined(1, alice, address(usdt), 500e6, block.timestamp);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);
    }

    function test_joinQueue_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.joinQueue(address(usdt), 0);
    }

    function test_joinQueue_revertsOnUnsupportedStablecoin() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.joinQueue(address(unsupported), 500e6);
    }

    function test_joinQueue_revertsOnInsufficientDLRS() public {
        // Alice has no DLRS
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientDlrsBalance.selector, 500e6, 0));
        dollarStore.joinQueue(address(usdt), 500e6);
    }

    function test_joinQueue_multiplePositions() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.startPrank(alice);
        uint256 pos1 = dollarStore.joinQueue(address(usdt), 300e6);
        uint256 pos2 = dollarStore.joinQueue(address(usdt), 200e6);
        vm.stopPrank();

        assertEq(pos1, 1);
        assertEq(pos2, 2);
        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);

        uint256[] memory positions = dollarStore.getUserQueuePositions(alice);
        assertEq(positions.length, 2);
    }

    // ============ Queue Tests - cancelQueue ============

    function test_cancelQueue_returnsDLRS() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        uint256 dlrsBefore = dlrs.balanceOf(alice);

        vm.prank(alice);
        uint256 returned = dollarStore.cancelQueue(positionId);

        assertEq(returned, 500e6);
        assertEq(dlrs.balanceOf(alice), dlrsBefore + 500e6);
    }

    function test_cancelQueue_removesPosition() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        vm.prank(alice);
        dollarStore.cancelQueue(positionId);

        (address owner,,,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, address(0)); // Position deleted

        uint256[] memory positions = dollarStore.getUserQueuePositions(alice);
        assertEq(positions.length, 0);
    }

    function test_cancelQueue_updatesQueueDepth() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);

        vm.prank(alice);
        dollarStore.cancelQueue(positionId);

        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);
    }

    function test_cancelQueue_emitsEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        vm.expectEmit(true, true, false, true);
        emit IDollarStore.QueueCancelled(positionId, alice, 500e6);

        vm.prank(alice);
        dollarStore.cancelQueue(positionId);
    }

    function test_cancelQueue_revertsOnNonExistentPosition() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.QueuePositionNotFound.selector, 999));
        dollarStore.cancelQueue(999);
    }

    function test_cancelQueue_revertsOnNotOwner() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.NotPositionOwner.selector, positionId, bob, alice));
        dollarStore.cancelQueue(positionId);
    }

    function test_cancelQueue_middleOfQueue() public {
        // Alice and Bob both deposit
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);
        vm.prank(bob);
        dollarStore.deposit(address(usdc), 1000e6);

        // Create 3 positions
        vm.prank(alice);
        uint256 pos1 = dollarStore.joinQueue(address(usdt), 200e6);

        vm.prank(bob);
        uint256 pos2 = dollarStore.joinQueue(address(usdt), 300e6);

        vm.prank(alice);
        uint256 pos3 = dollarStore.joinQueue(address(usdt), 400e6);

        // Cancel middle position
        vm.prank(bob);
        dollarStore.cancelQueue(pos2);

        // Queue should still have pos1 and pos3
        assertEq(dollarStore.getQueueDepth(address(usdt)), 600e6);

        // Verify positions 1 and 3 still exist
        (address owner1,,,) = dollarStore.getQueuePosition(pos1);
        (address owner3,,,) = dollarStore.getQueuePosition(pos3);
        assertEq(owner1, alice);
        assertEq(owner3, alice);
    }

    // ============ Queue Tests - Auto-Settlement on Deposit ============

    function test_deposit_fillsQueueFIFO() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Alice joins queue for USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        // Bob deposits USDT - should fill Alice's queue position
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        // Alice should have received USDT
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + 500e6);

        // Queue should be empty
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);

        // Position should be deleted
        (address owner,,,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, address(0));

        // Reserves should be 0 since all went to queue
        assertEq(dollarStore.getReserve(address(usdt)), 0);
    }

    function test_deposit_partialFill() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Alice joins queue for 1000 USDT
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 1000e6);

        // Bob deposits only 400 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 400e6);

        // Alice should have received 400 USDT
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + 400e6);

        // Position should show 600 remaining
        (, , uint256 remaining,) = dollarStore.getQueuePosition(positionId);
        assertEq(remaining, 600e6);

        // Queue depth should be 600
        assertEq(dollarStore.getQueueDepth(address(usdt)), 600e6);

        // No reserves added
        assertEq(dollarStore.getReserve(address(usdt)), 0);
    }

    function test_deposit_fillsMultiplePositions() public {
        // Alice and Bob get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 500e6);
        vm.prank(bob);
        dollarStore.deposit(address(usdc), 500e6);

        // Both join queue for USDT
        vm.prank(alice);
        uint256 pos1 = dollarStore.joinQueue(address(usdt), 300e6);
        vm.prank(bob);
        uint256 pos2 = dollarStore.joinQueue(address(usdt), 400e6);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        uint256 bobUsdtBefore = usdt.balanceOf(bob);

        // New user deposits enough to fill both
        address charlie = address(0xC);
        usdt.mint(charlie, 1000e6);
        vm.startPrank(charlie);
        usdt.approve(address(dollarStore), type(uint256).max);
        dollarStore.deposit(address(usdt), 800e6);
        vm.stopPrank();

        // Both should be filled
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + 300e6);
        assertEq(usdt.balanceOf(bob), bobUsdtBefore + 400e6);

        // Both positions deleted
        (address owner1,,,) = dollarStore.getQueuePosition(pos1);
        (address owner2,,,) = dollarStore.getQueuePosition(pos2);
        assertEq(owner1, address(0));
        assertEq(owner2, address(0));

        // Remaining 100 goes to reserves
        assertEq(dollarStore.getReserve(address(usdt)), 100e6);
    }

    function test_deposit_emitsQueueFilledEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueueFilled(positionId, alice, address(usdt), 500e6, 0);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);
    }

    function test_deposit_emitsPartialFillEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueueFilled(positionId, alice, address(usdt), 200e6, 300e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 200e6);
    }

    function test_deposit_noQueueNoChange() public {
        // Deposit with empty queue - all goes to reserves
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        assertEq(dollarStore.getReserve(address(usdc)), 1000e6);
        assertEq(dollarStore.getQueueDepth(address(usdc)), 0);
    }

    function test_deposit_wrongStablecoinDoesntFillQueue() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Alice wants USDT
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        // Bob deposits USDC (not what Alice wants)
        vm.prank(bob);
        dollarStore.deposit(address(usdc), 500e6);

        // Alice's USDT queue unchanged
        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);

        // USDC goes to reserves
        assertEq(dollarStore.getReserve(address(usdc)), 1500e6);
    }

    // ============ Queue View Functions Tests ============

    function test_getQueueDepth_empty() public view {
        assertEq(dollarStore.getQueueDepth(address(usdc)), 0);
    }

    function test_getUserQueuePositions_empty() public view {
        uint256[] memory positions = dollarStore.getUserQueuePositions(alice);
        assertEq(positions.length, 0);
    }

    function test_getQueuePosition_nonExistent() public view {
        (address owner, address stablecoin, uint256 amount, uint256 timestamp) = dollarStore.getQueuePosition(999);
        assertEq(owner, address(0));
        assertEq(stablecoin, address(0));
        assertEq(amount, 0);
        assertEq(timestamp, 0);
    }

    // ============ Queue Fuzz Tests ============

    function testFuzz_joinQueue_anyAmount(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), amount);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), amount);

        (, , uint256 positionAmount,) = dollarStore.getQueuePosition(positionId);
        assertEq(positionAmount, amount);
        assertEq(dollarStore.getQueueDepth(address(usdt)), amount);
        assertEq(dlrs.balanceOf(alice), 0);
    }

    function testFuzz_queueAndCancel_returnsFull(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), amount);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), amount);

        vm.prank(alice);
        uint256 returned = dollarStore.cancelQueue(positionId);

        assertEq(returned, amount);
        assertEq(dlrs.balanceOf(alice), amount);
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);
    }

    function testFuzz_depositFillsQueue(uint256 queueAmount, uint256 depositAmount) public {
        queueAmount = bound(queueAmount, 1, INITIAL_BALANCE);
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);

        // Alice gets DLRS and joins queue
        vm.prank(alice);
        dollarStore.deposit(address(usdc), queueAmount);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), queueAmount);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);

        // Bob deposits USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), depositAmount);

        uint256 expectedFill = depositAmount < queueAmount ? depositAmount : queueAmount;
        uint256 expectedReserve = depositAmount > queueAmount ? depositAmount - queueAmount : 0;
        uint256 expectedQueueRemaining = queueAmount > depositAmount ? queueAmount - depositAmount : 0;

        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + expectedFill);
        assertEq(dollarStore.getReserve(address(usdt)), expectedReserve);
        assertEq(dollarStore.getQueueDepth(address(usdt)), expectedQueueRemaining);
    }

    // ============ Swap Tests - Instant Swap ============

    function test_swap_instantSwap() public {
        // Bob deposits USDT to create reserves
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        // Alice swaps USDC for USDT
        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(address(usdc), address(usdt), 500e6, false);

        assertEq(received, 500e6);
        assertEq(positionId, 0); // No queue position

        // Alice should have received USDT
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + 500e6);

        // USDC should be in reserves, USDT reduced
        assertEq(dollarStore.getReserve(address(usdc)), 500e6);
        assertEq(dollarStore.getReserve(address(usdt)), 500e6);
    }

    function test_swap_emitsEvent() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.Swap(alice, address(usdc), address(usdt), 500e6, 500e6, 0);

        vm.prank(alice);
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);
    }

    function test_swap_revertsOnSameStablecoin() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.SameStablecoin.selector);
        dollarStore.swap(address(usdc), address(usdc), 500e6, false);
    }

    function test_swap_revertsOnUnsupportedFrom() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.swap(address(unsupported), address(usdt), 500e6, false);
    }

    function test_swap_revertsOnUnsupportedTo() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.swap(address(usdc), address(unsupported), 500e6, false);
    }

    function test_swap_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.swap(address(usdc), address(usdt), 0, false);
    }

    // ============ Swap Tests - Queue Fallback ============

    function test_swap_queuesWhenNoReserves() public {
        // No USDT reserves

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(address(usdc), address(usdt), 500e6, true);

        assertEq(received, 0);
        assertEq(positionId, 1); // First queue position

        // USDC in reserves
        assertEq(dollarStore.getReserve(address(usdc)), 500e6);

        // Queue should have 500e6
        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);

        // Verify queue position
        (address owner, address stablecoin, uint256 amount,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, alice);
        assertEq(stablecoin, address(usdt));
        assertEq(amount, 500e6);
    }

    function test_swap_partialFillThenQueue() public {
        // Bob deposits only 300 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 300e6);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(address(usdc), address(usdt), 500e6, true);

        assertEq(received, 300e6);
        assertEq(positionId, 1); // Queue position created

        // Alice received 300 USDT
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + 300e6);

        // USDT reserves depleted
        assertEq(dollarStore.getReserve(address(usdt)), 0);

        // 200 queued
        assertEq(dollarStore.getQueueDepth(address(usdt)), 200e6);
    }

    function test_swap_noQueueReturnsDLRS() public {
        // Bob deposits only 300 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 300e6);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(address(usdc), address(usdt), 500e6, false);

        assertEq(received, 300e6);
        assertEq(positionId, 0); // No queue

        // Alice got DLRS for the unfilled 200
        assertEq(dlrs.balanceOf(alice), 200e6);

        // No queue
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);
    }

    function test_swap_revertsWhenNoReservesAndNoQueue() public {
        // No reserves, queueIfUnavailable = false

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 0));
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);
    }

    function test_swap_fillsExistingQueueWithFromStablecoin() public {
        // Bob has DLRS and is waiting for USDC
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.prank(bob);
        dollarStore.joinQueue(address(usdc), 300e6);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        // Alice swaps USDC for USDT - should fill Bob's queue first
        vm.prank(alice);
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);

        // Bob should have received USDC from the queue
        assertEq(usdc.balanceOf(bob), bobUsdcBefore + 300e6);

        // USDC queue should be empty
        assertEq(dollarStore.getQueueDepth(address(usdc)), 0);

        // Remaining USDC (200) in reserves
        assertEq(dollarStore.getReserve(address(usdc)), 200e6);
    }

    // ============ SwapFromDLRS Tests ============

    function test_swapFromDLRS_instantSwap() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob deposits USDT to create reserves
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(address(usdt), 500e6, false);

        assertEq(received, 500e6);
        assertEq(positionId, 0);

        // Alice received USDT
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + 500e6);

        // DLRS burned
        assertEq(dlrs.balanceOf(alice), 500e6); // 1000 - 500
    }

    function test_swapFromDLRS_queuesWhenNoReserves() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // No USDT reserves

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(address(usdt), 500e6, true);

        assertEq(received, 0);
        assertEq(positionId, 1);

        // All DLRS burned and queued
        assertEq(dlrs.balanceOf(alice), 500e6); // 1000 - 500 burned
        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6);
    }

    function test_swapFromDLRS_partialFillThenQueue() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob deposits only 200 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 200e6);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(address(usdt), 500e6, true);

        assertEq(received, 200e6);
        assertEq(positionId, 1);

        // 500 DLRS burned total (200 for instant, 300 for queue)
        assertEq(dlrs.balanceOf(alice), 500e6);
        assertEq(dollarStore.getQueueDepth(address(usdt)), 300e6);
    }

    function test_swapFromDLRS_partialFillNoQueue() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob deposits only 200 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 200e6);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swapFromDLRS(address(usdt), 500e6, false);

        assertEq(received, 200e6);
        assertEq(positionId, 0);

        // Only 200 DLRS burned, 800 remain
        assertEq(dlrs.balanceOf(alice), 800e6);
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);
    }

    function test_swapFromDLRS_revertsWhenNoReservesAndNoQueue() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 0));
        dollarStore.swapFromDLRS(address(usdt), 500e6, false);
    }

    function test_swapFromDLRS_revertsOnInsufficientDLRS() public {
        // Alice has no DLRS

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientDlrsBalance.selector, 500e6, 0));
        dollarStore.swapFromDLRS(address(usdt), 500e6, true);
    }

    function test_swapFromDLRS_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.swapFromDLRS(address(usdt), 0, false);
    }

    function test_swapFromDLRS_emitsEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.Swap(alice, address(dlrs), address(usdt), 500e6, 500e6, 0);

        vm.prank(alice);
        dollarStore.swapFromDLRS(address(usdt), 500e6, false);
    }

    // ============ Swap Fuzz Tests ============

    function testFuzz_swap_anyAmount(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        // Bob deposits USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), INITIAL_BALANCE);

        vm.prank(alice);
        (uint256 received, uint256 positionId) = dollarStore.swap(address(usdc), address(usdt), amount, false);

        assertEq(received, amount);
        assertEq(positionId, 0);
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + amount);
    }

    // ============ Pause Tests ============

    function test_pause_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert(DollarStore.OnlyAdmin.selector);
        dollarStore.pause();

        // Admin can pause
        vm.prank(admin);
        dollarStore.pause();
        assertTrue(dollarStore.paused());
    }

    function test_unpause_onlyAdmin() public {
        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(DollarStore.OnlyAdmin.selector);
        dollarStore.unpause();

        // Admin can unpause
        vm.prank(admin);
        dollarStore.unpause();
        assertFalse(dollarStore.paused());
    }

    function test_deposit_revertsWhenPaused() public {
        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.deposit(address(usdc), 100e6);
    }

    function test_withdraw_revertsWhenPaused() public {
        // Deposit first
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.withdraw(address(usdc), 100e6);
    }

    function test_joinQueue_revertsWhenPaused() public {
        // Get DLRS first
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.joinQueue(address(usdt), 50e6);
    }

    function test_cancelQueue_revertsWhenPaused() public {
        // Setup a queue position
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 50e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.cancelQueue(positionId);
    }

    function test_swap_revertsWhenPaused() public {
        // Create some reserves
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.swap(address(usdc), address(usdt), 100e6, false);
    }

    function test_swapFromDLRS_revertsWhenPaused() public {
        // Get DLRS and create reserves
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.swapFromDLRS(address(usdt), 50e6, false);
    }

    function test_operationsResumeAfterUnpause() public {
        vm.prank(admin);
        dollarStore.pause();

        vm.prank(admin);
        dollarStore.unpause();

        // All operations should work
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);
        assertEq(dlrs.balanceOf(alice), 100e6);
    }

    function test_viewFunctionsWorkWhenPaused() public {
        // Deposit first
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100e6);

        vm.prank(admin);
        dollarStore.pause();

        // View functions should still work
        assertEq(dollarStore.getReserve(address(usdc)), 100e6);
        assertTrue(dollarStore.isSupported(address(usdc)));
        assertEq(dollarStore.admin(), admin);
        assertTrue(dollarStore.paused());
    }
}
