# Deployment - Sepolia

**Network:** Sepolia (chain id 11155111)
**Date:** 2026-07-10
**Block:** 11244019
**Script:** `script/DeployGovernance.s.sol:DeployGovernance`
**Total gas paid:** ~0.01246 ETH
**Topology:** one shared Safe for the three roles; short delays for rehearsal (build now uses
`bytecode_hash = "none"`).

> Supersedes the earlier Sepolia deploy (block 11243952). Those addresses are dead.

## Addresses

| Contract | Address | Verified | Explorer |
|---|---|---|---|
| **DollarStore proxy** (interact here) | `0x409AB4a2F0d53C26DB78974896a850638dFdeC35` | yes | [link](https://sepolia.etherscan.io/address/0x409AB4a2F0d53C26DB78974896a850638dFdeC35) |
| DollarStore implementation | `0x486Ef5f0116D822fF74C485D8082e1c5adA10436` | **NO (pending)** | [link](https://sepolia.etherscan.io/address/0x486Ef5f0116D822fF74C485D8082e1c5adA10436) |
| DLRS token | `0xd5C333F0651bbB84Dd66CC6220B1750b2Fb18078` | yes | [link](https://sepolia.etherscan.io/address/0xd5C333F0651bbB84Dd66CC6220B1750b2Fb18078) |
| Upgrader timelock | `0xeA52572e34c44804818e019dB5518ad5d21c02FE` | yes | [link](https://sepolia.etherscan.io/address/0xeA52572e34c44804818e019dB5518ad5d21c02FE) |
| Governor timelock | `0x10ce4886846093f91F5C64Ed4F12624339D1341E` | yes | [link](https://sepolia.etherscan.io/address/0x10ce4886846093f91F5C64Ed4F12624339D1341E) |
| Guardian / Governor / Upgrader Safe (shared) | `0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31` | Safe | [link](https://sepolia.etherscan.io/address/0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31) |

## Role wiring (on the proxy)

| Role | Held by | Delay |
|---|---|---|
| `upgrader` | Upgrader timelock `0xeA52...02FE` | 3600s (1h) |
| `governor` | Governor timelock `0x10ce...341E` | 600s (10m) |
| `guardian` | Safe `0x19cA...fc31` (direct, no timelock) | - |

Both timelocks are proposed/cancelled by the same Safe `0x19cA...fc31`; execution is open; no
external admin.

## Deploy transactions

| What | Tx hash |
|---|---|
| Upgrader timelock | `0xe86a845bb45e736d5bc900aff4c106c7a6f04328594ff8f373041e26304abae5` |
| Governor timelock | `0xa5451ac21adaa54cbf627ecf84a67da2e4a010b8706e5b3a91a9ed2573e5bf80` |
| Implementation | `0x0aa8a952c03ed9fe080329d30c0e71599dce01f675738d1b2f6452fc4003493b` |
| Proxy (+ DLRS via initialize) | `0xe06ee2a16b10265e80d54661c0bb6ac6a8b0821ec9a40ca52d75b323c9340f08` |

(forge mislabels the proxy/impl in the broadcast list; roles above are by constructor args + gas.)

## Pending / follow-ups: verify the implementation

4 of 5 verified. The **implementation** (`0x486Ef5f0...`) fails on Etherscan with
`Compiled contract deployment bytecode does NOT match the transaction deployment bytecode`.

**Root cause (diagnosed by byte comparison):** it is NOT our source, config or metadata. The local
build reproduces the on-chain bytecode exactly (`forge inspect ... bytecode` == the deploy tx input,
both diverge-marker `612704`). Etherscan recompiles the *same* standard-json to a *different*,
294-bytes-larger bytecode (marker `612c4b`). So Etherscan's solc build produces different **via_ir**
output than the toolchain that deployed (same `0.8.24+commit.e11b9ed9`; native vs Etherscan build
diverge on via_ir for this complex contract). DLRS, being simple, verifies either way.

**Fix to try - Sourcify** (more reproducible; Etherscan shows Sourcify-verified sources):

```bash
cd contracts
forge verify-contract 0x486Ef5f0116D822fF74C485D8082e1c5adA10436 \
  src/DollarStore.sol:DollarStore --chain sepolia --verifier sourcify --watch
```

If Etherscan-native verification is required for mainnet, align the compiler build so the deployed
bytecode equals what Etherscan's verifier produces (pin the exact solc, or compile with the same
build Etherscan uses), and confirm on testnet before launch. This is a known via_ir + Etherscan
friction, not a contract issue.

## Sanity checks

```bash
PROXY=0x409AB4a2F0d53C26DB78974896a850638dFdeC35
cast call $PROXY "upgrader()(address)" --rpc-url sepolia   # 0xeA52...02FE
cast call $PROXY "governor()(address)" --rpc-url sepolia   # 0x10ce...341E
cast call $PROXY "guardian()(address)" --rpc-url sepolia   # 0x19cA...fc31
cast call $PROXY "version()(string)"   --rpc-url sepolia   # 0.8.1-M8.1
```

## Hub assets (Sepolia rehearsal)

**Date:** 2026-07-10. Listed the two mock stables as hub assets (poolId 0) through the governor
timelock (schedule -> wait 600s -> execute). Both point at one shared, always-fresh `$1` test feed.

> Operator note: the shared operator `0x19caCb4c...fc31` is an **EOA** on-chain (`cast code` returns
> `0x`) and equals the deployer, so the timelock was driven directly with `cast send`, not a Safe UI.
> (The "Safe" label in the Addresses table above is aspirational for mainnet; on Sepolia it's an EOA.)

| Contract | Address | Verified | Explorer |
|---|---|---|---|
| **TestnetPriceFeed** (shared `$1`, 8 dp) | `0xc09183D6C4657697B94a4056a98D09345C028341` | yes | [link](https://sepolia.etherscan.io/address/0xc09183D6C4657697B94a4056a98D09345C028341) |

Feed is configurable (`setAnswer(int256)`) and always fresh (`updatedAt == block.timestamp`), so it
never trips staleness; set the answer outside the peg band to rehearse the depeg revert. Testnet only.

| Asset | Address | poolId | decimals | priceFeed | listed |
|---|---|---|---|---|---|
| Mock USDC | `0x0a9479f7aff770965b3b2D28b29E40C3F6168588` | 0 | 6 | feed above | yes |
| Mock USDT | `0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05` | 0 | 6 | feed above | yes |

### Transactions

| What | Tx hash |
|---|---|
| Feed deploy (`TestnetPriceFeed`, args `8 100000000`) | `0xc5a60dbd1368fd6dc81b8030950cbba88ddcf30657fad0ff9f9320c1fb033bd8` |
| Schedule `addHubAsset(USDC, feed)` | `0xe8237edce963c61c137b5c027ea25a41d1a2ce03eee047e57dd9361bc733438d` |
| Schedule `addHubAsset(USDT, feed)` | `0x2611e43f54a730fd3c08f472f5dc1e887ba6454a9c30538b888eb934473b53d3` |
| Execute `addHubAsset(USDC, feed)` | `0x2731f81d7df6134d0441edf8a0b042f274af7397aba252eee16216896ce0a8ce` |
| Execute `addHubAsset(USDT, feed)` | `0x493f101e322cc163f7b9f4ff9e85be2443bd027a6b9b05ee7b0ad4a094a6e5f8` |

Operation ids (governor timelock): USDC `0xfca9c2a2b37a2f4fee468815e6232e37446e74fbfd726202a22a5542933ff80b`,
USDT `0x5fd5268afe7dac74a39cb0ab3eb929259bb63c6d5054b9130b3ae7ff40e33c7c`. Both used
`predecessor = salt = bytes32(0)`, `delay = 600` (== min delay), value `0`, target the proxy.

### Post-listing checks (all pass)

```bash
PROXY=0x409AB4a2F0d53C26DB78974896a850638dFdeC35
USDC=0x0a9479f7aff770965b3b2D28b29E40C3F6168588
USDT=0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05
cast call $PROXY "isAssetListed(address)(bool)"    $USDC --rpc-url sepolia   # true
cast call $PROXY "isAssetListed(address)(bool)"    $USDT --rpc-url sepolia   # true
cast call $PROXY "assetPriceFeed(address)(address)" $USDC --rpc-url sepolia  # 0xc091...8341
cast call $PROXY "assetDecimals(address)(uint8)"    $USDC --rpc-url sepolia  # 6
```

### Seeded liquidity + smoke swap (2026-07-10)

Public faucet `mint` used to fund the deployer, then hub liquidity added and a swap exercised
end-to-end. All at the `$1` peg (1:1), confirming deposit -> reserves -> DLRS mint and a
reserve-neutral hub-hub swap.

| Action | Amount | Tx hash |
|---|---|---|
| Mint USDC → deployer | 1,000,000 | `0xf2b076314f1aabbf14d525a3f8936214a9ea22547cd1d75af36eea2f9035dadb` |
| Mint USDT → deployer | 1,000,000 | `0x142de947ba2c5db3f44a84d3ffca7c90ee656deee673850f15fa5ad34d6c6530` |
| Deposit USDC (hub) | 1,000,000 | `0x45a633a7fcb62b55b7bf7c22f27d8415b8d10303bd70e9ed9ae01a71e9b27ec3` |
| Deposit USDT (hub) | 1,000,000 | `0xb963b2100c95b1b6eaf867e7356acd23eef44c5c159b7bdaab646fd0b631279c` |
| Mint USDC (swap test) | 1,000 | `0x9fe5f29b5035b773958b79ce8c38c07cc354257c28806107667b439f284490d5` |
| Swap USDC → USDT | 1,000 → 1,000 | `0x2581847d01bbbb9f0d4714e24d3839c369eaba2bb9a70ddd423d7895f5e0d996` |

Post-state: DLRS supply `2_000_000_000000` (2M, minted 1:1 on the two deposits); hub reserves
USDC `1_001_000_000000`, USDT `999_000_000000` (swap moved 1k of value 1:1). Swapper received
exactly 1,000 USDT for 1,000 USDC — no slippage at peg.

## Next steps

- Verify the implementation (above) — the important follow-up (source visibility for integrators).
- ~~Phase 3: list USDC/USDT (`addHubAsset`)~~ — **done** (see "Hub assets" above). Still pending:
  set launch caps via the **governor timelock** (schedule -> wait 10m -> execute).
- Phase 4: governance rehearsal (guardian pause, a governor action, a governed upgrade).
- Optional smoke test: mint mocks to a test wallet, approve the proxy, then one `deposit` + one `swap`.

See `contracts/DEPLOY.md` for the full runbook.
