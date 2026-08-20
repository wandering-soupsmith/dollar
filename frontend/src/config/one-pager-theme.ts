/**
 * The one-pager palette, in both variants.
 *
 * The page itself is styled from the `.one-pager` custom properties in `globals.css`; these values
 * exist because the generated OG cards are rendered by satori, which cannot read CSS variables.
 * The two must stay in step — change a colour here and change it there.
 *
 * The variants are not a mechanical inversion. In the cream original one warm brass carries both
 * the hero accent and the stat figures; in the dark one those split, with the figures going lime
 * and "one dollar" staying gold. Several emphases move the same way, so they get their own tokens
 * rather than being hardcoded per variant.
 */
export type OnePagerTheme = "light" | "dark";

export type Palette = {
  bg: string;
  /** Headlines and other high-contrast type. */
  ink: string;
  /** Body copy. */
  body: string;
  /** Captions and the legal disclaimer. */
  soft: string;
  /** Small-caps section marks, and emphasis like "Queued positions get filled." */
  olive: string;
  /** The hero accent — "one dollar". */
  brass: string;
  /** The stat numerals. Tracks `brass` in light, goes lime in dark. */
  figure: string;
  /** Inline emphasis that sits in running copy: "exactly 1:1", and the pair arrows. */
  emphasis: string;
  /** The small-caps labels under each stat figure. */
  label: string;
  /** The call-to-action band. Deliberately identical in both variants: it is the signature. */
  lime: string;
  /** Type set on the lime band. */
  onLime: string;
  rule: string;
};

export const PALETTES: Record<OnePagerTheme, Palette> = {
  light: {
    bg: "#f1f1eb",
    ink: "#191a12",
    body: "#4d4f45",
    soft: "#85887a",
    olive: "#828e2d",
    brass: "#a08b2c",
    figure: "#a08b2c",
    emphasis: "#191a12",
    label: "#4d4f45",
    lime: "#c9dc4a",
    onLime: "#2f3a15",
    rule: "#d7d7cb",
  },
  dark: {
    bg: "#17170f",
    ink: "#eaeae1",
    body: "#c0c1b7",
    soft: "#7c7d73",
    olive: "#c2d44a",
    brass: "#d7ac47",
    figure: "#c8d94a",
    emphasis: "#c2d44a",
    label: "#d2d3c9",
    lime: "#c9dc4a",
    onLime: "#2f3a15",
    rule: "#2e2e25",
  },
};

/** The URL segment that selects the dark variant: `/<SYMBOL>/dark`. */
export const DARK_SEGMENT = "dark";
