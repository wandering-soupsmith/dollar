import { DepositRedeem } from "@/components/deposit-redeem";

export default function SupplyPage() {
  return (
    <div className="max-w-[1200px] mx-auto px-6 py-12">
      <div className="text-center mb-12">
        <h1 className="font-h1 text-white mb-4">Supply Liquidity</h1>
        <p className="font-body text-muted max-w-xl mx-auto">
          Add stablecoins to the pool or withdraw your position. 1:1, always.
        </p>
      </div>

      <DepositRedeem />
    </div>
  );
}
