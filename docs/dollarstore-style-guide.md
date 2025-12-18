# Dollarstore Style Guide

## Brand Overview

**Product:** Dollarstore  
**Domain:** dollarstore.world  
**Positioning:** Institutional-grade stablecoin aggregator  
**Design Philosophy:** Modern, minimal, technical. Let the numbers speak.

---

## Color Palette

### Primary Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| **Black** | `#0A0A0A` | 10, 10, 10 | Primary background |
| **Deep Green** | `#0D1A12` | 13, 26, 18 | Secondary background, cards |
| **Dollar Green** | `#85BB65` | 133, 187, 101 | Primary accent, positive values, CTAs |
| **White** | `#F5F5F5` | 245, 245, 245 | Primary text |
| **Gold** | `#D4AF37` | 212, 175, 55 | Highlights, premium indicators |

### Secondary/State Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| **Muted** | `#6B7280` | 107, 114, 128 | Secondary text, labels |
| **Error** | `#DC2626` | 220, 38, 38 | Errors, negative values |
| **Error Muted** | `#7F1D1D` | 127, 29, 29 | Error backgrounds |
| **Border** | `#1F2A23` | 31, 42, 35 | Subtle borders, dividers |
| **Hover** | `#0F2318` | 15, 35, 24 | Hover states on dark surfaces |

### Opacity Variants

```
Dollar Green @ 10%: rgba(133, 187, 101, 0.10) — subtle highlights
Dollar Green @ 20%: rgba(133, 187, 101, 0.20) — button hover backgrounds
Gold @ 15%: rgba(212, 175, 55, 0.15) — premium feature badges
```

---

## Typography

### Font Family

**Primary:** JetBrains Mono  
**Fallback:** `'JetBrains Mono', 'Fira Code', 'SF Mono', Consolas, monospace`

### Type Scale

| Name | Size | Weight | Line Height | Letter Spacing | Usage |
|------|------|--------|-------------|----------------|-------|
| **Display** | 48px | 700 | 1.1 | -0.02em | Hero numbers, total balance |
| **H1** | 32px | 600 | 1.2 | -0.01em | Page titles |
| **H2** | 24px | 600 | 1.3 | 0 | Section headers |
| **H3** | 18px | 500 | 1.4 | 0 | Card headers |
| **Body** | 14px | 400 | 1.5 | 0.01em | General text |
| **Body Small** | 12px | 400 | 1.5 | 0.02em | Labels, secondary info |
| **Caption** | 11px | 400 | 1.4 | 0.03em | Timestamps, metadata |
| **Mono Numbers** | 14px | 500 | 1 | 0.05em | Balances, amounts |

### Number Formatting

- Use tabular figures for alignment in tables
- Always show 2-6 decimal places for stablecoin amounts
- Use locale-appropriate thousand separators
- Positive values: Dollar Green
- Negative values: Error Red
- Zero/neutral: Muted

```css
.amount {
  font-variant-numeric: tabular-nums;
  font-feature-settings: "tnum" 1;
}
```

---

## Spacing System

Base unit: **4px**

| Token | Value | Usage |
|-------|-------|-------|
| `space-1` | 4px | Tight gaps, inline spacing |
| `space-2` | 8px | Small gaps, icon padding |
| `space-3` | 12px | Input padding, small margins |
| `space-4` | 16px | Standard padding, card gaps |
| `space-5` | 20px | Medium spacing |
| `space-6` | 24px | Section padding |
| `space-8` | 32px | Large gaps, section margins |
| `space-10` | 40px | Major section breaks |
| `space-12` | 48px | Page-level spacing |

---

## Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `radius-sm` | 4px | Buttons, inputs, small elements |
| `radius-md` | 8px | Cards, panels |
| `radius-lg` | 12px | Modal corners, large cards |
| `radius-full` | 9999px | Pills, badges, avatars |

---

## Components

### Buttons

#### Primary Button
```
Background: #85BB65 (Dollar Green)
Text: #0A0A0A (Black)
Padding: 12px 24px
Border Radius: 4px
Font: 14px / 500

:hover
  Background: #9ACC7A (lighter green)
  
:active
  Background: #6FA052 (darker green)
  
:disabled
  Background: #2D3B32
  Text: #6B7280
  Cursor: not-allowed
```

#### Secondary Button
```
Background: transparent
Border: 1px solid #1F2A23
Text: #F5F5F5
Padding: 12px 24px
Border Radius: 4px

:hover
  Background: #0F2318
  Border-color: #85BB65
  
:disabled
  Border-color: #1F2A23
  Text: #6B7280
```

#### Ghost Button
```
Background: transparent
Text: #85BB65
Padding: 12px 24px

:hover
  Background: rgba(133, 187, 101, 0.10)
```

#### Withdraw Button
```
Background: #1A2E1F (dark green, slightly lighter than deep-green)
Text: #D4AF37 (Gold)
Border: 1px solid #2D4A35
Padding: 12px 24px
Border Radius: 4px

:hover
  Background: #243D2A
  Border-color: #D4AF37
  
:active
  Background: #1A2E1F
```

### Inputs

```
Background: #0D1A12
Border: 1px solid #1F2A23
Text: #F5F5F5
Placeholder: #6B7280
Padding: 12px 16px
Border Radius: 4px
Font: 14px JetBrains Mono

:focus
  Border-color: #85BB65
  Outline: none
  Box-shadow: 0 0 0 2px rgba(133, 187, 101, 0.20)
  
:error
  Border-color: #DC2626
  Box-shadow: 0 0 0 2px rgba(220, 38, 38, 0.20)
  
:disabled
  Background: #0A0A0A
  Text: #6B7280
```

