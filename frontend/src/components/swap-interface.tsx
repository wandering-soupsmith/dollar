"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { STABLECOINS, StablecoinSymbol } from "@/config/contracts";
import { useSwap } from "@/hooks/useSwap";
import { useQueueActions, useQueueDepths } from "@/hooks/useQueue";
import { useTokenBalance } from "@/hooks/useTokenBalance";

export function SwapInterface() {
  const { isConnected } = useAccount();
  const [fromCoin, setFromCoin] = useState<StablecoinSymbol>("USDC");
  const [toCoin, setToCoin] = useState<StablecoinSymbol>("USDT");
  const [amount, setAmount] = useState("");
  const [queueIfUnavailable, setQueueIfUnavailable] = useState(true);

  // Get balances
  const fromBalance = useTokenBalance(fromCoin);
  const dlrsBalance = useTokenBalance("DLRS");

  // Get queue depths to show availability
  const { depths, isDeployed } = useQueueDepths();

  // Transaction hooks
  const swap = useSwap();
  const queueActions = useQueueActions();

  // Reset transaction state when switching coins
  useEffect(() => {
    swap.reset();
    queueActions.reset();
  }, [fromCoin, toCoin]);

  // Auto-clear success state
  useEffect(() => {
    if (swap.swapSuccess || queueActions.joinSuccess) {
      const timer = setTimeout(() => {
        swap.reset();
        queueActions.reset();
        setAmount("");
        fromBalance.refetch();
        dlrsBalance.refetch();
      }, 3000);
      return () => clearTimeout(timer);
    }
  }, [swap.swapSuccess, queueActions.joinSuccess]);

  const handleSwapDirection = () => {
    const temp = fromCoin;
    setFromCoin(toCoin);
    setToCoin(temp);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) return;

    await swap.executeSwap(fromCoin, toCoin, amount, queueIfUnavailable);
  };

  const handleMaxClick = () => {
    setAmount(fromBalance.formatted);
  };

  // Calculate available reserves for the target coin
  const availableReserves = depths[toCoin];
  const amountBn = BigInt(Math.floor(Number(amount || 0) * 10 ** 6));
  const hasEnoughReserves = availableReserves >= amountBn;

  // Determine current state
  const isApproving = swap.step === "approving";
  const isSwapping = swap.step === "swapping" || swap.isSwapping;
  const isJoining = queueActions.step === "joining" || queueActions.isJoining;
  const isLoading = isApproving || isSwapping || isJoining;
  const isSuccess = swap.swapSuccess || queueActions.joinSuccess;
  const error = swap.error || queueActions.error;

  // Get button text
  const getButtonText = () => {
    if (isApproving) return `Approving ${fromCoin}...`;
    if (isSwapping) return "Swapping...";
    if (isJoining) return "Joining queue...";
    if (isSuccess) return "Success!";
    if (!hasEnoughReserves && amount && Number(amount) > 0) {
      return queueIfUnavailable ? "Swap (will queue)" : "Insufficient reserves";
    }
    return "Swap";
  };

  // Format reserve amount for display
  const formatReserve = (amount: bigint) => {
    const num = Number(amount) / 10 ** 6;
    return new Intl.NumberFormat("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: 2,
    }).format(num);
  };

  return (
    <div className="bg-deep-green rounded-md p-6 border border-border">
      <h2 className="font-h3 text-white mb-6">Swap</h2>

      <form onSubmit={handleSubmit}>
        {/* From */}
        <div className="mb-2">
          <label className="block font-body-sm text-muted mb-2">From</label>
          <div className="bg-black rounded-sm p-4 border border-border">
            <div className="flex items-center gap-4">
              <select
                value={fromCoin}
                onChange={(e) => setFromCoin(e.target.value as StablecoinSymbol)}
                disabled={isLoading}
                className="bg-deep-green border border-border rounded-sm px-3 py-2 font-medium text-sm focus:outline-none focus:border-dollar-green disabled:opacity-50"
              >
                {(Object.keys(STABLECOINS) as StablecoinSymbol[]).map((coin) => (
                  <option key={coin} value={coin} disabled={coin === toCoin}>
                    {coin}
                  </option>
                ))}
              </select>
              <input
                type="number"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="0.00"
                disabled={isLoading}
                className="flex-1 bg-transparent text-right text-2xl tabular-nums focus:outline-none disabled:opacity-50"
              />
            </div>
            <div className="flex items-center justify-between mt-3 font-body-sm text-muted">
              <span>{STABLECOINS[fromCoin].name}</span>
              {isConnected && (
                <button
                  type="button"
                  onClick={handleMaxClick}
                  disabled={isLoading}
                  className="text-dollar-green hover:text-dollar-green-light disabled:opacity-50"
                >
                  Balance: <span className="tabular-nums">{Number(fromBalance.formatted).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
                </button>
              )}
            </div>
          </div>
        </div>

        {/* Swap Direction Button */}
        <div className="flex justify-center -my-2 relative z-10">
          <button
            type="button"
            onClick={handleSwapDirection}
            disabled={isLoading}
            className="w-10 h-10 bg-border hover:bg-hover rounded-full flex items-center justify-center disabled:opacity-50"
          >
            <svg
              className="w-5 h-5 text-muted"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M7 16V4m0 0L3 8m4-4l4 4m6 0v12m0 0l4-4m-4 4l-4-4"
              />
            </svg>
          </button>
        </div>

        {/* To */}
        <div className="mb-6">
          <label className="block font-body-sm text-muted mb-2">To</label>
          <div className="bg-black rounded-sm p-4 border border-border">
            <div className="flex items-center gap-4">
              <select
                value={toCoin}
                onChange={(e) => setToCoin(e.target.value as StablecoinSymbol)}
                disabled={isLoading}
                className="bg-deep-green border border-border rounded-sm px-3 py-2 font-medium text-sm focus:outline-none focus:border-dollar-green disabled:opacity-50"
              >
                {(Object.keys(STABLECOINS) as StablecoinSymbol[]).map((coin) => (
                  <option key={coin} value={coin} disabled={coin === fromCoin}>
                    {coin}
                  </option>
                ))}
              </select>
              <div className="flex-1 text-right text-2xl tabular-nums text-muted">
                {amount || "0.00"}
              </div>
            </div>
            <div className="flex items-center justify-between mt-3 font-body-sm text-muted">
              <span>{STABLECOINS[toCoin].name}</span>
              <span className={hasEnoughReserves || !amount ? "text-muted" : "text-gold"}>
                Available: <span className="tabular-nums">{formatReserve(availableReserves)}</span>
              </span>
            </div>
          </div>
        </div>

        {/* Queue Option */}
        <div className="mb-6 p-4 bg-black rounded-sm border border-border">
          <label className="flex items-center gap-3 cursor-pointer">
            <input
              type="checkbox"
              checked={queueIfUnavailable}
              onChange={(e) => setQueueIfUnavailable(e.target.checked)}
              disabled={isLoading}
              className="w-5 h-5 rounded-sm border-border bg-deep-green text-dollar-green focus:ring-dollar-green focus:ring-offset-0 accent-dollar-green"
            />
            <div>
              <span className="font-medium text-sm">Queue if unavailable</span>
              <p className="font-body-sm text-muted">
                If reserves are insufficient, join the queue to receive funds
                when deposits come in.
              </p>
            </div>
          </label>
        </div>

        {/* Reserve Warning */}
        {!hasEnoughReserves && amount && Number(amount) > 0 && (
          <div className={`mb-4 p-3 rounded-sm ${queueIfUnavailable ? "bg-gold/15 border border-gold/30" : "bg-error-muted/30 border border-error-muted"}`}>
            <p className={`font-body-sm ${queueIfUnavailable ? "text-gold" : "text-error"}`}>
              {queueIfUnavailable
                ? `Only ${formatReserve(availableReserves)} ${toCoin} available. Your swap will be queued for the remaining amount.`
                : `Insufficient ${toCoin} reserves. Enable queuing or reduce amount.`}
            </p>
          </div>
        )}

        {/* Rate Info */}
        <div className="mb-6 font-body-sm text-muted">
          <div className="flex items-center justify-between">
            <span>Rate</span>
            <span className="text-white">1:1 (no fees)</span>
          </div>
        </div>

        {/* Error Message */}
        {error && (
          <div className="bg-error-muted/30 border border-error-muted rounded-sm p-3 mb-4">
            <p className="text-error font-body-sm">{error}</p>
          </div>
        )}

        {/* Success Message */}
        {isSuccess && (
          <div className="bg-dollar-green/15 border border-dollar-green/30 rounded-sm p-3 mb-4">
            <p className="text-dollar-green font-body-sm">
              {swap.swapSuccess
                ? `Successfully swapped ${amount} ${fromCoin} for ${toCoin}!`
                : `Successfully joined queue for ${toCoin}!`}
            </p>
          </div>
        )}

        {/* Transaction Hash */}
        {(swap.swapHash || queueActions.joinHash) && (
          <div className="mb-4">
            <a
              href={`https://sepolia.etherscan.io/tx/${swap.swapHash || queueActions.joinHash}`}
              target="_blank"
              rel="noopener noreferrer"
              className="font-caption text-muted hover:text-white underline"
            >
              View transaction on Etherscan
            </a>
          </div>
        )}

        {/* Submit Button */}
        {isConnected ? (
          <button
            type="submit"
            disabled={
              !amount ||
              Number(amount) <= 0 ||
              isLoading ||
              isSuccess ||
              (!hasEnoughReserves && !queueIfUnavailable)
            }
            className={`w-full py-4 px-6 rounded-sm font-medium text-sm ${
              isSuccess
                ? "bg-dollar-green-dark text-black"
                : isLoading
                  ? "bg-disabled-bg text-muted"
                  : "bg-dollar-green hover:bg-dollar-green-light text-black disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
            }`}
          >
            {isLoading && (
              <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
            )}
            {getButtonText()}
          </button>
        ) : (
          <div className="text-center py-4 px-4 bg-black border border-border rounded-sm text-muted font-body-sm">
            Connect wallet to swap
          </div>
        )}
      </form>

      {!isDeployed && (
        <p className="mt-4 font-caption text-muted text-center">
          Showing mock data - contracts not yet deployed
        </p>
      )}
    </div>
  );
}
