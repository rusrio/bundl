"use client";

import styles from "./Dashboard.module.css";
import { useUnderlyingTokens, useAmountsPerUnit, useTotalBacking, usePoolStates, useNavPerUnit } from '@/hooks/useBundlHook';
import { useIndexTotalSupply } from '@/hooks/useBundlToken';
import { formatUnits } from 'viem';

const TOKEN_META: Record<number, { symbol: string; name: string; color: string; decimals: number }> = {
  0: { symbol: "WBTC", name: "Wrapped Bitcoin", color: "#f7931a", decimals: 8 },
  1: { symbol: "WETH", name: "Wrapped Ether", color: "#627eea", decimals: 18 },
};

/**
 * Convert sqrtPriceX96 → spot price of the underlying token in USDC.
 *
 * Uniswap v4 sqrtPriceX96 encodes:  sqrt( currency1 / currency0 ) * 2^96
 *
 * Two pool layouts are possible:
 *   usdcIs0 = true  → currency0 = USDC (6 dec), currency1 = token
 *     raw ratio = token_wei / usdc_wei
 *     price_usdc_per_token = 1 / raw_ratio  * 10^(tokenDecimals - usdcDecimals)
 *
 *   usdcIs0 = false → currency0 = token, currency1 = USDC (6 dec)
 *     raw ratio = usdc_wei / token_wei
 *     price_usdc_per_token = raw_ratio * 10^(tokenDecimals - usdcDecimals)
 */
function sqrtPriceToUsdcPrice(
  sqrtPriceX96: bigint,
  usdcIs0: boolean,
  usdcDecimals = 6,
  tokenDecimals = 18
): number {
  const sqrtPrice = Number(sqrtPriceX96) / 2 ** 96;
  const rawRatio = sqrtPrice * sqrtPrice; // currency1 / currency0 in raw (wei) units
  const decimalAdj = 10 ** (tokenDecimals - usdcDecimals);

  if (usdcIs0) {
    // rawRatio = tokenWei / usdcWei  →  price = usdcWei/tokenWei = 1/rawRatio
    // then adjust decimals: usdcPerToken = (1/rawRatio) * 10^(tokenDec - usdcDec)
    return rawRatio > 0 ? decimalAdj / rawRatio : 0;
  } else {
    // rawRatio = usdcWei / tokenWei  →  price = rawRatio * 10^(tokenDec - usdcDec)
    return rawRatio * decimalAdj;
  }
}

