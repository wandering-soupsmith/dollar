// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title NormalizationLib - Decimal normalization helpers (native <-> 6-decimal units)
/// @notice All internal accounting is in 6-decimal normalized units; native token amounts are
///         converted only at transfer boundaries. Conversions round in the protocol's favor:
///         inbound amounts round DOWN, leaving sub-unit dust with the user.
/// @dev Supports tokens with 6..18 decimals. Rebasing / fee-on-transfer tokens are out of policy.
/// @custom:security-contact admin@dollarstore.world
library NormalizationLib {
    /// @notice Internal accounting precision.
    uint8 internal constant BASE_DECIMALS = 6;
    /// @notice Minimum supported token decimals.
    uint8 internal constant MIN_DECIMALS = 6;
    /// @notice Maximum supported token decimals.
    uint8 internal constant MAX_DECIMALS = 18;

    /// @notice Token decimals outside the supported [6, 18] range.
    error UnsupportedDecimals(uint8 decimals);

    /// @notice Compute the scaling factor 10**(decimals - 6) for a token.
    /// @dev Reverts if decimals are outside [6, 18]. Result fits in uint64 (max 10**12).
    /// @param decimals_ The token's decimals.
    /// @return The scaling factor between native units and 6-decimal normalized units.
    function scalingFactor(uint8 decimals_) internal pure returns (uint64) {
        if (decimals_ < MIN_DECIMALS || decimals_ > MAX_DECIMALS) revert UnsupportedDecimals(decimals_);
        return uint64(10 ** (uint256(decimals_) - BASE_DECIMALS));
    }

    /// @notice Convert a native token amount to normalized 6dp units, rounding DOWN.
    /// @param nativeAmount The amount in the token's native decimals.
    /// @param scaling The token's scaling factor (from `scalingFactor`).
    /// @return units The amount in normalized 6dp units (rounded down).
    /// @return nativePulled The native amount the protocol should actually pull (units * scaling);
    ///         any difference `nativeAmount - nativePulled` is sub-unit dust that stays with the user.
    function toUnits(uint256 nativeAmount, uint64 scaling) internal pure returns (uint256 units, uint256 nativePulled) {
        units = nativeAmount / scaling;
        nativePulled = units * scaling;
    }

    /// @notice Convert normalized 6dp units back to a native token amount (exact).
    /// @param units The amount in normalized 6dp units.
    /// @param scaling The token's scaling factor.
    /// @return The amount in the token's native decimals.
    function toNative(uint256 units, uint64 scaling) internal pure returns (uint256) {
        return units * scaling;
    }
}
