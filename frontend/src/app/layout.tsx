import type { Metadata } from "next";
import { JetBrains_Mono } from "next/font/google";
import "./globals.css";

const jetbrainsMono = JetBrains_Mono({
  subsets: ["latin"],
  variable: "--font-jetbrains",
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
        className={`${jetbrainsMono.variable} font-mono antialiased bg-black text-white min-h-screen flex flex-col`}
      >
        {children}
      </body>
    </html>
  );
}
