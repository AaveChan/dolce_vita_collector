# Makefile for Dolce Vita Collector

include .env

# Scripts
FETCH_RESERVES_SCRIPT := script/FetchReserves.s.sol
MINT_TO_TREASURY_SCRIPT := script/MintToTreasury.s.sol

# Log directory
LOG_DIR := ./logs

# Timeout duration (in seconds)
TIMEOUT := 300

# Network list
NETWORK_LIST := MAINNET AVALANCHE OPTIMISM POLYGON ARBITRUM BASE GNOSIS BNB SCROLL METIS LINEA SONIC CELO PLASMA SONEIUM MANTLE MEGAETH INK

# Dry run support
ifneq ($(dry),)
  PRIVATE_KEY_ARG := --sender $(SENDER)
  EXTRA_ARGS := -vvvv
else
  PRIVATE_KEY_ARG := --private-key ${PRIVATE_KEY}
  EXTRA_ARGS := --broadcast -vvvv
endif

.PHONY: fetch-reserves mint clean run-all

# Ensure logs dir exists
$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

fetch-reserves: $(LOG_DIR)
	@echo "🔄 Fetching reserves list for all networks..."
	@forge script ${FETCH_RESERVES_SCRIPT}:FetchReservesScript -vvvv || true
	@if [ -f "./logs/reserves.json" ] && [ -s "./logs/reserves.json" ]; then \
		echo "✅ Reserves fetched successfully"; \
	else \
		echo "❌ Failed to fetch reserves" && exit 1; \
	fi

mint:
	@if [ -z "$(NETWORK)" ]; then \
		echo "❌ Error: NETWORK is not set. Use 'make mint NETWORK=<network_name>' or set NETWORK in .env file."; \
		exit 1; \
	fi
	@echo "🚀 Minting to treasury for network: $(NETWORK)"
	TARGET_NETWORK=$(NETWORK) timeout $(TIMEOUT) forge script ${MINT_TO_TREASURY_SCRIPT}:MintToTreasuryScript ${EXTRA_ARGS} ${PRIVATE_KEY_ARG}

clean:
	@echo "🧹 Cleaning logs and build artifacts..."
	@find $(LOG_DIR) -type f -delete
	@find broadcast -mindepth 1 -delete
	@find cache -mindepth 1 -delete
	@find out -mindepth 1 -delete
	@echo "✅ Clean complete"

run-all: fetch-reserves
	@for network in $(NETWORK_LIST); do \
		echo "🌐 Running mint for $$network"; \
		$(MAKE) mint NETWORK=$$network || echo "⚠️ Mint failed for $$network"; \
	done
	@echo "🏁 Dolce Vita run-all complete"
