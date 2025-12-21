"use client";

import { useReadContract, useReadContracts, useAccount, useChainId, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { formatUnits, parseUnits } from "viem";
import { centsABI } from "@/config/abis";
import { CONTRACTS } from "@/config/contracts";
import { useState, useEffect } from "react";

const CENTS_DECIMALS = 6;
const FULL_POWER_DURATION = 30 * 24 * 60 * 60; // 30 days in seconds
const UNSTAKE_COOLDOWN = 7 * 24 * 60 * 60; // 7 days in seconds

export function useCentsBalance() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const { data, isLoading, error, refetch } = useReadContract({
    address: contracts.cents,
    abi: centsABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && contracts.cents !== "0x0000000000000000000000000000000000000000",
      refetchInterval: 10000,
    },
  });

  const balance = data ?? 0n;
  const formatted = formatUnits(balance, CENTS_DECIMALS);

  return {
    balance,
    formatted,
    isLoading,
    error,
    refetch,
  };
}

export function useCentsStaking() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const centsAddress = contracts.cents;
  const isDeployed = centsAddress !== "0x0000000000000000000000000000000000000000";

  // Get staking info
  const { data: stakingInfo, isLoading: stakingLoading, refetch: refetchStaking } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "getStakingInfo",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && isDeployed,
      refetchInterval: 10000,
    },
  });

  // Get daily fee-free cap
  const { data: feeFreeCap, refetch: refetchFeeFree } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "getDailyFeeFreeCap",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && isDeployed,
      refetchInterval: 10000,
    },
  });

  // Get daily redemption used
  const { data: redemptionUsed } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "dailyRedemptionUsed",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && isDeployed,
      refetchInterval: 10000,
    },
  });

  // Get wallet balance
  const { data: walletBalance, refetch: refetchBalance } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && isDeployed,
      refetchInterval: 10000,
    },
  });

  const refetch = () => {
    refetchStaking();
    refetchFeeFree();
    refetchBalance();
  };

  // Parse staking info
  const staked = stakingInfo?.[0] ?? 0n;
  const stakePower = stakingInfo?.[1] ?? 0n;
  const stakedSince = stakingInfo?.[2] ?? 0n;
  const unstakeTime = stakingInfo?.[3] ?? 0n;
  const isUnstaking = stakingInfo?.[4] ?? false;

  // Calculate power percentage (0-100)
  const powerPercentage = staked > 0n
    ? Number((stakePower * 100n) / staked)
    : 0;

  // Calculate time until full power
  const now = BigInt(Math.floor(Date.now() / 1000));
  const timeStaked = stakedSince > 0n ? now - stakedSince : 0n;
  const timeUntilFullPower = timeStaked < BigInt(FULL_POWER_DURATION)
    ? BigInt(FULL_POWER_DURATION) - timeStaked
    : 0n;

  // Calculate time until unstake complete
  const timeUntilUnstakeComplete = isUnstaking && unstakeTime > 0n
    ? unstakeTime + BigInt(UNSTAKE_COOLDOWN) > now
      ? unstakeTime + BigInt(UNSTAKE_COOLDOWN) - now
      : 0n
    : 0n;

  const canCompleteUnstake = isUnstaking && timeUntilUnstakeComplete === 0n;

  return {
    staked: formatUnits(staked, CENTS_DECIMALS),
    stakedRaw: staked,
    stakePower: formatUnits(stakePower, CENTS_DECIMALS),
    stakePowerRaw: stakePower,
    powerPercentage,
    stakedSince: Number(stakedSince),
    isUnstaking,
    unstakeTime: Number(unstakeTime),
    timeUntilFullPower: Number(timeUntilFullPower),
    timeUntilUnstakeComplete: Number(timeUntilUnstakeComplete),
    canCompleteUnstake,
    feeFreeCap: formatUnits(feeFreeCap ?? 0n, CENTS_DECIMALS),
    feeFreeCapRaw: feeFreeCap ?? 0n,
    redemptionUsed: formatUnits(redemptionUsed ?? 0n, CENTS_DECIMALS),
    walletBalance: formatUnits(walletBalance ?? 0n, CENTS_DECIMALS),
    walletBalanceRaw: walletBalance ?? 0n,
    isLoading: stakingLoading,
    isDeployed,
    refetch,
  };
}

export function useCentsEmissions() {
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const centsAddress = contracts.cents;
  const isDeployed = centsAddress !== "0x0000000000000000000000000000000000000000";

  const { data, isLoading } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "getEmissionStats",
    query: {
      enabled: isDeployed,
      refetchInterval: 30000,
    },
  });

  const makerRemaining = data?.[0] ?? 0n;
  const takerRemaining = data?.[1] ?? 0n;
  const founderVested = data?.[2] ?? 0n;
  const totalMinted = data?.[3] ?? 0n;

  const MAKER_CAP = 600_000_000n * BigInt(1e6);
  const TAKER_CAP = 200_000_000n * BigInt(1e6);
  const FOUNDER_CAP = 200_000_000n * BigInt(1e6);

  return {
    makerRemaining: formatUnits(makerRemaining, CENTS_DECIMALS),
    makerEmitted: formatUnits(MAKER_CAP - makerRemaining, CENTS_DECIMALS),
    makerPercentage: Number(((MAKER_CAP - makerRemaining) * 100n) / MAKER_CAP),
    takerRemaining: formatUnits(takerRemaining, CENTS_DECIMALS),
    takerEmitted: formatUnits(TAKER_CAP - takerRemaining, CENTS_DECIMALS),
    takerPercentage: Number(((TAKER_CAP - takerRemaining) * 100n) / TAKER_CAP),
    founderVested: formatUnits(founderVested, CENTS_DECIMALS),
    founderPercentage: Number((founderVested * 100n) / FOUNDER_CAP),
    totalMinted: formatUnits(totalMinted, CENTS_DECIMALS),
    isLoading,
  };
}

