import Link from "next/link";
import { AssetConfig } from "@/config/assets";
import { NETWORK_BADGE } from "@/config/deployments";
import { DARK_SEGMENT, OnePagerTheme } from "@/config/one-pager-theme";

/**
 * The per-asset landing page — the printed issuer one-pager, rendered on the web.
 *
 * Section order, wording and proportions follow the approved print piece, because the two are
 * distributed together: an issuer hands out the PDF, and the reader who follows the URL should
 * arrive at the same document. Everything on the page comes from the asset's registry entry.
 *
 * The variant is part of the URL rather than the visitor's system setting: these links get pasted
 * into decks and docs, so whoever shares one needs to know which version the reader will see.
 */
export function AssetPage({
  asset,
  theme = "light",
}: {
  asset: AssetConfig;
  theme?: OnePagerTheme;
}) {
  return (
    <div className="one-pager" data-theme={theme}>
      <div className="mx-auto max-w-[880px] px-6 sm:px-10">
        <PageHeader asset={asset} />
        <Hero asset={asset} />
        <CallToAction asset={asset} />
        <Stats />
        <HowItWorks symbol={asset.symbol} />
        <SwapStrip asset={asset} />
        <MorePairs symbol={asset.symbol} />
      </div>
      <PageFooter asset={asset} theme={theme} />
    </div>
  );
}

/* ---------------------------------------------------------------- header */

function PageHeader({ asset }: { asset: AssetConfig }) {
  return (
    <header className="flex items-start justify-between gap-6 pt-10 sm:pt-12 pb-7 border-b border-[var(--op-rule)]">
      <div className="flex items-center gap-3">
        <IssuerMark asset={asset} size={38} />
        <span
          className="text-[0.95rem] font-semibold leading-[1.15]"
          style={{ color: "var(--op-ink)" }}
        >
          {asset.issuerNetwork ? (
            <>
              {asset.issuerNetwork.split(" ").slice(0, -1).join(" ")}
              <br />
              {asset.issuerNetwork.split(" ").slice(-1)}
            </>
          ) : (
            asset.issuer
          )}
        </span>
      </div>

      <p className="op-mark text-right leading-[1.7] shrink-0">
        An announcement
        <br />
        for {asset.symbol} users
      </p>
    </header>
  );
}

/**
 * The issuer's mark. Registry entries can point at a file under /public; without one the page falls
 * back to a monogram so the layout holds rather than showing a broken image.
 */
function IssuerMark({ asset, size, onLime }: { asset: AssetConfig; size: number; onLime?: boolean }) {
  if (asset.logo) {
    // eslint-disable-next-line @next/next/no-img-element -- issuer marks are local SVGs, already sized
    return <img src={asset.logo} alt="" width={size} height={size} className="rounded-full" />;
  }
  return (
    <span
      aria-hidden="true"
      className="op-display inline-grid place-items-center rounded-full shrink-0"
      style={{
        width: size,
        height: size,
        // On the page the mark inverts with the variant, as the print pieces do: dark on cream,
        // light on ink. On the lime band it stays a dark disc in both.
        background: onLime ? "var(--op-on-lime)" : "var(--op-ink)",
        color: onLime ? "var(--op-lime)" : "var(--op-bg)",
        fontSize: size * 0.46,
        lineHeight: 1,
      }}
    >
      {asset.symbol.charAt(asset.symbol.length - 1)}
    </span>
  );
}

/* ------------------------------------------------------------------ hero */

function Hero({ asset }: { asset: AssetConfig }) {
  return (
    <section className="pt-11 sm:pt-14">
      <h1 className="op-display op-hero">
        Get and sell {asset.symbol} on-chain,
        {/* The print piece breaks here; on a phone the line is let to wrap naturally instead. */}
        <br className="hidden sm:inline" />{" "}
        always at <em style={{ color: "var(--op-brass)", fontStyle: "italic" }}>one dollar</em>.
      </h1>

      <p className="text-[1.02rem] leading-[1.62] mt-7 max-w-[47rem]">
        There is now one place to convert {asset.symbol} on-chain at par. Bring{" "}
        <SymbolList symbols={asset.pairs} /> and receive {asset.symbol} at{" "}
        <strong className="font-semibold" style={{ color: "var(--op-emphasis)" }}>
          exactly 1:1
        </strong>
        , or go the other way just as easily. No slippage. No fees. Nothing to negotiate.
      </p>
    </section>
  );
}

