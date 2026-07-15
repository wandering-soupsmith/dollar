# Deploy runbook

Step by step to deploy DollarStore with the production topology: an **upgrader timelock**, a
**governor timelock**, and a **guardian Safe**. The same procedure runs on Sepolia (rehearsal) and
mainnet (production); you only change which environment file you load. Design reference:
[SECURITY.md](SECURITY.md).

Golden rule: the roles are wired to the timelocks/Safe at `initialize()` time, so the **deployer
keeps no power**. All later configuration (listing assets, caps) goes through the governor timelock,
and every upgrade through the upgrader timelock.

There are two deploy scripts:

- `script/Deploy.s.sol` — local / anvil only. Roles are plain addresses (default: the deployer).
- `script/DeployGovernance.s.sol` — Sepolia and mainnet. Deploys the two timelocks + the proxy,
  wired to the operator Safes. **This runbook uses `DeployGovernance`.**

---

## Decisions to make once

- How many Safes: one shared (all three roles point at it) or up to three distinct
  (upgrader / governor / guardian). See SECURITY.md for the trade-off.
- Delays: short on Sepolia (to rehearse quickly), 7d (upgrader) / 2d (governor) on mainnet.
- Initial hub assets and their Chainlink feeds (USDC, USDT).
- Initial launch caps.

## Prerequisites

- Foundry installed and dependencies: `cd contracts && forge install` (OZ v5.6.1 x2 + forge-std).
- Green suite: `forge test`.
- A deployer EOA funded with gas on the target network (Sepolia test ETH / mainnet ETH).
- An Etherscan API key.

---

## Phase 0 - Prepare Safes and environment

1. Create the Safe(s) at https://app.safe.global on the target network (3-of-5, >= 2 hardware
   signers, secure the 5th signer). Record the address(es).
2. Fill the network env file (`.env.sepolia` or `.env.mainnet`; copy from `.env.example`):
   - `SEPOLIA_RPC_URL` / `MAINNET_RPC_URL`
   - `DEPLOYER_PRIVATE_KEY` (with the `0x` prefix)
   - `ETHERSCAN_API_KEY`
   - `UPGRADER_SAFE` (required), `GOVERNOR_SAFE`, `GUARDIAN_SAFE` (if omitted, they default to
     `UPGRADER_SAFE`)
   - `UPGRADER_DELAY`, `GOVERNOR_DELAY` (seconds)

## Phase 1 - Deploy

> [!WARNING]
> **Etherscan Verification and macOS compile mismatch:** Due to a known issue with the Solidity Yul optimizer (`via_ir = true`), compiling on macOS can produce slightly different bytecode compared to compiling on Linux. Since Etherscan's verification servers run Linux, contracts deployed directly from macOS may fail verification with a `Compiled contract deployment bytecode does NOT match the transaction deployment bytecode` error.
> 
> **Recommendation:** To guarantee verification success on Etherscan/Sourcify, always deploy from a standardized Linux Docker container (or clean Linux VM) using the helper script `script/deploy-docker.sh`.

### Option A: Deploy via Docker (Recommended for production/rehearsals)

A helper script is provided to automate compilation and deployment inside a Linux-based Docker container:

```bash
cd contracts

# 1) Dry run (no tx broadcasted)
./script/deploy-docker.sh .env.sepolia

# 2) Broadcast and verify on-chain
./script/deploy-docker.sh .env.sepolia --broadcast --verify
```

### Option B: Deploy directly (Only for local VM or Linux hosts)

You pick the network here: (a) which env file you load, and (b) which `--rpc-url` you target. They must match.

```bash
cd contracts

# Load the network environment. IMPORTANT: `set -a` EXPORTS the variables to the forge process.
# A plain `source` sets them as shell variables but does NOT export them, so forge would not see them.
set -a; source .env.sepolia; set +a        # or: source .env.mainnet

# 1) Dry run (simulation, no tx sent).
forge script script/DeployGovernance.s.sol:DeployGovernance --rpc-url sepolia

# 2) Real deploy + explorer verification.
forge script script/DeployGovernance.s.sol:DeployGovernance \
  --rpc-url sepolia --broadcast --verify
```

Record from the logs (or from `broadcast/`): `DollarStore proxy`, `DLRS token`,
`upgrader timelock`, `governor timelock`. You will use these in every later phase.

If `DLRS` was not verified (it is created inside `initialize`), verify it manually:

```bash
forge verify-contract <DLRS_ADDR> src/DLRS.sol:DLRS --chain sepolia \
  --constructor-args $(cast abi-encode "constructor(address)" <PROXY_ADDR>)
```

## Phase 2 - Verify the wiring on-chain

