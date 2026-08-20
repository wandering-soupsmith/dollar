"use client";

import { useMemo, useState } from "react";
import { Guilloche } from "./guilloche";
import { TOKENS, TINT, usd, routeFor, routeCapacity } from "@/config/markets";

const MIN_ORDER = 100;
const QUEUE_ETA = "est. >1 hr";
const TOLERANCES = [100, 75, 50, 25]; // advanced: max share of the ORDER allowed to queue before reverting

// Swap console. Pools / hubs / spokes / routing are fully abstracted for the swapper. Whatever reserves
// cover settles instantly; the choice is what happens to the REMAINDER:
//   Queue the remainder OFF -> settle what is available now, the rest stays as your offer asset (never sent)
//   Queue the remainder ON  -> settle now, queue the rest. Advanced: a tolerance = max % of the ORDER you
//     allow to queue; if reserves move so more than that would queue at execution, the swap reverts.
//     (This maps to the contract's minAmountOut. The instant figure shown is only a live snapshot.)
export function SwapConsole({ want }: { want?: string }) {
  // An asset landing page links in with the asset it is about already selected as the want side.
  const preselected = want && TOKENS.some((t) => t.symbol === want) ? want : null;
  const [from, setFrom] = useState(preselected === "USDC" ? "USDS" : "USDC");
  const [to, setTo] = useState(preselected ?? "RLUSD");
  const [amount, setAmount] = useState("");
  const [queueRemainder, setQueueRemainder] = useState(false);
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [maxQueuedPct, setMaxQueuedPct] = useState(100); // tolerance: max % of the order allowed to queue

  const route = useMemo(() => routeFor(from, to), [from, to]);
  const instant = routeCapacity(route); // how much of this pair can settle right now (a live snapshot)
  const amt = Number(amount) || 0;

  const settlesNow = Math.min(amt, instant);
  const remainder = Math.max(0, amt - instant);
  const remainderPct = amt > 0 ? (remainder / amt) * 100 : 0;
  const minInstant = amt * (1 - maxQueuedPct / 100); // guaranteed instant floor (contract minAmountOut)

  const queued = queueRemainder ? remainder : 0;
  const kept = queueRemainder ? 0 : remainder; // stays as the offer asset, never sent

  const belowMin = amt > 0 && amt < MIN_ORDER;
  const hasRemainder = amt > 0 && !belowMin && remainder > 0;
  // Snapshot already shows more of the order queuing than the tolerance allows -> would revert on execution.
  const overTolerance = queueRemainder && hasRemainder && remainderPct > maxQueuedPct + 1e-6;
  // Keeping everything while nothing settles == a no-op.
  const noop = hasRemainder && settlesNow === 0 && !queueRemainder;
  const blocked = overTolerance || noop;

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

          {/* Remainder choice — up front */}
          <div className="mt-4 well px-4 py-3">
            <div className="flex items-center justify-between gap-4">
              <div>
                <div className="text-paper text-sm">Queue the remainder</div>
                <div className="label mt-0.5" style={{ letterSpacing: "0.03em", textTransform: "none" }}>
                  {queueRemainder
                    ? `Unfilled amount waits to fill (${QUEUE_ETA})`
                    : `Unfilled amount stays as your ${from} — never sent`}
                </div>
              </div>
              <Switch checked={queueRemainder} onChange={() => setQueueRemainder((q) => !q)} label="Queue the remainder" />
            </div>

            {queueRemainder && (
              <div className="mt-3 pt-3 border-t border-hairline">
                <button
                  type="button"
                  onClick={() => setShowAdvanced((s) => !s)}
                  className="label hover:text-dollar-bright"
                  style={{ letterSpacing: "0.08em" }}
                  aria-expanded={showAdvanced}
                >
                  Advanced {showAdvanced ? "−" : "+"}
                </button>
                {showAdvanced && (
                  <div className="mt-3">
                    <div className="label mb-1" style={{ letterSpacing: "0.04em", textTransform: "none" }}>
                      Max queued — revert if more of my order would queue
                    </div>
                    <div className="flex gap-2 mt-2">
                      {TOLERANCES.map((p) => (
                        <button key={p} type="button" onClick={() => setMaxQueuedPct(p)} className="chip px-3 py-1.5" data-active={maxQueuedPct === p}>
                          {p}%
                        </button>
                      ))}
                    </div>
                    <div className="label mt-2" style={{ letterSpacing: "0.03em", textTransform: "none" }}>
                      Guarantees at least {usd(minInstant, { compact: true })} settles instantly, or the swap cancels.
                    </div>
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Message slot (reserved height so the card never shifts) */}
          <div className="mt-4 min-h-[2.75rem]">
            {belowMin ? (
              <p className="text-sm leading-relaxed" style={{ color: "var(--color-brass)" }}>
                Minimum swap is {usd(MIN_ORDER)}. Enter a larger amount.
              </p>
            ) : noop ? (
              <p className="text-sm leading-relaxed text-muted">
                None of {to} is available to settle instantly. Turn on Queue the remainder to submit your order.
              </p>
            ) : overTolerance ? (
              <p className="text-sm leading-relaxed" style={{ color: "var(--color-brass)" }}>
                {remainderPct.toFixed(0)}% of your order would queue right now, over your {maxQueuedPct}% limit. Raise
                the limit or reduce the amount.
              </p>
            ) : hasRemainder ? (
              <p className="text-sm leading-relaxed text-muted">
                <span className="text-paper">{usd(settlesNow, { compact: true })}</span> settles instantly,{" "}
                <span className="text-paper">{usd(remainder, { compact: true })}</span>{" "}
                {queueRemainder ? `queues (${QUEUE_ETA})` : `stays as ${from}`}.
              </p>
            ) : null}
          </div>

          {/* Action */}
          <button type="button" disabled={amt <= 0 || belowMin || blocked} className="btn-primary w-full py-4 text-[0.95rem]">
            {amt <= 0
              ? "Enter an amount"
              : belowMin
                ? "Enter a larger amount"
                : noop
                  ? "Turn on queue to submit"
                  : overTolerance
                    ? "Raise limit or reduce amount"
                    : !hasRemainder
                      ? `Swap ${usd(amt, { compact: true })} ${from} for ${to}`
                      : queueRemainder
                        ? settlesNow === 0
                          ? `Queue ${usd(remainder, { compact: true })} · ${QUEUE_ETA}`
                          : `Settle ${usd(settlesNow, { compact: true })} now, queue ${usd(remainder, { compact: true })}`
                        : `Settle ${usd(settlesNow, { compact: true })} now, keep the rest`}
          </button>
        </div>
      </div>

      {/* ---- Settlement panel (informational, right) ---- */}
      <div className="note p-6 sm:p-7">
        <div className="relative flex flex-col h-full">
          <span className="eyebrow">Settlement</span>

          <div className="mt-5">
            <div className="num" style={{ fontSize: "2rem", color: "var(--color-dollar)" }}>
              {usd(instant, { compact: true })}
            </div>
            <div className="label mt-1">{to} available to settle instantly</div>
          </div>

          <div className="mt-5 h-px bg-hairline-strong" />

          {amt > 0 && !belowMin ? (
            <div className="mt-5 space-y-3">
              <Row label="You want" value={`${usd(amt)} ${to}`} />
              <Row label="Settles now" value={`${usd(settlesNow)} ${to}`} tone="dollar" />
              {queued > 0 && <Row label={`Queues · ${QUEUE_ETA}`} value={`${usd(queued)} ${to}`} tone="muted" />}
              {kept > 0 && <Row label={`Stays as ${from} · not swapped`} value={usd(kept)} tone="brass" />}
            </div>
          ) : (
            <p className="mt-5 text-muted text-sm leading-relaxed">
              Enter an amount to see exactly how much settles instantly and what happens to the rest.
            </p>
          )}

          <div className="mt-auto pt-6">
            <p className="label leading-relaxed" style={{ letterSpacing: "0.04em", textTransform: "none" }}>
              The instant figure is live. The final split is set when your swap executes, so it may differ if
              reserves move before then.
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}

function Switch({ checked, onChange, label }: { checked: boolean; onChange: () => void; label: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={onChange}
      className="relative shrink-0 h-6 w-11 rounded-full transition-colors"
      style={{ background: checked ? "var(--color-dollar)" : "var(--color-hairline-strong)" }}
    >
      <span
        className="absolute top-0.5 h-5 w-5 rounded-full transition-all"
        style={{ left: checked ? "1.375rem" : "0.125rem", background: checked ? "#0a1a0e" : "var(--color-muted)" }}
      />
    </button>
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

function Row({ label, value, tone = "default" }: { label: string; value: string; tone?: "default" | "dollar" | "muted" | "brass" }) {
  const color =
    tone === "dollar"
      ? "var(--color-dollar)"
      : tone === "muted"
        ? "var(--color-muted)"
        : tone === "brass"
          ? "var(--color-brass)"
          : "var(--color-paper)";
  return (
    <div className="flex items-center justify-between text-sm">
      <span className="label">{label}</span>
      <span className="num" style={{ color }}>
        {value}
      </span>
    </div>
  );
}
