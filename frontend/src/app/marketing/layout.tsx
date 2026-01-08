import type { Metadata } from "next";
import Link from "next/link";
import { CONTRACTS } from "@/config/contracts";

export const metadata: Metadata = {
  title: "Dollar Store | Zero-Fee Stablecoin Infrastructure",
  description:
    "Open-source protocol enabling 1:1 stablecoin swaps with no fees and no slippage. Published by Buckets LLC.",
  keywords: ["stablecoin", "USDC", "USDT", "swap", "DeFi", "Ethereum", "protocol"],
  openGraph: {
    title: "Dollar Store",
    description: "Zero-fee stablecoin infrastructure",
    siteName: "Dollar Store",
    type: "website",
  },
};

function MarketingHeader() {
  return (
    <header className="border-b border-border">
      <div className="max-w-[1200px] mx-auto px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2 group">
          <span className="text-2xl text-dollar-green">$</span>
          <span className="font-semibold text-lg text-white">dollarstore</span>
        </Link>

        <nav className="flex items-center gap-8">
          <Link
            href="https://docs.dollarstore.world"
            className="text-sm font-medium text-muted hover:text-white"
          >
            Docs
          </Link>
          <Link
            href="https://github.com/wandering-soupsmith/dollar"
            target="_blank"
            rel="noopener noreferrer"
            className="text-sm font-medium text-muted hover:text-white"
          >
            GitHub
          </Link>
          <Link
            href="https://app.dollarstore.world"
            className="bg-dollar-green hover:bg-dollar-green-light text-black px-4 py-2 rounded-sm text-sm font-medium transition-colors"
          >
            Launch App
          </Link>
        </nav>
      </div>
    </header>
  );
}

function MarketingFooter() {
  return (
    <footer className="border-t border-border py-8 mt-auto">
      <div className="max-w-[1200px] mx-auto px-6">
        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          <div className="flex items-center gap-2">
            <span className="text-xl text-dollar-green">$</span>
            <span className="font-semibold text-white">dollarstore</span>
          </div>

          <div className="flex items-center gap-6 text-sm text-muted">
            <Link
              href="https://docs.dollarstore.world"
              className="hover:text-white"
            >
              Docs
            </Link>
            <Link
              href="https://github.com/wandering-soupsmith/dollar"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white"
            >
              GitHub
            </Link>
            <Link
              href={`https://sepolia.etherscan.io/address/${CONTRACTS.sepolia.dollarStore}`}
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white"
            >
              Contract
            </Link>
            <Link href="/terms" className="hover:text-white">
              Terms
            </Link>
          </div>
        </div>

        <div className="mt-6 pt-6 border-t border-border text-center font-caption text-muted">
          <p>Published by Buckets LLC</p>
        </div>
      </div>
    </footer>
  );
}

export default function MarketingLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <>
      <MarketingHeader />
      <main className="flex-1">{children}</main>
      <MarketingFooter />
    </>
  );
}
