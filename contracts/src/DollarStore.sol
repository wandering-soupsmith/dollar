// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDollarStore} from "./interfaces/IDollarStore.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {CoreStorage} from "./storage/CoreStorage.sol";
import {RegistryStorage} from "./storage/RegistryStorage.sol";
import {QueueStorage} from "./storage/QueueStorage.sol";
import {NormalizationLib} from "./libraries/NormalizationLib.sol";
import {QueueLib} from "./libraries/QueueLib.sol";
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
        $.pegTolerance = 50; // 0.5%
        $.maxStaleness = 3600; // 1 hour

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
        return "0.8.1-M8.1";
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
    /// @dev Hub-only in M3. New exposure → gated by global pause + reentrancy guard.
    ///      Pulls only `nativePulled` (= units * scalingFactor); sub-unit dust stays with the user.
    ///      A before/after balance check rejects fee-on-transfer tokens. Per-asset deposit pause
    ///      and the oracle peg check are added in M5.
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
        if (cfg.poolId != poolId) revert WrongPool(asset, poolId);
        if (poolId != 0) revert NotEnabled(); // hub-only in M3; spoke deposits land in U2

        _checkInflow(asset); // per-asset/pool deposit pause + oracle peg check (M5)

        (uint256 units, uint256 nativePulled) = NormalizationLib.toUnits(amount, cfg.scalingFactor);
        if (units == 0) revert ZeroAmount();

        _checkLaunchCap(poolId, units); // temporary launch exposure cap (M6)

        // Pull tokens and verify the exact amount arrived (rejects fee-on-transfer).
        uint256 balBefore = IERC20(asset).balanceOf(address(this));
        IERC20(asset).safeTransferFrom(msg.sender, address(this), nativePulled);
        uint256 received = IERC20(asset).balanceOf(address(this)) - balBefore;
        if (received < nativePulled) revert FeeOnTransferNotSupported(asset);

        r.reserves[poolId][asset] += units;
        receiptUnits = units;

        DLRS(CoreStorage.layout().dlrs).mint(msg.sender, units);

        emit Deposit(msg.sender, poolId, asset, nativePulled, units);
    }

    /// @inheritdoc IDollarStore
    /// @dev Exit path: NOT blocked by pause (only by the reentrancy guard). Burns `units` DLRS
    ///      (a claim on the hub basket) and sends the chosen hub asset 1:1 in native units.
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
        if (cfg.poolId != poolId) revert WrongPool(asset, poolId);
        if (poolId != 0) revert NotEnabled(); // hub-only in M3; spoke withdrawals land in U2

        uint256 available = r.reserves[poolId][asset];
        if (available < units) revert InsufficientReserves(asset, units, available);

        // Effects before interaction (CEI): burn DLRS, decrease reserve, then transfer out.
        DLRS(CoreStorage.layout().dlrs).burn(msg.sender, units);
        r.reserves[poolId][asset] = available - units;

        nativeAmountOut = NormalizationLib.toNative(units, cfg.scalingFactor);
        IERC20(asset).safeTransfer(msg.sender, nativeAmountOut);

        emit Withdraw(msg.sender, poolId, asset, units, nativeAmountOut);
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

        (uint64 offerScaling, uint64 wantScaling) = _validateRoute(offerAsset, wantAsset);
        _checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, offerScaling);
        if (amountUnits == 0) revert ZeroAmount();

        _pullExact(offerAsset, nativePulled);

        amountFilled = _fillDirected(offerAsset, wantAsset, offerScaling, amountUnits, true);
        uint256 remaining = amountUnits - amountFilled;

        if (amountFilled < minAmountOut) revert MinAmountNotMet(amountFilled, minAmountOut);

        if (amountFilled > 0) {
            IERC20(wantAsset).safeTransfer(msg.sender, NormalizationLib.toNative(amountFilled, wantScaling));
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

        (uint64 offerScaling, uint64 wantScaling) = _validateRoute(offerAsset, wantAsset);
        _checkInflow(offerAsset); // block toxic inflow of a depegged/paused asset (M5)

        (uint256 amountUnits, uint256 nativePulled) = NormalizationLib.toUnits(amount, offerScaling);
        if (amountUnits == 0) revert ZeroAmount();

        _pullExact(offerAsset, nativePulled);

        uint256 filled = _fillDirected(offerAsset, wantAsset, offerScaling, amountUnits, true);
        if (filled < amountUnits) revert InsufficientLiquidity(filled, amountUnits);

        amountOut = NormalizationLib.toNative(filled, wantScaling);
        if (amountOut < minAmountOut) revert MinAmountNotMet(filled, minAmountOut);

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
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        QueueStorage.Layout storage qs = QueueStorage.layout();

        uint64 wantScaling = r.assetConfig[wantAsset].scalingFactor;
        uint256 current = qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].head;

        while (current != 0 && positionsProcessed < maxPositions) {
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            address o = p.owner;
            uint256 posAmt = p.offerAmount;

            uint256 available = r.reserves[0][wantAsset];
            if (available == 0) break;

            uint256 fill = posAmt <= available ? posAmt : available;

            if (_tryTransfer(wantAsset, o, NormalizationLib.toNative(fill, wantScaling))) {
                r.reserves[0][wantAsset] = available - fill;
                r.reserves[0][offerAsset] += fill;
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
                // Tripwire (U2): the DLRS / hub-reserve fallback is only valid for hub assets. A
                // spoke asset must instead mint that spoke's receipt into its own pool (Pool.receiptToken).
                // Unreachable in hub-only v1; stops U2 from silently backing the hub with a spoke asset.
                if (r.assetConfig[escrowAsset].poolId != 0) revert NotEnabled();
                r.reserves[0][escrowAsset] += posAmt;
                DLRS(CoreStorage.layout().dlrs).mint(owner_, posAmt);
                emit QueuePositionRefunded(current, owner_, escrowAsset, posAmt);
            }

            positionsProcessed += 1;
            current = next;
        }
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
        returns (address owner, address offerAsset, address wantAsset, uint256 amount, uint256 timestamp)
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
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig memory oc = r.assetConfig[offerAsset];
        RegistryStorage.AssetConfig memory wc = r.assetConfig[wantAsset];
        if (offerAsset == wantAsset || !oc.listed || !wc.listed || oc.poolId != 0 || wc.poolId != 0) {
            return 0;
        }

        QueueStorage.Layout storage qs = QueueStorage.layout();
        // FIFO availability: a non-empty same-direction queue owns all instant liquidity.
        if (qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount != 0) {
            return 0;
        }

        uint256 units = amount / oc.scalingFactor;
        if (units == 0) return 0;

        uint256 avail = qs.queues[QueueStorage.queueKey(wantAsset, offerAsset)].totalDepth + r.reserves[0][wantAsset];
        uint256 fillable = units <= avail ? units : avail;
        return NormalizationLib.toNative(fillable, wc.scalingFactor);
    }

    // ============ Internal: routing & fills ============

    /// @dev Validates a hub-hub swap route and returns both asset configs. Spoke routes deferred.
    function _validateRoute(address offerAsset, address wantAsset)
        internal
        view
        returns (uint64 offerScaling, uint64 wantScaling)
    {
        if (offerAsset == wantAsset) revert SameAsset();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        RegistryStorage.AssetConfig storage offerCfg = r.assetConfig[offerAsset];
        RegistryStorage.AssetConfig storage wantCfg = r.assetConfig[wantAsset];
        if (!offerCfg.listed) revert AssetNotListed(offerAsset);
        if (!wantCfg.listed) revert AssetNotListed(wantAsset);
        if (offerCfg.poolId != 0 || wantCfg.poolId != 0) revert InvalidRoute(offerAsset, wantAsset);
        offerScaling = offerCfg.scalingFactor;
        wantScaling = wantCfg.scalingFactor;
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
        address offerAsset,
        address wantAsset,
        uint64 offerScaling,
        uint256 amountUnits,
        bool allowReserves
    ) internal returns (uint256 filled) {
        QueueStorage.Layout storage qs = QueueStorage.layout();
        RegistryStorage.Layout storage r = RegistryStorage.layout();
        uint256 remaining = amountUnits;

        // Step 1: exact-opposite queue (wantAsset -> offerAsset).
        uint256 current = qs.queues[QueueStorage.queueKey(wantAsset, offerAsset)].head;
        while (current != 0 && remaining > 0) {
            QueueStorage.QueuePosition storage p = qs.positions[current];
            uint256 next = p.next;
            address o = p.owner;
            uint256 posAmt = p.offerAmount; // escrowed wantAsset units
            uint256 fill = posAmt <= remaining ? posAmt : remaining;

            if (_tryTransfer(offerAsset, o, NormalizationLib.toNative(fill, offerScaling))) {
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
                // Paying the queued owner failed: eject and convert its escrow to a DLRS claim.
                (address owner_, address escrowAsset,) = QueueLib.remove(qs, current);
                // Tripwire (U2): hub-only fallback — a spoke asset must mint its own pool's receipt
                // instead. Unreachable in v1; guards against silently backing the hub with a spoke asset.
                if (r.assetConfig[escrowAsset].poolId != 0) revert NotEnabled();
                r.reserves[0][escrowAsset] += posAmt;
                DLRS(CoreStorage.layout().dlrs).mint(owner_, posAmt);
                emit QueuePositionRefunded(current, owner_, escrowAsset, posAmt);
            }
            current = next;
        }

        // Step 2: protocol reserves, only when the same-direction queue is empty (FIFO rule).
        if (allowReserves && remaining > 0) {
            if (qs.queues[QueueStorage.queueKey(offerAsset, wantAsset)].positionCount == 0) {
                uint256 available = r.reserves[0][wantAsset];
                uint256 fill = available <= remaining ? available : remaining;
                if (fill > 0) {
                    r.reserves[0][wantAsset] = available - fill;
                    r.reserves[0][offerAsset] += fill; // swapper's offer enters reserves
                    remaining -= fill;
                    filled += fill;
                }
            }
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
        (bool ok, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, amount));
        return ok && (data.length == 0 || abi.decode(data, (bool)));
    }

    /// @dev Remove a position and return its escrow to the owner (DLRS fallback on transfer failure).
    function _cancelPosition(uint256 positionId) internal {
        (address owner_, address offerAsset, uint256 amount) = QueueLib.remove(QueueStorage.layout(), positionId);
        uint64 scaling = RegistryStorage.layout().assetConfig[offerAsset].scalingFactor;
        if (_tryTransfer(offerAsset, owner_, NormalizationLib.toNative(amount, scaling))) {
            emit QueueCancelled(positionId, owner_, amount);
        } else {
            // Tripwire (U2): hub-only fallback — a spoke asset must mint its own pool's receipt
            // instead. Unreachable in v1; guards against silently backing the hub with a spoke asset.
            if (RegistryStorage.layout().assetConfig[offerAsset].poolId != 0) revert NotEnabled();
            RegistryStorage.layout().reserves[0][offerAsset] += amount;
            DLRS(CoreStorage.layout().dlrs).mint(owner_, amount);
            emit QueuePositionRefunded(positionId, owner_, offerAsset, amount);
        }
    }

    // ============ Risk Controls (M5) ============

    /// @inheritdoc IDollarStore
    function setPriceFeed(address asset, address feed) external override onlyGovernor {
        if (feed == address(0)) revert ZeroAddress();
        RegistryStorage.AssetConfig storage cfg = RegistryStorage.layout().assetConfig[asset];
        if (!cfg.listed) revert AssetNotListed(asset);
        cfg.priceFeed = feed;
        emit PriceFeedUpdated(asset, feed);
    }

    /// @inheritdoc IDollarStore
    function setPegTolerance(uint256 tolerance) external override onlyGovernor {
        if (tolerance == 0 || tolerance > 500) revert InvalidTolerance(); // <= 5%
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
        uint256 accounted;
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

        uint256 scale = 10 ** (18 - uint256(agg.decimals()));
        uint256 normalized = uint256(answer) * scale;
        uint256 lower = 1e18 - (1e18 * c.pegTolerance / 10_000);
        uint256 upper = 1e18 + (1e18 * c.pegTolerance / 10_000);
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

    /// @dev Enforce a pool's launch cap against its active exposure. For the hub (poolId 0),
    ///      active exposure == total DLRS supply (backed 1:1 by hub reserves); queue escrow is
    ///      excluded. cap == 0 means no cap. Spoke exposure accounting lands with spokes (U2).
    function _checkLaunchCap(uint16 poolId, uint256 addedUnits) internal view {
        uint256 cap = RegistryStorage.layout().pools[poolId].launchCap;
        if (cap == 0) return;
        uint256 newExposure = DLRS(CoreStorage.layout().dlrs).totalSupply() + addedUnits;
        if (newExposure > cap) revert LaunchCapExceeded(poolId, newExposure, cap);
    }

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorize a UUPS upgrade. Upgrader-gated (separate from the governor, M8).
    /// @dev In production the upgrader is a TimelockController (longest delay), so upgrades carry
    ///      a public delay and cannot be triggered by a governor or guardian compromise alone.
    /// @param newImplementation The address of the new implementation (validated by UUPS machinery).
    function _authorizeUpgrade(address newImplementation) internal override onlyUpgrader {}
}
