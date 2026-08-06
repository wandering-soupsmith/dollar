import type { Metadata } from "next";
import { Fraunces, Inter, JetBrains_Mono } from "next/font/google";
import "./globals.css";

// Display: an engraved, high-contrast serif — the engraved-note voice. Used with restraint.
const fraunces = Fraunces({
  subsets: ["latin"],
  variable: "--font-display",
  display: "swap",
});

// Body / UI: neutral, legible.
const inter = Inter({
  subsets: ["latin"],
  variable: "--font-sans",
  display: "swap",
});

// Data / serials: monospace, reserved for serial numbers, addresses and tabular figures.
const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Dollar Store | Stablecoin Swap Protocol",
  description:
    "Open-source protocol enabling 1:1 stablecoin swaps. No fees. No slippage.",
  keywords: ["stablecoin", "USDC", "USDT", "swap", "DeFi", "Ethereum", "protocol"],
  openGraph: {
    title: "Dollar Store",
    description: "1:1 stablecoin swaps",
    siteName: "Dollar Store",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className="dark">
      <body
        className={`${fraunces.variable} ${inter.variable} ${jetbrainsMono.variable} font-sans antialiased min-h-screen flex flex-col`}
      >
        {children}
      </body>
    </html>
  );
}
