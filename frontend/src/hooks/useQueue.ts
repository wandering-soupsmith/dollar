"use client";

import { useState, useCallback } from "react";
import {
  useReadContract,
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
  useChainId,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { dollarStoreABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";

export type QueueStep = "idle" | "joining" | "canceling" | "success" | "error";

// Get queue depths for each stablecoin
export function useQueueDepths() {
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const isDeployed =
    contracts.dollarStore !== "0x0000000000000000000000000000000000000000";

  // Get USDC queue depth
  const { data: usdcDepth, refetch: refetchUsdc } = useReadContract({
    address: contracts.dollarStore,
    abi: dollarStoreABI,
    functionName: "getQueueDepth",
    args: [contracts.usdc],
    query: {
      enabled: isDeployed,
      refetchInterval: 10000,
    },
  });

  // Get USDT queue depth
  const { data: usdtDepth, refetch: refetchUsdt } = useReadContract({
    address: contracts.dollarStore,
    abi: dollarStoreABI,
    functionName: "getQueueDepth",
    args: [contracts.usdt],
    query: {
      enabled: isDeployed,
      refetchInterval: 10000,
    },
  });

  const refetch = useCallback(() => {
    refetchUsdc();
    refetchUsdt();
  }, [refetchUsdc, refetchUsdt]);

  // Mock data when not deployed
  const mockData = {
    USDC: 0n,
    USDT: 150000n * 10n ** 6n,
  };

  return {
    depths: {
      USDC: isDeployed ? (usdcDepth as bigint) ?? 0n : mockData.USDC,
      USDT: isDeployed ? (usdtDepth as bigint) ?? 0n : mockData.USDT,
    },
    isDeployed,
    refetch,
  };
}

// Get user's queue position for a stablecoin
export function useUserQueuePosition(stablecoin: StablecoinSymbol) {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const isDeployed =
    contracts.dollarStore !== "0x0000000000000000000000000000000000000000";

  const tokenAddress =
    stablecoin === "USDC" ? contracts.usdc : contracts.usdt;

  const { data, isLoading, error, refetch } = useReadContract({
    address: contracts.dollarStore,
    abi: dollarStoreABI,
    functionName: "getUserQueuePosition",
    args: userAddress ? [userAddress, tokenAddress] : undefined,
    query: {
      enabled: isDeployed && !!userAddress,
      refetchInterval: 10000,
    },
  });

  // Data format: [amount, timestamp]
  const position = data as [bigint, bigint] | undefined;
  const amount = position?.[0] ?? 0n;
  const timestamp = position?.[1] ?? 0n;
  const decimals = STABLECOINS[stablecoin].decimals;

  return {
    amount,
    formatted: formatUnits(amount, decimals),
    timestamp: Number(timestamp),
    hasPosition: amount > 0n,
    isLoading,
    error,
    refetch,
    isDeployed,
  };
}

// Hook for joining and canceling queue
export function useQueueActions() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const [step, setStep] = useState<QueueStep>("idle");
  const [error, setError] = useState<string | null>(null);

  // Contract write hooks
  const { writeContract: joinQueue, data: joinHash } = useWriteContract();
  const { writeContract: cancelQueue, data: cancelHash } = useWriteContract();

  // Wait for transactions
  const { isLoading: isJoining, isSuccess: joinSuccess } =
    useWaitForTransactionReceipt({ hash: joinHash });
  const { isLoading: isCanceling, isSuccess: cancelSuccess } =
    useWaitForTransactionReceipt({ hash: cancelHash });

  const executeJoinQueue = useCallback(
    async (stablecoin: StablecoinSymbol, dlrsAmount: string) => {
      if (!userAddress) {
        setError("Wallet not connected");
        return;
      }

      const tokenAddress =
        stablecoin === "USDC" ? contracts.usdc : contracts.usdt;
      // DLRS has 18 decimals
      const amountBn = parseUnits(dlrsAmount, 18);

      try {
        setError(null);
        setStep("joining");

        await joinQueue({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "joinQueue",
          args: [tokenAddress, amountBn],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Failed to join queue");
      }
    },
    [userAddress, contracts, joinQueue]
  );

  const executeCancelQueue = useCallback(
    async (stablecoin: StablecoinSymbol) => {
      if (!userAddress) {
        setError("Wallet not connected");
        return;
      }

      const tokenAddress =
        stablecoin === "USDC" ? contracts.usdc : contracts.usdt;

      try {
        setError(null);
        setStep("canceling");

        await cancelQueue({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "cancelQueue",
          args: [tokenAddress],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Failed to cancel queue position");
      }
    },
    [userAddress, contracts, cancelQueue]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
  }, []);

  return {
    step,
    error,
    isJoining,
    isCanceling,
    joinSuccess,
    cancelSuccess,
    executeJoinQueue,
    executeCancelQueue,
    reset,
    joinHash,
    cancelHash,
  };
}
