# Dollar Store Implementation Plan

This document is a guide for implementing Dollar Store. Use this alongside `dollarstore-design.md` which contains the full product specification.

---

## Project Overview

**What we're building:** A minimalist stablecoin aggregator and 1:1 swap facility on Ethereum mainnet.

**Core components:**
1. Solidity smart contracts (DollarStore.sol, DLRS token)
2. Frontend website (dollarstore.space)

**Design philosophy:** Extreme simplicity. No fees, no yield, no governance token, no complex risk management. The protocol is a transparent primitive—users manage their own risk.

---

## Tech Stack

### Contracts
- Solidity 0.8.x
- Foundry for development, testing, deployment
- OpenZeppelin for ERC-20 base and security primitives

### Frontend
- Next.js or similar React framework
- Tailwind CSS
- wagmi + viem for wallet connection and contract interaction
- Clean, minimal design (reference: m0.org, ondo.finance)

---

## Phase 1: Smart Contract Foundation

### Goal
Get the core contract working: deposit, withdraw, and the $DLRS token.

### Context
- $DLRS is an ERC-20 receipt token minted 1:1 on deposit of any supported stablecoin
- Withdrawals burn $DLRS and return any available stablecoin the user chooses
- No queue logic yet—just the basic pool mechanics

### Tasks

**1.1 Project Setup**
- Initialize Foundry project
- Set up directory structure (src/, test/, script/)
- Add OpenZeppelin as dependency
- Configure foundry.toml for mainnet fork testing

**1.2 DLRS Token**
- ERC-20 token contract
- Only the DollarStore contract can mint/burn
- Standard metadata: name "Dollar Store Token", symbol "DLRS", 18 decimals
- Consider whether to make it a separate contract or embed in main contract (separate is cleaner)

**1.3 DollarStore Core Contract**
- State: mapping of supported stablecoins, reserves per stablecoin
- `deposit(address stablecoin, uint256 amount)` → transfers stablecoin in, mints DLRS
- `withdraw(address stablecoin, uint256 amount)` → burns DLRS, transfers stablecoin out (reverts if insufficient reserves)
- View functions: `getReserves()`, `supportedStablecoins()`
- Admin: whitelist management (keep minimal—maybe just constructor-set and immutable for v1)

**1.4 Testing**
- Unit tests for deposit/withdraw
- Fork tests using real USDC/USDT on mainnet fork
- Edge cases: withdraw more than reserves, unsupported stablecoin, zero amounts

### Acceptance Criteria
- Can deposit USDC or USDT and receive equivalent DLRS
- Can burn DLRS and withdraw any stablecoin that has sufficient reserves
- All view functions return accurate state
- Comprehensive test coverage

---

## Phase 2: Swap Queue

### Goal
Add the queue system that lets users wait for a specific stablecoin.

### Context
- Users lock DLRS to join a queue for a specific stablecoin
- When new deposits arrive in that stablecoin, queued positions fill FIFO
- Users can cancel anytime and get their DLRS back (unlocked)
- The queue is a "1:1 swap market where the only variable is time, not price"

### Tasks

**2.1 Queue Data Structures**
- Decide on queue implementation: linked list, array with pointer, or mapping-based
- Queue entry struct: depositor, wanted stablecoin, amount, timestamp, position ID
- Need efficient FIFO operations: enqueue, dequeue, cancel by position ID
- Consider gas costs for queue operations at scale

**2.2 Queue Functions**
- `joinQueue(address wantedStablecoin, uint256 dlrsAmount)` → lock DLRS, add to queue, return position ID
- `cancelQueue(uint256 positionId)` → remove from queue, unlock DLRS back to user
- Internal `_processQueue(address stablecoin, uint256 availableAmount)` → fill positions FIFO

**2.3 Queue Settlement Logic**
- When a deposit comes in, check if there's a queue for that stablecoin
- If yes, auto-fill queued positions before adding to free reserves
- Support partial fills (a 150k position can fill across multiple deposits)
- Emit events for fills so users can track without polling

**2.4 Queue View Functions**
- `getQueueDepth(address stablecoin)` → total DLRS waiting for this stablecoin
- `getQueuePosition(uint256 positionId)` → details of a specific position
- `getUserQueuePositions(address user)` → all positions for a user

**2.5 Testing**
- FIFO ordering is correct
- Partial fills work correctly
- Cancel returns correct amount
- Settlement triggers correctly on deposit
- Multiple users, multiple stablecoins, interleaved operations

### Acceptance Criteria
- Users can join queue and see their position
- Deposits auto-settle queued positions in correct order
- Partial fills work
- Cancel works at any time
- Queue depth view is accurate

---

## Phase 3: Swap Convenience Function

### Goal
Add the one-transaction swap function for seamless UX.

