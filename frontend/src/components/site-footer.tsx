import Link from "next/link";
import { Logo } from "./logo";
import { AUDITS } from "@/config/contracts";

const LINKS = [
  { href: "https://docs.dollarstore.world", label: "Docs", external: true },
  { href: "https://github.com/wandering-soupsmith/dollar", label: "GitHub", external: true },
  { href: AUDITS.current.href, label: "Audit", external: true },
  { href: "/terms", label: "Terms", external: false },
  { href: "/privacy", label: "Privacy", external: false },
];

export function SiteFooter() {
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
            {LINKS.map((l) => (
              <Link
                key={l.label}
                href={l.href}
                target={l.external ? "_blank" : undefined}
                rel={l.external ? "noopener noreferrer" : undefined}
                className="text-sm text-muted hover:text-paper"
              >
                {l.label}
              </Link>
            ))}
          </nav>
        </div>
        <div className="mt-8 pt-6 border-t border-hairline flex flex-col sm:flex-row items-center justify-between gap-3">
          <p className="serial" style={{ letterSpacing: "0.14em" }}>
            SN 0000-0001-USD · DOLLAR STORE PROTOCOL
          </p>
          <p className="text-faint text-xs">
            Audited by{" "}
            <Link
              href={AUDITS.current.href}
              target="_blank"
              rel="noopener noreferrer"
              className="text-muted hover:text-dollar-bright underline underline-offset-2"
            >
              OpenZeppelin
            </Link>
            . Use at your own risk.
          </p>
        </div>
      </div>
    </footer>
  );
}
