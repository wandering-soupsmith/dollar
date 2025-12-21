"use client";

import { useState, useEffect } from "react";
import { useAccount } from "wagmi";
import { useCentsStaking, useStakeCents, useUnstakeCents, formatDuration } from "@/hooks/useCents";

type Mode = "stake" | "unstake";

export function StakeInterface() {
  const { isConnected } = useAccount();
  const [mode, setMode] = useState<Mode>("stake");
  const [amount, setAmount] = useState("");

  const staking = useCentsStaking();
  const stake = useStakeCents();
  const unstake = useUnstakeCents();

  // Reset when switching modes
  useEffect(() => {
    stake.reset();
    unstake.reset();
    setAmount("");
  }, [mode]);

  // Continue stake after approval
  useEffect(() => {
    if (stake.approveSuccess && stake.step === "approving" && amount) {
      stake.continueStake(amount);
    }
  }, [stake.approveSuccess, stake.step, amount]);

  // Refetch after success
  useEffect(() => {
    if (stake.stakeSuccess || unstake.unstakeSuccess || unstake.completeSuccess || unstake.cancelSuccess) {
      staking.refetch();
    }
  }, [stake.stakeSuccess, unstake.unstakeSuccess, unstake.completeSuccess, unstake.cancelSuccess]);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (mode === "stake" && amount && Number(amount) > 0) {
      await stake.executeStake(amount);
    } else if (mode === "unstake" && !staking.isUnstaking) {
      unstake.initiateUnstake();
    }
  };

  const handleMaxClick = () => {
    setAmount(staking.walletBalance);
  };

  const isLoading = stake.isApproving || stake.isStaking || unstake.isInitiating || unstake.isCompleting || unstake.isCancelling;
  const isSuccess = stake.stakeSuccess || unstake.unstakeSuccess || unstake.completeSuccess || unstake.cancelSuccess;
  const error = stake.error || unstake.error;

  const getButtonText = () => {
    if (stake.step === "approving") return "Approving CENTS...";
    if (stake.isStaking) return "Staking...";
    if (unstake.isInitiating) return "Initiating Unstake...";
    if (unstake.isCompleting) return "Completing Unstake...";
    if (unstake.isCancelling) return "Cancelling...";
    if (isSuccess) return "Success!";
    if (mode === "stake") return "Stake CENTS";
    if (staking.isUnstaking) {
      if (staking.canCompleteUnstake) return "Complete Unstake";
      return `Unstaking (${formatDuration(staking.timeUntilUnstakeComplete)})`;
    }
    return "Begin Unstake";
  };

  if (!staking.isDeployed) {
    return (
      <div className="bg-deep-green rounded-md p-6 border border-border">
        <div className="text-center py-8">
          <div className="text-4xl mb-4 text-muted">&#162;</div>
          <h3 className="font-h3 text-white mb-2">CENTS Coming Soon</h3>
          <p className="font-body-sm text-muted">
            The CENTS token has not been deployed yet. Check back soon!
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="bg-deep-green rounded-md p-6 border border-border">
      {/* Mode Toggle */}
      <div className="flex bg-black rounded-sm p-1 mb-6">
        <button
          onClick={() => setMode("stake")}
          disabled={isLoading}
          className={`flex-1 py-3 px-4 rounded-sm text-sm font-medium ${
            mode === "stake"
              ? "bg-dollar-green text-black"
              : "text-muted hover:text-white"
          } disabled:opacity-50`}
        >
          Stake
        </button>
        <button
          onClick={() => setMode("unstake")}
          disabled={isLoading}
          className={`flex-1 py-3 px-4 rounded-sm text-sm font-medium ${
            mode === "unstake"
              ? "bg-withdraw-bg text-gold border border-withdraw-border"
              : "text-muted hover:text-white"
          } disabled:opacity-50`}
        >
          Unstake
        </button>
      </div>

      {mode === "stake" ? (
        <form onSubmit={handleSubmit}>
          {/* Amount Input */}
          <div className="mb-4">
            <div className="flex items-center justify-between mb-2">
              <label className="font-body-sm text-muted">Amount to Stake</label>
              {isConnected && (
                <span className="font-caption text-muted">
                  Balance: <span className="tabular-nums">{Number(staking.walletBalance).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span> CENTS
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

          {/* Preview */}
          <div className="bg-black rounded-sm p-4 mb-4 border border-border">
            <div className="flex items-center justify-between mb-2">
              <span className="text-muted font-body-sm">Currently Staked</span>
              <span className="tabular-nums">
                {Number(staking.staked).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} CENTS
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted font-body-sm">After Staking</span>
              <span className="tabular-nums text-dollar-green">
                {(Number(staking.staked) + Number(amount || 0)).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} CENTS
              </span>
            </div>
          </div>

          {/* Error */}
          {error && (
            <div className="bg-error-muted/30 border border-error-muted rounded-sm p-3 mb-4">
              <p className="text-error font-body-sm">{error}</p>
            </div>
          )}

          {/* Success */}
          {stake.stakeSuccess && (
            <div className="bg-dollar-green/15 border border-dollar-green/30 rounded-sm p-3 mb-4">
              <p className="text-dollar-green font-body-sm">Successfully staked CENTS!</p>
            </div>
          )}

          {/* Submit */}
          {isConnected ? (
            <button
              type="submit"
              disabled={!amount || Number(amount) <= 0 || isLoading || stake.stakeSuccess}
              className="w-full py-3 px-6 rounded-sm font-medium text-sm bg-dollar-green hover:bg-dollar-green-light text-black disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
            >
              {isLoading && (
                <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
              )}
              {getButtonText()}
            </button>
          ) : (
            <div className="text-center py-3 px-4 bg-black border border-border rounded-sm text-muted font-body-sm">
              Connect wallet to stake
            </div>
          )}
        </form>
      ) : (
        /* Unstake Mode */
        <div>
          {/* Current Stake Info */}
          <div className="bg-black rounded-sm p-4 mb-4 border border-border">
            <div className="flex items-center justify-between mb-2">
              <span className="text-muted font-body-sm">Staked Amount</span>
              <span className="tabular-nums">
                {Number(staking.staked).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} CENTS
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-muted font-body-sm">Current Power</span>
              <span className="tabular-nums">
                {Number(staking.stakePower).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ({staking.powerPercentage}%)
              </span>
            </div>
          </div>

          {/* Unstaking Status */}
          {staking.isUnstaking && (
            <div className="bg-gold/10 border border-gold/30 rounded-sm p-4 mb-4">
              <div className="flex items-center justify-between mb-2">
                <span className="text-gold font-body-sm">Unstaking in Progress</span>
                <span className="text-gold font-body-sm tabular-nums">
                  {staking.canCompleteUnstake ? "Ready!" : formatDuration(staking.timeUntilUnstakeComplete)}
                </span>
              </div>
              <p className="text-muted font-caption">
                {staking.canCompleteUnstake
                  ? "Your cooldown is complete. Click below to withdraw your CENTS."
                  : "7-day cooldown in progress. Your stake power is currently 0."}
              </p>
            </div>
          )}

          {/* Warning */}
          {!staking.isUnstaking && Number(staking.staked) > 0 && (
            <div className="bg-error-muted/20 border border-error-muted/30 rounded-sm p-4 mb-4">
              <p className="text-muted font-body-sm">
                <span className="text-error font-medium">Warning:</span> Unstaking initiates a 7-day cooldown during which your stake power drops to 0. You will lose all fee discounts and queue priority.
              </p>
            </div>
          )}

          {/* Error */}
          {error && (
            <div className="bg-error-muted/30 border border-error-muted rounded-sm p-3 mb-4">
              <p className="text-error font-body-sm">{error}</p>
            </div>
          )}

          {/* Success Messages */}
          {unstake.unstakeSuccess && (
            <div className="bg-gold/15 border border-gold/30 rounded-sm p-3 mb-4">
              <p className="text-gold font-body-sm">Unstake initiated! 7-day cooldown started.</p>
            </div>
          )}
          {unstake.completeSuccess && (
            <div className="bg-dollar-green/15 border border-dollar-green/30 rounded-sm p-3 mb-4">
              <p className="text-dollar-green font-body-sm">Successfully unstaked! CENTS returned to wallet.</p>
            </div>
          )}
          {unstake.cancelSuccess && (
            <div className="bg-dollar-green/15 border border-dollar-green/30 rounded-sm p-3 mb-4">
              <p className="text-dollar-green font-body-sm">Unstake cancelled. Stake power timer reset.</p>
            </div>
          )}

          {/* Buttons */}
          {isConnected ? (
            <div className="space-y-3">
              {staking.isUnstaking ? (
                <>
                  <button
                    onClick={() => unstake.completeUnstake()}
                    disabled={!staking.canCompleteUnstake || isLoading}
                    className="w-full py-3 px-6 rounded-sm font-medium text-sm bg-dollar-green hover:bg-dollar-green-light text-black disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
                  >
                    {unstake.isCompleting && (
                      <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
                    )}
                    {staking.canCompleteUnstake ? "Complete Unstake" : `${formatDuration(staking.timeUntilUnstakeComplete)} remaining`}
                  </button>
                  <button
                    onClick={() => unstake.cancelUnstake()}
                    disabled={isLoading}
                    className="w-full py-3 px-6 rounded-sm font-medium text-sm bg-transparent border border-border hover:border-dollar-green text-muted hover:text-white disabled:opacity-50"
                  >
                    {unstake.isCancelling && (
                      <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
                    )}
                    Cancel & Keep Staking
                  </button>
                </>
              ) : (
                <button
                  onClick={() => unstake.initiateUnstake()}
                  disabled={Number(staking.staked) === 0 || isLoading}
                  className="w-full py-3 px-6 rounded-sm font-medium text-sm bg-withdraw-bg hover:bg-withdraw-hover text-gold border border-withdraw-border disabled:bg-disabled-bg disabled:text-muted disabled:cursor-not-allowed"
                >
                  {unstake.isInitiating && (
                    <span className="inline-block w-4 h-4 border-2 border-current/30 border-t-current rounded-full animate-spin mr-2" />
                  )}
                  Begin Unstake (7-day cooldown)
                </button>
              )}
            </div>
          ) : (
            <div className="text-center py-3 px-4 bg-black border border-border rounded-sm text-muted font-body-sm">
              Connect wallet to unstake
            </div>
          )}
        </div>
      )}

      {/* Info text */}
      <p className="mt-4 font-caption text-muted text-center">
        {mode === "stake"
          ? "Stake grows to full power over 30 days"
          : "7-day cooldown required to unstake"}
      </p>
    </div>
  );
}
