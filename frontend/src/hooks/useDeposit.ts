"use client";

import { useState, useCallback } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useReadContract,
  useAccount,
  useChainId,
} from "wagmi";
import { parseUnits } from "viem";
import { dollarStoreABI, erc20ABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";

export type DepositStep = "idle" | "approving" | "depositing" | "success" | "error";

export function useDeposit() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const [step, setStep] = useState<DepositStep>("idle");
  const [error, setError] = useState<string | null>(null);

  // Contract write hooks
  const { writeContract: approve, data: approveHash } = useWriteContract();
  const { writeContract: deposit, data: depositHash } = useWriteContract();

  // Wait for transactions
  const { isLoading: isApproving, isSuccess: approveSuccess } =
    useWaitForTransactionReceipt({ hash: approveHash });

  const { isLoading: isDepositing, isSuccess: depositSuccess } =
    useWaitForTransactionReceipt({ hash: depositHash });

  // Check allowance
  const checkAllowance = useCallback(
    async (stablecoin: StablecoinSymbol, amount: string) => {
      const tokenAddress =
        stablecoin === "USDC" ? contracts.usdc : contracts.usdt;
      const decimals = STABLECOINS[stablecoin].decimals;
      const amountBn = parseUnits(amount, decimals);

      // This is a simplified check - in production we'd use useReadContract
      return { needsApproval: true, amountBn };
    },
    [contracts]
  );

  const executeDeposit = useCallback(
    async (stablecoin: StablecoinSymbol, amount: string) => {
      if (!userAddress) {
        setError("Wallet not connected");
        return;
      }

      const tokenAddress =
        stablecoin === "USDC" ? contracts.usdc : contracts.usdt;
      const decimals = STABLECOINS[stablecoin].decimals;
      const amountBn = parseUnits(amount, decimals);

      try {
        setError(null);
        setStep("approving");

        // First approve
        await approve({
          address: tokenAddress,
          abi: erc20ABI,
          functionName: "approve",
          args: [contracts.dollarStore, amountBn],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Approval failed");
      }
    },
    [userAddress, contracts, approve]
  );

  // Effect to continue to deposit after approval
  const continueDeposit = useCallback(
    async (stablecoin: StablecoinSymbol, amount: string) => {
      const tokenAddress =
        stablecoin === "USDC" ? contracts.usdc : contracts.usdt;
      const decimals = STABLECOINS[stablecoin].decimals;
      const amountBn = parseUnits(amount, decimals);

      try {
        setStep("depositing");

        await deposit({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "deposit",
          args: [tokenAddress, amountBn],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Deposit failed");
      }
    },
    [contracts, deposit]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
  }, []);

  return {
    step,
    error,
    isApproving,
    isDepositing,
    approveSuccess,
    depositSuccess,
    executeDeposit,
    continueDeposit,
    reset,
    approveHash,
    depositHash,
  };
}