function SymbolList({ symbols }: { symbols: string[] }) {
  if (symbols.length === 0) return null;
  const last = symbols[symbols.length - 1];
  const head = symbols.slice(0, -1);
  return <>{head.length > 0 ? `${head.join(", ")}, or ${last}` : last}</>;
}

/* -------------------------------------------------------- call to action */

function CallToAction({ asset }: { asset: AssetConfig }) {
  return (
    <section className="mt-9">
      <Link
        href={`/?want=${asset.symbol}`}
        className="group flex flex-col sm:flex-row sm:items-center gap-5 sm:gap-6 px-6 sm:px-8 py-6 sm:py-7"
        style={{ background: "var(--op-lime)" }}
      >
        <IssuerMark asset={asset} size={46} onLime />

        <div className="min-w-0 flex-1">
          <p
            className="op-display text-[1.3rem] sm:text-[1.95rem] leading-[1.15] break-words group-hover:underline underline-offset-[6px]"
            style={{ color: "var(--op-on-lime)" }}
          >
            dollarstore.world/{asset.symbol}
          </p>
          <p className="text-[0.85rem] mt-1.5" style={{ color: "var(--op-on-lime)" }}>
            Swap into and out of {asset.symbol} here
          </p>
        </div>

        <p
          className="op-mark sm:text-right shrink-0 leading-[1.7]"
          style={{ color: "var(--op-on-lime)" }}
        >
          {NETWORK_BADGE.prefix}
          <br />
          {NETWORK_BADGE.network}
        </p>
      </Link>
    </section>
  );
}

/* ----------------------------------------------------------------- stats */

const STATS = [
  {
    figure: "1:1",
    label: "Exchange rate",
    body: "Exact, on every swap you make, at any size, in either direction.",
  },
  {
    figure: "$0",
    label: "Cost to swap",
    body: "You pay no protocol fee, no spread, and no slippage.",
  },
  {
    figure: "24/7",
    label: "Availability",
    body: "On-chain and permissionless. Open whenever you need it.",
  },
];

