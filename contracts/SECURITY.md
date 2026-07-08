# Security

This document describes the trust model, on-chain roles, and operational
security posture for the DollarStore protocol. It is the reference for how
privileged powers are split and how emergencies are handled.

## Trust model at a glance

There are **three on-chain roles** plus a **transient deployer**. Powers are split
by blast radius: the two strongest roles (upgrades, and risk/registry params) sit
behind timelocks; only the fast fail-safe brakes are instant.

| Role | Who | Speed | Can do |
|---|---|---|---|
| **Upgrader** | TimelockController, long delay (proposed by a Safe) | Delayed (long timelock) | Replace the implementation (UUPS upgrade) |
| **Governor** | TimelockController, short delay (proposed by a Safe) | Delayed (short timelock) | List assets, raise caps, oracle/risk params, reserve markdown, token rescue, role transfers |
| **Guardian** | Safe multisig (3-of-5) | Instant | Pause / unpause, cancel queue positions, tighten caps |
| **Deployer** | Deploy account | One-time | Deploy + initialize, then hands off. Holds no lasting power |

Each role has its own two-step transfer (`transfer*` + `accept*`), so a handoff
requires the incoming address to explicitly accept.

## Upgrader (long timelock)

The upgrader holds the single most powerful authority: replacing the contract
code. It is isolated in its own role precisely because a bad or malicious upgrade
can rewrite everything, including every other control. Whoever can upgrade can
effectively become any other role, so this role gets the strongest protection:
the longest timelock delay and the best-guarded multisig.

Upgrader-gated functions:

- `upgradeToAndCall` (UUPS upgrade authority, via `_authorizeUpgrade`)
- `transferUpgrader` (self-managed: the upgrader hands itself off; the governor
  cannot rotate it, so a governor compromise cannot seize upgrade authority)

## Governor (short timelock)

The governor controls risk, registry and cap parameters. Every governor action is
subject to its timelock delay, which gives users a window to exit before a change
takes effect. It does **not** hold upgrade authority (that is the upgrader).

Governor-gated functions:

- `addHubAsset`, `setLaunchCap`
- `setPriceFeed`, `setPegTolerance`, `setMaxStaleness`
- `syncReserves` (marks reserves down after a loss)
- `rescueTokens` (sweeps only unaccounted excess above reserves + escrow)
- `transferGovernor` (self-managed), `transferGuardian` (governor rotates the guardian)

What sits behind each timelock (this is what makes the delays meaningful):

- **PROPOSER** = a Safe multisig (3-of-5). A timelock proposed by a single EOA
  is theater; the proposer must itself be a multisig.
- **EXECUTOR** = open (`address(0)`), so execution does not depend on any single
  signer being available after the delay elapses.
- **CANCELLER** = the guardian Safe, so a malicious or mistaken queued proposal
  can be aborted quickly.
- **Admin** = renounced after wiring, so no one can silently reconfigure roles.

The upgrader and governor can share the same proposer Safe; what is separated is
the mechanism and the delay per class of action, and (optionally) the signer sets.

## Guardian (fast, no timelock)

The guardian is an emergency role held by a Safe multisig. It has **fail-safe
brakes only** and never touches funds, the oracle, or upgrades.

Guardian-gated functions:

- `pause` / `unpause` (global)
- `pauseDeposits` / `unpauseDeposits` (per asset)
- `pausePool` / `unpausePool`
- `adminCancelQueue` (force-cancel a queue position, returning escrow to its owner)
- `lowerLaunchCap` (tighten a cap; can never loosen or remove it)

Rationale: the worst thing a compromised guardian can do is stop or slow the
system (a denial of service). It cannot move funds, repoint the oracle, or
upgrade. That bounded blast radius is exactly why it is allowed to act instantly.

Guardian rotation is **governor-gated**, not guardian-gated: a compromised
guardian must not be able to rotate itself and lock out the legitimate one.

## Deployer (transient)

The deployer is the account that runs the deploy script. It:

1. Deploys the implementation and the ERC1967 proxy.
2. Calls `initialize(upgrader, governor, guardian)` with the production
   **Timelocks** (upgrader + governor) and **Safe** (guardian) addresses.

The deployer holds no lasting on-chain role. If, for setup convenience,
deployment temporarily assigns a role to an EOA, that role **must** be handed off
to the Timelock / Safe (two-step `transfer*` + `accept*`) and the temporary key
retired **before the first deposit**.

## Emergency playbook (pause-then-fix)

Because the dangerous knobs live behind the timelock, incidents are handled in
two moves:

1. **Guardian pauses instantly** (global, per-pool, or per-asset). Exits
   (`withdraw`) stay open; only inflows (`deposit` / `swap`) are blocked.
2. **Governor fixes the root cause through its timelock** (repoint a broken feed,
   adjust tolerance, mark down reserves, sweep stray tokens), then unpauses. A code
   fix instead goes through the **upgrader** timelock.

Example: a Chainlink feed is deprecated. The guardian pauses the affected asset
immediately, the governor schedules `setPriceFeed`, and after the delay it is
executed and the asset unpaused.

## Recommended launch parameters

- **Upgrader timelock delay**: 7 days. Upgrades are the highest-impact action, so
  they get the longest exit window.
- **Governor timelock delay**: 48-72h to start, raised over time. Long enough to
  give users a real exit window, short enough to stay operational. The instant
  guardian pause is what covers true emergencies, so the governor delay does not
  need to be aggressively short.
- **Safe threshold**: 3-of-5. At least 2 hardware wallets, and at least one
  hardware signer required per transaction. Signers should be independent parties
  (for example an external liquidity-provider signer) and diverse in location and
  hardware vendor.
- **Peg controls**: `pegTolerance` 0.5% (50 bps) default, `maxStaleness` 1 hour.

## Key hygiene

- Hardware wallets, independent seeds, and on-device verification of the
  transaction hash before signing. No blind signing (this class of mistake is
  what has broken other multisig setups).
- Publish signer addresses and the threshold for public review.

## Upgrades and storage

The protocol is UUPS-upgradeable; upgrade authority is the **upgrader** (a
long-delay timelock), separate from the governor. Storage uses ERC-7201 namespaced
layouts and is frozen for the v1 launch: upgrades are append-only and must not
reorder or retype existing fields.

## Reserve accounting

DLRS is fully backed: `totalSupply()` equals the sum of hub reserves, and queue
escrow is not counted as backing. `syncReserves` only ever decreases reserves,
to true them up to the real balance after an external loss. Because that
acknowledges a shortfall against outstanding DLRS claims, it is a governor
(timelock) decision, not a guardian one.

## Responsible disclosure

Report suspected vulnerabilities privately to **admin@dollarstore.world**. A
`/.well-known/security.txt` with the same contact will be published alongside the
deployment. Please do not disclose publicly until a fix has been deployed.
