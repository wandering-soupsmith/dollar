# Dollar Store

**dollarstore.space**

*Everything is a dollar.*

---

## Overview

Dollar Store is a minimalist stablecoin aggregator and swap facility. Users deposit any supported stablecoin and receive a fungible receipt token ($DLRS) representing a 1:1 claim on the pool. Users can redeem $DLRS for any available stablecoin in the reserves.

The protocol has no fees, no yield mechanics, no governance token, and no complex risk management. It is a simple, transparent primitive that lets sophisticated users manage their own risk.

---

## Core Mechanics

### Deposit
- User deposits any supported stablecoin (e.g., USDC, USDT)
- User receives $DLRS at 1:1 ratio
- Deposited stablecoin enters the shared reserve pool
- What you deposited is irrelevant after minting—$DLRS is fully fungible

### Withdraw
- User burns $DLRS
- User receives any available stablecoin of their choice at 1:1 ratio
- If requested stablecoin has insufficient reserves, user can withdraw a different stablecoin or enter the swap queue

### The $DLRS Token
- ERC-20 receipt token
- Fully fungible claim on the reserve pool
- Effectively a basket stablecoin / meta-stablecoin
- Freely transferable, composable with other DeFi protocols

---

## Swap Queue

The swap queue enables users to declare intent for a specific stablecoin that is currently unavailable or in short supply. It functions as a 1:1 swap market where the only variable is time, not price.

### How It Works
1. Alice holds $DLRS and wants USDT, but reserves are empty
2. Alice locks her $DLRS in escrow and joins the USDT queue
3. When Bob deposits USDT, Alice's position is filled FIFO
4. Alice receives USDT, her $DLRS is burned
5. Partial fills are supported—Alice's 150k request can fill across multiple deposits

### Queue Rules
- **Locked tokens**: $DLRS must be locked/escrowed to hold a queue position
- **FIFO ordering**: First in, first out
- **Cancel anytime**: User can exit the queue and reclaim their $DLRS (unlocked, still redeemable for other stablecoins)
- **No price**: All swaps are 1:1, the queue only determines sequencing

### What the Queue Provides
- **Intent signal**: Public, on-chain visibility into demand for each stablecoin
- **Gasless limit orders**: "I want this, wake me up when it's done"
- **Natural matching**: Depositors may be attracted to deposit scarce stablecoins when they see queue depth

---

## Transparency

All state is publicly visible on-chain:

### Reserve View
```
getReserves() → mapping(address => uint256)
```
Returns current reserves for each supported stablecoin.

Example output:
- USDC: 2,400,000
- USDT: 1,100,000

### Queue Depth View
```
getQueueDepth(address stablecoin) → uint256
```
Returns total $DLRS locked waiting for a specific stablecoin.

Example output:
- USDT queue: 150,000
- USDC queue: 0

---

## Risk Model

Dollar Store explicitly does not manage risk at the protocol level. Users accept the following:

### Basket Risk
$DLRS is a claim on a variable basket. Composition shifts based on deposits and withdrawals. The "weakest" stablecoin may concentrate in reserves due to arbitrage.

### Depeg Risk
If one supported stablecoin depegs, rational actors will deposit the depegged asset and withdraw sound assets, potentially draining reserves of everything except the depegged stablecoin.

### No Mitigations By Design
- No composition caps
- No withdrawal fees
- No oracle-based redemption ratios
- No circuit breakers

Users who hold $DLRS understand they are exposed to basket composition risk. This is a "fair weather" product that works well in normal conditions. Sophisticated users can monitor reserves and act accordingly.

---

## Supported Stablecoins

### Initial Whitelist
- USDC (Circle)
- USDT (Tether)

### Whitelist Governance
- Immutable after launch? Or minimal governance for additions?
- Criteria: Only established, high-liquidity USD stablecoins
- No algorithmic stablecoins

---

## Chain Support

### V1: Ethereum Mainnet

Everything lives on Ethereum mainnet for launch:
- $DLRS token
- All reserves
- Swap queue

**Rationale:**
- Deepest stablecoin liquidity
- Single deployment, minimal complexity
- Target users are doing 6-figure swaps—gas costs are noise
- Proves the concept before adding cross-chain complexity

### Future: Cross-Chain Expansion

The ideal end state treats "chain" as just another dimension in the matching engine:
- Deposit USDC on Arbitrum
- Request USDT on Base
- System matches with counterparty going the other direction

This requires:
- Multi-chain reserve accounting
- Cross-chain messaging for settlement
- Relayers or keepers per chain
- Significant additional complexity and bridge risk

**Decision**: Cross-chain is explicitly out of scope for v1. Revisit if there's demand.

### Third-Party Bridge Integration

Nothing stops others from building bridge wrappers around Dollar Store:
- User deposits USDC on Arbitrum to a third-party service
- Service bridges to mainnet, deposits into Dollar Store
- Service bridges $DLRS (or redeemed stablecoin) back to user's chain

This lets the market solve cross-chain UX without adding complexity to the core protocol.

---

## UX Design

### Design Direction

Clean, modern, institutional feel. Reference: m0.org, ondo.finance. Minimalist, no flashy DeFi aesthetics. The UI should communicate "simple, trustworthy infrastructure."

