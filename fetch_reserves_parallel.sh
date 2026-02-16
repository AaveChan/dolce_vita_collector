#!/bin/bash
# Parallel reserves fetcher — runs one forge call per network concurrently
# Replaces the monolithic FetchReserves.s.sol that times out with 18+ networks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/.env"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

NETWORKS=(
  MAINNET AVALANCHE OPTIMISM POLYGON ARBITRUM BASE GNOSIS BNB
  SCROLL METIS LINEA SONIC CELO PLASMA SONEIUM MANTLE MEGAETH INK
)

MAX_PARALLEL=${MAX_PARALLEL:-6}
TIMEOUT_PER_NETWORK=${TIMEOUT_PER_NETWORK:-60}

# Clean old fragments
rm -f "$LOG_DIR"/reserves_*.json

echo "🔄 Fetching reserves for ${#NETWORKS[@]} networks (max $MAX_PARALLEL parallel, ${TIMEOUT_PER_NETWORK}s timeout each)"

# Track PIDs and results
declare -A PIDS
declare -a SUCCEEDED=()
declare -a FAILED=()

fetch_network() {
  local network=$1
  local logfile="$LOG_DIR/fetch_${network}.log"
  
  TARGET_NETWORK="$network" \
  FOUNDRY_DISABLE_NIGHTLY_WARNING=1 \
    timeout "$TIMEOUT_PER_NETWORK" \
    forge script script/FetchReservesSingle.s.sol:FetchReservesSingleScript -vvvv \
    > "$logfile" 2>&1
}

# Launch in batches
running=0
for network in "${NETWORKS[@]}"; do
  fetch_network "$network" &
  PIDS[$network]=$!
  running=$((running + 1))

  if [ $running -ge $MAX_PARALLEL ]; then
    # Wait for any one to finish
    wait -n 2>/dev/null || true
    running=$((running - 1))
  fi
done

# Wait for all remaining
for network in "${NETWORKS[@]}"; do
  pid=${PIDS[$network]}
  if wait "$pid" 2>/dev/null; then
    if [ -f "$LOG_DIR/reserves_${network}.json" ] && [ -s "$LOG_DIR/reserves_${network}.json" ]; then
      SUCCEEDED+=("$network")
    else
      FAILED+=("$network")
    fi
  else
    FAILED+=("$network")
  fi
done

echo "✅ Succeeded: ${#SUCCEEDED[@]}/${#NETWORKS[@]} — ${SUCCEEDED[*]}"
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "❌ Failed: ${FAILED[*]}"
fi

# Merge fragments into single reserves.json
python3 -c "
import json, glob, os

merged = {}
for f in sorted(glob.glob('$LOG_DIR/reserves_*.json')):
    network = os.path.basename(f).replace('reserves_','').replace('.json','')
    try:
        data = json.loads(open(f).read())
        if data:  # skip empty objects
            merged[network] = data
    except Exception as e:
        print(f'Warning: could not parse {f}: {e}')

with open('$LOG_DIR/reserves.json', 'w') as out:
    json.dump(merged, out)

print(f'Merged {len(merged)} networks into reserves.json')
"

# Validate
if [ -f "$LOG_DIR/reserves.json" ] && [ -s "$LOG_DIR/reserves.json" ]; then
  echo "✅ reserves.json ready"
  exit 0
else
  echo "❌ reserves.json missing or empty"
  exit 1
fi
