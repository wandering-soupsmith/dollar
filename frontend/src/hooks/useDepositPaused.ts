"use client";

import { useReadContracts, useChainId } from "wagmi";
import { dollarStoreABI } from "@/config/abis";
import { CONTRACTS, StablecoinSymbol } from "@/config/contracts";

export function useDepositPaused() {
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const isDeployed = contracts.dollarStore !== "0x0000000000000000000000000000000000000000";

  const { data, isLoading } = useReadContracts({
    contracts: [
      {
        address: contracts.dollarStore,
        abi: dollarStoreABI,
        functionName: "isDepositPaused",
        args: [contracts.usdc],
      },
      {
        address: contracts.dollarStore,
        abi: dollarStoreABI,
        functionName: "isDepositPaused",
        args: [contracts.usdt],
      },
    ],
    query: {
      enabled: isDeployed,
      refetchInterval: 10000,
    },
  });

  const paused: Record<StablecoinSymbol, boolean> = {
    USDC: data?.[0]?.result === true,
    USDT: data?.[1]?.result === true,
  };

  return { paused, isLoading };
}
