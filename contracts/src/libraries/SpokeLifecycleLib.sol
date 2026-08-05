// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IDollarStore} from "../interfaces/IDollarStore.sol";
import {RegistryStorage} from "../storage/RegistryStorage.sol";
import {QueueStorage} from "../storage/QueueStorage.sol";
import {QueueLib} from "./QueueLib.sol";
import {NormalizationLib} from "./NormalizationLib.sol";

/// @title SpokeLifecycleLib - spoke wind-down / impairment / removal / redeem logic.
/// @notice Holds the spoke wind-down, escrow-impairment haircut, pool-removal and proportional-redeem
///         bodies. These ship in this deployment but live in an external library (deployed separately,
///         linked to DollarStore) so the DollarStore implementation stays under the EIP-170 24576-byte
///         runtime limit. Being cold, admin/emergency functions, hosting them via delegatecall costs
///         no gas on the hot swap path.
/// @dev External library: its public functions run in the DollarStore proxy storage context via
///      delegatecall (same ERC-7201 slots, msg.sender and block.timestamp preserved). The DollarStore
///      wrappers keep the access modifiers (onlyGovernor / onlyGuardian / nonReentrant) and run BEFORE
///      delegating here, so these functions assume they are already access-gated.
/// @custom:security-contact admin@dollarstore.world
library SpokeLifecycleLib {
    using SafeERC20 for IERC20;

    // Re-declared so library code can emit them; under delegatecall they log from the proxy address.
    event PoolRemoved(uint16 indexed poolId);
    event SpokeWindDownStarted(uint16 indexed poolId);
    event EscrowHaircut(address indexed asset, uint16 indexed poolId, uint256 oldEscrow, uint256 newEscrow);
    event SpokeRedeemed(
        uint16 indexed poolId, address indexed provider, uint256 sharesBurned, uint256 spokeUnits, uint256 dlrsUnits
    );

    /// @dev Returns the spoke pool at `poolId`, reverting InvalidPool if it does not exist and
    ///      PoolNotSpoke if it is the hub.
    function _spoke(RegistryStorage.Layout storage r, uint16 poolId)
        private
        view
        returns (RegistryStorage.Pool storage p)
    {
        if (poolId >= r.pools.length) revert IDollarStore.InvalidPool(poolId);
        p = r.pools[poolId];
        if (p.kind != RegistryStorage.PoolKind.Spoke) revert IDollarStore.PoolNotSpoke(poolId);
    }

    /// @notice Enter the winding-down state for a spoke (see IDollarStore.windDownSpoke).
    function windDownSpoke(uint16 poolId) external {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.Pool storage p = _spoke(r, poolId);
        if (p.status != RegistryStorage.PoolStatus.Active) revert IDollarStore.SpokeWindingDown(poolId);
        p.status = RegistryStorage.PoolStatus.WindingDown;
        emit SpokeWindDownStarted(poolId);
    }

    /// @notice Kill a fully-drained spoke (see IDollarStore.removePool).
    function removePool(uint16 poolId) external {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.Pool storage p = _spoke(r, poolId);
        if (p.dlrsReserve != 0) revert IDollarStore.PoolNotEmpty(poolId);
        if (r.receiptTotalShares[poolId] != 0) revert IDollarStore.PoolNotEmpty(poolId);

        address[] storage spokeAssets = p.assets;
        address[] storage hubAssets = r.pools[0].assets;
        QueueStorage.Layout storage qs = QueueStorage.layout();
        for (uint256 i; i < spokeAssets.length; ++i) {
            address sa = spokeAssets[i];
            if (r.reserves[poolId][sa] != 0) revert IDollarStore.PoolNotEmpty(poolId);
            for (uint256 j; j < hubAssets.length; ++j) {
                address ha = hubAssets[j];
                if (qs.queues[QueueStorage.queueKey(sa, ha)].totalDepth != 0) revert IDollarStore.PoolNotEmpty(poolId);
                if (qs.queues[QueueStorage.queueKey(ha, sa)].totalDepth != 0) revert IDollarStore.PoolNotEmpty(poolId);
            }
            r.assetConfig[sa].listed = false;
        }

        p.paused = true;
        p.status = RegistryStorage.PoolStatus.Killed;
        emit PoolRemoved(poolId);
    }

    /// @notice Guardian escrow-impairment haircut (see IDollarStore.haircutEscrow).
    function haircutEscrow(address asset, uint256 maxPositions) external returns (uint256 removedUnits) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (!cfg.listed) revert IDollarStore.AssetNotListed(asset);
        if (!r.pools[cfg.poolId].paused) revert IDollarStore.PoolNotPaused(cfg.poolId);

        QueueStorage.Layout storage qs = QueueStorage.layout();
        uint256 escrow = qs.totalEscrowedByAsset[asset];
        if (escrow == 0) revert IDollarStore.NoEscrowToHaircut(asset);

        uint256 actualUnits = IERC20(asset).balanceOf(address(this)) / cfg.scalingFactor;
        uint256 reserves = r.reserves[cfg.poolId][asset];
        if (actualUnits >= reserves + escrow) revert IDollarStore.AssetNotImpaired(asset);

        uint256 targetEscrow = actualUnits > reserves ? actualUnits - reserves : 0;

        uint256 budget = maxPositions;
        uint256 poolLen = r.pools.length;
        for (uint256 pid; pid < poolLen; ++pid) {
            address[] storage passets = r.pools[pid].assets;
            for (uint256 a; a < passets.length; ++a) {
                address want = passets[a];
                if (want == asset) continue;
                budget = _haircutQueue(qs, asset, want, targetEscrow, escrow, budget);
            }
        }

        uint256 newEscrow = qs.totalEscrowedByAsset[asset];
        removedUnits = escrow - newEscrow;
        emit EscrowHaircut(asset, cfg.poolId, escrow, newEscrow);
    }

    function _haircutQueue(
        QueueStorage.Layout storage qs,
        address offerAsset,
        address wantAsset,
        uint256 targetEscrow,
        uint256 escrow,
        uint256 budget
    ) private returns (uint256) {
        uint256 current = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].head;
        while (current != 0) {
            if (budget == 0) revert IDollarStore.HaircutBudgetExceeded();
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            uint256 amt = p.offerAmount;
            uint256 newAmt = Math.mulDiv(amt, targetEscrow, escrow); // floor, pro-rata
            if (newAmt == 0) {
                QueueLib.remove(qs, current);
            } else if (newAmt < amt) {
                QueueLib.reduce(qs, current, amt - newAmt);
            }
            budget -= 1;
            current = next;
        }
        return budget;
    }

    /// @notice Proportional spoke redemption across both sides (see IDollarStore.redeemSpoke).
    function redeemSpoke(uint16 poolId, uint256 shares, uint256 deadline)
        external
        returns (uint256 spokeUnits, uint256 dlrsUnits)
    {
        if (block.timestamp > deadline) revert IDollarStore.DeadlineExpired(deadline, block.timestamp);
        if (shares == 0) revert IDollarStore.ZeroAmount();

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.Pool storage p = _spoke(r, poolId);

        uint256 ownerShares = r.receiptShares[poolId][msg.sender];
        if (ownerShares < shares) revert IDollarStore.InsufficientReceiptShares(shares, ownerShares);

        uint256 total = r.receiptTotalShares[poolId];
        address spokeAsset = p.assets[0];
        uint256 spokeReserve = r.reserves[poolId][spokeAsset];

        spokeUnits = Math.mulDiv(shares, spokeReserve, total); // floor, pro-rata
        dlrsUnits = Math.mulDiv(shares, p.dlrsReserve, total); // floor, pro-rata
        if (spokeUnits == 0 && dlrsUnits == 0) revert IDollarStore.ZeroAmount();

        r.receiptShares[poolId][msg.sender] = ownerShares - shares;
        r.receiptTotalShares[poolId] = total - shares;

        if (spokeUnits > 0) {
            r.reserves[poolId][spokeAsset] = spokeReserve - spokeUnits;
            IERC20(spokeAsset)
                .safeTransfer(
                    msg.sender, NormalizationLib.toNative(spokeUnits, r.assetConfig[spokeAsset].scalingFactor)
                );
        }

        if (dlrsUnits > 0) {
            p.dlrsReserve -= dlrsUnits;
            uint256 remaining = dlrsUnits;
            address[] storage hubAssets = r.pools[0].assets;
            for (uint256 i; i < hubAssets.length && remaining > 0; ++i) {
                address h = hubAssets[i];
                uint256 hr = r.reserves[0][h];
                if (hr == 0) continue;
                uint256 pay = remaining < hr ? remaining : hr;
                r.reserves[0][h] = hr - pay;
                remaining -= pay;
                IERC20(h).safeTransfer(msg.sender, NormalizationLib.toNative(pay, r.assetConfig[h].scalingFactor));
            }
            if (remaining != 0) revert IDollarStore.InsufficientReserves(spokeAsset, dlrsUnits, dlrsUnits - remaining);
        }

        emit SpokeRedeemed(poolId, msg.sender, shares, spokeUnits, dlrsUnits);
    }
}
