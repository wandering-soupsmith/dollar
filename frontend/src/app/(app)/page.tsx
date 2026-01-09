import { ReserveDisplay } from "@/components/reserve-display";
import { SwapInterface } from "@/components/swap-interface";
import { QueueStatus } from "@/components/queue-status";
import { VolumeStats } from "@/components/volume-stats";

export default function Home() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12">
      {/* Hero */}
      <section className="text-center mb-12">
        <h1 className="font-body text-lg text-white mb-4">
          swap stablecoins <span className="text-dollar-green">1:1</span>
        </h1>
        <p className="font-body text-lg text-muted max-w-xl mx-auto">
          No fees. No slippage. No complexity.
        </p>
      </section>

      {/* Reserve Display */}
      <section className="mb-8">
        <ReserveDisplay />
      </section>

      {/* Swap + Queue */}
      <section className="grid lg:grid-cols-2 gap-8 mb-16">
        <div className="space-y-4">
          <SwapInterface />
          <VolumeStats />
        </div>
        <div>
          <QueueStatus />
        </div>
      </section>

      {/* How the protocol works */}
      <section className="mb-16">
        <h2 className="font-h2 text-white mb-8 text-center">How the protocol works</h2>
        <div className="grid md:grid-cols-3 gap-6">
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              1
            </div>
            <h3 className="font-h3 text-white mb-2">Select</h3>
            <p className="font-body-sm text-muted">
              Choose which stablecoin you have and which one you want.
              USDC, USDT — all dollars are equal here.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              2
            </div>
            <h3 className="font-h3 text-white mb-2">Submit</h3>
            <p className="font-body-sm text-muted">
              If reserves are available, the swap executes instantly at exactly 1:1.
              No spread, no fees, no slippage.
            </p>
          </div>
          <div className="bg-deep-green rounded-md p-6 border border-border">
            <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center mb-4 font-semibold">
              3
            </div>
            <h3 className="font-h3 text-white mb-2">Queue</h3>
            <p className="font-body-sm text-muted">
              If reserves are low, positions queue and fill automatically
              when opposing liquidity is deposited. First in, first out.
            </p>
          </div>
        </div>
      </section>

      {/* Risk notice */}
      <section className="bg-gold/10 rounded-md p-6 border border-gold/30">
        <h3 className="font-h3 text-gold mb-2">Risk Notice</h3>
        <p className="font-body-sm text-muted">
          The protocol treats all supported stablecoins as equivalent. If any underlying
          stablecoin depegs, users interacting with the protocol share that risk.
          This is autonomous software used entirely at your own risk.
        </p>
      </section>
    </div>
  );
}
