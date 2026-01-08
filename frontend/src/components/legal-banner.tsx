"use client";

import Link from "next/link";

export function LegalBanner() {
  return (
    <div className="bg-deep-green border-b border-border py-2 px-6">
      <div className="max-w-[1200px] mx-auto flex items-center justify-center gap-2 font-caption text-muted text-center">
        <span>
          Transactions execute via autonomous smart contracts.
        </span>
        <Link
          href="/terms"
          className="text-dollar-green hover:text-dollar-green-light underline"
        >
          Terms
        </Link>
      </div>
    </div>
  );
}
