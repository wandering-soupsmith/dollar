"use client";

import Link from "next/link";
import {
  HUB,
  SPOKES,
  TOTAL_SUPPLY,
  TOTAL_VOLUME_24H,
  usd,
} from "@/config/markets";
import { MarketNote } from "./market-note";
import { SwapConsole } from "./swap-console";

const STEPS = [
  {
    n: "I",
    title: "Select",
    body: "Pick any pair — hub dollars or certified issuer notes. All trade at par.",
  },
  {
    n: "II",
    title: "Settle",
    body: "If reserves cover it, the swap settles instantly at exactly 1:1. No spread, no fee, no slippage.",
  },
  {
    n: "III",
    title: "Queue",
    body: "If reserves run short, your position joins the FIFO queue and fills the moment opposing liquidity lands.",
  },
];

export function SwapView() {
  return (
    <div className="max-w-[1180px] mx-auto px-6 pb-20">
      {/* Compact hero — the tool sits right under it */}
      <section className="pt-10 pb-6 rise">
        <div className="flex flex-col lg:flex-row lg:items-end justify-between gap-6">
          <div>
            <span className="eyebrow">Stablecoin Exchange · Ethereum</span>
            <h1 className="display-lg text-paper mt-3">
              Every dollar is worth <span style={{ color: "var(--color-dollar)" }}>a dollar</span>.
            </h1>
            <p className="text-muted mt-2 max-w-lg leading-relaxed">
              Swap USDC, USDT and certified issuer stablecoins one-to-one — no fees, no slippage.
            </p>
          </div>
          <div className="flex items-center gap-6 shrink-0">
            <Stat label="In reserve" value={usd(TOTAL_SUPPLY, { compact: true })} />
            <span className="w-px h-9 bg-hairline-strong" />
            <Stat label="24h volume" value={usd(TOTAL_VOLUME_24H, { compact: true })} />
            <span className="w-px h-9 bg-hairline-strong" />
            <Stat label="Markets" value={String(1 + SPOKES.length)} />
          </div>
        </div>
      </section>

      {/* Primary tool */}
      <SwapConsole />

      {/* Markets — browse the notes (secondary) */}
      <section className="mt-14">
        <div className="flex items-baseline justify-between mb-4">
          <h2 className="label" style={{ letterSpacing: "0.16em" }}>
            The counter — markets
          </h2>
          <Link href="/markets" className="label hover:text-dollar-bright" style={{ letterSpacing: "0.1em" }}>
            All markets →
          </Link>
        </div>
        <div className="grid lg:grid-cols-2 gap-4">
          <MarketNote market={HUB} />
          <MarketNote market={SPOKES[0]} />
        </div>
        <div className="grid sm:grid-cols-2 gap-4 mt-4">
          {SPOKES.slice(1).map((m) => (
            <MarketNote key={m.id} market={m} />
          ))}
        </div>
      </section>

      {/* How settlement works */}
      <section className="mt-14">
        <h2 className="display-lg text-paper mb-6">How settlement works</h2>
        <div className="grid md:grid-cols-3 gap-4">
          {STEPS.map((s) => (
            <div key={s.n} className="note p-6">
              <div className="relative">
                <div className="flex items-center gap-3">
                  <span className="display-md" style={{ color: "var(--color-brass)" }}>
                    {s.n}
                  </span>
                  <span className="h-px flex-1 bg-hairline-strong" />
                </div>
                <h3 className="display-md text-paper mt-4">{s.title}</h3>
                <p className="text-muted text-sm mt-2 leading-relaxed">{s.body}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* Risk notice */}
      <section className="mt-8 note p-6" style={{ borderColor: "color-mix(in srgb, var(--color-brass) 30%, transparent)" }}>
        <div className="relative flex flex-col sm:flex-row gap-4 sm:items-center">
          <span className="seal h-11 w-11 shrink-0">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" aria-hidden="true">
              <path d="M12 3l7 3v5c0 4.2-2.8 7.6-7 9-4.2-1.4-7-4.8-7-9V6l7-3z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
            </svg>
          </span>
          <div>
            <h3 className="eyebrow" style={{ color: "var(--color-brass)" }}>Risk Notice</h3>
            <p className="text-muted text-sm mt-2 leading-relaxed">
              The protocol is{" "}
              <Link href="/dollarstore-audit-openzeppelin.pdf" target="_blank" rel="noopener noreferrer" className="text-paper hover:text-dollar-bright underline underline-offset-2">
                audited by OpenZeppelin
              </Link>
              , but all smart-contract interactions carry risk. Supported stablecoins are treated as
              equivalent; if any underlying coin depegs, everyone interacting shares that risk. This is
              autonomous software used entirely at your own risk.
            </p>
          </div>
        </div>
      </section>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="num text-paper" style={{ fontSize: "1.25rem" }}>
        {value}
      </div>
      <div className="label mt-1" style={{ letterSpacing: "0.1em" }}>
        {label}
      </div>
    </div>
  );
}
