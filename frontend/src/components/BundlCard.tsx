import styles from "./BundlCard.module.css";
import Link from "next/link";

export interface BundlCardData {
  id: string;
  name: string;
  category: string;
  strategy: string;
  curator: string;
  tokenCount: number;
  aum: string;
  rebalancing: string;
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
  const chartId = `bundl-chart-${data.id.replace(/[^a-zA-Z0-9_-]/g, "")}`;
  const chartHeight = 84;
  const chartWidth = 100;
  const pointStep =
    data.chartBars.length > 1 ? chartWidth / (data.chartBars.length - 1) : chartWidth;
  const points = data.chartBars.map((value, index) => {
    const x = index * pointStep;
    const y = chartHeight - (Math.max(0, Math.min(100, value)) / 100) * chartHeight;

    return { x, y };
  });
  const polylinePoints = points.map(({ x, y }) => `${x},${y}`).join(" ");
  const areaPath = points.length
    ? `M 0 ${chartHeight} L ${points
        .map(({ x, y }) => `${x} ${y}`)
        .join(" L ")} L ${chartWidth} ${chartHeight} Z`
    : "";
  const lastPoint = points[points.length - 1];

  return (
    <Link href={`/bundl/${data.id}`} className={styles.card}>

      <div className={styles.header}>
        <div>
          <h3 className={styles.name}>{data.name}</h3>
          <p className={styles.strategy}>{data.strategy}</p>
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

      <div className={styles.metrics}>
        <div className={styles.metric}>
          <span className={styles.metricLabel}>AUM</span>
          <strong className={styles.metricValue}>{data.aum}</strong>
        </div>
      </div>

      <div className={styles.chart}>
        <div className={styles.chartGrid} aria-hidden="true">
          {[0, 1, 2, 3].map((line) => (
            <span key={line} className={styles.chartGridLine} />
          ))}
        </div>
        <svg
          className={styles.chartSvg}
          viewBox={`0 0 ${chartWidth} ${chartHeight}`}
          preserveAspectRatio="none"
          aria-hidden="true"
        >
          <defs>
            <linearGradient id={`${chartId}-fill`} x1="0" y1="0" x2="0" y2="1">
              <stop
                offset="0%"
                stopColor={`color-mix(in srgb, ${barColor} 38%, transparent)`}
              />
              <stop
                offset="100%"
                stopColor={`color-mix(in srgb, ${barColor} 4%, transparent)`}
              />
            </linearGradient>
          </defs>

          {areaPath ? (
            <>
              <path d={areaPath} fill={`url(#${chartId}-fill)`} />
              <polyline
                className={styles.chartLine}
                points={polylinePoints}
                style={{ stroke: barColor }}
              />
              {points.map(({ x, y }, index) => (
                <circle
                  key={index}
                  cx={x}
                  cy={y}
                  r={index === points.length - 1 ? 3.2 : 1.8}
                  className={index === points.length - 1 ? styles.chartPointActive : styles.chartPoint}
                  style={{ color: barColor }}
                />
              ))}
            </>
          ) : null}
        </svg>
        {lastPoint ? (
          <div className={styles.chartBadge} style={{ color: barColor }}>
            <span className={styles.chartBadgeDot} />
            7D
          </div>
        ) : null}
      </div>

      <div className={styles.footer}>

        <span className={styles.viewBtn}>View Details</span>
      </div>
    </Link>
  );
}
