"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectWallet } from "./connect-wallet";
import { Logo } from "./logo";

export function Header() {
  const pathname = usePathname();

  const isActive = (path: string) => pathname === path;

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

        {/* Wallet Connection */}
        <ConnectWallet />
      </div>
    </header>
  );
}
