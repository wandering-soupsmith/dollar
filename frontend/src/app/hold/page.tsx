import { DepositRedeem } from "@/components/deposit-redeem";

export default function HoldPage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12">
      <div className="text-center mb-12">
        <h1 className="font-h1 text-white mb-4">Hold DLRS</h1>
        <p className="font-body text-muted max-w-xl mx-auto">
          Deposit stablecoins to mint DLRS, or withdraw stablecoins by burning DLRS.
          1:1, always.
        </p>
      </div>

      <DepositRedeem />

      {/* Info section */}
      <div className="mt-12 max-w-md mx-auto">
        <div className="bg-deep-green rounded-md p-6 border border-border">
          <h3 className="font-h3 text-white mb-3">What is DLRS?</h3>
          <p className="font-body-sm text-muted mb-4">
            DLRS is a receipt token representing a 1:1 claim on the stablecoin reserves.
            When you deposit USDC or USDT, you receive an equal amount of DLRS.
          </p>
          <p className="font-body-sm text-muted">
            Most users don&apos;t need to hold DLRS directly — just use the swap interface
            on the home page. This page is for advanced users who want explicit
            control over their reserve positions.
          </p>
        </div>
      </div>
    </div>
  );
}
