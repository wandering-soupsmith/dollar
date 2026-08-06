"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Logo } from "./logo";

const NAV = [
  { href: "/", label: "Swap" },
  { href: "/supply", label: "Supply" },
  { href: "/markets", label: "Markets" },
];

export function SiteHeader() {
  const pathname = usePathname();
  const isActive = (href: string) =>
    href === "/" ? pathname === "/" : pathname.startsWith(href);

  const navLinks = NAV.map((item) => (
    <Link
      key={item.href}
      href={item.href}
      className="px-3 py-1.5 rounded-md text-sm font-medium"
      style={{
        color: isActive(item.href) ? "var(--color-dollar-bright)" : "var(--color-muted)",
        background: isActive(item.href) ? "rgba(133,187,101,0.08)" : "transparent",
      }}
    >
      {item.label}
    </Link>
  ));

  return (
    <header className="sticky top-0 z-40 border-b border-hairline-strong bg-ink/80 backdrop-blur-md">
      <div className="max-w-[1180px] mx-auto px-6 h-16 flex items-center justify-between">
        <Link href="/" className="flex items-center gap-2.5">
          <Logo size={22} />
          <span className="display-md text-paper tracking-tight">dollarstore</span>
        </Link>

        <nav className="hidden md:flex items-center gap-1">{navLinks}</nav>

        <div className="flex items-center gap-3">
          <span className="hidden sm:flex items-center gap-1.5 label" style={{ letterSpacing: "0.1em" }}>
            <span className="dot" style={{ background: "var(--color-dollar)" }} />
            Ethereum
          </span>
          <button type="button" className="btn-ghost text-sm px-4 py-2">
            Connect Wallet
          </button>
        </div>
      </div>

      {/* Mobile nav row */}
      <nav className="md:hidden flex items-center justify-center gap-1 pb-2 -mt-1">{navLinks}</nav>
    </header>
  );
}
