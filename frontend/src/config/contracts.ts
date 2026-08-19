import { Address } from "viem";

/**
 * The DollarStore protocol is not deployed to any network yet, so it has no address.
 *
 * Nothing may link to, or call, an address that does not exist. Guard on `IS_DEPLOYED`
 * before rendering an explorer link or wiring a contract read. Fill the tables below in
 * (and flip `IS_DEPLOYED`) as part of the deployment, using the addresses published in
 * the docs — that page is the canonical source.
 */
export const UNDEPLOYED = "0x0000000000000000000000000000000000000000" as Address;

/** Whether the protocol has a live deployment on any supported network. */
export const IS_DEPLOYED = false;

// Protocol contracts, per network. Both are pending deployment.
export const CONTRACTS = {
  mainnet: {
    dollarStore: UNDEPLOYED,
    dlrs: UNDEPLOYED,
    // Canonical mainnet token addresses (not ours — these exist independently of our deploy).
    usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" as Address,
    usdt: "0xdAC17F958D2ee523a2206206994597C13D831ec7" as Address,
  },
  sepolia: {
    dollarStore: UNDEPLOYED,
    dlrs: UNDEPLOYED,
    // Testnet mocks are published together with the testnet deployment.
    usdc: UNDEPLOYED,
    usdt: UNDEPLOYED,
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

/**
 * The OpenZeppelin audit reports, newest first. `current` is the one to surface: it covers
 * the v3 hub-and-spoke protocol that is in the repo today. The March report audited the
 * earlier single-pool design and is kept for the record, not as the current review.
 */
export const AUDITS = {
  current: {
    href: "/dollarstore-audit-openzeppelin-2.pdf",
    label: "DollarStore V3 Audit",
    date: "August 2026",
  },
  previous: {
    href: "/dollarstore-audit-openzeppelin.pdf",
    label: "DollarStore Audit",
    date: "March 2026",
  },
} as const;
