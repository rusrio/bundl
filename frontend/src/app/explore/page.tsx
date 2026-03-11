import Navbar from "@/components/Navbar";
import FeaturedBundl from "@/components/FeaturedBundl";
import SearchFilter from "@/components/SearchFilter";
import BundlCard from "@/components/BundlCard";
import type { BundlCardData } from "@/components/BundlCard";
import Footer from "@/components/Footer";
import styles from "./page.module.css";

const BUNDLS: BundlCardData[] = [
  {
    id: "blue-chip-defi",
    name: "Blue Chip DeFi",
    tokenCount: 12,
    performance7d: 8.2,
    riskLevel: 2,
    chartBars: [25, 50, 33, 75, 66, 80, 100],
  },
  {
    id: "layer-1-leaders",
    name: "Layer 1 Leaders",
    tokenCount: 8,
    performance7d: 12.4,
    riskLevel: 3,
    chartBars: [66, 50, 80, 66, 75, 100, 80],
  },
  {
    id: "ai-big-data",
    name: "AI & Big Data",
    tokenCount: 5,
    performance7d: -2.1,
    riskLevel: 3,
    chartBars: [100, 80, 75, 66, 50, 40, 25],
  },
  {
    id: "stable-yields",
    name: "Stable Yields",
    tokenCount: 2,
    performance7d: 0.4,
    riskLevel: 1,
    chartBars: [60, 62, 61, 63, 64, 65, 66],
  },
  {
    id: "sustainable-energy",
    name: "Sustainable Energy",
    tokenCount: 15,
    performance7d: 5.5,
    riskLevel: 2,
    chartBars: [20, 40, 25, 60, 80, 66, 100],
  },
  {
    id: "infrastructure-2",
    name: "Infrastructure 2.0",
    tokenCount: 20,
    performance7d: 1.8,
    riskLevel: 1,
    chartBars: [33, 50, 25, 66, 60, 50, 66],
  },
];

export default function Home() {
  return (
    <>
      <Navbar />
      <main className={styles.main}>
        <FeaturedBundl />
        <SearchFilter />
        <section className={styles.grid}>
          {BUNDLS.map((bundl) => (
            <BundlCard key={bundl.id} data={bundl} />
          ))}
        </section>
        <div className={styles.loadMore}>
          <button className={styles.loadMoreBtn}>
            Load More Bundls
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <polyline points="6 9 12 15 18 9" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        </div>
      </main>
      <Footer />
    </>
  );
}
