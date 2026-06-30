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
import {CoreStorage} from "./storage/CoreStorage.sol";
import {RegistryStorage} from "./storage/RegistryStorage.sol";
import {NormalizationLib} from "./libraries/NormalizationLib.sol";
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
    /// @param governor_ The governor address (structure + upgrade authority).
    /// @param guardian_ The guardian address (emergency authority).
    function initialize(address governor_, address guardian_) external initializer {
        if (governor_ == address(0)) revert ZeroAddress();
        if (guardian_ == address(0)) revert ZeroAddress();

        __Pausable_init();
        // ReentrancyGuard (OZ v5.6+) is stateless/namespaced and has no initializer:
        // the guard slot defaults to 0, which `_nonReentrantBefore` treats as NOT_ENTERED.

        CoreStorage.Layout storage $ = CoreStorage.layout();
        $.governor = governor_;
        $.guardian = guardian_;
        $.dlrs = address(new DLRS(address(this)));

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
    function dlrs() external view override returns (address) {
        return CoreStorage.layout().dlrs;
    }

    /// @inheritdoc IDollarStore
    function version() external pure override returns (string memory) {
        return "0.3.0-M3";
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

        (uint256 units, uint256 nativePulled) = NormalizationLib.toUnits(amount, cfg.scalingFactor);
        if (units == 0) revert ZeroAmount();

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

    // ============ UUPS Upgrade Authorization ============

    /// @notice Authorize a UUPS upgrade. Governor-gated.
    /// @dev In production the governor is a TimelockController, so upgrades carry a public delay.
    /// @param newImplementation The address of the new implementation (validated by UUPS machinery).
    function _authorizeUpgrade(address newImplementation) internal override onlyGovernor {}
}
