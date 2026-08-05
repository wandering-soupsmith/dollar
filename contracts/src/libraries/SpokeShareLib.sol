// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SpokeShareLib - Pro-rata share math for non-transferable spoke LP receipts (U2)
/// @notice A spoke is a two-component pool: its spoke-asset reserve plus an internal DLRS-side
///         reserve (`dlrsReserve`). Both are normalized 6-decimal, par-valued dollar amounts, so the
///         pool's total value is the scalar `poolValue = spokeReserve + dlrsReserve`. LP receipts are
///         a pro-rata claim on that value. This library is the pure mint/burn conversion.
/// @dev All rounding is DOWN (against the caller): a depositor never mints more claim than the value
///      they add, and a redeemer never draws more than their share. No MINIMUM_LIQUIDITY lock is used
///      because `poolValue` is INTERNAL accounting, not `balanceOf`, so the classic donate-to-inflate
///      first-depositor attack is impossible; keeping total shares able to reach zero also lets a fully
///      wound-down spoke reach the all-zero state required by removePool.
/// @custom:security-contact admin@dollarstore.world
library SpokeShareLib {
    /// @notice Deposit value must be non-zero.
    error ZeroValue();
    /// @notice Share amount must be non-zero.
    error ZeroShares();
    /// @notice A deposit was too small to mint any shares at the current share price.
    error DepositTooSmall();
    /// @notice Requested more shares than the pool has outstanding.
    error InsufficientShares(uint256 requested, uint256 available);

    /// @notice Shares to mint for depositing `valueIn` into a spoke pool.
    /// @dev First LP into an empty pool mints 1:1 with value. Otherwise shares are pro-rata against the
    ///      pool value BEFORE this deposit, rounded down. Reverts if the deposit is too small to mint a
    ///      whole share (which would otherwise donate the value to existing LPs).
    /// @param valueIn Deposited value in normalized 6dp units.
    /// @param poolValueBefore Pool value (spokeReserve + dlrsReserve) BEFORE this deposit, 6dp.
    /// @param totalShares Outstanding shares BEFORE this deposit.
    /// @return shares Shares to mint to the depositor.
    function sharesForDeposit(uint256 valueIn, uint256 poolValueBefore, uint256 totalShares)
        internal
        pure
        returns (uint256 shares)
    {
        if (valueIn == 0) revert ZeroValue();
        if (totalShares == 0 || poolValueBefore == 0) {
            return valueIn; // first LP: 1:1
        }
        shares = Math.mulDiv(valueIn, totalShares, poolValueBefore); // floor
        if (shares == 0) revert DepositTooSmall();
    }

    /// @notice Like {sharesForDeposit} but returns 0 instead of reverting when the value is too small
    ///         to mint a whole share. For fallback paths (blacklist eject converting escrow into a
    ///         receipt) where reverting would brick the queue; the negligible dust simply accrues to
    ///         existing LPs rather than blocking the eject.
    function sharesForDepositOrZero(uint256 valueIn, uint256 poolValueBefore, uint256 totalShares)
        internal
        pure
        returns (uint256 shares)
    {
        if (valueIn == 0) return 0;
        if (totalShares == 0 || poolValueBefore == 0) return valueIn;
        return Math.mulDiv(valueIn, totalShares, poolValueBefore); // floor, may be 0 for extreme dust
    }

    /// @notice Value redeemable for burning `sharesIn` of a spoke pool.
    /// @dev Pro-rata against current pool value, rounded down. If the pool is value-impaired
    ///      (poolValue < totalShares after a write-down), each share simply pays less, sharing the loss.
    /// @param sharesIn Shares being burned.
    /// @param poolValue Current pool value (spokeReserve + dlrsReserve), 6dp.
    /// @param totalShares Outstanding shares BEFORE this burn.
    /// @return value Redeemable value in normalized 6dp units (rounded down).
    function valueForShares(uint256 sharesIn, uint256 poolValue, uint256 totalShares)
        internal
        pure
        returns (uint256 value)
    {
        if (sharesIn == 0) revert ZeroShares();
        if (sharesIn > totalShares) revert InsufficientShares(sharesIn, totalShares);
        // totalShares >= sharesIn >= 1 here, so mulDiv never divides by zero (no dead guard needed).
        value = Math.mulDiv(sharesIn, poolValue, totalShares); // floor
    }
}
