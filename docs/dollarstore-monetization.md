# Dollar Store Monetization Design

## Overview

This document specifies the monetization layer for Dollar Store. It introduces a 1 basis point (0.01%) redemption fee, with proceeds split between DLRS holders (via a reward system) and the protocol operator (via direct stablecoin collection).

This design maintains the core "everything is a dollar" philosophy while creating sustainable revenue.

---

## Core Concepts

### Fee Model

A fee of 1 basis point is charged on all redemptions (DLRS → stablecoin). This applies to:
- Direct withdrawals via `withdraw()`
- Queue settlements (when a queued position is filled)
- The withdrawal leg of the `swap()` convenience function

Deposits remain free. The fee is denominated in the output stablecoin.

### Fee Split

Collected fees are split 50/50:
- **Register**: 50% is used to mint DLRS immediately, held by the contract for distribution to holders
- **Bank**: 50% goes directly to the protocol operator as stablecoin

### The Register (Holder Rewards)

The register holds DLRS tokens (not stablecoins) that are distributed to holders as rewards. When fees are collected:

1. Half the fee (in stablecoin) goes into reserves
2. An equivalent amount of DLRS is minted immediately and held by the contract
3. Holders accrue claims on this DLRS proportional to their balance at time of each redemption
4. Holders claim rewards by calling `claimRewards()`, which transfers DLRS from the contract to them
5. Claimed DLRS is fully backed (the stablecoin went into reserves when it was minted) and redeemable like any other DLRS

### The Bank (Operator Revenue)

The bank is a simple accumulator of stablecoins belonging to the protocol operator. It is entirely separate from protocol reserves and does not back any DLRS. The operator can withdraw from the bank at any time.

### Stablecoin Fungibility

DLRS is a claim on ANY stablecoin in reserves - we never track which stablecoin backs which DLRS. A user holding 100 DLRS can redeem for 100 USDC or 100 USDT (subject to availability), regardless of what was originally deposited. This fungibility is fundamental to the design and must be preserved.

---

## Supported Stablecoins

- USDC (Circle)
- USDT (Tether)

DAI is not supported.

---

## State Variables

### Existing (from base design)

```
reserves: mapping(stablecoin → uint256)
    Stablecoins backing circulating DLRS from user deposits
```

### New

```
rewardPool: uint256
    DLRS tokens held by the contract for reward distribution
    These tokens are already minted and backed

bank: mapping(stablecoin → uint256)
    Operator's accumulated fee revenue
    Not part of protocol reserves, does not back any DLRS

rewardPerToken: uint256
    Accumulated rewards per DLRS, scaled by 1e18
    Increases with each redemption fee collected

userRewardDebt: mapping(address → uint256)
    Snapshot of rewardPerToken at user's last interaction
    Used to calculate pending rewards

escrowedBalance: mapping(address → uint256)
    DLRS locked in queue positions, tracked separately for reward calculations
    (Queue transfers DLRS to contract, but this tracks original owner for rewards)
```

---

## Constants

```
REDEMPTION_FEE_BPS = 1          // 1 basis point = 0.01%
BPS_DENOMINATOR = 10000
PRECISION = 1e18                 // For reward calculations
```

---

## Function Specifications

### Modified: withdraw()

**Signature**: `withdraw(address stablecoin, uint256 dlrsAmount) → uint256 received`

**Behavior**:

1. Calculate fee: `fee = dlrsAmount * REDEMPTION_FEE_BPS / BPS_DENOMINATOR`
2. Calculate net output: `netOutput = dlrsAmount - fee`
3. Verify `reserves[stablecoin] >= netOutput`
4. Burn `dlrsAmount` DLRS from caller
5. Decrease `reserves[stablecoin]` by `netOutput`
6. Transfer `netOutput` stablecoin to caller
7. Split fee:
   - `bankShare = fee / 2`
   - `registerShare = fee - bankShare` (avoids rounding loss)
8. Add `bankShare` to `bank[stablecoin]` (stablecoin stays in contract, tracked separately)
9. Mint `registerShare` DLRS to the contract itself (backed by stablecoin remaining in reserves)
10. Add `registerShare` to `rewardPool`
11. Update reward accumulator: `rewardPerToken += (registerShare * PRECISION) / effectiveSupply()`
    - `effectiveSupply()` = `dlrs.totalSupply() - rewardPool` (circulating supply, not including unclaimed rewards)
12. Emit event with fee breakdown
13. Return `netOutput`

**Note**: The burned DLRS does not earn rewards from its own fee (rewardPerToken is updated after burn).

### Modified: Queue Settlement (internal)

When a queued position is filled via deposit, the same fee logic applies. The queue stores the original DLRS amount, and upon settlement:

1. Calculate fee on the DLRS amount being settled
2. Transfer `netOutput` stablecoin to the queue position holder
3. Burn the DLRS that was escrowed
4. Split fee between bank and register as above

Partial fills apply the fee proportionally to the filled portion.

### New: claimRewards()

**Signature**: `claimRewards() → uint256 claimed`

