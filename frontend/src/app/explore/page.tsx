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
    category: "Core allocation",
    strategy: "Large-cap DeFi exposure built for users prioritizing protocol durability.",
    curator: "Bundl Labs",
    tokenCount: 12,
    aum: "$18.6M",
    rebalancing: "Weekly",
    performance7d: 8.2,
    riskLevel: 2,
    chartBars: [25, 50, 33, 75, 66, 80, 100],
  },
  {
    id: "layer-1-leaders",
    name: "Layer 1 Leaders",
    category: "Momentum",
    strategy: "A basket of L1 networks with strong liquidity, throughput, and narrative pull.",
    curator: "Atlas Research",
    tokenCount: 8,
    aum: "$9.4M",
    rebalancing: "Biweekly",
    performance7d: 12.4,
    riskLevel: 3,
    chartBars: [66, 50, 80, 66, 75, 100, 80],
  },
  {
    id: "ai-big-data",
    name: "AI & Big Data",
    category: "Thematic",
    strategy: "Focused exposure to AI infra, data orchestration, and compute-adjacent protocols.",
    curator: "Signal Desk",
    tokenCount: 5,
    aum: "$6.1M",
    rebalancing: "Weekly",
    performance7d: -2.1,
    riskLevel: 3,
    chartBars: [100, 80, 75, 66, 50, 40, 25],
  },
  {
    id: "stable-yields",
    name: "Stable Yields",
    category: "Defensive",
    strategy: "Yield-oriented stablecoin strategies designed to minimize rotation noise.",
    curator: "Treasury Ops",
    tokenCount: 2,
    aum: "$22.8M",
    rebalancing: "Monthly",
    performance7d: 0.4,
    riskLevel: 1,
    chartBars: [60, 62, 61, 63, 64, 65, 66],
  },
  {
    id: "sustainable-energy",
    name: "Sustainable Energy",
    category: "Narrative",
    strategy: "Climate and clean-energy token exposure across infrastructure and tokenized assets.",
    curator: "Orbital",
    tokenCount: 15,
    aum: "$4.7M",
    rebalancing: "Monthly",
    performance7d: 5.5,
    riskLevel: 2,
    chartBars: [20, 40, 25, 60, 80, 66, 100],
  },
  {
    id: "infrastructure-2",
    name: "Infrastructure 2.0",
    category: "Builders",
    strategy: "Infra primitives spanning interoperability, middleware, and execution layers.",
    curator: "Foundry Index",
    tokenCount: 20,
    aum: "$11.2M",
    rebalancing: "Quarterly",
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
        <section className={styles.overview}>
          <div className={styles.overviewCopy}>
            <span className={styles.eyebrow}>Explore Bundls</span>
            <h1 className={styles.title}>Professional index discovery, not a wall of interchangeable cards.</h1>
            <p className={styles.subtitle}>
              Browse thematic portfolios with a clearer read on thesis, rebalance cadence, and risk posture before you commit capital.
            </p>
          </div>
          <div className={styles.overviewStats}>
            <div>
              <strong>48</strong>
              <span>Live strategies</span>
            </div>
            <div>
              <strong>7 sectors</strong>
              <span>Across DeFi, infra, AI, and more</span>
            </div>
            <div>
              <strong>Hourly</strong>
              <span>NAV refresh and screening</span>
            </div>
          </div>
        </section>
        <SearchFilter />
        <div className={styles.resultsBar}>
          <p>Showing curated strategies ranked by recent conviction and portfolio quality.</p>
          <button className={styles.sortBtn}>Sort: Featured first</button>
        </div>
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
