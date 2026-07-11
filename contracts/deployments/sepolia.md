# Deployment - Sepolia

**Network:** Sepolia (chain id 11155111)
**Date:** 2026-07-11
**Block:** 11250015
**Script:** `script/DeployGovernance.s.sol:DeployGovernance`
**Total gas paid:** ~0.11 ETH (including verification costs)
**Topology:** one shared Safe for the three roles; short delays for rehearsal (`bytecode_hash = "none"`).

> Supersedes the earlier Sepolia deploys (block 11244019 and 11243952). Those addresses are deprecated.
> This deployment was executed inside a Linux Docker container to solve the `via_ir` compilation non-determinism issue between macOS and Etherscan's Linux verifier.

## Addresses

| Contract | Address | Verified | Explorer |
|---|---|---|---|
| **DollarStore proxy** (interact here) | `0x63d7EF051285c14FF54311cdd4Dc246DeD402097` | **yes** | [link](https://sepolia.etherscan.io/address/0x63d7EF051285c14FF54311cdd4Dc246DeD402097) |
| DollarStore implementation | `0x2c5DbDCc7A7AdDE59Cd085F195015432803E1467` | **yes** | [link](https://sepolia.etherscan.io/address/0x2c5DbDCc7A7AdDE59Cd085F195015432803E1467) |
| DLRS token | `0xaD694EC07cCF1e2ABE8D604609c59b095DB0aAaC` | **yes** | [link](https://sepolia.etherscan.io/address/0xaD694EC07cCF1e2ABE8D604609c59b095DB0aAaC) |
| Upgrader timelock | `0x35889DdA205122726a2267aDa0Acfd2ad281e137` | **yes** | [link](https://sepolia.etherscan.io/address/0x35889DdA205122726a2267aDa0Acfd2ad281e137) |
| Governor timelock | `0x18B486A50E935F689bEb4F2d83628b9110B2B3Ba` | **yes** | [link](https://sepolia.etherscan.io/address/0x18B486A50E935F689bEb4F2d83628b9110B2B3Ba) |
| Guardian / Governor / Upgrader Safe (shared) | `0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31` | Safe (EOA) | [link](https://sepolia.etherscan.io/address/0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31) |

## Role wiring (on the proxy)

| Role | Held by | Delay |
|---|---|---|
| `upgrader` | Upgrader timelock `0x35889DdA205122726a2267aDa0Acfd2ad281e137` | 3600s (1h) |
| `governor` | Governor timelock `0x18B486A50E935F689bEb4F2d83628b9110B2B3Ba` | 600s (10m) |
| `guardian` | Safe `0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31` (direct, no timelock) | - |

Both timelocks are proposed/cancelled by the same Safe/EOA `0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31`; execution is open; no external admin.

## Deploy transactions

| What | Tx hash |
|---|---|
| Upgrader timelock | `0x425eae6c3cb9e4128d7a884877eaae02699c6aa301039baa5f4d6808198dbd63` |
| Governor timelock | `0xe70d3c1e8d9bb75b3557b1c8fe43d7bfa72850f0db11ad727890ac7db0b82a5b` |
| DollarStore implementation | `0x23cbcb073cc509de64e88d33fdccdd49cb5059a1119baa9a90ee9c31707754d8` |
| Proxy (+ DLRS via initialize) | `0xfdc4e05b76cf6b9e59d9ec16c8e312a02b37ab80d5d143cbf48a97759a22cc3c` |

---

## Verification Status

**All 5 contracts have been successfully verified on Etherscan.** 

*   **Root cause solved:** Due to macOS vs Linux Yul optimizer compiler non-determinism when `via_ir` is enabled in Solidity (specifically around pointer sorting in `solc` optimization passes), compiling directly on macOS produces a slightly different bytecode than on Etherscan's Linux servers.
*   **Resolution:** We compiled and ran the deploy script inside a standardized `ghcr.io/foundry-rs/foundry:latest` Linux Docker container. This ensured 100% byte-for-byte identical compiled bytecode between the deployed code and Etherscan's re-compilations.

## Sanity checks

```bash
PROXY=0x63d7EF051285c14FF54311cdd4Dc246DeD402097
cast call $PROXY "upgrader()(address)" --rpc-url sepolia   # 0x35889DdA205122726a2267aDa0Acfd2ad281e137
cast call $PROXY "governor()(address)" --rpc-url sepolia   # 0x18B486A50E935F689bEb4F2d83628b9110B2B3Ba
cast call $PROXY "guardian()(address)" --rpc-url sepolia   # 0x19caCb4c0A7fC25598CC44564ED0eCA01249fc31
cast call $PROXY "version()(string)"   --rpc-url sepolia   # 0.8.1-M8.1
```

## Hub assets (Sepolia rehearsal)

**Date:** 2026-07-11. Listed the two mock stables as hub assets (poolId 0) through the governor timelock (schedule -> wait 600s -> execute). Both point at one shared, always-fresh `$1` test feed.

| Contract | Address | Verified | Explorer |
|---|---|---|---|
| **TestnetPriceFeed** (shared `$1`, 8 dp) | `0xc09183D6C4657697B94a4056a98D09345C028341` | yes | [link](https://sepolia.etherscan.io/address/0xc09183D6C4657697B94a4056a98D09345C028341) |

| Asset | Address | poolId | decimals | priceFeed | listed |
|---|---|---|---|---|---|
| Mock USDC | `0x0a9479f7aff770965b3b2D28b29E40C3F6168588` | 0 | 6 | feed above | **yes** |
| Mock USDT | `0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05` | 0 | 6 | feed above | **yes** |

### Listing Transactions

| What | Action | Tx hash |
|---|---|---|
| Mock USDC | Schedule | `0x14c41c8ed8e45114d13d54611ee0aa6e11879d202a80dc52d37e5c1338edaa3b` |
| Mock USDC | Execute | `0x4b5821afe2174cebd0ab6543426c9e73dc024e615bb69b80297e578b8512a1fe` |
| Mock USDT | Schedule | `0x808d6b7bd85a6cf2ea15a047ecb48e2b7188e0711db82ad26ee5cc62ea524fc6` |
| Mock USDT | Execute | `0xe79252ad4ce286a472d3ec379cb7b11ed3025d097daface540dbc5f66435662a` |

Operation ids:
*   USDC: `0x10cb33b4d3883ffcaff1ed827b251a9e3a69b02421ef0cf42e1f2dc1c2684b73`
*   USDT: `0xf012f0185d7f5f3e1ad07f3dd1e238dffe5262a46cdf3a7693cd061551848878`

### Post-listing checks (all pass)

```bash
PROXY=0x63d7EF051285c14FF54311cdd4Dc246DeD402097
USDC=0x0a9479f7aff770965b3b2D28b29E40C3F6168588
USDT=0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05
cast call $PROXY "isAssetListed(address)(bool)"    $USDC --rpc-url sepolia   # true
cast call $PROXY "isAssetListed(address)(bool)"    $USDT --rpc-url sepolia   # true
cast call $PROXY "assetPriceFeed(address)(address)" $USDC --rpc-url sepolia  # 0xc091...8341
cast call $PROXY "assetDecimals(address)(uint8)"    $USDC --rpc-url sepolia  # 6
```

## Seeded liquidity + smoke swap (2026-07-11)

Public faucet `mint` used to fund the deployer, then hub liquidity added and a swap exercised
end-to-end on this deploy. All at the `$1` peg (1:1), confirming deposit -> reserves -> DLRS mint
and a reserve-neutral hub-hub swap.

| Action | Amount | Tx hash |
|---|---|---|
| Mint USDC → deployer | 1,000,000 | `0xbc9b3742f3e8d220b653185103b0fa02712cabcf46136aa7f789188ca802f03d` |
| Mint USDT → deployer | 1,000,000 | `0xbeaff9268c2fc1bc841e5aaa9456bb79aea8c1aa3a2502e2ea7d5c8cae17e153` |
| Approve USDC → proxy | 1,000,000 | `0x96ba421983f7800cf9f80af7a87027c59b1424413861144adadeca345c08b461` |
| Approve USDT → proxy | 1,000,000 | `0xabfcdb9c55b96266bfd11974e27a996f88fc60982abfdfd7197a0551cab74be8` |
| Deposit USDC (hub) | 1,000,000 | `0x5ce6fef7373a324b97c8026a01cbac235f89541094cb85231de67794e7b3a1f6` |
| Deposit USDT (hub) | 1,000,000 | `0xcd1fd3293ca6185a3b3f8f1443f096804d2766f8ddfc8f72db16e2c52e1434b0` |
| Mint USDC (swap test) | 1,000 | `0xb22a9f21e2ae667cfc86f94dcdcc3658a704d39eb144d256c2dc8e132ef503d8` |
| Approve USDC (swap) | 1,000 | `0x6c34e63f5ab9ede8409d17eb49f893f837e6a292bcfb9de4467670760c70fe01` |
| Swap USDC → USDT | 1,000 → 1,000 | `0x6c8b070a78aa9bf5f2a58acc07b28c08937cd4afbee1cee8479fa918e5cb53cf` |

Post-state: DLRS supply `2_000_000_000000` (2M, minted 1:1 on the two deposits); hub reserves
USDC `1_001_000_000000`, USDT `999_000_000000` (swap moved 1k of value 1:1). Swapper received
exactly 1,000 USDT for 1,000 USDC — no slippage at peg.

See `contracts/DEPLOY.md` for the full runbook.
