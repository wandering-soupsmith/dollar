// Mock market data for the visual shell. No contract wiring — these figures exist only to make the
// interface feel alive while we iterate on design and the hub/spoke model with Nick. Amounts are in
// whole dollars. Replace with the on-chain data layer during the migration (see FRONTEND-MIGRATION).

export type PegStatus = "on-peg" | "watch" | "off-peg";

export type Asset = {
  symbol: string;
  name: string;
  reserve: number; // dollars currently held in reserve for this asset
  tint: string; // brand dot color
};

export type Market = {
  id: string;
  kind: "hub" | "spoke";
  serial: string; // note-style serial number
  title: string; // note headline
  issuer: string; // who stands behind it
  assets: Asset[];
  peg: PegStatus;
  queueDepth: number; // dollars waiting to fill
  minOrder: number; // minimum to join the queue
  volume24h: number;
  // spoke-only
  certifiedAt?: string; // "certified 1:1" date
  launchCap?: number; // current cap on the spoke
  launchCapUsed?: number; // how much of the cap is used
  dlrsReserve?: number; // internal DLRS paired against the spoke asset
};

export const HUB: Market = {
  id: "hub",
  kind: "hub",
  serial: "SN 0000-0001-USD",
  title: "Legal Tender",
  issuer: "Dollar Store reserve",
  peg: "on-peg",
  queueDepth: 128_400,
  minOrder: 100,
  volume24h: 4_182_500,
  assets: [
    { symbol: "USDC", name: "USD Coin", reserve: 3_420_180, tint: "#2775CA" },
    { symbol: "USDT", name: "Tether USD", reserve: 2_980_640, tint: "#26A17B" },
  ],
};

export const SPOKES: Market[] = [
  {
    id: "rlusd",
    kind: "spoke",
    serial: "SN 0001-0007-RLU",
    title: "RLUSD",
    issuer: "Ripple",
    peg: "on-peg",
    certifiedAt: "2026-07-18",
    queueDepth: 42_100,
    minOrder: 250,
    volume24h: 986_300,
    launchCap: 1_500_000,
    launchCapUsed: 910_500,
    dlrsReserve: 910_500,
    assets: [{ symbol: "RLUSD", name: "Ripple USD", reserve: 910_500, tint: "#0aa5ff" }],
  },
  {
    id: "pyusd",
    kind: "spoke",
    serial: "SN 0001-0012-PYU",
    title: "PYUSD",
    issuer: "PayPal",
    peg: "watch",
    certifiedAt: "2026-06-30",
    queueDepth: 8_750,
    minOrder: 250,
    volume24h: 214_900,
    launchCap: 750_000,
    launchCapUsed: 402_300,
    dlrsReserve: 402_300,
    assets: [{ symbol: "PYUSD", name: "PayPal USD", reserve: 402_300, tint: "#c0b6f2" }],
  },
  {
    id: "usdg",
    kind: "spoke",
    serial: "SN 0001-0019-USG",
    title: "USDG",
    issuer: "Global Dollar Network",
    peg: "on-peg",
    certifiedAt: "2026-07-02",
    queueDepth: 0,
    minOrder: 250,
    volume24h: 61_200,
    launchCap: 500_000,
    launchCapUsed: 118_000,
    dlrsReserve: 118_000,
    assets: [{ symbol: "USDG", name: "Global Dollar", reserve: 118_000, tint: "#d9b45a" }],
  },
];

export const MARKETS: Market[] = [HUB, ...SPOKES];

export function getMarket(id: string): Market {
  return MARKETS.find((m) => m.id === id) ?? HUB;
}

export function marketReserve(m: Market): number {
  return m.assets.reduce((sum, a) => sum + a.reserve, 0);
}

export const TOTAL_SUPPLY = MARKETS.reduce((sum, m) => sum + marketReserve(m), 0);
export const TOTAL_VOLUME_24H = MARKETS.reduce((sum, m) => sum + m.volume24h, 0);

