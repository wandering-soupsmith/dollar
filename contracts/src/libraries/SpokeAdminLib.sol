// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDollarStore} from "../interfaces/IDollarStore.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {RegistryStorage} from "../storage/RegistryStorage.sol";
import {QueueStorage} from "../storage/QueueStorage.sol";
import {NormalizationLib} from "./NormalizationLib.sol";

/// @title SpokeAdminLib - cold-path spoke logic extracted from DollarStore to stay under EIP-170.
/// @notice External library whose public functions run in the DollarStore proxy's storage context via
///         delegatecall (they read/write the same ERC-7201 namespaced slots and preserve msg.sender).
///         Holds the rarely-called spoke-admin functions - spoke creation and the reserve write-down /
///         excess-sweep tools - so the hot swap/deposit/withdraw paths stay inline in DollarStore (no
///         delegatecall overhead on trades). The remaining spoke tooling (wind-down / escrow-haircut /
///         removePool / redeemSpoke) lives in SpokeLifecycleLib; the directed-swap engine lives in
///         SwapRouteLib. All three are linked and deployed with the implementation (full feature set,
///         single deployment).
/// @dev Access control (onlyGovernor / onlyGuardian / nonReentrant) stays on the DollarStore wrappers
///      and runs BEFORE delegating here; these functions assume they are already gated.
/// @custom:security-contact admin@dollarstore.world
library SpokeAdminLib {
    using SafeERC20 for IERC20;

    /// @dev Max supported price-feed decimals (mirrors DollarStore.MAX_FEED_DECIMALS).
    uint8 private constant MAX_FEED_DECIMALS = 18;

    // Events are re-declared here so they can be emitted from library code; in delegatecall they are
    // logged from the DollarStore proxy address, identical to emitting them directly in the contract.
    event PoolCreated(uint16 indexed poolId, uint8 kind);
    event AssetListed(address indexed asset, uint16 indexed poolId, uint8 decimals, address priceFeed);
    event MinDlrsReserveSet(uint16 indexed poolId, uint256 oldMin, uint256 newMin);
    event ReservesSynced(address indexed asset, uint256 oldReserves, uint256 newReserves);
    event TokensRescued(address indexed asset, address indexed to, uint256 amount);

    /// @notice Create a spoke pool for `spokeAsset` (see IDollarStore.createSpoke).
    function createSpoke(address spokeAsset, address priceFeed, uint256 minDlrsReserve_)
        external
        returns (uint16 poolId)
    {
        if (spokeAsset == address(0) || priceFeed == address(0)) revert IDollarStore.ZeroAddress();
        uint8 feedDec = AggregatorV3Interface(priceFeed).decimals();
        if (feedDec > MAX_FEED_DECIMALS) revert NormalizationLib.UnsupportedDecimals(feedDec);

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (r.assetConfig[spokeAsset].listed) revert IDollarStore.AssetAlreadyListed(spokeAsset);

        uint256 newIndex = r.pools.length;
        if (newIndex > type(uint16).max) revert IDollarStore.MaxPoolsReached();
        poolId = uint16(newIndex);

        uint8 dec = IERC20Metadata(spokeAsset).decimals();
        uint64 sf = NormalizationLib.scalingFactor(dec);

        RegistryStorage.Pool storage p = r.pools.push();
        p.kind = RegistryStorage.PoolKind.Spoke;
        p.minDlrsReserve = minDlrsReserve_;

        r.assetConfig[spokeAsset] = RegistryStorage.AssetConfig({
            poolId: poolId, decimals: dec, scalingFactor: sf, priceFeed: priceFeed, listed: true, depositPaused: false
        });
        p.assets.push(spokeAsset);

        emit PoolCreated(poolId, uint8(RegistryStorage.PoolKind.Spoke));
        emit AssetListed(spokeAsset, poolId, dec, priceFeed);
        emit MinDlrsReserveSet(poolId, 0, minDlrsReserve_);
    }

    /// @notice Escrow-aware reserve write-down (see IDollarStore.syncReserves).
    function syncReserves(uint16 poolId, address asset) external {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (!cfg.listed) revert IDollarStore.AssetNotListed(asset);
        if (cfg.poolId != poolId) revert IDollarStore.WrongPool(asset, poolId);

        uint256 actualUnits = IERC20(asset).balanceOf(address(this)) / cfg.scalingFactor;
        uint256 escrowUnits = QueueStorage.layout().totalEscrowedByAsset[asset];
        uint256 prevReserves = r.reserves[poolId][asset];

        if (actualUnits >= prevReserves + escrowUnits) revert IDollarStore.ReservesNotDrifted(asset);
        if (actualUnits < escrowUnits) revert IDollarStore.EscrowImpaired(asset); // deeper haircut path deferred

        uint256 newReserves = actualUnits - escrowUnits;
        r.reserves[poolId][asset] = newReserves;
        emit ReservesSynced(asset, prevReserves, newReserves);
    }

    /// @notice Sweep the excess of `asset` above accounted (reserves + escrow) (see IDollarStore.rescueTokens).
    function rescueTokens(address asset, address to) external {
        if (to == address(0)) revert IDollarStore.ZeroAddress();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];

        uint256 actual = IERC20(asset).balanceOf(address(this));
        uint256 accounted = 0;
        if (cfg.listed) {
            uint256 escrowUnits = QueueStorage.layout().totalEscrowedByAsset[asset];
            accounted = (r.reserves[cfg.poolId][asset] + escrowUnits) * cfg.scalingFactor;
        }
        if (actual <= accounted) revert IDollarStore.NoExcessTokens(asset);

        uint256 excess = actual - accounted;
        IERC20(asset).safeTransfer(to, excess);
        emit TokensRescued(asset, to, excess);
    }
}
