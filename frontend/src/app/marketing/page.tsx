import Link from "next/link";
import { AUDITS, CONTRACTS, IS_DEPLOYED } from "@/config/contracts";

const FEATURES = [
  {
    mark: "1:1 · $0",
    title: "Exact exchange",
    body: "One dollar in, one dollar out. No spread, no slippage, no protocol fees.",
  },
  {
    mark: "24/7",
    title: "No lockups",
    body: "Withdraw any available stablecoin instantly, anytime, no restrictions.",
  },
  {
    mark: "FIFO",
    title: "Queue-based",
    body: "Want a stablecoin that is not currently in reserves? Join the queue and get filled automatically when it arrives.",
  },
];

export default function MarketingPage() {
  return (
    <div className="max-w-[1180px] mx-auto px-6">
      {/* Hero */}
      <section className="pt-24 pb-16 text-center rise">
        <span className="eyebrow">Stablecoin Exchange · Ethereum</span>
        <h1 className="display-hero text-paper mt-4 max-w-3xl mx-auto">
          Zero-fee stablecoin swaps
        </h1>
        <p className="text-muted text-lg max-w-2xl mx-auto mt-5 leading-relaxed">
          Open-source protocol for 1:1 stablecoin swaps. No fees, no slippage. Autonomous smart
          contracts settle every swap according to deterministic rules.
        </p>
        <div className="flex items-center justify-center gap-3 mt-8">
          <Link href="https://app.dollarstore.world" className="btn-primary px-7 py-3.5 text-[0.98rem]">
            Launch app
          </Link>
          <Link href="https://docs.dollarstore.world" className="btn-ghost px-7 py-3.5 text-[0.98rem]">
            Read docs
          </Link>
        </div>
      </section>

      {/* Features */}
      <section className="py-12 border-t border-hairline-strong">
        <div className="grid md:grid-cols-3 gap-4">
          {FEATURES.map((f) => (
            <div key={f.title} className="note p-6">
              <div className="relative">
                <div className="num text-dollar" style={{ fontSize: "1.4rem" }}>
                  {f.mark}
                </div>
                <h3 className="display-md text-paper mt-4">{f.title}</h3>
                <p className="text-muted text-sm mt-2 leading-relaxed">{f.body}</p>
              </div>
            </div>
          ))}
        </div>
      </section>

      {/* About */}
      <section className="py-16 border-t border-hairline-strong">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="display-lg text-paper mb-5">About the protocol</h2>
          <p className="text-muted leading-relaxed mb-4">
            Dollar Store is open-source software deployed as autonomous smart contracts on Ethereum.
            The protocol facilitates queue-based stablecoin exchange, treating all supported dollars
            as equivalent.
          </p>
          <p className="text-muted leading-relaxed mb-7">
            Once deployed, smart contracts operate automatically according to their programmed logic.
            No person or entity executes transactions, routes assets, or intervenes in protocol
            operation.
          </p>
          <div className="flex items-center justify-center gap-5 text-sm">
            {IS_DEPLOYED && (
              <>
                <Link
                  href={`https://etherscan.io/address/${CONTRACTS.mainnet.dollarStore}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-dollar-bright hover:text-dollar"
                >
                  View contract
                </Link>
                <span className="text-faint">·</span>
              </>
            )}
            <Link
              href="https://github.com/coasify/dollar"
              target="_blank"
              rel="noopener noreferrer"
              className="text-dollar-bright hover:text-dollar"
            >
              Source code
            </Link>
          </div>
        </div>
      </section>

      {/* Security & Audits */}
      <section className="py-16 border-t border-hairline-strong">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="display-lg text-paper mb-5">Security &amp; audits</h2>
          <p className="text-muted leading-relaxed mb-8">
            Dollar Store smart contracts have been audited by OpenZeppelin, a leading blockchain
            security firm. The latest report covers the v3 hub-and-spoke protocol: pools, deposits and
            withdrawals, directed swaps, queue management, and the oracle and pause risk controls.
          </p>
          <Link
            href={AUDITS.current.href}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex flex-col items-center gap-3 group"
          >
            <div className="note px-8 py-6 transition-colors group-hover:border-dollar-deep">
              <svg viewBox="0 0 200 40" className="relative h-8 w-auto" fill="none" xmlns="http://www.w3.org/2000/svg">
                <g transform="translate(0, 2) scale(1.9)">
                  <path d="M0 18.9539C2.17294 15.313 4.01936 12.3103 6.36619 8.19498C7.19516 6.80627 8.62757 5.94336 10.3959 5.94336H13.1744L5.41504 18.9539H0Z" fill="#2E99FF" />
                  <path d="M0.0234375 0H16.6958L13.8471 4.8101H0.0234375V0Z" fill="#4F56FA" />
                  <path d="M8.37464 15.9582C9.0016 14.8849 10.0094 14.218 11.421 14.218L16.6989 14.2041V18.9543H6.58594C7.2191 17.9027 7.76889 16.9952 8.37464 15.9582Z" fill="#09C2FF" />
                </g>
                <text x="42" y="27" className="fill-white" fontFamily="system-ui, sans-serif" fontSize="20" fontWeight="600">
                  OpenZeppelin
                </text>
              </svg>
            </div>
            <span className="text-sm text-muted group-hover:text-dollar-bright transition-colors">
              View audit report
            </span>
          </Link>
        </div>
      </section>

      {/* Integrators */}
      <section className="py-16 border-t border-hairline-strong">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="display-lg text-paper mb-5">For integrators</h2>
          <p className="text-muted leading-relaxed mb-7">
            The protocol exposes permissionless smart-contract interfaces for programmatic
            integration. Aggregators, protocols, and applications can incorporate Dollar Store routes
            directly.
          </p>
          <Link href="https://docs.dollarstore.world" className="text-dollar-bright hover:text-dollar font-medium">
            View integration documentation
          </Link>
        </div>
      </section>
    </div>
  );
}