**Behavior**:

1. Calculate pending: `pending = pendingRewards(msg.sender)`
2. Require `pending > 0`
3. Update `userRewardDebt[msg.sender] = rewardPerToken`
4. Decrease `rewardPool` by `pending`
5. Transfer `pending` DLRS from contract to caller
6. Emit event
7. Return `pending`

**Note**: This is a transfer, not a mint - the DLRS was minted when the fee was collected.

### New: pendingRewards()

**Signature**: `pendingRewards(address user) → uint256`

**Behavior**:

```
userBalance = dlrs.balanceOf(user) + escrowedBalance[user]
rewardDelta = rewardPerToken - userRewardDebt[user]
return (userBalance * rewardDelta) / PRECISION
```

**View function** - does not modify state.

The `escrowedBalance` is added to ensure users with DLRS locked in the queue continue earning rewards.

### New: withdrawBank()

**Signature**: `withdrawBank(address stablecoin, address to) → uint256 amount`

**Access**: `onlyOwner`

**Behavior**:

1. Get `amount = bank[stablecoin]`
2. Set `bank[stablecoin] = 0`
3. Transfer `amount` stablecoin to `to`
4. Emit event
5. Return `amount`

### New: getRewardPool()

**Signature**: `getRewardPool() → uint256`

**View function** returning the amount of DLRS held for reward distribution.

### New: getBankBalance()

**Signature**: `getBankBalance() → (address[] stablecoins, uint256[] amounts)`

**View function** returning the composition of the bank.

---

## Reward Accounting Deep Dive

### The Problem

When DLRS holders earn rewards, the rewards must be backed by real stablecoins to maintain the 1:1 redemption guarantee. We cannot simply mint unbacked DLRS.

### The Solution

Rewards are minted immediately when fees are collected:

1. When a fee is collected, half goes to the bank (operator revenue)
2. The other half stays in reserves as backing for newly minted reward DLRS
3. Reward DLRS is minted to the contract and added to `rewardPool`
4. The `rewardPerToken` accumulator tracks how much each holder can claim
5. When users claim, DLRS is transferred from `rewardPool` to them
6. The claimed DLRS is indistinguishable from regular DLRS - fully backed and redeemable

### Worked Example

**State**: 1,000,000 DLRS circulating, rewardPool = 0, rewardPerToken = 0

**Action**: Alice redeems 100,000 DLRS for USDC

1. Fee = 100,000 * 0.0001 = 10 DLRS worth = 10 USDC
2. Alice receives 99,990 USDC (reserves decrease by 99,990)
3. Bank gets 5 USDC (tracked separately, stays in contract)
4. 5 DLRS minted to contract, added to rewardPool (backed by 5 USDC staying in reserves)
5. DLRS circulating supply is now 900,005 (100,000 burned, 5 minted to contract)
6. Effective supply for rewards = 900,005 - 5 = 900,000
7. rewardPerToken += 5e18 / 900,000 ≈ 5.555...e12

**State**: 900,005 DLRS total (900,000 circulating + 5 in rewardPool), rewardPerToken = 5.555...e12

**Action**: Bob holds 90,000 DLRS and claims rewards

1. Bob's pending = 90,000 * 5.555...e12 / 1e18 = 0.5 DLRS
2. 0.5 DLRS transferred from contract to Bob
3. rewardPool decreases by 0.5
4. Bob's userRewardDebt = current rewardPerToken

**State**: 900,005 DLRS total (900,000.5 circulating + 4.5 in rewardPool)

Bob can now redeem his 90,000.5 DLRS for stablecoins (minus fee).

### Invariants

1. `rewardPool` = total unclaimed rewards (in DLRS held by contract)
2. `sum(reserves[*])` = total DLRS supply (all DLRS is always fully backed)
3. Bank is completely separate - not part of backing calculations

---

## Edge Cases

### Transfer Handling

No special handling required on DLRS transfers.

The natural concern is front-running: someone buys DLRS right before a large redemption to capture a share of the fee, then exits. But the redemption fee itself is the protection:

1. Alice front-runs Bob's 1M DLRS redemption by depositing 500k USDC
2. Bob's tx executes, ~100 DLRS in fees accrue
3. Alice captures ~33 DLRS worth of rewards
4. Alice redeems to exit, pays 1bp on 500k = 50 DLRS in fees
5. Net result: Alice loses ~17 DLRS

The only way to extract value is to redeem, and redemption costs 1bp. You cannot profitably front-run.

If Alice instead sells DLRS on secondary market, she's selling to someone who will eventually redeem and pay the fee. The terminal extraction point is always redemption.

Therefore: standard ERC-20 transfers with no checkpoint overhead.

### Zero Supply

If effective supply ever reaches zero, `rewardPerToken` division would fail. Handle by checking for zero supply before division. This edge case means the protocol is essentially empty.

### Rounding

All division rounds down (Solidity default). Dust may accumulate in rewardPool over time. This is acceptable - it's always in favor of the protocol.

