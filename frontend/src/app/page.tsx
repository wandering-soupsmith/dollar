import { ReserveDisplay } from "@/components/reserve-display";
import { DepositRedeem } from "@/components/deposit-redeem";
import Link from "next/link";

export default function Home() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12">
      {/* Hero */}
      <section className="text-center mb-16">
        <h1 className="font-body text-lg text-white mb-4">
          where everything is a <span className="text-dollar-green">dollar</span>
        </h1>
        <p className="font-body text-lg text-muted max-w-2xl mx-auto mb-8">
          Institutional-grade stablecoin aggregator. Deposit any dollar, get $DLRS.
          Redeem $DLRS for any dollar. No fees. No complexity.
        </p>
        <div className="flex items-center justify-center gap-4">
          <Link
            href="/swap"
            className="px-6 py-3 bg-dollar-green hover:bg-dollar-green-light text-black rounded-sm font-medium text-sm"
          >
            Start Swapping
          </Link>
          <Link
            href="https://github.com/dollarstore"
            target="_blank"
            rel="noopener noreferrer"
            className="px-6 py-3 bg-transparent border border-border hover:border-dollar-green hover:bg-hover text-white rounded-sm font-medium text-sm"
          >
            View Code
          </Link>
        </div>
      </section>

      {/* Reserve Display */}
      <section className="mb-16">
        <ReserveDisplay />
      </section>

      {/* Deposit / Redeem */}
      <section className="mb-16">
        <DepositRedeem />
      </section>

      {/* How it works */}
      <section className="mb-16">
        <h2 className="font-h2 text-white mb-8 text-center">How it works</h2>
        <div className="grid md:grid-cols-3 gap-6">
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              1
            </div>
            <h3 className="font-h3 text-white mb-2">Deposit</h3>
            <p className="font-body-sm text-muted">
              Deposit USDC or USDT and receive $DLRS at a 1:1 ratio. Your
              stablecoin enters the shared reserve pool.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              2
            </div>
            <h3 className="font-h3 text-white mb-2">Hold $DLRS</h3>
            <p className="font-body-sm text-muted">
              $DLRS is backed 1:1 by the basket of stablecoins in reserves. It's
              fully fungible regardless of what you deposited.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              3
            </div>
            <h3 className="font-h3 text-white mb-2">Redeem</h3>
            <p className="font-body-sm text-muted">
              Burn $DLRS to withdraw any available stablecoin from the reserves.
              If your preferred coin isn't available, queue up.
            </p>
          </div>
        </div>
      </section>

      {/* Risk notice */}
      <section className="bg-gold/10 rounded-md p-6 border border-gold/30">
        <h3 className="font-h3 text-gold mb-2">Risk Notice</h3>
        <p className="font-body-sm text-muted">
          dollarstore does not manage risk at the protocol level. By holding
          $DLRS, you accept exposure to the basket of stablecoins in reserves.
          If any underlying stablecoin depegs, $DLRS holders share that risk.
          This is a &quot;fair weather&quot; product designed for sophisticated users who
          understand and accept these tradeoffs.
        </p>
      </section>
    </div>
  );
}
