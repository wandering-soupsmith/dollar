import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { AssetPage } from "@/components/asset-page";
import { ASSET_SYMBOLS, findAsset } from "@/config/assets";

/**
 * `dollarstore.world/<SYMBOL>/dark` — the dark counterpart of the asset one-pager.
 *
 * Same content, same registry entry, different palette. It is its own URL rather than a system-
 * preference switch so that whoever shares the link controls which version the reader opens.
 */
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
    metadataBase: new URL("https://dollarstore.world"),
    title,
    description,
    // The two variants are the same document, so search engines are pointed at the light one.
    alternates: { canonical: `/${asset.symbol}` },
    openGraph: {
      title,
      description,
      siteName: "Dollar Store",
      type: "website",
      url: `https://dollarstore.world/${asset.symbol}/dark`,
    },
    twitter: { card: "summary_large_image", title, description },
  };
}

export default async function AssetDarkRoute({ params }: Params) {
  const { symbol } = await params;
  const asset = findAsset(symbol);
  if (!asset) notFound();

  return <AssetPage asset={asset} theme="dark" />;
}
