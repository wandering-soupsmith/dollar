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
    dollarStore: "0x0D748365aA0A38EBaF6Df0C46f0Ebf2D79837c30" as Address,
    dlrs: "0xe78e2CfC18DaB60dbfEEBd83A7562D241Fc295F0" as Address,
    usdc: "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238" as Address,
    usdt: "0xaA8E23Fb1079EA71e0a56F48a2aA51851D8433D0" as Address,
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
