"use client";

import { useReadContract, useReadContracts } from "wagmi";
import { formatUnits } from "viem";
import { dollarStoreABI, erc20ABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";
import { useChainId } from "wagmi";

export interface Reserve {
  symbol: StablecoinSymbol;
  address: `0x${string}`;
  amount: bigint;
  decimals: number;
  formatted: string;
}

export function useReserves() {
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;
  const isDeployed = contracts.dollarStore !== "0x0000000000000000000000000000000000000000";

  // Get reserves from contract
  const { data, isLoading, error, refetch } = useReadContract({
    address: contracts.dollarStore,
    abi: dollarStoreABI,
    functionName: "getReserves",
    query: {
      enabled: isDeployed,
      refetchInterval: 10000, // Refetch every 10 seconds
    },
  });

  // Get DLRS total supply
  const { data: dlrsTotalSupply } = useReadContract({
    address: contracts.dlrs,
    abi: erc20ABI,
    functionName: "totalSupply",
    query: {
      enabled: isDeployed,
      refetchInterval: 10000,
    },
  });

  // Process reserves data
  let reserves: Reserve[] = [];

  if (data) {
    const [stablecoins, amounts] = data;
    // Filter to only show stablecoins configured in frontend
    reserves = stablecoins
      .map((address, index) => {
        // Find which stablecoin this is
        let symbol: StablecoinSymbol | null = null;
        if (address.toLowerCase() === contracts.usdc.toLowerCase()) {
          symbol = "USDC";
        } else if (address.toLowerCase() === contracts.usdt.toLowerCase()) {
          symbol = "USDT";
        }

        // Skip unknown stablecoins
        if (!symbol) return null;

        const decimals = STABLECOINS[symbol].decimals;
        const amount = amounts[index];

        return {
          symbol,
          address: address as `0x${string}`,
          amount,
          decimals,
          formatted: formatUnits(amount, decimals),
        };
      })
      .filter((r): r is Reserve => r !== null);
  } else {
    // Show empty state while loading
    reserves = [
      {
        symbol: "USDC",
        address: contracts.usdc,
        amount: 0n,
        decimals: 6,
        formatted: "0",
      },
      {
        symbol: "USDT",
        address: contracts.usdt,
        amount: 0n,
        decimals: 6,
        formatted: "0",
      },
    ];
  }

  const totalReserves = reserves.reduce(
    (sum, r) => sum + Number(r.formatted),
    0
  );

  const totalSupply = dlrsTotalSupply
    ? formatUnits(dlrsTotalSupply, 6)
    : "0";

  return {
    reserves,
    totalReserves,
    totalSupply,
    isLoading,
    error,
    refetch,
    isDeployed,
  };
}
