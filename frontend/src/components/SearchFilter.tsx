"use client";

import { useState } from "react";
import styles from "./SearchFilter.module.css";

const CATEGORIES = [
  { id: "all", label: "All Categories", icon: null },
  { id: "high-yield", label: "High Yield", icon: "⚡" },
  { id: "low-risk", label: "Low Risk", icon: "🛡️" },
  { id: "trending", label: "Trending", icon: "📈" },
];

export default function SearchFilter() {
  const [active, setActive] = useState("all");
  const [search, setSearch] = useState("");

  return (
    <section className={styles.section}>
      <div className={styles.searchBox}>
        <svg className={styles.searchIcon} width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <circle cx="11" cy="11" r="8" />
          <line x1="21" y1="21" x2="16.65" y2="16.65" />
        </svg>
        <input
          className={styles.searchInput}
          type="text"
          placeholder="Search indices by name or theme (e.g. AI, DeFi, ESG)..."
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </div>
      <div className={styles.chips}>
        {CATEGORIES.map((cat) => (
          <button
            key={cat.id}
            className={`${styles.chip} ${active === cat.id ? styles.chipActive : ""}`}
            onClick={() => setActive(cat.id)}
          >
            {cat.icon && <span>{cat.icon}</span>}
            {cat.label}
          </button>
        ))}
      </div>
    </section>
  );
}
