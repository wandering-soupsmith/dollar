import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { AssetPage } from "@/components/asset-page";
import { ASSET_SYMBOLS, findAsset } from "@/config/assets";

/**
 * `dollarstore.world/<SYMBOL>` — the landing page an issuer's one-pager points at.
 *
 * One route serves every asset: middleware rewrites the bare `/<SYMBOL>` path here for any symbol
 * in the registry, so launching a new asset page is a registry entry and nothing else. The page is
 * fully static — its content comes from that entry, not from the chain, so it can be published
 * ahead of the listing it describes.
 */

// Registry symbols are prerendered; anything else still resolves so it can 404 through this
// segment's own not-found boundary rather than the site-wide one.
export const dynamicParams = true;

type Params = { params: Promise<{ symbol: string }> };

export function generateStaticParams() {
  return ASSET_SYMBOLS.map((symbol) => ({ symbol }));
}

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const { symbol } = await params;
  const asset = findAsset(symbol);
  if (!asset) return {};

  const title = `Swap ${asset.symbol} 1:1 on Dollar Store`;
  const description = `Convert ${asset.name} (${asset.symbol}) on-chain at exactly one dollar, in both directions. No fees, no slippage, no minimum negotiation.`;

  return {
    // Scoped to this route: asset pages are canonically served from the marketing domain, which is
    // what the one-pagers print and what the OG image URL has to resolve against.
    metadataBase: new URL("https://dollarstore.world"),
    title,
    description,
    alternates: { canonical: `/${asset.symbol}` },
    openGraph: {
      title,
      description,
      siteName: "Dollar Store",
      type: "website",
      url: `https://dollarstore.world/${asset.symbol}`,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function AssetRoute({ params }: Params) {
  const { symbol } = await params;
  const asset = findAsset(symbol);
  if (!asset) notFound();

  // Keep one canonical casing so links, metadata and analytics agree.
  if (symbol !== asset.symbol) redirect(`/${asset.symbol}`);

  return <AssetPage asset={asset} />;
}
