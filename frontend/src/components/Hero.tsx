"use client";

import styles from "./Hero.module.css";

export default function Hero() {
  return (
    <section className={styles.hero}>
      {/* Animated background */}
      <div className={styles.bgGrid} />
      <div className={styles.bgGlow1} />
      <div className={styles.bgGlow2} />
      <div className={styles.grain} />

      <div className={styles.content}>
        <div className={styles.badge}>
          <span className={styles.badgeDot} />
          Powered by Uniswap v4 Hooks
        </div>

        <h1 className={styles.title}>
          <span>Forge Your</span>
          <span className="text-gradient"> Index Token</span>
        </h1>

        <p className={styles.subtitle}>
          Bundle multiple crypto assets into a single token. Buy, sell, and
          redeem at NAV price — all on-chain through Uniswap v4&apos;s hook
          system.
        </p>

        <div className={styles.stats}>
          <div className={styles.stat}>
            <span className={styles.statValue}>$0.00</span>
            <span className={styles.statLabel}>Total Value Locked</span>
          </div>
          <div className={styles.statDivider} />
          <div className={styles.stat}>
            <span className={styles.statValue}>$0.00</span>
            <span className={styles.statLabel}>NAV / Unit</span>
          </div>
          <div className={styles.statDivider} />
          <div className={styles.stat}>
            <span className={styles.statValue}>2</span>
            <span className={styles.statLabel}>Underlying Assets</span>
          </div>
        </div>

        <div className={styles.actions}>
          <button
            className={styles.ctaPrimary}
            onClick={() => {
              const el = document.getElementById("swap");
              el?.scrollIntoView({ behavior: "smooth" });
            }}
          >
            Start Trading
            <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
              <path
                d="M6 12L10 8L6 4"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
          </button>
          <button
            className={styles.ctaSecondary}
            onClick={() => {
              const el = document.getElementById("dashboard");
              el?.scrollIntoView({ behavior: "smooth" });
            }}
          >
            View Dashboard
          </button>
        </div>
      </div>

      {/* Scroll indicator */}
      <div className={styles.scrollIndicator}>
        <span>Scroll to explore</span>
        <div className={styles.scrollLine}>
          <div className={styles.scrollDot} />
        </div>
      </div>
    </section>
  );
}
