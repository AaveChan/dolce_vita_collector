#!/bin/bash

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Load environment variables
source "$SCRIPT_DIR/.env"

LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/dolce_vita_collector_log.txt"

# Function to send Telegram messages
send_telegram_message() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message"
}

# Function to log messages and send to Telegram
log_message() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local message="[$timestamp] $1"
  echo "$message" | tee -a "$LOG_FILE"
  send_telegram_message "$message"
}

# Check for command line arguments
if [ "$1" == "--mainnet-only" ]; then
    NETWORKS=("MAINNET")
    log_message "🔄 Starting Dolce Vita Collector script (MAINNET only)"
elif [ "$1" == "--l2s-only" ]; then
    NETWORKS=("AVALANCHE" "OPTIMISM" "POLYGON" "ARBITRUM" "METIS" "BASE" "GNOSIS" "BNB" "SCROLL")
    log_message "🔄 Starting Dolce Vita Collector script (L2s only)"
else
    log_message "❌ Error: Invalid or no argument provided. Use --mainnet-only or --l2s-only"
    exit 1
fi

# Run make clean
log_message "Running make clean"
make clean
if [ $? -ne 0 ]; then
  log_message "⚠️ Warning: make clean failed"
fi

# Run make fetch-reserves with a timeout of 180 seconds
log_message "Running make fetch-reserves (180s timeout)"
timeout 180 make fetch-reserves
FETCH_RESULT=$?
if [ $FETCH_RESULT -eq 124 ]; then
  log_message "❌ Error: make fetch-reserves timed out after 180 seconds"
  exit 1
elif [ $FETCH_RESULT -ne 0 ]; then
  log_message "❌ Error: make fetch-reserves failed with status: $FETCH_RESULT"
  exit 1
else
  log_message "✅ make fetch-reserves completed successfully"
fi

# Check if reserves.json exists and is not empty
if [ -f "$SCRIPT_DIR/logs/reserves.json" ] && [ -s "$SCRIPT_DIR/logs/reserves.json" ]; then
  log_message "✅ reserves.json exists and is not empty"
else
  log_message "❌ Error: reserves.json is missing or empty"
  exit 1
fi

# Run make mint for each network without checking for success
TOTAL_NETWORKS=${#NETWORKS[@]}
for ((i=0; i<$TOTAL_NETWORKS; i++)); do
  network=${NETWORKS[$i]}
  log_message "($((i+1))/$TOTAL_NETWORKS) Starting make mint for $network"
  timeout 180 make mint NETWORK=$network
  mint_result=$?
  if [ $mint_result -eq 0 ]; then
    log_message "($((i+1))/$TOTAL_NETWORKS) ✅ Completed make mint for $network successfully"
  elif [ $mint_result -eq 124 ]; then
    log_message "($((i+1))/$TOTAL_NETWORKS) ⏱️ make mint for $network timed out after 180 seconds"
  else
    log_message "($((i+1))/$TOTAL_NETWORKS) ❌ make mint for $network failed with exit code $mint_result"
  fi
done

log_message "🏁 Dolce Vita Collector script completed"