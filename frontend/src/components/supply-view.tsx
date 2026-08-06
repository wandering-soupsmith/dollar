"use client";

import { useMemo, useState } from "react";
import {
  MARKETS,
  TINT,
  getMarket,
  poolComposition,
  poolQueue,
  splitQueueForAsset,
  usd,
  type Position,
} from "@/config/markets";

export function SupplyView() {
  const [marketId, setMarketId] = useState("pyusd");
  const [mode, setMode] = useState<"deposit" | "redeem">("deposit");
  const [amount, setAmount] = useState("");
  const market = getMarket(marketId);

  const { holdings, total } = poolComposition(market);
  const assets = market.assets.map((a) => a.symbol);
  const [asset, setAsset] = useState(assets[0]);
  const validAsset = useMemo(() => (assets.includes(asset) ? asset : assets[0]), [assets, asset]);
  const amt = Number(amount) || 0;

  const positions = poolQueue(market.id);
  const spokeAsset = market.kind === "spoke" ? market.assets[0].symbol : null;

  return (
    <div className="max-w-[1180px] mx-auto px-6 pt-12 pb-20">
      <section className="rise">
        <span className="eyebrow">Supply</span>
        <h1 className="display-lg text-paper mt-3">Provide liquidity to a pool</h1>
        <p className="text-muted mt-2 max-w-xl leading-relaxed">
          Deposit into a pool to back its swaps and earn issuer rewards. Inspect what the pool holds and
          the queue moving through it.
        </p>
      </section>

      {/* Pool selector */}
      <section className="mt-7">
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

      {/* Composition + deposit */}
      <section className="mt-5 grid lg:grid-cols-[1fr_0.8fr] gap-4 items-start">
        {/* Composition */}
        <div className="note p-6 sm:p-7">
          <div className="relative">
            <div className="flex items-center justify-between">
              <span className="eyebrow">{market.title} pool</span>
              <span className="label" style={{ letterSpacing: "0.08em" }}>
                {market.kind === "hub" ? "Core reserve" : "Issuer pool"}
              </span>
            </div>

            <div className="mt-5">
              <div className="num text-paper" style={{ fontSize: "2.1rem" }}>
                {usd(total, { compact: true })}
              </div>
              <div className="label mt-1">Total value in pool</div>
            </div>

            {/* Stacked composition bar */}
            <div className="mt-5 flex h-2.5 rounded-full overflow-hidden bg-forest">
              {holdings.map((h) => (
                <div key={h.symbol} style={{ width: `${(h.amount / total) * 100}%`, background: h.tint }} />
              ))}
            </div>

            {/* Holdings breakdown */}
            <div className="mt-5 space-y-3">
              {holdings.map((h) => (
                <div key={h.symbol} className="flex items-center gap-3">
                  <span className="dot" style={{ background: h.tint }} />
                  <span className="text-paper text-sm">{h.label}</span>
                  <span className="label ml-auto" style={{ letterSpacing: "0.06em" }}>
                    {((h.amount / total) * 100).toFixed(0)}%
                  </span>
                  <span className="num text-paper text-sm w-24 text-right">{usd(h.amount, { compact: true })}</span>
                </div>
              ))}
            </div>
          </div>
        </div>

        {/* Deposit / redeem */}
        <div className="note p-6 sm:p-7">
          <div className="relative">
            <div className="well inline-flex p-1 gap-1">
              {(["deposit", "redeem"] as const).map((m) => (
                <button key={m} type="button" onClick={() => setMode(m)} className="chip px-4 py-1.5" data-active={mode === m}>
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
                  aria-label="Amount"
                />
              </div>
            </div>

            <div className="mt-4 space-y-2.5">
              <Row
                label={mode === "deposit" ? "You receive" : "You return"}
                value={`${amt.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })} DLRS`}
              />
              <Row label="Redeemable" value="1 : 1" />
              <Row label="Fee" value="None" />
            </div>

            <button type="button" disabled={amt <= 0} className="btn-primary w-full py-3.5 mt-5 text-[0.95rem]">
              {amt <= 0 ? "Enter an amount" : mode === "deposit" ? `Deposit ${validAsset}` : `Redeem ${validAsset}`}
            </button>
          </div>
        </div>
      </section>

      {/* Queue moving through the pool */}
      <section className="mt-4 note p-6 sm:p-7">
        <div className="relative">
          <div className="flex items-center justify-between mb-5">
            <span className="eyebrow">Queue · {market.title}</span>
            <span className="label" style={{ letterSpacing: "0.08em" }}>
              {usd(market.queueDepth, { compact: true })} waiting
            </span>
          </div>

          {spokeAsset ? (
            <SpokeQueue positions={positions} asset={spokeAsset} />
          ) : (
            <QueueColumn title="All positions" positions={positions} highlight={null} />
          )}
        </div>
      </section>
    </div>
  );
}

function SpokeQueue({ positions, asset }: { positions: Position[]; asset: string }) {
  const { wanting, offering } = splitQueueForAsset(positions, asset);
  return (
    <div className="grid md:grid-cols-2 gap-x-8 gap-y-2">
      <QueueColumn title={`Wants ${asset}`} sub="offering, to receive it" positions={wanting} highlight={asset} />
      <QueueColumn title={`Offers ${asset}`} sub="wanting, in return" positions={offering} highlight={asset} />
    </div>
  );
}

function QueueColumn({
  title,
  sub,
  positions,
  highlight,
}: {
  title: string;
  sub?: string;
  positions: Position[];
  highlight: string | null;
}) {
  return (
    <div>
      <div className="flex items-baseline justify-between pb-2 border-b border-hairline-strong">
        <span className="label" style={{ letterSpacing: "0.1em" }}>
          {title}
        </span>
        <span className="serial">{positions.length} pos</span>
      </div>
      {sub && <p className="label mt-2" style={{ letterSpacing: "0.04em", textTransform: "none" }}>{sub}</p>}
      {positions.length === 0 ? (
        <p className="text-muted text-sm py-4">No positions.</p>
      ) : (
        <ul className="mt-1">
          {positions.map((p, i) => (
            <li key={i} className="flex items-center gap-2 py-2.5">
              <Token symbol={p.offer} dim={p.offer === highlight} />
              <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden="true" className="text-faint shrink-0">
                <path d="M5 12h14M13 6l6 6-6 6" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              <Token symbol={p.want} dim={p.want === highlight} />
              <span className="num text-paper text-sm ml-auto">{usd(p.amount)}</span>
              <span className="label w-8 text-right">{p.ago}</span>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function Token({ symbol, dim }: { symbol: string; dim?: boolean }) {
  return (
    <span className="inline-flex items-center gap-1.5 shrink-0" style={{ opacity: dim ? 0.55 : 1 }}>
      <span className="dot" style={{ background: TINT[symbol] }} />
      <span className="num text-paper text-sm">{symbol}</span>
    </span>
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
