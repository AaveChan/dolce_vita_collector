#!/bin/bash
# Parallel reserves fetcher with retry — runs one forge call per network concurrently
# Replaces the monolithic FetchReserves.s.sol that times out with 18+ networks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/.env"

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

NETWORKS=(
  MAINNET AVALANCHE OPTIMISM POLYGON ARBITRUM BASE GNOSIS BNB
  SCROLL METIS LINEA SONIC CELO PLASMA SONEIUM MANTLE MEGAETH INK
)

MAX_PARALLEL=${MAX_PARALLEL:-3}
TIMEOUT_PER_NETWORK=${TIMEOUT_PER_NETWORK:-90}
MAX_RETRIES=${MAX_RETRIES:-2}
STAGGER_MS=${STAGGER_MS:-2}  # seconds between launches to avoid rate limit bursts

# Clean old fragments
rm -f "$LOG_DIR"/reserves_*.json

echo "🔄 Fetching reserves for ${#NETWORKS[@]} networks (max $MAX_PARALLEL parallel, ${TIMEOUT_PER_NETWORK}s timeout, $MAX_RETRIES retries)"

fetch_network() {
  local network=$1
  local logfile="$LOG_DIR/fetch_${network}.log"
  
  TARGET_NETWORK="$network" \
    timeout "$TIMEOUT_PER_NETWORK" \
    forge script script/FetchReservesSingle.s.sol:FetchReservesSingleScript -vvvv \
    > "$logfile" 2>&1
}

run_batch() {
  local -n networks_ref=$1
  local -n succeeded_ref=$2
  local -n failed_ref=$3
  
  declare -A PIDS
  local running=0
  
  for network in "${networks_ref[@]}"; do
    fetch_network "$network" &
    PIDS[$network]=$!
    running=$((running + 1))
    
    # Stagger to avoid Alchemy rate limit bursts
    sleep "$STAGGER_MS"

    if [ $running -ge $MAX_PARALLEL ]; then
      wait -n 2>/dev/null || true
      running=$((running - 1))
    fi
  done

  # Wait for all
  for network in "${networks_ref[@]}"; do
    pid=${PIDS[$network]}
    if wait "$pid" 2>/dev/null; then
      if [ -f "$LOG_DIR/reserves_${network}.json" ] && [ -s "$LOG_DIR/reserves_${network}.json" ]; then
        succeeded_ref+=("$network")
      else
        failed_ref+=("$network")
      fi
    else
      failed_ref+=("$network")
    fi
  done
}

# === Pass 1 ===
declare -a SUCCEEDED=()
declare -a FAILED=()
run_batch NETWORKS SUCCEEDED FAILED

echo "Pass 1: ${#SUCCEEDED[@]}/${#NETWORKS[@]} succeeded"

# === Retry failed networks sequentially (more reliable) ===
retry=0
while [ ${#FAILED[@]} -gt 0 ] && [ $retry -lt $MAX_RETRIES ]; do
  retry=$((retry + 1))
  echo "🔁 Retry $retry/${MAX_RETRIES} for ${#FAILED[@]} failed: ${FAILED[*]}"
  sleep 5  # cool down before retry
  
  declare -a RETRY_LIST=("${FAILED[@]}")
  FAILED=()
  
  # Retry one at a time (sequential) to avoid rate limits
  for network in "${RETRY_LIST[@]}"; do
    if fetch_network "$network"; then
      if [ -f "$LOG_DIR/reserves_${network}.json" ] && [ -s "$LOG_DIR/reserves_${network}.json" ]; then
        SUCCEEDED+=("$network")
        echo "  ✅ $network recovered"
      else
        FAILED+=("$network")
      fi
    else
      FAILED+=("$network")
      echo "  ❌ $network still failing"
    fi
    sleep 2
  done
done

echo "✅ Final: ${#SUCCEEDED[@]}/${#NETWORKS[@]} — ${SUCCEEDED[*]}"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "❌ Still failed after retries: ${FAILED[*]}"
fi

# Merge fragments into single reserves.json
python3 -c "
import json, glob, os

merged = {}
for f in sorted(glob.glob('$LOG_DIR/reserves_*.json')):
    network = os.path.basename(f).replace('reserves_','').replace('.json','')
    try:
        data = json.loads(open(f).read())
        if data:
            merged[network] = data
    except Exception as e:
        print(f'Warning: could not parse {f}: {e}')

with open('$LOG_DIR/reserves.json', 'w') as out:
    json.dump(merged, out)

print(f'Merged {len(merged)} networks into reserves.json')
"

# Validate — require at least 14/18 (allow some transient RPC failures)
MERGED_COUNT=$(python3 -c "import json; print(len(json.load(open('$LOG_DIR/reserves.json'))))")
MIN_NETWORKS=14

if [ "$MERGED_COUNT" -ge "$MIN_NETWORKS" ]; then
  echo "✅ reserves.json ready ($MERGED_COUNT networks)"
  exit 0
else
  echo "❌ Only $MERGED_COUNT networks succeeded (minimum: $MIN_NETWORKS)"
  exit 1
fi
