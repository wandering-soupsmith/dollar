"use client";

import { useMemo, useState } from "react";
import { Guilloche } from "./guilloche";
import {
  TOKENS,
  TINT,
  usd,
  routeFor,
  routeCapacity,
  availableOut,
  getMarket,
  token,
} from "@/config/markets";

const MIN_ORDER = 100;

export function SwapConsole() {
  const [from, setFrom] = useState("USDC");
  const [to, setTo] = useState("RLUSD");
  const [amount, setAmount] = useState("");

  const route = useMemo(() => routeFor(from, to), [from, to]);
  const capacity = routeCapacity(route);
  const amt = Number(amount) || 0;

  const pick = (side: "from" | "to", sym: string) => {
    // Never allow both sides equal — swap if the user picks the opposite token.
    if (side === "from") {
      if (sym === to) setTo(from);
      setFrom(sym);
    } else {
      if (sym === from) setFrom(to);
      setTo(sym);
    }
  };
  const flip = () => {
    setFrom(to);
    setTo(from);
  };

  const belowMin = amt > 0 && amt < MIN_ORDER;
  const overCapacity = amt > capacity;
  // Direct routes can partial-fill and queue the remainder. A via-hub route needs the atomic router,
  // which is all-or-nothing: over capacity means there is no automatic route right now.
  const noAutoRoute = route.kind === "via-hub" && overCapacity;
  const partialQueue = route.kind === "direct" && overCapacity;

  return (
    <div className="grid lg:grid-cols-[1.05fr_0.95fr] gap-4 items-stretch">
      {/* ---- Swap card (the engraved note) ---- */}
      <div className="note p-6 sm:p-7">
        <div className="guilloche">
          <Guilloche rosette="right" className="w-full h-full" />
        </div>
        <div className="relative">
          <div className="flex items-center justify-between">
            <span className="eyebrow">Exchange</span>
            <span className="serial">SN 0000-0001-USD</span>
          </div>

          {/* You pay */}
          <div className="mt-6">
            <div className="flex items-center justify-between mb-2">
              <span className="label">You pay</span>
              <span className="label">Balance —</span>
            </div>
            <div className="well flex items-center gap-3 px-4 py-4">
              <TokenSelect value={from} exclude={to} onPick={(s) => pick("from", s)} />
              <input
                inputMode="decimal"
                placeholder="0.00"
                value={amount}
                onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))}
                className="num flex-1 min-w-0 bg-transparent text-right text-3xl text-paper outline-none placeholder:text-faint"
                aria-label="Amount to pay"
              />
            </div>
          </div>

          {/* Flip */}
          <div className="flex justify-center -my-3 relative z-10">
            <button
              type="button"
              onClick={flip}
              aria-label="Flip direction"
              className="btn-ghost h-10 w-10 grid place-items-center rounded-full bg-ink"
            >
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                <path d="M7 4v13M7 17l-3-3M7 17l3-3M17 20V7M17 7l-3 3M17 7l3 3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </button>
          </div>

          {/* You receive */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="label">You receive</span>
              <span className="label">1 : 1 · no fee</span>
            </div>
            <div className="well flex items-center gap-3 px-4 py-4">
              <TokenSelect value={to} exclude={from} onPick={(s) => pick("to", s)} />
              <span className="num flex-1 min-w-0 text-right text-3xl text-paper">
                {amt > 0 ? amt.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0.00"}
              </span>
            </div>
          </div>

          {/* Route line */}
          <div className="mt-4 flex items-center justify-between">
            <RoutePath from={from} to={to} via={route.via} />
            <span className="label" style={{ letterSpacing: "0.08em" }}>
              {route.kind === "via-hub" ? "Auto-routed" : "Direct"}
            </span>
          </div>

          {/* State + action. The message slot has reserved height so it never shifts the card. */}
          <div className="mt-5">
            <div className="min-h-[3rem] mb-1">
              {belowMin ? (
                <Note tone="brass">Minimum trade is {usd(MIN_ORDER)}. Enter a larger amount.</Note>
              ) : noAutoRoute ? (
                <Note tone="error">
                  No liquidity for an automatic route right now. {token(to).symbol} reserves via {route.via} cover{" "}
                  {usd(capacity, { compact: true })}. Route the first leg manually, or try a smaller amount.
                </Note>
              ) : partialQueue ? (
                <Note tone="muted">
                  Reserves cover {usd(capacity, { compact: true })}. The remainder joins the FIFO queue and fills as
                  opposing liquidity arrives.
                </Note>
              ) : null}
            </div>

            {noAutoRoute ? (
              <button type="button" className="btn-ghost w-full py-4 text-[0.95rem]">
                Swap {from} → {route.via} instead
              </button>
            ) : (
              <button type="button" disabled={amt <= 0 || belowMin} className="btn-primary w-full py-4 text-[0.98rem]">
                {amt <= 0
                  ? "Enter an amount"
                  : partialQueue
                    ? `Swap ${usd(capacity, { compact: true })} now + queue rest`
                    : `Swap ${from} for ${to}`}
              </button>
            )}
          </div>
        </div>
      </div>

      {/* ---- Ticket (route + liquidity) ---- */}
      <TicketPanel from={from} to={to} amount={amt} route={route} capacity={capacity} noAutoRoute={noAutoRoute} />
    </div>
  );
}

