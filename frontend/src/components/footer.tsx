import Link from "next/link";
import { CONTRACTS } from "@/config/contracts";
import { Logo } from "./logo";

export function Footer() {
  return (
    <footer className="border-t border-border py-8 mt-auto">
      <div className="max-w-[1200px] mx-auto px-6">
        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          {/* Logo and tagline */}
          <div className="flex items-center gap-2">
            <Logo size={20} />
            <span className="font-semibold text-white">dollarstore</span>
            <span className="text-muted text-sm">
              — Everything is a dollar
            </span>
          </div>

          {/* Links */}
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
          <p>
            dollarstore is unaudited software. Use at your own risk.
          </p>
        </div>
      </div>
    </footer>
  );
}