### Claim Gas Costs

Small holders may have rewards worth less than the gas to claim. No minimum threshold is enforced - let users decide when claiming is worth the gas. Small holders can accumulate and claim less frequently.

---

## Integration with Queue

When queue positions are filled:

1. The fill amount determines the fee
2. Fee split works identically to direct withdrawal
3. Partial fills apply fee to filled portion only
4. The queued user receives `filledAmount - fee` stablecoin
5. rewardPerToken updates, rewarding current holders

### Escrowed DLRS Earns Rewards

DLRS locked in the queue continues earning rewards. Rationale:

- Users are committing capital and signaling demand
- Queue participation provides valuable market information
- Locking capital is a service to the protocol - it should be compensated
- Users shouldn't be penalized for using the queue vs holding and waiting

**Implementation**: When DLRS is transferred to the contract for queue escrow, the original owner's balance is tracked in `escrowedBalance[user]`. This is added to their `balanceOf` when calculating pending rewards.

When the position is filled or cancelled:
- **Filled**: escrowed DLRS is burned, user receives stablecoin, `escrowedBalance` is cleared
- **Cancelled**: escrowed DLRS is returned to user, `escrowedBalance` is cleared

No special reward handling needed at fill/cancel - the user has been accruing the whole time via `escrowedBalance`.

---

## Events

```
RewardsAccrued(uint256 feeAmount, uint256 rewardMinted, uint256 bankAmount, uint256 newRewardPerToken)
RewardsClaimed(address indexed user, uint256 dlrsAmount)
BankWithdrawal(address indexed stablecoin, address indexed to, uint256 amount)
```

---

## View Functions Summary

| Function | Returns |
|----------|---------|
| `pendingRewards(user)` | uint256 - claimable DLRS |
| `getRewardPool()` | uint256 - DLRS held for distribution |
| `getBankBalance()` | arrays - stablecoin addresses and amounts |
| `rewardPerToken()` | uint256 - current accumulator value |
| `userRewardDebt(user)` | uint256 - user's last checkpoint |
| `escrowedBalance(user)` | uint256 - user's DLRS locked in queue |

---

## Security Considerations

### Reentrancy

Apply reentrancy guards to:
- `withdraw()`
- `claimRewards()`
- `withdrawBank()`

Use checks-effects-interactions pattern: update state before external calls.

### Access Control

- `withdrawBank()`: onlyOwner
- All other functions: permissionless

### Overflow

With 1e18 precision and reasonable supply limits (< 1e30), overflow is not a concern in Solidity 0.8+.

### Front-running

Not a concern. Any attempt to front-run redemptions to capture fees requires eventually redeeming to extract value, which costs 1bp - more than can be captured. The redemption fee is self-protecting.

---

## Gas Optimization Notes

- No transfer hooks needed - DLRS is a vanilla ERC-20 with standard gas costs
- Reward calculation is O(1) - no iteration required
- Pack storage where possible (e.g., if owner is stored, pack with a flag)
- `escrowedBalance` adds one storage read per reward calculation, but only for users with queue positions

---

## Testing Requirements

### Unit Tests

1. Fee calculation accuracy at various amounts
2. Correct split between bank and rewardPool
3. Reward accrual math across multiple redemptions
4. Claim transfers correct amount
5. Transfers do not affect reward accounting
6. Zero balance edge cases
7. Zero supply edge cases
8. escrowedBalance correctly included in reward calculations

### Integration Tests

1. Full flow: deposit → redeem → claim → redeem claimed DLRS
2. Queue settlement with fees
3. Multiple users with interleaved actions
4. Partial queue fills with fees
5. Escrowed DLRS earns rewards while queued
6. Queue cancel returns DLRS with accumulated rewards intact

### Invariant Tests (Fuzz)

1. `totalSupply = sum(reserves[*])` (all DLRS is backed)
2. Bank never affects backing calculations
3. No user can claim more than their fair share
4. Front-running redemptions is unprofitable
5. `rewardPool` always equals sum of unclaimed rewards

---

## Migration Notes

If deploying as upgrade to existing Dollar Store:

1. Initialize `rewardPerToken = 0`
2. Initialize `rewardPool = 0`
3. All existing users start with `userRewardDebt = 0`
4. First redemption after upgrade starts accruing rewards
5. No migration of existing balances needed

If deploying fresh:

1. All state initializes to zero
2. No special handling needed

---

## Summary

This design adds sustainable monetization to Dollar Store while preserving the core simplicity:

- 1bp fee on redemptions only
- 50% to DLRS holders as immediately-minted, claimable DLRS rewards
- 50% to operator as raw stablecoin
- Rewards are fully backed and redeemable
- No governance token, no inflation, no complexity
- No special transfer handling - redemption fee is self-protecting
- Queued DLRS continues earning rewards via `escrowedBalance` tracking
- DLRS remains fungible - never tracked by backing stablecoin

The rewardPool/bank split cleanly separates "holder rewards" from "operator revenue" while maintaining the 1:1 backing guarantee.
