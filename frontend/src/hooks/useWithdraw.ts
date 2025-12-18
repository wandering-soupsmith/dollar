"use client";

import { useState, useCallback } from "react";
import {
  useWriteContract,
  useWaitForTransactionReceipt,
  useAccount,
  useChainId,
} from "wagmi";
import { parseUnits } from "viem";
import { dollarStoreABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";

export type WithdrawStep = "idle" | "withdrawing" | "success" | "error";

export function useWithdraw() {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const [step, setStep] = useState<WithdrawStep>("idle");
  const [error, setError] = useState<string | null>(null);

  // Contract write hook
  const { writeContract: withdraw, data: withdrawHash } = useWriteContract();

  // Wait for transaction
  const { isLoading: isWithdrawing, isSuccess: withdrawSuccess } =
    useWaitForTransactionReceipt({ hash: withdrawHash });

  const executeWithdraw = useCallback(
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
        setStep("withdrawing");

        await withdraw({
          address: contracts.dollarStore,
          abi: dollarStoreABI,
          functionName: "withdraw",
          args: [tokenAddress, amountBn],
        });
      } catch (err) {
        setStep("error");
        setError(err instanceof Error ? err.message : "Withdraw failed");
      }
    },
    [userAddress, contracts, withdraw]
  );

  const reset = useCallback(() => {
    setStep("idle");
    setError(null);
  }, []);

  return {
    step,
    error,
    isWithdrawing,
    withdrawSuccess,
    executeWithdraw,
    reset,
    withdrawHash,
  };
}
