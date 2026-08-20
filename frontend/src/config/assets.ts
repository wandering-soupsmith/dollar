/**
 * Per-asset landing pages (`dollarstore.world/<SYMBOL>`).
 *
 * This registry is the whole source of truth for an asset page: add an entry and `/<SYMBOL>` starts
 * resolving, with metadata, OG card and static rendering. Nothing is read from the chain, which is
 * deliberate — the one-pagers go out to issuers before the protocol is deployed, so a page has to be
 * publishable ahead of the listing it describes. Whoever adds an entry is asserting that the pairs
 * below are the ones that will be live.
 *
 * When the deployment lands and pages should reflect real listings instead, the swap here is to
 * derive `pairs` from the protocol registry rather than from this file. Nothing else about the page
 * depends on where the list came from.
 */
export type AssetConfig = {
  /** Canonical uppercase symbol. Doubles as the URL path. */
  symbol: string;
  /** Token name, as the issuer writes it. */
  name: string;
  /** Who issues the asset. Named in the hero, the footer and the legal disclaimer. */
  issuer: string;
  /** Network or consortium that distributes the one-pager, shown in the page header. */
  issuerNetwork?: string;
  /** One line for the meta description. */
  description: string;
  /**
   * Counterassets this asset swaps against 1:1, in the order they should read. Every entry becomes
   * one pair in the "What you can swap" strip, so list only routes that are actually going live.
   */
  pairs: string[];
  /**
   * Issuer mark for the page header and the call-to-action badge, as a path under /public. Falls
   * back to a lettered monogram when absent, so a missing file degrades quietly.
   */
  logo?: string;
};

export const ASSETS: AssetConfig[] = [
  {
    symbol: "USDG",
    name: "Global Dollar",
    issuer: "Paxos",
    issuerNetwork: "Global Dollar Network",
    description:
      "Global Dollar (USDG) is issued by Paxos and distributed through the Global Dollar Network.",
    pairs: ["USDC", "USDT", "USDS"],
  },
];

const BY_SYMBOL = new Map(ASSETS.map((a) => [a.symbol, a]));

/** Look up an asset by symbol, case-insensitively. Returns null for anything not whitelisted. */
export function findAsset(symbol: string): AssetConfig | null {
  return BY_SYMBOL.get(symbol.toUpperCase()) ?? null;
}

/** Canonical uppercase symbol for a path segment, or null if we do not publish a page for it. */
export function canonicalSymbol(segment: string): string | null {
  return findAsset(segment)?.symbol ?? null;
}

/** Every symbol that has a page. Drives static generation and the middleware rewrite. */
export const ASSET_SYMBOLS: string[] = ASSETS.map((a) => a.symbol);