// ---- Token + routing model (drives the unified swap) ----
export type TokenKind = "hub" | "spoke";
export type TokenInfo = { symbol: string; name: string; tint: string; kind: TokenKind; marketId: string };

export const TOKENS: TokenInfo[] = [
  { symbol: "USDC", name: "USD Coin", tint: "#2775CA", kind: "hub", marketId: "hub" },
  { symbol: "USDT", name: "Tether USD", tint: "#26A17B", kind: "hub", marketId: "hub" },
  ...SPOKES.map((s) => ({
    symbol: s.assets[0].symbol,
    name: s.assets[0].name,
    tint: s.assets[0].tint,
    kind: "spoke" as const,
    marketId: s.id,
  })),
];

export function token(symbol: string): TokenInfo {
  return TOKENS.find((t) => t.symbol === symbol) ?? TOKENS[0];
}

export const TINT: Record<string, string> = {
  ...Object.fromEntries(TOKENS.map((t) => [t.symbol, t.tint])),
  DLRS: "#85bb65",
};

// Reserve available to pay OUT a given token right now (mock).
export function availableOut(symbol: string): number {
  const t = token(symbol);
  if (t.kind === "hub") return HUB.assets.find((a) => a.symbol === symbol)?.reserve ?? 0;
  return marketReserve(getMarket(t.marketId));
}

export type LegKind = "HubToHub" | "HubToSpoke" | "SpokeToHub";
export type Leg = { from: string; to: string; kind: LegKind; available: number };
export type SwapRoute = { kind: "direct" | "via-hub"; legs: Leg[]; via?: string };

// The hub asset a spoke->spoke route hops through. In the real router this is picked by deepest
// reserve / the pairing; the shell keeps it simple.
const HUB_HOP = "USDC";

export function routeFor(from: string, to: string): SwapRoute {
  const f = token(from);
  const t = token(to);
  const legKind = (a: TokenInfo, b: TokenInfo): LegKind =>
    a.kind === "hub" && b.kind === "hub" ? "HubToHub" : a.kind === "hub" ? "HubToSpoke" : "SpokeToHub";

  // Direct: any pair touching the hub (hub<->hub, hub<->spoke) is a single on-chain route.
  if (f.kind === "hub" || t.kind === "hub") {
    return { kind: "direct", legs: [{ from, to, kind: legKind(f, t), available: availableOut(to) }] };
  }
  // Spoke -> spoke: rejected on-chain, so route through the hub as two legs (needs the periphery router).
  return {
    kind: "via-hub",
    via: HUB_HOP,
    legs: [
      { from, to: HUB_HOP, kind: "SpokeToHub", available: availableOut(HUB_HOP) },
      { from: HUB_HOP, to, kind: "HubToSpoke", available: availableOut(to) },
    ],
  };
}

// Amount the whole route can settle instantly. For a via-hub route the atomic router needs BOTH legs
// to fill, so capacity is the tighter leg.
export function routeCapacity(route: SwapRoute): number {
  return Math.min(...route.legs.map((l) => l.available));
}

export const PEG_LABEL: Record<PegStatus, string> = {
  "on-peg": "On peg",
  watch: "Watch",
  "off-peg": "Off peg",
};

export const PEG_COLOR: Record<PegStatus, string> = {
  "on-peg": "var(--color-dollar)",
  watch: "var(--color-brass)",
  "off-peg": "var(--color-error)",
};

// Shared formatting for the shell.
export function usd(n: number, opts: { compact?: boolean; cents?: boolean } = {}): string {
  const { compact = false, cents = false } = opts;
  if (compact && Math.abs(n) >= 1000) {
    if (Math.abs(n) >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
    return `$${(n / 1000).toFixed(1)}K`;
  }
  return `$${n.toLocaleString("en-US", {
    minimumFractionDigits: cents ? 2 : 0,
    maximumFractionDigits: cents ? 2 : 0,
  })}`;
}
