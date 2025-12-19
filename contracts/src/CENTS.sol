// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CENTS - Dollar Store Utility Token
/// @notice Utility token providing fee discounts and queue priority
/// @dev Staking with time-weighted power, emissions via maker/taker rewards
contract CENTS is ERC20, ReentrancyGuard {
    // ============ Constants ============

    uint256 public constant TOTAL_SUPPLY_CAP = 1_000_000_000e6; // 1B with 6 decimals
    uint256 public constant MAKER_EMISSIONS_CAP = 600_000_000e6; // 600M (75% of 800M user pool)
    uint256 public constant TAKER_EMISSIONS_CAP = 200_000_000e6; // 200M (25% of 800M user pool)
    uint256 public constant FOUNDER_EMISSIONS_CAP = 200_000_000e6; // 200M (20% total)

    uint256 public constant FULL_POWER_DURATION = 30 days;
    uint256 public constant UNSTAKE_COOLDOWN = 7 days;

    uint256 public constant MAKER_APY_BPS = 800; // 8% APY
    uint256 public constant BPS_DENOMINATOR = 10000;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public constant CENTS_PRICE_FLOOR = 1e4; // $0.01 with 6 decimals

    // ============ State ============

    address public immutable dollarStore;
    address public founder;

    uint256 public makerEmissionsRemaining;
    uint256 public takerEmissionsRemaining;
    uint256 public founderEmissionsReceived;

    // Staking state
    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public stakeTimestamp;
    mapping(address => uint256) public unstakeInitiated;

    // Daily fee-free redemption tracking
    mapping(address => uint256) public dailyRedemptionUsed;
    mapping(address => uint256) public lastRedemptionDay;

    // ============ Events ============

    event Staked(address indexed user, uint256 amount, uint256 newStakePower);
    event UnstakeInitiated(address indexed user, uint256 amount, uint256 completionTime);
    event UnstakeCompleted(address indexed user, uint256 amount);
    event UnstakeCancelled(address indexed user, uint256 amount);
    event MakerRewardsMinted(address indexed user, uint256 centsAmount, uint256 dlrsAmount, uint256 secondsQueued);
    event TakerRewardsMinted(address indexed user, uint256 centsAmount, uint256 queueCleared, uint256 feeGenerated);
    event FounderVestingMinted(uint256 amount, uint256 totalVested);

    // ============ Errors ============

    error OnlyDollarStore();
    error ZeroAmount();
    error NotStaking();
    error AlreadyUnstaking();
    error NotUnstaking();
    error CooldownNotComplete();
    error EmissionsExhausted();
    error ZeroAddress();

    // ============ Modifiers ============

    modifier onlyDollarStore() {
        if (msg.sender != dollarStore) revert OnlyDollarStore();
        _;
    }

    // ============ Constructor ============

    constructor(address _dollarStore, address _founder) ERC20("Dollar Store Cents", "CENTS") {
        if (_dollarStore == address(0)) revert ZeroAddress();
        if (_founder == address(0)) revert ZeroAddress();

        dollarStore = _dollarStore;
        founder = _founder;

        makerEmissionsRemaining = MAKER_EMISSIONS_CAP;
        takerEmissionsRemaining = TAKER_EMISSIONS_CAP;
    }

    // ============ ERC20 Overrides ============

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // ============ Staking Functions ============

    /// @notice Stake CENTS to earn fee discounts and queue priority
    /// @param amount Amount of CENTS to stake
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();

        // Transfer CENTS from user
        _transfer(msg.sender, address(this), amount);

        uint256 existingStake = stakedBalance[msg.sender];

        if (existingStake > 0) {
            // Weighted average timestamp to preserve partial power
            uint256 oldTimestamp = stakeTimestamp[msg.sender];
            uint256 newTimestamp = (existingStake * oldTimestamp + amount * block.timestamp)
                                   / (existingStake + amount);
            stakeTimestamp[msg.sender] = newTimestamp;
        } else {
            stakeTimestamp[msg.sender] = block.timestamp;
        }

        // Clear any pending unstake
        if (unstakeInitiated[msg.sender] != 0) {
            unstakeInitiated[msg.sender] = 0;
        }

        stakedBalance[msg.sender] += amount;

        emit Staked(msg.sender, amount, getStakePower(msg.sender));
    }

    /// @notice Initiate unstaking (starts 7-day cooldown)
    function unstake() external {
        if (stakedBalance[msg.sender] == 0) revert NotStaking();
        if (unstakeInitiated[msg.sender] != 0) revert AlreadyUnstaking();

        unstakeInitiated[msg.sender] = block.timestamp;

        emit UnstakeInitiated(
            msg.sender,
            stakedBalance[msg.sender],
            block.timestamp + UNSTAKE_COOLDOWN
        );
    }

    /// @notice Complete unstaking after cooldown
    function completeUnstake() external nonReentrant {
        if (unstakeInitiated[msg.sender] == 0) revert NotUnstaking();
        if (block.timestamp < unstakeInitiated[msg.sender] + UNSTAKE_COOLDOWN) {
            revert CooldownNotComplete();
        }

        uint256 amount = stakedBalance[msg.sender];

        // Clear state
        stakedBalance[msg.sender] = 0;
        stakeTimestamp[msg.sender] = 0;
        unstakeInitiated[msg.sender] = 0;

        // Transfer CENTS back to user
        _transfer(address(this), msg.sender, amount);

        emit UnstakeCompleted(msg.sender, amount);
    }

    /// @notice Cancel unstaking (resets power timer)
    function cancelUnstake() external {
        if (unstakeInitiated[msg.sender] == 0) revert NotUnstaking();

        uint256 amount = stakedBalance[msg.sender];

        // Reset unstake and restart power timer
        unstakeInitiated[msg.sender] = 0;
        stakeTimestamp[msg.sender] = block.timestamp;

        emit UnstakeCancelled(msg.sender, amount);
    }

    // ============ Stake Power Calculation ============

    /// @notice Get current stake power for a user
    /// @dev Power = staked * sqrt(hoursStaked / 720), capped at 30 days
    /// @param user The user address
    /// @return Stake power (same units as staked amount at full power)
    function getStakePower(address user) public view returns (uint256) {
        // No power if unstaking
        if (unstakeInitiated[user] != 0) {
            return 0;
        }

        uint256 staked = stakedBalance[user];
        if (staked == 0) {
            return 0;
        }

        uint256 timeStaked = block.timestamp - stakeTimestamp[user];

        // Cap at 30 days
        if (timeStaked > FULL_POWER_DURATION) {
            timeStaked = FULL_POWER_DURATION;
        }

        // Power = staked * sqrt(timeStaked / FULL_POWER_DURATION)
        // Using: sqrt(a/b) = sqrt(a) / sqrt(b)
        // We scale up for precision: staked * sqrt(timeStaked * 1e18) / sqrt(FULL_POWER_DURATION * 1e18)

        uint256 scaledTime = timeStaked * 1e18;
        uint256 scaledFullPower = FULL_POWER_DURATION * 1e18;

        uint256 sqrtTime = sqrt(scaledTime);
        uint256 sqrtFullPower = sqrt(scaledFullPower);

        return (staked * sqrtTime) / sqrtFullPower;
    }

    /// @notice Get remaining daily fee-free redemption capacity
    /// @param user The user address
    /// @return Remaining fee-free capacity in DLRS units
    function getDailyFeeFreeCap(address user) external view returns (uint256) {
        uint256 stakePower = getStakePower(user);
        uint256 today = block.timestamp / 1 days;

        if (lastRedemptionDay[user] < today) {
            return stakePower; // Fresh day, full cap
        }

        if (stakePower <= dailyRedemptionUsed[user]) {
            return 0;
        }
        return stakePower - dailyRedemptionUsed[user];
    }

    // ============ Emissions Functions (called by DollarStore) ============

    /// @notice Mint maker rewards when queue position is filled
    /// @param recipient The maker who was filled
    /// @param dlrsAmount Amount of DLRS that was queued
    /// @param secondsQueued Time the position was in queue
    /// @return centsAmount Amount of CENTS minted
    function mintMakerRewards(
        address recipient,
        uint256 dlrsAmount,
        uint256 secondsQueued
    ) external onlyDollarStore returns (uint256 centsAmount) {
        // Calculate USD earnings: dlrsAmount * APY * (seconds / year)
        // USD earnings = dlrsAmount * 0.08 * (secondsQueued / SECONDS_PER_YEAR)
        uint256 usdEarnings = (dlrsAmount * MAKER_APY_BPS * secondsQueued)
                              / (BPS_DENOMINATOR * SECONDS_PER_YEAR);

        // Convert to CENTS at floor price ($0.01)
        // centsAmount = usdEarnings / $0.01 = usdEarnings / 0.01 = usdEarnings * 100
        // But with 6 decimals: usdEarnings (6 dec) / CENTS_PRICE_FLOOR (6 dec) * 1e6
        centsAmount = (usdEarnings * 1e6) / CENTS_PRICE_FLOOR;

        if (centsAmount == 0) {
            return 0;
        }

        // Check emissions cap
        if (centsAmount > makerEmissionsRemaining) {
            centsAmount = makerEmissionsRemaining;
        }

        if (centsAmount == 0) {
            return 0;
        }

        // Mint with founder share
        _mintWithFounderShare(recipient, centsAmount, true);

        emit MakerRewardsMinted(recipient, centsAmount, dlrsAmount, secondsQueued);

        return centsAmount;
    }

    /// @notice Mint taker rewards when deposit clears queue
    /// @param recipient The taker who deposited
    /// @param queueCleared Amount of queue cleared
    /// @param feeGenerated Fee amount generated (1bp of queueCleared)
    /// @return centsAmount Amount of CENTS minted
    function mintTakerRewards(
        address recipient,
        uint256 queueCleared,
        uint256 feeGenerated
    ) external onlyDollarStore returns (uint256 centsAmount) {
        // Convert fee to CENTS at floor price
        centsAmount = (feeGenerated * 1e6) / CENTS_PRICE_FLOOR;

        if (centsAmount == 0) {
            return 0;
        }

        // Check emissions cap
        if (centsAmount > takerEmissionsRemaining) {
            centsAmount = takerEmissionsRemaining;
        }

        if (centsAmount == 0) {
            return 0;
        }

        // Mint with founder share
        _mintWithFounderShare(recipient, centsAmount, false);

        emit TakerRewardsMinted(recipient, centsAmount, queueCleared, feeGenerated);

        return centsAmount;
    }

    /// @notice Record fee-free redemption usage (called by DollarStore)
    /// @param user The user redeeming
    /// @param feeFreePortion Amount of fee-free redemption used
    function recordRedemption(address user, uint256 feeFreePortion) external onlyDollarStore {
        uint256 today = block.timestamp / 1 days;

        // Reset if new day
        if (lastRedemptionDay[user] < today) {
            dailyRedemptionUsed[user] = 0;
            lastRedemptionDay[user] = today;
        }

        dailyRedemptionUsed[user] += feeFreePortion;
    }

    // ============ Internal Functions ============

    /// @dev Mint tokens with 1:4 founder share
    function _mintWithFounderShare(address recipient, uint256 userAmount, bool isMaker) internal {
        // Decrement appropriate pool
        if (isMaker) {
            makerEmissionsRemaining -= userAmount;
        } else {
            takerEmissionsRemaining -= userAmount;
        }

        // Calculate founder share (1:4 ratio)
        uint256 founderAmount = userAmount / 4;
        uint256 founderRemaining = FOUNDER_EMISSIONS_CAP - founderEmissionsReceived;
        if (founderAmount > founderRemaining) {
            founderAmount = founderRemaining;
        }

        // Mint to user
        _mint(recipient, userAmount);

        // Mint to founder
        if (founderAmount > 0) {
            _mint(founder, founderAmount);
            founderEmissionsReceived += founderAmount;
            emit FounderVestingMinted(founderAmount, founderEmissionsReceived);
        }
    }

    /// @dev Babylonian square root
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;

        uint256 z = (x + 1) / 2;
        uint256 y = x;

        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }

    // ============ View Functions ============

    /// @notice Get staking info for a user
    function getStakingInfo(address user) external view returns (
        uint256 staked,
        uint256 stakePower,
        uint256 stakedSince,
        uint256 unstakeTime,
        bool isUnstaking
    ) {
        staked = stakedBalance[user];
        stakePower = getStakePower(user);
        stakedSince = stakeTimestamp[user];
        unstakeTime = unstakeInitiated[user];
        isUnstaking = unstakeTime != 0;
    }

    /// @notice Get emission stats
    function getEmissionStats() external view returns (
        uint256 makerRemaining,
        uint256 takerRemaining,
        uint256 founderVested,
        uint256 totalMinted
    ) {
        makerRemaining = makerEmissionsRemaining;
        takerRemaining = takerEmissionsRemaining;
        founderVested = founderEmissionsReceived;
        totalMinted = totalSupply();
    }
}
