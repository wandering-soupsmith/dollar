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

/// @dev Mock Chainlink price feed for testing
contract MockPriceFeed {
    int256 public price;
    uint256 public updatedAt;
    uint8 private _decimals;

    constructor(int256 _price) {
        price = _price;
        updatedAt = block.timestamp;
        _decimals = 8;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function setDecimals(uint8 d) external {
        _decimals = d;
    }

    function setPrice(int256 _price) external {
        price = _price;
        updatedAt = block.timestamp;
    }

    function setUpdatedAt(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        return (1, price, block.timestamp, updatedAt, 1);
        }
    }
/// @dev Mock stablecoin that can blacklist addresses (transfer reverts for blacklisted recipients)
contract BlacklistableStablecoin is ERC20 {
    uint8 private _decimals;
    mapping(address => bool) public blacklisted;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function setBlacklisted(address account, bool status) external {
        blacklisted[account] = status;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[to], "Blacklisted");
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(!blacklisted[to], "Blacklisted");
        return super.transferFrom(from, to, amount);
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

        // Set up price feeds for both stablecoins (required for deposits)
        MockPriceFeed usdcFeed = new MockPriceFeed(1e8);
        MockPriceFeed usdtFeed = new MockPriceFeed(1e8);
        vm.startPrank(admin);
        dollarStore.setPriceFeed(address(usdc), address(usdcFeed));
        dollarStore.setPriceFeed(address(usdt), address(usdtFeed));
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
        assertEq(dlrs.decimals(), 6); // Matches stablecoin decimals for 1:1 math
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
        uint256 withdrawAmount = 400e6;

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
        dollarStore.withdraw(address(usdc), withdrawAmount);
        vm.stopPrank();

        // Reserves decrease by full amount (no fee)
        uint256 expectedReserve = depositAmount - withdrawAmount;
        assertEq(dollarStore.getReserve(address(usdc)), expectedReserve);
    }

    function test_withdraw_transfersStablecoin() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 400e6;

        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), depositAmount);
        uint256 balanceAfterDeposit = usdc.balanceOf(alice);
        dollarStore.withdraw(address(usdc), withdrawAmount);
        vm.stopPrank();

        // User receives full amount (no fee)
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
        uint256 withdrawAmount = 500e6;
        vm.prank(alice);
        dollarStore.withdraw(address(usdt), withdrawAmount);

        // Alice receives full amount (no fee)
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + withdrawAmount);
        assertEq(dlrs.balanceOf(alice), 1000e6 - withdrawAmount);
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

    function test_removeStablecoin_revertsWithActiveQueue() public {
        // Alice deposits USDC to get DLRS, then joins queue for USDT
        vm.startPrank(alice);
        dollarStore.deposit(address(usdc), 1000e6);
        dollarStore.joinQueue(address(usdt), 500e6);
        vm.stopPrank();

        // Admin tries to remove USDT while queue has active positions
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.ActiveQueuePositions.selector, address(usdt)));
        dollarStore.removeStablecoin(address(usdt));

        // USDT is still supported
        assertTrue(dollarStore.isSupported(address(usdt)));
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

    function test_dlrs_transferReverts() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);
        assertEq(dlrs.balanceOf(alice), 1000e6);

        // Alice tries to transfer to Bob - should revert
        vm.prank(alice);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.transfer(bob, 500e6);

        // Balances unchanged
        assertEq(dlrs.balanceOf(alice), 1000e6);
        assertEq(dlrs.balanceOf(bob), 0);
    }

    function test_dlrs_approveReverts() public {
        // Alice tries to approve Bob - should revert
        vm.prank(alice);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.approve(bob, 500e6);
    }

    function test_dlrs_transferFromReverts() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob tries to transferFrom - should revert (no approval possible anyway)
        vm.prank(bob);
        vm.expectRevert(DLRS.NonTransferable.selector);
        dlrs.transferFrom(alice, bob, 500e6);

        // Balances unchanged
        assertEq(dlrs.balanceOf(alice), 1000e6);
        assertEq(dlrs.balanceOf(bob), 0);
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

        // DLRS burned equals withdraw amount
        uint256 expectedDlrs = depositAmount - withdrawAmount;
        // Reserve decreases by full amount (no fee)
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

    function test_getMinimumOrderSize_boundaryUsesNextTier() public {
        // Deposit enough DLRS to create 24 queue positions
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 100_000e6);

        // Create 24 positions at $100 each (tier 0)
        vm.startPrank(alice);
        for (uint256 i = 0; i < 24; i++) {
            dollarStore.joinQueue(address(usdt), 100e6);
        }
        vm.stopPrank();

        // With 24 positions, the 25th position should require $1,000 (tier 1)
        // because (24 + 1) / 25 = 1 tier
        uint256 minOrder = dollarStore.getMinimumOrderSize(address(usdt));
        assertEq(minOrder, 1000e6, "25th position should be at tier 1 ($1,000)");
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

    // ============ Queue Tests - Auto-Settlement on Deposit (FIFO) ============

    function test_deposit_fillsQueueFIFO() public {
        // Alice deposits USDC to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Alice joins queue for USDT
        uint256 queueAmount = 500e6;
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), queueAmount);

        // Bob deposits USDT - should fill Alice's queue position
        vm.prank(bob);
        dollarStore.deposit(address(usdt), queueAmount);

        // Alice should have received USDT (no fee)
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + queueAmount);

        // Queue should be empty
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);

        // Position should be deleted
        (address owner,,,) = dollarStore.getQueuePosition(positionId);
        assertEq(owner, address(0));

        // No reserves added (all went to fill queue)
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
        uint256 fillAmount = 400e6;
        vm.prank(bob);
        dollarStore.deposit(address(usdt), fillAmount);

        // Alice should have received 400 USDT (no fee)
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE + fillAmount);

        // Position should show 600 remaining
        (, , uint256 remaining,) = dollarStore.getQueuePosition(positionId);
        assertEq(remaining, 600e6);

        // Queue depth should be 600
        assertEq(dollarStore.getQueueDepth(address(usdt)), 600e6);

        // No reserves added (all went to fill queue)
        assertEq(dollarStore.getReserve(address(usdt)), 0);
    }

    function test_deposit_fillsMultiplePositions() public {
        // Alice and Bob get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 500e6);
        vm.prank(bob);
        dollarStore.deposit(address(usdc), 500e6);

        // Both join queue for USDT
        uint256 aliceQueueAmount = 300e6;
        uint256 bobQueueAmount = 400e6;
        vm.prank(alice);
        uint256 pos1 = dollarStore.joinQueue(address(usdt), aliceQueueAmount);
        vm.prank(bob);
        uint256 pos2 = dollarStore.joinQueue(address(usdt), bobQueueAmount);

        uint256 aliceUsdtBefore = usdt.balanceOf(alice);
        uint256 bobUsdtBefore = usdt.balanceOf(bob);

        // New user deposits enough to fill both
        address charlie = address(0xC);
        usdt.mint(charlie, 1000e6);
        vm.startPrank(charlie);
        usdt.approve(address(dollarStore), type(uint256).max);
        dollarStore.deposit(address(usdt), 800e6);
        vm.stopPrank();

        // Both should be filled (no fees)
        assertEq(usdt.balanceOf(alice), aliceUsdtBefore + aliceQueueAmount);
        assertEq(usdt.balanceOf(bob), bobUsdtBefore + bobQueueAmount);

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

        uint256 queueAmount = 500e6;
        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), queueAmount);

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueueFilled(positionId, alice, address(usdt), queueAmount, 0);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), queueAmount);
    }

    function test_deposit_emitsPartialFillEvent() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 500e6);

        uint256 fillAmount = 200e6;
        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueueFilled(positionId, alice, address(usdt), fillAmount, 300e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), fillAmount);
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
        // Minimum order size is 100e6 ($100)
        amount = bound(amount, 100e6, INITIAL_BALANCE);

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
        // Minimum order size is 100e6 ($100)
        amount = bound(amount, 100e6, INITIAL_BALANCE);

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
        // Minimum order size is 100e6 ($100)
        queueAmount = bound(queueAmount, 100e6, INITIAL_BALANCE);
        depositAmount = bound(depositAmount, 100e6, INITIAL_BALANCE);

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

        // No fee on queue fills
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

    function test_swap_revertsOnPartialFillNoQueue() public {
        // Bob deposits only 300 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 300e6);

        // Alice tries to swap 500 USDC for USDT with queueIfUnavailable=false
        // Should revert since only 300 available
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 300e6));
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);
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

        uint256 bobQueueAmount = 300e6;
        vm.prank(bob);
        dollarStore.joinQueue(address(usdc), bobQueueAmount);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        // Alice swaps USDC for USDT - should fill Bob's queue first
        vm.prank(alice);
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);

        // Bob should have received USDC from the queue (no fee)
        assertEq(usdc.balanceOf(bob), bobUsdcBefore + bobQueueAmount);

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

    function test_swapFromDLRS_revertsOnPartialFillNoQueue() public {
        // Alice deposits to get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Bob deposits only 200 USDT
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 200e6);

        // Alice tries to swapFromDLRS 500 for USDT with queueIfUnavailable=false
        // Should revert since only 200 available
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 200e6));
        dollarStore.swapFromDLRS(address(usdt), 500e6, false);
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
        // Get DLRS first (min order is 100e6)
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 200e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.joinQueue(address(usdt), 100e6);
    }

    function test_cancelQueue_revertsWhenPaused() public {
        // Setup a queue position (min order is 100e6)
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 200e6);

        vm.prank(alice);
        uint256 positionId = dollarStore.joinQueue(address(usdt), 200e6);

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
        dollarStore.deposit(address(usdc), 200e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.prank(admin);
        dollarStore.pause();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.swapFromDLRS(address(usdt), 100e6, false);
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

    // ============ No Fee Tests ============

    function test_withdraw_noFee() public {
        uint256 depositAmount = 1000e6;
        uint256 withdrawAmount = 1000e6;

        vm.prank(alice);
        dollarStore.deposit(address(usdc), depositAmount);

        vm.prank(alice);
        uint256 received = dollarStore.withdraw(address(usdc), withdrawAmount);

        // User receives full amount (no fee)
        assertEq(received, withdrawAmount);
    }

    function testFuzz_noFeeOnWithdraw(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1, INITIAL_BALANCE);

        vm.prank(alice);
        dollarStore.deposit(address(usdc), withdrawAmount);

        vm.prank(alice);
        uint256 received = dollarStore.withdraw(address(usdc), withdrawAmount);

        // User receives full amount (no fee)
        assertEq(received, withdrawAmount);
    }

    // ============ Aggregator Tests - getSwapQuote ============

    function test_getSwapQuote_returnsAmountWhenSufficientReserves() public {
        // Create USDT reserves
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdt), 500e6);
        assertEq(quote, 500e6);
    }

    function test_getSwapQuote_returnsZeroWhenInsufficientReserves() public {
        // Only 300 USDT available
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 300e6);

        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdt), 500e6);
        assertEq(quote, 0); // Returns 0, not partial
    }

    function test_getSwapQuote_returnsZeroForUnsupportedFrom() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);

        uint256 quote = dollarStore.getSwapQuote(address(unsupported), address(usdt), 500e6);
        assertEq(quote, 0);
    }

    function test_getSwapQuote_returnsZeroForUnsupportedTo() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);

        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(unsupported), 500e6);
        assertEq(quote, 0);
    }

    function test_getSwapQuote_returnsZeroForSameStablecoin() public {
        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdc), 500e6);
        assertEq(quote, 0);
    }

    function test_getSwapQuote_returnsZeroForEmptyReserves() public {
        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdt), 500e6);
        assertEq(quote, 0);
    }

    function test_getSwapQuote_exactReservesMatch() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdt), 500e6);
        assertEq(quote, 500e6); // Exactly matches
    }

    function testFuzz_getSwapQuote_anyAmount(uint256 reserves, uint256 queryAmount) public {
        reserves = bound(reserves, 0, INITIAL_BALANCE);
        queryAmount = bound(queryAmount, 1, INITIAL_BALANCE);

        if (reserves > 0) {
            vm.prank(bob);
            dollarStore.deposit(address(usdt), reserves);
        }

        uint256 quote = dollarStore.getSwapQuote(address(usdc), address(usdt), queryAmount);

        if (reserves >= queryAmount) {
            assertEq(quote, queryAmount);
        } else {
            assertEq(quote, 0);
        }
    }

    // ============ Aggregator Tests - swapExactInput ============

    function test_swapExactInput_successfulSwap() public {
        // Create USDT reserves
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        address recipient = address(0xCAFE);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        uint256 amountOut = dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            recipient,
            deadline
        );

        assertEq(amountOut, 500e6);
        assertEq(usdt.balanceOf(recipient), 500e6);
        assertEq(dollarStore.getReserve(address(usdc)), 500e6);
        assertEq(dollarStore.getReserve(address(usdt)), 500e6);
    }

    function test_swapExactInput_sendsToRecipient() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        address recipient = address(0xBEEF);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            recipient,
            deadline
        );

        // Recipient gets tokens, not caller
        assertEq(usdt.balanceOf(recipient), 500e6);
        assertEq(usdt.balanceOf(alice), INITIAL_BALANCE); // Unchanged
    }

    function test_swapExactInput_fillsQueueWithFromToken() public {
        // Bob has DLRS and is waiting for USDC
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        vm.prank(bob);
        dollarStore.joinQueue(address(usdc), 300e6);

        uint256 bobUsdcBefore = usdc.balanceOf(bob);

        // Create USDT reserves for Alice
        address charlie = address(0xC);
        usdt.mint(charlie, 500e6);
        vm.prank(charlie);
        usdt.approve(address(dollarStore), type(uint256).max);
        vm.prank(charlie);
        dollarStore.deposit(address(usdt), 500e6);

        address recipient = address(0xCAFE);
        uint256 deadline = block.timestamp + 1 hours;

        // Alice swaps USDC for USDT - should fill Bob's queue first
        vm.prank(alice);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            recipient,
            deadline
        );

        // Bob's queue should be filled
        assertEq(usdc.balanceOf(bob), bobUsdcBefore + 300e6);
        assertEq(dollarStore.getQueueDepth(address(usdc)), 0);

        // Remaining 200 USDC goes to reserves
        assertEq(dollarStore.getReserve(address(usdc)), 200e6);
    }

    function test_swapExactInput_revertsOnExpiredDeadline() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        uint256 expiredDeadline = block.timestamp - 1;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.DeadlineExpired.selector, expiredDeadline, block.timestamp)
        );
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            expiredDeadline
        );
    }

    function test_swapExactInput_revertsOnInsufficientReserves() public {
        // Only 300 USDT available
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 300e6);

        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 300e6)
        );
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_revertsOnZeroAmount() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAmount.selector);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            0,
            0,
            alice,
            deadline
        );
    }

    function test_swapExactInput_revertsOnZeroRecipient() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(IDollarStore.ZeroAddress.selector);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            address(0),
            deadline
        );
    }

    function test_swapExactInput_revertsOnSameStablecoin() public {
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(IDollarStore.SameStablecoin.selector);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdc),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_revertsOnUnsupportedFrom() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.swapExactInput(
            address(unsupported),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_revertsOnUnsupportedTo() public {
        MockStablecoin unsupported = new MockStablecoin("Unsupported", "UNS", 18);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.StablecoinNotSupported.selector, address(unsupported)));
        dollarStore.swapExactInput(
            address(usdc),
            address(unsupported),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_revertsWhenPaused() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        vm.prank(admin);
        dollarStore.pause();

        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(bytes4(keccak256("EnforcedPause()"))));
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_emitsSwapEvent() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        uint256 deadline = block.timestamp + 1 hours;

        vm.expectEmit(true, true, true, true);
        emit IDollarStore.Swap(alice, address(usdc), address(usdt), 500e6, 500e6, 0);

        vm.prank(alice);
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );
    }

    function test_swapExactInput_neverQueues() public {
        // No USDT reserves - should revert, not queue

        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.InsufficientReservesNoQueue.selector, address(usdt), 500e6, 0)
        );
        dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );

        // Verify no queue position was created
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);
    }

    function testFuzz_swapExactInput_anyValidAmount(uint256 reserves, uint256 swapAmount) public {
        reserves = bound(reserves, 1, INITIAL_BALANCE);
        swapAmount = bound(swapAmount, 1, reserves); // Must be <= reserves

        vm.prank(bob);
        dollarStore.deposit(address(usdt), reserves);

        address recipient = address(0xCAFE);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        uint256 amountOut = dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            swapAmount,
            swapAmount,
            recipient,
            deadline
        );

        assertEq(amountOut, swapAmount);
        assertEq(usdt.balanceOf(recipient), swapAmount);
    }

    function test_swapExactInput_exactReservesMatch() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        address recipient = address(0xCAFE);
        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        uint256 amountOut = dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            recipient,
            deadline
        );

        assertEq(amountOut, 500e6);
        assertEq(dollarStore.getReserve(address(usdt)), 0);
    }

    function test_swapExactInput_maxDeadline() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        // Aggregators often pass max uint256 as deadline
        uint256 deadline = type(uint256).max;

        vm.prank(alice);
        uint256 amountOut = dollarStore.swapExactInput(
            address(usdc),
            address(usdt),
            500e6,
            500e6,
            alice,
            deadline
        );

        assertEq(amountOut, 500e6);
    }

    // ============ Depeg Protection Tests ============

    function test_deposit_revertsWhenDepositPaused() public {
        vm.prank(admin);
        dollarStore.pauseDeposits(address(usdc));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DepositsPaused.selector, address(usdc)));
        dollarStore.deposit(address(usdc), 1000e6);
    }

    function test_swap_revertsWhenFromStablecoinDepositPaused() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        vm.prank(admin);
        dollarStore.pauseDeposits(address(usdc));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DepositsPaused.selector, address(usdc)));
        dollarStore.swap(address(usdc), address(usdt), 500e6, false);
    }

    function test_swapExactInput_revertsWhenFromStablecoinDepositPaused() public {
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 1000e6);

        vm.prank(admin);
        dollarStore.pauseDeposits(address(usdc));

        uint256 deadline = block.timestamp + 1 hours;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.DepositsPaused.selector, address(usdc)));
        dollarStore.swapExactInput(address(usdc), address(usdt), 500e6, 500e6, alice, deadline);
    }

    function test_withdraw_worksWhenDepositPaused() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(admin);
        dollarStore.pauseDeposits(address(usdc));

        vm.prank(alice);
        uint256 received = dollarStore.withdraw(address(usdc), 500e6);
        assertEq(received, 500e6);
    }

    function test_swapFromDLRS_worksWhenDepositPaused() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(admin);
        dollarStore.pauseDeposits(address(usdc));

        vm.prank(alice);
        (uint256 received,) = dollarStore.swapFromDLRS(address(usdc), 500e6, false);
        assertEq(received, 500e6);
    }

    function test_deposit_revertsWhenPriceStale() public {
        vm.warp(10000); // Ensure block.timestamp is large enough
        MockPriceFeed feed = new MockPriceFeed(1e8);
        feed.setUpdatedAt(block.timestamp - 7200); // 2 hours ago
        uint256 staleTime = block.timestamp - 7200;

        vm.prank(admin);
        dollarStore.setPriceFeed(address(usdc), address(feed));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.PriceStale.selector, address(usdc), staleTime)
        );
        dollarStore.deposit(address(usdc), 1000e6);
    }

    function test_deposit_revertsWhenPriceOutOfBounds() public {
        MockPriceFeed feed = new MockPriceFeed(0.98e8); // $0.98 in 8 decimals

        vm.prank(admin);
        dollarStore.setPriceFeed(address(usdc), address(feed));

        // _checkPeg normalizes to 18 decimals: 0.98e8 * 10^10 = 0.98e18
        uint256 normalizedPrice = 0.98e18;
        uint256 lower = 1e18 - (1e18 * 50 / 10000);
        uint256 upper = 1e18 + (1e18 * 50 / 10000);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IDollarStore.PriceOutOfBounds.selector, address(usdc), normalizedPrice, lower, upper)
        );
        dollarStore.deposit(address(usdc), 1000e6);
    }

    function test_deposit_succeedsWithGoodPrice() public {
        MockPriceFeed feed = new MockPriceFeed(1e8);

        vm.prank(admin);
        dollarStore.setPriceFeed(address(usdc), address(feed));

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(address(usdc), 1000e6);
        assertEq(minted, 1000e6);
    }

    function test_deposit_revertsWithNoFeedConfigured() public {
        // Remove the feed set in setUp
        vm.prank(admin);
        dollarStore.setPriceFeed(address(usdc), address(0));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.NoPriceFeed.selector, address(usdc)));
        dollarStore.deposit(address(usdc), 1000e6);
    }

    function test_unpauseDeposits_allowsDepositsAgain() public {
        vm.startPrank(admin);
        dollarStore.pauseDeposits(address(usdc));
        dollarStore.unpauseDeposits(address(usdc));
        vm.stopPrank();

        vm.prank(alice);
        uint256 minted = dollarStore.deposit(address(usdc), 1000e6);
        assertEq(minted, 1000e6);
    }

    function test_setPriceFeed_onlyAdmin() public {
        MockPriceFeed feed = new MockPriceFeed(1e8);

        vm.prank(alice);
        vm.expectRevert();
        dollarStore.setPriceFeed(address(usdc), address(feed));
    }

    function test_setPegTolerance_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        dollarStore.setPegTolerance(100);
    }

    function test_pauseDeposits_onlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert();
        dollarStore.pauseDeposits(address(usdc));
    }

    function test_setPegTolerance_revertsOverMax() public {
        vm.prank(admin);
        vm.expectRevert(IDollarStore.InvalidTolerance.selector);
        dollarStore.setPegTolerance(10001);
    }

    function test_setMaxStaleness_revertsOnZero() public {
        vm.prank(admin);
        vm.expectRevert(IDollarStore.InvalidStaleness.selector);
        dollarStore.setMaxStaleness(0);
    }

    function test_constructor_setsDepegDefaults() public view {
        assertEq(dollarStore.pegTolerance(), 50);
        assertEq(dollarStore.maxStaleness(), 3600);
    }

    function test_isDepositPaused_returnsFalseByDefault() public view {
        assertFalse(dollarStore.isDepositPaused(address(usdc)));
    }

    function test_getPriceFeed_returnsConfiguredFeed() public view {
        assertTrue(dollarStore.getPriceFeed(address(usdc)) != address(0));
    }
    // ============ M-01: Blacklist-Resilient Queue Tests ============

    function test_processQueue_skipsBlacklistedRecipient() public {
        // Deploy a blacklistable stablecoin and set up DollarStore with it
        BlacklistableStablecoin blusdc = new BlacklistableStablecoin("Blacklistable USDC", "bUSDC", 6);

        address[] memory stables = new address[](1);
        stables[0] = address(blusdc);

        vm.prank(admin);
        DollarStore ds = new DollarStore(admin, stables);
        MockPriceFeed blusdcFeed = new MockPriceFeed(1e8);
        vm.prank(admin);
        ds.setPriceFeed(address(blusdc), address(blusdcFeed));

        DLRS dsToken = ds.dlrs();

        // Fund users
        blusdc.mint(alice, 10_000e6);
        blusdc.mint(bob, 10_000e6);

        vm.prank(alice);
        blusdc.approve(address(ds), type(uint256).max);
        vm.prank(bob);
        blusdc.approve(address(ds), type(uint256).max);

        // Alice deposits to get DLRS, then joins queue
        vm.prank(alice);
        ds.deposit(address(blusdc), 1000e6);
        vm.prank(alice);
        ds.joinQueue(address(blusdc), 500e6);

        // Blacklist Alice on the stablecoin
        blusdc.setBlacklisted(alice, true);

        // Bob deposits — this triggers _processQueue which tries to fill Alice's position
        vm.prank(bob);
        ds.deposit(address(blusdc), 1000e6);

        // Alice's position was ejected: she gets DLRS back instead of bUSDC
        // She had 1000 DLRS from deposit, burned 500 for queue, now gets 500 refunded
        assertEq(dsToken.balanceOf(alice), 1000e6);

        // Queue is empty (Alice was ejected)
        assertEq(ds.getQueueDepth(address(blusdc)), 0);

        // Reserves: 1000 (Alice's deposit) + 1000 (Bob's — queue fill skipped, all to reserves)
        assertEq(ds.getReserve(address(blusdc)), 2000e6);
    }

    function test_processQueue_fillsNextPositionAfterSkip() public {
        BlacklistableStablecoin blusdc = new BlacklistableStablecoin("Blacklistable USDC", "bUSDC", 6);

        address[] memory stables = new address[](1);

        stables[0] = address(blusdc);

        vm.prank(admin);
        DollarStore ds = new DollarStore(admin, stables);
        MockPriceFeed blusdcFeed = new MockPriceFeed(1e8);
        vm.prank(admin);
        ds.setPriceFeed(address(blusdc), address(blusdcFeed));

        DLRS dsToken = ds.dlrs();

        address charlie = address(0xC);
        blusdc.mint(alice, 10_000e6);
        blusdc.mint(bob, 10_000e6);
        blusdc.mint(charlie, 10_000e6);

        vm.prank(alice);
        blusdc.approve(address(ds), type(uint256).max);
        vm.prank(bob);
        blusdc.approve(address(ds), type(uint256).max);
        vm.prank(charlie);
        blusdc.approve(address(ds), type(uint256).max);

        // Alice and Bob both get DLRS and join queue
        vm.prank(alice);
        ds.deposit(address(blusdc), 1000e6);
        vm.prank(bob);
        ds.deposit(address(blusdc), 1000e6);

        vm.prank(alice);
        ds.joinQueue(address(blusdc), 500e6); // position 1 (head)
        vm.prank(bob);
        ds.joinQueue(address(blusdc), 300e6); // position 2

        // Blacklist Alice (head of queue)
        blusdc.setBlacklisted(alice, true);

        uint256 bobBlusdcBefore = blusdc.balanceOf(bob);

        // Charlie deposits 1000 — should skip Alice, fill Bob, rest to reserves
        vm.prank(charlie);
        ds.deposit(address(blusdc), 1000e6);

        // Alice ejected with DLRS refund (500 burned for queue, 500 refunded)
        assertEq(dsToken.balanceOf(alice), 1000e6);

        // Bob's 300 was filled with actual bUSDC
        assertEq(blusdc.balanceOf(bob), bobBlusdcBefore + 300e6);

        // Queue is empty
        assertEq(ds.getQueueDepth(address(blusdc)), 0);

        // Reserves: 1000 (Alice's deposit) + 1000 (Bob's deposit) + 700 (Charlie's remaining after filling Bob's 300)
        assertEq(ds.getReserve(address(blusdc)), 2700e6);
    }

    function test_processQueue_emitsRefundEvent() public {
        BlacklistableStablecoin blusdc = new BlacklistableStablecoin("Blacklistable USDC", "bUSDC", 6);

        address[] memory stables = new address[](1);
        stables[0] = address(blusdc);

        vm.prank(admin);
        DollarStore ds = new DollarStore(admin, stables);
        MockPriceFeed blusdcFeed = new MockPriceFeed(1e8);
        vm.prank(admin);
        ds.setPriceFeed(address(blusdc), address(blusdcFeed));


        blusdc.mint(alice, 10_000e6);
        blusdc.mint(bob, 10_000e6);

        vm.prank(alice);
        blusdc.approve(address(ds), type(uint256).max);
        vm.prank(bob);
        blusdc.approve(address(ds), type(uint256).max);

        vm.prank(alice);
        ds.deposit(address(blusdc), 1000e6);
        vm.prank(alice);
        ds.joinQueue(address(blusdc), 500e6);

        blusdc.setBlacklisted(alice, true);

        // Expect the refund event
        vm.expectEmit(true, true, true, true);
        emit IDollarStore.QueuePositionRefunded(1, alice, address(blusdc), 500e6);

        vm.prank(bob);
        ds.deposit(address(blusdc), 1000e6);
    }

    // ============ Admin Cancel Queue Tests ============

    function test_adminCancelQueue_removesPosition() public {
        // Alice deposits and joins queue
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        uint256 aliceDlrsBefore = dlrs.balanceOf(alice);

        // Admin cancels Alice's position
        vm.prank(admin);
        uint256 returned = dollarStore.adminCancelQueue(1);

        assertEq(returned, 500e6);
        assertEq(dlrs.balanceOf(alice), aliceDlrsBefore + 500e6);
        assertEq(dollarStore.getQueueDepth(address(usdt)), 0);

        // Position is deleted
        (address owner,,,) = dollarStore.getQueuePosition(1);
        assertEq(owner, address(0));
    }

    function test_adminCancelQueue_revertsNonAdmin() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        vm.prank(alice);
        vm.expectRevert(DollarStore.OnlyAdmin.selector);
        dollarStore.adminCancelQueue(1);
    }

    function test_adminCancelQueue_revertsNonExistent() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IDollarStore.QueuePositionNotFound.selector, 999));
        dollarStore.adminCancelQueue(999);
    }

    function test_adminCancelQueue_middleOfQueue() public {
        // Create 3 positions
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 3000e6);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6); // pos 1
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 300e6); // pos 2
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 200e6); // pos 3

        // Admin cancels middle position
        vm.prank(admin);
        dollarStore.adminCancelQueue(2);

        // Queue depth should reflect removal
        assertEq(dollarStore.getQueueDepth(address(usdt)), 700e6); // 500 + 200

        // Positions 1 and 3 still exist
        (address owner1,,,) = dollarStore.getQueuePosition(1);
        (address owner3,,,) = dollarStore.getQueuePosition(3);
        assertEq(owner1, alice);
        assertEq(owner3, alice);
    }
}
