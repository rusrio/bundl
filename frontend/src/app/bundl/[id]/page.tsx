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

const BUNDL_META: Record<string, { category: string; thesis: string; volatility: string }> = {
  "blue-chip-defi": {
    category: "Core allocation",
    thesis: "A higher-conviction basket built around liquid majors.",
    volatility: "Low volatility",
  }
  // "layer-1-leaders": {
  //   category: "Momentum",
  //   thesis: "A directional mix of L1 ecosystems with strong market structure and developer gravity.",
  //   cadence: "Biweekly rebalance",
  //   risk: "High beta",
  // },
  // "ai-big-data": {
  //   category: "Thematic",
  //   thesis: "Targeted AI and data-infrastructure exposure for users leaning into narrative rotation.",
  //   cadence: "Weekly rebalance",
  //   risk: "High risk",
  // },
  // "stable-yields": {
  //   category: "Defensive",
  //   thesis: "A lower-volatility structure focused on preserving capital while harvesting stable yield.",
  //   cadence: "Monthly rebalance",
  //   risk: "Low risk",
  // },
  // "sustainable-energy": {
  //   category: "Narrative",
  //   thesis: "A clean-energy thesis spanning tokenized infrastructure, climate markets, and adjacent assets.",
  //   cadence: "Monthly rebalance",
  //   risk: "Moderate risk",
  // },
  // "infrastructure-2": {
  //   category: "Builders",
  //   thesis: "Infrastructure primitives across interoperability, execution, and middleware layers.",
  //   cadence: "Quarterly rebalance",
  //   risk: "Moderate risk",
  // },
};

export default async function BundlDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const name = BUNDL_NAMES[id] || id;
  const meta = BUNDL_META[id] || {
    category: "Curated strategy",
    thesis: "A professionally packaged index strategy with onchain execution and transparent composition.",
    volatility: "Moderate risk",
  };

  return (
    <>
      <Navbar />
      <main className={styles.main}>
        <section className={styles.hero}>
          <div className={styles.heroGlow} />
          <div className={styles.heroCopy}>
            <a href="/explore" className={styles.backLink}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <polyline points="15 18 9 12 15 6" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              Back to Explore
            </a>
            <span className={styles.eyebrow}>{meta.category}</span>
            <h1 className={styles.title}>{name}</h1>
            <p className={styles.subtitle}>{meta.thesis}</p>

            <div className={styles.heroMeta}>
              <div>
                <strong>NAV-aware</strong>
                <span>Execution priced from underlying spot markets</span>
              </div>
              <div>
                <strong>{meta.volatility}</strong>
                <span>Volatility posture for this basket configuration</span>
              </div>
            </div>
          </div>

          <div className={styles.heroPanel}>
            <span className={styles.panelLabel}>Strategy brief</span>
            <div className={styles.panelGrid}>
              <div>
                <strong>Onchain</strong>
                <span>Mint, sell, or redeem through the live vault flow.</span>
              </div>
              <div>
                <strong>Transparent</strong>
                <span>Composition, supply, and backing visible in one place.</span>
              </div>
              <div>
                <strong>Composable</strong>
                <span>Built around Bundl routing and Uniswap v4 infrastructure.</span>
              </div>
              <div>
                <strong>Auditable</strong>
                <span>Readable mechanics instead of opaque portfolio wrappers.</span>
              </div>
            </div>
          </div>
        </section>

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
