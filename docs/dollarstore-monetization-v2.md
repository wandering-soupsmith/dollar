# Dollar Store Monetization v2: CENTS Token

## Overview

This document specifies the monetization layer for Dollar Store via the CENTS utility token. CENTS provides two benefits: reduced redemption fees and queue priority. CENTS is earned by participating in the marketplace as a maker (queuing DLRS) or taker (depositing to clear queue).

This design maintains regulatory clarity by making CENTS a pure utility token with no revenue sharing or dividend-like mechanics.

---

## The CENTS Token

### Supply

- **Total Supply**: 1,000,000,000 (1 billion) CENTS
- **Distribution Pool**: 800,000,000 (80%) — earned via maker/taker rewards
- **Founder Allocation**: 200,000,000 (20%) — vested proportionally with distribution

Founder vesting mechanic: For every 4 CENTS distributed to users, 1 CENTS is minted to founder. This aligns founder incentives with platform growth and ensures founder allocation vests alongside actual usage.

No pre-mint. CENTS are minted as earned. Total supply is a hard cap — when 1B is reached, emissions stop forever.

### Supported Stablecoins

- USDC (Circle)
- USDT (Tether)

---

## Earning CENTS

### Maker Rewards (75% of distribution pool = 600M CENTS)

Users earn CENTS by queuing DLRS (placing maker orders). This compensates users for locking capital and signaling demand.

**Mechanic**: APY-based earnings denominated in USD, paid in CENTS.

```
centsEarned = (dlrsQueued * timeInQueue * apyRate) / centsPrice
```

**Parameters**:
- `apyRate`: 8% annually (adjustable via governance if introduced later)
- `centsPrice`: Floor of $0.01, or Uniswap TWAP if conditions met

**APY Example**:
- Queue 100,000 DLRS for 1 week
- USD earnings: $100,000 × 8% × (7/365) = $153.42
- At floor price: $153.42 / $0.01 = 15,342 CENTS

### Taker Rewards (25% of distribution pool = 200M CENTS)

Users earn CENTS by depositing stablecoins that clear queued orders. This rewards liquidity providers who resolve market imbalances.

**Mechanic**: 1:1 value match with fees generated, denominated at CENTS price.

```
centsEarned = feeGenerated / centsPrice
```

**Parameters**:
- `feeGenerated`: 1bp of the queue amount cleared
- `centsPrice`: Floor of $0.01, or Uniswap TWAP if conditions met

**Taker Example**:
- Deposit $10,000 USDC that clears $10,000 of USDT queue
- Fee generated: $10,000 × 0.0001 = $1.00
- At floor price: $1.00 / $0.01 = 100 CENTS

### CENTS Price Oracle

CENTS price uses a floor with market override:

- **Default**: $0.01 per CENTS
- **Market Override**: Uniswap V3 TWAP when:
  - CENTS/USDC pool has ≥$500k liquidity per side ($1M total)
  - TWAP price ≥ $0.01

This protects against hyperinflation during early days or price crashes while allowing natural emission slowdown as CENTS appreciates.

### Emission Dynamics

The USD-denominated approach creates self-regulating emissions:

| CENTS Price | $100k queued 1 week (maker) | $10k deposit clearing queue (taker) |
|-------------|-----------------------------|------------------------------------|
| $0.01 (floor) | 15,342 CENTS | 100 CENTS |
| $0.05 | 3,068 CENTS | 20 CENTS |
| $0.50 | 307 CENTS | 2 CENTS |

Higher CENTS price → fewer CENTS emitted → supply pressure decreases → price supported.

---

## Staking CENTS

### Stake Power

Stake power determines both fee discounts and queue priority. It follows a logarithmic curve based on staking duration:

```
stakePower = stakedCents * sqrt(hoursStaked / 720)
```

Where 720 hours = 30 days (full power).

| Time Staked | % of Max Power |
|-------------|----------------|
| 1 hour | 3.7% |
| 1 day | 18% |
| 1 week | 48% |
| 2 weeks | 68% |
| 30 days | 100% |

At full power: 1 staked CENTS = 1 stake power.

### Unstaking

- **Cooldown Period**: 7 days
- **Benefits During Cooldown**: None (benefits lost immediately upon initiating unstake)
- **Cancellation**: User can cancel unstake and retain position, but timer resets

---

## CENTS Utility: Fee Discounts

### The 1:1 Model

At full stake power:
```
1 staked CENTS = 1 DLRS of daily fee-free redemption capacity
```

Before full power, capacity scales with stake power:
```
dailyFeeFreeCap = stakePower
```

### Fee Calculation

For a redemption of `amount` DLRS:

```
if amount <= dailyFeeFreeCap:
    fee = 0
else:
    fee = (amount - dailyFeeFreeCap) * 0.0001  // 1bp on excess
```

