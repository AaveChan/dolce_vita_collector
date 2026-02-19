#!/bin/bash
set -euo pipefail
export PATH="$HOME/.foundry/bin:$PATH"

usage() {
  echo "Usage: $0 <rpc_url> <pool_address> <keyfile> [--legacy]" >&2
  exit 1
}

[[ $# -lt 3 ]] && usage

RPC_URL="$1"
POOL="$2"
KEYFILE="$3"
LEGACY_FLAG=""

if [[ "${4:-}" == "--legacy" ]]; then
  LEGACY_FLAG="--legacy"
fi

if [[ ! -f "$KEYFILE" ]]; then
  echo "FAIL: keyfile not found: $KEYFILE" >&2
  exit 1
fi

PRIVATE_KEY="$(cat "$KEYFILE")"

CALL_ERR=$(mktemp)
RESERVES=$(cast call "$POOL" "getReservesList()(address[])" --rpc-url "$RPC_URL" 2>"$CALL_ERR") || {
  echo "FAIL: getReservesList call failed — $(cat "$CALL_ERR")"
  rm -f "$CALL_ERR"
  exit 1
}
rm -f "$CALL_ERR"

if [[ -z "$RESERVES" || "$RESERVES" == "[]" ]]; then
  echo "SKIP: no reserves"
  exit 0
fi

SEND_ERR=$(mktemp)
SEND_OUTPUT=$(cast send "$POOL" "mintToTreasury(address[])" "$RESERVES" \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --json \
  $LEGACY_FLAG 2>"$SEND_ERR") || {
  echo "FAIL: cast send failed — $(cat "$SEND_ERR")"
  rm -f "$SEND_ERR"
  exit 1
}
rm -f "$SEND_ERR"

read -r TX_HASH TX_STATUS < <(python3 -c "
import json, sys
try:
    r = json.loads(sys.argv[1])
    print(r.get('transactionHash',''), r.get('status',''))
except Exception as e:
    print('', '', file=sys.stdout)
    print(f'json parse error: {e}', file=sys.stderr)
" "$SEND_OUTPUT")

if [[ -z "$TX_HASH" ]]; then
  echo "FAIL: could not parse tx hash from receipt"
  exit 1
fi

if [[ "$TX_STATUS" == "0x0" ]]; then
  echo "FAIL: tx reverted — $TX_HASH"
  exit 1
fi

echo "OK:$TX_HASH"