function TicketPanel({
  from,
  to,
  amount,
  route,
  capacity,
  noAutoRoute,
}: {
  from: string;
  to: string;
  amount: number;
  route: ReturnType<typeof routeFor>;
  capacity: number;
  noAutoRoute: boolean;
}) {
  const market = getMarket(token(to).kind === "spoke" ? token(to).marketId : token(from).marketId);
  return (
    <div className="note p-6 sm:p-7">
      <div className="relative flex flex-col h-full">
        <div className="flex items-center justify-between">
          <span className="eyebrow">Ticket</span>
          <span className="label" style={{ letterSpacing: "0.08em" }}>
            {route.kind === "via-hub" ? "Two legs · atomic" : "One leg"}
          </span>
        </div>

        {/* Route diagram */}
        <div className="mt-5 well px-4 py-4">
          <RoutePath from={from} to={to} via={route.via} big />
          {route.kind === "via-hub" && (
            <p className="text-muted text-xs mt-3 leading-relaxed">
              {from} and {to} are separate spokes, so the trade hops through the {route.via} hub in a single atomic
              transaction. You sign once.
            </p>
          )}
        </div>

        {/* Legs / availability */}
        <div className="mt-5 space-y-3">
          {route.legs.map((l, i) => (
            <div key={i} className="flex items-center justify-between text-sm">
              <span className="label">
                {route.kind === "via-hub" ? `Leg ${i + 1} · ` : ""}
                {l.from} → {l.to}
              </span>
              <span className="num text-muted">{usd(l.available, { compact: true })} avail</span>
            </div>
          ))}
          <div className="h-px bg-hairline-strong" />
          <Row label="Rate" value="1 : 1" />
          <Row label="Fee" value="None" />
          <Row
            label="Route capacity"
            value={usd(capacity, { compact: true })}
            tone={amount > 0 && noAutoRoute ? "error" : "default"}
          />
        </div>

        {/* Queue readout for the destination market */}
        <div className="mt-auto pt-5">
          <div className="flex items-center justify-between">
            <span className="label">{market.title} fill queue</span>
            <span className="num text-paper text-sm">{usd(market.queueDepth, { compact: true })}</span>
          </div>
          <div className="mt-2 h-1 rounded-full bg-forest overflow-hidden">
            <div
              className="h-full rounded-full"
              style={{
                width: `${Math.min(100, (market.queueDepth / 150_000) * 100)}%`,
                background: "linear-gradient(90deg, var(--color-dollar-deep), var(--color-dollar))",
              }}
            />
          </div>
        </div>
      </div>
    </div>
  );
}

function RoutePath({ from, to, via, big = false }: { from: string; to: string; via?: string; big?: boolean }) {
  const size = big ? "text-sm" : "text-xs";
  const chips = via ? [from, via, to] : [from, to];
  return (
    <span className="flex items-center gap-2">
      {chips.map((s, i) => (
        <span key={i} className="flex items-center gap-2">
          {i > 0 && (
            <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden="true" className="text-faint">
              <path d="M5 12h14M13 6l6 6-6 6" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          )}
          <span className={`num ${size} inline-flex items-center gap-1.5 ${s === via ? "text-muted" : "text-paper"}`}>
            <span className="dot" style={{ background: TINT[s] }} />
            {s}
          </span>
        </span>
      ))}
    </span>
  );
}

function TokenSelect({ value, exclude, onPick }: { value: string; exclude: string; onPick: (s: string) => void }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="relative shrink-0">
      <button
        type="button"
        onClick={() => setOpen((o) => !o)}
        aria-haspopup="listbox"
        aria-expanded={open}
        className="inline-flex items-center gap-2 rounded-md border border-hairline-strong px-3 py-2.5 hover:border-dollar-deep"
      >
        <span className="dot" style={{ background: TINT[value] }} />
        <span className="num text-paper text-sm">{value}</span>
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" aria-hidden="true" className="text-muted">
          <path d="M6 9l6 6 6-6" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open && (
        <>
          <button type="button" aria-label="Close" className="fixed inset-0 z-20 cursor-default" onClick={() => setOpen(false)} />
          <ul
            role="listbox"
            className="absolute left-0 top-full mt-2 z-30 w-52 rounded-lg p-1.5"
            style={{
              background: "var(--color-note)",
              border: "1px solid var(--color-hairline-strong)",
              boxShadow: "0 24px 50px -18px rgba(0,0,0,0.95)",
            }}
          >
            {TOKENS.map((t) => (
              <li key={t.symbol}>
                <button
                  type="button"
                  role="option"
                  aria-selected={t.symbol === value}
                  onClick={() => {
                    onPick(t.symbol);
                    setOpen(false);
                  }}
                  className="relative w-full flex items-center gap-2.5 px-3 py-2.5 rounded-md text-left hover:bg-forest"
                >
                  <span className="dot" style={{ background: TINT[t.symbol] }} />
                  <span className="num text-paper text-sm">{t.symbol}</span>
                  <span className="text-muted text-xs ml-auto">{t.kind === "hub" ? "Hub" : "Spoke"}</span>
                  {t.symbol === exclude && <span className="absolute inset-0 rounded-md bg-ink/60" />}
                </button>
              </li>
            ))}
          </ul>
        </>
      )}
    </div>
  );
}

function Row({ label, value, tone = "default" }: { label: string; value: string; tone?: "default" | "error" }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="label">{label}</span>
      <span className="num" style={{ color: tone === "error" ? "var(--color-error)" : "var(--color-paper)" }}>
        {value}
      </span>
    </div>
  );
}

function Note({ tone, children }: { tone: "brass" | "error" | "muted"; children: React.ReactNode }) {
  const color =
    tone === "brass" ? "var(--color-brass)" : tone === "error" ? "var(--color-error)" : "var(--color-muted)";
  return (
    <p className="text-sm leading-relaxed" style={{ color }}>
      {children}
    </p>
  );
}