```bash
PROXY=<proxy>
cast call $PROXY "upgrader()(address)" --rpc-url sepolia   # == upgrader timelock
cast call $PROXY "governor()(address)" --rpc-url sepolia   # == governor timelock
cast call $PROXY "guardian()(address)" --rpc-url sepolia   # == guardian Safe
cast call $PROXY "version()(string)"   --rpc-url sepolia

cast call <UPGRADER_TL> "getMinDelay()(uint256)" --rpc-url sepolia
cast call <GOVERNOR_TL> "getMinDelay()(uint256)" --rpc-url sepolia

# Guardian is CANCELLER on both timelocks, and the temporary deploy admin was renounced (no admin left).
CANC=$(cast call <UPGRADER_TL> "CANCELLER_ROLE()(bytes32)" --rpc-url sepolia)
ADMIN=$(cast call <UPGRADER_TL> "DEFAULT_ADMIN_ROLE()(bytes32)" --rpc-url sepolia)
cast call <UPGRADER_TL> "hasRole(bytes32,address)(bool)" $CANC <GUARDIAN_SAFE> --rpc-url sepolia   # true
cast call <GOVERNOR_TL> "hasRole(bytes32,address)(bool)" $CANC <GUARDIAN_SAFE> --rpc-url sepolia   # true
cast call <UPGRADER_TL> "hasRole(bytes32,address)(bool)" $ADMIN <DEPLOYER>     --rpc-url sepolia   # false
cast call <GOVERNOR_TL> "hasRole(bytes32,address)(bool)" $ADMIN <DEPLOYER>     --rpc-url sepolia   # false
```

Do not proceed if anything does not match.

## Phase 3 - Configure the protocol (via the governor timelock)

`addHubAsset` and `setLaunchCap` are governor-gated, so they are **not** called directly: they are
scheduled on the governor timelock, wait the delay, then are executed. This is driven by the
governor Safe.

With the Safe (production): Safe -> New transaction -> Transaction Builder, targeting the governor
timelock, function `schedule(...)` with the payload below. Sign 3-of-5. After the delay, another tx
to the same timelock `execute(...)` (execution is open, anyone can execute).

With an EOA operator (testnet quick rehearsal only):

```bash
GOV_TL=<governor timelock>;  USDC=<usdc>;  USDC_FEED=<chainlink usdc/usd>
DATA=$(cast calldata "addHubAsset(address,address)" $USDC $USDC_FEED)

# schedule (proposer = governor Safe/EOA)
cast send $GOV_TL "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $PROXY 0 $DATA 0x0 0x0 "$GOVERNOR_DELAY" \
  --private-key $GOV_OP_KEY --rpc-url sepolia

# ...wait GOVERNOR_DELAY...

# execute (open)
cast send $GOV_TL "execute(address,uint256,bytes,bytes32,bytes32)" \
  $PROXY 0 $DATA 0x0 0x0 \
  --private-key $ANY_KEY --rpc-url sepolia
```

Repeat for USDT and for `setLaunchCap(uint16,uint256)` (poolId 0). Check with
`cast call $PROXY "isAssetListed(address)(bool)" $USDC`.

## Phase 4 - Governance rehearsal (mandatory on Sepolia)

1. Instant guardian: from the guardian Safe, `pause()` and `unpause()` on the proxy (no timelock).
2. Governor action: a full `setPegTolerance` / `setLaunchCap` through the governor timelock
   (schedule -> wait -> execute), as in Phase 3.
3. Governed upgrade: deploy a new implementation and schedule `upgradeToAndCall(newImpl, "")` on the
   UPGRADER timelock (schedule -> wait UPGRADER_DELAY -> execute). Confirm the new implementation is
   active and state was preserved.
4. Guardian cancel: schedule any op on a timelock, then from the guardian Safe `cancel(id)` before
   the delay elapses. Confirms the guardian can abort a queued op even though it is not the proposer.

These rehearsals validate the three authority paths plus the guardian's cancel power before mainnet.

## Phase 5 - Pre-mainnet checklist and mainnet

Before mainnet:

- Full Sepolia rehearsal completed and green.
- External review closed (fixes merged + re-tested).
- `security.txt` ready to publish (contact admin@dollarstore.world).

Mainnet is the same sequence with `.env.mainnet` (real Safes, 7d/2d delays). Before the first
deposit, confirm on-chain: roles = timelocks/Safe, assets listed, caps active, expected `version()`,
`tip` = 0.

---

## Operational notes

- The Safe operates the timelocks: each `schedule` / `execute` is a Safe transaction (Transaction
  Builder), with its signatures. Only the guardian acts without a timelock (pauses).
- `execute` is open: after the delay, anyone can execute. `schedule` requires the proposer Safe.
  `cancel` can be done by the proposer Safe or the guardian Safe (the guardian is granted CANCELLER
  on both timelocks).
- The deployer is not a lasting trust anchor: during the deploy it holds a temporary timelock admin
  only to grant the guardian its CANCELLER role, then renounces it in the same run. The on-chain
  roles are the timelocks/Safe from genesis.
- Initial configuration is timelocked: listing the first assets goes through the governor timelock,
  so on mainnet it takes GOVERNOR_DELAY (2d) from the schedule. Plan it into the launch calendar.
```
