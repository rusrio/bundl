import Link from "next/link";
import ForgeCanvas from "@/components/ForgeCanvas";
import Navbar from "@/components/Navbar";
import styles from "./page.module.css";

const featuredBundls = [
  {
    name: "Blue Chip DeFi",
    symbol: "bBLUE",
    composition: [
      { label: "BTC", value: "50%" },
      { label: "ETH", value: "50%" },
    ],
    note: "For users who want a calm core position instead of juggling majors one by one.",
  },
  {
    name: "BTC-ETH-UNI Index",
    symbol: "bBEU",
    composition: [
      { label: "BTC", value: "40%" },
      { label: "ETH", value: "30%" },
      { label: "UNI", value: "30%" },
    ],
    note: "A tighter basket leaning into majors plus liquidity infrastructure.",
  },
];

const process = [
  {
    index: "01",
    title: "Pick a thesis",
    text: "Choose a basket that matches the exposure you actually want, instead of manually recreating it across several swaps.",
  },
  {
    index: "02",
    title: "Mint one position",
    text: "Bundl compresses a multi-asset idea into a single redeemable token that is easier to understand and easier to hold.",
  },
  {
    index: "03",
    title: "Redeem back out",
    text: "Burn the index token when you want to unwind and return to the underlying assets directly onchain.",
  },
];

export default function LandingPage() {
  return (
    <>
      <ForgeCanvas />
      <Navbar />

      <main className={styles.main}>
        <section className={styles.hero}>
          <div className={styles.heroFrame}>
            <div className={styles.heroCopy}>

              <h1 className={styles.heroTitle}>
                Build a portfolio
                <span className={styles.heroAccent}> that behaves like one asset.</span>
              </h1>

              <p className={styles.heroText}>
                Bundl turns a basket of assets into a single redeemable token.
                The point is not novelty. The point is cleaner exposure, cleaner
                execution, and a simpler way to move through DeFi.
              </p>

              <div className={styles.heroActions}>
                <Link href="/explore" className={styles.primaryLink}>
                  Enter App
                </Link>
                <a href="#process" className={styles.secondaryLink}>
                  Read the flow
                </a>
              </div>
            </div>
          </div>

          <div className={styles.scrollHint}>
            <span>Keep scrolling</span>
            <div className={styles.scrollBar}>
              <div className={styles.scrollDot} />
            </div>
          </div>
        </section>

        <section className={styles.manifesto}>
          <div className={styles.manifestoIntro}>
            <span className={styles.sectionMark}>Why Bundl</span>
            <h2 className={styles.sectionTitle}>
              Most crypto interfaces add more moving parts than they remove.
            </h2>
          </div>

          <div className={styles.manifestoBody}>
            <p className={styles.manifestoLead}>
              Bundl is better when it feels quieter. Less dashboard theater,
              less inflated metrics, less “all-in-one super app” language. What
              matters is the structure: basket in, single token out, underlying
              redeemable later.
            </p>

            <div className={styles.manifestoStats}>
              <div>
                <span className={styles.statValue}>2</span>
                <span className={styles.statText}>live Bundls wired in the app today</span>
              </div>
              <div>
                <span className={styles.statValue}>1</span>
                <span className={styles.statText}>clean position instead of several manual entries</span>
              </div>
              <div>
                <span className={styles.statValue}>100%</span>
                <span className={styles.statText}>onchain mint and redeem path</span>
              </div>
            </div>
          </div>
        </section>

        <section id="featured" className={styles.featuredSection}>
          <div className={styles.sectionIntro}>
            <span className={styles.sectionMark}>Current Bundls</span>
            <h2 className={styles.sectionTitle}>Two baskets, shown plainly.</h2>
          </div>

          <div className={styles.featuredGrid}>
            {featuredBundls.map((bundl, index) => (
              <article
                key={bundl.symbol}
                className={`${styles.featuredCard} ${index % 2 === 1 ? styles.featuredCardOffset : ""}`}
              >
                <div className={styles.featuredHeader}>
                  <div>
                    <p className={styles.featuredSymbol}>{bundl.symbol}</p>
                    <h3 className={styles.featuredTitle}>{bundl.name}</h3>
                  </div>
                  <span className={styles.featuredTag}>Redeemable</span>
                </div>

                <p className={styles.featuredNote}>{bundl.note}</p>

                <div className={styles.compositionList}>
                  {bundl.composition.map((item) => (
                    <div key={`${bundl.symbol}-${item.label}`} className={styles.compositionRow}>
                      <span>{item.label}</span>
                      <span>{item.value}</span>
                    </div>
                  ))}
                </div>
              </article>
            ))}
          </div>
        </section>

        <section id="process" className={styles.processSection}>
          <div className={styles.sectionIntro}>
            <h2 className={styles.sectionTitle}>Three moves. No drama.</h2>
          </div>

          <div className={styles.processList}>
            {process.map((step) => (
              <article key={step.index} className={styles.processItem}>
                <span className={styles.processIndex}>{step.index}</span>
                <div>
                  <h3 className={styles.processTitle}>{step.title}</h3>
                  <p className={styles.processText}>{step.text}</p>
                </div>
              </article>
            ))}
          </div>
        </section>

        <section className={styles.ctaSection}>
          <div className={styles.ctaBlock}>
            <p className={styles.ctaEyebrow}>Ready when you are</p>
            <h2 className={styles.ctaTitle}>Open the app and inspect the baskets directly.</h2>
            <Link href="/explore" className={styles.primaryLink}>
              Explore Bundls
            </Link>
          </div>
        </section>

        <footer className={styles.footer}>
          <div className={styles.footerInner}>
            <span className={styles.footerBrand}>© 2026 Bundl Protocol</span>
            <div className={styles.footerLinks}>
              <a href="#featured">Bundls</a>
              <a href="#process">Flow</a>
              <Link href="/explore">App</Link>
            </div>
          </div>
        </footer>
      </main>
    </>
  );
}
