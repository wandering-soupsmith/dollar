import Link from "next/link";
import { CONTRACTS } from "@/config/contracts";

export default function MarketingPage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6">
      {/* Hero */}
      <section className="py-24 text-center">
        <h1 className="text-4xl md:text-5xl font-bold text-white mb-6">
          Zero-fee stablecoin swaps
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
            <div className="text-3xl mb-4">
              <span>1:1</span>
              <span className="text-dollar-green ml-2">$0</span>
            </div>
            <h3 className="font-h3 text-white mb-2">Exact Exchange</h3>
            <p className="font-body-sm text-muted">
              One dollar in, one dollar out. No spread, no slippage, no protocol
              fees.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="text-3xl mb-4">24/7</div>
            <h3 className="font-h3 text-white mb-2">No Lockups</h3>
            <p className="font-body-sm text-muted">
              Withdraw any available stablecoin instantly, anytime, no
              restrictions.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="text-3xl mb-4">FIFO</div>
            <h3 className="font-h3 text-white mb-2">Queue-Based</h3>
            <p className="font-body-sm text-muted">
              Want a stablecoin that&apos;s not currently in reserves? Join the
              queue and get filled automatically when it arrives.
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
              href={`https://etherscan.io/address/${CONTRACTS.mainnet.dollarStore}`}
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

      {/* Security & Audits */}
      <section className="py-16 border-t border-border">
        <div className="max-w-3xl mx-auto text-center">
          <h2 className="font-h2 text-white mb-6">Security & Audits</h2>
          <p className="font-body text-muted mb-10">
            Dollar Store smart contracts have been audited by OpenZeppelin, a leading
            blockchain security firm. The audit covered all core protocol logic including
            deposits, withdrawals, swaps, queue management, and depeg protection.
          </p>
          <Link
            href="/dollarstore-audit-openzeppelin.pdf"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex flex-col items-center gap-3 group"
          >
            <div className="bg-deep-green border border-border group-hover:border-dollar-green rounded-md px-8 py-6 transition-colors">
              <svg
                viewBox="0 0 200 40"
                className="h-8 w-auto"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <g transform="translate(0, 2) scale(1.9)">
                  <path d="M0 18.9539C2.17294 15.313 4.01936 12.3103 6.36619 8.19498C7.19516 6.80627 8.62757 5.94336 10.3959 5.94336H13.1744L5.41504 18.9539H0Z" fill="#2E99FF"/>
                  <path d="M0.0234375 0H16.6958L13.8471 4.8101H0.0234375V0Z" fill="#4F56FA"/>
                  <path d="M8.37464 15.9582C9.0016 14.8849 10.0094 14.218 11.421 14.218L16.6989 14.2041V18.9543H6.58594C7.2191 17.9027 7.76889 16.9952 8.37464 15.9582Z" fill="#09C2FF"/>
                </g>
                <text
                  x="42" y="27"
                  className="fill-white"
                  fontFamily="system-ui, sans-serif"
                  fontSize="20"
                  fontWeight="600"
                >
                  OpenZeppelin
                </text>
              </svg>
            </div>
            <span className="text-sm text-muted group-hover:text-dollar-green transition-colors">
              View Audit Report
            </span>
          </Link>
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
