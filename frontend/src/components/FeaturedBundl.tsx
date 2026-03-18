import styles from "./FeaturedBundl.module.css";

export default function FeaturedBundl() {
  return (
    <section className={styles.section}>
      <div className={styles.card}>
        <div className={styles.overlay} />
        <div className={styles.bgImage} />
        <div className={styles.orb} />

        <div className={styles.content}>
          <div className={styles.copy}>
            <span className={styles.badge}>Featured thesis</span>
            <h2 className={styles.title}>Metaverse Index</h2>
            <p className={styles.description}>
              A tighter basket of gaming, creator-economy, and virtual world assets with for medium-conviction growth exposure.
            </p>
            <div className={styles.actions}>
              <button className={styles.btnPrimary}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                  <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" strokeLinecap="round" strokeLinejoin="round"/>
                  <polyline points="17 6 23 6 23 12" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
                Open thesis
              </button>
              <button className={styles.btnSecondary}>See constituents</button>
            </div>
          </div>

          <div className={styles.statsCard}>
            <span className={styles.statsLabel}>Portfolio snapshot</span>
            <div className={styles.statsGrid}>
              <div>
                <strong>$12.4M</strong>
                <span>Total TVL</span>
              </div>
              <div>
                <strong>+14.8%</strong>
                <span>30D performance</span>
              </div>
              <div>
                <strong>9 assets</strong>
                <span>Core positions</span>
              </div>
            </div>
            <p className={styles.statsNote}>
              .
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
