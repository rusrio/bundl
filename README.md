<img width="1377" height="476" alt="image" src="https://github.com/user-attachments/assets/11709d65-f376-470f-8f2a-5ab25271dd97" />

# Bundl — On-chain Index Protocol

**Bundl** is a permissionless tokenized index protocol built natively on [Uniswap v4](https://docs.uniswap.org/contracts/v4/overview). Each index is represented by a standard ERC-20 token (e.g. `bBLUE`, `bBEU`) whose price is always equal to its **Net Asset Value (NAV)** — enforced on every swap by a custom Uniswap v4 hook, with no reliance on external arbitrageurs.

> **Status:** Prototype / Hackathon — not audited, do not use in production.

---

## How It Works

Instead of relying on an AMM curve to price the index token, the `BundlHook` intercepts every swap via `beforeSwap` and acts as the sole market maker. On each buy, it purchases the underlying assets proportionally with the user's USDC, mints new index tokens, and delivers them at exact NAV. On each sell, it burns the index tokens, sells the underlying basket back to USDC, and returns the proceeds to the user.

```
User (USDC)
    │
    ▼
SwapRouter / BundlRouter
    │
    ▼
PoolManager  ──beforeSwap──►  BundlHook
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
              WBTC/USDC     WETH/USDC     WUNI/USDC
              (pool)        (pool)        (pool)
```

Any holder can also `redeem()` index tokens directly for the pro-rata basket of underlying assets, bypassing the pool entirely — this provides a hard floor against NAV discount.

---

## Architecture

| Contract | Description |
|---|---|
| `BundlFactory` | One-click deployment of hook + token + pool. Mines the `CREATE2` salt to satisfy Uniswap v4 hook permission bits. |
| `BundlHook` | Core contract. Uniswap v4 hook + collateral vault + NAV market maker. |
| `BundlToken` | Minimal ERC-20 index token. Only its paired `BundlHook` can mint/burn. |
| `BundlRouter` | Stateless sell router. Handles the two-phase `unlock → deposit → swap → take` flow required for selling. |

> For a deep-dive into every contract and architectural decision, see [ARCHITECTURE.md](./ARCHITECTURE.md).

---

## Repository Structure

```
bundl/
├── foundry/
│   ├── src/
│   │   ├── BundlFactory.sol
│   │   ├── BundlHook.sol
│   │   ├── BundlToken.sol
│   │   ├── BundlRouter.sol
│   │   └── interfaces/
│   │       └── IBundlHook.sol
│   ├── script/
│   │   ├── Deploy.s.sol           # Deploys core protocol + bBLUE index
│   │   └── DeployBtcEthUni.s.sol  # Deploys bBEU index (BTC+ETH+UNI)
│   ├── test/
│   │   ├── BundlHook.t.sol
│   │   └── BundlToken.t.sol
│   └── foundry.toml
├── frontend/                      # Next.js frontend (wagmi + viem)
├── Makefile                       # Developer workflow commands
└── ARCHITECTURE.md
```

---

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- [Node.js](https://nodejs.org/) ≥ 18
- [pnpm](https://pnpm.io/installation)

---

## Quick Start (Local)

### 1. Install dependencies

```bash
make install
```

### 2. Start a local Anvil node

Open a dedicated terminal and keep it running:

```bash
make anvil
```

### 3. Deploy the protocol and sync the frontend

```bash
# Deploys PoolManager, BundlFactory, BundlRouter, and the default index (bBLUE)
make setup-local

# Optionally deploy a second index: bBEU (BTC + ETH + UNI)
make setup-local-beu
```

### 4. Start the frontend

```bash
make dev
# → http://localhost:3000
```

### 5. Fund a wallet for testing

```bash
make fund WALLET=0xYourAddress
# Mints 10,000 USDC and sends 10 ETH to the specified address
```

---

## Available Commands

```
make install          Install all dependencies (Foundry + frontend)
make build            Compile smart contracts
make anvil            Start local Anvil node (chain-id 31337)
make deploy-local     Deploy protocol to local Anvil
make sync-local       Sync deployed addresses to frontend .env.local
make setup-local      deploy-local + sync-local in one step
make deploy-local-beu Deploy the bBEU index to local Anvil
make sync-local-beu   Sync bBEU addresses to frontend .env.local
make setup-local-beu  deploy-local-beu + sync-local-beu in one step
make dev              Start Next.js dev server on port 3000
make fund WALLET=     Mint 10,000 USDC + send 10 ETH to WALLET
make pool-status      Print NAV, pool states, backing, and token supply
make clean            Remove build artifacts (forge + Next.js)
```

---

## Running Tests

```bash
cd foundry
forge test -vv
```

---

## Key Design Decisions

### NAV-priced market maker
The `BundlHook` uses `BeforeSwapDelta` to completely override the Uniswap v4 AMM curve. There is no AMM liquidity in the IndexToken/USDC pool — the hook resolves every swap at the exact current NAV, eliminating the spread between market price and backing value.

### CREATE2 salt mining
Uniswap v4 encodes hook permissions in the hook's contract address (lower bits). `BundlFactory` mines the correct `CREATE2` salt on-chain during `createBundl()` to produce an address with the required permission flags. A per-index `hookSalt` prevents address collisions across multiple deployments.

### Asymmetric buy/sell routing
- **BUY** — uses a standard Uniswap v4 SwapRouter. The hook mints and deposits index tokens inside `beforeSwap`, no pre-deposit needed.
- **SELL** — uses `BundlRouter`. Index tokens must be deposited into the PoolManager *before* the swap so the hook can `take` and burn them inside `beforeSwap`.

### No external liquidity
`beforeAddLiquidity` reverts for any caller that is not the hook itself. The IndexToken/USDC pool has no AMM liquidity — it exists solely as a routing surface for the hook.

### Price oracle
NAV is computed from `getSlot0().sqrtPriceX96` of each underlying pool — i.e. **spot price**. This is simple and real-time but manipulable within a single transaction. A production deployment should replace this with a TWAP (Uniswap v4 `OracleHook`) or an external oracle (Chainlink, Pyth).

---

## Indices

New indices can be deployed permissionlessly via `BundlFactory.createBundl()`.

---

## Stack

- **Smart contracts:** Solidity 0.8.26 · [Foundry](https://book.getfoundry.sh/)
- **Core protocol:** [Uniswap v4](https://github.com/Uniswap/v4-core)
- **Token standard:** [OpenZeppelin ERC-20](https://docs.openzeppelin.com/contracts/5.x/)
- **Frontend:** Next.js · [wagmi](https://wagmi.sh/) · [viem](https://viem.sh/)

---

## Security

This project is **unaudited** and intended for hackathon / prototype use only.

Known risks:
- **Spot price manipulation** — NAV uses `getSlot0()` which can be moved within a single transaction via flash loans. Mitigated in production by replacing with a TWAP or Chainlink oracle.
- **No upgradeability** — contracts are immutable post-deployment; bugs cannot be patched without redeployment.
- **Fixed composition** — `amountsPerUnit` is set at deployment and never rebalances.

---

## License

MIT
