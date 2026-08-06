"use client";

import { useMemo, useState } from "react";
import { Guilloche } from "./guilloche";
import { TOKENS, TINT, usd, routeFor, routeCapacity } from "@/config/markets";

const MIN_ORDER = 100;
const QUEUE_ETA = "est. >1 hr";

// Swap console. For the person swapping we abstract away pools / hubs / spokes / routing entirely:
// they say what they have and what they want, and we tell them exactly how much settles instantly and
// what the remainder would be, then let them choose to partial-settle or queue. Routing still happens
// under the hood (see routeFor), it is just never shown here.
export function SwapConsole() {
  const [from, setFrom] = useState("USDC");
  const [to, setTo] = useState("RLUSD");
  const [amount, setAmount] = useState("");

  const route = useMemo(() => routeFor(from, to), [from, to]);
  const instant = routeCapacity(route); // how much of this pair can settle right now
  const amt = Number(amount) || 0;

  const settlesNow = Math.min(amt, instant);
  const queues = Math.max(0, amt - instant);
  const belowMin = amt > 0 && amt < MIN_ORDER;
  const partial = amt > 0 && !belowMin && queues > 0 && settlesNow > 0; // some now, some queued
  const queueOnly = amt > 0 && !belowMin && settlesNow === 0; // nothing available now

  const pick = (side: "from" | "to", sym: string) => {
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

  return (
    <div className="grid lg:grid-cols-[1.05fr_0.95fr] gap-4 items-stretch">
      {/* ---- Swap card ---- */}
      <div className="note p-6 sm:p-7">
        <div className="guilloche">
          <Guilloche rosette="right" className="w-full h-full" />
        </div>
        <div className="relative">
          <div className="flex items-center justify-between">
            <span className="eyebrow">Swap</span>
            <span className="label" style={{ letterSpacing: "0.08em" }}>
              1 : 1 · no fee
            </span>
          </div>

          {/* I have */}
          <div className="mt-6">
            <div className="flex items-center justify-between mb-2">
              <span className="label">I have</span>
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
                aria-label="Amount"
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

          {/* I want */}
          <div>
            <div className="flex items-center justify-between mb-2">
              <span className="label">I want</span>
            </div>
            <div className="well flex items-center gap-3 px-4 py-4">
              <TokenSelect value={to} exclude={from} onPick={(s) => pick("to", s)} />
              <span className="num flex-1 min-w-0 text-right text-3xl text-paper">
                {amt > 0 ? amt.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) : "0.00"}
              </span>
            </div>
          </div>

          {/* Message slot (reserved height so the card never shifts) */}
          <div className="mt-5 min-h-[3rem]">
            {belowMin ? (
              <p className="text-sm leading-relaxed" style={{ color: "var(--color-brass)" }}>
                Minimum swap is {usd(MIN_ORDER)}. Enter a larger amount.
              </p>
            ) : queueOnly ? (
              <p className="text-sm leading-relaxed text-muted">
                None of {to} is available to settle instantly right now. You can queue the full amount and it fills
                as {to} liquidity arrives.
              </p>
            ) : partial ? (
              <p className="text-sm leading-relaxed text-muted">
                <span className="text-paper">{usd(settlesNow)}</span> settles instantly.{" "}
                <span className="text-paper">{usd(queues)}</span> would queue ({QUEUE_ETA}). Your call:
              </p>
            ) : null}
          </div>

          {/* Action(s) — the queue vs partial-settle choice lives here */}
          {amt <= 0 || belowMin ? (
            <button type="button" disabled className="btn-primary w-full py-4 text-[0.98rem]">
              {amt <= 0 ? "Enter an amount" : "Enter a larger amount"}
            </button>
          ) : queueOnly ? (
            <button type="button" className="btn-primary w-full py-4 text-[0.98rem]">
              Queue {usd(amt)} · {QUEUE_ETA}
            </button>
          ) : partial ? (
            <div className="space-y-2">
              <button type="button" className="btn-primary w-full py-4 text-[0.95rem]">
                Settle {usd(settlesNow, { compact: true })} now, queue {usd(queues, { compact: true })}
              </button>
              <button type="button" className="btn-ghost w-full py-4 text-[0.95rem]">
                Queue all {usd(amt, { compact: true })} instead · {QUEUE_ETA}
              </button>
            </div>
          ) : (
            <button type="button" className="btn-primary w-full py-4 text-[0.98rem]">
              Swap {usd(amt, { compact: true })} {from} for {to}
            </button>
          )}
        </div>
      </div>

      {/* ---- Settlement panel (informational, right) ---- */}
      <div className="note p-6 sm:p-7">
        <div className="relative flex flex-col h-full">
          <span className="eyebrow">Settlement</span>

          {/* Available instantly for this pair */}
          <div className="mt-5">
            <div className="num text-paper" style={{ fontSize: "2rem", color: "var(--color-dollar)" }}>
              {usd(instant, { compact: true })}
            </div>
            <div className="label mt-1">{to} available to settle instantly</div>
          </div>

          <div className="mt-5 h-px bg-hairline-strong" />

          {/* Exact breakdown of the current amount */}
          {amt > 0 && !belowMin ? (
            <div className="mt-5 space-y-3">
              <Row label="You want" value={`${usd(amt)} ${to}`} />
              <Row label="Settles now" value={usd(settlesNow)} tone="dollar" />
              <Row label={`Queues · ${QUEUE_ETA}`} value={usd(queues)} tone="muted" />
            </div>
          ) : (
            <p className="mt-5 text-muted text-sm leading-relaxed">
              Enter an amount to see exactly how much settles instantly and how much would queue.
            </p>
          )}

          <div className="mt-auto pt-6">
            <p className="label leading-relaxed" style={{ letterSpacing: "0.04em", textTransform: "none" }}>
              Instant settlement comes straight from reserves. Queued amounts fill in order as opposing
              liquidity arrives.
            </p>
          </div>
        </div>
      </div>
    </div>
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
            className="absolute left-0 top-full mt-2 z-30 w-56 rounded-lg p-1.5"
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
                  <span className="text-muted text-xs ml-auto truncate max-w-[7rem]">{t.name}</span>
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

function Row({ label, value, tone = "default" }: { label: string; value: string; tone?: "default" | "dollar" | "muted" }) {
  const color =
    tone === "dollar" ? "var(--color-dollar)" : tone === "muted" ? "var(--color-muted)" : "var(--color-paper)";
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="label">{label}</span>
      <span className="num" style={{ color }}>
        {value}
      </span>
    </div>
  );
}
