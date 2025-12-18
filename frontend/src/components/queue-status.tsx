"use client";

import { useEffect } from "react";
import { useAccount } from "wagmi";
import { STABLECOINS, StablecoinSymbol } from "@/config/contracts";
import { useQueueDepths, useUserQueuePosition, useQueueActions } from "@/hooks/useQueue";

function UserQueuePosition({ stablecoin }: { stablecoin: StablecoinSymbol }) {
  const position = useUserQueuePosition(stablecoin);
  const queueActions = useQueueActions();

  // Auto-clear success state
  useEffect(() => {
    if (queueActions.cancelSuccess) {
      const timer = setTimeout(() => {
        queueActions.reset();
        position.refetch();
      }, 2000);
      return () => clearTimeout(timer);
    }
  }, [queueActions.cancelSuccess]);

  if (!position.hasPosition) return null;

  const formatTime = (timestamp: number) => {
    if (timestamp === 0) return "Just now";
    const diff = Date.now() - timestamp * 1000;
    const hours = Math.floor(diff / 3600000);
    if (hours < 1) return "< 1 hour ago";
    if (hours === 1) return "1 hour ago";
    if (hours < 24) return `${hours} hours ago`;
    const days = Math.floor(hours / 24);
    return `${days} day${days > 1 ? "s" : ""} ago`;
  };

  const isCanceling = queueActions.step === "canceling" || queueActions.isCanceling;

  return (
    <div className="p-5 bg-black rounded-sm border border-border hover:border-dollar-green">
      <div className="flex items-center justify-between mb-2">
        <span className="font-medium text-sm">Waiting for {stablecoin}</span>
        <span className="font-caption text-muted">
          {formatTime(position.timestamp)}
        </span>
      </div>
      <div className="flex items-center justify-between mb-4">
        <span className="text-2xl tabular-nums text-white">
          {Number(position.formatted).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
        </span>
        <span className="font-body-sm text-dollar-green">$DLRS</span>
      </div>

      {queueActions.error && (
        <p className="text-error font-caption mb-2">{queueActions.error}</p>
      )}

      {queueActions.cancelSuccess ? (
        <div className="w-full py-2 px-4 bg-dollar-green/15 text-dollar-green rounded-sm text-sm font-medium text-center">
          Cancelled!
        </div>
      ) : (
        <button
          onClick={() => {
            if (position.positionId !== null) {
              queueActions.executeCancelQueue(position.positionId);
            }
          }}
          disabled={isCanceling || position.positionId === null}
          className="w-full py-2 px-4 bg-error/15 hover:bg-error/25 text-error rounded-sm text-sm font-medium disabled:opacity-50"
        >
          {isCanceling ? (
            <>
              <span className="inline-block w-3 h-3 border-2 border-error/30 border-t-error rounded-full animate-spin mr-2" />
              Canceling...
            </>
          ) : (
            "Cancel Position"
          )}
        </button>
      )}

      {queueActions.cancelHash && (
        <a
          href={`https://sepolia.etherscan.io/tx/${queueActions.cancelHash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="block mt-2 font-caption text-muted hover:text-white underline text-center"
        >
          View transaction
        </a>
      )}
    </div>
  );
}

export function QueueStatus() {
  const { isConnected } = useAccount();
  const { depths, isDeployed, refetch } = useQueueDepths();
  const usdcPosition = useUserQueuePosition("USDC");
  const usdtPosition = useUserQueuePosition("USDT");

  const formatAmount = (amount: bigint, decimals: number = 6) => {
    const num = Number(amount) / 10 ** decimals;
    return new Intl.NumberFormat("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };

  const hasAnyPosition = usdcPosition.hasPosition || usdtPosition.hasPosition;

  return (
    <div className="space-y-6">
      {/* Queue Depths */}
      <div className="bg-deep-green rounded-md p-6 border border-border">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-h3 text-white">Swap Demand</h2>
          <button
            onClick={() => refetch()}
            className="font-caption text-muted hover:text-white"
          >
            Refresh
          </button>
        </div>
        <p className="font-body-sm text-muted mb-4">
          Total $DLRS waiting to be exchanged for each stablecoin
        </p>

        <div className="space-y-3">
          {(Object.keys(STABLECOINS) as StablecoinSymbol[]).map((symbol) => {
            const depth = depths[symbol];
            const hasQueue = depth > 0n;

            return (
              <div
                key={symbol}
                className="flex items-center justify-between p-4 bg-black rounded-sm border border-border"
              >
                <div className="flex items-center gap-3">
                  <div
                    className={`w-3 h-3 rounded-full ${
                      symbol === "USDC" ? "bg-[#2775CA]" : "bg-[#26A17B]"
                    }`}
                  />
                  <span className="font-medium text-sm">{symbol}</span>
                </div>
                <div className="text-right">
                  {hasQueue ? (
                    <span className="text-gold tabular-nums">
                      {formatAmount(depth)} waiting
                    </span>
                  ) : (
                    <span className="text-dollar-green">No queue</span>
                  )}
                </div>
              </div>
            );
          })}
        </div>

      </div>

      {/* User's Queue Positions */}
      <div className="bg-deep-green rounded-md p-6 border border-border">
        <h2 className="font-h3 text-white mb-6">Your Queue Positions</h2>

        {!isConnected ? (
          <p className="text-muted text-center py-8 font-body-sm">
            Connect wallet to view your positions
          </p>
        ) : !hasAnyPosition ? (
          <p className="text-muted text-center py-8 font-body-sm">
            You have no active queue positions
          </p>
        ) : (
          <div className="space-y-4">
            <UserQueuePosition stablecoin="USDC" />
            <UserQueuePosition stablecoin="USDT" />
          </div>
        )}
      </div>

      {/* Info Card */}
      <div className="bg-deep-green/50 rounded-md p-5 border border-border">
        <h3 className="font-medium text-sm mb-3">How the queue works</h3>
        <ul className="font-body-sm text-muted space-y-2">
          <li className="flex items-start gap-2">
            <span className="text-dollar-green">1.</span>
            Positions are filled FIFO (first in, first out)
          </li>
          <li className="flex items-start gap-2">
            <span className="text-dollar-green">2.</span>
            When someone deposits the stablecoin you want, your position gets
            filled automatically
          </li>
          <li className="flex items-start gap-2">
            <span className="text-dollar-green">3.</span>
            You can cancel anytime and get your $DLRS back
          </li>
          <li className="flex items-start gap-2">
            <span className="text-dollar-green">4.</span>
            Partial fills are possible - you&apos;ll receive what&apos;s available
          </li>
        </ul>
      </div>
    </div>
  );
}
