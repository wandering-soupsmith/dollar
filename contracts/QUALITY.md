# Code quality & security checklist

Run through this before finishing ANY change to the Solidity code. It captures the recurring items an
external audit or static analyzer will otherwise flag, so we do not re-introduce them. Seeded from the
OpenZeppelin audit "Notes" (N-01..N-04) and expanded with the standard public auditor checklists
(see References). Tailored to this protocol: a UUPS-upgradeable, oracle-gated, FIFO-queue stablecoin
exchange with ERC-7201 namespaced storage and a 3-role (upgrader / governor / guardian) model.

Not every item applies to every change. Skim the categories, apply what is relevant, and do not
regress anything already enforced.

## 1. Solidity style (from the OZ audit notes)

- **Type-safe calldata.** Build calldata with `abi.encodeCall(IFace.fn, (args))`, never
  `abi.encodeWithSelector` / `abi.encodeWithSignature`. (N-01)
- **No magic numbers.** Every non-trivial literal (decimals, bps, delays, tolerances, order sizes,
  `1e18`, `10_000`, ...) is a named `constant`. The same literal with two meanings gets two
  constants and is never collapsed (e.g. max feed decimals `18` vs the `18` fixed-point target). (N-02)
- **Fixed pragma.** `pragma solidity 0.8.24;`, not `^0.8.24`. (N-03)
- **One return convention per function.** Do not mix named returns with an explicit tuple `return`.
  No unused named returns. (N-04)
- Custom errors over `require` strings. NatSpec on every external function accurate to the code
  (gating role, units, revert conditions).

## 2. Access control & privileged roles

- Every state-changing external function has an explicit, correct access modifier (or is
  deliberately permissionless). No missing/`public` where it should be restricted.
- Powers are split by blast radius (upgrader / governor / guardian). The fast role can only slow or
  stop, never move funds or upgrade. Role hand-offs are two-step (`transfer*` + `accept*`).
- Privileged setters emit events and validate inputs (non-zero, bounds).
- A compromised single role cannot escalate to another (e.g. governor cannot rotate the upgrader).
- Timelock: schedule/execute/cancel roles are wired as intended and no residual admin remains.

## 3. Reentrancy & external calls (CEI)

- Checks-Effects-Interactions: update storage BEFORE external calls/transfers. State-changing paths
  with token transfers carry `nonReentrant`.
- Treat every external call as adversarial (reentrancy, return-bomb, gas griefing). Handle failed
  transfers gracefully where a revert would brick a batch (use the `_tryTransfer` pattern).
- No reliance on `msg.sender` being an EOA; no `tx.origin` for auth.
- Beware read-only reentrancy: view functions used by others should not return mid-update state.

## 4. Arithmetic, units & rounding

- Rounding direction is deliberate and always favors the protocol (dust stays with the user on the
  way in, exact on the way out). No free-mint / inflation path.
- Normalize to the internal unit (6dp) at the boundary; keep native units only at transfer edges.
  `minAmountOut` and error payloads use a single, documented unit convention across all entrypoints.
- Guard against silent truncation on downcasts (`uintN`). Watch subtraction underflow on scaling
  like `10**(18 - feedDecimals)` (validate the input range so it cannot panic-revert a hot path).
- No unchecked math unless proven safe with a comment. Prefer explicit bounds over relying on 0.8
  overflow reverts in user-facing hot paths (a revert can be a DoS).

## 5. Oracles / price feeds

- Validate `answer > 0`, `answeredInRound >= roundId`, and freshness
  (`block.timestamp - updatedAt <= maxStaleness`). Reject feeds reporting > 18 decimals at config.
- Apply the peg band on BOTH directions: inflows (deposit / swap offer / queue settlement) and the
  upper band on outflows (withdraw / swap wantAsset), so a premium asset cannot be drained.
- Feed and tolerance are governor-configurable; do not add a permanent "ignore oracle" flag.
- Consider what happens if the feed is stale or reverts: which user paths get blocked, and is there
  an alternative exit (e.g. redeem a different basket asset).

## 6. ERC-20 / token integration

- Use `SafeERC20` for transfers/approvals. Do not assume a boolean return.
- Do not assume 18 decimals; read and normalize. Do not assume `transfer` moves the full amount
  (fee-on-transfer) or that balances are static (rebasing) unless the trust model excludes them, and
  state that exclusion.
