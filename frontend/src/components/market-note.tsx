"use client";

import { Guilloche } from "./guilloche";
import {
  type Market,
  PEG_COLOR,
  PEG_LABEL,
  marketReserve,
  usd,
} from "@/config/markets";

type Props = {
  market: Market;
  active?: boolean;
  onSelect?: (id: string) => void;
};

export function MarketNote({ market, active = false, onSelect }: Props) {
  const isHub = market.kind === "hub";
  const reserve = marketReserve(market);
  const capPct =
    market.launchCap && market.launchCapUsed
      ? Math.min(100, (market.launchCapUsed / market.launchCap) * 100)
      : null;

  return (
    <button
      type="button"
      onClick={() => onSelect?.(market.id)}
      aria-pressed={active}
      className="note group w-full text-left p-5 sm:p-6"
      style={{
        borderColor: active ? "var(--color-dollar-deep)" : undefined,
        boxShadow: active
          ? "0 0 0 1px var(--color-dollar-deep), 0 20px 40px -30px rgba(0,0,0,0.9)"
          : undefined,
      }}
    >
      <div className="guilloche">
        <Guilloche rosette="right" className="w-full h-full" />
      </div>

      {/* corner denomination */}
      <span
        className="denom pointer-events-none absolute right-4 bottom-2 select-none"
        style={{ fontSize: "3.4rem", opacity: 0.12 }}
      >
        $
      </span>

      <div className="relative">
        {/* top rule: classification + serial */}
        <div className="flex items-center justify-between gap-3">
          <span className="eyebrow" style={{ color: isHub ? "var(--color-ivory)" : "var(--color-brass)" }}>
            {isHub ? "Legal Tender" : "Challenger Note"}
          </span>
          <span className="serial">{market.serial}</span>
        </div>

        {/* headline */}
        <div className="mt-4 flex items-end justify-between gap-4">
          <div>
            <h3 className="display-lg text-paper">{market.title}</h3>
            <p className="label mt-1" style={{ letterSpacing: "0.1em" }}>
              {market.issuer}
            </p>
          </div>
          <div className="text-right">
            <div className="num text-paper" style={{ fontSize: "1.35rem" }}>
              {usd(reserve, { compact: true })}
            </div>
            <div className="mt-1 flex items-center justify-end gap-1.5">
              <span className="dot" style={{ background: PEG_COLOR[market.peg] }} />
              <span className="label" style={{ letterSpacing: "0.08em" }}>
                {PEG_LABEL[market.peg]}
              </span>
            </div>
          </div>
        </div>

        {/* footing: hub assets, or spoke certification + cap meter */}
        {isHub ? (
          <div className="mt-5 flex items-center gap-4">
            {market.assets.map((a) => (
              <div key={a.symbol} className="flex items-center gap-2">
                <span className="dot" style={{ background: a.tint }} />
                <span className="num text-muted" style={{ fontSize: "0.8rem" }}>
                  {a.symbol}
                </span>
              </div>
            ))}
            <span className="label ml-auto" style={{ letterSpacing: "0.08em" }}>
              Reserve base
            </span>
          </div>
        ) : (
          <div className="mt-5">
            <div className="flex items-center justify-between gap-3">
              <span className="seal h-8 px-2.5 gap-1.5 text-[0.62rem]" style={{ letterSpacing: "0.12em" }}>
                <SealMark /> CERTIFIED 1:1
              </span>
              {capPct !== null && (
                <span className="label" style={{ letterSpacing: "0.08em" }}>
                  Cap {capPct.toFixed(0)}%
                </span>
              )}
            </div>
            {capPct !== null && (
              <div className="mt-2 h-1 rounded-full bg-forest overflow-hidden">
                <div
                  className="h-full rounded-full"
                  style={{
                    width: `${capPct}%`,
                    background: "linear-gradient(90deg, var(--color-dollar-deep), var(--color-dollar))",
                  }}
                />
              </div>
            )}
          </div>
        )}
      </div>
    </button>
  );
}

function SealMark() {
  return (
    <svg width="11" height="11" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeWidth="1.5" />
      <path d="M8 12.5l2.5 2.5L16 9" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