Daily capacity resets at 00:00 UTC.

### Examples

**User A**: 1,000,000 CENTS staked for 30 days
- Stake power: 1,000,000
- Daily fee-free cap: 1,000,000 DLRS
- Redeem 500,000 DLRS → $0 fee
- Redeem 1,500,000 DLRS → fee on 500,000 = $50

**User B**: 1,000,000 CENTS staked for 7 days
- Stake power: 1,000,000 × sqrt(168/720) = 483,046
- Daily fee-free cap: 483,046 DLRS
- Redeem 500,000 DLRS → fee on 16,954 = $1.70

**User C**: 0 CENTS staked
- Stake power: 0
- Daily fee-free cap: 0
- Redeem 500,000 DLRS → fee = $50

### North Star

Platform processes $1B daily volume with 1B CENTS fully staked at full power = entire platform runs fee-free.

Reality: Not everyone stakes, not everyone reaches full power. Fee revenue always exists from:
- Users with no CENTS
- Users with insufficient stake power
- Users exceeding their daily cap

All fee revenue goes to the bank (protocol operator).

---

## CENTS Utility: Queue Priority

### Fill Score Formula

When deposits arrive to clear queue, positions are filled in order of fill score (highest first):

```
fillScore = (basePower + stakePower / sqrt(fillSize)) * secondsInQueue
```

**Parameters**:
- `basePower`: 1 (ensures zero-stake users can still get filled via FIFO)
- `stakePower`: User's current stake power
- `fillSize`: Size of the queued position in DLRS
- `secondsInQueue`: Time since joining queue

### Design Rationale

- **basePower = 1**: Zero-stake users aren't locked out, just slower
- **stakePower / sqrt(fillSize)**: Stake advantage is diluted for larger fills; whales can't steamroll with modest stake
- **× secondsInQueue**: Time always wins eventually; patience beats money

### Examples

| User | Stake Power | Fill Size | Hours in Queue | Fill Score |
|------|-------------|-----------|----------------|------------|
| Alice | 1,000,000 | 10,000,000 | 1 | 4,437,600 |
| Bob | 100,000 | 100,000 | 1 | 1,443,600 |
| Charlie | 10,000 | 10,000 | 1 | 363,600 |
| Dave | 0 | 10,000 | 24 | 86,400 |
| Eve | 0 | 10,000 | 168 | 604,800 |

- Alice has 100x Bob's stake but only ~3x the fill score (large fill dilutes advantage)
- Eve waited a week with zero stake and beats everyone except Alice
- Dave with zero stake for 1 day is behind, but not permanently stuck

### Queued DLRS Earns Rewards

DLRS in queue continues earning maker rewards (CENTS APY). Users are compensated for locking capital and providing market signal.

---

## State Variables

### CENTS Token

```
totalSupply: uint256
    Current minted supply (starts at 0, caps at 1B)

balanceOf: mapping(address → uint256)
    Standard ERC-20 balances

makerEmissionsRemaining: uint256
    Initialized to 600,000,000
    Decremented on maker rewards

takerEmissionsRemaining: uint256
    Initialized to 200,000,000
    Decremented on taker rewards

founderEmissionsReceived: uint256
    Tracks founder vesting (caps at 200,000,000)
```

### Staking

```
stakedBalance: mapping(address → uint256)
    CENTS currently staked per user

stakeTimestamp: mapping(address → uint256)
    When user's current stake began (for power calculation)

unstakeInitiated: mapping(address → uint256)
    Timestamp when unstake was initiated (0 if not unstaking)

dailyRedemptionUsed: mapping(address → uint256)
    Fee-free capacity used today

lastRedemptionDay: mapping(address → uint256)
    Day number of last redemption (for reset logic)
```

### Protocol

```
reserves: mapping(stablecoin → uint256)
    Stablecoins backing DLRS

bank: mapping(stablecoin → uint256)
    Accumulated fee revenue for operator
```

---

## Function Specifications

### stake()

**Signature**: `stake(uint256 amount)`

**Behavior**:
1. Transfer `amount` CENTS from caller to contract
2. If user has existing stake:
   - Calculate weighted average stake timestamp (preserves partial power)
   - `newTimestamp = (oldStake * oldTimestamp + amount * now) / (oldStake + amount)`
3. If new stake: `stakeTimestamp = now`
4. Increment `stakedBalance[caller]` by `amount`
5. Emit event

### unstake()

**Signature**: `unstake()`

**Behavior**:
1. Require `stakedBalance[caller] > 0`
2. Require `unstakeInitiated[caller] == 0` (not already unstaking)
3. Set `unstakeInitiated[caller] = now`
4. Benefits immediately suspended (stake power reads as 0)
5. Emit event

### completeUnstake()

**Signature**: `completeUnstake()`

