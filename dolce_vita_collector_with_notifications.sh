#!/bin/bash

# === Dolce Vita Collector Script ===

export PATH="$HOME/.foundry/bin:$PATH"
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: .env not found at $SCRIPT_DIR/.env" >&2
  exit 1
fi
source "$SCRIPT_DIR/.env"

LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/dolce_vita_collector_log.txt"
mkdir -p "$LOG_DIR"

KEYFILE="$SCRIPT_DIR/.keyfile"
if [[ ! -f "$KEYFILE" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') - FATAL: .keyfile not found" >&2
  exit 1
fi
MINT_TIMEOUT=60
MAX_RETRIES=3
DELAY_BETWEEN=5
LEGACY_NETWORKS="METIS BNB CELO"

declare -a SUCCESS_POOLS=()
declare -a FAILED_POOLS=()
declare -a TIMEOUT_POOLS=()
declare -a SKIPPED_POOLS=()
declare -A TX_HASHES=()

# === Helpers ===

send_telegram_message() {
  local message=$1
  local response
  response=$(curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$message" \
    -d parse_mode="HTML" 2>&1)
  if ! echo "$response" | grep -q '"ok":true'; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - WARNING: Telegram send failed: $response" >> "$LOG_FILE"
  fi
}

log_message() {
  local message="$1"
  local notify="${2:-true}"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
  if [ "$notify" = "true" ]; then
    send_telegram_message "$message"
  fi
}

log_local() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

is_legacy() {
  local network="$1"
  [[ " $LEGACY_NETWORKS " == *" $network "* ]]
}

env_fallback_pools() {
  grep -oP '^([A-Z0-9_]+)_([A-Z0-9_]+)_POOL=' "$SCRIPT_DIR/.env" | while IFS= read -r match; do
    local varname="${match%=}"
    local network="${varname%%_*}"
    local rest="${varname#*_}"
    local pool_type="${rest%_POOL}"
    local pool_addr
    pool_addr=$(grep "^${varname}=" "$SCRIPT_DIR/.env" | cut -d= -f2 | tr -d "'\"")
    if [[ -n "$pool_addr" ]]; then
      echo "$network 0 $pool_addr $pool_type"
    fi
  done
}

# === Parse BGD address book (with .env fallback) ===

BGD_CACHE="$LOG_DIR/bgd_address_book.csv"
BGD_STDERR=$(mktemp)
POOL_CONFIG=$("$SCRIPT_DIR/parse_address_book.sh" "$BGD_CACHE" 2>"$BGD_STDERR")
BGD_EXIT=$?

if [[ -s "$BGD_STDERR" ]]; then
  log_local "BGD parser stderr: $(cat "$BGD_STDERR")"
fi
rm -f "$BGD_STDERR"

if [[ $BGD_EXIT -ne 0 ]] || [[ -z "$POOL_CONFIG" ]]; then
  log_local "BGD parser failed or returned empty; falling back to .env pool entries"
  POOL_CONFIG=$(env_fallback_pools)
  if [[ -z "$POOL_CONFIG" ]]; then
    log_message "BGD parser failed and no *_POOL entries in .env. Cannot proceed."
    exit 1
  fi
fi

# === Network selection ===

mapfile -t ALL_NETWORKS < <(echo "$POOL_CONFIG" | awk '{print $1}' | sort -u)

if [ "${1:-}" == "--mainnet-only" ]; then
  NETWORKS=("MAINNET")
  log_message "Starting Dolce Vita Collector (MAINNET only)"
elif [ "${1:-}" == "--l2s-only" ]; then
  NETWORKS=()
  for n in "${ALL_NETWORKS[@]}"; do
    [ "$n" != "MAINNET" ] && NETWORKS+=("$n")
  done
  log_message "Starting Dolce Vita Collector (${#NETWORKS[@]} L2s)"
else
  log_message "Invalid or no argument provided. Use --mainnet-only or --l2s-only"
  exit 1
fi

# === Mint to treasury ===

TOTAL_POOLS=0

for network in "${NETWORKS[@]}"; do
  RPC_VAR="RPC_${network}"
  RPC_URL="${!RPC_VAR:-}"

  if [[ -z "$RPC_URL" ]]; then
    log_local "Skipping $network: no RPC_${network} in .env"
    continue
  fi

  LEGACY_FLAG=""
  if is_legacy "$network"; then
    LEGACY_FLAG="--legacy"
  fi

  while IFS=' ' read -r _net _chain pool_addr pool_type; do
    POOL_LABEL="${network}/${pool_type}"
    TOTAL_POOLS=$((TOTAL_POOLS + 1))

    log_local "Starting mint for $POOL_LABEL ($pool_addr)"

    success=false
    MINT_EXIT=0
    MINT_OUTPUT=""

    for attempt in $(seq 1 $MAX_RETRIES); do
      MINT_OUTPUT=$(timeout "$MINT_TIMEOUT" "$SCRIPT_DIR/mint_via_cast.sh" "$RPC_URL" "$pool_addr" "$KEYFILE" $LEGACY_FLAG 2>&1)
      MINT_EXIT=$?

      if [[ $MINT_EXIT -eq 0 ]]; then
        if [[ "$MINT_OUTPUT" == OK:* ]]; then
          TX_HASH="${MINT_OUTPUT#OK:}"
          TX_HASHES[$POOL_LABEL]="$TX_HASH"
          SUCCESS_POOLS+=("$POOL_LABEL")
          log_local "Mint succeeded for $POOL_LABEL: $TX_HASH (attempt $attempt)"
        elif [[ "$MINT_OUTPUT" == SKIP:* ]]; then
          SKIPPED_POOLS+=("$POOL_LABEL")
          log_local "Mint skipped for $POOL_LABEL: $MINT_OUTPUT"
        else
          log_local "WARNING: unexpected output from mint_via_cast.sh for $POOL_LABEL: $MINT_OUTPUT"
          SUCCESS_POOLS+=("$POOL_LABEL")
        fi
        success=true
        break
      fi

      if [ $attempt -lt $MAX_RETRIES ]; then
        BACKOFF=$((DELAY_BETWEEN * attempt))
        log_local "Mint failed for $POOL_LABEL (attempt $attempt/$MAX_RETRIES), retrying in ${BACKOFF}s..."
        sleep $BACKOFF
      fi
    done

    if [ "$success" = false ]; then
      if [ $MINT_EXIT -eq 124 ]; then
        TIMEOUT_POOLS+=("$POOL_LABEL")
        log_message "$POOL_LABEL: Timeout after $MAX_RETRIES attempts"
      else
        FAILED_POOLS+=("$POOL_LABEL")
        ERROR_MSG=$(echo "$MINT_OUTPUT" | grep -i "error\|revert\|fail" | tail -1)
        log_local "Mint failed for $POOL_LABEL after $MAX_RETRIES attempts: $MINT_OUTPUT"
        log_message "$POOL_LABEL: Failed after $MAX_RETRIES attempts${ERROR_MSG:+ - $ERROR_MSG}"
      fi
    fi

  done < <(echo "$POOL_CONFIG" | grep "^${network} ")

  sleep $DELAY_BETWEEN
done

# === Summary Report ===

SUCCESS_COUNT=${#SUCCESS_POOLS[@]}
FAILED_COUNT=${#FAILED_POOLS[@]}
TIMEOUT_COUNT=${#TIMEOUT_POOLS[@]}
SKIPPED_COUNT=${#SKIPPED_POOLS[@]}

SUMMARY="<b>Dolce Vita Collector Complete</b>

Results: $SUCCESS_COUNT/$TOTAL_POOLS succeeded"

if [ $SKIPPED_COUNT -gt 0 ]; then
  SUMMARY+=$'\n'"Skipped (no reserves): $SKIPPED_COUNT"
fi

if [ $FAILED_COUNT -gt 0 ]; then
  SUMMARY+=$'\n'"Failed: ${FAILED_POOLS[*]}"
fi

if [ $TIMEOUT_COUNT -gt 0 ]; then
  SUMMARY+=$'\n'"Timeout: ${TIMEOUT_POOLS[*]}"
fi

if [ $SUCCESS_COUNT -gt 0 ] && [ ${#TX_HASHES[@]} -gt 0 ]; then
  SUMMARY+=$'\n\n'"Successful:"
  for pool_label in "${SUCCESS_POOLS[@]}"; do
    if [ -n "${TX_HASHES[$pool_label]:-}" ]; then
      SHORT_HASH="${TX_HASHES[$pool_label]:0:10}..."
      SUMMARY+=$'\n'"- $pool_label: <code>$SHORT_HASH</code>"
    fi
  done
fi

if [ ${#SUMMARY} -gt 4000 ]; then
  SUMMARY="${SUMMARY:0:3990}
...(truncated)"
fi

log_message "$SUMMARY"

if [ $SUCCESS_COUNT -eq 0 ] && [ $SKIPPED_COUNT -eq 0 ]; then
  exit 1
fi
