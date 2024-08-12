# Makefile for Dolce Vita Collector

include .env

# Scripts
FETCH_RESERVES_SCRIPT := script/FetchReserves.s.sol
MINT_TO_TREASURY_SCRIPT := script/MintToTreasury.s.sol

# Log directory
LOG_DIR := ./logs

# Timeout duration (5 minutes)
TIMEOUT := 300

# Determine if it's a dry run
ifneq ($(dry),)
  PRIVATE_KEY_ARG := --sender $(SENDER)
  EXTRA_ARGS := -vvvv
else
  PRIVATE_KEY_ARG := --private-key ${PRIVATE_KEY}
  EXTRA_ARGS := --broadcast -vvvv
endif

.PHONY: fetch-reserves mint-to-treasury run-all clean

$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

fetch-reserves: $(LOG_DIR)
	@echo "Fetching reserves list for all networks..."
	@forge script ${FETCH_RESERVES_SCRIPT} -vvvv

mint:
	@if [ -z "$(NETWORK)" ]; then \
		echo "Error: NETWORK is not set. Use 'make mint NETWORK=<network_name>' or set NETWORK in .env file."; \
		exit 1; \
	fi
	@echo "Minting for network: $(NETWORK)"
	TARGET_NETWORK=$(NETWORK) forge script script/MintToTreasury.s.sol:MintToTreasuryScript --broadcast

clean:
	@rm -rf $(LOG_DIR) broadcast cache out