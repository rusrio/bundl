import styles from "./BundlCard.module.css";
import Link from "next/link";

export interface BundlCardData {
  id: string;
  name: string;
  tokenCount: number;
  performance7d: number;
  riskLevel: 1 | 2 | 3;
  chartBars: number[];
}

const RISK_COLORS: Record<number, string> = {
  1: "#22c55e",
  2: "#eab308",
  3: "#ef4444",
};

function getRiskColor(level: number, bar: number): string {
  if (bar <= level) return RISK_COLORS[level] || "#22c55e";
  return "var(--bg-tertiary)";
}

export default function BundlCard({ data }: { data: BundlCardData }) {
  const isNegative = data.performance7d < 0;
  const barColor = isNegative ? "var(--error)" : "var(--accent-primary)";

  return (
    <Link href={`/bundl/${data.id}`} className={styles.card}>
      {/* Header */}
      <div className={styles.header}>
        <div>
          <h3 className={styles.name}>{data.name}</h3>
          <div className={styles.tokens}>
            <div className={styles.tokenAvatars}>
              {[0, 1, 2].map((i) => (
                <div
                  key={i}
                  className={styles.tokenDot}
                  style={{
                    background: `hsl(${30 + i * 40}, 70%, ${50 + i * 5}%)`,
                    zIndex: 3 - i,
                  }}
                />
              ))}
            </div>
            <span className={styles.tokenMore}>
              +{data.tokenCount} more
            </span>
          </div>
        </div>
        <div className={styles.perf}>
          <span
            className={styles.perfValue}
            style={{ color: isNegative ? "var(--error)" : "#22c55e" }}
          >
            {isNegative ? "" : "+"}
            {data.performance7d}%
          </span>
          <span className={styles.perfLabel}>7D PERFORMANCE</span>
        </div>
      </div>

      {/* Mini Bar Chart */}
      <div className={styles.chart}>
        {data.chartBars.map((h, i) => (
          <div
            key={i}
            className={styles.bar}
            style={{
              height: `${h}%`,
              background:
                i < data.chartBars.length - 2
                  ? `color-mix(in srgb, ${barColor} 25%, transparent)`
                  : i < data.chartBars.length - 1
                    ? `color-mix(in srgb, ${barColor} 45%, transparent)`
                    : `color-mix(in srgb, ${barColor} 65%, transparent)`,
            }}
          />
        ))}
      </div>

      {/* Footer */}
      <div className={styles.footer}>
        <div className={styles.risk}>
          <span className={styles.riskLabel}>RISK LEVEL</span>
          <div className={styles.riskBars}>
            {[1, 2, 3].map((bar) => (
              <div
                key={bar}
                className={styles.riskBar}
                style={{ background: getRiskColor(data.riskLevel, bar) }}
              />
            ))}
          </div>
        </div>
        <span className={styles.viewBtn}>View Details</span>
      </div>
    </Link>
  );
}
