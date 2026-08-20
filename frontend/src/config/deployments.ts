/**
 * Which network the asset landing pages announce.
 *
 * The pages are published ahead of the deployment they describe, so this label is asserted here
 * rather than read from a contract. Switching to mainnet, or back to a testnet label for a
 * rehearsal, is this one constant.
 *
 * Protocol addresses live in `contracts.ts`; nothing on these pages reads them.
 */
export type NetworkBadge = {
  /** Small line above the network name, e.g. "Live on". */
  prefix: string;
  /** The network itself, e.g. "Ethereum mainnet". */
  network: string;
};

export const NETWORK_BADGE: NetworkBadge = {
  prefix: "Live on",
  network: "Ethereum mainnet",
};
