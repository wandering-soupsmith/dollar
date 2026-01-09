"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAccount } from "wagmi";
import { ConnectWallet } from "./connect-wallet";
import { Logo } from "./logo";
import { useTokenBalance } from "@/hooks/useTokenBalance";

export function Header() {
  const pathname = usePathname();
  const { isConnected } = useAccount();
  const dlrsBalance = useTokenBalance("DLRS");

  const isActive = (path: string) => pathname === path;

  const hasDlrsBalance = isConnected && dlrsBalance.balance > 0n;

  const formatBalance = (balance: string) => {
    const num = Number(balance);
    if (num >= 1000000) {
      return `$${(num / 1000000).toFixed(1)}M`;
    } else if (num >= 1000) {
      return `$${(num / 1000).toFixed(1)}k`;
    }
    return `$${num.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };

  return (
    <header className="border-b border-border">
      <div className="max-w-[1200px] mx-auto px-6 h-16 flex items-center justify-between">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2 group">
          <Logo size={24} />
          <span className="font-semibold text-lg text-white">dollarstore</span>
        </Link>

        {/* Navigation */}
        <nav className="flex items-center gap-8">
          <Link
            href="/"
            className={`text-sm font-medium transition-colors ${
              isActive("/")
                ? "text-dollar-green"
                : "text-muted hover:text-white"
            }`}
          >
            Swap
          </Link>
          <Link
            href="/supply"
            className={`text-sm font-medium transition-colors ${
              isActive("/supply")
                ? "text-dollar-green"
                : "text-muted hover:text-white"
            }`}
          >
            Supply
          </Link>
        </nav>

        {/* User Balance + Wallet Connection */}
        <div className="flex items-center gap-4">
          {hasDlrsBalance && (
            <div className="text-sm">
              <span className="text-muted">Your Supply:</span>{" "}
              <span className="text-dollar-green font-medium tabular-nums">
                {formatBalance(dlrsBalance.formatted)}
              </span>
            </div>
          )}
          <ConnectWallet />
        </div>
      </div>
    </header>
  );
}
