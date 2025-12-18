import { Address } from "viem";

// Contract addresses - update these after deployment
export const CONTRACTS = {
  mainnet: {
    dollarStore: "0x0000000000000000000000000000000000000000" as Address,
    dlrs: "0x0000000000000000000000000000000000000000" as Address,
    usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" as Address,
    usdt: "0xdAC17F958D2ee523a2206206994597C13D831ec7" as Address,
  },
  sepolia: {
    dollarStore: "0x707E0f870b89fA941922cb5940Ed05F5A69fb868" as Address,
    dlrs: "0xe93112458C2faea2372599Fa95cB03Aa3c2295f7" as Address,
    usdc: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as Address,
    usdt: "0x7169D38820dfd117C3FA1f22a697dBA58d90BA06" as Address,
  },
} as const;

// Supported stablecoins
export const STABLECOINS = {
  USDC: {
    symbol: "USDC",
    name: "USD Coin",
    decimals: 6,
    logo: "/usdc.svg",
  },
  USDT: {
    symbol: "USDT",
    name: "Tether USD",
    decimals: 6,
    logo: "/usdt.svg",
  },
} as const;

export type StablecoinSymbol = keyof typeof STABLECOINS;
