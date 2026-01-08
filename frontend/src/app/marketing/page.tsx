import Link from "next/link";
import { CONTRACTS } from "@/config/contracts";

export default function MarketingPage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6">
      {/* Hero */}
      <section className="py-24 text-center">
        <h1 className="text-4xl md:text-5xl font-bold text-white mb-6">
          Zero-fee stablecoin infrastructure
        </h1>
        <p className="text-xl text-muted max-w-2xl mx-auto mb-10">
          Open-source protocol enabling 1:1 stablecoin swaps. No fees. No slippage.
          Autonomous smart contracts execute swaps according to deterministic rules.
        </p>
        <div className="flex items-center justify-center gap-4">
          <Link
            href="https://app.dollarstore.world"
            className="bg-dollar-green hover:bg-dollar-green-light text-black px-8 py-3 rounded-sm text-lg font-medium transition-colors"
          >
            Launch App
          </Link>
          <Link
            href="https://docs.dollarstore.world"
            className="border border-border hover:border-dollar-green text-white px-8 py-3 rounded-sm text-lg font-medium transition-colors"
          >
            Read Docs
          </Link>
        </div>
      </section>

      {/* Features */}
      <section className="py-16 border-t border-border">
        <div className="grid md:grid-cols-3 gap-8">
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="text-3xl mb-4">1:1</div>
            <h3 className="font-h3 text-white mb-2">Exact Exchange</h3>
            <p className="font-body-sm text-muted">
              The protocol enables swaps at exactly 1:1. No spread, no slippage,
              no hidden costs.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="text-3xl mb-4 text-dollar-green">$0</div>
            <h3 className="font-h3 text-white mb-2">Zero Fees</h3>
            <p className="font-body-sm text-muted">
              No protocol fees. Users pay only network gas costs. The protocol
              operates without extraction.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="text-3xl mb-4">FIFO</div>
            <h3 className="font-h3 text-white mb-2">Queue-Based</h3>
            <p className="font-body-sm text-muted">
              When reserves are low, positions queue and fill automatically
              when matching deposits arrive.
            </p>
          </div>
        </div>
      </section>

      {/* About */}
      <section className="py-16 border-t border-border">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="font-h2 text-white mb-6">About the Protocol</h2>
          <p className="font-body text-muted mb-6">
            Dollar Store is open-source software deployed as autonomous smart contracts
            on Ethereum. The protocol facilitates queue-based stablecoin exchange,
            treating all supported dollars as equivalent.
          </p>
          <p className="font-body text-muted mb-8">
            Once deployed, smart contracts operate automatically according to their
            programmed logic. No person or entity executes transactions, routes assets,
            or intervenes in protocol operation.
          </p>
          <div className="flex items-center justify-center gap-6 text-sm">
            <Link
              href={`https://sepolia.etherscan.io/address/${CONTRACTS.sepolia.dollarStore}`}
              target="_blank"
              rel="noopener noreferrer"
              className="text-dollar-green hover:text-dollar-green-light"
            >
              View Contract
            </Link>
            <span className="text-border">|</span>
            <Link
              href="https://github.com/wandering-soupsmith/dollar"
              target="_blank"
              rel="noopener noreferrer"
              className="text-dollar-green hover:text-dollar-green-light"
            >
              Source Code
            </Link>
          </div>
        </div>
      </section>

      {/* Integrators */}
      <section className="py-16 border-t border-border">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="font-h2 text-white mb-6">For Integrators</h2>
          <p className="font-body text-muted mb-8">
            The protocol exposes permissionless smart contract interfaces for
            programmatic integration. Aggregators, protocols, and applications
            can incorporate Dollar Store routes directly.
          </p>
          <Link
            href="https://docs.dollarstore.world"
            className="text-dollar-green hover:text-dollar-green-light font-medium"
          >
            View Integration Documentation
          </Link>
        </div>
      </section>
    </div>
  );
}
