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
  listedAt?: string; // date the spoke was listed
  launchCap?: number; // current cap on the spoke
  launchCapUsed?: number; // how much of the cap is used
  dlrsReserve?: number; // internal DLRS paired against the spoke asset
};

export const HUB: Market = {
  id: "hub",
  kind: "hub",
  serial: "SN 0000-0001-USD",
  title: "Core",
  issuer: "Dollar Store reserve",
  peg: "on-peg",
  queueDepth: 128_400,
  minOrder: 500,
  volume24h: 4_182_500,
  assets: [
    { symbol: "USDC", name: "USD Coin", reserve: 3_420_180, tint: "#2775CA" },
    { symbol: "USDS", name: "USDS", reserve: 2_980_640, tint: "#f4b731" },
  ],
};

export const SPOKES: Market[] = [
  {
    id: "usdt",
    kind: "spoke",
    serial: "SN 0001-0001-UST",
    title: "USDT",
    issuer: "Tether",
    peg: "on-peg",
    listedAt: "2026-08-20",
    queueDepth: 61_800,
    minOrder: 500,
    volume24h: 1_842_700,
    launchCap: 2_000_000,
    launchCapUsed: 1_284_400,
    dlrsReserve: 1_284_400,
    assets: [{ symbol: "USDT", name: "Tether USD", reserve: 1_284_400, tint: "#26A17B" }],
  },
  {
    id: "rlusd",
    kind: "spoke",
    serial: "SN 0001-0007-RLU",
    title: "RLUSD",
    issuer: "Ripple",
    peg: "on-peg",
    listedAt: "2026-07-18",
    queueDepth: 42_100,
    minOrder: 500,
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
    listedAt: "2026-06-30",
    queueDepth: 8_750,
    minOrder: 500,
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
    listedAt: "2026-07-02",
    queueDepth: 0,
    minOrder: 500,
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
  { symbol: "USDS", name: "USDS", tint: "#f4b731", kind: "hub", marketId: "hub" },
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

// ---- Pool composition + queue positions (drives the Supply / LP view) ----
export type Holding = { label: string; symbol: string; amount: number; tint: string };

// What a pool actually holds: for a spoke, the spoke asset plus the internal DLRS (hub receipt) it is
// paired against; for the hub, its core dollar reserves.
export function poolComposition(m: Market): { holdings: Holding[]; total: number } {
  let holdings: Holding[];
  if (m.kind === "hub") {
    holdings = m.assets.map((a) => ({ label: a.name, symbol: a.symbol, amount: a.reserve, tint: a.tint }));
  } else {
    const a = m.assets[0];
    holdings = [
      { label: `${a.symbol} · spoke asset`, symbol: a.symbol, amount: a.reserve, tint: a.tint },
      { label: "DLRS · hub receipt", symbol: "DLRS", amount: m.dlrsReserve ?? 0, tint: TINT.DLRS },
    ];
  }
  const total = holdings.reduce((s, h) => s + h.amount, 0);
  return { holdings, total };
}

// A queued FIFO position: someone offering `offer` who wants `want`.
export type Position = { offer: string; want: string; amount: number; ago: string };

export const POSITIONS: Record<string, Position[]> = {
  hub: [
    { offer: "USDC", want: "USDS", amount: 42_000, ago: "3m" },
    { offer: "USDS", want: "USDC", amount: 28_500, ago: "12m" },
    { offer: "USDC", want: "USDS", amount: 9_800, ago: "37m" },
  ],
  usdt: [
    { offer: "USDC", want: "USDT", amount: 22_000, ago: "5m" },
    { offer: "USDT", want: "USDC", amount: 15_400, ago: "19m" },
    { offer: "USDS", want: "USDT", amount: 8_600, ago: "48m" },
  ],
  rlusd: [
    { offer: "USDC", want: "RLUSD", amount: 18_000, ago: "2m" },
    { offer: "USDT", want: "RLUSD", amount: 6_500, ago: "24m" },
    { offer: "RLUSD", want: "USDC", amount: 12_400, ago: "9m" },
    { offer: "RLUSD", want: "USDT", amount: 5_200, ago: "41m" },
  ],
  pyusd: [
    { offer: "USDC", want: "PYUSD", amount: 4_000, ago: "6m" },
    { offer: "PYUSD", want: "USDC", amount: 4_750, ago: "14m" },
  ],
  usdg: [],
};

export function poolQueue(marketId: string): Position[] {
  return POSITIONS[marketId] ?? [];
}

// Split a spoke pool's queue by direction relative to its own asset.
export function splitQueueForAsset(positions: Position[], asset: string) {
  return {
    wanting: positions.filter((p) => p.want === asset), // people who want the asset (and what they offer)
    offering: positions.filter((p) => p.offer === asset), // people offering the asset (and what they want)
  };
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
    const [div, suffix] = Math.abs(n) >= 1_000_000 ? [1_000_000, "M"] : [1000, "K"];
    const v = Number((n / div).toFixed(2)); // trims trailing zeros: 500.00 -> 500, 1.50 -> 1.5
    return `$${v}${suffix}`;
  }
  return `$${n.toLocaleString("en-US", {
    minimumFractionDigits: cents ? 2 : 0,
    maximumFractionDigits: cents ? 2 : 0,
  })}`;
}