### Context
- Users on the swap page just want "USDC → USDT"
- They shouldn't need to understand DLRS mechanics
- One function that handles: deposit → instant withdraw OR deposit → queue

### Tasks

**3.1 Swap Function**
```
swap(address fromStablecoin, address toStablecoin, uint256 amount, bool queueIfUnavailable)
→ returns (uint256 received, uint256 queued)
```
- If `toStablecoin` has enough reserves: instant swap in one tx
- If not enough and `queueIfUnavailable = true`: partial fill + queue the rest
- If not enough and `queueIfUnavailable = false`: either revert or partial fill only (decide which is better UX)

**3.2 Also Support DLRS Input**
- Users who already hold DLRS should be able to swap directly
- Might need overloaded function or flag to indicate "I'm swapping from DLRS, not a stablecoin"

**3.3 Testing**
- Instant swap when reserves available
- Partial fill + queue when reserves insufficient
- Behavior when queueIfUnavailable = false
- DLRS-to-stablecoin swap path

### Acceptance Criteria
- One-tx swap works for instant case
- Queue fallback works correctly
- Works for both stablecoin input and DLRS input

---

## Phase 4: Security & Gas Optimization

### Goal
Harden the contracts before deployment.

### Context
- This contract will hold potentially millions in stablecoins
- Gas efficiency matters for queue operations at scale
- Reentrancy, access control, and integer overflow are primary concerns

### Tasks

**4.1 Security Review**
- Add reentrancy guards (OpenZeppelin ReentrancyGuard)
- Review all external calls (transfer before state change? CEI pattern)
- Check for integer overflow (Solidity 0.8+ helps but verify)
- Review access control on admin functions
- Consider pause functionality for emergencies

**4.2 Gas Optimization**
- Profile gas costs for deposit, withdraw, queue operations
- Optimize storage layout (pack structs, minimize SLOADs)
- Consider if queue can be made more gas-efficient
- Benchmark with realistic queue sizes (100s of entries)

**4.3 Events**
- Comprehensive events for all state changes
- Needed for frontend to track without excessive RPC calls
- Deposit, Withdraw, QueueJoined, QueueCancelled, QueueFilled (with partial fill info)

**4.4 Natspec & Documentation**
- Full Natspec comments on all public functions
- Document any assumptions or edge cases

### Acceptance Criteria
- No known security vulnerabilities
- Gas costs are reasonable for target use case (6-figure swaps)
- All state changes emit events
- Code is well-documented

---

## Phase 5: Frontend - Core Structure

### Goal
Get the basic site structure up with wallet connection.

### Context
- Two pages: Home (/) and Swaps (/swap)
- Clean, institutional design aesthetic (m0.org, ondo.finance reference)
- Wallet connection for all interactions

### Tasks

**5.1 Project Setup**
- Initialize Next.js project (or preferred React framework)
- Tailwind CSS configuration
- wagmi + viem setup for Ethereum interaction
- Configure for mainnet (with testnet option for development)

**5.2 Layout & Navigation**
- Header with logo, nav links (Home, Swap), Connect Wallet button
- Footer with links (Docs, GitHub, Contract)
- Responsive design that works on mobile

**5.3 Wallet Connection**
- WalletConnect, MetaMask, Coinbase Wallet support
- Show connected address, network indicator
- Handle wrong network gracefully

**5.4 Design System**
- Establish color palette, typography, spacing
- Component library: buttons, inputs, cards, modals
- Keep it minimal—this isn't a complex UI

### Acceptance Criteria
- Site loads with proper routing
- Wallet connects successfully
- Responsive on mobile
- Design feels clean and professional

---

## Phase 6: Frontend - Home Page

### Goal
Build the home page with $DLRS info, reserves display, and deposit/redeem.

### Context
- This page is about $DLRS as an asset
- Shows live reserve composition
- Allows deposit (stablecoin → DLRS) and redeem (DLRS → stablecoin)

### Tasks

**6.1 Hero Section**
- "Everything is a dollar" tagline
- Brief one-liner explaining Dollar Store
- Links to whitepaper, GitHub, contract address

**6.2 Reserve Display**
- Live data from contract: `getReserves()`
- Visual display (progress bars or similar) showing composition
- Total $DLRS supply
- Auto-refresh or manual refresh button

**6.3 Deposit Flow**
- Select stablecoin (USDC, USDT)
- Input amount
- Approve token (if needed) → Deposit transaction
- Show resulting DLRS received

**6.4 Redeem Flow**
- Input DLRS amount
- Select which stablecoin to receive (show available amounts)
- Transaction to withdraw
- Handle case where requested amount exceeds reserves

**6.5 Transaction States**
- Loading states during transactions
- Success/error feedback
- Link to Etherscan for completed transactions