export default function Dashboard() {
  const { data: underlyingAddrs } = useUnderlyingTokens();
  const { data: amountsPerUnit } = useAmountsPerUnit();
  const { data: totalBacking } = useTotalBacking();
  const { data: totalSupply } = useIndexTotalSupply();
  const { data: poolStates } = usePoolStates();
  const { data: navRaw } = useNavPerUnit();

  const isLive = underlyingAddrs && amountsPerUnit && totalBacking;
  const numAssets = isLive ? (underlyingAddrs as string[]).length : 2;
  const allocationPct = numAssets > 0 ? Math.floor(100 / numAssets) : 50;

  // NAV per unit: getNavPerUnit() returns a value already scaled to usdcDecimals (6)
  const navPerUnit = navRaw ? Number(formatUnits(navRaw as bigint, 6)) : 0;
  const navDisplay = navPerUnit > 0 ? navPerUnit.toFixed(2) : "—";

  // Total supply (18 decimals)
  const supply = totalSupply ? Number(formatUnits(totalSupply as bigint, 18)) : 0;

  // Pool states
  const sqrtPrices: bigint[] = poolStates ? (poolStates as any)[0] : [];
  const ticks: number[] = poolStates ? (poolStates as any)[1] : [];
  const liquidities: bigint[] = poolStates ? (poolStates as any)[2] : [];

  let calcTotalBackingUsd = 0;

  const displayTokens = isLive
    ? (underlyingAddrs as string[]).map((_addr: string, i: number) => {
        const meta = TOKEN_META[i] || {
          symbol: `Asset ${i + 1}`,
          name: _addr.slice(0, 6) + "..." + _addr.slice(-4),
          color: "#888",
          decimals: 18,
        };

        // Determine pool orientation: compare addresses lexicographically as the hook does
        // usdcIs0 = usdc address < token address (same _sortCurrencies logic as deploy)
        // We can't know usdc address here without context, so we derive it from sqrtPrice magnitude:
        // For WBTC (dec=8): if usdcIs0, price ~$85k → rawRatio ~1/850, decimalAdj=100 → ~0.12 (wrong)
        //                   if !usdcIs0, price ~$85k → rawRatio*100 ~85k (correct)
        // Since we store usdcIs0 per-pool in the hook but don't expose it as a view,
        // we infer it: if the naive !usdcIs0 formula gives a plausible price (>100 for BTC), use it.
        const naiveUsdcIs1 = sqrtPrices[i]
          ? sqrtPriceToUsdcPrice(sqrtPrices[i], false, 6, meta.decimals)
          : 0;
        const naiveUsdcIs0 = sqrtPrices[i]
          ? sqrtPriceToUsdcPrice(sqrtPrices[i], true, 6, meta.decimals)
          : 0;

        // Heuristic: pick whichever gives a price > 1 USDC (both assets are worth >>$1)
        // and is the larger value (avoids picking the inverted near-zero result)
        const spotPrice = naiveUsdcIs1 > naiveUsdcIs0 ? naiveUsdcIs1 : naiveUsdcIs0;

        const backingAmount = Number(formatUnits((totalBacking as bigint[])[i], meta.decimals));
        calcTotalBackingUsd += backingAmount * spotPrice;

        return {
          ...meta,
          allocation: allocationPct,
          backing: backingAmount.toFixed(6),
          perUnit: Number(formatUnits((amountsPerUnit as bigint[])[i], meta.decimals)).toFixed(6),
          spotPrice: spotPrice > 0 ? spotPrice.toFixed(2) : "—",
          tick: ticks[i] ?? "—",
          liquidity: liquidities[i] ? liquidities[i].toString() : "—",
        };
      })
    : [
        { symbol: "WBTC", name: "Wrapped Bitcoin", color: "#f7931a", allocation: 50, backing: "0.000000", perUnit: "0.001000", spotPrice: "—", tick: "—", liquidity: "—" },
        { symbol: "WETH", name: "Wrapped Ether", color: "#627eea", allocation: 50, backing: "0.000000", perUnit: "0.010000", spotPrice: "—", tick: "—", liquidity: "—" },
      ];

  return (
    <section id="dashboard" className={styles.section}>
      <div className={styles.container}>
        <div className={styles.header}>
          <span className={styles.label}>Dashboard</span>
          <h2 className={styles.title}>Index Composition</h2>
          <p className={styles.subtitle}>
            Real-time view of the vault&apos;s underlying asset allocation and
            backing.
          </p>
        </div>

        <div className={styles.grid}>
          {/* ── Composition Card ── */}
          <div className={`${styles.card} ${styles.cardWide}`}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Basket Composition</h3>
              <span className={styles.cardBadge}>{numAssets} Assets</span>
            </div>

            <div className={styles.allocationBar}>
              {displayTokens.map((token: any, i: number) => (
                <div
                  key={i}
                  className={styles.allocationSegment}
                  style={{
                    width: `${token.allocation}%`,
                    background: token.color,
                  }}
                />
              ))}
            </div>

            <div className={styles.tokenList}>
              {displayTokens.map((token: any, i: number) => (
                <div key={i} className={styles.tokenRow}>
                  <div className={styles.tokenInfo}>
                    <div
                      className={styles.tokenDot}
                      style={{ background: token.color }}
                    />
                    <div>
                      <span className={styles.tokenSymbol}>{token.symbol}</span>
                      <span className={styles.tokenName}>{token.name}</span>
                    </div>
                  </div>
                  <div className={styles.tokenData}>
                    <span className={styles.tokenAllocation}>
                      ${token.spotPrice}
                    </span>
                    <span className={styles.tokenPerUnit}>
                      {token.perUnit} / unit
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* ── NAV Card ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>NAV per Unit</h3>
              <span className={styles.liveDot} />
            </div>
            <div className={styles.navValue}>
              <span className={styles.navAmount}>${navDisplay}</span>
              <span className={styles.navChange}>
                <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
                  <path d="M6 2L10 8H2L6 2Z" fill="#22c55e" />
                </svg>
                Live
              </span>
            </div>
            <p className={styles.navDescription}>
              Calculated from spot prices of underlying assets on Uniswap v4
              pools.
            </p>
          </div>

          {/* ── Total Backing Card ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Total Backing</h3>
            </div>
            <div className={styles.backingList}>
              {displayTokens.map((token: any, i: number) => (
                <div key={i} className={styles.backingRow}>
                  <div className={styles.backingToken}>
                    <div
                      className={styles.tokenDot}
                      style={{ background: token.color }}
                    />
                    <span>{token.symbol}</span>
                  </div>
                  <span className={styles.backingAmount}>{token.backing}</span>
                </div>
              ))}
            </div>
            <div className={styles.backingTotal}>
              <span>Total (USDC equivalent)</span>
              <span className={styles.backingTotalValue}>
                ${calcTotalBackingUsd > 0 ? calcTotalBackingUsd.toFixed(2) : "0.00"}
              </span>
            </div>
          </div>

          {/* ── Supply Card ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Index Token Supply</h3>
            </div>
            <div className={styles.navValue}>
              <span className={styles.navAmount}>{supply > 0 ? supply.toFixed(4) : "0.0000"}</span>
            </div>
            <p className={styles.navDescription}>
              Total units of the index token currently in circulation.
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
