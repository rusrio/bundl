import ForgeCanvas from "@/components/ForgeCanvas";
import Navbar from "@/components/Navbar";
import styles from "./page.module.css";
import Link from "next/link";

export default function LandingPage() {
  return (
    <>
      <ForgeCanvas />
      <Navbar />

      <main className={styles.main}>
        {/* ═══ Section 1: Hero ═══ */}
        <section className={styles.hero}>
          <div className={styles.heroContent}>
            <span className={styles.heroBadge}>
              <span className={styles.heroBadgeDot} />
              Built on Uniswap v4
            </span>
            <h1 className={styles.heroTitle}>
              Forge Your
              <br />
              <span className={styles.heroAccent}>Index Token</span>
            </h1>
            <p className={styles.heroSub}>
              Bundle multiple crypto assets into one token. Trade at NAV price.
              Redeem for underlying assets. All on-chain.
            </p>
            <div className={styles.heroActions}>
              <Link href="/explore" className={styles.btnPrimary}>
                Explore Bundls
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <path d="M5 12h14M12 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </Link>
              <a href="#how-it-works" className={styles.btnGhost}>
                How It Works
              </a>
            </div>
          </div>
          <div className={styles.scrollHint}>
            <span>Scroll to forge</span>
            <div className={styles.scrollBar}>
              <div className={styles.scrollDot} />
            </div>
          </div>
        </section>

        {/* ═══ Section 2: Stats ═══ */}
        <section className={styles.statsSection}>
          <div className={styles.statsGrid}>
            <div className={styles.statCard}>
              <span className={styles.statNumber}>$0</span>
              <span className={styles.statLabel}>Total Value Locked</span>
            </div>
            <div className={styles.statCard}>
              <span className={styles.statNumber}>6</span>
              <span className={styles.statLabel}>Index Bundls</span>
            </div>
            <div className={styles.statCard}>
              <span className={styles.statNumber}>50+</span>
              <span className={styles.statLabel}>Underlying Tokens</span>
            </div>
            <div className={styles.statCard}>
              <span className={styles.statNumber}>0%</span>
              <span className={styles.statLabel}>Management Fee</span>
            </div>
          </div>
        </section>

        {/* ═══ Section 3: How It Works ═══ */}
        <section id="how-it-works" className={styles.howSection}>
          <span className={styles.sectionLabel}>How It Works</span>
          <h2 className={styles.sectionTitle}>
            Three steps to a diversified portfolio
          </h2>

          <div className={styles.stepsGrid}>
            <div className={styles.step}>
              <div className={styles.stepIcon}>
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="11" cy="11" r="8"/>
                  <line x1="21" y1="21" x2="16.65" y2="16.65"/>
                </svg>
              </div>
              <h3 className={styles.stepTitle}>1. Explore</h3>
              <p className={styles.stepText}>
                Browse curated index bundls — from Blue Chip DeFi to AI & Big
                Data. Compare performance and risk levels.
              </p>
            </div>

            <div className={styles.stepArrow}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M5 12h14M12 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </div>

            <div className={styles.step}>
              <div className={styles.stepIcon}>
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" strokeLinecap="round" strokeLinejoin="round"/>
                  <polyline points="17 6 23 6 23 12" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
              </div>
              <h3 className={styles.stepTitle}>2. Invest</h3>
              <p className={styles.stepText}>
                Buy index tokens with USDC. The smart contract automatically
                acquires all underlying assets at NAV price.
              </p>
            </div>

            <div className={styles.stepArrow}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path d="M5 12h14M12 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </div>

            <div className={styles.step}>
              <div className={styles.stepIcon}>
                <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <rect x="2" y="2" width="8" height="8" rx="2"/>
                  <rect x="14" y="2" width="8" height="8" rx="2"/>
                  <rect x="2" y="14" width="8" height="8" rx="2"/>
                  <rect x="14" y="14" width="8" height="8" rx="2"/>
                </svg>
              </div>
              <h3 className={styles.stepTitle}>3. Redeem</h3>
              <p className={styles.stepText}>
                Burn your index tokens anytime to claim the underlying assets
                directly. No restrictions, no lock-ups.
              </p>
            </div>
          </div>
        </section>

        {/* ═══ Section 4: CTA ═══ */}
        <section className={styles.ctaSection}>
          <div className={styles.ctaCard}>
            <h2 className={styles.ctaTitle}>
              Ready to forge your portfolio?
            </h2>
            <p className={styles.ctaSub}>
              Start with as little as $1. Diversify across the best crypto
              assets in one transaction.
            </p>
            <Link href="/explore" className={styles.ctaBtn}>
              Launch App
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <path d="M5 12h14M12 5l7 7-7 7" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            </Link>
          </div>
        </section>

        {/* ═══ Footer ═══ */}
        <footer className={styles.footer}>
          <div className={styles.footerInner}>
            <span className={styles.footerBrand}>
              © 2026 Bundl Protocol
            </span>
            <div className={styles.footerLinks}>
              <a href="#">Docs</a>
              <a href="#">GitHub</a>
              <a href="#">Security</a>
            </div>
          </div>
        </footer>
      </main>
    </>
  );
}
