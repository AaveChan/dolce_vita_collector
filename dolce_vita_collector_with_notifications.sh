#!/bin/bash

# === Dolce Vita Collector Script ===

# Get the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# Load environment variables
source "$SCRIPT_DIR/.env"

# Log setup
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/dolce_vita_collector_log.txt"
mkdir -p "$LOG_DIR"

# === Helpers ===

send_telegram_message() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$message"
}

log_message() {
  local message="$1"
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
  send_telegram_message "$message"
}

# === Network Selection ===

if [ "$1" == "--mainnet-only" ]; then
  NETWORKS=("MAINNET")
  log_message "🔄 Starting Dolce Vita Collector (MAINNET only)"
elif [ "$1" == "--l2s-only" ]; then
  NETWORKS=("AVALANCHE" "OPTIMISM" "POLYGON" "ARBITRUM" "METIS" "BASE" "GNOSIS" "BNB" "SCROLL" "LINEA" "SONIC" "CELO" "PLASMA" "SONEIUM" "MANTLE" "MEGAETH" "INK")
  log_message "🔄 Starting Dolce Vita Collector (L2s only)"
else
  log_message "❌ Invalid or no argument provided. Use --mainnet-only or --l2s-only"
  exit 1
fi

# === Run make clean ===
log_message "🧹 Running make clean"
make clean
if [ $? -ne 0 ]; then
  log_message "⚠️ Warning: make clean failed"
fi

# === Fetch reserves ===
log_message "📥 Running make fetch-reserves (timeout: 180s)"
timeout 180 make fetch-reserves
FETCH_RESULT=$?

if [ $FETCH_RESULT -eq 124 ]; then
  log_message "❌ Error: fetch-reserves timed out after 180 seconds"
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
for network in "${NETWORKS[@]}"; do
  log_message "🚀 Running make mint for $network"
  timeout 180 make mint NETWORK="$network"
  if [ $? -eq 124 ]; then
    log_message "⏰ Timeout: mint for $network took too long (180s)"
  else
    log_message "✅ Completed mint for $network"
  fi
done

log_message "🏁 Dolce Vita Collector run completed"
