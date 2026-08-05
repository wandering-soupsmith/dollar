// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IDollarStore} from "../interfaces/IDollarStore.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {RegistryStorage} from "../storage/RegistryStorage.sol";
import {CoreStorage} from "../storage/CoreStorage.sol";

/// @title PegLib - shared oracle peg + inflow gating
/// @notice Single source of truth for the deposit-inflow gate (per-asset deposit pause, pool pause,
///         and the oracle peg / staleness check) shared by the implementation and SwapRouteLib. It
///         exposes both a reverting form (`checkInflow` / `checkPeg`) for callers that must reject a
///         toxic inflow and a non-reverting form (`canInflow`) for callers that must skip it. Keeping
///         one copy avoids the drift risk of applying a peg-tolerance or staleness change to some but
///         not all of these gates.
/// @dev All functions are `internal` and read the same ERC-7201 namespaced storage the callers do, so
///      they are inlined into the caller and add no linking or delegatecall cost.
library PegLib {
    /// @dev Fixed-point decimals the normalized oracle price is compared against (one dollar == ONE).
    uint256 internal constant PRICE_DECIMALS = 18;
    /// @dev One dollar in PRICE_DECIMALS fixed point.
    uint256 internal constant ONE = 1e18;
    /// @dev Basis-points denominator (100% == 10_000 bps).
    uint256 internal constant BPS_DENOMINATOR = 10_000;

    /// @dev Reverts if `asset` is deposit-paused, its pool is paused, or it is off-peg / stale.
    function checkInflow(address asset) internal view {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (cfg.depositPaused) revert IDollarStore.DepositsPaused(asset);
        if (r.pools[cfg.poolId].paused) revert IDollarStore.PoolPaused(cfg.poolId);
        checkPeg(asset, cfg);
    }

    /// @dev Reverts if the asset's oracle price is missing, invalid, stale, or off-peg.
    function checkPeg(address asset, RegistryStorage.AssetConfig storage cfg) internal view {
        address feed = cfg.priceFeed;
        if (feed == address(0)) revert IDollarStore.NoPriceFeed(asset);

        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = agg.latestRoundData();
        if (answer <= 0) revert IDollarStore.InvalidPrice(asset);
        if (answeredInRound < roundId) revert IDollarStore.StaleRound(asset);

        CoreStorage.Layout storage c = CoreStorage.layout();
        if (block.timestamp - updatedAt > c.maxStaleness) revert IDollarStore.PriceStale(asset, updatedAt);

        uint256 scale = 10 ** (PRICE_DECIMALS - uint256(agg.decimals()));
        uint256 normalized = uint256(answer) * scale;
        uint256 lower = ONE - (ONE * c.pegTolerance / BPS_DENOMINATOR);
        uint256 upper = ONE + (ONE * c.pegTolerance / BPS_DENOMINATOR);
        if (normalized < lower || normalized > upper) {
            revert IDollarStore.PriceOutOfBounds(asset, normalized, lower, upper);
        }
    }

    /// @dev Non-reverting counterpart of `checkInflow`: returns true iff `asset` is safe to absorb into
    ///      reserves right now (not deposit-paused, its pool not paused, and its oracle is present, valid,
    ///      fresh and on-peg). Used to SKIP (not revert on) an unhealthy asset, so an unrelated bad asset
    ///      cannot DoS a legitimate deposit. A reverting feed reads as false.
    function canInflow(address asset) internal view returns (bool) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (cfg.depositPaused) return false;
        if (r.pools[cfg.poolId].paused) return false;

        address feed = cfg.priceFeed;
        if (feed == address(0)) return false;

        try AggregatorV3Interface(feed).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            if (answer <= 0) return false;
            if (answeredInRound < roundId) return false;

            CoreStorage.Layout storage c = CoreStorage.layout();
            if (block.timestamp - updatedAt > c.maxStaleness) return false;

            uint256 scale = 10 ** (PRICE_DECIMALS - uint256(AggregatorV3Interface(feed).decimals()));
            uint256 normalized = uint256(answer) * scale;
            uint256 lower = ONE - (ONE * c.pegTolerance / BPS_DENOMINATOR);
            uint256 upper = ONE + (ONE * c.pegTolerance / BPS_DENOMINATOR);
            return normalized >= lower && normalized <= upper;
        } catch {
            return false;
        }
    }
}
