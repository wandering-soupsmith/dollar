# Test map

Where each `src/` module is tested. The small pure libraries have a dedicated `*.t.sol` named after
them. The three large linked libraries (`SwapRouteLib`, `SpokeAdminLib`, `SpokeLifecycleLib`) run via
`delegatecall` over the proxy's ERC-7201 storage, so they are exercised through the proxy by the
feature-named integration suites listed below rather than by a same-named unit file.

## Core

| Module | Test file(s) |
|---|---|
| `DollarStore.sol` (init / roles / upgrade) | `DollarStore.t.sol` |
| `DollarStore.sol` (hub deposit / withdraw) | `HubDepositWithdraw.t.sol` |
| `DollarStore.sol` (asset registry) | `AssetRegistry.t.sol` |
| `DollarStore.sol` (risk controls: pauses, peg, staleness) | `RiskControls.t.sol` |
| `DollarStore.sol` (launch caps) | `LaunchCaps.t.sol` |
| `DLRS.sol` (soulbound token, mint/burn authority) | `DLRS.t.sol` |

## Storage

| Module | Test file(s) |
|---|---|
| `storage/CoreStorage.sol` | `CoreStorage.t.sol` |
| `storage/QueueStorage.sol` | `QueueStorage.t.sol` |
| `storage/RegistryStorage.sol` | `RegistryStorage.t.sol` |

## Libraries

Small pure/internal libraries — dedicated unit files:

| Library | Test file(s) |
|---|---|
| `libraries/NormalizationLib.sol` | `NormalizationLib.t.sol` |
| `libraries/QueueLib.sol` | `QueueLib.t.sol` |
| `libraries/SpokeShareLib.sol` | `SpokeShareLib.t.sol` |
| `libraries/PegLib.sol` (oracle peg + inflow gate) | `RiskControls.t.sol`, `SpokeQueueTrigger.t.sol` |

Large linked libraries — tested through the proxy by the integration suites:

| Library | Responsibilities | Test file(s) |
|---|---|---|
| `libraries/SwapRouteLib.sol` | directed swap engine, FIFO fill/settle, processQueue, cancelQueue, spoke-queue trigger | `HubSwapQueue.t.sol`, `HubSwapFallback.t.sol`, `SpokeSwap.t.sol`, `SpokeQueueTrigger.t.sol`, `RiskControls.t.sol` |
| `libraries/SpokeAdminLib.sol` | createSpoke, syncReserves, rescueTokens | `SpokeDeposit.t.sol`, `SpokeCapsAndPauses.t.sol`, `AssetRegistry.t.sol` |
| `libraries/SpokeLifecycleLib.sol` | windDownSpoke, removePool, haircutEscrow, redeemSpoke | `SpokeLifecycle.t.sol`, `SpokeWinddownHaircut.t.sol`, `SpokeWithdraw.t.sol` |

## Invariants

`test/invariant/` (`DollarStoreInvariants.t.sol`, `Handler.sol`) drives randomized
deposit/withdraw/swap/cancel/process/spoke sequences and asserts the DLRS-backing and solvency
invariants across the whole system.
