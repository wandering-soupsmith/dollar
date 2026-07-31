// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IDollarStore} from "./interfaces/IDollarStore.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {CoreStorage} from "./storage/CoreStorage.sol";
import {RegistryStorage} from "./storage/RegistryStorage.sol";
import {QueueStorage} from "./storage/QueueStorage.sol";
import {NormalizationLib} from "./libraries/NormalizationLib.sol";
import {QueueLib} from "./libraries/QueueLib.sol";
import {SpokeShareLib} from "./libraries/SpokeShareLib.sol";
import {DLRS} from "./DLRS.sol";

/// @title DollarStore - Upgradeable (UUPS) base + governance skeleton (Milestone M1)
/// @notice Establishes the upgradeable core: ERC-7201 namespaced storage, two-step
///         governor/guardian roles, pause/unpause, and governor-gated UUPS upgrades.
/// @dev Swap/queue/reserve logic is added in later milestones. This is the M1 foundation.
/// @dev Storage is held in CoreStorage's ERC-7201 namespaced slot, NOT in contract state
///      variables, so the layout is stable across upgrades.
/// @custom:security-contact admin@dollarstore.world
contract DollarStore is Initializable, UUPSUpgradeable, PausableUpgradeable, ReentrancyGuard, IDollarStore {
    using SafeERC20 for IERC20;

    // ============ Constants ============

    /// @dev Max supported price-feed decimals; the peg math scales by 10**(PRICE_DECIMALS - feedDecimals).
    uint8 private constant MAX_FEED_DECIMALS = 18;
    /// @dev Fixed-point precision for the peg math (one dollar == ONE == 10**PRICE_DECIMALS). Distinct
    ///      from MAX_FEED_DECIMALS even though both are 18: this is the normalization target, not a limit.
    uint256 private constant PRICE_DECIMALS = 18;
    /// @dev One dollar in PRICE_DECIMALS fixed point.
    uint256 private constant ONE = 1e18;
    /// @dev Basis-points denominator (100% == 10_000 bps).
    uint256 private constant BPS_DENOMINATOR = 10_000;
    /// @dev Peg tolerance set at initialize: 50 bps == 0.5%.
    uint256 private constant DEFAULT_PEG_TOLERANCE_BPS = 50;
    /// @dev Maximum settable peg tolerance: 500 bps == 5%.
    uint256 private constant MAX_PEG_TOLERANCE_BPS = 500;
    /// @dev Max oracle staleness set at initialize: 3600 s == 1 hour.
    uint256 private constant DEFAULT_MAX_STALENESS = 3600;
    /// @dev Max same-direction queue positions a swap settles from reserves inline before filling
    ///      itself (M-01). Bounds the extra gas a swap can incur; a deeper queue keeps its FIFO order
    ///      and drains across subsequent swaps / processQueue calls.
    uint256 private constant MAX_INLINE_SETTLE = 8;

    // ============ Routing types (U2) ============

    /// @dev The three supported swap routes. Spoke-to-spoke is rejected (done as two hub-legged swaps).
    enum RouteKind {
        HubToHub,
        HubToSpoke,
        SpokeToHub
    }

    /// @dev A validated swap route: its kind, the spoke pool involved (0 for HubToHub), and the
    ///      offer/want scaling factors. Threaded through the fill/settle path so reserve accounting
    ///      (and the dlrsReserve / minDlrsReserve rules) can branch per route.
    struct Route {
        RouteKind kind;
        uint16 spokePoolId;
        uint64 offerScaling;
        uint64 wantScaling;
    }

    // ============ Modifiers ============

    /// @dev Restricts to the current governor (read from namespaced core storage).
    modifier onlyGovernor() {
        if (msg.sender != CoreStorage.layout().governor) revert OnlyGovernor();
        _;
    }

    /// @dev Restricts to the current guardian (read from namespaced core storage).
    modifier onlyGuardian() {
        if (msg.sender != CoreStorage.layout().guardian) revert OnlyGuardian();
        _;
    }

    /// @dev Restricts to the current upgrader (read from namespaced core storage). The upgrader
    ///      holds UUPS upgrade authority and is kept separate from the governor (M8).
    modifier onlyUpgrader() {
        if (msg.sender != CoreStorage.layout().upgrader) revert OnlyUpgrader();
        _;
    }

    // ============ Constructor ============

    /// @notice Locks the implementation contract so it can never be initialized directly.
    /// @dev All state lives behind the proxy; the implementation must stay uninitialized.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============

    /// @notice Initialize the proxy: set roles, init bases, and deploy the DLRS token.
    /// @dev Deploys a fresh DLRS bound to this proxy (address(this)) and stores its address.
    /// @param upgrader_ The upgrader address (UUPS upgrade authority; expected: timelock).
    /// @param governor_ The governor address (risk params + registry + caps; expected: timelock).
    /// @param guardian_ The guardian address (emergency authority; expected: multisig).
    function initialize(address upgrader_, address governor_, address guardian_) external initializer {
        if (upgrader_ == address(0)) revert ZeroAddress();
        if (governor_ == address(0)) revert ZeroAddress();
        if (guardian_ == address(0)) revert ZeroAddress();

        __Pausable_init();
        // ReentrancyGuard (OZ v5.6+) is stateless/namespaced and has no initializer:
        // the guard slot defaults to 0, which `_nonReentrantBefore` treats as NOT_ENTERED.

        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.upgrader = upgrader_;
        $.governor = governor_;
        $.guardian = guardian_;
        $.dlrs = address(new DLRS(address(this)));
        $.pegTolerance = DEFAULT_PEG_TOLERANCE_BPS;
        $.maxStaleness = DEFAULT_MAX_STALENESS;

        // Create the hub pool (poolId 0). Spoke pools (poolId >= 1) are created later.
        RegistryStorage.Pool storage hub = RegistryStorage.layout().pools.push();
        hub.kind = RegistryStorage.PoolKind.Hub;
        emit PoolCreated(0, uint8(RegistryStorage.PoolKind.Hub));
    }

    // ============ Getters ============

    /// @inheritdoc IDollarStore
    function governor() external view override returns (address) {
        return CoreStorage.layout().governor;
    }

    /// @inheritdoc IDollarStore
    function guardian() external view override returns (address) {
        return CoreStorage.layout().guardian;
    }

    /// @inheritdoc IDollarStore
    function pendingGovernor() external view override returns (address) {
        return CoreStorage.layout().pendingGovernor;
    }

    /// @inheritdoc IDollarStore
    function pendingGuardian() external view override returns (address) {
        return CoreStorage.layout().pendingGuardian;
    }

    /// @inheritdoc IDollarStore
    function upgrader() external view override returns (address) {
        return CoreStorage.layout().upgrader;
    }

    /// @inheritdoc IDollarStore
    function pendingUpgrader() external view override returns (address) {
        return CoreStorage.layout().pendingUpgrader;
    }

    /// @inheritdoc IDollarStore
    function dlrs() external view override returns (address) {
        return CoreStorage.layout().dlrs;
    }

    /// @inheritdoc IDollarStore
    function version() external pure override returns (string memory) {
        return "0.9.0-U2";
    }

    // ============ Two-step Role Transfers ============

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated. The new governor must call acceptGovernor to take the role.
    function transferGovernor(address newGovernor) external override onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.pendingGovernor = newGovernor;
        emit GovernorTransferInitiated($.governor, newGovernor);
    }

    /// @inheritdoc IDollarStore
    /// @dev Callable only by the pending governor.
    function acceptGovernor() external override {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        if (msg.sender != $.pendingGovernor) revert OnlyPendingGovernor();
        address previousGovernor = $.governor;
        $.governor = $.pendingGovernor;
        $.pendingGovernor = address(0);
        emit GovernorTransferCompleted(previousGovernor, $.governor);
    }

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated (NOT guardian-gated): if the guardian could rotate itself, a
    ///      compromised guardian could lock out the legitimate one. The governor's slower
    ///      path protects the emergency role. Same rationale as the prior design.
    function transferGuardian(address newGuardian) external override onlyGovernor {
        if (newGuardian == address(0)) revert ZeroAddress();
        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.pendingGuardian = newGuardian;
        emit GuardianTransferInitiated($.guardian, newGuardian);
    }

    /// @inheritdoc IDollarStore
    /// @dev Callable only by the pending guardian.
    function acceptGuardian() external override {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        if (msg.sender != $.pendingGuardian) revert OnlyPendingGuardian();
        address previousGuardian = $.guardian;
        $.guardian = $.pendingGuardian;
        $.pendingGuardian = address(0);
        emit GuardianTransferCompleted(previousGuardian, $.guardian);
    }

    /// @inheritdoc IDollarStore
    /// @dev Upgrader-gated (self-managed), NOT governor-gated: if the governor could rotate the
    ///      upgrader, a compromised governor could seize upgrade authority. The upgrader is the
    ///      most powerful role, so only it can hand itself off (two-step).
    function transferUpgrader(address newUpgrader) external override onlyUpgrader {
        if (newUpgrader == address(0)) revert ZeroAddress();
        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.pendingUpgrader = newUpgrader;
        emit UpgraderTransferInitiated($.upgrader, newUpgrader);
    }

    /// @inheritdoc IDollarStore
    /// @dev Callable only by the pending upgrader.
    function acceptUpgrader() external override {
        CoreStorage.Layout storage $ = CoreStorage.layout();
        if (msg.sender != $.pendingUpgrader) revert OnlyPendingUpgrader();
        address previousUpgrader = $.upgrader;
        $.upgrader = $.pendingUpgrader;
        $.pendingUpgrader = address(0);
        emit UpgraderTransferCompleted(previousUpgrader, $.upgrader);
    }

    // ============ Emergency ============

    /// @inheritdoc IDollarStore
    /// @dev Guardian-gated (instant).
    function pause() external override onlyGuardian {
        _pause();
    }

    /// @inheritdoc IDollarStore
    /// @dev Guardian-gated (instant).
    function unpause() external override onlyGuardian {
        _unpause();
    }

    // ============ Asset Registry (M2) ============

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated. Reads and freezes the token's decimals, computes the scaling factor
    ///      (reverts if decimals are outside [6, 18]), requires a price feed, and lists the asset
    ///      into the hub (poolId 0). Reserves remain zero until deposits land in M3.
    function addHubAsset(address asset, address priceFeed) external override onlyGovernor {
        if (asset == address(0) || priceFeed == address(0)) revert ZeroAddress();
        // Feed decimals must be <= 18: _checkPeg scales by 10**(18 - feedDecimals), which would
        // underflow (and DoS every inflow of this asset) for a feed with more than 18 decimals.
        uint8 feedDec = AggregatorV3Interface(priceFeed).decimals();
        if (feedDec > MAX_FEED_DECIMALS) revert NormalizationLib.UnsupportedDecimals(feedDec);

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (r.assetConfig[asset].listed) revert AssetAlreadyListed(asset);

        uint8 dec = IERC20Metadata(asset).decimals();
        uint64 sf = NormalizationLib.scalingFactor(dec); // reverts UnsupportedDecimals if out of range

        r.assetConfig[asset] = RegistryStorage.AssetConfig({
            poolId: 0, decimals: dec, scalingFactor: sf, priceFeed: priceFeed, listed: true, depositPaused: false
        });
        r.pools[0].assets.push(asset);

        emit AssetListed(asset, 0, dec, priceFeed);
    }

    // ============ Spoke Lifecycle (U2) ============

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated. Mirrors addHubAsset's listing guards but creates a NEW spoke pool
    ///      (poolId >= 1) and registers the asset into it. Ownership is enforced by the `listed`
    ///      flag: an already-listed asset (hub or another spoke) cannot be re-listed, so an asset
    ///      belongs to exactly one pool.
    function createSpoke(address spokeAsset, address priceFeed, uint256 minDlrsReserve_)
        external
        override
        onlyGovernor
        returns (uint16 poolId)
    {
        if (spokeAsset == address(0) || priceFeed == address(0)) revert ZeroAddress();
        uint8 feedDec = AggregatorV3Interface(priceFeed).decimals();
        if (feedDec > MAX_FEED_DECIMALS) revert NormalizationLib.UnsupportedDecimals(feedDec);

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (r.assetConfig[spokeAsset].listed) revert AssetAlreadyListed(spokeAsset);

        uint256 newIndex = r.pools.length;
        if (newIndex > type(uint16).max) revert MaxPoolsReached();
        poolId = uint16(newIndex);

        uint8 dec = IERC20Metadata(spokeAsset).decimals();
        uint64 sf = NormalizationLib.scalingFactor(dec); // reverts UnsupportedDecimals if out of range

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

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated, spoke-only. The guardian must not change it (it moves market behavior).
    function setMinDlrsReserve(uint16 poolId, uint256 newMin) external override onlyGovernor {
        RegistryStorage.Pool storage p = _spokePool(poolId);
        uint256 old = p.minDlrsReserve;
        p.minDlrsReserve = newMin;
        emit MinDlrsReserveSet(poolId, old, newMin);
    }

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated. A spoke can only be removed once fully drained: no spoke reserves, no
    ///      dlrsReserve, no LP shares, and no queued depth on any route touching the spoke asset. Kills
    ///      the pool by pausing it and unlisting its assets; the poolId is retired but the pool stays as
    ///      a tombstone in the array so later poolIds never shift.
    function removePool(uint16 poolId) external override onlyGovernor {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.Pool storage p = _spokePool(poolId);
        if (p.dlrsReserve != 0) revert PoolNotEmpty(poolId);
        if (r.receiptTotalShares[poolId] != 0) revert PoolNotEmpty(poolId);

        address[] storage spokeAssets = p.assets;
        address[] storage hubAssets = r.pools[0].assets;
        QueueStorage.Layout storage qs = QueueStorage.layout();
        for (uint256 i; i < spokeAssets.length; ++i) {
            address sa = spokeAssets[i];
            if (r.reserves[poolId][sa] != 0) revert PoolNotEmpty(poolId);
            for (uint256 j; j < hubAssets.length; ++j) {
                address ha = hubAssets[j];
                if (qs.queues[QueueStorage.queueKey(sa, ha)].totalDepth != 0) revert PoolNotEmpty(poolId);
                if (qs.queues[QueueStorage.queueKey(ha, sa)].totalDepth != 0) revert PoolNotEmpty(poolId);
            }
            r.assetConfig[sa].listed = false;
        }

        p.paused = true;
        p.status = RegistryStorage.PoolStatus.Killed;
        emit PoolRemoved(poolId);
    }

    /// @inheritdoc IDollarStore
    /// @dev Governor-gated, spoke-only. Enters the winding-down state: `_validateRoute` then blocks
    ///      risk-increasing spoke->hub trades and `deposit` blocks new spoke liquidity, while LP exits,
    ///      cancellations, and risk-reducing hub->spoke trades stay live.
    function windDownSpoke(uint16 poolId) external override onlyGovernor {
        RegistryStorage.Pool storage p = _spokePool(poolId);
        if (p.status != RegistryStorage.PoolStatus.Active) revert SpokeWindingDown(poolId);
        p.status = RegistryStorage.PoolStatus.WindingDown;
        emit SpokeWindDownStarted(poolId);
    }

    /// @inheritdoc IDollarStore
    function getPoolStatus(uint16 poolId) external view override returns (uint8) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return uint8(r.pools[poolId].status);
    }

    /// @dev Returns the spoke pool at `poolId`, reverting InvalidPool if it does not exist and
    ///      PoolNotSpoke if it is the hub (poolId 0, which exists but is not a spoke).
    function _spokePool(uint16 poolId) internal view returns (RegistryStorage.Pool storage p) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        p = r.pools[poolId];
        if (p.kind != RegistryStorage.PoolKind.Spoke) revert PoolNotSpoke(poolId);
    }

    /// @inheritdoc IDollarStore
    function getMinDlrsReserve(uint16 poolId) external view override returns (uint256) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return r.pools[poolId].minDlrsReserve;
    }

    /// @inheritdoc IDollarStore
    function getDlrsReserve(uint16 poolId) external view override returns (uint256) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return r.pools[poolId].dlrsReserve;
    }

    /// @inheritdoc IDollarStore
    function getReceiptShares(uint16 poolId, address owner_) external view override returns (uint256) {
        return RegistryStorage.layout().receiptShares[poolId][owner_];
    }

    /// @inheritdoc IDollarStore
    function getReceiptTotalShares(uint16 poolId) external view override returns (uint256) {
        return RegistryStorage.layout().receiptTotalShares[poolId];
    }

    /// @inheritdoc IDollarStore
    function poolKind(uint16 poolId) external view override returns (uint8) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return uint8(r.pools[poolId].kind);
    }

    /// @inheritdoc IDollarStore
    function isAssetListed(address asset) external view override returns (bool) {
        return RegistryStorage.layout().assetConfig[asset].listed;
    }

    /// @inheritdoc IDollarStore
    function assetDecimals(address asset) external view override returns (uint8) {
        return RegistryStorage.layout().assetConfig[asset].decimals;
    }

    /// @inheritdoc IDollarStore
    function assetScalingFactor(address asset) external view override returns (uint64) {
        return RegistryStorage.layout().assetConfig[asset].scalingFactor;
    }

    /// @inheritdoc IDollarStore
    function assetPoolId(address asset) external view override returns (uint16) {
        return RegistryStorage.layout().assetConfig[asset].poolId;
    }

    /// @inheritdoc IDollarStore
    function assetPriceFeed(address asset) external view override returns (address) {
        return RegistryStorage.layout().assetConfig[asset].priceFeed;
    }

    /// @inheritdoc IDollarStore
    function getReserve(uint16 poolId, address asset) external view override returns (uint256) {
        return RegistryStorage.layout().reserves[poolId][asset];
    }

    /// @inheritdoc IDollarStore
    function poolCount() external view override returns (uint256) {
        return RegistryStorage.layout().pools.length;
    }

    /// @inheritdoc IDollarStore
    function getPoolAssets(uint16 poolId) external view override returns (address[] memory) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return r.pools[poolId].assets;
    }

    /// @inheritdoc IDollarStore
    function getReserves(uint16 poolId)
        external
        view
        override
        returns (address[] memory assets, uint256[] memory amounts)
    {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        assets = r.pools[poolId].assets;
        amounts = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            amounts[i] = r.reserves[poolId][assets[i]];
        }
    }

    // ============ Hub Deposit / Withdraw (M3) ============

    /// @inheritdoc IDollarStore
    /// @dev Routes to the hub (poolId 0, mints DLRS 1:1) or a spoke (poolId >= 1). A spoke deposit is
    ///      either the spoke's own asset (enters the spoke reserve) or a hub asset that funds the
    ///      spoke's dlrsReserve; both mint pro-rata receipt shares. New exposure is gated by global
    ///      pause + reentrancy guard. Pulls only `nativePulled` (= units * scalingFactor); sub-unit
    ///      dust stays with the user. A before/after balance check rejects fee-on-transfer tokens.
    /// @return receiptUnits For a HUB deposit, the DLRS minted (normalized 6dp). For a SPOKE deposit,
    ///         the non-transferable receipt shares credited to the LP.
    function deposit(uint16 poolId, address asset, uint256 amount, uint256 deadline)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 receiptUnits)
    {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig memory cfg = r.assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);

        if (poolId == 0) {
            // Hub deposit: asset must be a hub asset; mints DLRS 1:1 (M3).
            if (cfg.poolId != 0) revert WrongPool(asset, poolId);
            return _depositHub(r, asset, cfg.scalingFactor, amount);
        }

        // Spoke deposit (U2). The pool must be a live, active spoke (no new liquidity once winding down).
        RegistryStorage.Pool storage p = _spokePool(poolId);
        if (p.paused) revert PoolPaused(poolId);
        if (p.status != RegistryStorage.PoolStatus.Active) revert SpokeWindingDown(poolId);
        if (cfg.poolId == poolId) {
            // The spoke's own asset enters that spoke's active reserve.
            return _depositSpokeAsset(r, p, poolId, asset, cfg.scalingFactor, amount);
        }
        if (cfg.poolId == 0) {
            // A hub asset funds the spoke's DLRS side (enters hub reserves, credits dlrsReserve).
            return _depositSpokeFunding(r, p, poolId, asset, cfg.scalingFactor, amount);
        }
        revert WrongPool(asset, poolId); // asset belongs to a different spoke
    }

    /// @dev Hub deposit: pull the hub asset into hub reserves and mint DLRS 1:1 to the depositor.
    function _depositHub(RegistryStorage.Layout storage r, address asset, uint64 scaling, uint256 amount)
        internal
        returns (uint256 units)
    {
        _checkInflow(asset); // per-asset/hub-pool deposit pause + oracle peg check
        uint256 nativePulled;
        (units, nativePulled) = NormalizationLib.toUnits(amount, scaling);
        if (units == 0) revert ZeroAmount();

        _checkLaunchCap(0, units);
        _pullExact(asset, nativePulled); // rejects fee-on-transfer

        r.reserves[0][asset] += units;
        DLRS(CoreStorage.layout().dlrs).mint(msg.sender, units);

        emit Deposit(msg.sender, 0, asset, nativePulled, units);
    }

    /// @dev Spoke-asset LP: the spoke asset enters that spoke's active reserve and mints receipt shares
    ///      pro-rata against the pool value (spokeReserve + dlrsReserve). No DLRS is minted.
    function _depositSpokeAsset(
        RegistryStorage.Layout storage r,
        RegistryStorage.Pool storage p,
        uint16 poolId,
        address asset,
        uint64 scaling,
        uint256 amount
    ) internal returns (uint256 shares) {
        _checkInflow(asset); // spoke asset: deposit pause + spoke-pool pause + peg
        (uint256 units, uint256 nativePulled) = NormalizationLib.toUnits(amount, scaling);
        if (units == 0) revert ZeroAmount();

        uint256 poolValueBefore = r.reserves[poolId][asset] + p.dlrsReserve;
        shares = SpokeShareLib.sharesForDeposit(units, poolValueBefore, r.receiptTotalShares[poolId]);

        _checkLaunchCap(poolId, units);
        _pullExact(asset, nativePulled);

        r.reserves[poolId][asset] += units;
        r.receiptShares[poolId][msg.sender] += shares;
        r.receiptTotalShares[poolId] += shares;

        emit SpokeLiquidityAdded(poolId, msg.sender, asset, nativePulled, units, shares);

        // The new spoke reserve can now settle waiting hub->spoke demand (hubAsset -> this spoke asset).
        _triggerSpokeQueues(poolId, asset, true);
    }

    /// @dev Hub-asset LP into a spoke: the hub asset enters HUB reserves and credits the spoke's
    ///      internal `dlrsReserve` (streamlined, no wallet DLRS round-trip), minting receipt shares
    ///      pro-rata. Hub-reserve backing and dlrsReserve grow together, preserving DLRS conservation.
    function _depositSpokeFunding(
        RegistryStorage.Layout storage r,
        RegistryStorage.Pool storage p,
        uint16 poolId,
        address hubAsset,
        uint64 scaling,
        uint256 amount
    ) internal returns (uint256 shares) {
        _checkInflow(hubAsset); // hub asset: deposit pause + hub-pool pause + peg
        (uint256 units, uint256 nativePulled) = NormalizationLib.toUnits(amount, scaling);
        if (units == 0) revert ZeroAmount();

        address spokeAsset = p.assets[0]; // a spoke has exactly one spoke asset
        uint256 poolValueBefore = r.reserves[poolId][spokeAsset] + p.dlrsReserve;
        shares = SpokeShareLib.sharesForDeposit(units, poolValueBefore, r.receiptTotalShares[poolId]);

        _checkLaunchCap(poolId, units);
        _pullExact(hubAsset, nativePulled);

        r.reserves[0][hubAsset] += units; // hub asset backs the new DLRS-side liquidity
        p.dlrsReserve += units; // credit the spoke's DLRS side (no wallet DLRS minted)
        r.receiptShares[poolId][msg.sender] += shares;
        r.receiptTotalShares[poolId] += shares;

        emit SpokeLiquidityAdded(poolId, msg.sender, hubAsset, nativePulled, units, shares);

        // The new DLRS side can now settle waiting spoke->hub demand (this spoke asset -> hubAsset).
        _triggerSpokeQueues(poolId, spokeAsset, false);
    }

    /// @dev After spoke liquidity is added, settle (bounded, FIFO) the directed queues the new
    ///      liquidity can now fill. A spoke-asset deposit enables hub->spoke demand for every hub asset
    ///      (`spokeIsWant == true`, queues hubAsset -> spokeAsset); a hub-asset funding deposit enables
    ///      spoke->hub demand for every hub asset (`spokeIsWant == false`, queues spokeAsset -> hubAsset).
    ///      Bounded by the small, fixed hub-asset count x MAX_INLINE_SETTLE. The spoke is known live
    ///      (deposit already checked it is not paused).
    function _triggerSpokeQueues(uint16 poolId, address spokeAsset, bool spokeIsWant) internal {
        address[] storage hubAssets = RegistryStorage.layout().pools[0].assets;
        for (uint256 i; i < hubAssets.length; ++i) {
            address h = hubAssets[i];
            address offer = spokeIsWant ? h : spokeAsset;
            address want = spokeIsWant ? spokeAsset : h;
            Route memory route = _validateRoute(offer, want);
            _settleSameDirection(route, offer, want, MAX_INLINE_SETTLE);
        }
    }

    /// @inheritdoc IDollarStore
    /// @dev Exit path: NOT blocked by pause (only by the reentrancy guard), so LPs can always exit.
    ///      Hub (poolId 0): `units` is DLRS to burn, paid 1:1 in the chosen hub asset. Spoke (poolId
    ///      >= 1): `units` is receipt SHARES to burn; the LP is paid the pro-rata value in the chosen
    ///      asset (the spoke asset from its reserve, or a hub asset consuming dlrsReserve). minDlrsReserve
    ///      does NOT block LP withdrawals - the full dlrsReserve is available to exiting LPs.
    function withdraw(uint16 poolId, address asset, uint256 units, uint256 deadline)
        external
        override
        nonReentrant
        returns (uint256 nativeAmountOut)
    {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (units == 0) revert ZeroAmount();

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig memory cfg = r.assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);

        if (poolId == 0) {
            if (cfg.poolId != 0) revert WrongPool(asset, poolId);
            return _withdrawHub(r, asset, cfg.scalingFactor, units);
        }

        // Spoke withdrawal. `_spokePool` does not check pause, so exits stay live while paused.
        RegistryStorage.Pool storage p = _spokePool(poolId);
        if (cfg.poolId == poolId) {
            return _withdrawSpokeAsset(r, p, poolId, asset, cfg.scalingFactor, units);
        }
        if (cfg.poolId == 0) {
            return _withdrawSpokeHubAsset(r, p, poolId, asset, cfg.scalingFactor, units);
        }
        revert WrongPool(asset, poolId); // asset belongs to a different spoke
    }

    /// @dev Hub withdrawal: burn `units` DLRS (a claim on the hub basket) and send the chosen hub
    ///      asset 1:1 in native units. CEI: effects before the transfer.
    function _withdrawHub(RegistryStorage.Layout storage r, address asset, uint64 scaling, uint256 units)
        internal
        returns (uint256 nativeAmountOut)
    {
        uint256 available = r.reserves[0][asset];
        if (available < units) revert InsufficientReserves(asset, units, available);

        DLRS(CoreStorage.layout().dlrs).burn(msg.sender, units);
        r.reserves[0][asset] = available - units;

        nativeAmountOut = NormalizationLib.toNative(units, scaling);
        IERC20(asset).safeTransfer(msg.sender, nativeAmountOut);
        emit Withdraw(msg.sender, 0, asset, units, nativeAmountOut);
    }

    /// @dev Spoke LP exit paid in the spoke asset: burn `shares`, pay the pro-rata value from the
    ///      spoke's own reserve. Reverts if that reserve cannot cover the value.
    function _withdrawSpokeAsset(
        RegistryStorage.Layout storage r,
        RegistryStorage.Pool storage p,
        uint16 poolId,
        address asset,
        uint64 scaling,
        uint256 shares
    ) internal returns (uint256 nativeAmountOut) {
        uint256 ownerShares = r.receiptShares[poolId][msg.sender];
        if (ownerShares < shares) revert InsufficientReceiptShares(shares, ownerShares);

        uint256 total = r.receiptTotalShares[poolId];
        uint256 available = r.reserves[poolId][asset];
        uint256 value = SpokeShareLib.valueForShares(shares, available + p.dlrsReserve, total);
        if (value == 0) revert ZeroAmount();
        if (value > available) revert InsufficientReserves(asset, value, available);

        // Effects before interaction (CEI).
        r.receiptShares[poolId][msg.sender] = ownerShares - shares;
        r.receiptTotalShares[poolId] = total - shares;
        r.reserves[poolId][asset] = available - value;

        nativeAmountOut = NormalizationLib.toNative(value, scaling);
        IERC20(asset).safeTransfer(msg.sender, nativeAmountOut);
        emit SpokeLiquidityRemoved(poolId, msg.sender, asset, shares, value, nativeAmountOut);
    }

    /// @dev Spoke LP exit paid in a hub asset: burn `shares`, consume the pro-rata value from the
    ///      spoke's dlrsReserve and pay it out of hub reserves. Bounded by min(dlrsReserve, hub
    ///      reserve of that asset). minDlrsReserve does NOT gate this (exits are always live).
    function _withdrawSpokeHubAsset(
        RegistryStorage.Layout storage r,
        RegistryStorage.Pool storage p,
        uint16 poolId,
        address hubAsset,
        uint64 scaling,
        uint256 shares
    ) internal returns (uint256 nativeAmountOut) {
        uint256 ownerShares = r.receiptShares[poolId][msg.sender];
        if (ownerShares < shares) revert InsufficientReceiptShares(shares, ownerShares);

        uint256 total = r.receiptTotalShares[poolId];
        uint256 spokeReserve = r.reserves[poolId][p.assets[0]];
        uint256 value = SpokeShareLib.valueForShares(shares, spokeReserve + p.dlrsReserve, total);
        if (value == 0) revert ZeroAmount();

        uint256 dlrsAvail = p.dlrsReserve;
        uint256 hubAvail = r.reserves[0][hubAsset];
        uint256 available = dlrsAvail < hubAvail ? dlrsAvail : hubAvail;
        if (value > available) revert InsufficientReserves(hubAsset, value, available);

        // Effects before interaction (CEI): burn shares, drop dlrsReserve and hub reserve together.
        r.receiptShares[poolId][msg.sender] = ownerShares - shares;
        r.receiptTotalShares[poolId] = total - shares;
        p.dlrsReserve = dlrsAvail - value;
        r.reserves[0][hubAsset] = hubAvail - value;

        nativeAmountOut = NormalizationLib.toNative(value, scaling);
        IERC20(hubAsset).safeTransfer(msg.sender, nativeAmountOut);
        emit SpokeLiquidityRemoved(poolId, msg.sender, hubAsset, shares, value, nativeAmountOut);
    }

    /// @inheritdoc IDollarStore
    /// @dev Proportional exit across BOTH sides of the spoke, so an LP never gets stuck on rounding
    ///      dust (the single-asset `withdraw` can leave a sliver on one side that neither reserve can
    ///      cover alone). Exit path: not blocked by pause (only the reentrancy guard), not gated by
    ///      minDlrsReserve. Both slices floor, so the redeemer never draws more than their pro-rata
    ///      share and remaining LPs are never diluted. Burning the last shares drains both reserves to
    ///      exactly zero, which is what makes a fully-exited spoke reach the all-zero state removePool
    ///      requires.
    function redeemSpoke(uint16 poolId, uint256 shares, uint256 deadline)
        external
        override
        nonReentrant
        returns (uint256 spokeUnits, uint256 dlrsUnits)
    {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (shares == 0) revert ZeroAmount();

        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.Pool storage p = _spokePool(poolId);

        uint256 ownerShares = r.receiptShares[poolId][msg.sender];
        if (ownerShares < shares) revert InsufficientReceiptShares(shares, ownerShares);

        uint256 total = r.receiptTotalShares[poolId];
        address spokeAsset = p.assets[0];
        uint256 spokeReserve = r.reserves[poolId][spokeAsset];

        spokeUnits = Math.mulDiv(shares, spokeReserve, total); // floor, pro-rata
        dlrsUnits = Math.mulDiv(shares, p.dlrsReserve, total); // floor, pro-rata
        if (spokeUnits == 0 && dlrsUnits == 0) revert ZeroAmount();

        // Effects before interaction (CEI): burn shares, then pay each side.
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
            // Pay the DLRS side out of hub reserves, greedily across the (small, fixed) hub-asset set.
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
            // dlrsReserve is always backed by hub reserves (conservation), so this never leaves a
            // shortfall; the check is defensive and reverts atomically if it somehow did.
            if (remaining != 0) revert InsufficientReserves(spokeAsset, dlrsUnits, dlrsUnits - remaining);
        }

        emit SpokeRedeemed(poolId, msg.sender, shares, spokeUnits, dlrsUnits);
    }

    // ============ Directed Swaps & Queues (M4) ============

    /// @inheritdoc IDollarStore
    /// @dev Fill order: exact-opposite queue -> protocol reserves (only if the same-direction
    ///      queue is empty) -> queue the remainder. Hub-hub swaps are reserve-neutral (no DLRS
    ///      mint/burn) — they move reserve value 1:1 between assets. tip must be 0 (reserved for U1).
    function swap(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 tip,
        uint256 deadline
    ) external override nonReentrant whenNotPaused returns (uint256 amountFilled, uint256 amountQueued) {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);
        if (tip != 0) revert TipNotEnabled();

        Route memory route = _validateRoute(offerAsset, wantAsset);
        _checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, route.offerScaling);
        if (amountUnits == 0) revert ZeroAmount();

        _pullExact(offerAsset, nativePulled);

        amountFilled = _fillDirected(route, offerAsset, wantAsset, amountUnits, true);
        uint256 remaining = amountUnits - amountFilled;

        if (amountFilled < minAmountOut) revert MinAmountNotMet(amountFilled, minAmountOut);

        if (amountFilled > 0) {
            IERC20(wantAsset).safeTransfer(msg.sender, NormalizationLib.toNative(amountFilled, route.wantScaling));
        }

        if (remaining > 0) {
            _enqueueRemainder(offerAsset, wantAsset, remaining);
            amountQueued = remaining;
        }

        emit Swap(msg.sender, offerAsset, wantAsset, amountUnits, amountFilled, amountQueued);
    }

    /// @inheritdoc IDollarStore
    /// @dev All-or-nothing: fills fully from opposite queue + reserves or reverts. Never queues.
    function swapExactInput(
        address offerAsset,
        address wantAsset,
        uint256 amount,
        uint256 minAmountOut,
        uint256 deadline
    ) external override nonReentrant whenNotPaused returns (uint256 amountOut) {
        if (block.timestamp > deadline) revert DeadlineExpired(deadline, block.timestamp);

        Route memory route = _validateRoute(offerAsset, wantAsset);
        _checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, route.offerScaling);
        if (amountUnits == 0) revert ZeroAmount();

        _pullExact(offerAsset, nativePulled);

        uint256 filled = _fillDirected(route, offerAsset, wantAsset, amountUnits, true);
        if (filled < amountUnits) revert InsufficientLiquidity(filled, amountUnits);

        // minAmountOut is a floor in normalized 6dp units, same convention as swap() (L-01).
        if (filled < minAmountOut) revert MinAmountNotMet(filled, minAmountOut);
        amountOut = NormalizationLib.toNative(filled, route.wantScaling);

        IERC20(wantAsset).safeTransfer(msg.sender, amountOut);
        emit Swap(msg.sender, offerAsset, wantAsset, amountUnits, filled, 0);
    }

    /// @inheritdoc IDollarStore
    /// @dev Exit path: not blocked by pause. Returns the escrowed offer; on a failed transfer the
    ///      escrow is converted to a DLRS claim (moved to hub reserves + DLRS minted) to avoid bricking.
    function cancelQueue(uint256 positionId) external override nonReentrant {
        QueueStorage.QueuePosition storage p = QueueStorage.layout().positions[positionId];
        if (p.owner == address(0)) revert QueuePositionNotFound(positionId);
        if (p.owner != msg.sender) revert NotPositionOwner(positionId, msg.sender);
        _cancelPosition(positionId);
    }

    /// @inheritdoc IDollarStore
    /// @dev Fills the (offerAsset -> wantAsset) queue from reserves[wantAsset] in FIFO order,
    ///      bounded by `maxPositions`. Each fill moves the owner's escrowed offer into reserves.
    function processQueue(address offerAsset, address wantAsset, uint256 maxPositions)
        external
        override
        nonReentrant
        whenNotPaused
        returns (uint256 positionsProcessed, uint256 amountFilled)
    {
        // Classify the route (also blocks a paused spoke) and gate the offer side the same way a
        // deposit is: filling a queued position moves the owner's escrowed offer asset into reserves,
        // which is deposit-equivalent, so block while it is deposit-paused, pool-paused, or off-peg.
        // Otherwise a paused/depegged asset could still be pushed into the pool via queue processing.
        Route memory route = _validateRoute(offerAsset, wantAsset);
        _checkInflow(offerAsset);

        (positionsProcessed, amountFilled) = _settleSameDirection(route, offerAsset, wantAsset, maxPositions);
    }

    // ============ Swap / Queue Views ============

    /// @inheritdoc IDollarStore
    function getQueueDepth(address offerAsset, address wantAsset) external view override returns (uint256) {
        return QueueStorage.layout().queues[QueueStorage.queueKey(offerAsset, wantAsset)].totalDepth;
    }

    /// @inheritdoc IDollarStore
    function getQueuePosition(uint256 positionId)
        external
        view
        override
        returns (address, address, address, uint256, uint256)
    {
        QueueStorage.QueuePosition storage p = QueueStorage.layout().positions[positionId];
        return (p.owner, p.offerAsset, p.wantAsset, p.offerAmount, p.timestamp);
    }

    /// @inheritdoc IDollarStore
    function getUserQueuePositions(address user) external view override returns (uint256[] memory) {
        return QueueStorage.layout().userPositions[user];
    }

    /// @inheritdoc IDollarStore
    function getMinimumOrderSize(address offerAsset, address wantAsset) external view override returns (uint256) {
        uint256 count = QueueStorage.layout().queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount;
        return QueueLib.minimumOrderSize(count);
    }

    /// @inheritdoc IDollarStore
    function getSwapQuote(address offerAsset, address wantAsset, uint256 amount)
        external
        view
        override
        returns (uint256)
    {
        (bool valid, Route memory route) = _classifyRoute(offerAsset, wantAsset);
        if (!valid) return 0;

        QueueStorage.Layout storage qs = QueueStorage.layout();
        // FIFO availability: a non-empty same-direction queue owns all instant liquidity.
        if (qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount != 0) {
            return 0;
        }

        uint256 units = amount / route.offerScaling;
        if (units == 0) return 0;

        // Instant liquidity = opposite-queue escrow (peer matches) + route-aware protocol reserves.
        uint256 avail = qs.queues[QueueStorage.queueKey(wantAsset, offerAsset)].totalDepth
            + _wantReserveAvailable(route, wantAsset);
        uint256 fillable = units <= avail ? units : avail;
        return NormalizationLib.toNative(fillable, route.wantScaling);
    }

    // ============ Internal: routing & fills ============

    /// @dev Validates and classifies a swap route. Allowed: hub->hub, hub->spoke, spoke->hub. Rejects
    ///      same-asset and spoke->spoke. A swap touching a paused spoke pool is blocked here (killed
    ///      spokes are already blocked because their asset is unlisted).
    function _validateRoute(address offerAsset, address wantAsset) internal view returns (Route memory route) {
        if (offerAsset == wantAsset) revert SameAsset();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage offerCfg = r.assetConfig[offerAsset];
        RegistryStorage.AssetConfig storage wantCfg = r.assetConfig[wantAsset];
        if (!offerCfg.listed) revert AssetNotListed(offerAsset);
        if (!wantCfg.listed) revert AssetNotListed(wantAsset);

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
            revert InvalidRoute(offerAsset, wantAsset); // spoke -> spoke
        }

        if (route.spokePoolId != 0) {
            RegistryStorage.Pool storage sp = r.pools[route.spokePoolId];
            if (sp.paused) revert PoolPaused(route.spokePoolId);
            // Winding down: block risk-increasing spoke->hub (grows the spoke asset reserve). The
            // risk-reducing hub->spoke direction (grows the hub-backed dlrsReserve) stays live.
            if (sp.status == RegistryStorage.PoolStatus.WindingDown && route.kind == RouteKind.SpokeToHub) {
                revert SpokeWindingDown(route.spokePoolId);
            }
        }
    }

    /// @dev Non-reverting route classification for views (getSwapQuote). Returns valid == false for any
    ///      unsupported route (same-asset, unlisted, spoke->spoke, or a paused spoke).
    function _classifyRoute(address offerAsset, address wantAsset)
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

    /// @dev Protocol-reserve liquidity available to fill `want` for a route. Hub->hub: hub reserve of
    ///      want. Hub->spoke: the spoke's reserve of the (spoke) want asset. Spoke->hub: hub reserve of
    ///      want, bounded by the spoke's exitable DLRS (dlrsReserve above minDlrsReserve).
    function _wantReserveAvailable(Route memory route, address want) internal view returns (uint256) {
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
    ///      (absorbed), per route. Caller must ensure `fill <= _wantReserveAvailable(route, want)`.
    function _applyReserveFill(Route memory route, address offer, address want, uint256 fill) internal {
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
    function _pullExact(address asset, uint256 nativeAmount) internal {
        uint256 balBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), nativeAmount);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balBefore;
        if (received < nativeAmount) revert FeeOnTransferNotSupported(asset);
    }

    /// @dev Fills a directed swap: exact-opposite queue first, then reserves (only if the
    ///      same-direction queue is empty). Sends offer to matched owners; returns the filled
    ///      amount (== want units owed to the swapper, delivered by the caller).
    function _fillDirected(
        Route memory route,
        address offerAsset,
        address wantAsset,
        uint256 amountUnits,
        bool allowReserves
    ) internal returns (uint256 filled) {
        QueueStorage.Layout storage qs = QueueStorage.layout();
        uint256 remaining = amountUnits;

        // Step 1: exact-opposite queue (wantAsset -> offerAsset). This is a peer-to-peer escrow match
        // (pay the queued owner the offer, deliver their escrowed want to the swapper); it touches no
        // protocol reserves and no dlrsReserve, so it is route-independent.
        uint256 current = qs.queues[QueueStorage.queueKey(wantAsset, offerAsset)].head;
        while (current != 0 && remaining > 0) {
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            address o = p.owner;
            uint256 posAmt = p.offerAmount; // escrowed wantAsset units
            uint256 fill = posAmt <= remaining ? posAmt : remaining;

            if (_tryTransfer(offerAsset, o, NormalizationLib.toNative(fill, route.offerScaling))) {
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
                _refundEscrow(current, owner_, escrowAsset, posAmt);
            }
            current = next;
        }

        // Step 2: protocol reserves. FIFO rule (M-01): any earlier same-direction queued positions
        // are entitled to these reserves first, so settle them (bounded) before the swapper touches
        // reserves. Only fill the swapper's remainder if the queue is now fully cleared; a deeper
        // queue keeps its order and the swapper queues its remainder (handled by the caller).
        if (allowReserves && remaining > 0) {
            _settleSameDirection(route, offerAsset, wantAsset, MAX_INLINE_SETTLE);
            if (qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount == 0) {
                uint256 available = _wantReserveAvailable(route, wantAsset);
                uint256 fill = available <= remaining ? available : remaining;
                if (fill > 0) {
                    _applyReserveFill(route, offerAsset, wantAsset, fill);
                    remaining -= fill;
                    filled += fill;
                }
            }
        }
    }

    /// @dev Settles the (offerAsset -> wantAsset) queue from protocol reserves in FIFO order, bounded by
    ///      `maxPositions`, using route-aware accounting (`_wantReserveAvailable` / `_applyReserveFill`).
    ///      Pays each queued owner their wantAsset and absorbs their escrowed offer; on a failed payout,
    ///      ejects the position and converts its escrow into the canonical receipt (`_refundEscrow`).
    ///      Callers must have inflow-gated `offerAsset` (deposit-equivalent). Shared by processQueue, the
    ///      swap reserve-fill path (M-01), and deposit-triggered settlement (U2).
    function _settleSameDirection(Route memory route, address offerAsset, address wantAsset, uint256 maxPositions)
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

            uint256 available = _wantReserveAvailable(route, wantAsset);
            if (available == 0) break;

            uint256 fill = posAmt <= available ? posAmt : available;

            if (_tryTransfer(wantAsset, o, NormalizationLib.toNative(fill, route.wantScaling))) {
                _applyReserveFill(route, offerAsset, wantAsset, fill);
                amountFilled += fill;
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
                _refundEscrow(current, owner_, escrowAsset, posAmt);
            }

            positionsProcessed += 1;
            current = next;
        }
    }

    /// @dev Escrow the remainder into the (offerAsset -> wantAsset) queue. Enforces cap and the
    ///      minimum order size, with the below-minimum exception only for the first position.
    function _enqueueRemainder(address offerAsset, address wantAsset, uint256 remaining) internal {
        QueueStorage.Layout storage qs = QueueStorage.layout();
        QueueStorage.Queue storage q = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)];
        if (q.positionCount >= QueueStorage.MAX_QUEUE_POSITIONS) revert QueueFull(offerAsset, wantAsset);

        uint256 minOrder = QueueLib.minimumOrderSize(q.positionCount);
        // Below-minimum allowed only when opening the first position of an empty directed queue.
        if (remaining < minOrder && q.positionCount != 0) revert OrderTooSmall(remaining, minOrder);

        uint256 positionId = QueueLib.enqueue(qs, offerAsset, wantAsset, msg.sender, remaining);
        emit QueueJoined(positionId, msg.sender, offerAsset, wantAsset, remaining);
    }

    /// @dev Low-level transfer that returns false instead of reverting (for blacklist resilience).
    function _tryTransfer(address token, address to, uint256 amount) internal returns (bool) {
        if (amount == 0) return true;
        (bool ok, bytes memory data) = token.call(abi.encodeCall(IERC20.transfer, (to, amount)));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    /// @dev Remove a position and return its escrow to the owner; on a failed transfer (e.g. the owner
    ///      is blacklisted on the escrow token), convert the escrow into the canonical receipt.
    function _cancelPosition(uint256 positionId) internal {
        (address owner_, address offerAsset, uint256 amount) = QueueLib.remove(QueueStorage.layout(), positionId);
        uint64 scaling = RegistryStorage.layout().assetConfig[offerAsset].scalingFactor;
        if (_tryTransfer(offerAsset, owner_, NormalizationLib.toNative(amount, scaling))) {
            emit QueueCancelled(positionId, owner_, amount);
        } else {
            _refundEscrow(positionId, owner_, offerAsset, amount);
        }
    }

    /// @dev Blacklist-safe fallback: convert an ejected position's escrow into its canonical receipt.
    ///      A HUB escrow asset moves into hub reserves and mints DLRS 1:1 (a claim on the hub basket).
    ///      A SPOKE escrow asset moves into that spoke's reserve and mints the spoke's non-transferable
    ///      receipt shares pro-rata (U2), so a spoke asset never silently backs the hub. Never reverts.
    function _refundEscrow(uint256 positionId, address owner_, address escrowAsset, uint256 amount) internal {
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

    // ============ Risk Controls (M5) ============

    /// @inheritdoc IDollarStore
    function setPriceFeed(address asset, address feed) external override onlyGovernor {
        if (feed == address(0)) revert ZeroAddress();
        uint8 feedDec = AggregatorV3Interface(feed).decimals();
        if (feedDec > MAX_FEED_DECIMALS) revert NormalizationLib.UnsupportedDecimals(feedDec);
        RegistryStorage.AssetConfig storage cfg = RegistryStorage.layout().assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        cfg.priceFeed = feed;
        emit PriceFeedUpdated(asset, feed);
    }

    /// @inheritdoc IDollarStore
    function setPegTolerance(uint256 tolerance) external override onlyGovernor {
        if (tolerance == 0 || tolerance > MAX_PEG_TOLERANCE_BPS) revert InvalidTolerance();
        CoreStorage.layout().pegTolerance = tolerance;
        emit PegToleranceSet(tolerance);
    }

    /// @inheritdoc IDollarStore
    function setMaxStaleness(uint256 staleness) external override onlyGovernor {
        if (staleness == 0 || staleness > 1 days) revert InvalidStaleness();
        CoreStorage.layout().maxStaleness = staleness;
        emit MaxStalenessSet(staleness);
    }

    /// @inheritdoc IDollarStore
    function pauseDeposits(address asset) external override onlyGuardian {
        RegistryStorage.AssetConfig storage cfg = RegistryStorage.layout().assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        cfg.depositPaused = true;
        emit DepositsPausedSet(asset, true);
    }

    /// @inheritdoc IDollarStore
    function unpauseDeposits(address asset) external override onlyGuardian {
        RegistryStorage.AssetConfig storage cfg = RegistryStorage.layout().assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        cfg.depositPaused = false;
        emit DepositsPausedSet(asset, false);
    }

    /// @inheritdoc IDollarStore
    function pausePool(uint16 poolId) external override onlyGuardian {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        r.pools[poolId].paused = true;
        emit PoolPausedSet(poolId, true);
    }

    /// @inheritdoc IDollarStore
    function unpausePool(uint16 poolId) external override onlyGuardian {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        r.pools[poolId].paused = false;
        emit PoolPausedSet(poolId, false);
    }

    /// @inheritdoc IDollarStore
    /// @dev Escrow-aware: reserves sync down to (actualBalance - escrow). Only decreases.
    function syncReserves(uint16 poolId, address asset) external override onlyGovernor {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        if (cfg.poolId != poolId) revert WrongPool(asset, poolId);

        uint256 actualUnits = IERC20(asset).balanceOf(address(this)) / cfg.scalingFactor;
        uint256 escrowUnits = QueueStorage.layout().totalEscrowedByAsset[asset];
        uint256 prevReserves = r.reserves[poolId][asset];

        if (actualUnits >= prevReserves + escrowUnits) revert ReservesNotDrifted(asset);
        if (actualUnits < escrowUnits) revert EscrowImpaired(asset); // deeper haircut path deferred

        uint256 newReserves = actualUnits - escrowUnits;
        r.reserves[poolId][asset] = newReserves;
        emit ReservesSynced(asset, prevReserves, newReserves);
    }

    /// @inheritdoc IDollarStore
    /// @dev Sweeps only the excess above accounted (reserves + escrow); full balance for unlisted assets.
    function rescueTokens(address asset, address to) external override onlyGovernor {
        if (to == address(0)) revert ZeroAddress();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];

        uint256 actual = IERC20(asset).balanceOf(address(this));
        uint256 accounted = 0;
        if (cfg.listed) {
            uint256 escrowUnits = QueueStorage.layout().totalEscrowedByAsset[asset];
            accounted = (r.reserves[cfg.poolId][asset] + escrowUnits) * cfg.scalingFactor;
        }
        if (actual <= accounted) revert NoExcessTokens(asset);

        uint256 excess = actual - accounted;
        IERC20(asset).safeTransfer(to, excess);
        emit TokensRescued(asset, to, excess);
    }

    /// @inheritdoc IDollarStore
    /// @dev Guardian emergency, paused-only. Reduces the queue escrow of a balance-impaired asset
    ///      pro-rata so the escrow accounting fits the surviving token balance. Only touches queue
    ///      positions; the reserve (LP) side is handled separately by syncReserves + share exposure.
    ///      Deep impairment (actual < reserves) haircuts escrow toward 0, then syncReserves writes the
    ///      reserve down. Purely accounting - no token transfers.
    function haircutEscrow(address asset, uint256 maxPositions)
        external
        override
        onlyGuardian
        nonReentrant
        returns (uint256 removedUnits)
    {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        if (!r.pools[cfg.poolId].paused) revert PoolNotPaused(cfg.poolId);

        QueueStorage.Layout storage qs = QueueStorage.layout();
        uint256 escrow = qs.totalEscrowedByAsset[asset];
        if (escrow == 0) revert NoEscrowToHaircut(asset);

        uint256 actualUnits = IERC20(asset).balanceOf(address(this)) / cfg.scalingFactor;
        uint256 reserves = r.reserves[cfg.poolId][asset];
        if (actualUnits >= reserves + escrow) revert AssetNotImpaired(asset);

        // Escrow absorbs its share of the shortfall: bring total escrow down to what the surviving
        // balance can back after reserves. keepRatio = targetEscrow / escrow, applied to each position.
        uint256 targetEscrow = actualUnits > reserves ? actualUnits - reserves : 0;

        uint256 budget = maxPositions;
        uint256 poolLen = r.pools.length;
        for (uint256 pid; pid < poolLen; ++pid) {
            address[] storage passets = r.pools[pid].assets;
            for (uint256 a; a < passets.length; ++a) {
                address want = passets[a];
                if (want == asset) continue; // spoke->spoke queues never exist; same-asset is invalid
                budget = _haircutQueue(qs, asset, want, targetEscrow, escrow, budget);
            }
        }

        uint256 newEscrow = qs.totalEscrowedByAsset[asset];
        removedUnits = escrow - newEscrow;
        emit EscrowHaircut(asset, cfg.poolId, escrow, newEscrow);
    }

    /// @dev Apply the haircut ratio (targetEscrow/escrow) to every position in the (offerAsset ->
    ///      wantAsset) queue: reduce each pro-rata, or remove it if its share floors to zero. Returns
    ///      the remaining position budget; reverts if the queue is deeper than the budget allows.
    function _haircutQueue(
        QueueStorage.Layout storage qs,
        address offerAsset,
        address wantAsset,
        uint256 targetEscrow,
        uint256 escrow,
        uint256 budget
    ) internal returns (uint256) {
        uint256 current = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].head;
        while (current != 0) {
            if (budget == 0) revert HaircutBudgetExceeded();
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

    /// @inheritdoc IDollarStore
    function adminCancelQueue(uint256 positionId) external override nonReentrant onlyGuardian {
        if (QueueStorage.layout().positions[positionId].owner == address(0)) revert QueuePositionNotFound(positionId);
        _cancelPosition(positionId);
    }

    // ============ Risk Views ============

    /// @inheritdoc IDollarStore
    function isDepositPaused(address asset) external view override returns (bool) {
        return RegistryStorage.layout().assetConfig[asset].depositPaused;
    }

    /// @inheritdoc IDollarStore
    function isPoolPaused(uint16 poolId) external view override returns (bool) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return r.pools[poolId].paused;
    }

    /// @inheritdoc IDollarStore
    function pegTolerance() external view override returns (uint256) {
        return CoreStorage.layout().pegTolerance;
    }

    /// @inheritdoc IDollarStore
    function maxStaleness() external view override returns (uint256) {
        return CoreStorage.layout().maxStaleness;
    }

    // ============ Internal: risk checks ============

    /// @dev Guards an inflow of `asset`: per-asset deposit pause, pool pause, and the peg check.
    function _checkInflow(address asset) internal view {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage cfg = r.assetConfig[asset];
        if (cfg.depositPaused) revert DepositsPaused(asset);
        if (r.pools[cfg.poolId].paused) revert PoolPaused(cfg.poolId);
        _checkPeg(asset, cfg);
    }

    /// @dev Reverts if the asset's oracle price is missing, invalid, stale, or off-peg.
    function _checkPeg(address asset, RegistryStorage.AssetConfig storage cfg) internal view {
        address feed = cfg.priceFeed;
        if (feed == address(0)) revert NoPriceFeed(asset);

        AggregatorV3Interface agg = AggregatorV3Interface(feed);
        (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) = agg.latestRoundData();
        if (answer <= 0) revert InvalidPrice(asset);
        if (answeredInRound < roundId) revert StaleRound(asset);

        CoreStorage.Layout storage c = CoreStorage.layout();
        if (block.timestamp - updatedAt > c.maxStaleness) revert PriceStale(asset, updatedAt);

        uint256 scale = 10 ** (PRICE_DECIMALS - uint256(agg.decimals()));
        uint256 normalized = uint256(answer) * scale;
        uint256 lower = ONE - (ONE * c.pegTolerance / BPS_DENOMINATOR);
        uint256 upper = ONE + (ONE * c.pegTolerance / BPS_DENOMINATOR);
        if (normalized < lower || normalized > upper) revert PriceOutOfBounds(asset, normalized, lower, upper);
    }

    // ============ Launch Caps (M6) ============

    /// @inheritdoc IDollarStore
    function setLaunchCap(uint16 poolId, uint256 cap) external override onlyGovernor {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        r.pools[poolId].launchCap = cap;
        emit LaunchCapSet(poolId, cap);
    }

    /// @inheritdoc IDollarStore
    function lowerLaunchCap(uint16 poolId, uint256 cap) external override onlyGuardian {
        if (cap == 0) revert CapNotStricter(); // 0 would remove/loosen — governor-only
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        uint256 current = r.pools[poolId].launchCap;
        // Stricter = a positive cap below the current one (or any positive value if uncapped).
        if (current != 0 && cap >= current) revert CapNotStricter();
        r.pools[poolId].launchCap = cap;
        emit LaunchCapSet(poolId, cap);
    }

    /// @inheritdoc IDollarStore
    function getLaunchCap(uint16 poolId) external view override returns (uint256) {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId);
        return r.pools[poolId].launchCap;
    }

    /// @dev Enforce a pool's launch cap against its active exposure. cap == 0 means no cap. Queue
    ///      escrow is excluded from exposure (it is not active pool liquidity). For the hub (poolId 0),
    ///      exposure == total DLRS supply (backed 1:1 by hub reserves). For a spoke, exposure == that
    ///      spoke's asset reserve + its dlrsReserve (U2).
    function _checkLaunchCap(uint16 poolId, uint256 addedUnits) internal view {
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        if (poolId >= r.pools.length) revert InvalidPool(poolId); // defense-in-depth (callers validate)
        RegistryStorage.Pool storage p = r.pools[poolId];
        uint256 cap = p.launchCap;
        if (cap == 0) return;
        uint256 newExposure;
        if (poolId == 0) {
            newExposure = DLRS(CoreStorage.layout().dlrs).totalSupply() + addedUnits;
        } else {
            newExposure = r.reserves[poolId][p.assets[0]] + p.dlrsReserve + addedUnits;
        }
        if (newExposure > cap) revert LaunchCapExceeded(poolId, newExposure, cap);
    }

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorize a UUPS upgrade. Upgrader-gated (separate from the governor, M8).
    /// @dev In production the upgrader is a TimelockController (longest delay), so upgrades carry
    ///      a public delay and cannot be triggered by a governor or guardian compromise alone.
    /// @param newImplementation The address of the new implementation (validated by UUPS machinery).
    function _authorizeUpgrade(address newImplementation) internal override onlyUpgrader {}
}
