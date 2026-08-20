import { SwapView } from "@/components/swap-view";

// `?want=<SYMBOL>` lets an asset landing page hand the desk its asset already selected.
export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ want?: string }>;
}) {
  const { want } = await searchParams;
  return <SwapView want={want?.toUpperCase()} />;
}
