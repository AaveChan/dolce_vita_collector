#!/bin/bash
# Per-network reserves fetcher with retry
# Networks and pools auto-discovered from .env (RPC_* and *_POOL entries)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/.env"

export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Auto-discover networks from .env RPC_* entries
mapfile -t NETWORKS < <(grep -oP '^RPC_\K[A-Z0-9_]+(?==)' "$SCRIPT_DIR/.env")

if [ ${#NETWORKS[@]} -eq 0 ]; then
  echo "❌ No RPC_* entries found in .env"
  exit 1
fi

TIMEOUT_PER_NETWORK=${TIMEOUT_PER_NETWORK:-90}
MAX_RETRIES=${MAX_RETRIES:-2}

# Clean old fragments
rm -f "$LOG_DIR"/reserves_*.json

echo "🔄 Fetching reserves for ${#NETWORKS[@]} networks (sequential, ${TIMEOUT_PER_NETWORK}s timeout, $MAX_RETRIES retries)"

get_pools() {
  local network=$1
  grep -oP "^${network}_\K[A-Z0-9_]+(?=_POOL=)" "$SCRIPT_DIR/.env" | tr '\n' ',' | sed 's/,$//'
}

fetch_network() {
  local network=$1
  local logfile="$LOG_DIR/fetch_${network}.log"
  local pools
  pools=$(get_pools "$network")

  TARGET_NETWORK="$network" \
    TARGET_POOLS="$pools" \
    timeout "$TIMEOUT_PER_NETWORK" \
    forge script script/FetchReservesSingle.s.sol:FetchReservesSingleScript -vvvv \
    > "$logfile" 2>&1
}

succeeded=()
failed=()

for network in "${NETWORKS[@]}"; do
  if fetch_network "$network"; then
    if [ -f "$LOG_DIR/reserves_${network}.json" ] && [ -s "$LOG_DIR/reserves_${network}.json" ]; then
      succeeded+=("$network")
      echo "  ✅ $network"
    else
      failed+=("$network")
      echo "  ❌ $network (no output)"
    fi
  else
    failed+=("$network")
    echo "  ❌ $network"
  fi
done

echo "Pass 1: ${#succeeded[@]}/${#NETWORKS[@]}"

# Retry failed networks
retry=0
while [ ${#failed[@]} -gt 0 ] && [ $retry -lt $MAX_RETRIES ]; do
  retry=$((retry + 1))
  echo "🔁 Retry $retry/$MAX_RETRIES for ${#failed[@]} failed: ${failed[*]}"
  sleep 5

  retry_list=("${failed[@]}")
  failed=()

  for network in "${retry_list[@]}"; do
    if fetch_network "$network"; then
      if [ -f "$LOG_DIR/reserves_${network}.json" ] && [ -s "$LOG_DIR/reserves_${network}.json" ]; then
        succeeded+=("$network")
        echo "  ✅ $network recovered"
      else
        failed+=("$network")
      fi
    else
      failed+=("$network")
      echo "  ❌ $network still failing"
    fi
  done
done

echo "✅ Final: ${#succeeded[@]}/${#NETWORKS[@]} — ${succeeded[*]}"
if [ ${#failed[@]} -gt 0 ]; then
  echo "❌ Still failed after retries: ${failed[*]}"
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

# Validate — require at least 14/N (allow some transient RPC failures)
MERGED_COUNT=$(python3 -c "import json; print(len(json.load(open('$LOG_DIR/reserves.json'))))")
MIN_NETWORKS=14

if [ "$MERGED_COUNT" -ge "$MIN_NETWORKS" ]; then
  echo "✅ reserves.json ready ($MERGED_COUNT networks)"
  exit 0
else
  echo "❌ Only $MERGED_COUNT networks succeeded (minimum: $MIN_NETWORKS)"
  exit 1
fi
