import { ImageResponse } from "next/og";
import { findAsset } from "@/config/assets";
import { OnePagerTheme, PALETTES } from "@/config/one-pager-theme";

/**
 * The card a pasted `dollarstore.world/<SYMBOL>` link unfurls into.
 *
 * These pages travel by hand — an issuer sends the one-pager, a reader forwards the URL — so a bare
 * text unfurl is a real cost. Each variant renders its own card in its own palette, so the preview
 * and the page it opens read as the same document.
 *
 * Shared by both `/`(light) and `/dark` image routes.
 */
export const OG_SIZE = { width: 1200, height: 630 };

export function renderOnePagerCard(symbol: string, theme: OnePagerTheme) {
  const palette = PALETTES[theme];
  const label = findAsset(symbol)?.symbol ?? symbol.toUpperCase();

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          backgroundColor: palette.bg,
          padding: "68px 78px",
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 16 }}>
          <div
            style={{
              display: "flex",
              width: 44,
              height: 44,
              borderRadius: 22,
              backgroundColor: palette.olive,
              alignItems: "center",
              justifyContent: "center",
              color: palette.bg,
              fontSize: 21,
            }}
          >
            {label.charAt(label.length - 1)}
          </div>
          <span style={{ color: palette.ink, fontSize: 28 }}>dollarstore</span>
        </div>

        <div style={{ display: "flex", flexDirection: "column" }}>
          <div style={{ display: "flex", color: palette.ink, fontSize: 72, lineHeight: 1.12 }}>
            Get and sell {label} on-chain,
          </div>
          <div style={{ display: "flex", fontSize: 72, lineHeight: 1.12, color: palette.ink }}>
            always at&nbsp;<span style={{ color: palette.brass }}>one dollar</span>.
          </div>
        </div>

        <div style={{ display: "flex", alignItems: "flex-end", justifyContent: "space-between" }}>
          <div
            style={{
              display: "flex",
              backgroundColor: palette.lime,
              color: palette.onLime,
              fontSize: 28,
              padding: "12px 22px",
            }}
          >
            dollarstore.world/{label}
          </div>
          <span style={{ color: palette.soft, fontSize: 23 }}>1:1 · no fees · no slippage</span>
        </div>
      </div>
    ),
    OG_SIZE
  );
}
