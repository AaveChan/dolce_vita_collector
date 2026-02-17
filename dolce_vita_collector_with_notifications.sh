#!/bin/bash

# === Dolce Vita Collector Script ===

# Ensure foundry is on PATH (cron/non-interactive shells don't source .bashrc)
export PATH="$HOME/.foundry/bin:$PATH"

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Load environment variables
source "$SCRIPT_DIR/.env"

# Log setup
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/dolce_vita_collector_log.txt"
mkdir -p "$LOG_DIR"

# Track results
declare -a SUCCESS_NETWORKS=()
declare -a FAILED_NETWORKS=()
declare -a TIMEOUT_NETWORKS=()
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

get_tx_hash() {
  local network=$1
  local chain_id

  case $network in
    MAINNET) chain_id=1 ;;
    AVALANCHE) chain_id=43114 ;;
    OPTIMISM) chain_id=10 ;;
    POLYGON) chain_id=137 ;;
    ARBITRUM) chain_id=42161 ;;
    BASE) chain_id=8453 ;;
    GNOSIS) chain_id=100 ;;
    BNB) chain_id=56 ;;
    SCROLL) chain_id=534352 ;;
    METIS) chain_id=1088 ;;
    LINEA) chain_id=59144 ;;
    SONIC) chain_id=146 ;;
    CELO) chain_id=42220 ;;
    PLASMA) chain_id=3693 ;;
    SONEIUM) chain_id=1868 ;;
    MANTLE) chain_id=5000 ;;
    MEGAETH) chain_id=6342 ;;
    INK) chain_id=57073 ;;
    *) return 1 ;;
  esac

  local broadcast_file="$SCRIPT_DIR/broadcast/MintToTreasury.s.sol/$chain_id/run-latest.json"
  if [ -f "$broadcast_file" ]; then
    grep -o '"hash": *"0x[a-fA-F0-9]*"' "$broadcast_file" | head -1 | sed 's/.*"0x/0x/' | tr -d '"'
  fi
}

# === Network Selection (auto-derived from .env RPC_* entries) ===

ALL_NETWORKS=($(grep -oP '^RPC_\K[A-Z0-9_]+(?==)' "$SCRIPT_DIR/.env"))

if [ "$1" == "--mainnet-only" ]; then
  NETWORKS=("MAINNET")
  log_message "🔄 Starting Dolce Vita Collector (MAINNET only)"
elif [ "$1" == "--l2s-only" ]; then
  NETWORKS=()
  for n in "${ALL_NETWORKS[@]}"; do
    [ "$n" != "MAINNET" ] && NETWORKS+=("$n")
  done
  log_message "🔄 Starting Dolce Vita Collector (${#NETWORKS[@]} L2s)"
else
  log_message "❌ Invalid or no argument provided. Use --mainnet-only or --l2s-only"
  exit 1
fi

# === Clean broadcast artifacts (reserves are freshly fetched each run) ===
find "$SCRIPT_DIR/broadcast" -mindepth 1 -delete 2>/dev/null || true

# === Fetch reserves ===
log_message "📥 Running make fetch-reserves (parallel, timeout: 300s)"
timeout 300 make fetch-reserves
FETCH_RESULT=$?

if [ $FETCH_RESULT -eq 124 ]; then
  log_message "❌ Error: fetch-reserves timed out after 300 seconds"
  exit 1
elif [ $FETCH_RESULT -ne 0 ]; then
  log_message "❌ Error: fetch-reserves failed (status: $FETCH_RESULT)"
  exit 1
else
  log_message "✅ Reserves fetched successfully"
fi

# === Check reserves.json ===
if [ -f "$LOG_DIR/reserves.json" ] && [ -s "$LOG_DIR/reserves.json" ]; then
  log_message "✅ reserves.json exists and is not empty"
else
  log_message "❌ Error: reserves.json is missing or empty"
  exit 1
fi

# === Mint to treasury for each network ===
MAX_RETRIES=3
DELAY_BETWEEN=8

for network in "${NETWORKS[@]}"; do
  log_local "Starting mint for $network"

  success=false
  for attempt in $(seq 1 $MAX_RETRIES); do
    MINT_OUTPUT=$(timeout 180 make mint NETWORK="$network" 2>&1)
    MINT_EXIT=$?

    if [ $MINT_EXIT -eq 0 ]; then
      TX_HASH=$(get_tx_hash "$network")
      if [ -n "$TX_HASH" ]; then
        TX_HASHES[$network]="$TX_HASH"
      fi
      SUCCESS_NETWORKS+=("$network")
      log_local "Mint succeeded for $network${TX_HASH:+ : $TX_HASH} (attempt $attempt)"
      success=true
      break
    fi

    if [ $attempt -lt $MAX_RETRIES ]; then
      BACKOFF=$((DELAY_BETWEEN * attempt))
      log_local "Mint failed for $network (attempt $attempt/$MAX_RETRIES), retrying in ${BACKOFF}s..."
      sleep $BACKOFF
    fi
  done

  if [ "$success" = false ]; then
    if [ $MINT_EXIT -eq 124 ]; then
      TIMEOUT_NETWORKS+=("$network")
      log_message "⏰ $network: Timeout after $MAX_RETRIES attempts"
    else
      FAILED_NETWORKS+=("$network")
      ERROR_MSG=$(echo "$MINT_OUTPUT" | grep -i "error\|revert\|fail" | tail -1)
      log_local "Mint failed for $network after $MAX_RETRIES attempts: $MINT_OUTPUT"
      log_message "❌ $network: Failed after $MAX_RETRIES attempts${ERROR_MSG:+ - $ERROR_MSG}"
    fi
  fi

  # Throttle between chains to avoid Alchemy rate limits
  sleep $DELAY_BETWEEN
done

# === Summary Report ===
TOTAL=${#NETWORKS[@]}
SUCCESS_COUNT=${#SUCCESS_NETWORKS[@]}
FAILED_COUNT=${#FAILED_NETWORKS[@]}
TIMEOUT_COUNT=${#TIMEOUT_NETWORKS[@]}

SUMMARY="🏁 <b>Dolce Vita Collector Complete</b>

📊 Results: $SUCCESS_COUNT/$TOTAL succeeded"

if [ $FAILED_COUNT -gt 0 ]; then
  SUMMARY+=$'\n'"❌ Failed: ${FAILED_NETWORKS[*]}"
fi

if [ $TIMEOUT_COUNT -gt 0 ]; then
  SUMMARY+=$'\n'"⏰ Timeout: ${TIMEOUT_NETWORKS[*]}"
fi

if [ $SUCCESS_COUNT -gt 0 ] && [ ${#TX_HASHES[@]} -gt 0 ]; then
  SUMMARY+=$'\n\n'"✅ Successful:"
  for network in "${SUCCESS_NETWORKS[@]}"; do
    if [ -n "${TX_HASHES[$network]}" ]; then
      SHORT_HASH="${TX_HASHES[$network]:0:10}..."
      SUMMARY+=$'\n'"• $network: <code>$SHORT_HASH</code>"
    fi
  done
fi

log_message "$SUMMARY"

# Exit 0 on partial failures (summary already sent via Telegram)
# Exit 1 only if ALL networks failed (total infrastructure issue)
if [ $SUCCESS_COUNT -eq 0 ]; then
  exit 1
fi
