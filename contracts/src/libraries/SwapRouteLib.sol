// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDollarStore} from "../interfaces/IDollarStore.sol";
import {AggregatorV3Interface} from "../interfaces/AggregatorV3Interface.sol";
import {RegistryStorage} from "../storage/RegistryStorage.sol";
import {QueueStorage} from "../storage/QueueStorage.sol";
import {CoreStorage} from "../storage/CoreStorage.sol";
import {NormalizationLib} from "./NormalizationLib.sol";
import {QueueLib} from "./QueueLib.sol";
import {SpokeShareLib} from "./SpokeShareLib.sol";
import {DLRS} from "../DLRS.sol";

/// @title SwapRouteLib - directed-swap routing, fill and FIFO settlement subsystem.
/// @notice The full directed-queue swap engine (route classification + reserve-aware fills + FIFO
///         same-direction settlement + escrow refund) extracted out of DollarStore so the
///         implementation fits under the EIP-170 24576-byte runtime limit while still shipping the
///         complete U2 feature set in a single deployment. The state-changing entrypoints (swap,
///         swapExactInput, processQueue, triggerSpokeQueues, cancelPosition) are `public`, so
///         DollarStore reaches them via DELEGATECALL: they run in the proxy storage context (same
///         ERC-7201 slots) and msg.sender / block.timestamp are preserved. This is the accepted cost
///         of fitting everything in one implementation (~1 delegatecall per swap).
/// @dev Access gating (nonReentrant / whenNotPaused / owner checks) stays on the DollarStore wrappers
///      and runs BEFORE delegating here. The internal helpers are shared with DollarStore's inline
///      views (getSwapQuote) via direct `SwapRouteLib.<fn>` calls, which inline (no delegatecall).
/// @custom:security-contact admin@dollarstore.world
library SwapRouteLib {
    using SafeERC20 for IERC20;

    /// @dev Max positions settled inline from reserves per directed queue in a single call.
    uint256 private constant MAX_INLINE_SETTLE = 8;
    /// @dev Fixed-point decimals the normalized oracle price is compared against.
    uint256 private constant PRICE_DECIMALS = 18;
    uint256 private constant ONE = 1e18;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev The three supported swap routes. Spoke-to-spoke is rejected (done as two hub-legged swaps).
    enum RouteKind {
        HubToHub,
        HubToSpoke,
        SpokeToHub
    }

    /// @dev A validated swap route: its kind, the spoke pool involved (0 for HubToHub), and the
    ///      offer/want scaling factors.
    struct Route {
        RouteKind kind;
        uint16 spokePoolId;
        uint64 offerScaling;
        uint64 wantScaling;
    }

    // Re-declared so library code can emit them; under delegatecall they log from the proxy address.
    event Swap(
        address indexed user,
        address indexed offerAsset,
        address indexed wantAsset,
        uint256 amountIn,
        uint256 amountFilled,
        uint256 amountQueued
    );
    event QueueJoined(
        uint256 indexed positionId, address indexed owner, address offerAsset, address wantAsset, uint256 amount
    );
    event QueueFilled(uint256 indexed positionId, address indexed owner, uint256 filled, uint256 remaining);
    event QueueCancelled(uint256 indexed positionId, address indexed owner, uint256 amountReturned);
    event QueuePositionRefunded(uint256 indexed positionId, address indexed owner, address offerAsset, uint256 units);

    // ============ Public entrypoints (delegatecall from DollarStore) ============

    /// @notice Directed swap: opposite-queue match -> reserves (if same-direction queue empty) -> queue
    ///         the remainder (see IDollarStore.swap). Gating (nonReentrant/whenNotPaused) is on the
    ///         DollarStore wrapper.
    function swap(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 tip,
        uint256 deadline
    ) external returns (uint256 amountFilled, uint256 amountQueued) {
        if (block.timestamp > deadline) revert IDollarStore.DeadlineExpired(deadline, block.timestamp);
        if (tip != 0) revert IDollarStore.TipNotEnabled();

        Route memory route = validateRoute(offerAsset, wantAsset);
        checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, route.offerScaling);
        if (amountUnits == 0) revert IDollarStore.ZeroAmount();

        pullExact(offerAsset, nativePulled);

        amountFilled = fillDirected(route, offerAsset, wantAsset, amountUnits, true);
        uint256 remaining = amountUnits - amountFilled;

        if (amountFilled < minAmountOut) revert IDollarStore.MinAmountNotMet(amountFilled, minAmountOut);

        if (amountFilled > 0) {
            IERC20(wantAsset).safeTransfer(msg.sender, NormalizationLib.toNative(amountFilled, route.wantScaling));
        }

        if (remaining > 0) {
            enqueueRemainder(offerAsset, wantAsset, remaining);
            amountQueued = remaining;
        }

        emit Swap(msg.sender, offerAsset, wantAsset, amountUnits, amountFilled, amountQueued);
    }

    /// @notice All-or-nothing swap: fills fully from opposite queue + reserves or reverts. Never queues
    ///         (see IDollarStore.swapExactInput).
    function swapExactInput(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 deadline
    ) external returns (uint256 amountOut) {
        if (block.timestamp > deadline) {
            revert IDollarStore.DeadlineExpired(deadline, block.timestamp);
        }

        Route memory route = validateRoute(offerAsset, wantAsset);
        checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, route.offerScaling);
        if (amountUnits == 0) revert IDollarStore.ZeroAmount();

        pullExact(offerAsset, nativePulled);

        uint256 filled = fillDirected(route, offerAsset, wantAsset, amountUnits, true);
        if (filled < amountUnits) revert IDollarStore.InsufficientLiquidity(filled, amountUnits);

        // minAmountOut is a floor in normalized 6dp units, same convention as swap() (L-01).
        if (filled < minAmountOut) revert IDollarStore.MinAmountNotMet(filled, minAmountOut);
        amountOut = NormalizationLib.toNative(filled, route.wantScaling);

        IERC20(wantAsset).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, offerAsset, wantAsset, amountUnits, filled, 0);
    }

    /// @notice Settle the (offerAsset -> wantAsset) queue from reserves in FIFO order, bounded by
    ///         `maxPositions` (see IDollarStore.processQueue).
    function processQueue(address offerAsset, address wantAsset, uint256 maxPositions)
        external
        returns (uint256 positionsProcessed, uint256 amountFilled)
    {
        // Classify the route (also blocks a paused spoke) and gate the offer side the same way a
        // deposit is: filling a queued position moves the owner's escrowed offer asset into reserves,
        // which is deposit-equivalent, so block while it is deposit-paused, pool-paused, or off-peg.
        Route memory route = validateRoute(offerAsset, wantAsset);
        checkInflow(offerAsset);

        (positionsProcessed, amountFilled) = settleSameDirection(route, offerAsset, wantAsset, maxPositions);
    }

    /// @notice After spoke liquidity is added, settle (bounded, FIFO) the directed queues the new
    ///         liquidity can now fill (see DollarStore._triggerSpokeQueues). `spokeIsWant == true`
    ///         settles hubAsset -> spokeAsset (hub->spoke demand); false settles spokeAsset -> hubAsset.
    function triggerSpokeQueues(address spokeAsset, bool spokeIsWant) external {
        address[] storage hubAssets = RegistryStorage.layout().pools[0].assets;
        for (uint256 i; i < hubAssets.length; ++i) {
            address h = hubAssets[i];
            address offer = spokeIsWant ? h : spokeAsset;
            address want = spokeIsWant ? spokeAsset : h;
            Route memory route = validateRoute(offer, want);
            settleSameDirection(route, offer, want, MAX_INLINE_SETTLE);
        }
    }

    /// @notice Remove a position and return its escrow to the owner; on a failed transfer convert the
    ///         escrow into the canonical receipt (see DollarStore._cancelPosition). Owner / existence /
    ///         gating checks are performed by the DollarStore wrapper before delegating.
    function cancelPosition(uint256 positionId) external {
        (address owner_, address offerAsset, uint256 amount) = QueueLib.remove(QueueStorage.layout(), positionId);
        uint64 scaling = RegistryStorage.layout().assetConfig[offerAsset].scalingFactor;
        if (tryTransfer(offerAsset, owner_, NormalizationLib.toNative(amount, scaling))) {
            emit QueueCancelled(positionId, owner_, amount);
        } else {
            refundEscrow(positionId, owner_, offerAsset, amount);
        }
    }

    // ============ Internal: routing & fills (inlined; shared with DollarStore views) ============

    /// @dev Validates and classifies a swap route. Allowed: hub->hub, hub->spoke, spoke->hub. Rejects
    ///      same-asset and spoke->spoke. A swap touching a paused spoke pool is blocked here.
    function validateRoute(address offerAsset, address wantAsset) internal view returns (Route memory route) {
        if (offerAsset == wantAsset) revert IDollarStore.SameAsset();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage offerCfg = r.assetConfig[offerAsset];
        RegistryStorage.AssetConfig storage wantCfg = r.assetConfig[wantAsset];
        if (!offerCfg.listed) revert IDollarStore.AssetNotListed(offerAsset);
        if (!wantCfg.listed) revert IDollarStore.AssetNotListed(wantAsset);

        uint16 offerPool = offerCfg.poolId;
        uint16 wantPool = wantCfg.poolId;
        route.offerScaling = offerCfg.scalingFactor;
        route.wantScaling = wantCfg.scalingFactor;

        if (offerPool == 0 && wantPool == 0) {
            route.kind = RouteKind.HubToHub;
        } else if (offerPool == 0) {
            route.kind = RouteKind.HubToSpoke;
            route.spokePoolId = wantPool;
        } else if (wantPool == 0) {
            route.kind = RouteKind.SpokeToHub;
            route.spokePoolId = offerPool;
        } else {
            revert IDollarStore.InvalidRoute(offerAsset, wantAsset); // spoke -> spoke
        }

        if (route.spokePoolId != 0) {
            RegistryStorage.Pool storage sp = r.pools[route.spokePoolId];
            if (sp.paused) revert IDollarStore.PoolPaused(route.spokePoolId);
            // Winding down: block risk-increasing spoke->hub (grows the spoke asset reserve). The
            // risk-reducing hub->spoke direction (grows the hub-backed dlrsReserve) stays live.
            if (sp.status == RegistryStorage.PoolStatus.WindingDown && route.kind == RouteKind.SpokeToHub) {
                revert IDollarStore.SpokeWindingDown(route.spokePoolId);
            }
        }
    }

    /// @dev Non-reverting route classification for views (getSwapQuote). Returns valid == false for any
    ///      unsupported route (same-asset, unlisted, spoke->spoke, or a paused spoke).
    function classifyRoute(address offerAsset, address wantAsset)
        internal
        view
        returns (bool valid, Route memory route)
    {
        if (offerAsset == wantAsset) return (false, route);
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig memory oc = r.assetConfig[offerAsset];
        RegistryStorage.AssetConfig memory wc = r.assetConfig[wantAsset];
        if (!oc.listed || !wc.listed) return (false, route);

        route.offerScaling = oc.scalingFactor;
        route.wantScaling = wc.scalingFactor;
        if (oc.poolId == 0 && wc.poolId == 0) {
            route.kind = RouteKind.HubToHub;
        } else if (oc.poolId == 0) {
            route.kind = RouteKind.HubToSpoke;
            route.spokePoolId = wc.poolId;
        } else if (wc.poolId == 0) {
            route.kind = RouteKind.SpokeToHub;
            route.spokePoolId = oc.poolId;
        } else {
            return (false, route); // spoke -> spoke
        }
        if (route.spokePoolId != 0) {
            RegistryStorage.Pool storage sp = r.pools[route.spokePoolId];
            if (sp.paused) return (false, route);
            if (sp.status == RegistryStorage.PoolStatus.WindingDown && route.kind == RouteKind.SpokeToHub) {
                return (false, route);
            }
        }
        valid = true;
    }

    /// @dev Protocol-reserve liquidity available to fill `want` for a route.
    function wantReserveAvailable(Route memory route, address want) internal view returns (uint256) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (route.kind == RouteKind.HubToHub) {
            return r.reserves[0][want];
        }
        if (route.kind == RouteKind.HubToSpoke) {
            return r.reserves[route.spokePoolId][want];
        }
        // SpokeToHub
        uint256 hubAvail = r.reserves[0][want];
        RegistryStorage.Pool storage p = r.pools[route.spokePoolId];
        uint256 dlrsExit = p.dlrsReserve > p.minDlrsReserve ? p.dlrsReserve - p.minDlrsReserve : 0;
        return hubAvail < dlrsExit ? hubAvail : dlrsExit;
    }

    /// @dev Apply the reserve movement for filling `fill` units of `want` (paid out) against `offer`
    ///      (absorbed), per route. Caller must ensure `fill <= wantReserveAvailable(route, want)`.
    function applyReserveFill(Route memory route, address offer, address want, uint256 fill) internal {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (route.kind == RouteKind.HubToHub) {
            r.reserves[0][want] -= fill;
            r.reserves[0][offer] += fill;
        } else if (route.kind == RouteKind.HubToSpoke) {
            r.reserves[route.spokePoolId][want] -= fill; // spoke asset leaves the spoke
            r.reserves[0][offer] += fill; // hub offer asset backs new DLRS-side liquidity
            r.pools[route.spokePoolId].dlrsReserve += fill; // spoke DLRS side grows
        } else {
            // SpokeToHub
            r.reserves[0][want] -= fill; // hub want asset leaves hub reserves
            r.reserves[route.spokePoolId][offer] += fill; // spoke offer asset enters the spoke
            r.pools[route.spokePoolId].dlrsReserve -= fill; // spoke DLRS side consumed
        }
    }

    /// @dev Pull exactly `nativeAmount` of `asset`, rejecting fee-on-transfer via a balance check.
    function pullExact(address asset, uint256 nativeAmount) internal {
        uint256 balBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), nativeAmount);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balBefore;
        if (received < nativeAmount) revert IDollarStore.FeeOnTransferNotSupported(asset);
    }

    /// @dev Reverts if the asset is deposit-paused, its pool is paused, or it is off-peg / stale.
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

    /// @dev Low-level transfer that returns false instead of reverting (for blacklist resilience).
    function tryTransfer(address token, address to, uint256 amount) internal returns (bool) {
        if (amount == 0) return true;
        (bool ok, bytes memory data) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    /// @dev Fills a directed swap: exact-opposite queue first, then reserves (only if the
    ///      same-direction queue is empty). Sends offer to matched owners; returns the filled amount.
    function fillDirected(
        Route memory route,
        address offerAsset,
        address wantAsset,
        uint256 amountUnits,
        bool allowReserves
    ) internal returns (uint256 filled) {
        QueueStorage.Layout storage qs = QueueStorage.layout();
        uint256 remaining = amountUnits;

        // Step 1: exact-opposite queue (wantAsset -> offerAsset). Peer-to-peer escrow match; touches no
        // protocol reserves and no dlrsReserve, so it is route-independent.
        uint256 current = qs.queues[QueueStorage.queueKey(wantAsset, offerAsset)].head;
        while (current != 0 && remaining > 0) {
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            address o = p.owner;
            uint256 posAmt = p.offerAmount; // escrowed wantAsset units
            uint256 fill = posAmt <= remaining ? posAmt : remaining;

            if (tryTransfer(offerAsset, o, NormalizationLib.toNative(fill, route.offerScaling))) {
                remaining -= fill;
                filled += fill;
                if (fill == posAmt) {
                    QueueLib.remove(qs, current);
                    emit QueueFilled(current, o, fill, 0);
                } else {
                    QueueLib.reduce(qs, current, fill);
                    emit QueueFilled(current, o, fill, posAmt - fill);
                }
            } else {
                // Paying the queued owner failed: eject and convert its escrow into the canonical
                // receipt (hub -> DLRS, spoke -> that spoke's shares), pool-aware (U2).
                (address owner_, address escrowAsset,) = QueueLib.remove(qs, current);
                refundEscrow(current, owner_, escrowAsset, posAmt);
            }
            current = next;
        }

        // Step 2: protocol reserves. FIFO rule (M-01): settle any earlier same-direction queued
        // positions (bounded) before the swapper touches reserves. Only fill the swapper's remainder if
        // the queue is now fully cleared.
        if (allowReserves && remaining > 0) {
            settleSameDirection(route, offerAsset, wantAsset, MAX_INLINE_SETTLE);
            if (qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount == 0) {
                uint256 available = wantReserveAvailable(route, wantAsset);
                uint256 fill = available <= remaining ? available : remaining;
                if (fill > 0) {
                    applyReserveFill(route, offerAsset, wantAsset, fill);
                    remaining -= fill;
                    filled += fill;
                }
            }
        }
    }

    /// @dev Settles the (offerAsset -> wantAsset) queue from protocol reserves in FIFO order, bounded by
    ///      `maxPositions`, using route-aware accounting. On a failed payout, ejects the position and
    ///      converts its escrow into the canonical receipt. Callers must have inflow-gated `offerAsset`.
    function settleSameDirection(Route memory route, address offerAsset, address wantAsset, uint256 maxPositions)
        internal
        returns (uint256 positionsProcessed, uint256 amountFilled)
    {
        QueueStorage.Layout storage qs = QueueStorage.layout();

        uint256 current = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].head;

        while (current != 0 && positionsProcessed < maxPositions) {
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            address o = p.owner;
            uint256 posAmt = p.offerAmount;

            uint256 available = wantReserveAvailable(route, wantAsset);
            if (available == 0) break;

            uint256 fill = posAmt <= available ? posAmt : available;

            if (tryTransfer(wantAsset, o, NormalizationLib.toNative(fill, route.wantScaling))) {
                applyReserveFill(route, offerAsset, wantAsset, fill);
                amountFilled += fill;
                if (fill == posAmt) {
                    QueueLib.remove(qs, current);
                    emit QueueFilled(current, o, fill, 0);
                } else {
                    QueueLib.reduce(qs, current, fill);
                    emit QueueFilled(current, o, fill, posAmt - fill);
                }
            } else {
                (address owner_, address escrowAsset,) = QueueLib.remove(qs, current);
                refundEscrow(current, owner_, escrowAsset, posAmt);
            }

            positionsProcessed += 1;
            current = next;
        }
    }

    /// @dev Escrow the remainder into the (offerAsset -> wantAsset) queue. Enforces cap and the
    ///      minimum order size, with the below-minimum exception only for the first position.
    function enqueueRemainder(address offerAsset, address wantAsset, uint256 remaining) internal {
        QueueStorage.Layout storage qs = QueueStorage.layout();
        QueueStorage.Queue storage q = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)];
        if (q.positionCount >= QueueStorage.MAX_QUEUE_POSITIONS) revert IDollarStore.QueueFull(offerAsset, wantAsset);

        uint256 minOrder = QueueLib.minimumOrderSize(q.positionCount);
        // Below-minimum allowed only when opening the first position of an empty directed queue.
        if (remaining < minOrder && q.positionCount != 0) revert IDollarStore.OrderTooSmall(remaining, minOrder);

        uint256 positionId = QueueLib.enqueue(qs, offerAsset, wantAsset, msg.sender, remaining);
        emit QueueJoined(positionId, msg.sender, offerAsset, wantAsset, remaining);
    }

    /// @dev Blacklist-safe fallback: convert an ejected position's escrow into its canonical receipt.
    ///      HUB escrow -> hub reserves + DLRS minted 1:1. SPOKE escrow -> that spoke's reserve + receipt
    ///      shares minted pro-rata (U2). Never reverts.
    function refundEscrow(uint256 positionId, address owner_, address escrowAsset, uint256 amount) internal {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        uint16 poolId = r.assetConfig[escrowAsset].poolId;
        if (poolId == 0) {
            r.reserves[0][escrowAsset] += amount;
            DLRS(CoreStorage.layout().dlrs).mint(owner_, amount);
        } else {
            RegistryStorage.Pool storage p = r.pools[poolId];
            uint256 shares = SpokeShareLib.sharesForDepositOrZero(
                amount, r.reserves[poolId][escrowAsset] + p.dlrsReserve, r.receiptTotalShares[poolId]
            );
            r.reserves[poolId][escrowAsset] += amount;
            r.receiptShares[poolId][owner_] += shares;
            r.receiptTotalShares[poolId] += shares;
        }
        emit QueuePositionRefunded(positionId, owner_, escrowAsset, amount);
    }
}
