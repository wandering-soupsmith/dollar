# Deployment - Testnet mocks (USDC / USDT)

**Network:** Sepolia (chain id 11155111)
**Date:** 2026-07-10
**Block:** 11244130
**Script:** `test/testnet-mocks/DeployMockStables.s.sol:DeployMockStables`
**Total gas paid:** 0.001143488375584736 ETH (1116088 gas @ avg 1.024550372 gwei)
**Purpose:** faucet ERC20 mocks with a public `mint` to simulate USDC and USDT in the rehearsal.
Testnet only; not part of the real `src/` protocol.

## Addresses

| Contract | Address | Decimals | Verified | Explorer |
|---|---|---|---|---|
| Mock USDC | `0x0a9479f7aff770965b3b2D28b29E40C3F6168588` | 6 | yes | [link](https://sepolia.etherscan.io/address/0x0a9479f7aff770965b3b2D28b29E40C3F6168588#code) |
| Mock USDT | `0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05` | 6 | yes | [link](https://sepolia.etherscan.io/address/0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05#code) |

Decimals = 6 on both, same as real USDC/USDT on Ethereum.

## Deploy transactions

| What | Tx hash | Gas | Cost |
|---|---|---|---|
| Mock USDC | `0x24408be83eaa9315d50a43f6a3f092dce2a1836ccabc3878de47c38191df3e0b` | 558032 | 0.000571731893187904 ETH |
| Mock USDT | `0xeb3d34ac2c0ddfdfeafb30cdc73891e622bdb8b7942c91bc90a2ace3054c2753` | 558056 | 0.000571756482396832 ETH |

## Constructor args

| Token | name | symbol | decimals |
|---|---|---|---|
| Mock USDC | `USD Coin (Mock)` | `USDC` | 6 |
| Mock USDT | `Tether USD (Mock)` | `USDT` | 6 |

## Verification

Both contracts **verified** on Etherscan (2026-07-10).

The automatic `--verify` on the first run failed with
`Error: cannot resolve file at ...testnet-mocks/MockStableERC20.sol` because the contract was in a
stray folder at the root of `contracts`, outside the paths forge indexes. Once moved under
`test/testnet-mocks/`, manual verification (without redeploying) passed:

```bash
cd contracts
set -a; source .env.sepolia; set +a

forge verify-contract 0x0a9479f7aff770965b3b2D28b29E40C3F6168588 \
  test/testnet-mocks/MockStableERC20.sol:MockStableERC20 --chain sepolia --watch \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin (Mock)" "USDC" 6)

forge verify-contract 0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05 \
  test/testnet-mocks/MockStableERC20.sol:MockStableERC20 --chain sepolia --watch \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Tether USD (Mock)" "USDT" 6)
```

## Sanity checks

```bash
USDC=0x0a9479f7aff770965b3b2D28b29E40C3F6168588
USDT=0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05
cast call $USDC "symbol()(string)"   --rpc-url sepolia   # USDC
cast call $USDC "decimals()(uint8)"  --rpc-url sepolia   # 6
cast call $USDT "symbol()(string)"   --rpc-url sepolia   # USDT
cast call $USDT "decimals()(uint8)"  --rpc-url sepolia   # 6
```
