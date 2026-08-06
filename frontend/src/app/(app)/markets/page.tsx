import Link from "next/link";
import { HUB, SPOKES, usd, marketReserve } from "@/config/markets";
import { MarketNote } from "@/components/market-note";

export default function MarketsPage() {
  return (
    <div className="max-w-[1180px] mx-auto px-6 pt-14 pb-20">
      <section className="rise">
        <span className="eyebrow">Markets</span>
        <h1 className="display-hero text-paper mt-4">The reserve floor</h1>
        <p className="text-muted mt-4 max-w-xl leading-relaxed">
          One hub of core dollars backs every trade. Each issuer stablecoin is admitted as its own
          spoke — a challenger note certified to trade at par, paired against internal DLRS and capped
          while it earns its place.
        </p>
      </section>

      {/* Hub */}
      <section className="mt-10">
        <h2 className="label mb-4" style={{ letterSpacing: "0.16em" }}>
          Hub · reserve base
        </h2>
        <MarketNote market={HUB} />
      </section>

      {/* Spokes */}
      <section className="mt-8">
        <div className="flex items-baseline justify-between mb-4">
          <h2 className="label" style={{ letterSpacing: "0.16em" }}>
            Spokes · certified issuer notes
          </h2>
          <span className="label" style={{ letterSpacing: "0.1em" }}>
            {SPOKES.length} listed
          </span>
        </div>
        <div className="grid md:grid-cols-2 gap-4">
          {SPOKES.map((m) => (
            <MarketNote key={m.id} market={m} />
          ))}
        </div>
      </section>

      {/* Spoke ledger table */}
      <section className="mt-8 note p-0 overflow-hidden">
        <div className="relative overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="label" style={{ letterSpacing: "0.1em" }}>
                <Th className="text-left pl-6">Note</Th>
                <Th>Issuer</Th>
                <Th className="text-right">Reserve</Th>
                <Th className="text-right">24h vol</Th>
                <Th className="text-right">Queue</Th>
                <Th className="text-right pr-6">Cap used</Th>
              </tr>
            </thead>
            <tbody>
              {[HUB, ...SPOKES].map((m) => {
                const cap =
                  m.launchCap && m.launchCapUsed
                    ? `${((m.launchCapUsed / m.launchCap) * 100).toFixed(0)}%`
                    : "—";
                return (
                  <tr key={m.id} className="border-t border-hairline">
                    <td className="py-3.5 pl-6">
                      <span className="num text-paper">{m.title}</span>
                    </td>
                    <td className="py-3.5 text-muted">{m.issuer}</td>
                    <td className="py-3.5 text-right num text-paper">{usd(marketReserve(m), { compact: true })}</td>
                    <td className="py-3.5 text-right num text-muted">{usd(m.volume24h, { compact: true })}</td>
                    <td className="py-3.5 text-right num text-muted">{usd(m.queueDepth, { compact: true })}</td>
                    <td className="py-3.5 text-right num text-muted pr-6">{cap}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </section>

      <div className="mt-8">
        <Link href="/" className="btn-ghost inline-flex px-5 py-3 text-sm">
          ← Back to the counter
        </Link>
      </div>
    </div>
  );
}

function Th({ children, className = "" }: { children: React.ReactNode; className?: string }) {
  return <th className={`py-3 font-medium text-muted ${className}`}>{children}</th>;
}
