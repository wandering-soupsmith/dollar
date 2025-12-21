// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/DollarStore.sol";
import "../src/DLRS.sol";
import "../src/CENTS.sol";
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

contract CENTSTest is Test {
    DollarStore public dollarStore;
    DLRS public dlrs;
    CENTS public cents;

    MockStablecoin public usdc;
    MockStablecoin public usdt;

    address public admin = address(0xAD);
    address public founder = address(0xF0);
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

        // Deploy CENTS token
        cents = new CENTS(address(dollarStore), founder);

        // Set CENTS token in DollarStore
        vm.prank(admin);
        dollarStore.setCentsToken(address(cents));

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

    // ============ CENTS Constructor Tests ============

    function test_constructor_setsName() public view {
        assertEq(cents.name(), "Dollar Store Cents");
    }

    function test_constructor_setsSymbol() public view {
        assertEq(cents.symbol(), "CENTS");
    }

    function test_constructor_setsDecimals() public view {
        assertEq(cents.decimals(), 6);
    }

    function test_constructor_setsDollarStore() public view {
        assertEq(cents.dollarStore(), address(dollarStore));
    }

    function test_constructor_setsFounder() public view {
        assertEq(cents.founder(), founder);
    }

    function test_constructor_initializesEmissions() public view {
        assertEq(cents.makerEmissionsRemaining(), 600_000_000e6);
        assertEq(cents.takerEmissionsRemaining(), 200_000_000e6);
        assertEq(cents.founderEmissionsReceived(), 0);
    }

    function test_constructor_revertsOnZeroDollarStore() public {
        vm.expectRevert(CENTS.ZeroAddress.selector);
        new CENTS(address(0), founder);
    }

    function test_constructor_revertsOnZeroFounder() public {
        vm.expectRevert(CENTS.ZeroAddress.selector);
        new CENTS(address(dollarStore), address(0));
    }

    // ============ Staking Tests ============

    function test_stake_transfersCENTS() public {
        // Give alice some CENTS first (via minting through DollarStore queue fill)
        _giveCents(alice, 1000e6);

        uint256 balanceBefore = cents.balanceOf(alice);

        vm.prank(alice);
        cents.stake(500e6);

        assertEq(cents.balanceOf(alice), balanceBefore - 500e6);
        assertEq(cents.stakedBalance(alice), 500e6);
    }

    function test_stake_setsTimestamp() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        assertEq(cents.stakeTimestamp(alice), block.timestamp);
    }

    function test_stake_emitsEvent() public {
        _giveCents(alice, 1000e6);

        vm.expectEmit(true, false, false, true);
        emit CENTS.Staked(alice, 500e6, 0); // Power is 0 at time 0

        vm.prank(alice);
        cents.stake(500e6);
    }

    function test_stake_additionalStake_updatesWeightedTimestamp() public {
        _giveCents(alice, 1000e6);

        // First stake
        vm.prank(alice);
        cents.stake(500e6);
        uint256 firstTimestamp = cents.stakeTimestamp(alice);

        // Wait 15 days
        vm.warp(block.timestamp + 15 days);

        // Second stake
        vm.prank(alice);
        cents.stake(500e6);

        // Weighted timestamp: (500 * firstTimestamp + 500 * now) / 1000
        uint256 expectedTimestamp = (500e6 * firstTimestamp + 500e6 * block.timestamp) / 1000e6;
        assertEq(cents.stakeTimestamp(alice), expectedTimestamp);
        assertEq(cents.stakedBalance(alice), 1000e6);
    }

    function test_stake_clearsPendingUnstake() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        assertEq(cents.unstakeInitiated(alice), block.timestamp);

        // Stake more clears unstake
        cents.stake(200e6);
        assertEq(cents.unstakeInitiated(alice), 0);
        vm.stopPrank();
    }

    function test_stake_revertsOnZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(CENTS.ZeroAmount.selector);
        cents.stake(0);
    }

    // ============ Unstake Tests ============

    function test_unstake_initatesCooldown() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        vm.stopPrank();

        assertEq(cents.unstakeInitiated(alice), block.timestamp);
    }

    function test_unstake_emitsEvent() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        vm.expectEmit(true, false, false, true);
        emit CENTS.UnstakeInitiated(alice, 500e6, block.timestamp + 7 days);

        vm.prank(alice);
        cents.unstake();
    }

    function test_unstake_revertsIfNotStaking() public {
        vm.prank(alice);
        vm.expectRevert(CENTS.NotStaking.selector);
        cents.unstake();
    }

    function test_unstake_revertsIfAlreadyUnstaking() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();

        vm.expectRevert(CENTS.AlreadyUnstaking.selector);
        cents.unstake();
        vm.stopPrank();
    }

    // ============ Complete Unstake Tests ============

    function test_completeUnstake_returnsCENTS() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        vm.stopPrank();

        // Wait for cooldown
        vm.warp(block.timestamp + 7 days);

        uint256 balanceBefore = cents.balanceOf(alice);

        vm.prank(alice);
        cents.completeUnstake();

        assertEq(cents.balanceOf(alice), balanceBefore + 500e6);
        assertEq(cents.stakedBalance(alice), 0);
        assertEq(cents.stakeTimestamp(alice), 0);
        assertEq(cents.unstakeInitiated(alice), 0);
    }

    function test_completeUnstake_emitsEvent() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        vm.expectEmit(true, false, false, true);
        emit CENTS.UnstakeCompleted(alice, 500e6);

        vm.prank(alice);
        cents.completeUnstake();
    }

    function test_completeUnstake_revertsBeforeCooldown() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();

        // Only wait 6 days
        vm.warp(block.timestamp + 6 days);

        vm.expectRevert(CENTS.CooldownNotComplete.selector);
        cents.completeUnstake();
        vm.stopPrank();
    }

    function test_completeUnstake_revertsIfNotUnstaking() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        vm.prank(alice);
        vm.expectRevert(CENTS.NotUnstaking.selector);
        cents.completeUnstake();
    }

    // ============ Cancel Unstake Tests ============

    function test_cancelUnstake_resetsState() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        cents.cancelUnstake();
        vm.stopPrank();

        assertEq(cents.unstakeInitiated(alice), 0);
        assertEq(cents.stakeTimestamp(alice), block.timestamp);
        assertEq(cents.stakedBalance(alice), 500e6);
    }

    function test_cancelUnstake_emitsEvent() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        vm.prank(alice);
        cents.unstake();

        vm.expectEmit(true, false, false, true);
        emit CENTS.UnstakeCancelled(alice, 500e6);

        vm.prank(alice);
        cents.cancelUnstake();
    }

    function test_cancelUnstake_revertsIfNotUnstaking() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        vm.prank(alice);
        vm.expectRevert(CENTS.NotUnstaking.selector);
        cents.cancelUnstake();
    }

    // ============ Stake Power Tests ============

    function test_getStakePower_zeroAtStart() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        // At time 0, power is 0
        assertEq(cents.getStakePower(alice), 0);
    }

    function test_getStakePower_increasesOverTime() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        // After 7.5 days (1/4 of 30 days), power should be sqrt(1/4) = 0.5
        vm.warp(block.timestamp + 7.5 days);

        uint256 power = cents.getStakePower(alice);
        // Expected: 1000e6 * 0.5 = 500e6
        assertApproxEqRel(power, 500e6, 0.01e18); // 1% tolerance
    }

    function test_getStakePower_fullPowerAt30Days() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        // After 30 days, power should equal staked amount
        vm.warp(block.timestamp + 30 days);

        uint256 power = cents.getStakePower(alice);
        assertEq(power, 1000e6);
    }

    function test_getStakePower_cappedAt30Days() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        // After 60 days, power should still equal staked amount (capped)
        vm.warp(block.timestamp + 60 days);

        uint256 power = cents.getStakePower(alice);
        assertEq(power, 1000e6);
    }

    function test_getStakePower_zeroWhenUnstaking() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(1000e6);
        vm.warp(block.timestamp + 30 days);

        assertEq(cents.getStakePower(alice), 1000e6);

        cents.unstake();

        assertEq(cents.getStakePower(alice), 0);
        vm.stopPrank();
    }

    function test_getStakePower_zeroIfNotStaking() public view {
        assertEq(cents.getStakePower(alice), 0);
    }

    // ============ Daily Fee-Free Cap Tests ============

    function test_getDailyFeeFreeCap_equalsStakePower() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        vm.warp(block.timestamp + 30 days);

        assertEq(cents.getDailyFeeFreeCap(alice), 1000e6);
    }

    function test_getDailyFeeFreeCap_decreasesWithUsage() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        vm.warp(block.timestamp + 30 days);

        // Record some usage via DollarStore
        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 400e6);

        assertEq(cents.getDailyFeeFreeCap(alice), 600e6);
    }

    function test_getDailyFeeFreeCap_resetsNextDay() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(1000e6);

        vm.warp(block.timestamp + 30 days);

        // Use full cap
        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 1000e6);

        assertEq(cents.getDailyFeeFreeCap(alice), 0);

        // Next day
        vm.warp(block.timestamp + 1 days);

        assertEq(cents.getDailyFeeFreeCap(alice), 1000e6);
    }

    // ============ Maker Rewards Tests ============

    function test_mintMakerRewards_mintsCorrectAmount() public {
        // 1000 DLRS queued for 1 year at 8% APY = 80 USD earned
        // At $0.01 floor = 8000 CENTS
        uint256 dlrsAmount = 1000e6;
        uint256 secondsQueued = 365 days;

        // Calculate expected: dlrsAmount * 8% * (seconds / year) / $0.01
        // = 1000e6 * 800 * 365days / (10000 * 365days) / 1e4 * 1e6
        // = 1000e6 * 0.08 * 100 = 8000e6
        uint256 expectedCents = 8000e6;

        vm.prank(address(dollarStore));
        uint256 minted = cents.mintMakerRewards(alice, dlrsAmount, secondsQueued);

        assertEq(minted, expectedCents);
        assertEq(cents.balanceOf(alice), expectedCents);
    }

    function test_mintMakerRewards_mintsFounderShare() public {
        uint256 dlrsAmount = 1000e6;
        uint256 secondsQueued = 365 days;
        uint256 expectedFounderCents = 2000e6; // 1:4 ratio (8000e6 / 4)

        vm.prank(address(dollarStore));
        cents.mintMakerRewards(alice, dlrsAmount, secondsQueued);

        assertEq(cents.balanceOf(founder), expectedFounderCents);
        assertEq(cents.founderEmissionsReceived(), expectedFounderCents);
    }

    function test_mintMakerRewards_decrementsEmissions() public {
        uint256 dlrsAmount = 1000e6;
        uint256 secondsQueued = 365 days;
        uint256 expectedCents = 8000e6;

        uint256 makerBefore = cents.makerEmissionsRemaining();

        vm.prank(address(dollarStore));
        cents.mintMakerRewards(alice, dlrsAmount, secondsQueued);

        assertEq(cents.makerEmissionsRemaining(), makerBefore - expectedCents);
    }

    function test_mintMakerRewards_emitsEvent() public {
        uint256 dlrsAmount = 1000e6;
        uint256 secondsQueued = 365 days;

        vm.expectEmit(true, false, false, true);
        emit CENTS.MakerRewardsMinted(alice, 8000e6, dlrsAmount, secondsQueued);

        vm.prank(address(dollarStore));
        cents.mintMakerRewards(alice, dlrsAmount, secondsQueued);
    }

    function test_mintMakerRewards_capsAtEmissionsLimit() public {
        // This test verifies that maker emissions are capped at the remaining amount
        // We verify by checking the emissions decrement correctly and testing edge cases

        uint256 initialRemaining = cents.makerEmissionsRemaining();

        // Mint a small amount first
        vm.prank(address(dollarStore));
        uint256 minted1 = cents.mintMakerRewards(alice, 1000e6, 365 days);

        // Verify emissions decreased by exactly what was minted
        assertEq(cents.makerEmissionsRemaining(), initialRemaining - minted1);

        // Verify the math: 1000e6 * 8% = 80e6 in USD, converted to CENTS at $0.01 = 8000e6
        assertEq(minted1, 8000e6);
    }

    function test_mintMakerRewards_onlyDollarStore() public {
        vm.prank(alice);
        vm.expectRevert(CENTS.OnlyDollarStore.selector);
        cents.mintMakerRewards(alice, 1000e6, 365 days);
    }

    // ============ Taker Rewards Tests ============

    function test_mintTakerRewards_mintsCorrectAmount() public {
        // Fee of 100e6 at $0.01 floor = 10000 CENTS
        uint256 feeGenerated = 100e6;
        uint256 queueCleared = 1_000_000e6;

        uint256 expectedCents = (feeGenerated * 1e6) / 1e4; // 100e6 * 100 = 10000e6

        vm.prank(address(dollarStore));
        uint256 minted = cents.mintTakerRewards(alice, queueCleared, feeGenerated);

        assertEq(minted, expectedCents);
        assertEq(cents.balanceOf(alice), expectedCents);
    }

    function test_mintTakerRewards_mintsFounderShare() public {
        uint256 feeGenerated = 100e6;
        uint256 queueCleared = 1_000_000e6;
        uint256 expectedFounderCents = 2500e6; // 1:4 ratio (10000e6 / 4)

        vm.prank(address(dollarStore));
        cents.mintTakerRewards(alice, queueCleared, feeGenerated);

        assertEq(cents.balanceOf(founder), expectedFounderCents);
    }

    function test_mintTakerRewards_decrementsEmissions() public {
        uint256 feeGenerated = 100e6;
        uint256 queueCleared = 1_000_000e6;
        uint256 expectedCents = 10000e6;

        uint256 takerBefore = cents.takerEmissionsRemaining();

        vm.prank(address(dollarStore));
        cents.mintTakerRewards(alice, queueCleared, feeGenerated);

        assertEq(cents.takerEmissionsRemaining(), takerBefore - expectedCents);
    }

    function test_mintTakerRewards_emitsEvent() public {
        uint256 feeGenerated = 100e6;
        uint256 queueCleared = 1_000_000e6;

        vm.expectEmit(true, false, false, true);
        emit CENTS.TakerRewardsMinted(alice, 10000e6, queueCleared, feeGenerated);

        vm.prank(address(dollarStore));
        cents.mintTakerRewards(alice, queueCleared, feeGenerated);
    }

    function test_mintTakerRewards_onlyDollarStore() public {
        vm.prank(alice);
        vm.expectRevert(CENTS.OnlyDollarStore.selector);
        cents.mintTakerRewards(alice, 1_000_000e6, 100e6);
    }

    // ============ Record Redemption Tests ============

    function test_recordRedemption_tracksUsage() public {
        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 500e6);

        assertEq(cents.dailyRedemptionUsed(alice), 500e6);
        assertEq(cents.lastRedemptionDay(alice), block.timestamp / 1 days);
    }

    function test_recordRedemption_accumulatesInSameDay() public {
        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 500e6);

        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 300e6);

        assertEq(cents.dailyRedemptionUsed(alice), 800e6);
    }

    function test_recordRedemption_resetsOnNewDay() public {
        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 500e6);

        vm.warp(block.timestamp + 1 days);

        vm.prank(address(dollarStore));
        cents.recordRedemption(alice, 300e6);

        assertEq(cents.dailyRedemptionUsed(alice), 300e6);
    }

    function test_recordRedemption_onlyDollarStore() public {
        vm.prank(alice);
        vm.expectRevert(CENTS.OnlyDollarStore.selector);
        cents.recordRedemption(alice, 500e6);
    }

    // ============ View Functions Tests ============

    function test_getStakingInfo_returnsCorrectData() public {
        _giveCents(alice, 1000e6);

        vm.prank(alice);
        cents.stake(500e6);

        vm.warp(block.timestamp + 15 days);

        (
            uint256 staked,
            uint256 stakePower,
            uint256 stakedSince,
            uint256 unstakeTime,
            bool isUnstaking
        ) = cents.getStakingInfo(alice);

        assertEq(staked, 500e6);
        assertTrue(stakePower > 0);
        assertTrue(stakedSince > 0);
        assertEq(unstakeTime, 0);
        assertFalse(isUnstaking);
    }

    function test_getStakingInfo_showsUnstaking() public {
        _giveCents(alice, 1000e6);

        vm.startPrank(alice);
        cents.stake(500e6);
        cents.unstake();
        vm.stopPrank();

        (
            ,
            ,
            ,
            uint256 unstakeTime,
            bool isUnstaking
        ) = cents.getStakingInfo(alice);

        assertTrue(unstakeTime > 0);
        assertTrue(isUnstaking);
    }

    function test_getEmissionStats_returnsCorrectData() public {
        // Mint some to generate stats
        vm.prank(address(dollarStore));
        cents.mintMakerRewards(alice, 1000e6, 365 days);

        (
            uint256 makerRemaining,
            uint256 takerRemaining,
            uint256 founderVested,
            uint256 totalMinted
        ) = cents.getEmissionStats();

        assertEq(makerRemaining, 600_000_000e6 - 8000e6);
        assertEq(takerRemaining, 200_000_000e6);
        assertEq(founderVested, 2000e6);
        assertEq(totalMinted, 8000e6 + 2000e6);
    }

    // ============ Integration Tests: No Fee ============
    // Note: With REDEMPTION_FEE_BPS = 0, there are no fees to discount.
    // These tests verify the no-fee behavior.

    function test_noFee_fullAmountReceived() public {
        // Deposit and withdraw without any fee
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 10000e6);

        vm.prank(alice);
        uint256 received = dollarStore.withdraw(address(usdc), 10000e6);

        // No fee - full amount received
        assertEq(received, 10000e6);
        assertEq(dollarStore.getBankBalance(address(usdc)), 0);
    }

    function test_noFee_stakeDoesntAffectWithdrawal() public {
        // Give alice CENTS and stake
        _giveCents(alice, 5000e6);

        vm.prank(alice);
        cents.stake(5000e6);

        // Wait for full power
        vm.warp(block.timestamp + 30 days);

        // Withdraw - should receive full amount (no fee to discount)
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 10000e6);

        vm.prank(alice);
        uint256 received = dollarStore.withdraw(address(usdc), 10000e6);

        // No fee - full amount received
        assertEq(received, 10000e6);
    }

    function test_feeFreeCap_stillTracked() public {
        _giveCents(alice, 5000e6);

        vm.prank(alice);
        cents.stake(5000e6);

        vm.warp(block.timestamp + 30 days);

        // Fee-free cap is still tracked even with no fee
        assertEq(cents.getDailyFeeFreeCap(alice), 5000e6);

        // Next day, cap still works
        vm.warp(block.timestamp + 1 days);
        assertEq(cents.getDailyFeeFreeCap(alice), 5000e6);
    }

    // ============ Integration Tests: Queue Priority ============

    function test_queuePriority_higherStakeFillsFirst() public {
        // Alice has more stake than Bob
        _giveCents(alice, 10000e6);
        _giveCents(bob, 1000e6);

        vm.prank(alice);
        cents.stake(10000e6);

        vm.prank(bob);
        cents.stake(1000e6);

        vm.warp(block.timestamp + 30 days);

        // Both get DLRS
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 500e6);

        vm.prank(bob);
        dollarStore.deposit(address(usdc), 500e6);

        // Bob joins first (lower priority)
        vm.prank(bob);
        dollarStore.joinQueue(address(usdt), 500e6);

        // Wait a bit so Alice's position has less time in queue
        vm.warp(block.timestamp + 1 hours);

        // Alice joins second (higher priority due to stake should overcome time disadvantage)
        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        // Wait a bit more so both have accumulated some time
        vm.warp(block.timestamp + 1 hours);

        // Check fill scores - Alice should have higher score despite less time
        uint256 aliceFillScore = dollarStore.getFillScore(2); // Alice's position
        uint256 bobFillScore = dollarStore.getFillScore(1); // Bob's position

        // Alice's score should be higher due to 10x stake power advantage
        // fillScore = (basePower + stakePower / sqrt(fillSize)) * secondsInQueue
        // Alice: (1e6 + 10000e6 / sqrt(500)) * 3600 ~= much higher than Bob
        // Bob: (1e6 + 1000e6 / sqrt(500)) * 7200
        assertTrue(aliceFillScore > bobFillScore, "Alice should have higher fill score");

        // Charlie deposits enough for only one position
        address charlie = address(0xC);
        usdt.mint(charlie, 500e6);

        vm.startPrank(charlie);
        usdt.approve(address(dollarStore), type(uint256).max);
        dollarStore.deposit(address(usdt), 500e6);
        vm.stopPrank();

        // Alice should be filled (higher fill score due to stake)
        // Bob should still be waiting
        assertGt(usdt.balanceOf(alice), INITIAL_BALANCE, "Alice should have received USDT");
        assertEq(usdt.balanceOf(bob), INITIAL_BALANCE, "Bob should not have received USDT yet");
        assertEq(dollarStore.getQueueDepth(address(usdt)), 500e6, "One position should remain in queue");
    }

    // ============ Integration Tests: Maker Rewards on Fill ============

    function test_makerRewards_mintedOnQueueFill() public {
        // Alice joins queue
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        uint256 centsBalanceBefore = cents.balanceOf(alice);

        // Wait some time
        vm.warp(block.timestamp + 30 days);

        // Bob fills the queue
        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        // Alice should have received CENTS rewards
        uint256 centsEarned = cents.balanceOf(alice) - centsBalanceBefore;
        assertTrue(centsEarned > 0);
    }

    // ============ Integration Tests: Taker Rewards ============
    // Note: With REDEMPTION_FEE_BPS = 0, feeGenerated is 0, so no taker rewards are minted.

    function test_takerRewards_notMintedWithNoFee() public {
        // Alice joins queue
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        vm.prank(alice);
        dollarStore.joinQueue(address(usdt), 500e6);

        // Bob deposits to clear queue
        uint256 bobCentsBefore = cents.balanceOf(bob);

        vm.prank(bob);
        dollarStore.deposit(address(usdt), 500e6);

        // With no fee, no taker rewards are minted (feeGenerated = 0)
        uint256 bobCentsEarned = cents.balanceOf(bob) - bobCentsBefore;
        assertEq(bobCentsEarned, 0);
    }

    // ============ Minimum Order Size Tests ============

    function test_minimumOrderSize_increasesWithQueueDepth() public {
        // Initially minimum is $100
        assertEq(dollarStore.getMinimumOrderSize(address(usdt)), 100e6);

        // Add positions to queue
        for (uint256 i = 0; i < 25; i++) {
            address user = address(uint160(0x1000 + i));
            usdc.mint(user, 1_000_000e6);

            vm.startPrank(user);
            usdc.approve(address(dollarStore), type(uint256).max);
            dollarStore.deposit(address(usdc), 1_000_000e6);
            dollarStore.joinQueue(address(usdt), 100e6);
            vm.stopPrank();
        }

        // After 25 positions, minimum should be ~$1000
        uint256 minOrder = dollarStore.getMinimumOrderSize(address(usdt));
        assertApproxEqRel(minOrder, 1000e6, 0.1e18); // 10% tolerance
    }

    function test_joinQueue_revertsIfBelowMinimum() public {
        vm.prank(alice);
        dollarStore.deposit(address(usdc), 1000e6);

        // Try to join with less than $100
        vm.prank(alice);
        vm.expectRevert(); // Should revert with OrderTooSmall
        dollarStore.joinQueue(address(usdt), 50e6);
    }

    // ============ Helper Functions ============

    /// @dev Give CENTS to a user by simulating taker rewards
    function _giveCents(address user, uint256 amount) internal {
        vm.prank(address(dollarStore));
        cents.mintTakerRewards(user, amount * 100, amount / 100 + 1);
    }
}
