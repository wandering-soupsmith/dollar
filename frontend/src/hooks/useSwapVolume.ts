"use client";

import { useState, useEffect, useCallback } from "react";
import { usePublicClient, useChainId } from "wagmi";
import { parseAbiItem } from "viem";
import { CONTRACTS } from "@/config/contracts";

// Block time estimates (in seconds)
const MAINNET_BLOCK_TIME = 12;
const SEPOLIA_BLOCK_TIME = 12;

const ONE_DAY = 24 * 60 * 60;

// Deployment blocks (to avoid querying from genesis)
const DEPLOYMENT_BLOCKS = {
  mainnet: 24638428n, // DollarStore v2 mainnet deployment
  sepolia: 7400000n,  // Approximate
};

export function useSwapVolume() {
  const publicClient = usePublicClient();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const isDeployed = contracts.dollarStore !== "0x0000000000000000000000000000000000000000";

  const [volume24h, setVolume24h] = useState<bigint>(0n);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const blockTime = chainId === 1 ? MAINNET_BLOCK_TIME : SEPOLIA_BLOCK_TIME;
  const deploymentBlock = chainId === 1 ? DEPLOYMENT_BLOCKS.mainnet : DEPLOYMENT_BLOCKS.sepolia;

  const fetchVolume = useCallback(async () => {
    if (!publicClient || !isDeployed) {
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
      const currentBlock = await publicClient.getBlockNumber();
      const blocks24h = BigInt(Math.floor(ONE_DAY / blockTime));

      // Use the later of: 24h ago OR deployment block
      const block24hAgo = currentBlock > blocks24h ? currentBlock - blocks24h : 0n;
      const fromBlock = block24hAgo > deploymentBlock ? block24hAgo : deploymentBlock;

      const swapEvent = parseAbiItem(
        "event Swap(address indexed user, address indexed fromStablecoin, address indexed toStablecoin, uint256 amountIn, uint256 amountOut, uint256 amountQueued)"
      );

      const queueFilledEvent = parseAbiItem(
        "event QueueFilled(uint256 indexed positionId, address indexed user, address indexed stablecoin, uint256 amountFilled, uint256 amountRemaining)"
      );

      // Fetch both Swap and QueueFilled events
      const [swapLogs, queueFilledLogs] = await Promise.all([
        publicClient.getLogs({
          address: contracts.dollarStore,
          event: swapEvent,
          fromBlock,
          toBlock: currentBlock,
        }),
        publicClient.getLogs({
          address: contracts.dollarStore,
          event: queueFilledEvent,
          fromBlock,
          toBlock: currentBlock,
        }),
      ]);

      let total = 0n;

      // Count Swap events: amountIn + amountOut (both sides)
      for (const log of swapLogs) {
        const amountIn = log.args.amountIn ?? 0n;
        const amountOut = log.args.amountOut ?? 0n;
        total += amountIn + amountOut;
      }

      // Count QueueFilled events: amountFilled * 2 (both sides of the fill)
      for (const log of queueFilledLogs) {
        const amountFilled = log.args.amountFilled ?? 0n;
        total += amountFilled * 2n;
      }

      setVolume24h(total);
    } catch (err) {
      console.error("Failed to fetch swap volume:", err);
      setError(err instanceof Error ? err.message : "Failed to fetch volume");
    } finally {
      setIsLoading(false);
    }
  }, [publicClient, isDeployed, contracts.dollarStore, blockTime, deploymentBlock]);

  useEffect(() => {
    fetchVolume();
  }, [fetchVolume]);

  // Format volume for display (e.g., $1.23k, $12.3k, $123k)
  const formatVolume = (amount: bigint) => {
    const num = Number(amount) / 10 ** 6;
    if (num >= 1000000) {
      return `$${(num / 1000000).toFixed(1)}M`;
    } else if (num >= 1000) {
      return `$${(num / 1000).toFixed(1)}k`;
    } else if (num > 0) {
      return `$${num.toFixed(0)}`;
    }
    return "$0";
  };

  return {
    volume24h,
    formatted: formatVolume(volume24h),
    isLoading,
    error,
    refetch: fetchVolume,
  };
}
