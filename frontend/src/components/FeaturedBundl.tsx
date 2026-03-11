import styles from "./FeaturedBundl.module.css";

export default function FeaturedBundl() {
  return (
    <section className={styles.section}>
      <div className={styles.card}>
        <div className={styles.overlay} />
        <div className={styles.bgImage} />

        <div className={styles.content}>
          <span className={styles.badge}>FEATURED BUNDL</span>
          <h2 className={styles.title}>Metaverse Index</h2>
          <p className={styles.description}>
            A selection of the most promising virtual world and gaming tokens in
            one diversified portfolio.
          </p>
          <div className={styles.actions}>
            <button className={styles.btnPrimary}>
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
                <polyline points="23 6 13.5 15.5 8.5 10.5 1 18" strokeLinecap="round" strokeLinejoin="round"/>
                <polyline points="17 6 23 6 23 12" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
              Invest Now
            </button>
            <button className={styles.btnSecondary}>View Assets</button>
          </div>
        </div>
      </div>
    </section>
  );
}
