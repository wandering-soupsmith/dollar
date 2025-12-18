import { http, createConfig } from "wagmi";
import { mainnet, sepolia } from "wagmi/chains";
import { injected } from "wagmi/connectors";

export const config = createConfig({
  chains: [mainnet, sepolia],
  connectors: [
    injected(),
    // WalletConnect and Coinbase connectors can be added later
    // They have compatibility issues with Next.js 16 + Turbopack
  ],
  transports: {
    [mainnet.id]: http(
      process.env.NEXT_PUBLIC_MAINNET_RPC_URL ||
        "https://eth-mainnet.g.alchemy.com/v2/demo"
    ),
    [sepolia.id]: http(
      process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL ||
        "https://eth-sepolia.g.alchemy.com/v2/demo"
    ),
  },
});

declare module "wagmi" {
  interface Register {
    config: typeof config;
  }
}
