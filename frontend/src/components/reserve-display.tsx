"use client";

import { useReserves } from "@/hooks/useReserves";
import { useState, useEffect } from "react";

export function ReserveDisplay() {
  const { reserves, totalReserves, totalSupply, isLoading, error, isDeployed, refetch } =
    useReserves();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  const formatCurrency = (amount: number) => {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(amount);
  };

  if (error) {
    return (
      <div className="bg-deep-green rounded-md p-6 border border-border">
        <p className="text-error font-body-sm">Failed to load reserves</p>
      </div>
    );
  }

  // Show loading state until mounted to prevent hydration mismatch
  if (!mounted) {
    return (
      <div className="bg-deep-green rounded-md p-6 border border-border">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h2 className="font-h3 text-white">Reserve Composition</h2>
            <p className="font-body-sm text-muted mt-1">
              Total $DLRS Supply: <span className="text-white tabular-nums">...</span>
            </p>
          </div>
          <div className="text-right">
            <p className="font-body-sm text-muted">Total Reserves</p>
            <p className="font-display text-dollar-green tabular-nums">...</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-deep-green rounded-md p-6 border border-border">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h2 className="font-h3 text-white">Reserve Composition</h2>
          <p className="font-body-sm text-muted mt-1">
            Total $DLRS Supply:{" "}
            <span className="text-white tabular-nums">
              {Number(totalSupply).toLocaleString()}
            </span>
          </p>
        </div>
        <div className="text-right">
          <p className="font-body-sm text-muted">Total Reserves</p>
          <p className="font-display text-dollar-green tabular-nums">
            {isLoading ? "..." : formatCurrency(totalReserves)}
          </p>
          <button
            onClick={() => refetch()}
            className="font-caption text-muted hover:text-white mt-1"
          >
            Refresh
          </button>
        </div>
      </div>

      <div className="space-y-4">
        {reserves.map((reserve) => {
          const amount = Number(reserve.formatted);
          const percentage =
            totalReserves > 0 ? (amount / totalReserves) * 100 : 0;

          return (
            <div key={reserve.symbol}>
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <div
                    className={`w-3 h-3 rounded-full ${
                      reserve.symbol === "USDC" ? "bg-[#2775CA]" : "bg-[#26A17B]"
                    }`}
                  />
                  <span className="font-medium text-sm">{reserve.symbol}</span>
                </div>
                <div className="text-right">
                  <span className="tabular-nums">{formatCurrency(amount)}</span>
                  <span className="text-muted font-body-sm ml-2">
                    ({percentage.toFixed(1)}%)
                  </span>
                </div>
              </div>
              <div className="h-2 bg-black rounded-full overflow-hidden">
                <div
                  className={`h-full rounded-full transition-all duration-500 ${
                    reserve.symbol === "USDC" ? "bg-[#2775CA]" : "bg-[#26A17B]"
                  }`}
                  style={{ width: `${percentage}%` }}
                />
              </div>
            </div>
          );
        })}
      </div>

    </div>
  );
}
