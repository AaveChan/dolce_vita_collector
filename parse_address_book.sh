#!/usr/bin/env bash
set -euo pipefail

CSV_URL="https://raw.githubusercontent.com/bgd-labs/aave-address-book/main/safe.csv"
CACHE_FILE="${1:-/tmp/bgd_address_book.csv}"
CACHE_MAX_AGE=3600

declare -A CHAIN_MAP=(
  [1]=MAINNET [10]=OPTIMISM [56]=BNB [100]=GNOSIS [137]=POLYGON [146]=SONIC
  [1088]=METIS [1868]=SONEIUM [4326]=MEGAETH [5000]=MANTLE [8453]=BASE
  [9745]=PLASMA [42161]=ARBITRUM [42220]=CELO [43114]=AVALANCHE [57073]=INK
  [59144]=LINEA [534352]=SCROLL
)

declare -A CHAIN_PREFIX=(
  [1]=Ethereum [10]=Optimism [56]=BNB [100]=Gnosis [137]=Polygon [146]=Sonic
  [1088]=Metis [1868]=Soneium [4326]=MegaEth [5000]=Mantle [8453]=Base
  [9745]=Plasma [42161]=Arbitrum [42220]=Celo [43114]=Avalanche [57073]=Ink
  [59144]=Linea [534352]=Scroll
)

fetch_csv() {
  local need_download=true

  if [[ -f "$CACHE_FILE" ]]; then
    local age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE") ))
    if (( age < CACHE_MAX_AGE )); then
      need_download=false
    fi
  fi

  if $need_download; then
    if curl -sfL --max-time 15 -o "${CACHE_FILE}.tmp" "$CSV_URL"; then
      mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
    else
      rm -f "${CACHE_FILE}.tmp"
      if [[ -f "$CACHE_FILE" ]]; then
        echo "WARNING: download failed, using stale cache" >&2
      else
        echo "ERROR: download failed and no cache available" >&2
        exit 1
      fi
    fi
  fi
}

parse_pool_type() {
  local name="$1"
  local chain_id="$2"

  local body="${name#AaveV3}"
  body="${body% POOL}"

  local prefix="${CHAIN_PREFIX[$chain_id]}"
  local suffix="${body#"$prefix"}"

  if [[ -z "$suffix" ]]; then
    echo "MAIN"
  elif [[ "$suffix" == "Whitelabel" ]]; then
    echo "MAIN"
  else
    echo "${suffix^^}"
  fi
}

fetch_csv

grep -E ',AaveV3[A-Za-z]+ POOL,' "$CACHE_FILE" | while IFS=',' read -r address name chain_id; do
  chain_id="${chain_id%%$'\r'}"

  if [[ -z "${CHAIN_MAP[$chain_id]+x}" ]]; then
    continue
  fi

  network="${CHAIN_MAP[$chain_id]}"
  pool_type=$(parse_pool_type "$name" "$chain_id")

  echo "$network $chain_id $address $pool_type"
done
