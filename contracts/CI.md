# Continuous Integration

CI runs on every push to `main` and on every pull request. The workflow is
[`.github/workflows/ci.yml`](../.github/workflows/ci.yml). It has two jobs.

## Job 1: build + test + coverage

Runs in `contracts/`:

1. **Install Foundry** (`foundry-rs/foundry-toolchain`).
2. **Install dependencies** (pinned): OpenZeppelin Contracts `v5.6.1`, OpenZeppelin Contracts
   Upgradeable `v5.6.1`, and `forge-std`. Dependencies are not committed (`contracts/lib/` is
   git-ignored), so CI fetches them.
3. **Format check**: `forge fmt --check` (fails on unformatted code).
4. **Build**: `forge build --sizes`.
5. **Test**: `forge test -vvv` (unit + fuzz + invariant suites).
6. **Coverage gate**: `forge coverage --report lcov --ir-minimum`, then
   [`ci/coverage_gate.py`](ci/coverage_gate.py) parses `lcov.info` and fails the build if line
   coverage of `src/` is below the threshold.

## Job 2: static analysis (Slither)

Runs `crytic/slither-action` against `contracts/` using
[`slither.config.json`](slither.config.json). It builds the project and runs Slither with
`fail-on: high`, so the job fails only on high-severity findings (medium/low/informational are
reported but do not block).

## Thresholds

| Check | Threshold | Where |
|---|---|---|
| Line coverage (`src/` only) | **>= 90%** | `ci/coverage_gate.py` (`THRESHOLD`) |
| Slither | fail on **high** severity | `ci.yml` (`fail-on: high`) |
| Formatting | must match `forge fmt` | `forge fmt --check` |
| Fuzz runs | 256 per fuzz test | `foundry.toml` `[profile.default.fuzz]` |
| Invariant runs / depth | 128 runs, depth 32 | `foundry.toml` `[profile.default.invariant]` |

The coverage threshold lives in `ci/coverage_gate.py` (`THRESHOLD = 90.0`). Raise it as the suite
matures. Coverage uses `--ir-minimum` because the project builds with `via_ir = true`.

## What is tested

- **Unit tests** per module: governance/upgrade (`DollarStore.t.sol`), storage-slot guards and
  round-trips (`CoreStorage.t.sol`, `QueueStorage.t.sol`, `RegistryStorage.t.sol`), decimal
  normalization (`NormalizationLib.t.sol`), queue mechanics (`QueueLib.t.sol`), hub deposit/withdraw
  (`HubDepositWithdraw.t.sol`), directed swaps + queues (`HubSwapQueue.t.sol`), failed-transfer /
  blacklist fallbacks (`HubSwapFallback.t.sol`), asset registry (`AssetRegistry.t.sol`), risk
  controls (`RiskControls.t.sol`), and launch caps (`LaunchCaps.t.sol`).
- **Fuzz tests**: decimal round-trip / no-inflation, and other property tests.
- **Invariant tests** (`test/invariant/`): randomized deposit/withdraw/swap/cancel/process sequences
  assert two global properties:
  1. **DLRS backing** - total DLRS supply equals the sum of hub reserves (queue escrow is not backing).
  2. **Solvency** - the contract's token balance always covers reserves + queue escrow for every asset.

## Run the same checks locally

```bash
cd contracts
forge fmt --check
forge build --sizes
forge test -vvv
forge coverage --report lcov --ir-minimum && python3 ci/coverage_gate.py
# static analysis (requires slither: `pipx install slither-analyzer` or `pip install slither-analyzer`)
slither . --config-file slither.config.json
```
