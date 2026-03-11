import Navbar from "@/components/Navbar";
import Dashboard from "@/components/Dashboard";
import SwapCard from "@/components/SwapCard";
import Footer from "@/components/Footer";
import styles from "./page.module.css";

// Static params for our demo bundls
export function generateStaticParams() {
  return [
    { id: "blue-chip-defi" },
    { id: "layer-1-leaders" },
    { id: "ai-big-data" },
    { id: "stable-yields" },
    { id: "sustainable-energy" },
    { id: "infrastructure-2" },
  ];
}

const BUNDL_NAMES: Record<string, string> = {
  "blue-chip-defi": "Blue Chip DeFi",
  "layer-1-leaders": "Layer 1 Leaders",
  "ai-big-data": "AI & Big Data",
  "stable-yields": "Stable Yields",
  "sustainable-energy": "Sustainable Energy",
  "infrastructure-2": "Infrastructure 2.0",
};

export default async function BundlDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const name = BUNDL_NAMES[id] || id;

  return (
    <>
      <Navbar />
      <main className={styles.main}>
        <div className={styles.header}>
          <a href="/" className={styles.backLink}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <polyline points="15 18 9 12 15 6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            Back to Explore
          </a>
          <h1 className={styles.title}>{name}</h1>
          <p className={styles.subtitle}>
            View composition, trade, or redeem your index tokens.
          </p>
        </div>

        <div className={styles.layout}>
          <div className={styles.dashboardCol}>
            <Dashboard />
          </div>
          <div className={styles.swapCol}>
            <SwapCard />
          </div>
        </div>
      </main>
      <Footer />
    </>
  );
}
