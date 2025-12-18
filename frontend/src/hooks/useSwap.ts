"use client";

import { useState, useCallback } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
  useChainId,
} from "wagmi";
import { parseUnits } from "viem";
import { dollarStoreABI, erc20ABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";

export type SwapStep = "idle" | "approving" | "swapping" | "success" | "error";

export function useSwap() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const [step, setStep] = useState<SwapStep>("idle");
  const [error, setError] = useState<string | null>(null);

  // Contract write hooks
  const { writeContractAsync: approveAsync } = useWriteContract();
  const { writeContract: swap, data: swapHash } = useWriteContract();

  // Wait for transaction
  const { isLoading: isSwapping, isSuccess: swapSuccess } =
    useWaitForTransactionReceipt({ hash: swapHash });

  const executeSwap = useCallback(
    async (
      fromCoin: StablecoinSymbol,
      toCoin: StablecoinSymbol,
      amount: string,
      queueIfUnavailable: boolean = true
    ) => {
      if (!userAddress) {
        setError("Wallet not connected");
        return;
      }

      if (fromCoin === toCoin) {
        setError("Cannot swap to the same stablecoin");
        return;
      }

      const fromTokenAddress =
        fromCoin === "USDC" ? contracts.usdc : contracts.usdt;
      const toTokenAddress =
        toCoin === "USDC" ? contracts.usdc : contracts.usdt;
      const decimals = STABLECOINS[fromCoin].decimals;
      const amountBn = parseUnits(amount, decimals);

      try {
        setError(null);
        setStep("approving");

        // First approve the DollarStore contract to spend the stablecoin
        await approveAsync({
          address: fromTokenAddress,
          abi: erc20ABI,
          functionName: "approve",
          args: [contracts.dollarStore, amountBn],
        });

        setStep("swapping");

        // Execute the swap
        await swap({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "swap",
          args: [fromTokenAddress, toTokenAddress, amountBn, queueIfUnavailable],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Swap failed");
      }
    },
    [userAddress, contracts, approveAsync, swap]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
  }, []);

  return {
    step,
    error,
    isSwapping,
    swapSuccess,
    executeSwap,
    reset,
    swapHash,
  };
}
