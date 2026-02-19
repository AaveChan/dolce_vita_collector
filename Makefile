export PATH := $(HOME)/.foundry/bin:$(PATH)
export FOUNDRY_DISABLE_NIGHTLY_WARNING := 1

include .env

KEYFILE := .keyfile
LOG_DIR := ./logs
LEGACY_NETWORKS := METIS BNB CELO

.PHONY: mint run-l2s run-mainnet clean

$(LOG_DIR):
	@mkdir -p $(LOG_DIR)

mint: $(LOG_DIR)
	@if [ -z "$(NETWORK)" ]; then \
		echo "Error: NETWORK not set. Use 'make mint NETWORK=<name>'"; \
		exit 1; \
	fi
	@if [ ! -f "$(KEYFILE)" ]; then \
		echo "Error: .keyfile not found"; \
		exit 1; \
	fi
	$(eval LEGACY_FLAG := $(if $(filter $(NETWORK),$(LEGACY_NETWORKS)),--legacy,))
	$(eval RPC_URL := $(RPC_$(NETWORK)))
	$(eval POOL_ADDR := $($(NETWORK)_MAIN_POOL))
	@./mint_via_cast.sh "$(RPC_URL)" "$(POOL_ADDR)" "$(KEYFILE)" $(LEGACY_FLAG)

run-l2s:
	@./dolce_vita_collector_with_notifications.sh --l2s-only

run-mainnet:
	@./dolce_vita_collector_with_notifications.sh --mainnet-only

clean:
	@find $(LOG_DIR) -type f -delete 2>/dev/null || true
	@echo "Clean complete"
