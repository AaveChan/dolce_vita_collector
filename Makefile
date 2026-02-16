# Makefile for Dolce Vita Collector

include .env

# Scripts
FETCH_RESERVES_SCRIPT := script/FetchReserves.s.sol
MINT_TO_TREASURY_SCRIPT := script/MintToTreasury.s.sol

# Log directory
LOG_DIR := ./logs

# Timeout duration (in seconds)
TIMEOUT := 300

# Network list — auto-derived from .env RPC_* entries
NETWORK_LIST := $(shell grep -oP '^RPC_\K[A-Z0-9_]+(?==)' .env)

# Private key file (more secure than command line)
KEYFILE := .keyfile

# Dry run support
ifneq ($(dry),)
  PRIVATE_KEY_ARG := --sender $(SENDER)
  EXTRA_ARGS := -vvvv
else
  PRIVATE_KEY_ARG := --private-key "$$(cat $(KEYFILE))"
  EXTRA_ARGS := --broadcast -vvvv
endif

# Networks that don't support EIP-1559 and need legacy gas pricing
LEGACY_NETWORKS := METIS BNB CELO

.PHONY: fetch-reserves mint clean run-all

# Ensure logs dir exists
$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

fetch-reserves: $(LOG_DIR)
	@echo "🔄 Fetching reserves in parallel..."
	@bash ./fetch_reserves_parallel.sh
	@if [ -f "./logs/reserves.json" ] && [ -s "./logs/reserves.json" ]; then \
		echo "✅ Reserves fetched successfully"; \
	else \
		echo "❌ Failed to fetch reserves" && exit 1; \
	fi

# Legacy sequential fetch (kept for reference)
fetch-reserves-sequential: $(LOG_DIR)
	@echo "🔄 Fetching reserves list for all networks (sequential)..."
	@forge script ${FETCH_RESERVES_SCRIPT}:FetchReservesScript -vvvv || true

mint:
	@if [ -z "$(NETWORK)" ]; then \
		echo "❌ Error: NETWORK is not set. Use 'make mint NETWORK=<network_name>' or set NETWORK in .env file."; \
		exit 1; \
	fi
	@if [ ! -f "$(KEYFILE)" ]; then \
		echo "❌ Error: Keyfile not found. Create .keyfile with your private key."; \
		exit 1; \
	fi
	@echo "🚀 Minting to treasury for network: $(NETWORK)"
	$(eval LEGACY_FLAG := $(if $(filter $(NETWORK),$(LEGACY_NETWORKS)),--legacy,))
	@TARGET_NETWORK=$(NETWORK) timeout $(TIMEOUT) forge script ${MINT_TO_TREASURY_SCRIPT}:MintToTreasuryScript ${EXTRA_ARGS} --private-key "$$(cat $(KEYFILE))" $(LEGACY_FLAG)

clean:
	@echo "🧹 Cleaning logs and broadcast artifacts..."
	@find $(LOG_DIR) -type f -delete
	@find broadcast -mindepth 1 -delete 2>/dev/null || true
	@echo "✅ Clean complete"

# Full clean including compiled artifacts (slow rebuild)
clean-all: clean
	@find out -mindepth 1 -delete 2>/dev/null || true
	@echo "✅ Full clean complete"

run-all: fetch-reserves
	@for network in $(NETWORK_LIST); do \
		echo "🌐 Running mint for $$network"; \
		$(MAKE) mint NETWORK=$$network || echo "⚠️ Mint failed for $$network"; \
	done
	@echo "🏁 Dolce Vita run-all complete"