### Acceptance Criteria
- Reserve display shows accurate live data
- Deposit flow works end-to-end
- Redeem flow works end-to-end
- Good UX feedback for all transaction states

---

## Phase 7: Frontend - Swap Page

### Goal
Build the swap interface with queue visibility and management.

### Context
- This page is for users who want to swap stablecoins
- Abstracts away DLRS mechanics—user just says "I have X, I want Y"
- Shows queue depth and handles instant vs queued swaps

### Tasks

**7.1 Queue/Demand Display**
- Show queue depth per stablecoin: `getQueueDepth()`
- Show current reserves for context
- Help users understand "if I want USDT, will it be instant or queued?"

**7.2 Swap Interface**
- "From" selector: stablecoin or DLRS
- "To" selector: stablecoin
- Amount input
- Preview: "Instant" vs "Queued (X ahead of you)"

**7.3 Swap Execution**
- If instant: execute and show success
- If queued: clearly communicate position, estimated wait (if possible)
- Toggle for "queue if unavailable" vs "instant only"

**7.4 Queue Management**
- Show user's active queue positions
- Cancel button for each position
- Show partial fill progress if applicable

**7.5 Real-time Updates**
- Listen for events to update queue positions
- Notify user when their position is filled

### Acceptance Criteria
- Swap flow works for instant case
- Swap flow works for queued case
- User can see and manage their queue positions
- UI clearly communicates instant vs queued status

---

## Phase 8: Deployment & Launch

### Goal
Deploy contracts and launch the site.

### Tasks

**8.1 Testnet Deployment**
- Deploy to Sepolia or Goerli
- Test all flows end-to-end
- Get external eyes on it if possible

**8.2 Mainnet Deployment**
- Final contract review
- Deploy DLRS token
- Deploy DollarStore contract
- Verify contracts on Etherscan
- Set up monitoring/alerts for contract events

**8.3 Frontend Deployment**
- Deploy to Vercel or similar
- Point dollarstore.space domain
- Ensure environment variables are correct for mainnet

**8.4 Documentation**
- README for GitHub repo
- Brief docs explaining how it works
- Contract addresses and ABIs published

**8.5 Launch**
- Announce
- Seed initial liquidity if needed
- Monitor closely for first few days

### Acceptance Criteria
- Contracts verified and operational on mainnet
- Website live at dollarstore.space
- Documentation complete
- Monitoring in place

---

## Implementation Notes for Claude Code

### Priorities
1. **Correctness over cleverness** — Simple, readable code that obviously works
2. **Test coverage** — Every function should have tests, especially edge cases
3. **Gas awareness** — But don't over-optimize prematurely
4. **Security-first** — Assume adversarial users from day one

### Decisions Made (Don't Revisit)
- Ethereum mainnet only for v1 (no L2s, no multi-chain)
- No fees anywhere
- No governance token
- No protocol-level risk management
- FIFO queue ordering
- Users can cancel queue positions anytime
- $DLRS is fully fungible, composition of original deposit doesn't matter

### Open Decisions (Make Reasonable Choices)
- Queue data structure implementation (optimize for gas + readability)
- Exact behavior of swap() when queueIfUnavailable=false and partial reserves exist
- Whether whitelist is truly immutable or admin-upgradeable
- Contract upgradeability (recommend immutable for trust minimization)

### Testing Approach
- Unit tests for individual functions
- Integration tests for multi-step flows
- Fork tests against mainnet for realistic stablecoin behavior
- Fuzz tests for numeric edge cases if time permits

---

## File Structure (Suggested)

```
dollarstore/
├── contracts/
│   ├── foundry.toml
│   ├── src/
│   │   ├── DollarStore.sol
│   │   ├── DLRS.sol
│   │   └── interfaces/
│   │       └── IDollarStore.sol
│   ├── test/
│   │   ├── DollarStore.t.sol
│   │   └── DollarStore.fork.t.sol
│   └── script/
│       └── Deploy.s.sol
├── frontend/
│   ├── app/
│   │   ├── page.tsx (home)
│   │   └── swap/
│   │       └── page.tsx
│   ├── components/
│   ├── lib/
│   │   └── contracts.ts (ABIs, addresses)
│   └── ...
├── docs/
│   └── ...
└── README.md
```

---

## Sequencing Summary

1. **Phase 1** — Core contracts (deposit/withdraw/DLRS)
2. **Phase 2** — Queue system
3. **Phase 3** — Swap convenience function
4. **Phase 4** — Security & optimization
5. **Phase 5** — Frontend structure
6. **Phase 6** — Home page
7. **Phase 7** — Swap page
8. **Phase 8** — Deploy & launch

Each phase should be completable in relative isolation. Contracts (1-4) can be done before frontend (5-7), but can also be parallelized if needed.
