import type { Metadata } from "next";
import Link from "next/link";
import { CONTRACTS, IS_DEPLOYED } from "@/config/contracts";
import { Logo } from "@/components/logo";

export const metadata: Metadata = {
  title: "Dollar Store | Zero-Fee Stablecoin Swaps",
  description:
    "Open-source protocol enabling 1:1 stablecoin swaps with no fees and no slippage. Published by Buckets LLC.",
  keywords: ["stablecoin", "USDC", "USDS", "USDT", "swap", "DeFi", "Ethereum", "protocol"],
  openGraph: {
    title: "Dollar Store",
    description: "Zero-fee stablecoin swaps",
    siteName: "Dollar Store",
    type: "website",
  },
};

function MarketingHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-hairline-strong bg-ink/80 backdrop-blur-md">
      <div className="max-w-[1180px] mx-auto px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5">
          <Logo size={22} />
          <span className="display-md text-paper tracking-tight">dollarstore</span>
        </Link>

        <nav className="flex items-center gap-2 sm:gap-4">
          <Link
            href="https://docs.dollarstore.world"
            className="hidden sm:inline text-sm font-medium text-muted hover:text-paper px-2"
          >
            Docs
          </Link>
          <Link
            href="https://github.com/coasify/dollar"
            target="_blank"
            rel="noopener noreferrer"
            className="hidden sm:inline text-sm font-medium text-muted hover:text-paper px-2"
          >
            GitHub
          </Link>
          <Link href="https://app.dollarstore.world" className="btn-primary text-sm px-4 py-2">
            Launch app
          </Link>
        </nav>
      </div>
    </header>
  );
}

function MarketingFooter() {
  return (
    <footer className="border-t border-hairline-strong mt-auto">
      <div className="max-w-[1180px] mx-auto px-6 py-10">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-6">
          <div className="flex items-center gap-2.5">
            <Logo size={20} />
            <span className="display-md text-paper">dollarstore</span>
            <span className="text-muted text-sm ml-1">Everything is a dollar</span>
          </div>

          <nav className="flex flex-wrap items-center gap-x-6 gap-y-2">
            <Link href="https://docs.dollarstore.world" className="text-sm text-muted hover:text-paper">
              Docs
            </Link>
            <Link
              href="https://github.com/coasify/dollar"
              target="_blank"
              rel="noopener noreferrer"
              className="text-sm text-muted hover:text-paper"
            >
              GitHub
            </Link>
            {IS_DEPLOYED && (
              <Link
                href={`https://etherscan.io/address/${CONTRACTS.mainnet.dollarStore}`}
                target="_blank"
                rel="noopener noreferrer"
                className="text-sm text-muted hover:text-paper"
              >
                Contract
              </Link>
            )}
            <Link href="/terms" className="text-sm text-muted hover:text-paper">
              Terms
            </Link>
            <Link href="/privacy" className="text-sm text-muted hover:text-paper">
              Privacy
            </Link>
          </nav>
        </div>

        <div className="mt-8 pt-6 border-t border-hairline text-center">
          <p className="text-faint text-xs">
            Published by Buckets LLC ·{" "}
            <a href="mailto:admin@dollarstore.world" className="text-muted hover:text-dollar-bright underline underline-offset-2">
              admin@dollarstore.world
            </a>
          </p>
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
