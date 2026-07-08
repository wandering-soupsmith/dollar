# DollarStore — Contracts

Upgradeable (UUPS) stablecoin protocol: a **hub** pool (USDC/USDT + the DLRS receipt token) with
directed 1:1 swaps and FIFO queues. Built with [Foundry](https://book.getfoundry.sh/).

- Solidity **0.8.24**
- OpenZeppelin **v5.6.x** (contracts + contracts-upgradeable) — **not** v4
- `via_ir` is enabled (see `foundry.toml`)

---

## Quick start (clean laptop → running tests)

### 1. Prerequisites

- **git**
- **Foundry** (forge/cast/anvil). Install it:

```bash
curl -L https://foundry.paradigm.xyz | bash
# then open a new shell OR `source ~/.bashrc` (or ~/.zshenv), then:
foundryup
```

Verify: `forge --version`.

> Windows: use **WSL** (Ubuntu) and run the commands above inside it.

### 2. Get the code

```bash
git clone https://github.com/wandering-soupsmith/dollar.git
cd dollar/contracts
```

### 3. Install dependencies

Dependencies are **not** committed (`contracts/lib/` is git-ignored), so install them with Forge.
Pin OpenZeppelin to **v5.6.x**:

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.6.1
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v5.6.1
forge install foundry-rs/forge-std
```

> If Forge complains about a dirty working tree, add `--no-commit` to each command
> (older Foundry), or commit/stash first. Newer Foundry does not create commits.

After this you should have `contracts/lib/{openzeppelin-contracts, openzeppelin-contracts-upgradeable, forge-std}`.

### 4. Build & test

```bash
forge build
forge test           # or: forge test -vvv
```

Run a single file, or coverage:

```bash
forge test --match-path "test/HubSwapQueue.t.sol" -vvv
forge coverage --report summary --ir-minimum
forge fmt
```

> If `forge build` ever reports **"stack too deep"**, confirm `via_ir = true` is present in
> `foundry.toml` (`[profile.default]`); it already is.

### Continuous Integration

CI (build, format check, full test suite, a coverage gate, and Slither static analysis) runs on
every push to `main` and every PR. See **[CI.md](CI.md)** for the jobs, thresholds (e.g. the
`>= 90%` src coverage gate), and how to run the same checks locally.

### Security

The trust model, on-chain roles (governor timelock vs guardian Safe), the emergency
pause-then-fix playbook, and responsible disclosure are documented in **[SECURITY.md](SECURITY.md)**.

---

## Project layout

```
contracts/
├── src/
│   ├── DollarStore.sol            # core (UUPS): roles, hub deposit/withdraw, directed swaps + queues
│   ├── DLRS.sol                   # soulbound 6-decimal receipt token
│   ├── interfaces/IDollarStore.sol
│   ├── storage/                   # ERC-7201 namespaced storage (CoreStorage, RegistryStorage, QueueStorage)
│   └── libraries/                 # NormalizationLib (decimals), QueueLib (FIFO linked list)
├── script/                        # Deploy.s.sol (proxy + init), Upgrade.s.sol
├── test/                          # Foundry tests + mocks
├── foundry.toml
└── remappings.txt
```

## Deploy (local / testnet)

Deploy the implementation + ERC1967 proxy (initialized with upgrader/governor/guardian):

```bash
export DEPLOYER_PRIVATE_KEY=0x...
export UPGRADER=0x...   # optional; defaults to deployer (long-delay timelock in prod)
export GOVERNOR=0x...   # optional; defaults to deployer (short-delay timelock in prod)
export GUARDIAN=0x...   # optional; defaults to deployer (Safe multisig in prod)

forge script script/Deploy.s.sol:Deploy --rpc-url <your_rpc_url> --broadcast
```

The three roles are `upgrader` (UUPS upgrade authority), `governor` (risk/registry/caps) and
`guardian` (fast emergency). Upgrades go through the upgrader (a TimelockController in production)
— see `script/Upgrade.s.sol` and [SECURITY.md](SECURITY.md).

## Notes

- **OpenZeppelin must be v5.6.x.** With v4 the build fails (custom errors, `upgradeToAndCall`
  signature, and `ReentrancyGuard` differ). In v5.6 `ReentrancyGuard` is stateless (imported from
  `@openzeppelin/contracts`, no initializer).
- Environment variables live in a `.env` (see `.env.example`); never commit real keys.
```
