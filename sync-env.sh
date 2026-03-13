#!/bin/bash
# Syncs the deployed smart contract addresses from Foundry to the Next.js frontend

set -e

NETWORK=$1
ENV_PATH="./frontend/.env.local"
DEPLOY_JSON="./foundry/deploy.json"
DEPLOY2_JSON="./foundry/deploy2.json"

if [ "$NETWORK" != "--anvil" ] && [ "$NETWORK" != "--sepolia" ] && [ "$NETWORK" != "--beu" ]; then
    echo "Usage: ./sync-env.sh [--anvil|--sepolia|--beu]"
    exit 1
fi

# Create or touch .env.local
touch "$ENV_PATH"

# Function to update or append env var
update_env() {
    key=$1
    value=$2
    if grep -q "^$key=" "$ENV_PATH"; then
        sed -i "s|^$key=.*|$key=$value|" "$ENV_PATH"
    else
        echo "$key=$value" >> "$ENV_PATH"
    fi
}

# ── BEU (second index only) ─────────────────────────────────────────────────
if [ "$NETWORK" == "--beu" ]; then
    if [ ! -f "$DEPLOY2_JSON" ]; then
        echo "Error: deploy2.json not found at $DEPLOY2_JSON"
        echo "Run 'make deploy-local-beu' first."
        exit 1
    fi
    BUNDL_HOOK2=$(jq -r '.bundlHookAddress'  "$DEPLOY2_JSON")
    BUNDL_TOKEN2=$(jq -r '.bundlTokenAddress' "$DEPLOY2_JSON")
    WUNI_ADDRESS=$(jq -r '.wuniAddress'       "$DEPLOY2_JSON")
    update_env "NEXT_PUBLIC_BUNDL_HOOK2_ADDRESS"  "$BUNDL_HOOK2"
    update_env "NEXT_PUBLIC_BUNDL_TOKEN2_ADDRESS" "$BUNDL_TOKEN2"
    update_env "NEXT_PUBLIC_WUNI_ADDRESS"         "$WUNI_ADDRESS"
    echo "BTC-ETH-UNI index (bBEU) environment synced!"
    echo "BUNDL HOOK2:  $BUNDL_HOOK2"
    echo "BUNDL TOKEN2: $BUNDL_TOKEN2"
    echo "WUNI:         $WUNI_ADDRESS"
    exit 0
fi

# ── ANVIL / SEPOLIA (first index) ────────────────────────────────────────────
if [ ! -f "$DEPLOY_JSON" ]; then
    echo "Error: Deployment JSON not found at $DEPLOY_JSON"
    echo "Run 'forge script' in the foundry directory first."
    exit 1
fi

echo "Syncing addresses from $DEPLOY_JSON to $ENV_PATH..."

BUNDL_HOOK=$(jq -r '.bundlHookAddress' "$DEPLOY_JSON")
BUNDL_TOKEN=$(jq -r '.bundlTokenAddress' "$DEPLOY_JSON")
USDC_ADDRESS=$(jq -r '.usdcAddress' "$DEPLOY_JSON")
V4_ROUTER=$(jq -r '.swapRouterAddress' "$DEPLOY_JSON")
BUNDL_ROUTER=$(jq -r '.bundlRouterAddress' "$DEPLOY_JSON")

if [ "$NETWORK" == "--anvil" ]; then
    CHAIN_ID=31337
else
    CHAIN_ID=11155111
fi

update_env "NEXT_PUBLIC_BUNDL_HOOK_ADDRESS"   "$BUNDL_HOOK"
update_env "NEXT_PUBLIC_BUNDL_TOKEN_ADDRESS"  "$BUNDL_TOKEN"
update_env "NEXT_PUBLIC_USDC_ADDRESS"         "$USDC_ADDRESS"
update_env "NEXT_PUBLIC_V4_ROUTER_ADDRESS"    "$V4_ROUTER"
update_env "NEXT_PUBLIC_BUNDL_ROUTER_ADDRESS" "$BUNDL_ROUTER"
update_env "NEXT_PUBLIC_CHAIN_ID"             "$CHAIN_ID"

echo "Environment successfully synchronized!"
echo "CHAIN ID:     $CHAIN_ID"
echo "BUNDL HOOK:   $BUNDL_HOOK"
echo "BUNDL TOKEN:  $BUNDL_TOKEN"
echo "USDC:         $USDC_ADDRESS"
echo "V4 ROUTER:    $V4_ROUTER"
echo "BUNDL ROUTER: $BUNDL_ROUTER"
