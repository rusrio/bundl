#!/bin/bash
# Syncs the deployed smart contract addresses from Foundry to the Next.js frontend

set -e

NETWORK=$1
ENV_PATH="./frontend/.env.local"
DEPLOY_JSON="./foundry/deploy.json"

if [ "$NETWORK" != "--anvil" ] && [ "$NETWORK" != "--sepolia" ]; then
    echo "Usage: ./sync-env.sh [--anvil|--sepolia]"
    exit 1
fi

if [ ! -f "$DEPLOY_JSON" ]; then
    echo "Error: Deployment JSON not found at $DEPLOY_JSON"
    echo "Run 'forge script' in the foundry directory first."
    exit 1
fi

echo "Syncing addresses from $DEPLOY_JSON to $ENV_PATH..."

# Parse addresses using jq
BUNDL_HOOK=$(jq -r '.bundlHookAddress' "$DEPLOY_JSON")
BUNDL_TOKEN=$(jq -r '.bundlTokenAddress' "$DEPLOY_JSON")
USDC_ADDRESS=$(jq -r '.usdcAddress' "$DEPLOY_JSON")
V4_ROUTER=$(jq -r '.swapRouterAddress' "$DEPLOY_JSON")

# Determine correct Chain ID
if [ "$NETWORK" == "--anvil" ]; then
    CHAIN_ID=31337
else
    CHAIN_ID=11155111
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

update_env "NEXT_PUBLIC_BUNDL_HOOK_ADDRESS" "$BUNDL_HOOK"
update_env "NEXT_PUBLIC_BUNDL_TOKEN_ADDRESS" "$BUNDL_TOKEN"
update_env "NEXT_PUBLIC_USDC_ADDRESS" "$USDC_ADDRESS"
update_env "NEXT_PUBLIC_V4_ROUTER_ADDRESS" "$V4_ROUTER"
update_env "NEXT_PUBLIC_CHAIN_ID" "$CHAIN_ID"

echo "Environment successfully synchronized!"
echo "CHAIN ID: $CHAIN_ID"
echo "BUNDL HOOK: $BUNDL_HOOK"
echo "BUNDL TOKEN: $BUNDL_TOKEN"
echo "USDC: $USDC_ADDRESS"
echo "V4 ROUTER: $V4_ROUTER"
