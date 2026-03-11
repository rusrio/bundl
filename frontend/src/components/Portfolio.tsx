"use client";

import styles from "./Portfolio.module.css";
import { useAccount } from 'wagmi';
import { useIndexBalance, useUsdcBalance } from '@/hooks/useBundlToken';
import { formatUnits } from 'viem';

export default function Portfolio() {
  const { address, isConnected } = useAccount();
  const { data: indexBalanceRaw } = useIndexBalance(address);
  const { data: usdcBalanceRaw } = useUsdcBalance(address);

  const indexBalance = indexBalanceRaw ? Number(formatUnits(indexBalanceRaw, 18)).toFixed(4) : "0.00";
  const usdcBalance = usdcBalanceRaw ? Number(formatUnits(usdcBalanceRaw as bigint, 6)).toFixed(2) : "0.00";
  // Assuming a static $10 NAV for demo purposes until price oracle is integrated
  const indexUsdValue = (Number(indexBalance) * 10).toFixed(2);
  return (
    <section id="portfolio" className={styles.section}>
      <div className={styles.container}>
        <div className={styles.header}>
          <span className={styles.label}>Portfolio</span>
          <h2 className={styles.title}>Your Holdings</h2>
        </div>

        <div className={styles.grid}>
          {/* ── Balance Card ── */}
          <div className={`${styles.card} ${styles.balanceCard}`}>
            <div className={styles.balanceIcon}>
              <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
                <rect x="4" y="4" width="10" height="10" rx="3" fill="#f59e0b" />
                <rect x="18" y="4" width="10" height="10" rx="3" fill="#ea580c" opacity="0.7" />
                <rect x="4" y="18" width="10" height="10" rx="3" fill="#ea580c" opacity="0.5" />
                <rect x="18" y="18" width="10" height="10" rx="3" fill="#f59e0b" opacity="0.8" />
              </svg>
            </div>
            <div>
              <span className={styles.balanceLabel}>Index Token Balance</span>
              <span className={styles.balanceValue}>{isConnected ? indexBalance : "0.00"} bBTC-ETH</span>
              <span className={styles.balanceUsd}>≈ ${isConnected ? indexUsdValue : "0.00"}</span>
            </div>
          </div>

          {/* ── USDC Balance ── */}
          <div className={styles.card}>
            <div
              className={styles.balanceIcon}
              style={{ background: "rgba(39, 117, 202, 0.15)" }}
            >
              <svg width="32" height="32" viewBox="0 0 32 32" fill="none">
                <circle cx="16" cy="16" r="12" stroke="#2775ca" strokeWidth="2" />
                <text
                  x="16"
                  y="20"
                  textAnchor="middle"
                  fill="#2775ca"
                  fontSize="12"
                  fontWeight="bold"
                >
                  $
                </text>
              </svg>
            </div>
            <div>
              <span className={styles.balanceLabel}>USDC Balance</span>
              <span className={styles.balanceValue}>{isConnected ? usdcBalance : "0.00"} USDC</span>
            </div>
          </div>

          {/* ── Underlying Value ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Underlying Exposure</h3>
            </div>
            <p className={styles.emptyText}>
              Connect your wallet to see your underlying asset exposure based on
              your index token holdings.
            </p>
          </div>

          {/* ── Activity ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Recent Activity</h3>
            </div>
            <div className={styles.emptyState}>
              <svg width="40" height="40" viewBox="0 0 40 40" fill="none">
                <circle
                  cx="20"
                  cy="20"
                  r="16"
                  stroke="var(--text-tertiary)"
                  strokeWidth="1.5"
                  strokeDasharray="4 4"
                />
                <path
                  d="M15 20H25M20 15V25"
                  stroke="var(--text-tertiary)"
                  strokeWidth="1.5"
                  strokeLinecap="round"
                />
              </svg>
              <span className={styles.emptyText}>
                No transactions yet. Buy or redeem index tokens to see your
                activity here.
              </span>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
