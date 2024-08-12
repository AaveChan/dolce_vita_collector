#!/bin/bash

# Get the directory of the script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Load environment variables
source "$SCRIPT_DIR/.env"

LOG_DIR="/var/log/dolce_vita_collector"
COUNTER_FILE="${LOG_DIR}/counter.log"
MAX_LINES=2000

# Function to send Telegram messages
send_telegram_message() {
  local message=$1
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message"
}

# Initialize the counter and date if they don't exist
if [ ! -f $COUNTER_FILE ]; then
  mkdir -p "$LOG_DIR"
  echo "Loop Counter: 0" > $COUNTER_FILE
  echo "Last Run: Never" >> $COUNTER_FILE
fi

# Read the current counter value and date of last run
counter=$(grep -o '[0-9]\+' $COUNTER_FILE | head -n 1)
last_run=$(grep 'Last Run:' $COUNTER_FILE)

# Increment the counter
counter=$((counter + 1))
current_date=$(date '+%Y-%m-%d %H:%M:%S')

# Update the counter file with the new counter and date
echo "Loop Counter: $counter" > $COUNTER_FILE
echo "Last Run: $current_date" >> $COUNTER_FILE

# Determine if this is a weekly run (with MAINNET)
if [[ "$1" == "--include-mainnet" ]]; then
  run_type="Weekly (including MAINNET)"
  log_file="${LOG_DIR}/weekly.log"
else
  run_type="Daily"
  log_file="${LOG_DIR}/daily.log"
fi

# Log the start of the process
{
  echo "🚀 Starting Dolce Vita Collector $run_type script..."
  echo "Loop Counter: $counter"
  echo "Last Run: $current_date"
  
  send_telegram_message "🚀 Starting Dolce Vita Collector $run_type script. Loop Counter: $counter. Last Run: $current_date"

  # Run the original script
  if "$SCRIPT_DIR/dolce_vita_collector.sh" "$@"; then
    echo "🎉 Dolce Vita Collector $run_type script completed successfully."
    send_telegram_message "🎉 Dolce Vita Collector $run_type script completed successfully. Loop Counter: $counter."
  else
    echo "⚠️ Dolce Vita Collector $run_type script encountered errors."
    send_telegram_message "⚠️ Dolce Vita Collector $run_type script encountered errors. Loop Counter: $counter."
  fi

  # Truncate the log file to keep only the last $MAX_LINES lines
  tail -n $MAX_LINES $log_file > $log_file.tmp && mv $log_file.tmp $log_file

  # Concatenate the counter file and the log file
  cat $COUNTER_FILE $log_file > $log_file.tmp && mv $log_file.tmp $log_file
} | ts '[%Y-%m-%d %H:%M:%S]' >> $log_file
