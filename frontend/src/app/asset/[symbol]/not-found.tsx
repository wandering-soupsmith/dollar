import Link from "next/link";

/** Shown for any symbol the registry does not whitelist. Returns a 404 status. */
export default function AssetNotFound() {
  return (
    <div className="one-pager">
      <div className="mx-auto max-w-[520px] px-6 py-28 text-center">
        <p className="op-mark">Asset not supported</p>
        <h1 className="op-display op-hero mt-4">Nothing here, yet.</h1>
        <p className="text-[0.95rem] leading-[1.6] mt-5">
          Dollar Store does not have a page for that symbol. Supported assets each get their own, at
          dollarstore.world followed by the symbol.
        </p>

        <div className="flex flex-wrap items-center justify-center gap-3 mt-9">
          <Link
            href="/"
            className="px-6 py-3 text-sm font-medium"
            style={{ background: "var(--op-lime)", color: "var(--op-ink)" }}
          >
            Open the swap desk
          </Link>
          <Link
            href="https://docs.dollarstore.world"
            className="px-6 py-3 text-sm font-medium border border-[var(--op-rule)]"
            style={{ color: "var(--op-ink)" }}
          >
            Read docs
          </Link>
        </div>
      </div>
    </div>
  );
}
