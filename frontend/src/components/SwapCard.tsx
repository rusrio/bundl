"use client";

import { useState } from "react";
import styles from "./SwapCard.module.css";
import { useAccount } from 'wagmi';
import { useApproveToken, useSwapExactInput, useRedeemIndex, useSellIndex } from '@/hooks/useSwap';
import { USDC_ADDRESS, BUNDL_TOKEN_ADDRESS, V4_ROUTER_ADDRESS, BUNDL_ROUTER_ADDRESS, BUNDL_HOOK_ADDRESS } from '@/config/contracts';
import { useUsdcBalance, useIndexBalance, useTokenAllowance } from '@/hooks/useBundlToken';
import { parseUnits, formatUnits } from 'viem';
import { ConnectButton } from '@rainbow-me/rainbowkit';

type Tab = "buy" | "sell" | "redeem";

export default function SwapCard() {
  const [activeTab, setActiveTab] = useState<Tab>("buy");
  const [amount, setAmount] = useState("");
  const [isExecuting, setIsExecuting] = useState(false);

  const { isConnected } = useAccount();
  const { approve: approveUsdc, isPending: isApprovingUsdc } = useApproveToken(USDC_ADDRESS);
  const { approve: approveIndex, isPending: isApprovingIndex } = useApproveToken(BUNDL_TOKEN_ADDRESS);
  const { swap, isPending: isSwapping } = useSwapExactInput();
  const { sell, isPending: isSelling } = useSellIndex();
  const { redeem, isPending: isRedeeming } = useRedeemIndex();
  const { address } = useAccount();

  const { data: usdcBalanceData } = useUsdcBalance(address);
  const { data: indexBalanceData } = useIndexBalance(address);

  // Allowance checks
  const { data: usdcAllowance, refetch: refetchUsdcAllowance } = useTokenAllowance(USDC_ADDRESS, address, V4_ROUTER_ADDRESS);
  const { data: indexAllowance, refetch: refetchIndexAllowance } = useTokenAllowance(BUNDL_TOKEN_ADDRESS, address, BUNDL_ROUTER_ADDRESS);

  const displayUsdcBal = usdcBalanceData ? Number(formatUnits(usdcBalanceData as bigint, 6)).toFixed(2) : "0.00";
  const displayIndexBal = indexBalanceData ? Number(formatUnits(indexBalanceData as bigint, 18)).toFixed(2) : "0.00";

  const isPending = isApprovingUsdc || isApprovingIndex || isSwapping || isSelling || isRedeeming || isExecuting;

  const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));


  const getNeedsApproval = () => {
    if (!amount || Number(amount) <= 0) return false;
    if (activeTab === "buy") {
      const parsed = parseUnits(amount, 6);
      return (usdcAllowance ?? 0n) < parsed;
    }
    if (activeTab === "sell") {
      const parsed = parseUnits(amount, 18);
      return (indexAllowance ?? 0n) < parsed;
    }
    return false;
  };

  const needsApproval = getNeedsApproval();

  const handleAction = async () => {
    if (!amount || Number(amount) <= 0 || isExecuting) return;
    setIsExecuting(true);
    try {
      if (activeTab === "buy") {
        const usdcAmount = parseUnits(amount, 6);
        if (needsApproval) {
          await approveUsdc(usdcAmount);
          await sleep(500); // Wait for nonce/state sync
          await refetchUsdcAllowance();
        } else {
          await swap(usdcAmount);
        }
      } else if (activeTab === "sell") {
        const indexAmount = parseUnits(amount, 18);
        if (needsApproval) {
          await approveIndex(indexAmount, BUNDL_ROUTER_ADDRESS);
          await sleep(500); // Wait for nonce/state sync
          await refetchIndexAllowance();
        } else {
          await sell(BUNDL_TOKEN_ADDRESS, BUNDL_HOOK_ADDRESS, indexAmount, 0n);
        }

      } else if (activeTab === "redeem") {
        const units = parseUnits(amount, 18);
        await redeem(units);
      }
    } catch (error) {
      console.error("Action failed:", error);
    } finally {
      setIsExecuting(false);
    }
  };


  const getButtonText = () => {
    if (isPending) return "Processing...";
    if (needsApproval) {
      return activeTab === "buy" ? "Approve USDC" : "Approve bBTC-ETH";
    }
    if (activeTab === "buy") return "Buy Index Token";
    if (activeTab === "sell") return "Sell Index Token";
    return "Redeem for Assets";
  };


  return (
    <section id="swap" className={styles.section}>
      <div className={styles.container}>
        <div className={styles.cardWrapper}>
          <div className={styles.cardGlow} />

          <div className={styles.card}>
            {/* Tabs */}
            <div className={styles.tabs}>
              {(["buy", "sell", "redeem"] as Tab[]).map((tab) => (
                <button
                  key={tab}
                  className={`${styles.tab} ${activeTab === tab ? styles.tabActive : ""}`}
                  onClick={() => {
                    setActiveTab(tab);
                    setAmount("");
                  }}
                >
                  {tab.charAt(0).toUpperCase() + tab.slice(1)}
                </button>
              ))}
              <div
                className={styles.tabIndicator}
                style={{
                  transform: `translateX(${activeTab === "buy" ? 0 : activeTab === "sell" ? 100 : 200}%)`,
                }}
              />
            </div>

            {/* Input Section */}
            <div className={styles.inputSection}>
              <div className={styles.inputHeader}>
                <span className={styles.inputLabel}>
                  {activeTab === "buy"
                    ? "You pay"
                    : activeTab === "sell"
                      ? "You sell"
                      : "Units to redeem"}
                </span>
                <span className={styles.inputBalance}>
                  Balance: {activeTab === "buy" ? displayUsdcBal : displayIndexBal}
                </span>
              </div>
              <div className={styles.inputRow}>
                <input
                  type="text"
                  className={styles.input}
                  placeholder="0.00"
                  value={amount}
                  disabled={!isConnected || isPending}
                  onChange={(e) => {
                    const v = e.target.value;
                    if (/^[0-9]*\.?[0-9]*$/.test(v)) setAmount(v);
                  }}
                />
                <button className={styles.tokenSelect}>
                  <div
                    className={styles.tokenIcon}
                    style={{
                      background:
                        activeTab === "buy" ? "#2775ca" : "#f59e0b",
                    }}
                  />
                  <span>
                    {activeTab === "buy"
                      ? "USDC"
                      : activeTab === "sell"
                        ? "bBTC-ETH"
                        : "Units"}
                  </span>
                </button>
              </div>
            </div>

            {/* Arrow */}
            <div className={styles.arrowContainer}>
              <div className={styles.arrow}>
                <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                  <path
                    d="M8 3V13M8 13L4 9M8 13L12 9"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </div>
            </div>

            {/* Output Section */}
            <div className={styles.outputSection}>
              <div className={styles.inputHeader}>
                <span className={styles.inputLabel}>You receive</span>
              </div>
              <div className={styles.inputRow}>
                <input
                  type="text"
                  className={styles.input}
                  placeholder="0.00"
                  readOnly
                  value=""
                />
                <button className={styles.tokenSelect}>
                  <div
                    className={styles.tokenIcon}
                    style={{
                      background:
                        activeTab === "buy"
                          ? "#f59e0b"
                          : activeTab === "sell"
                            ? "#2775ca"
                            : "#627eea",
                    }}
                  />
                  <span>
                    {activeTab === "buy"
                      ? "bBTC-ETH"
                      : activeTab === "sell"
                        ? "USDC"
                        : "WBTC + WETH"}
                  </span>
                </button>
              </div>

              {activeTab === "redeem" && (
                <div className={styles.redeemBreakdown}>
                  <div className={styles.redeemRow}>
                    <span>WBTC</span>
                    <span>0.00</span>
                  </div>
                  <div className={styles.redeemRow}>
                    <span>WETH</span>
                    <span>0.00</span>
                  </div>
                </div>
              )}
            </div>

            {/* Details */}
            <div className={styles.details}>
              <div className={styles.detailRow}>
                <span>Rate</span>
                <span>1 bBTC-ETH = $0.00</span>
              </div>
              <div className={styles.detailRow}>
                <span>Price Impact</span>
                <span className={styles.detailGreen}>&lt; 0.01%</span>
              </div>
            </div>

            {/* Action Button */}
            {!isConnected ? (
              <div style={{ display: 'flex', justifyContent: 'center', marginTop: '1rem' }}>
                <ConnectButton />
              </div>
            ) : (
              <button
                className={styles.actionBtn}
                onClick={handleAction}
                disabled={isPending || !amount || Number(amount) <= 0}
              >
                {getButtonText()}
              </button>
            )}
          </div>
        </div>
      </div>
    </section>
  );
}
