import { SwapInterface } from "@/components/swap-interface";
import { QueueStatus } from "@/components/queue-status";

export default function SwapPage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12">
      <div className="text-center mb-12">
        <h1 className="font-h1 text-white mb-4">Swap Stablecoins</h1>
        <p className="font-body text-muted max-w-xl mx-auto">
          Swap between USDC and USDT instantly when reserves are available.
          If not, join the queue and get filled when deposits come in.
        </p>
      </div>

      <div className="grid lg:grid-cols-2 gap-8">
        {/* Swap Interface */}
        <div>
          <SwapInterface />
        </div>

        {/* Queue Status */}
        <div>
          <QueueStatus />
        </div>
      </div>
    </div>
  );
}
