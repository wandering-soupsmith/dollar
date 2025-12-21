"use client";

import { useAccount } from "wagmi";
import { useCentsStaking, formatDuration } from "@/hooks/useCents";

export function StakeDashboard() {
  const { isConnected } = useAccount();
  const staking = useCentsStaking();

  if (!staking.isDeployed) {
    return null;
  }

  // Calculate power progress for visual
  const powerProgress = Math.min(staking.powerPercentage, 100);

  // Calculate time staked in days
  const now = Math.floor(Date.now() / 1000);
  const daysStaked = staking.stakedSince > 0
    ? Math.floor((now - staking.stakedSince) / 86400)
    : 0;

  // Calculate queue boost multiplier for different order sizes
  const stakePowerNum = Number(staking.stakePower);
  const getQueueBoost = (orderSize: number) => {
    if (stakePowerNum === 0) return 1;
    return Math.round(1 + stakePowerNum / Math.sqrt(orderSize));
  };


  return (
    <div className="space-y-6">
      {/* Hero Stats */}
      <div className="bg-deep-green rounded-md border border-border overflow-hidden">
        <div className="px-6 py-4 border-b border-border flex items-center justify-between">
          <h2 className="font-h3 text-white">Your CENTS Position</h2>
          {staking.isUnstaking && (
            <span className="px-3 py-1 bg-gold/20 text-gold text-xs font-medium rounded-full">
              Unstaking
            </span>
          )}
        </div>

        {!isConnected ? (
          <div className="p-8 text-center">
            <div className="w-16 h-16 bg-dollar-green/10 rounded-full flex items-center justify-center mx-auto mb-4">
              <span className="text-3xl text-dollar-green">&#162;</span>
            </div>
            <p className="text-muted font-body-sm mb-2">Connect your wallet</p>
            <p className="text-muted font-caption">View your CENTS position and staking benefits</p>
          </div>
        ) : (
          <div className="p-6">
            {/* Top Row - Key Metrics */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
              {/* Total CENTS */}
              <div className="bg-black rounded-sm p-4 border border-border">
                <p className="text-muted font-caption mb-1">Total CENTS</p>
                <p className="text-xl tabular-nums font-medium">
                  {(Number(staking.staked) + Number(staking.walletBalance)).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                </p>
              </div>

              {/* Staked */}
              <div className="bg-black rounded-sm p-4 border border-border">
                <p className="text-muted font-caption mb-1">Staked</p>
                <p className="text-xl tabular-nums font-medium text-dollar-green">
                  {Number(staking.staked).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                </p>
              </div>

              {/* Wallet */}
              <div className="bg-black rounded-sm p-4 border border-border">
                <p className="text-muted font-caption mb-1">In Wallet</p>
                <p className="text-xl tabular-nums font-medium">
                  {Number(staking.walletBalance).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                </p>
              </div>

              {/* Days Staked */}
              <div className="bg-black rounded-sm p-4 border border-border">
                <p className="text-muted font-caption mb-1">Days Staked</p>
                <p className="text-xl tabular-nums font-medium">
                  {daysStaked} <span className="text-muted text-sm">/ 30</span>
                </p>
              </div>
            </div>

            {/* Stake Power Section */}
            <div className="bg-black rounded-sm p-5 border border-border mb-6">
              <div className="flex items-start justify-between mb-4">
                <div>
                  <h3 className="text-white font-medium mb-1">Stake Power</h3>
                  <p className="text-muted font-caption">
                    Your effective staking power based on amount and time
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-2xl tabular-nums font-medium text-dollar-green">
                    {Number(staking.stakePower).toLocaleString(undefined, { maximumFractionDigits: 0 })}
                  </p>
                  <p className="text-muted font-caption">{staking.powerPercentage}% of maximum</p>
                </div>
              </div>

              {/* Power Progress Bar */}
              <div className="relative">
                <div className="h-3 bg-border rounded-full overflow-hidden">
                  <div
                    className="h-full bg-gradient-to-r from-dollar-green/70 to-dollar-green transition-all duration-500"
                    style={{ width: `${powerProgress}%` }}
                  />
                </div>
                {/* Markers */}
                <div className="flex justify-between mt-2 text-xs text-muted">
                  <span>0%</span>
                  <span>25%</span>
                  <span>50%</span>
                  <span>75%</span>
                  <span>100%</span>
                </div>
              </div>

              {/* Power Status */}
              <div className="mt-4 pt-4 border-t border-border">
                {staking.isUnstaking ? (
                  <div className="flex items-center gap-2 text-gold">
                    <span className="w-2 h-2 bg-gold rounded-full animate-pulse" />
                    <span className="font-caption">
                      Power suspended - {staking.canCompleteUnstake
                        ? "Ready to complete unstake"
                        : `${formatDuration(staking.timeUntilUnstakeComplete)} until unstake completes`}
                    </span>
                  </div>
                ) : staking.timeUntilFullPower > 0 ? (
                  <div className="flex items-center gap-2 text-muted">
                    <span className="w-2 h-2 bg-dollar-green rounded-full" />
                    <span className="font-caption">
                      Full power in {formatDuration(staking.timeUntilFullPower)} ({Math.ceil(staking.timeUntilFullPower / 86400)} days remaining)
                    </span>
                  </div>
                ) : Number(staking.staked) > 0 ? (
                  <div className="flex items-center gap-2 text-dollar-green">
                    <span className="w-2 h-2 bg-dollar-green rounded-full" />
                    <span className="font-caption">Full power achieved!</span>
                  </div>
                ) : (
                  <div className="flex items-center gap-2 text-muted">
                    <span className="w-2 h-2 bg-muted rounded-full" />
                    <span className="font-caption">Stake CENTS to start building power</span>
                  </div>
                )}
              </div>
            </div>

            {/* Benefits Grid */}
            <div className="grid md:grid-cols-1 gap-4">
              {/* Queue Priority Card */}
              <div className="bg-black rounded-sm p-5 border border-border">
                <div className="flex items-center gap-3 mb-4">
                  <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center">
                    <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6" />
                    </svg>
                  </div>
                  <div>
                    <h3 className="text-white font-medium">Queue Priority</h3>
                    <p className="text-muted font-caption">Get filled before others in the queue</p>
                  </div>
                </div>

                <div className="space-y-3">
                  <p className="text-muted font-body-sm">
                    Your fill score multiplier by order size:
                  </p>

                  <div className="space-y-2">
                    <div className="flex justify-between items-center p-2 bg-deep-green rounded-sm">
                      <span className="text-muted font-caption">$100 order</span>
                      <span className="tabular-nums font-medium text-dollar-green">{getQueueBoost(100)}x</span>
                    </div>
                    <div className="flex justify-between items-center p-2 bg-deep-green rounded-sm">
                      <span className="text-muted font-caption">$500 order</span>
                      <span className="tabular-nums font-medium text-dollar-green">{getQueueBoost(500)}x</span>
                    </div>
                    <div className="flex justify-between items-center p-2 bg-deep-green rounded-sm">
                      <span className="text-muted font-caption">$1,000 order</span>
                      <span className="tabular-nums font-medium text-dollar-green">{getQueueBoost(1000)}x</span>
                    </div>
                    <div className="flex justify-between items-center p-2 bg-deep-green rounded-sm">
                      <span className="text-muted font-caption">$10,000 order</span>
                      <span className="tabular-nums font-medium text-dollar-green">{getQueueBoost(10000)}x</span>
                    </div>
                  </div>

                  <p className="text-muted font-caption pt-2 border-t border-border">
                    Fill score = (1 + stakePower / sqrt(orderSize)) * timeInQueue
                  </p>
                </div>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Earning CENTS Section */}
      <div className="bg-deep-green rounded-md border border-border overflow-hidden">
        <div className="px-6 py-4 border-b border-border">
          <h2 className="font-h3 text-white">How to Earn CENTS</h2>
        </div>
        <div className="p-6">
          <div className="grid md:grid-cols-2 gap-6">
            {/* Maker Rewards */}
            <div className="bg-black rounded-sm p-5 border border-border">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 bg-dollar-green/10 text-dollar-green rounded-sm flex items-center justify-center font-semibold">
                  M
                </div>
                <div>
                  <h3 className="text-white font-medium">Maker Rewards</h3>
                  <p className="text-dollar-green font-caption">8% APY on queued DLRS</p>
                </div>
              </div>
              <p className="text-muted font-body-sm mb-4">
                When you join the queue waiting for a specific stablecoin, you earn 8% APY
                on your queued DLRS. Rewards are minted as CENTS when your position is filled.
              </p>
              <div className="bg-deep-green rounded-sm p-3">
                <p className="text-xs text-muted mb-1">Example: Queue $10,000 for 30 days</p>
                <p className="text-sm">
                  Earn <span className="text-dollar-green font-medium">~6,575 CENTS</span> when filled
                </p>
              </div>
            </div>

            {/* Taker Rewards */}
            <div className="bg-black rounded-sm p-5 border border-border">
              <div className="flex items-center gap-3 mb-4">
                <div className="w-10 h-10 bg-gold/10 text-gold rounded-sm flex items-center justify-center font-semibold">
                  T
                </div>
                <div>
                  <h3 className="text-white font-medium">Taker Rewards</h3>
                  <p className="text-gold font-caption">Earn when you fill the queue</p>
                </div>
              </div>
              <p className="text-muted font-body-sm mb-4">
                When you deposit stablecoins that fill queue positions, you earn CENTS
                equal to the 1bp fee that would have been charged (at $0.01/CENTS).
              </p>
              <div className="bg-deep-green rounded-sm p-3">
                <p className="text-xs text-muted mb-1">Example: Deposit clears $100,000 queue</p>
                <p className="text-sm">
                  Earn <span className="text-gold font-medium">1,000 CENTS</span> instantly
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