function Stats() {
  return (
    <section className="mt-10 border-y border-[var(--op-rule)]">
      <div className="grid sm:grid-cols-3 divide-y sm:divide-y-0 sm:divide-x divide-[var(--op-rule)]">
        {STATS.map((stat) => (
          <div key={stat.label} className="py-6 sm:py-7 sm:px-7 sm:first:pl-0 sm:last:pr-0">
            <p className="op-display op-figure">{stat.figure}</p>
            <p className="op-label mt-2.5">{stat.label}</p>
            <p className="text-[0.87rem] leading-[1.55] mt-2">{stat.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}

/* ---------------------------------------------------------- how it works */

function HowItWorks({ symbol }: { symbol: string }) {
  return (
    <section className="mt-11">
      <p className="op-mark op-mark-square">How it works</p>

      <div className="grid md:grid-cols-2 gap-8 md:gap-12 mt-6">
        <div>
          <h2 className="op-display op-title flex items-baseline gap-3">
            <span
              className="op-display text-[0.82rem] font-normal"
              style={{ color: "var(--op-soft)" }}
            >
              01
            </span>
            If liquidity is there, take it.
          </h2>
          <p className="text-[0.9rem] leading-[1.6] mt-3">
            Deposit the stablecoin you are holding and receive {symbol} at exactly $1.00 in the same
            transaction. Whatever sits in reserve is yours to take at par, up to the full amount
            available.
          </p>
        </div>

        <div>
          <h2 className="op-display op-title flex items-baseline gap-3">
            <span
              className="op-display text-[0.82rem] font-normal"
              style={{ color: "var(--op-soft)" }}
            >
              02
            </span>
            If it is not, join the queue.
          </h2>
          <p className="text-[0.9rem] leading-[1.6] mt-3">
            Your place is recorded in order and fills automatically as reserves arrive. You are not
            bidding, and you are never exposed to a moving price: your rate is 1:1 whenever the fill
            lands.{" "}
            <strong className="font-semibold" style={{ color: "var(--op-olive)" }}>
              Queued positions get filled.
            </strong>
          </p>
        </div>
      </div>
    </section>
  );
}

/* ----------------------------------------------------------- swap strip */

function SwapStrip({ asset }: { asset: AssetConfig }) {
  return (
    <section className="mt-9">
      <div className="flex flex-col sm:flex-row border border-[var(--op-rule)]">
        <div className="sm:w-[13.5rem] shrink-0 px-5 py-5 border-b sm:border-b-0 sm:border-r border-[var(--op-rule)]">
          <p className="op-mark">What you can swap</p>
          <p className="text-[0.82rem] leading-[1.5] mt-2">
            Every pair, either direction, at exactly one dollar.
          </p>
        </div>

        {/* Pairs are divided by short centred rules, as on the print piece, rather than by borders
            running the full height of the box. */}
        <ul className="flex-1 flex flex-col sm:flex-row sm:flex-wrap items-start sm:items-center sm:justify-around gap-y-3 px-5 sm:px-4 py-5 sm:py-7">
          {asset.pairs.map((pair, i) => (
            <li key={pair} className="flex items-center">
              {i > 0 && (
                <span
                  aria-hidden="true"
                  className="hidden sm:block w-px h-5 mr-6"
                  style={{ background: "var(--op-rule)" }}
                />
              )}
              <span className="text-[1.08rem] px-2" style={{ color: "var(--op-ink)" }}>
                {pair}{" "}
                <span className="px-1.5" style={{ color: "var(--op-emphasis)" }}>
                  ⇄
                </span>{" "}
                {asset.symbol}
              </span>
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}

/* ------------------------------------------------------- more pairs copy */

function MorePairs({ symbol }: { symbol: string }) {
  return (
    <section className="mt-11 pb-16">
      <p className="op-mark op-mark-square">More pairs over time</p>
      <p className="text-[0.94rem] leading-[1.62] mt-4">
        Dollar Store treats every stablecoin it supports as worth exactly one dollar. As additional
        assets are added to the protocol,{" "}
        <strong className="font-semibold" style={{ color: "var(--op-ink)" }}>
          {symbol} becomes swappable 1:1 against each of them as well
        </strong>
        , in both directions, with no new steps for you.
      </p>
    </section>
  );
}

/* ---------------------------------------------------------------- footer */

function PageFooter({ asset, theme }: { asset: AssetConfig; theme: OnePagerTheme }) {
  const counterpart =
    theme === "dark"
      ? { href: `/${asset.symbol}`, label: "View the light version" }
      : { href: `/${asset.symbol}/${DARK_SEGMENT}`, label: "View the dark version" };

  return (
    <footer className="border-t border-[var(--op-rule)]">
      <div className="mx-auto max-w-[880px] px-6 sm:px-10 py-9">
        <div className="flex flex-col md:flex-row md:justify-between gap-7">
          <div>
            <p className="op-mark">Questions, or want the detail?</p>
            <Link
              href="https://docs.dollarstore.world"
              className="text-[1.12rem] font-medium mt-2 inline-block hover:underline underline-offset-4"
              style={{ color: "var(--op-ink)" }}
            >
              docs.dollarstore.world
            </Link>
            <p className="mt-3">
              <Link
                href={counterpart.href}
                className="op-mark hover:underline underline-offset-4"
              >
                {counterpart.label}
              </Link>
            </p>
          </div>

          <p
            className="text-[0.68rem] leading-[1.6] md:max-w-[27rem] md:text-right"
            style={{ color: "var(--op-soft)" }}
          >
            Dollar Store is built by Coasify Corporation: open-source contracts deployed on Ethereum
            mainnet and audited by OpenZeppelin. {asset.name} ({asset.symbol}) is issued by{" "}
            {asset.issuer}. Mention of third-party products or services is for informational purposes
            only and does not constitute an endorsement by {asset.issuer} or its affiliates.
          </p>
        </div>
      </div>
    </footer>
  );
}
