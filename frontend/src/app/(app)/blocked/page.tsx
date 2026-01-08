import Link from "next/link";
import { CONTRACTS } from "@/config/contracts";

export default function BlockedPage() {
  return (
    <div className="max-w-[600px] mx-auto px-6 py-24 text-center">
      <div className="text-6xl mb-6">
        <span className="text-dollar-green">$</span>
      </div>

      <h1 className="font-h1 text-white mb-4">Access Restricted</h1>

      <p className="font-body text-muted mb-8">
        The Dollar Store protocol interface is not available in your region.
      </p>

      <div className="bg-deep-green rounded-md p-6 border border-border mb-8">
        <p className="font-body-sm text-muted">
          The protocol itself remains accessible directly through smart contracts
          and alternative interfaces. This restriction applies only to this interface.
        </p>
      </div>

      <div className="flex flex-col items-center gap-4">
        <Link
          href="https://docs.dollarstore.world"
          className="text-dollar-green hover:text-dollar-green-light font-medium"
        >
          View Documentation
        </Link>
        <Link
          href={`https://etherscan.io/address/${CONTRACTS.mainnet.dollarStore}`}
          target="_blank"
          rel="noopener noreferrer"
          className="text-muted hover:text-white font-medium"
        >
          View Contract on Etherscan
        </Link>
      </div>
    </div>
  );
}
