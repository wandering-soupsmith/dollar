# Monetization Implementation Plan

## Overview

This plan covers implementing the monetization layer as specified in `dollarstore-monetization.md`. The work is scoped to smart contract changes only - frontend updates will follow separately.

---

## Phase 1: Contract State & Storage

Add new state variables to DollarStore.sol:

```solidity
uint256 public rewardPool;
mapping(address => uint256) public bank;
uint256 public rewardPerToken;
mapping(address => uint256) public userRewardDebt;
mapping(address => uint256) public escrowedBalance;
```

Add constants:

```solidity
uint256 public constant REDEMPTION_FEE_BPS = 1;
uint256 public constant BPS_DENOMINATOR = 10000;
uint256 public constant PRECISION = 1e18;
```

---

## Phase 2: Core Fee Logic

### 2.1 Internal helper: `_collectFee()`

Create internal function to handle fee collection and reward distribution:

```solidity
function _collectFee(uint256 dlrsAmount, address stablecoin) internal returns (uint256 netOutput)
```

- Calculate fee (`dlrsAmount * 1 / 10000`)
- Calculate `netOutput = dlrsAmount - fee`
- Split fee: `bankShare = fee / 2`, `registerShare = fee - bankShare`
- Add `bankShare` to `bank[stablecoin]`
- Mint `registerShare` DLRS to contract, add to `rewardPool`
- Update `rewardPerToken` using effective supply
- Emit `RewardsAccrued` event
- Return `netOutput`

### 2.2 Modify `withdraw()`

Update existing withdraw to use fee logic:

1. Call `_collectFee()` to get net output
2. Burn full `dlrsAmount` from user
3. Decrease reserves by `netOutput` (not full amount)
4. Transfer `netOutput` stablecoin to user

### 2.3 Modify `_settleQueue()` (internal)

Apply same fee logic when queue positions are filled:

1. Calculate fee on filled amount
2. Use `_collectFee()` pattern
3. Clear `escrowedBalance` for user

---

## Phase 3: Queue Escrow Tracking

### 3.1 Modify `joinQueue()`

When user joins queue:
- Transfer DLRS to contract (existing behavior)
- Add amount to `escrowedBalance[user]`

### 3.2 Modify `cancelQueue()`

When user cancels:
- Return DLRS to user (existing behavior)
- Clear `escrowedBalance[user]`

### 3.3 Modify queue settlement

When position is filled:
- Clear `escrowedBalance[user]`
- Burn escrowed DLRS
- Apply fee, send net stablecoin to user

---

## Phase 4: Reward Claiming

### 4.1 `pendingRewards(address user)`

View function:

```solidity
function pendingRewards(address user) public view returns (uint256) {
    uint256 balance = dlrs.balanceOf(user) + escrowedBalance[user];
    uint256 delta = rewardPerToken - userRewardDebt[user];
    return (balance * delta) / PRECISION;
}
```

### 4.2 `claimRewards()`

```solidity
function claimRewards() external nonReentrant returns (uint256 claimed) {
    claimed = pendingRewards(msg.sender);
    require(claimed > 0, "Nothing to claim");

    userRewardDebt[msg.sender] = rewardPerToken;
    rewardPool -= claimed;
    dlrs.transfer(msg.sender, claimed);

    emit RewardsClaimed(msg.sender, claimed);
}
```

---

## Phase 5: Bank Withdrawal

### 5.1 `withdrawBank()`

```solidity
function withdrawBank(address stablecoin, address to) external onlyOwner returns (uint256 amount) {
    amount = bank[stablecoin];
    require(amount > 0, "Nothing to withdraw");

    bank[stablecoin] = 0;
    IERC20(stablecoin).transfer(to, amount);

    emit BankWithdrawal(stablecoin, to, amount);
}
```

---

## Phase 6: View Functions

Add:
- `getRewardPool()` - returns `rewardPool`
- `getBankBalance()` - returns arrays of stablecoins and amounts
- `effectiveSupply()` - returns `dlrs.totalSupply() - rewardPool`

---

## Phase 7: Events

Add events:

```solidity
event RewardsAccrued(uint256 feeAmount, uint256 rewardMinted, uint256 bankAmount, uint256 newRewardPerToken);
event RewardsClaimed(address indexed user, uint256 dlrsAmount);
event BankWithdrawal(address indexed stablecoin, address indexed to, uint256 amount);
```

---

## Phase 8: Testing

### Unit Tests

1. Fee calculation at various amounts (including dust)
2. Correct 50/50 split between bank and rewardPool
3. `rewardPerToken` updates correctly after each withdrawal
4. `pendingRewards` returns correct amounts
5. `claimRewards` transfers correct DLRS
6. `escrowedBalance` included in reward calculations
7. Zero supply edge case handling
8. Bank withdrawal works correctly

### Integration Tests

1. Full flow: deposit → withdraw → claim → withdraw claimed DLRS
2. Multiple users with interleaved withdrawals and claims
3. Queue join → earn rewards while queued → position filled → verify rewards
4. Queue cancel returns DLRS, rewards intact
5. Partial queue fills with correct fee application

### Invariant Tests

1. `totalSupply == sum(reserves) + sum(bank)` (bank holds fee stablecoins)
2. `rewardPool == sum of all unclaimed rewards`
3. No user can claim more than their share
4. Bank balance only increases, never decreases (except via withdrawBank)

---

## Deployment

### Fresh Deploy

1. Deploy updated DollarStore with monetization
2. All state initializes to zero
3. Ready to use

### Upgrade Path (if applicable)

1. Deploy new implementation
2. Initialize `rewardPool = 0`, `rewardPerToken = 0`
3. Existing users have `userRewardDebt = 0`
4. First withdrawal after upgrade starts accruing rewards

---

## File Changes Summary

| File | Changes |
|------|---------|
| `DollarStore.sol` | Add state, constants, fee logic, modify withdraw/queue, add claim/bank functions |
| `DollarStore.t.sol` | Add comprehensive test suite for monetization |
| `DLRS.sol` | No changes needed |

---

## Estimated Scope

- ~150-200 lines of new Solidity code
- ~300-400 lines of tests
- No external dependencies added
