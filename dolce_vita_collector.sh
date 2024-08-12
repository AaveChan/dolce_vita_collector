#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Log file
LOG_FILE="${SCRIPT_DIR}/logs/dolce_vita_collector_log.txt"

# Ensure the logs directory exists
mkdir -p "${SCRIPT_DIR}/logs"

# Function to log messages
log_message() {
    echo "$(date +"%Y-%m-%d %H:%M:%S"): $1" | tee -a "$LOG_FILE"
}

# Function to execute and log a command with timeout
execute_command_with_timeout() {
    local COMMAND="$1"
    local TIMEOUT=180  # 180 seconds = 3 minutes

    log_message "Executing with ${TIMEOUT}s timeout: $COMMAND"
    
    timeout $TIMEOUT $COMMAND
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log_message "$COMMAND successful"
        return 0
    elif [ $EXIT_CODE -eq 124 ]; then
        log_message "$COMMAND timed out after ${TIMEOUT} seconds"
        return 1
    else
        log_message "$COMMAND failed with exit code $EXIT_CODE"
        return 1
    fi
}

# Check if MAINNET should be included
INCLUDE_MAINNET=0
if [ "$1" == "--include-mainnet" ]; then
    INCLUDE_MAINNET=1
fi

# Array of networks
NETWORKS=(
    "AVALANCHE"
    "OPTIMISM"
    "POLYGON"
    "ARBITRUM"
    "METIS"
    "BASE"
    "GNOSIS"
    "BNB"
    "SCROLL"
)

# Add MAINNET if flag is set
if [ $INCLUDE_MAINNET -eq 1 ]; then
    NETWORKS+=("MAINNET")
fi

# Main execution
log_message "Script execution started"

# Execute make clean
execute_command_with_timeout "make clean"

# Execute make fetch-reserves and wait for it to complete
if execute_command_with_timeout "make fetch-reserves"; then
    log_message "make fetch-reserves completed successfully. Proceeding with minting."

    log_message "Starting minting process for all networks"

    for NETWORK in "${NETWORKS[@]}"; do
        log_message "Processing $NETWORK"
        
        COMMAND="make mint NETWORK=$NETWORK"
        if execute_command_with_timeout "$COMMAND"; then
            log_message "Minting successful for $NETWORK"
        else
            log_message "Minting failed or timed out for $NETWORK. Moving to next network."
        fi
        
        echo "----------------------------------------"
    done

    log_message "Minting process completed for all networks"
else
    log_message "make fetch-reserves failed or timed out. Aborting minting process."
fi

log_message "Script execution completed"

exit 0