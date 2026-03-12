.PHONY: help install build anvil deploy-local sync-local setup-local dev pool-status clean

# Default local private key (Foundry's first dev account)
PRIVATE_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Bundl Index Protocol - Local Development Commands"
	@echo "-------------------------------------------------"
	@echo "make install      - Install all backend and frontend dependencies"
	@echo "make build        - Compile the Foundry smart contracts"
	@echo "make anvil        - Start a local Anvil node (runs in foreground)"
	@echo "make deploy-local - Deploy the protocol to the local Anvil node"
	@echo "make sync-local   - Sync the deployed Anvil addresses to the frontend .env.local"
	@echo "make setup-local  - Run deploy-local and sync-local together"
	@echo "make dev          - Start the Next.js frontend development server"
	@echo "make fund WALLET= - Mint 10,000 USDC and send 10 ETH to the specified wallet"
	@echo "make pool-status  - Show underlying pool states, NAV, and total backing"
	@echo "make clean        - Clean build artifacts for both frontend and backend"
	@echo "-------------------------------------------------"
	@echo "Suggested workflow: "
	@echo "  Terminal 1: make anvil"
	@echo "  Terminal 2: make setup-local"
	@echo "  Terminal 2: make dev"

install:
	cd foundry && forge install
	cd frontend && pnpm install

build:
	cd foundry && forge build

anvil:
	cd foundry && anvil --chain-id 31337 --block-gas-limit 300000000

deploy-local:
	@echo "Deploying to local Anvil node..."
	cd foundry && PRIVATE_KEY=$(PRIVATE_KEY) forge script script/Deploy.s.sol:DeployScript --rpc-url http://127.0.0.1:8545 --broadcast --gas-estimate-multiplier 100

sync-local:
	@echo "Syncing environment variables..."
	chmod +x ./sync-env.sh
	./sync-env.sh --anvil

setup-local: deploy-local sync-local
	@echo "Local environment setup complete! You can now run 'make dev'."

dev:
	cd frontend && pnpm dev --port 3000

fund:
	@if [ -z "$(WALLET)" ]; then echo "❌ Error: Please provide a WALLET address. Usage: make fund WALLET=0xYourAddress"; exit 1; fi
	@echo "💸 Funding $(WALLET) with 10,000 USDC and 10 ETH..."
	@USDC_ADDR=$$(grep NEXT_PUBLIC_USDC_ADDRESS frontend/.env.local | cut -d '=' -f2) && \
	cast send $$USDC_ADDR "mint(address,uint256)" $(WALLET) 10000000000 --rpc-url http://127.0.0.1:8545 --private-key $(PRIVATE_KEY) > /dev/null
	@cast send $(WALLET) --value 10ether --rpc-url http://127.0.0.1:8545 --private-key $(PRIVATE_KEY) > /dev/null
	@echo "✅ Wallet successfully funded!"

pool-status:
	@HOOK=$$(grep NEXT_PUBLIC_BUNDL_HOOK_ADDRESS frontend/.env.local | cut -d '=' -f2) && \
	TOKEN=$$(grep NEXT_PUBLIC_BUNDL_TOKEN_ADDRESS frontend/.env.local | cut -d '=' -f2) && \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
	echo "   Bundl Protocol — Pool Status" && \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" && \
	echo "" && \
	echo " NAV per Unit (USDC):" && \
	NAV=$$(cast call $$HOOK "getNavPerUnit()(uint256)" --rpc-url http://127.0.0.1:8545) && \
	echo "   $$NAV (raw)" && \
	echo "" && \
	echo " Underlying Pool States:" && \
	cast call $$HOOK "getPoolStates()(uint160[],int24[],uint128[])" --rpc-url http://127.0.0.1:8545 && \
	echo "" && \
	echo " Total Backing:" && \
	cast call $$HOOK "getTotalBacking()(uint256[])" --rpc-url http://127.0.0.1:8545 && \
	echo "" && \
	echo " Index Token Supply:" && \
	cast call $$TOKEN "totalSupply()(uint256)" --rpc-url http://127.0.0.1:8545 && \
	echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

clean:
	cd foundry && forge clean
	cd frontend && rm -rf .next
