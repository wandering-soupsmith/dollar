"use client";

import { useState, useCallback, useMemo } from "react";
import {
  useReadContract,
  useReadContracts,
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

  return {
    depths: {
      USDC: (usdcDepth as bigint) ?? 0n,
      USDT: (usdtDepth as bigint) ?? 0n,
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

  const stablecoinAddress =
    stablecoin === "USDC" ? contracts.usdc : contracts.usdt;

  // Get user's position IDs
  const {
    data: positionIds,
    isLoading: isLoadingIds,
    refetch: refetchIds,
  } = useReadContract({
    address: contracts.dollarStore,
    abi: dollarStoreABI,
    functionName: "getUserQueuePositions",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: isDeployed && !!userAddress,
      refetchInterval: 10000,
    },
  });

  // Build contracts array for multicall to fetch all position details
  const positionContracts = useMemo(() => {
    if (!positionIds || positionIds.length === 0) return [];
    return positionIds.map((id) => ({
      address: contracts.dollarStore as `0x${string}`,
      abi: dollarStoreABI,
      functionName: "getQueuePosition" as const,
      args: [id] as const,
    }));
  }, [positionIds, contracts.dollarStore]);

  // Fetch all position details in one multicall
  const {
    data: positionDetails,
    isLoading: isLoadingDetails,
    refetch: refetchDetails,
  } = useReadContracts({
    contracts: positionContracts,
    query: {
      enabled: positionContracts.length > 0,
      refetchInterval: 10000,
    },
  });

  // Find the position matching the requested stablecoin
  const matchingPosition = useMemo(() => {
    if (!positionIds || !positionDetails) return null;

    for (let i = 0; i < positionDetails.length; i++) {
      const result = positionDetails[i];
      if (result.status === "success" && result.result) {
        const [owner, positionStablecoin, amount, timestamp] = result.result as [
          `0x${string}`,
          `0x${string}`,
          bigint,
          bigint
        ];
        // Check if this position is for the stablecoin we're looking for
        if (
          positionStablecoin.toLowerCase() === stablecoinAddress.toLowerCase() &&
          amount > 0n
        ) {
          return {
            positionId: positionIds[i],
            owner,
            stablecoin: positionStablecoin,
            amount,
            timestamp: Number(timestamp),
          };
        }
      }
    }
    return null;
  }, [positionIds, positionDetails, stablecoinAddress]);

  const refetch = useCallback(() => {
    refetchIds();
    refetchDetails();
  }, [refetchIds, refetchDetails]);

  // DLRS has 18 decimals
  const decimals = 18;

  return {
    positionId: matchingPosition?.positionId ?? null,
    amount: matchingPosition?.amount ?? 0n,
    formatted: formatUnits(matchingPosition?.amount ?? 0n, decimals),
    timestamp: matchingPosition?.timestamp ?? 0,
    hasPosition: matchingPosition !== null && matchingPosition.amount > 0n,
    isLoading: isLoadingIds || isLoadingDetails,
    error: null,
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
    async (positionId: bigint) => {
      if (!userAddress) {
        setError("Wallet not connected");
        return;
      }

      try {
        setError(null);
        setStep("canceling");

        await cancelQueue({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "cancelQueue",
          args: [positionId],
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