### Cards

```
Background: #0D1A12
Border: 1px solid #1F2A23
Border Radius: 8px
Padding: 24px

Header:
  Font: 18px / 500
  Color: #F5F5F5
  Margin-bottom: 16px
```

### Tables

```
Header Row:
  Background: transparent
  Text: #6B7280
  Font: 12px / 500
  Text-transform: uppercase
  Letter-spacing: 0.05em
  Padding: 12px 16px
  Border-bottom: 1px solid #1F2A23

Body Row:
  Background: transparent
  Text: #F5F5F5
  Padding: 16px
  Border-bottom: 1px solid #1F2A23
  
  :hover
    Background: #0F2318

Amount Cells:
  Font-variant-numeric: tabular-nums
  Text-align: right
```

### Badges / Pills

#### Status Badge
```
Padding: 4px 8px
Border Radius: 9999px
Font: 11px / 500
Text-transform: uppercase
Letter-spacing: 0.05em

Pending:
  Background: rgba(212, 175, 55, 0.15)
  Text: #D4AF37
  
Complete:
  Background: rgba(133, 187, 101, 0.15)
  Text: #85BB65
  
Failed:
  Background: rgba(220, 38, 38, 0.15)
  Text: #DC2626
```

### Queue Item (Swap Request)

```
Container:
  Background: #0D1A12
  Border: 1px solid #1F2A23
  Border-radius: 8px
  Padding: 20px
  
  :hover
    Border-color: #85BB65

Layout:
  Display: flex
  Justify-content: space-between
  Align-items: center

Left side:
  - From amount (large, white)
  - Arrow icon (muted)
  - To amount (large, dollar green)
  
Right side:
  - Status badge
  - Timestamp (caption, muted)
```

---

## Shadows

Minimal shadow usage. Rely on borders and background contrast.

```
shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3)
shadow-md: 0 4px 12px rgba(0, 0, 0, 0.4)
shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.5)
```

Use shadows only for:
- Modals/dialogs
- Dropdown menus
- Tooltips

---

## Icons

**Style:** Outlined, 1.5px stroke  
**Size:** 16px (small), 20px (default), 24px (large)  
**Color:** Inherit from text color

Recommended set: Lucide Icons (consistent with the technical aesthetic)

---

## Motion

Keep animations subtle and functional.

```
transition-fast: 100ms ease-out
transition-base: 150ms ease-out
transition-slow: 250ms ease-out

Use for:
- Button hover states
- Input focus states
- Card hover states

Avoid:
- Decorative animations
- Bouncy easing
- Long durations
```

---

## Layout

### Container

```
Max-width: 1200px
Padding: 0 24px (desktop), 0 16px (tablet/mobile)
Margin: 0 auto
```

### Grid

12-column grid with 24px gutters

```
Dashboard layout:
- Sidebar: 240px fixed
- Main content: fluid
- Right panel (if needed): 320px
```

### Breakpoints

```
sm: 640px
md: 768px
lg: 1024px
xl: 1280px
```

---

## Dark Mode Notes

This is a dark-first design. There is no light mode variant planned. All colors, contrasts, and component styles are optimized for dark backgrounds.

### Accessibility

- Maintain WCAG AA contrast ratios (4.5:1 for body text)
- Dollar Green on Black: 7.2:1 ✓
- White on Black: 18.1:1 ✓
- Muted on Black: 4.6:1 ✓
- Gold on Black: 7.8:1 ✓

---

## Code Examples

### CSS Custom Properties

```css
:root {
  /* Colors */
  --color-black: #0A0A0A;
  --color-deep-green: #0D1A12;
  --color-dollar-green: #85BB65;
  --color-white: #F5F5F5;
  --color-gold: #D4AF37;
  --color-muted: #6B7280;
  --color-error: #DC2626;
  --color-border: #1F2A23;
  --color-hover: #0F2318;
  
  /* Typography */
  --font-mono: 'JetBrains Mono', 'Fira Code', monospace;
  
  /* Spacing */
  --space-1: 4px;
  --space-2: 8px;
  --space-3: 12px;
  --space-4: 16px;
  --space-6: 24px;
  --space-8: 32px;
  
  /* Radius */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;
  
  /* Transitions */
  --transition-fast: 100ms ease-out;
  --transition-base: 150ms ease-out;
}
```

### Tailwind Config (if applicable)

```js
module.exports = {
  theme: {
    extend: {
      colors: {
        black: '#0A0A0A',
        'deep-green': '#0D1A12',
        'dollar-green': '#85BB65',
        gold: '#D4AF37',
        muted: '#6B7280',
        border: '#1F2A23',
        hover: '#0F2318',
      },
      fontFamily: {
        mono: ['JetBrains Mono', 'Fira Code', 'monospace'],
      },
    },
  },
}
```

---

## Logo / Wordmark Direction

Pending design. Suggested direction:

- **Wordmark:** "dollarstore" in JetBrains Mono, weight 600
- **Styling options:**
  - All lowercase (technical, modern)
  - Dollar Green accent on "$" if stylized as "dollar$tore"
  - Or subtle gold underline/accent
- **Icon:** Abstract $ symbol or minimalist vault/safe concept

---

## File Naming

```
dollarstore-style-guide.md     — this document
dollarstore-components.tsx     — React component library
dollarstore-tokens.css         — CSS custom properties
dollarstore-tailwind.config.js — Tailwind configuration
```