**Behavior**:
1. Require `unstakeInitiated[caller] != 0`
2. Require `now >= unstakeInitiated[caller] + 7 days`
3. Transfer `stakedBalance[caller]` CENTS to caller
4. Reset `stakedBalance[caller] = 0`
5. Reset `stakeTimestamp[caller] = 0`
6. Reset `unstakeInitiated[caller] = 0`
7. Emit event

### cancelUnstake()

**Signature**: `cancelUnstake()`

**Behavior**:
1. Require `unstakeInitiated[caller] != 0`
2. Reset `unstakeInitiated[caller] = 0`
3. Reset `stakeTimestamp[caller] = now` (power timer restarts)
4. Emit event

### getStakePower()

**Signature**: `getStakePower(address user) → uint256`

**Behavior**:
```
if unstakeInitiated[user] != 0:
    return 0  // Unstaking, no power

staked = stakedBalance[user]
if staked == 0:
    return 0

hoursStaked = (now - stakeTimestamp[user]) / 3600
hoursStaked = min(hoursStaked, 720)  // Cap at 30 days

return staked * sqrt(hoursStaked) / sqrt(720)
```

### getDailyFeeFreeCap()

**Signature**: `getDailyFeeFreeCap(address user) → uint256`

**Behavior**:
```
stakePower = getStakePower(user)
today = now / 86400

if lastRedemptionDay[user] < today:
    return stakePower  // Fresh day, full cap

return max(0, stakePower - dailyRedemptionUsed[user])
```

### Modified: withdraw()

**Signature**: `withdraw(address stablecoin, uint256 dlrsAmount) → uint256 received`

**Behavior**:
1. Get `stakePower = getStakePower(caller)`
2. Get `today = now / 86400`
3. Reset daily tracking if new day:
   ```
   if lastRedemptionDay[caller] < today:
       dailyRedemptionUsed[caller] = 0
       lastRedemptionDay[caller] = today
   ```
4. Calculate fee-free portion:
   ```
   feeFreeCap = stakePower - dailyRedemptionUsed[caller]
   feeFreePortion = min(dlrsAmount, feeFreeCap)
   feePortion = dlrsAmount - feeFreePortion
   fee = feePortion * 0.0001
   ```
5. Update daily usage: `dailyRedemptionUsed[caller] += feeFreePortion`
6. Calculate net output: `netOutput = dlrsAmount - fee`
7. Standard withdrawal mechanics (burn DLRS, transfer stablecoin)
8. Fee to bank: `bank[stablecoin] += fee`
9. Emit event
10. Return `netOutput`

### Modified: deposit() — Taker Rewards

**Signature**: `deposit(address stablecoin, uint256 amount) → uint256 dlrsMinted`

**Behavior**:
1. Transfer stablecoin from caller
2. Check queue for this stablecoin
3. If queue exists:
   ```
   queueCleared = min(amount, queueDepth[stablecoin])
   feeGenerated = queueCleared * 0.0001
   centsReward = feeGenerated / getCentsPrice()
   mintCentsWithFounderShare(caller, centsReward, takerEmissionsRemaining)
   ```
4. Process queue fills (separate logic)
5. Remaining amount to reserves
6. Mint DLRS to caller
7. Emit event
8. Return dlrsMinted

### Queue Fill Processing

When deposit clears queue, fill by fill score order:

```
function processQueueFills(stablecoin, availableAmount):
    positions = getQueuePositions(stablecoin)
    
    for each position sorted by fillScore descending:
        fillAmount = min(position.amount, availableAmount)
        fee = fillAmount * 0.0001
        netAmount = fillAmount - fee
        
        transfer netAmount stablecoin to position.owner
        bank[stablecoin] += fee
        
        // Position owner already earned maker CENTS while queued
        // (accrued separately via claimMakerRewards)
        
        availableAmount -= fillAmount
        if availableAmount == 0: break
```

### claimMakerRewards()

**Signature**: `claimMakerRewards() → uint256 centsClaimed`

**Behavior**:
1. Calculate accrued rewards for caller's queue position(s):
   ```
   for each position owned by caller:
       dlrsHours = position.amount * hoursInQueue
       usdEarned = dlrsHours * 0.08 / 8760  // 8% APY
       centsEarned += usdEarned / getCentsPrice()
   ```
2. Update last claim timestamp
3. Mint CENTS with founder share
4. Emit event
5. Return centsClaimed

### getCentsPrice()

**Signature**: `getCentsPrice() → uint256`

**Behavior**:
```
if uniswapPoolLiquidity < 500_000 per side:
    return 0.01

twapPrice = getUniswapTWAP()
if twapPrice < 0.01:
    return 0.01

return twapPrice
```

### mintCentsWithFounderShare()

**Internal function for emission with founder vesting**

