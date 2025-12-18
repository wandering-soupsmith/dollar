import Link from "next/link";

export function Footer() {
  return (
    <footer className="border-t border-border py-8 mt-auto">
      <div className="max-w-[1200px] mx-auto px-6">
        <div className="flex flex-col md:flex-row items-center justify-between gap-4">
          {/* Logo and tagline */}
          <div className="flex items-center gap-2">
            <span className="text-xl text-dollar-green">$</span>
            <span className="font-semibold text-white">dollarstore</span>
            <span className="text-muted text-sm">
              — Everything is a dollar
            </span>
          </div>

          {/* Links */}
          <div className="flex items-center gap-6 text-sm text-muted">
            <Link
              href="https://github.com/wandering-soupsmith/dollar"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white"
            >
              GitHub
            </Link>
            <Link
              href="https://sepolia.etherscan.io/address/0x84C6c922c947a2d76DCB6dF1bd7C824De0c289BF"
              target="_blank"
              rel="noopener noreferrer"
              className="hover:text-white"
            >
              Contract
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
