"use client";

import { useMemo, useState } from "react";
import {
  HUB,
  MARKETS,
  getMarket,
  marketReserve,
  usd,
} from "@/config/markets";

const TINT: Record<string, string> = {
  USDC: "#2775CA",
  USDT: "#26A17B",
  RLUSD: "#0aa5ff",
  PYUSD: "#c0b6f2",
  USDG: "#d9b45a",
  DLRS: "#85BB65",
};

export function SupplyView() {
  const [marketId, setMarketId] = useState("hub");
  const [mode, setMode] = useState<"deposit" | "redeem">("deposit");
  const [amount, setAmount] = useState("");
  const market = getMarket(marketId);

  const assets = market.assets.map((a) => a.symbol);
  const [asset, setAsset] = useState(assets[0]);
  // keep asset valid when market changes
  const validAsset = useMemo(() => (assets.includes(asset) ? asset : assets[0]), [assets, asset]);

  const amt = Number(amount) || 0;

  return (
    <div className="max-w-[1180px] mx-auto px-6 pt-14 pb-20">
      <section className="rise">
        <span className="eyebrow">Supply</span>
        <h1 className="display-hero text-paper mt-4">Back the counter</h1>
        <p className="text-muted mt-4 max-w-xl leading-relaxed">
          Deposit dollars into a market&apos;s reserve to back its swaps and earn issuer rewards.
          Redeem your receipt one-to-one, any time reserves allow.
        </p>
      </section>

      {/* Market selector */}
      <section className="mt-8">
        <h2 className="label mb-3" style={{ letterSpacing: "0.16em" }}>
          Choose a market
        </h2>
        <div className="flex flex-wrap gap-2">
          {MARKETS.map((m) => (
            <button
              key={m.id}
              type="button"
              onClick={() => setMarketId(m.id)}
              className="chip px-3.5 py-2"
              data-active={m.id === marketId}
            >
              {m.title}
            </button>
          ))}
        </div>
      </section>

      <section className="mt-6 grid lg:grid-cols-[1fr_0.85fr] gap-4 items-start">
        {/* Deposit / redeem panel */}
        <div className="note p-6">
          <div className="relative">
            {/* mode toggle */}
            <div className="well inline-flex p-1 gap-1">
              {(["deposit", "redeem"] as const).map((m) => (
                <button
                  key={m}
                  type="button"
                  onClick={() => setMode(m)}
                  className="chip px-4 py-1.5"
                  data-active={mode === m}
                >
                  {m}
                </button>
              ))}
            </div>

            <div className="mt-5">
              <div className="flex items-center justify-between mb-2">
                <span className="label">{mode === "deposit" ? "You deposit" : "You redeem"}</span>
                <span className="label">Balance —</span>
              </div>
              <div className="well flex items-center gap-3 px-4 py-3.5">
                {assets.length > 1 ? (
                  <div className="inline-flex gap-1 shrink-0">
                    {assets.map((s) => (
                      <button
                        key={s}
                        type="button"
                        onClick={() => setAsset(s)}
                        className="inline-flex items-center gap-1.5 rounded-md border px-2.5 py-1.5"
                        style={{
                          borderColor: validAsset === s ? "var(--color-dollar-deep)" : "var(--color-hairline-strong)",
                          background: validAsset === s ? "rgba(133,187,101,0.08)" : "transparent",
                        }}
                      >
                        <span className="dot" style={{ background: TINT[s] }} />
                        <span className="num text-paper text-sm">{s}</span>
                      </button>
                    ))}
                  </div>
                ) : (
                  <span className="inline-flex items-center gap-2 shrink-0 rounded-md border border-hairline-strong px-3 py-2">
                    <span className="dot" style={{ background: TINT[validAsset] }} />
                    <span className="num text-paper text-sm">{validAsset}</span>
                  </span>
                )}
                <input
                  inputMode="decimal"
                  placeholder="0.00"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
                  className="num flex-1 min-w-0 bg-transparent text-right text-2xl text-paper outline-none placeholder:text-faint"
                />
              </div>
            </div>

            {/* receipt readout */}
            <div className="mt-4 space-y-2.5">
              <Row label={mode === "deposit" ? "You receive" : "You return"} value={`${amt.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ${market.kind === "hub" ? "DLRS" : market.title + " receipt"}`} />
              <Row label="Redeemable" value="1 : 1" />
              <Row label="Fee" value="None" />
            </div>

            <button type="button" disabled={amt <= 0} className="btn-primary w-full py-3.5 mt-5 text-[0.95rem]">
              {amt <= 0 ? "Enter an amount" : mode === "deposit" ? `Deposit ${validAsset}` : `Redeem ${validAsset}`}
            </button>
          </div>
        </div>

        {/* Position + market facts */}
        <div className="space-y-4">
          <div className="note p-6">
            <div className="relative">
              <span className="eyebrow">Your position</span>
              <div className="grid place-items-center text-center py-8">
                <div>
                  <p className="text-paper text-sm">No supply yet</p>
                  <p className="label mt-1.5">Connect a wallet to deposit</p>
                </div>
              </div>
            </div>
          </div>

          <div className="note p-6">
            <div className="relative">
              <span className="eyebrow">{market.title} reserve</span>
              <div className="mt-4 num text-paper" style={{ fontSize: "1.7rem" }}>
                {usd(marketReserve(market), { compact: true })}
              </div>
              <div className="mt-4 space-y-2.5">
                <Row label="24h volume" value={usd(market.volume24h, { compact: true })} />
                <Row label="In fill queue" value={usd(market.queueDepth, { compact: true })} />
                {market.kind === "spoke" && market.launchCap && (
                  <Row label="Launch cap" value={usd(market.launchCap, { compact: true })} />
                )}
              </div>
            </div>
          </div>
        </div>
      </section>

      <p className="mt-8 label" style={{ letterSpacing: "0.1em" }}>
        Hub · {usd(marketReserve(HUB), { compact: true })} reserve base
      </p>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="label">{label}</span>
      <span className="num text-paper">{value}</span>
    </div>
  );
}