```
function mintCentsWithFounderShare(recipient, userAmount, emissionsPool):
    require emissionsPool >= userAmount
    
    // Calculate founder share (1:4 ratio)
    founderAmount = userAmount / 4
    founderAmount = min(founderAmount, 200_000_000 - founderEmissionsReceived)
    
    // Mint to user
    mint(recipient, userAmount)
    emissionsPool -= userAmount
    
    // Mint to founder
    if founderAmount > 0:
        mint(founderAddress, founderAmount)
        founderEmissionsReceived += founderAmount
```

---

## Events

```
CentsStaked(user, amount, newStakePower)
UnstakeInitiated(user, amount, completionTime)
UnstakeCompleted(user, amount)
UnstakeCancelled(user, amount)
MakerRewardsClaimed(user, centsAmount, dlrsHoursAccrued)
TakerRewardsEarned(user, centsAmount, queueCleared, feeGenerated)
FounderVestingMinted(amount, totalVested)
RedemptionWithDiscount(user, dlrsAmount, fee, feeFreePortion)
BankWithdrawal(stablecoin, to, amount)
```

---

## Queue Priority Implementation

### Data Structure

```
struct QueuePosition {
    address owner;
    uint256 amount;
    uint256 timestamp;
    uint256 lastRewardClaim;
}

mapping(address stablecoin => QueuePosition[]) public queues;
```

### Fill Score Calculation

```
function getFillScore(position, user) → uint256:
    stakePower = getStakePower(user)
    secondsInQueue = now - position.timestamp
    fillSize = position.amount
    
    stakeBoost = stakePower / sqrt(fillSize)
    return (1 + stakeBoost) * secondsInQueue
```

### Sorting

On each deposit that clears queue:
1. Calculate fill scores for all positions
2. Sort descending
3. Fill from top until deposit exhausted

For gas efficiency with large queues, consider off-chain sorting with on-chain verification, or chunked processing.

---

## Edge Cases

### Zero Stake Users

- Queue priority: `fillScore = 1 * secondsInQueue` (pure FIFO)
- Fee discount: None (pay full 1bp)
- Can still participate fully, just without benefits

### Emissions Exhausted

When `makerEmissionsRemaining` or `takerEmissionsRemaining` hits 0:
- No more CENTS rewards for that activity
- Fee mechanics continue unchanged
- Existing CENTS retain full utility

### Price Oracle Manipulation

Uniswap TWAP with $500k minimum liquidity makes manipulation expensive. Floor price of $0.01 provides downside protection against:
- Flash loan attacks
- Sustained price suppression

### Partial Queue Fills

Positions can be partially filled. Maker rewards accrue on the portion still queued. Fill score recalculates on remaining amount.

---

## Security Considerations

### Reentrancy

Apply reentrancy guards to:
- `withdraw()`
- `stake()`
- `completeUnstake()`
- `claimMakerRewards()`
- `deposit()` (if processing queue fills)

### Integer Overflow

Solidity 0.8+ with checked math. Use careful scaling for sqrt calculations.

### Access Control

- `withdrawBank()`: onlyOwner
- `setFounderAddress()`: onlyOwner (if changeable)
- All other functions: permissionless

---

## Testing Requirements

### Unit Tests

1. Stake power calculation at various durations
2. Fee discount calculation with partial capacity
3. Daily fee cap reset logic
4. Fill score calculation with various stake/size combinations
5. CENTS emission at various prices
6. Founder vesting ratio accuracy
7. Unstake cooldown enforcement

### Integration Tests

1. Full flow: deposit → queue → wait → fill → claim maker rewards
2. Taker deposits clearing multiple queue positions by fill score
3. Stake → redeem with discount → unstake after cooldown
4. Price oracle transition from floor to market

### Invariant Tests

1. `totalSupply <= 1,000,000,000`
2. `makerEmissions + takerEmissions + founderEmissions = totalSupply`
3. `founderEmissionsReceived <= 200,000,000`
4. `founderEmissionsReceived = (makerDistributed + takerDistributed) / 4`

---

## Summary

CENTS is a pure utility token that provides:

1. **Fee Discounts**: 1 staked CENTS (at full power) = 1 DLRS daily fee-free redemption
2. **Queue Priority**: Stake power boosts queue position, diluted by fill size

CENTS is earned by:

1. **Makers**: APY on queued DLRS (8%, USD-denominated, $0.01 floor)
2. **Takers**: 1:1 value match with fees generated when clearing queue

Tokenomics:
- 1B total supply (hard cap)
- 80% to users via maker/taker rewards
- 20% to founder (vested 1:4 with distribution)
- No pre-mint, minted as earned

This creates aligned incentives:
- Users earn CENTS by using the platform
- CENTS utility encourages continued usage
- Founder allocation vests with platform growth
- Fee revenue exists from non-stakers and excess redemptions
- Early believers accumulate cheap CENTS, benefit forever
