"use client";

import { useSwapVolume } from "@/hooks/useSwapVolume";

export function VolumeStats() {
  const { formatted, isLoading, error, refetch } = useSwapVolume();

  return (
    <div className="bg-deep-green rounded-md p-4 border border-border">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-sm text-muted">24h Volume:</span>
          <span className="text-sm font-medium text-white tabular-nums">
            {isLoading ? "..." : formatted}
          </span>
        </div>
        <button
          onClick={() => refetch()}
          className="font-caption text-muted hover:text-white"
        >
          Refresh
        </button>
      </div>
    </div>
  );
}
