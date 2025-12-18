"use client";

import { useReadContract, useAccount, useChainId } from "wagmi";
import { formatUnits } from "viem";
import { erc20ABI } from "@/config/abis";
import { CONTRACTS, STABLECOINS, StablecoinSymbol } from "@/config/contracts";

export function useTokenBalance(symbol: StablecoinSymbol | "DLRS") {
  const { address: userAddress } = useAccount();
  const chainId = useChainId();
  const contracts = chainId === 1 ? CONTRACTS.mainnet : CONTRACTS.sepolia;

  const tokenAddress =
    symbol === "DLRS"
      ? contracts.dlrs
      : symbol === "USDC"
        ? contracts.usdc
        : contracts.usdt;

  const decimals = symbol === "DLRS" ? 18 : STABLECOINS[symbol].decimals;

  const { data, isLoading, error, refetch } = useReadContract({
    address: tokenAddress,
    abi: erc20ABI,
    functionName: "balanceOf",
    args: userAddress ? [userAddress] : undefined,
    query: {
      enabled: !!userAddress && tokenAddress !== "0x0000000000000000000000000000000000000000",
      refetchInterval: 10000,
    },
  });

  const balance = data ?? 0n;
  const formatted = formatUnits(balance, decimals);

  return {
    balance,
    formatted,
    decimals,
    isLoading,
    error,
    refetch,
  };
}

export function useAllBalances() {
  const usdc = useTokenBalance("USDC");
  const usdt = useTokenBalance("USDT");
  const dlrs = useTokenBalance("DLRS");

  return {
    USDC: usdc,
    USDT: usdt,
    DLRS: dlrs,
  };
}