export function useStakeCents() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const centsAddress = contracts.cents;

  const [step, setStep] = useState<"idle" | "approving" | "staking">("idle");
  const [error, setError] = useState<string | null>(null);

  // Check allowance
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: centsAddress,
    abi: centsABI,
    functionName: "allowance",
    args: userAddress ? [userAddress, centsAddress] : undefined,
    query: {
      enabled: !!userAddress,
    },
  });

  // Approve
  const { writeContract: approve, data: approveHash, isPending: isApproving, reset: resetApprove } = useWriteContract();
  const { isSuccess: approveSuccess } = useWaitForTransactionReceipt({ hash: approveHash });

  // Stake
  const { writeContract: stake, data: stakeHash, isPending: isStaking, reset: resetStake } = useWriteContract();
  const { isSuccess: stakeSuccess } = useWaitForTransactionReceipt({ hash: stakeHash });

  const executeStake = async (amount: string) => {
    setError(null);
    const parsedAmount = parseUnits(amount, CENTS_DECIMALS);

    try {
      // Check if approval needed
      if ((allowance ?? 0n) < parsedAmount) {
        setStep("approving");
        approve({
          address: centsAddress,
          abi: centsABI,
          functionName: "approve",
          args: [centsAddress, parsedAmount],
        });
      } else {
        setStep("staking");
        stake({
          address: centsAddress,
          abi: centsABI,
          functionName: "stake",
          args: [parsedAmount],
        });
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
      setStep("idle");
    }
  };

  // Continue staking after approval
  const continueStake = (amount: string) => {
    const parsedAmount = parseUnits(amount, CENTS_DECIMALS);
    setStep("staking");
    stake({
      address: centsAddress,
      abi: centsABI,
      functionName: "stake",
      args: [parsedAmount],
    });
  };

  const reset = () => {
    setStep("idle");
    setError(null);
    resetApprove();
    resetStake();
    refetchAllowance();
  };

  return {
    executeStake,
    continueStake,
    step,
    isApproving,
    isStaking,
    approveSuccess,
    stakeSuccess,
    stakeHash,
    error,
    reset,
  };
}

export function useUnstakeCents() {
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const centsAddress = contracts.cents;

  const [error, setError] = useState<string | null>(null);

  // Initiate unstake
  const { writeContract: unstake, data: unstakeHash, isPending: isInitiating, reset: resetUnstake } = useWriteContract();
  const { isSuccess: unstakeSuccess } = useWaitForTransactionReceipt({ hash: unstakeHash });

  // Complete unstake
  const { writeContract: complete, data: completeHash, isPending: isCompleting, reset: resetComplete } = useWriteContract();
  const { isSuccess: completeSuccess } = useWaitForTransactionReceipt({ hash: completeHash });

  // Cancel unstake
  const { writeContract: cancel, data: cancelHash, isPending: isCancelling, reset: resetCancel } = useWriteContract();
  const { isSuccess: cancelSuccess } = useWaitForTransactionReceipt({ hash: cancelHash });

  const initiateUnstake = () => {
    setError(null);
    try {
      unstake({
        address: centsAddress,
        abi: centsABI,
        functionName: "unstake",
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
    }
  };

  const completeUnstake = () => {
    setError(null);
    try {
      complete({
        address: centsAddress,
        abi: centsABI,
        functionName: "completeUnstake",
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
    }
  };

  const cancelUnstake = () => {
    setError(null);
    try {
      cancel({
        address: centsAddress,
        abi: centsABI,
        functionName: "cancelUnstake",
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : "Transaction failed");
    }
  };

  const reset = () => {
    setError(null);
    resetUnstake();
    resetComplete();
    resetCancel();
  };

  return {
    initiateUnstake,
    completeUnstake,
    cancelUnstake,
    isInitiating,
    isCompleting,
    isCancelling,
    unstakeSuccess,
    completeSuccess,
    cancelSuccess,
    unstakeHash,
    completeHash,
    cancelHash,
    error,
    reset,
  };
}

// Helper to format time duration
export function formatDuration(seconds: number): string {
  if (seconds <= 0) return "0s";

  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const mins = Math.floor((seconds % 3600) / 60);

  if (days > 0) {
    return `${days}d ${hours}h`;
  } else if (hours > 0) {
    return `${hours}h ${mins}m`;
  } else {
    return `${mins}m`;
  }
}
