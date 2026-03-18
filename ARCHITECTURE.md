# Bundl — Smart Contract Architecture Analysis

> **Scope:** Foundry contracts under `foundry/src/`  
> **Stack:** Solidity 0.8.26 · Uniswap v4 · OpenZeppelin 5.x  
> **Contracts:** `BundlFactory` · `BundlHook` · `BundlToken` · `BundlRouter`

---

## Table of Contents

- [Bundl — Smart Contract Architecture Analysis](#bundl--smart-contract-architecture-analysis)
  - [Table of Contents](#table-of-contents)
  - [1. System Overview](#1-system-overview)
  - [2. Component Breakdown](#2-component-breakdown)
    - [2.1 BundlFactory](#21-bundlfactory)
      - [`createBundl(CreateBundlParams)`](#createbundlcreatebundlparams)
      - [`CreateBundlParams` struct](#createbundlparams-struct)
    - [2.2 BundlHook](#22-bundlhook)
      - [Hook Permissions](#hook-permissions)
      - [State Variables](#state-variables)
      - [Key Functions](#key-functions)
    - [2.3 BundlToken](#23-bundltoken)
    - [2.4 BundlRouter](#24-bundlrouter)
      - [`sellIndex(key, hookAddress, indexAmount, minUsdcOut)`](#sellindexkey-hookaddress-indexamount-minusdcout)
  - [3. Key Architectural Decisions](#3-key-architectural-decisions)
    - [3.1 NAV-Priced Market Maker via Hook](#31-nav-priced-market-maker-via-hook)
    - [3.2 CREATE2 Salt Mining for Hook Permissions](#32-create2-salt-mining-for-hook-permissions)
    - [3.3 Singleton PoolManager — Delta Accounting](#33-singleton-poolmanager--delta-accounting)
    - [3.4 Asymmetric Buy/Sell Architecture](#34-asymmetric-buysell-architecture)
    - [3.5 No External Liquidity — Direct Liquidity Guard](#35-no-external-liquidity--direct-liquidity-guard)
    - [3.6 Spot Price Oracle — No TWAP](#36-spot-price-oracle--no-twap)
    - [3.7 Permissionless Index Creation](#37-permissionless-index-creation)
  - [4. Data Flow](#4-data-flow)
    - [4.1 BUY — USDC → IndexToken](#41-buy--usdc--indextoken)
    - [4.2 SELL — IndexToken → USDC](#42-sell--indextoken--usdc)
    - [4.3 REDEEM — IndexToken → Underlyings (direct)](#43-redeem--indextoken--underlyings-direct)
  - [5. Pricing Mechanics](#5-pricing-mechanics)
  - [6. Security Considerations](#6-security-considerations)
    - [Spot Price Manipulation](#spot-price-manipulation)
    - [Reentrancy](#reentrancy)
    - [No Admin / No Upgrade](#no-admin--no-upgrade)
    - [`amountsPerUnit` Fixed at Deployment](#amountsperunit-fixed-at-deployment)
    - [Salt Mining Gas Cost](#salt-mining-gas-cost)
  - [7. Limitations \& Future Work](#7-limitations--future-work)

---

## 1. System Overview

Bundl is a **tokenized index protocol** built natively on Uniswap v4. Each index is represented
by an ERC-20 token (e.g. `bBLUE`, `bBEU`) whose price is always equal to its **Net Asset Value
(NAV)** — the sum of the USDC spot prices of the underlying assets backing one unit of the index.

Unlike traditional AMM-based index tokens, Bundl does not rely on arbitrageurs to keep the index
token price aligned with NAV. Instead, the hook itself acts as the sole market maker and enforces
NAV pricing on every swap by intercepting `beforeSwap` and returning a `BeforeSwapDelta` that
completely overrides the AMM curve.

```
User (USDC)  ──►  [SwapRouter / BundlRouter]  ──►  PoolManager
                                                         │
                                              beforeSwap ▼
                                                    BundlHook
                                               ┌────────────────┐
                                               │ • buy/sell      │
                                               │   underlyings   │
                                               │ • mint/burn     │
                                               │   IndexToken    │
                                               └────────────────┘
                                              WBTC/USDC · WETH/USDC · …
```

The system is fully non-custodial: the hook holds the physical underlying tokens as collateral
and any holder can always `redeem()` their index tokens for the pro-rata underlying basket,
bypassing the swap entirely.

---

## 2. Component Breakdown

### 2.1 BundlFactory

**File:** `BundlFactory.sol`

The factory is the single deployment entry point. One `BundlFactory` instance serves all indices
on a given chain. It is constructed with three immutables that are shared across every index:
`poolManager`, `usdc`, and `usdcDecimals`.

#### `createBundl(CreateBundlParams)`

The function performs four sequential steps in a single transaction:

1. **Salt mining** — iterates up to 200,000 candidate salts to find one that produces a `CREATE2`
   address whose lower bits match the required Uniswap v4 hook permission flags exactly
   (`AFTER_INITIALIZE | BEFORE_ADD_LIQUIDITY | BEFORE_SWAP | BEFORE_SWAP_RETURNS_DELTA | AFTER_SWAP`).
2. **Hook deployment** — deploys `BundlHook` via inline assembly `create2`, using the mined salt.
   The `hookSalt` parameter (unique per index) is appended to the creation code before hashing,
   ensuring distinct `initCodeHash` values across indices and preventing `CREATE2` address
   collisions.
3. **Token deployment** — deploys a `BundlToken` with the hook address as its immutable `minter`.
4. **Pool initialization** — constructs a `PoolKey(IndexToken, USDC, fee=3000, tickSpacing=60, hook)`
   and calls `poolManager.initialize(poolKey, sqrtPriceX96)`.

#### `CreateBundlParams` struct

| Field | Type | Description |
|---|---|---|
| `name` / `symbol` | `string` | ERC-20 metadata for the index token |
| `underlyingTokens` | `address[]` | Ordered list of underlying assets |
| `amountsPerUnit` | `uint256[]` | Raw token amount per 1e18 index units |
| `weightsBps` | `uint256[]` | Portfolio weights in basis points (must sum to 10,000) |
| `underlyingPools` | `PoolKey[]` | Pre-existing Uniswap v4 pools for each underlying/USDC pair |
| `usdcIs0` | `bool[]` | Whether USDC is `currency0` in each underlying pool |
| `tokenDecimals` | `uint8[]` | Decimals of each underlying token |
| `sqrtPriceX96` | `uint160` | Initial price for the IndexToken/USDC pool |
| `hookSalt` | `bytes32` | Unique salt suffix to avoid CREATE2 collisions (e.g. `keccak256("bBLUE")`) |

---

### 2.2 BundlHook

**File:** `BundlHook.sol`

The hook is the core of the system. It implements `IHooks` and acts simultaneously as:
- A **Uniswap v4 hook** attached to the IndexToken/USDC pool
- A **collateral vault** holding the underlying token backing
- A **NAV-priced market maker** for buy and sell operations
- A **price oracle reader** querying spot prices from underlying pools

#### Hook Permissions

| Permission | Enabled | Reason |
|---|---|---|
| `afterInitialize` | ✅ | Register the `PoolId` of the IndexToken/USDC pool |
| `beforeAddLiquidity` | ✅ | Block external liquidity additions |
| `beforeSwap` | ✅ | Intercept and handle buy/sell at NAV |
| `beforeSwapReturnDelta` | ✅ | Override AMM curve with exact NAV deltas |
| `afterSwap` | ✅ | Required by v4 (returns 0 delta, no-op) |
| All others | ❌ | Not needed; reverts with `HookNotImplemented` |

#### State Variables

```solidity
address[]  underlyingTokens      // asset addresses
uint256[]  amountsPerUnit        // raw amount per 1e18 index units
uint256[]  underlyingWeightsBps  // portfolio weights in BPS
PoolKey[]  underlyingPoolKeys    // underlying/USDC pool keys
bool[]     usdcIsCurrency0       // token ordering per pool
uint8[]    underlyingDecimals    // token decimals
PoolId     registeredPoolId      // the IndexToken/USDC pool
BundlToken indexToken            // the index ERC-20
address    usdc                  // USDC address (immutable)
```

#### Key Functions

**`beforeSwap`** — Routes to `_handleBuy` or `_handleSell` based on swap direction.
Determines direction by comparing `indexToken` address with `currency0` and `params.zeroForOne`.

**`_handleBuy`** — Handles `USDC → IndexToken` swaps:
- Exact-in: spends `usdcAmount` across underlyings proportionally, mints the minimum index units
  that can be fully backed by the received amounts.
- Exact-out: computes USDC needed to buy exactly `indexToMint` units, then executes.
- Deposits minted tokens into PM via `sync + transfer + settle`.
- Returns `BeforeSwapDelta(±usdcAmount, ∓indexToMint)`.

**`_handleSell`** — Handles `IndexToken → USDC` swaps:
- Takes `indexToBurn` IndexTokens from PM (`pm.take`), burns them.
- Sells each underlying proportionally via `_swapExactUnderlyingForUsdc`, leaving USDC in PM.
- Returns `BeforeSwapDelta(+indexToBurn, -usdcReceived)`.

**`redeem(uint256 indexAmount)`** — Bypasses the pool entirely. Burns tokens and transfers
the pro-rata basket of each underlying directly to `msg.sender`. Guarded by `nonReentrant`.

**`getNavPerUnit()`** — Returns the sum of USDC spot values of `amountsPerUnit[i]` for each
underlying, reading `sqrtPriceX96` from `poolManager.getSlot0()` in real time.

---

### 2.3 BundlToken

**File:** `BundlToken.sol`

A minimal ERC-20 extension of OpenZeppelin's `ERC20`. The only non-standard addition is a
single immutable `minter` address set at construction time — the `BundlHook`. All calls to
`mint()` and `burn()` are guarded by `onlyMinter`, making supply manipulation impossible
without going through the hook's validated logic.

The token is always 18 decimals (ERC-20 default). There is no governance, no pausability,
and no upgradeability.

---

### 2.4 BundlRouter

**File:** `BundlRouter.sol`

A generic, stateless sell router. A single deployment serves all `BundlHook` instances — it
reads `indexToken()` and `usdc()` dynamically from the `hookAddress` parameter at call time.

**Why a separate router for sells?**  
The SELL flow requires depositing IndexTokens into the PoolManager *before* the swap executes,
so that `_handleSell` can call `pm.take(IndexToken)` inside `beforeSwap`. This two-phase
sequence (deposit → swap → take USDC) cannot be expressed with a simple `approve + swap` and
requires an `IUnlockCallback` implementation.

#### `sellIndex(key, hookAddress, indexAmount, minUsdcOut)`

1. `transferFrom(user → router, indexAmount)` — outside the unlock.
2. `poolManager.unlock(data)` — enters the callback.
3. Inside `unlockCallback`:
   - `sync(IndexToken) + transfer(router → PM) + settle()` — credits PM with IndexTokens.
   - `pm.swap()` — triggers `BundlHook._handleSell`.
   - `poolManager.currencyDelta(router, USDC)` — reads actual USDC credit via transient storage.
   - `pm.take(USDC, user, usdcOut)` — delivers USDC directly to the user.
4. Reverts if `usdcOut < minUsdcOut` (slippage protection).

**BUY** does not need `BundlRouter`. The user calls a standard Uniswap v4 `PoolSwapTest` (or
equivalent frontend router) with USDC; `_handleBuy` handles everything inside `beforeSwap`
without needing a pre-deposit step.

---

## 3. Key Architectural Decisions

### 3.1 NAV-Priced Market Maker via Hook

**Decision:** Use `beforeSwapReturnDelta` to completely override the AMM curve and enforce
NAV pricing, rather than relying on external arbitrage.

**Rationale:** Traditional AMM-based index tokens (e.g. Balancer) diverge from NAV whenever
liquidity is shallow or markets move fast. By intercepting every swap and computing the exact
NAV on-chain, Bundl guarantees zero spread between the index token price and the value of its
backing — at the cost of potential manipulation via spot prices (see §6).

**Trade-off:** The hook assumes infinite liquidity at NAV. If the underlying pools have
insufficient depth to absorb the USDC required for a buy (or the underlying tokens for a sell),
the transaction reverts. There is no partial fill.

---

### 3.2 CREATE2 Salt Mining for Hook Permissions

**Decision:** Mine the `CREATE2` salt on-chain inside `BundlFactory._mineSalt()` so the
deployed hook address encodes the correct permission flags in its lower bits.

**Rationale:** Uniswap v4 uses the hook address itself as a bitmask — specific bits in the
address must be set for the PoolManager to call the corresponding callbacks. The factory
iterates candidate salts until it finds one that produces an address satisfying
`address & ALL_HOOK_MASK == REQUIRED_FLAGS`.

**Gas note:** Salt mining runs up to 200,000 iterations on-chain during `createBundl()`. This
is gas-expensive but acceptable for a one-time deployment transaction. A per-index `hookSalt`
suffix is appended to the creation bytecode to ensure the `initCodeHash` is unique per index,
preventing two indices from resolving to the same mined address.

---

### 3.3 Singleton PoolManager — Delta Accounting

**Decision:** All token movements use the v4 `unlock → callback → settle/take` pattern rather
than direct ERC-20 transfers between contracts.

**Rationale:** Uniswap v4's `PoolManager` is a singleton that holds all pool liquidity. Tokens
are never transferred in/out per-swap at the ERC-20 level during intermediate steps — only net
deltas are settled at the end of the `unlock` context. This dramatically reduces the number of
ERC-20 transfers and saves gas compared to v3's per-pool model.

**Implication for the hook:** `_swapExactUnderlyingForUsdc` intentionally does NOT call
`pm.take(USDC)` after selling an underlying — the USDC credit stays in the PM as an open delta.
The BundlRouter reads this accumulated credit via `currencyDelta()` at the end of the unlock
and delivers it to the user in a single `take()`.

---

### 3.4 Asymmetric Buy/Sell Architecture

**Decision:** BUY uses a standard SwapRouter; SELL requires `BundlRouter`.

**Rationale:** During a buy, the hook mints new tokens and deposits them into PM inside
`beforeSwap` — the PM can then deliver them to the caller without any pre-deposit. During a
sell, the hook needs to receive the IndexTokens *before* it can burn them, which requires the
caller to deposit them into PM before the swap executes. This is handled by `BundlRouter`'s
`unlockCallback`.

---

### 3.5 No External Liquidity — Direct Liquidity Guard

**Decision:** `beforeAddLiquidity` reverts for any `sender != address(this)`.

**Rationale:** The IndexToken/USDC pool has no real AMM liquidity — it is a "virtual" pool
whose only purpose is to route swap calls through the hook. Allowing external LPs to add
liquidity would create idle capital in the pool that could interfere with the delta accounting
and potentially drain the hook's collateral via sandwich attacks.

---

### 3.6 Spot Price Oracle — No TWAP

**Decision:** NAV is computed using `getSlot0().sqrtPriceX96` — the current spot price — from
each underlying pool.

**Rationale:** Simplicity and real-time. In a production environment an oracle like Chainlink would be used.

**Trade-off:** Spot prices are manipulable within a single transaction (flash loan attacks).
A sufficiently capitalized attacker could manipulate an underlying pool's spot price, buy index
tokens at an artificially low NAV, and unwind the manipulation in the same block. This is the
primary security risk of the current design (see §6).

---

### 3.7 Permissionless Index Creation

**Decision:** `BundlFactory.createBundl()` is callable by anyone with no access control.

**Rationale:** Composability and decentralization. Any developer or DAO can deploy a new index
with arbitrary underlying tokens, weights, and amounts without permission from a central admin.

**Trade-off:** No validation of the `underlyingPools` or `usdcIs0` inputs. A misconfigured
deployment will produce a broken index (e.g. wrong price direction) rather than reverting.
Input validation is the deployer's responsibility.

---

## 4. Data Flow

### 4.1 BUY — USDC → IndexToken

```
User
 │  approve(USDC, swapRouter)
 │  swap(USDC → IndexToken, exactIn)
 ▼
SwapRouter (PoolSwapTest or equivalent)
 │  poolManager.unlock(swapData)
 ▼
PoolManager
 │  beforeSwap(BundlHook, params)
 ▼
BundlHook._handleBuy()
 ├─ _buyUnderlyingWithUsdc(totalUsdc)
 │   ├─ pm.swap(USDC → WBTC, exactIn, 40%)  ──► Pool WBTC/USDC
 │   ├─ pm.swap(USDC → WETH, exactIn, 30%)  ──► Pool WETH/USDC
 │   └─ pm.take(underlying → hook)  [hook holds collateral]
 ├─ indexToken.mint(hook, indexToMint)
 ├─ pm.sync(IndexToken) + transfer(hook → PM) + pm.settle()
 └─ return BeforeSwapDelta(+usdcSpent, -indexToMint)
 ▼
PoolManager delivers IndexToken to SwapRouter → User
```

### 4.2 SELL — IndexToken → USDC

```
User
 │  approve(IndexToken, BundlRouter)
 │  BundlRouter.sellIndex(key, hook, indexAmount, minUsdcOut)
 ▼
BundlRouter
 │  transferFrom(user → router, indexAmount)
 │  poolManager.unlock(callbackData)
 ▼
BundlRouter.unlockCallback()
 ├─ pm.sync(IndexToken) + transfer(router → PM) + pm.settle()
 │   [PM: +indexAmount IndexToken credit for router]
 ├─ pm.swap(IndexToken → USDC, exactIn)
 │   ▼
 │  BundlHook._handleSell()
 │   ├─ pm.take(IndexToken → hook, indexToBurn)  [PM IndexToken: 0]
 │   ├─ indexToken.burn(hook, indexToBurn)
 │   ├─ _sellUnderlyingForUsdc(indexToBurn)
 │   │   ├─ pm.swap(WBTC → USDC, exactIn)  ──► Pool WBTC/USDC
 │   │   └─ pm.swap(WETH → USDC, exactIn)  ──► Pool WUNI/USDC
 │   │       [USDC stays in PM as open delta — NOT taken yet]
 │   └─ return BeforeSwapDelta(+indexToBurn, -usdcReceived)
 ├─ currencyDelta(router, USDC)  → usdcOut
 └─ pm.take(USDC → user, usdcOut)
```

### 4.3 REDEEM — IndexToken → Underlyings (direct)

```
User
 │  approve(IndexToken, BundlHook)
 │  BundlHook.redeem(indexAmount)
 ▼
BundlHook
 ├─ indexToken.burn(user, indexAmount)
 └─ for each underlying:
     amount = indexAmount * amountsPerUnit[i] / 1e18
     IERC20(underlying).transfer(user, amount)
```

No pool interaction. No price dependency. Always redeems at the fixed `amountsPerUnit` ratio,
regardless of market prices.

---

## 5. Pricing Mechanics

The price of 1 index unit is computed as:

```
NAV = Σᵢ [ spotPrice(underlying_i) × amountsPerUnit[i] ]
```

where `spotPrice` is derived from `sqrtPriceX96` read from `getSlot0()` of the underlying pool:

```solidity
// usdcIs0 = false (underlying is currency0, USDC is currency1)
usdcValue = mulDiv(mulDiv(tokenAmount, sqrtPrice, 2^96), sqrtPrice, 2^96)

// usdcIs0 = true (USDC is currency0, underlying is currency1)
usdcValue = mulDiv(mulDiv(tokenAmount, 2^96, sqrtPrice), 2^96, sqrtPrice)
```

`FullMath.mulDiv` is used throughout to avoid 256-bit overflow in intermediate calculations.

The `amountsPerUnit` values are fixed at index creation time and represent the exact raw token
amounts (respecting each token's decimals) that make up one `1e18` unit of the index.

Example for a hypothetical $100 index at creation:
- WBTC ($85,000): 40% → `47,058 satoshis` (8 decimals)
- WETH ($2,000): 30% → `15,000,000,000,000,000` (18 decimals, = 0.015 ETH)
- WUNI ($10): 30% → `3,000,000,000,000,000,000` (18 decimals, = 3 UNI)

---

## 6. Security Considerations

### Spot Price Manipulation
The primary risk. NAV relies on `getSlot0().sqrtPriceX96` which can be moved within a single
transaction. An attacker could:
1. Flash-loan a large amount of an underlying asset.
2. Dump it into the underlying pool, depressing the spot price.
3. Buy index tokens at a discounted NAV.
4. Repay the flash loan, letting the price recover.
5. Sell or redeem index tokens at full NAV.

**Mitigation path:** Replace `getSlot0()` with or Chainlink or a TWAP oracle.

### Reentrancy
`redeem()` is guarded by OpenZeppelin's `ReentrancyGuard`. The `beforeSwap` and
`unlockCallback` paths are protected by the PoolManager's own reentrancy lock (`unlock` cannot
be nested).

### No Admin / No Upgrade
Contracts are immutable post-deployment. There is no `owner`, no proxy, and no emergency
pause. This maximizes trustlessness but means bugs cannot be patched without redeployment.

### `amountsPerUnit` Fixed at Deployment
Index composition never rebalances. If asset prices diverge significantly from their initial
weights, the effective portfolio allocation will drift. There is no on-chain mechanism to
update `amountsPerUnit` post-deployment.

### Salt Mining Gas Cost
`_mineSalt` runs up to 200,000 loop iterations on-chain. On a congested network this could
exceed block gas limits. The loop count may need tuning depending on target chain.

---

## 7. Limitations & Future Work

| Area | Current State | Suggested Improvement |
|---|---|---|
| Price oracle | Spot price (`getSlot0`) | TWAP via v4 `observe()` |
| Index rebalancing | Fixed at deployment | On-chain rebalancer with governance |
| Slippage (buy) | No `minIndexOut` guard on buy | Add `minOutput` to buy path |
| Fee distribution | No protocol fee | Add configurable fee in `_handleBuy/Sell` |

