"use client";

import { useState } from "react";
import styles from "./SearchFilter.module.css";

const CATEGORIES = [
  { id: "all", label: "All strategies" },
  { id: "high-yield", label: "Yield focused" },
  { id: "low-risk", label: "Defensive" },
  { id: "trending", label: "Momentum" },
];

export default function SearchFilter() {
  const [active, setActive] = useState("all");
  const [search, setSearch] = useState("");

  return (
    <section className={styles.section}>
      <div className={styles.searchPanel}>
        <div className={styles.searchMeta}>
          <span className={styles.eyebrow}>Discovery</span>
          <h2 className={styles.title}>Explore indices with a clearer point of view</h2>
          <p className={styles.description}>
            Compare curated bundles by theme, volatility profile, and rebalancing cadence.
          </p>
        </div>

        <div className={styles.searchBox}>
          <svg className={styles.searchIcon} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <circle cx="11" cy="11" r="8" />
            <line x1="21" y1="21" x2="16.65" y2="16.65" />
          </svg>
          <input
            className={styles.searchInput}
            type="text"
            placeholder="Search by thesis, sector, or token exposure"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className={styles.filterPanel}>
        <div className={styles.filterHeader}>
          <span className={styles.filterLabel}>Filter by style</span>
        </div>
        <div className={styles.chips}>
          {CATEGORIES.map((cat) => (
            <button
              key={cat.id}
              className={`${styles.chip} ${active === cat.id ? styles.chipActive : ""}`}
              onClick={() => setActive(cat.id)}
            >
              {cat.label}
            </button>
          ))}
        </div>
      </div>
    </section>
  );
}