### Site Structure

**Two pages:**

1. **Home (/)** — The $DLRS page
2. **Swaps (/swap)** — The swap market

---

### Home Page (/)

The landing page is about $DLRS as an asset and the protocol itself.

**Content:**
- Hero: "Everything is a dollar" + brief one-liner about what Dollar Store is
- Live reserve composition display (USDC: X, USDT: Y)
- Total $DLRS supply
- Links: Whitepaper, GitHub repo, contract addresses, documentation
- Simple explainer: how deposits and redemptions work

**Wallet Actions:**
- Connect wallet
- Deposit: select stablecoin → input amount → receive $DLRS
- Redeem: input $DLRS amount → select available stablecoin → receive stablecoin

This page is for users who want $DLRS as a basket stablecoin or need to do simple in/out operations.

---

### Swaps Page (/swap)

The swap market interface. For users who want to exchange one stablecoin for another.

**Display:**
- Aggregate queue depth per stablecoin ("150K waiting for USDT, 0 waiting for USDC")
- Current reserve levels
- User's active queue positions (if any)

**Swap Flow:**

User selects:
- **From**: Stablecoin they have (USDC, USDT) OR $DLRS
- **To**: Stablecoin they want
- **Amount**

**Execution logic:**
- If user deposits a stablecoin (not $DLRS), mint $DLRS first behind the scenes
- If requested stablecoin has sufficient reserves → instant swap, done
- If insufficient reserves → $DLRS goes into escrow, user joins queue
- User sees clear UI indicating: "Instant" vs "Queued (position #X, ~Y ahead of you)"

**The key UX insight:** Users don't need to understand $DLRS mechanics to use the swap page. They just say "I have USDC, I want USDT" and the system handles whether that's instant or queued.

**Queue Management:**
- View active queue positions
- Cancel position → get $DLRS back (can then redeem or re-queue)
- See partial fill progress

---

### Convenience Function

To support the seamless swap UX, the contract should have a one-tx swap function:

```solidity
function swap(
    address fromStablecoin,
    address toStablecoin,
    uint256 amount,
    bool queueIfUnavailable
) external returns (uint256 received, uint256 queued);
```

- If `toStablecoin` has enough reserves: instant swap, `received = amount`, `queued = 0`
- If insufficient and `queueIfUnavailable = true`: partial fill + queue remainder
- If insufficient and `queueIfUnavailable = false`: revert or partial fill only

---

### UI Components

**Reserve Display:**
```
┌─────────────────────────────────┐
│  Reserves                       │
│  ─────────────────────────────  │
│  USDC    ████████████░░  2.4M   │
│  USDT    █████░░░░░░░░░  1.1M   │
└─────────────────────────────────┘
```

**Queue Display:**
```
┌─────────────────────────────────┐
│  Swap Demand                    │
│  ─────────────────────────────  │
│  USDT    150K waiting           │
│  USDC    —                      │
└─────────────────────────────────┘
```

---

### Mobile

Responsive design, works on mobile. Same two-page structure. Wallet connect via WalletConnect / mobile wallet browsers.

---

## Contract Interface (Draft)

```solidity
interface IDollarStore {
    // Core functions
    function deposit(address stablecoin, uint256 amount) external returns (uint256 dlrsMinted);
    function withdraw(address stablecoin, uint256 amount) external returns (uint256 stablecoinReceived);
    
    // Swap convenience function (deposit + withdraw/queue in one tx)
    function swap(
        address fromStablecoin,
        address toStablecoin,
        uint256 amount,
        bool queueIfUnavailable
    ) external returns (uint256 received, uint256 queued);
    
    // Queue functions
    function joinQueue(address wantedStablecoin, uint256 dlrsAmount) external returns (uint256 positionId);
    function cancelQueue(uint256 positionId) external returns (uint256 dlrsReturned);
    
    // View functions
    function getReserves() external view returns (address[] memory stablecoins, uint256[] memory amounts);
    function getQueueDepth(address stablecoin) external view returns (uint256);
    function getQueuePosition(uint256 positionId) external view returns (address depositor, address wanted, uint256 amount, uint256 timestamp);
    function getUserQueuePositions(address user) external view returns (uint256[] memory positionIds);
    
    // Admin (minimal)
    function supportedStablecoins() external view returns (address[] memory);
}
```

---

## Open Questions

1. **Whitelist governance**: Immutable whitelist or upgradeable? Who decides on new stablecoin additions?

2. **Queue settlement trigger**: Automatic on deposit, or keeper-based, or user-initiated?

3. **Frontend hosting**: Decentralized (IPFS) or traditional? ENS integration (dollarstore.eth)?

4. **Revenue model**: None? Or minimal fee for sustainability? (Current design: no fees)

5. **Contract upgradeability**: Immutable or upgradeable proxy? Tradeoff between trust minimization and bug fixes.

6. **$DLRS token name**: "Dollar Store Token"? Ticker $DLRS? Or something else?

---

## Summary

Dollar Store is a zero-fee, zero-complexity stablecoin swap facility. Deposit any dollar, get $DLRS. Redeem $DLRS for any dollar. Queue up if what you want isn't available. Cancel anytime. Everything is transparent. Everything is a dollar.
