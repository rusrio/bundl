"use client";

import styles from "./Dashboard.module.css";
import {
  useUnderlyingTokens,
  useAmountsPerUnit,
  useTotalBacking,
  usePoolStates,
  useNavPerUnit,
  useUsdcIs0,
} from '@/hooks/useBundlHook';
import { useIndexTotalSupply } from '@/hooks/useBundlToken';
import { formatUnits } from 'viem';

const TOKEN_META: Record<number, { symbol: string; name: string; color: string; decimals: number }> = {
  0: { symbol: "WBTC", name: "Wrapped Bitcoin", color: "#f7931a", decimals: 8 },
  1: { symbol: "WETH", name: "Wrapped Ether", color: "#627eea", decimals: 18 },
};

/**
 * Convert sqrtPriceX96 → human-readable spot price of the underlying token in USDC.
 *
 * sqrtPriceX96 = sqrt(currency1 / currency0) * 2^96  (wei/wei ratio)
 *
 * usdcIs0 = true  (c0=USDC 6dec, c1=token):
 *   rawRatio = tokenWei / usdcWei
 *   price    = (1 / rawRatio) * 10^(tokenDec - usdcDec)
 *
 * usdcIs0 = false (c0=token, c1=USDC 6dec):
 *   rawRatio = usdcWei / tokenWei
 *   price    = rawRatio * 10^(tokenDec - usdcDec)
 */
function sqrtPriceToUsdcPrice(
  sqrtPriceX96: bigint,
  usdcIs0: boolean,
  usdcDecimals = 6,
  tokenDecimals = 18
): number {
  const sqrtPrice = Number(sqrtPriceX96) / 2 ** 96;
  const rawRatio = sqrtPrice * sqrtPrice;
  const decimalAdj = 10 ** (tokenDecimals - usdcDecimals);

  if (usdcIs0) {
    return rawRatio > 0 ? decimalAdj / rawRatio : 0;
  } else {
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
  const { data: usdcIs0Data } = useUsdcIs0();

  const isLive = underlyingAddrs && amountsPerUnit && totalBacking;
  const numAssets = isLive ? (underlyingAddrs as string[]).length : 2;
  const allocationPct = numAssets > 0 ? Math.floor(100 / numAssets) : 50;

  // NAV per unit: contract returns value scaled to usdcDecimals (6)
  const navPerUnit = navRaw ? Number(formatUnits(navRaw as bigint, 6)) : 0;
  const navDisplay = navPerUnit > 0 ? navPerUnit.toFixed(2) : "—";

  // Total index supply (18 decimals)
  const supply = totalSupply ? Number(formatUnits(totalSupply as bigint, 18)) : 0;

  const sqrtPrices: bigint[] = poolStates ? (poolStates as any)[0] : [];
  const ticks: number[] = poolStates ? (poolStates as any)[1] : [];
  const liquidities: bigint[] = poolStates ? (poolStates as any)[2] : [];
  const usdcIs0Arr: boolean[] = usdcIs0Data ? (usdcIs0Data as boolean[]) : [];

  let calcTotalBackingUsd = 0;

  const displayTokens = isLive
    ? (underlyingAddrs as string[]).map((_addr: string, i: number) => {
        const meta = TOKEN_META[i] || {
          symbol: `Asset ${i + 1}`,
          name: _addr.slice(0, 6) + '...' + _addr.slice(-4),
          color: '#888',
          decimals: 18,
        };

        // Use the authoritative usdcIs0 value from the contract
        const usdcIs0 = usdcIs0Arr[i] ?? false;
        const spotPrice =
          sqrtPrices[i] != null
            ? sqrtPriceToUsdcPrice(sqrtPrices[i], usdcIs0, 6, meta.decimals)
            : 0;

        const backingAmount = Number(
          formatUnits((totalBacking as bigint[])[i], meta.decimals)
        );
        calcTotalBackingUsd += backingAmount * spotPrice;

        return {
          ...meta,
          allocation: allocationPct,
          backing: backingAmount.toFixed(6),
          perUnit: Number(
            formatUnits((amountsPerUnit as bigint[])[i], meta.decimals)
          ).toFixed(6),
          spotPrice: spotPrice > 0 ? spotPrice.toFixed(2) : '—',
          tick: ticks[i] ?? '—',
          liquidity: liquidities[i] ? liquidities[i].toString() : '—',
        };
      })
    : [
        {
          symbol: 'WBTC', name: 'Wrapped Bitcoin', color: '#f7931a',
          allocation: 50, backing: '0.000000', perUnit: '0.000588', spotPrice: '—', tick: '—', liquidity: '—',
        },
        {
          symbol: 'WETH', name: 'Wrapped Ether', color: '#627eea',
          allocation: 50, backing: '0.000000', perUnit: '0.025000', spotPrice: '—', tick: '—', liquidity: '—',
        },
      ];

  return (
    <section id="dashboard" className={styles.section}>
      <div className={styles.container}>
        <div className={styles.header}>
          <span className={styles.label}>Dashboard</span>
          <h2 className={styles.title}>Index Composition</h2>
          <p className={styles.subtitle}>
            Real-time view of the vault&apos;s underlying asset allocation and backing.
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
                  style={{ width: `${token.allocation}%`, background: token.color }}
                />
              ))}
            </div>

            <div className={styles.tokenList}>
              {displayTokens.map((token: any, i: number) => (
                <div key={i} className={styles.tokenRow}>
                  <div className={styles.tokenInfo}>
                    <div className={styles.tokenDot} style={{ background: token.color }} />
                    <div>
                      <span className={styles.tokenSymbol}>{token.symbol}</span>
                      <span className={styles.tokenName}>{token.name}</span>
                    </div>
                  </div>
                  <div className={styles.tokenData}>
                    <span className={styles.tokenAllocation}>${token.spotPrice}</span>
                    <span className={styles.tokenPerUnit}>{token.perUnit} / unit</span>
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
              Calculated from spot prices of underlying assets on Uniswap v4 pools.
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
                    <div className={styles.tokenDot} style={{ background: token.color }} />
                    <span>{token.symbol}</span>
                  </div>
                  <span className={styles.backingAmount}>{token.backing}</span>
                </div>
              ))}
            </div>
            <div className={styles.backingTotal}>
              <span>Total (USDC equivalent)</span>
              <span className={styles.backingTotalValue}>
                ${calcTotalBackingUsd > 0 ? calcTotalBackingUsd.toFixed(2) : '0.00'}
              </span>
            </div>
          </div>

          {/* ── Supply Card ── */}
          <div className={styles.card}>
            <div className={styles.cardHeader}>
              <h3 className={styles.cardTitle}>Index Token Supply</h3>
            </div>
            <div className={styles.navValue}>
              <span className={styles.navAmount}>
                {supply > 0 ? supply.toFixed(4) : '0.0000'}
              </span>
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
