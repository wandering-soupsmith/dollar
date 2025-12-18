"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { STABLECOINS, StablecoinSymbol } from "@/config/contracts";
import { useDeposit } from "@/hooks/useDeposit";
import { useWithdraw } from "@/hooks/useWithdraw";
import { useTokenBalance } from "@/hooks/useTokenBalance";
import { useReserves } from "@/hooks/useReserves";

type Mode = "deposit" | "redeem";

interface SuccessInfo {
  type: "deposit" | "withdraw";
  amount: string;
  coin: StablecoinSymbol;
}

export function DepositRedeem() {
  const { isConnected } = useAccount();
  const [mode, setMode] = useState<Mode>("deposit");
  const [selectedCoin, setSelectedCoin] = useState<StablecoinSymbol>("USDC");
  const [amount, setAmount] = useState("");
  const [successInfo, setSuccessInfo] = useState<SuccessInfo | null>(null);

  // Get balances
  const stablecoinBalance = useTokenBalance(selectedCoin);
  const dlrsBalance = useTokenBalance("DLRS");

  // Get reserves for withdrawal availability check
  const { reserves } = useReserves();

  // Transaction hooks
  const deposit = useDeposit();
  const withdraw = useWithdraw();

  // Reset transaction state when switching modes or coins
  useEffect(() => {
    deposit.reset();
    withdraw.reset();
    setSuccessInfo(null);
    setAmount("");
  }, [mode, selectedCoin]);

  // Continue deposit after approval succeeds
  useEffect(() => {
    if (deposit.approveSuccess && deposit.step === "approving" && amount) {
      deposit.continueDeposit(selectedCoin, amount);
    }
  }, [deposit.approveSuccess, deposit.step, selectedCoin, amount]);

  // Capture success info when transaction completes
  useEffect(() => {
    if (deposit.depositSuccess && !successInfo) {
      setSuccessInfo({ type: "deposit", amount, coin: selectedCoin });
    }
  }, [deposit.depositSuccess]);

  useEffect(() => {
    if (withdraw.withdrawSuccess && !successInfo) {
      setSuccessInfo({ type: "withdraw", amount, coin: selectedCoin });
    }
  }, [withdraw.withdrawSuccess]);

  // Auto-clear success state after 10 seconds
  useEffect(() => {
    if (successInfo) {
      const timer = setTimeout(() => {
        deposit.reset();
        withdraw.reset();
        setSuccessInfo(null);
        setAmount("");
        // Refetch balances
        stablecoinBalance.refetch();
        dlrsBalance.refetch();
      }, 10000);
      return () => clearTimeout(timer);
    }
  }, [successInfo]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!amount || Number(amount) <= 0) return;

    if (mode === "deposit") {
      await deposit.executeDeposit(selectedCoin, amount);
    } else {
      await withdraw.executeWithdraw(selectedCoin, amount);
    }
  };

  const handleMaxClick = () => {
    if (mode === "deposit") {
      const balance = stablecoinBalance.formatted;
      setAmount(balance);
    } else {
      const balance = dlrsBalance.formatted;
      setAmount(balance);
    }
  };

  // Determine current state
  const isApproving = deposit.step === "approving";
  const isDepositing = deposit.step === "depositing" || deposit.isDepositing;
  const isWithdrawing = withdraw.step === "withdrawing" || withdraw.isWithdrawing;
  const isLoading = isApproving || isDepositing || isWithdrawing;
  const isSuccess = successInfo !== null;
  const error = deposit.error || withdraw.error;

  // Get button text
  const getButtonText = () => {
    if (isApproving) return `Approving ${selectedCoin}...`;
    if (isDepositing) return "Depositing...";
    if (isWithdrawing) return "Withdrawing...";
    if (isSuccess) return "Success!";
    if (mode === "deposit") return `Deposit ${selectedCoin}`;
    return `Withdraw ${selectedCoin}`;
  };

  // Get relevant balance for display
  const relevantBalance = mode === "deposit"
    ? stablecoinBalance.formatted
    : dlrsBalance.formatted;

  // Check available reserves for the selected coin (for withdrawals)
  const selectedReserve = reserves.find(r => r.symbol === selectedCoin);
  const availableReserve = selectedReserve ? Number(selectedReserve.formatted) : 0;
  const requestedAmount = Number(amount || 0);
  const hasInsufficientReserves = mode === "redeem" && requestedAmount > 0 && requestedAmount > availableReserve;

  return (
    <div className="bg-deep-green rounded-md p-6 border border-border max-w-md mx-auto">
      {/* Mode Toggle */}
      <div className="flex bg-black rounded-sm p-1 mb-6">
        <button
          onClick={() => setMode("deposit")}
          disabled={isLoading}
          className={`flex-1 py-3 px-4 rounded-sm text-sm font-medium ${
            mode === "deposit"
              ? "bg-dollar-green text-black"
              : "text-muted hover:text-white"
          } disabled:opacity-50`}
        >
          Deposit
        </button>
        <button
          onClick={() => setMode("redeem")}
          disabled={isLoading}
          className={`flex-1 py-3 px-4 rounded-sm text-sm font-medium ${
            mode === "redeem"
              ? "bg-withdraw-bg text-gold border border-withdraw-border"
              : "text-muted hover:text-white"
          } disabled:opacity-50`}
        >
          Withdraw
        </button>
      </div>

      <form onSubmit={handleSubmit}>
        {/* Stablecoin Selection */}
        <div className="mb-4">
          <label className="block font-body-sm text-muted mb-2">
            {mode === "deposit" ? "Deposit" : "Receive"}
          </label>
          <div className="flex gap-2">
            {(Object.keys(STABLECOINS) as StablecoinSymbol[]).map((symbol) => (
              <button
                key={symbol}
                type="button"
                onClick={() => setSelectedCoin(symbol)}
                disabled={isLoading}
                className={`flex-1 py-3 px-4 rounded-sm font-medium text-sm ${
                  selectedCoin === symbol
                    ? "bg-hover border border-dollar-green text-white"
                    : "bg-black border border-border text-muted hover:border-border hover:text-white"
                } disabled:opacity-50`}
              >
                {symbol}
              </button>
            ))}
          </div>
        </div>

        {/* Amount Input */}
        <div className="mb-4">
          <div className="flex items-center justify-between mb-2">
            <label className="font-body-sm text-muted">Amount</label>
            {isConnected && (
              <span className="font-caption text-muted">
                Balance: <span className="tabular-nums">{Number(relevantBalance).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>{" "}
                {mode === "deposit" ? selectedCoin : "DLRS"}
              </span>
            )}
          </div>
          <div className="relative">
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.00"
              disabled={isLoading}
              className="w-full bg-deep-green border border-border rounded-sm px-4 py-3 text-lg tabular-nums focus:border-dollar-green focus:outline-none focus:ring-2 focus:ring-dollar-green/20 disabled:opacity-50 disabled:bg-black"
            />
            <button
              type="button"
              onClick={handleMaxClick}
              disabled={isLoading}
              className="absolute right-3 top-1/2 -translate-y-1/2 font-caption text-dollar-green hover:text-dollar-green-light disabled:opacity-50"
            >
              MAX
            </button>
          </div>
        </div>

        {/* Result Preview */}
        <div className="bg-black rounded-sm p-4 mb-4 border border-border">
          <div className="flex items-center justify-between">
            <span className="text-muted font-body-sm">
              {mode === "deposit" ? "You will receive" : "You will burn"}
            </span>
            <span className="text-lg tabular-nums">
              {amount || "0"}{" "}
              <span className="text-dollar-green">$DLRS</span>
            </span>
          </div>
          {mode === "redeem" && (
            <div className="flex items-center justify-between mt-2 pt-2 border-t border-border">
              <span className="text-muted font-body-sm">Available in reserves</span>
              <span className={`font-body-sm tabular-nums ${hasInsufficientReserves ? "text-error" : "text-muted"}`}>
                {availableReserve.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} {selectedCoin}
              </span>
            </div>
          )}
        </div>

        {/* Insufficient Reserves Warning */}
        {hasInsufficientReserves && (
          <div className="bg-error-muted/30 border border-error-muted rounded-sm p-3 mb-4">
            <p className="text-error font-body-sm">
              Insufficient {selectedCoin} in reserves. Only {availableReserve.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} available.
            </p>
          </div>
        )}

        {/* Error Message */}
        {error && (
          <div className="bg-error-muted/30 border border-error-muted rounded-sm p-3 mb-4">
            <p className="text-error font-body-sm">{error}</p>
          </div>
        )}

        {/* Success Message */}
        {successInfo && (
          <div className="bg-dollar-green/15 border border-dollar-green/30 rounded-sm p-3 mb-4">
            <p className="text-dollar-green font-body-sm">
              {successInfo.type === "deposit"
                ? `Successfully deposited ${successInfo.amount} ${successInfo.coin}!`
                : `Successfully withdrew ${successInfo.amount} ${successInfo.coin}!`}
            </p>
          </div>
        )}

        {/* Transaction Hash */}
        {(deposit.depositHash || withdraw.withdrawHash) && (
          <div className="mb-4">
            <a
              href={`https://sepolia.etherscan.io/tx/${deposit.depositHash || withdraw.withdrawHash}`}
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
            disabled={!amount || Number(amount) <= 0 || isLoading || isSuccess || hasInsufficientReserves}
            className={`w-full py-3 px-6 rounded-sm font-medium text-sm ${
              isSuccess
                ? "bg-dollar-green-dark text-black"
                : isLoading
                  ? "bg-disabled-bg text-muted"
                  : mode === "deposit"
                    ? "bg-dollar-green hover:bg-dollar-green-light text-black disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
                    : "bg-withdraw-bg hover:bg-withdraw-hover text-gold border border-withdraw-border disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
            }`}
          >
            {isLoading && (
              <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
            )}
            {getButtonText()}
          </button>
        ) : (
          <div className="text-center py-3 px-4 bg-black border border-border rounded-sm text-muted font-body-sm">
            Connect wallet to {mode}
          </div>
        )}
      </form>

      {/* Info text */}
      <p className="mt-4 font-caption text-muted text-center">
        {mode === "deposit"
          ? "Deposit stablecoins to mint $DLRS at 1:1 ratio"
          : "Burn $DLRS to withdraw stablecoins at 1:1 ratio"}
      </p>
    </div>
  );
}
