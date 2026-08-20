import Link from "next/link";
import { CONTRACTS, IS_DEPLOYED } from "@/config/contracts";

export default function BlockedPage() {
  return (
    <div className="max-w-[600px] mx-auto px-6 py-24 text-center rise">
      <div className="denom mb-6" style={{ fontSize: "3.5rem", color: "var(--color-dollar-deep)" }}>
        $
      </div>

      <span className="eyebrow">Access restricted</span>
      <h1 className="display-lg text-paper mt-3 mb-4">Not available in your region</h1>

      <p className="text-muted leading-relaxed mb-8">
        The Dollar Store protocol interface is not available in your region.
      </p>

      <div className="note p-6 mb-8 text-left">
        <p className="relative text-muted text-sm leading-relaxed">
          The protocol itself remains accessible directly through smart contracts and alternative
          interfaces. This restriction applies only to this interface.
        </p>
      </div>

      <div className="flex flex-col items-center gap-4">
        <Link
          href="https://docs.dollarstore.world"
          target="_blank"
          rel="noopener noreferrer"
          className="text-dollar-bright hover:text-dollar font-medium"
        >
          View documentation
        </Link>
        {IS_DEPLOYED && (
          <Link
            href={`https://etherscan.io/address/${CONTRACTS.mainnet.dollarStore}`}
            target="_blank"
            rel="noopener noreferrer"
            className="text-muted hover:text-paper font-medium"
          >
            View contract on Etherscan
          </Link>
        )}
      </div>
    </div>
  );
}
