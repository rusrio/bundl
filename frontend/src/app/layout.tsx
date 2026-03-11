import type { Metadata } from "next";
import "./globals.css";
import { Providers } from "@/components/Providers";

export const metadata: Metadata = {
  title: "Bundl — Forge Your Index",
  description:
    "Decentralized index tokens powered by Uniswap v4 hooks. Bundle crypto assets into a single token, swap at NAV price, and redeem for underlying assets.",
  keywords: [
    "DeFi",
    "index token",
    "Uniswap v4",
    "crypto index",
    "portfolio",
    "hook",
  ],
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
