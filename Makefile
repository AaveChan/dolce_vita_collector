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

mint-to-treasury: $(LOG_DIR)
	@echo "Minting to treasury on ${NETWORK}..."
	@timeout $(TIMEOUT) bash -c "\
		RESERVES=\$$(cat $(LOG_DIR)/reserves.json); \
		NETWORK=${NETWORK} forge script ${MINT_TO_TREASURY_SCRIPT} \
			--sig \"run(string)\" \"\$$RESERVES\" \
			--rpc-url ${RPC_${NETWORK}} \
			${PRIVATE_KEY_ARG} \
			${EXTRA_ARGS}" \
	|| echo "Transaction for ${NETWORK} timed out after $(TIMEOUT) seconds. Skipping to next network."

run-all: fetch-reserves
	@echo "Running mint-to-treasury for all networks with reserves..."
	@NETWORKS=$$(jq -r 'keys[]' $(LOG_DIR)/reserves.json); \
	for network in $$NETWORKS; do \
		echo "Processing $$network"; \
		$(MAKE) mint-to-treasury NETWORK=$$network || true; \
	done

clean:
	@rm -rf $(LOG_DIR) broadcast cache out