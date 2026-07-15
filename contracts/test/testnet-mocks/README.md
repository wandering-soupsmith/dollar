# testnet-mocks

Testnet-only mocks, kept in `test/testnet-mocks/` (alongside the other mocks, outside the real
`src/` code). They are not part of the protocol and must never be deployed to mainnet.

> Note: they live under `test/` on purpose. `forge --verify` only resolves the standard-json of
> contracts inside the paths forge indexes (`src`, `test`, `script`). A stray folder at the root of
> `contracts` yields `Error: cannot resolve file at ...`.

Contents:

- `MockStableERC20.sol` - ERC20 with a public `mint` (faucet: anyone can mint) and configurable
  decimals.
- `DeployMockStables.s.sol` - deploys two instances simulating USDC and USDT.

## Decimals

Real USDC and USDT use **6 decimals** on Ethereum. Both mocks are deployed with 6.

## Deployed on Sepolia (2026-07-10)

| Token | Address | Decimals |
|---|---|---|
| Mock USDC | `0x0a9479f7aff770965b3b2D28b29E40C3F6168588` | 6 |
| Mock USDT | `0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05` | 6 |

## Deploy + verify (Sepolia)

From `contracts/`, with the environment loaded (use the same `.env.sepolia` as the main deploy):

```bash
cd contracts
set -a; source .env.sepolia; set +a

forge script test/testnet-mocks/DeployMockStables.s.sol:DeployMockStables \
  --rpc-url sepolia --broadcast --verify
```

## Verify already-deployed contracts (without redeploying)

The mocks are already on-chain; they just need verification. From `contracts/`:

```bash
cd contracts
set -a; source .env.sepolia; set +a

# Mock USDC - constructor("USD Coin (Mock)","USDC",6)
forge verify-contract 0x0a9479f7aff770965b3b2D28b29E40C3F6168588 \
  test/testnet-mocks/MockStableERC20.sol:MockStableERC20 --chain sepolia --watch \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "USD Coin (Mock)" "USDC" 6)

# Mock USDT - constructor("Tether USD (Mock)","USDT",6)
forge verify-contract 0x2F906e2AEE73e28C76c487912D4Aa4dDd64C2C05 \
  test/testnet-mocks/MockStableERC20.sol:MockStableERC20 --chain sepolia --watch \
  --constructor-args $(cast abi-encode "constructor(string,string,uint8)" "Tether USD (Mock)" "USDT" 6)
```

## Using the faucet

```bash
# mint 1000 USDC (6 decimals) to an address
cast send 0x0a9479f7aff770965b3b2D28b29E40C3F6168588 "mint(address,uint256)" <YOUR_ADDR> 1000000000 \
  --rpc-url sepolia --private-key $DEPLOYER_PRIVATE_KEY

# or mint to yourself
cast send 0x0a9479f7aff770965b3b2D28b29E40C3F6168588 "mint(uint256)" 1000000000 \
  --rpc-url sepolia --private-key $DEPLOYER_PRIVATE_KEY
```
