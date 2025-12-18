# Phase 8: Deploy & Launch

## 1. Smart Contract Deployment

### Testnet (Sepolia) first:
- Deploy DLRS token contract
- Deploy DollarStore main contract
- Verify contracts on Etherscan
- Update frontend with deployed addresses in `frontend/src/config/contracts.ts`
- Test all flows end-to-end on testnet

### Mainnet:
- Deploy with production wallet (multisig recommended)
- Verify contracts on Etherscan
- Update mainnet addresses in contracts.ts

### Requirements:
- Deployer wallet with ETH for gas
- RPC endpoints (Alchemy/Infura)
- Etherscan API key for verification

---

## 2. Frontend Deployment

### Options:
- **Vercel** (recommended for Next.js) - connect GitHub repo, auto-deploys
- **Netlify** - similar to Vercel
- **Self-hosted** - build and serve static files

### Environment variables needed:
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` - get from cloud.walletconnect.com
- `NEXT_PUBLIC_MAINNET_RPC_URL` - Alchemy/Infura endpoint
- `NEXT_PUBLIC_SEPOLIA_RPC_URL` - testnet endpoint

---

## 3. Domain Setup

- Point dollarstore.world DNS to hosting provider
- Configure SSL certificate (usually automatic with Vercel/Netlify)

---

## 4. Pre-Launch Checklist

- [ ] Contracts audited (or documented as unaudited)
- [ ] Testnet testing complete
- [ ] Contract addresses updated for mainnet
- [ ] WalletConnect project ID configured
- [ ] RPC endpoints configured
- [ ] Domain DNS configured
- [ ] Social links updated (GitHub, etc.)

---

## 5. Optional Enhancements

- Add more wallet connectors (WalletConnect, Coinbase)
- Analytics (Plausible, Fathom)
- Error tracking (Sentry)

---

## Recommended Order

1. Get a WalletConnect Project ID from cloud.walletconnect.com
2. Deploy contracts to Sepolia testnet
3. Test everything end-to-end on testnet
4. Deploy contracts to mainnet
5. Deploy frontend to Vercel/Netlify
6. Configure domain DNS
