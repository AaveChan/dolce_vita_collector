# Makefile for Dolce Vita Collector

include .env

# Scripts
FETCH_RESERVES_SCRIPT := script/FetchReserves.s.sol
MINT_TO_TREASURY_SCRIPT := script/MintToTreasury.s.sol

# Log directory
LOG_DIR := ./logs

# Determine if it's a dry run
ifneq ($(dry),)
  PRIVATE_KEY_ARG := --sender 0x3Cbded22F878aFC8d39dCD744d3Fe62086B76193
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

mint-to-treasury: $(LOG_DIR)
	@echo "Minting to treasury on ${NETWORK} ${POOL}..."
	@RESERVES=$$(cat $(LOG_DIR)/reserves.json); \
	NETWORK=${NETWORK} POOL=${POOL} forge script ${MINT_TO_TREASURY_SCRIPT} \
		--sig "run(string)" "$$RESERVES" \
		--rpc-url ${RPC_${NETWORK}} \
		${PRIVATE_KEY_ARG} \
		${EXTRA_ARGS}

run-all: fetch-reserves
	@echo "Running mint-to-treasury for all networks and pools with reserves..."
	@RESERVES=$$(cat $(LOG_DIR)/reserves.json); \
	for network in $$(echo "$$RESERVES" | jq -r 'keys[]'); do \
		for pool in $$(echo "$$RESERVES" | jq -r ".[\"$$network\"] | keys[]"); do \
			echo "Processing $$network $$pool"; \
			$(MAKE) mint-to-treasury NETWORK=$$network POOL=$$pool; \
		done; \
	done

clean:
	@rm -rf $(LOG_DIR) broadcast cache out