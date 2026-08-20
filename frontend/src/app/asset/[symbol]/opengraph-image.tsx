import { ASSET_SYMBOLS } from "@/config/assets";
import { OG_SIZE, renderOnePagerCard } from "@/components/one-pager-og";

export const alt = "Swap 1:1 on Dollar Store";
export const size = OG_SIZE;
export const contentType = "image/png";

export function generateStaticParams() {
  return ASSET_SYMBOLS.map((symbol) => ({ symbol }));
}

export default async function OpengraphImage({
  params,
}: {
  params: Promise<{ symbol: string }>;
}) {
  const { symbol } = await params;
  return renderOnePagerCard(symbol, "light");
}