- Account by explicit reserve bookkeeping, not `balanceOf`, so donations/seizures cannot skew logic;
  provide a `syncReserves`/write-down path for real losses.
- Handle blacklist/freeze on reserve assets (an issuer can block transfers); degrade gracefully.

## 7. Upgradeability & storage (frozen for v1)

- Implementation constructor only `_disableInitializers()`. All state is set in `initialize`
  (`initializer`) / `reinitializer(n)` for upgrades, never a constructor (proxy runs no constructor).
- ERC-7201 namespaced storage, one namespace per module. Grow a namespaced struct by APPENDING at
  the end only. Never reorder or retype existing fields. Slot-guard tests must stay green.
- `Pool` lives in a `Pool[]` array: its TOTAL size is fixed. New per-pool fields are carved from the
  `__gap` tail (add field, shrink `__gap` by the same slots). See `local/docs/STORAGE-MANIFEST.md`.
- `_authorizeUpgrade` is correctly gated (upgrader) and the new implementation preserves layout.
  Rehearse the full upgrade lifecycle (deploy -> init -> use -> schedule -> execute) on testnet.
- Do not change existing public/external signatures (integrators are not upgradeable). New behavior
  is additive: new functions/events/errors. `tip` stays reserved and `== 0`.

## 8. Denial of service, gas & loops

- No unbounded loops over user-controlled arrays/queues in a single tx. Cap iterations and/or make
  settlement paginated/permissionless. A single dust entry must not be able to strand a route.
- No single actor can grow a shared structure without an escalating cost (min order size / caps).
- Cache storage reads pulled repeatedly inside loops where it is a real win (not in a rarely-taken
  branch, where an unconditional cache would regress the hot path).
- Pull-over-push for value where a push to a hostile recipient could brick others.

## 9. Input validation, invariants & misc

- Validate every external input: non-zero addresses, deadlines, pool/asset existence, amount > 0.
- State a clear, testable invariant per subsystem (e.g. DLRS totalSupply == sum of hub reserves in
  the fully-backed state) and assert it in the invariant suite.
- No `selfdestruct`, no `delegatecall` to untrusted targets, no arbitrary external call with
  user-controlled target+calldata.
- Events for every state-changing action, with the right indexed fields.
- Deterministic build for verification (`bytecode_hash = "none"`, compile on Linux for Etherscan).

## 10. Testing, verification & tooling (before "done")

- Add/'update tests for the change: unit + fuzz + invariant where relevant. Do not weaken asserts to
  make something pass; fix the contract for a real bug.
- Bump `version()` and its assertion.
- **Contract size (EIP-170).** Every deployable contract must stay under the 24576-byte runtime
  limit. Check it locally BEFORE pushing so CI is not the first place it surfaces: run
  `forge build --sizes` (or `forge build --sizes --skip test`) and confirm no `src/` contract is
  over the limit or near it (treat < ~1KB of headroom as a warning). When a contract approaches the
  limit, move cold, rarely-called logic into an external `library` that runs via delegatecall over
  the same ERC-7201 storage (e.g. `SpokeAdminLib`) rather than trimming behavior or tests; keep the
  hot swap/deposit/withdraw path inline. Leave headroom for future upgrades.
- Full suite green, `src/` line coverage >= 90%, Slither with no HIGH (medium/low reported and
  justified). Run `slither . --config-file slither.config.json`.
- NEVER put secrets (private keys, RPC URLs, API keys) in any tracked file. They live only in the
  gitignored `.env.*`.
- No AI attribution anywhere (see `CLAUDE.md`).

## References (public checklists)

- OpenZeppelin - security guidelines & audit readiness: https://docs.openzeppelin.com and the OZ blog.
- Solcurity (Cyfrin / transmissions11) - concrete Solidity/EVM checklist:
  https://github.com/transmissions11/solcurity
- Trail of Bits - building-secure-contracts (+ Slither detectors):
  https://github.com/crytic/building-secure-contracts
- Consensys - Smart Contract Best Practices:
  https://consensys.github.io/smart-contract-best-practices/
- SWC Registry - weakness classification: https://swcregistry.io
- Chainlink - using data feeds safely (staleness/round checks):
  https://docs.chain.link/data-feeds
- Proxy/upgradeability checklist (Zealynx): https://www.zealynx.io/blogs/proxy-upgradeability-security-checklist
