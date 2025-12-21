"use client";

import { useCentsEmissions } from "@/hooks/useCents";

export function EmissionsStats() {
  const emissions = useCentsEmissions();

  return (
    <div className="bg-deep-green rounded-md border border-border overflow-hidden">
      {/* Header */}
      <div className="px-6 py-4 border-b border-border">
        <h2 className="font-h3 text-white">CENTS Emissions</h2>
        <p className="text-muted font-caption mt-1">
          Total supply: 1B CENTS (800M user rewards + 200M founder)
        </p>
      </div>

      <div className="p-6">
        <div className="grid md:grid-cols-3 gap-6">
          {/* Maker Rewards */}
          <div className="bg-black rounded-sm p-4 border border-border">
            <div className="flex items-center justify-between mb-3">
              <span className="text-muted font-body-sm">Maker Rewards</span>
              <span className="text-dollar-green font-caption">{emissions.makerPercentage.toFixed(1)}% emitted</span>
            </div>
            <div className="text-lg tabular-nums mb-2">
              {(Number(emissions.makerEmitted) / 1_000_000).toFixed(2)}M
              <span className="text-muted text-sm ml-1">/ 600M</span>
            </div>
            {/* Progress bar */}
            <div className="h-1.5 bg-border rounded-full overflow-hidden">
              <div
                className="h-full bg-dollar-green transition-all duration-500"
                style={{ width: `${Math.min(emissions.makerPercentage, 100)}%` }}
              />
            </div>
            <p className="text-muted font-caption mt-2">
              8% APY on queued DLRS, paid on fill
            </p>
          </div>

          {/* Taker Rewards */}
          <div className="bg-black rounded-sm p-4 border border-border">
            <div className="flex items-center justify-between mb-3">
              <span className="text-muted font-body-sm">Taker Rewards</span>
              <span className="text-dollar-green font-caption">{emissions.takerPercentage.toFixed(1)}% emitted</span>
            </div>
            <div className="text-lg tabular-nums mb-2">
              {(Number(emissions.takerEmitted) / 1_000_000).toFixed(2)}M
              <span className="text-muted text-sm ml-1">/ 200M</span>
            </div>
            {/* Progress bar */}
            <div className="h-1.5 bg-border rounded-full overflow-hidden">
              <div
                className="h-full bg-dollar-green transition-all duration-500"
                style={{ width: `${Math.min(emissions.takerPercentage, 100)}%` }}
              />
            </div>
            <p className="text-muted font-caption mt-2">
              Earned when deposits clear queue
            </p>
          </div>

          {/* Founder Vesting */}
          <div className="bg-black rounded-sm p-4 border border-border">
            <div className="flex items-center justify-between mb-3">
              <span className="text-muted font-body-sm">Founder Vesting</span>
              <span className="text-gold font-caption">{emissions.founderPercentage.toFixed(1)}% vested</span>
            </div>
            <div className="text-lg tabular-nums mb-2">
              {(Number(emissions.founderVested) / 1_000_000).toFixed(2)}M
              <span className="text-muted text-sm ml-1">/ 200M</span>
            </div>
            {/* Progress bar */}
            <div className="h-1.5 bg-border rounded-full overflow-hidden">
              <div
                className="h-full bg-gold transition-all duration-500"
                style={{ width: `${Math.min(emissions.founderPercentage, 100)}%` }}
              />
            </div>
            <p className="text-muted font-caption mt-2">
              1:4 ratio with user emissions
            </p>
          </div>
        </div>

        {/* Total Minted */}
        <div className="mt-6 pt-6 border-t border-border">
          <div className="flex items-center justify-between">
            <span className="text-muted font-body-sm">Total CENTS Minted</span>
            <span className="text-lg tabular-nums">
              {(Number(emissions.totalMinted) / 1_000_000).toFixed(2)}M
              <span className="text-muted text-sm ml-1">/ 1,000M</span>
            </span>
          </div>
        </div>
      </div>
    </div>
  );
}
