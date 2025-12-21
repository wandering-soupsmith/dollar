import { StakeDashboard } from "@/components/stake-dashboard";
import { StakeInterface } from "@/components/stake-interface";
import { EmissionsStats } from "@/components/emissions-stats";

export default function StakePage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12 relative">
      {/* Coming Soon Overlay */}
      <div className="absolute inset-0 z-20 flex items-center justify-center bg-black/60 backdrop-blur-sm rounded-lg">
        <div className="text-center p-8">
          <div className="inline-flex items-center justify-center w-20 h-20 bg-dollar-green/20 rounded-full mb-6">
            <span className="text-5xl text-dollar-green">&#162;</span>
          </div>
          <h2 className="font-h1 text-white mb-4">Coming Soon</h2>
          <p className="font-body text-muted max-w-md">
            CENTS staking is not yet available. Check back soon for updates on launch timing.
          </p>
        </div>
      </div>

      {/* Blurred Content */}
      <div className="blur-sm pointer-events-none select-none">
        {/* Header */}
        <div className="text-center mb-12">
          <div className="inline-flex items-center gap-2 px-4 py-2 bg-dollar-green/10 rounded-full mb-4">
            <span className="text-dollar-green text-lg">&#162;</span>
            <span className="text-dollar-green font-medium text-sm">CENTS Token</span>
          </div>
          <h1 className="font-h1 text-white mb-4">Stake & Earn</h1>
          <p className="font-body text-muted max-w-2xl mx-auto">
            Stake CENTS to unlock queue priority.
            Earn CENTS by providing liquidity to the queue or by filling orders.
          </p>
        </div>

        {/* Main Content */}
        <div className="grid lg:grid-cols-3 gap-8">
          {/* Left Column - Stake Interface */}
          <div className="lg:col-span-1 space-y-6">
            <StakeInterface />
            <EmissionsStats />
          </div>

          {/* Right Column - Dashboard */}
          <div className="lg:col-span-2">
            <StakeDashboard />
          </div>
        </div>
      </div>
    </div>
  );
}
