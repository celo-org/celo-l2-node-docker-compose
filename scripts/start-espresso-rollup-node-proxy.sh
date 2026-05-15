#!/bin/sh
set -e

if [ "$ESPRESSO_ENABLED" != "true" ]; then
  echo "ESPRESSO_ENABLED is not set to 'true'"
  echo "Not starting espresso-rollup-node-proxy"
  exit
fi

trap 'echo "Received shutdown signal, exiting..."; exit 0' TERM INT

if [ -z "$TEE_BATCHER_ADDR" ]; then
  echo "Error: TEE_BATCHER_ADDR environment variable is not set."
  exit 1
fi

if [ -z "$BATCH_AUTH_ADDR" ]; then
  echo "Error: BATCH_AUTH_ADDR environment variable is not set."
  exit 1
fi

if [ -z "$ESPRESSO_QUERY_SERVICE_URL" ]; then
  echo "Error: ESPRESSO_QUERY_SERVICE_URL environment variable is not set."
  exit 1
fi

if [ -z "$ESPRESSO_LIGHT_CLIENT_ADDRESS" ]; then
  echo "Error: ESPRESSO_LIGHT_CLIENT_ADDRESS environment variable is not set."
  exit 1
fi

if [ -z "$ESPRESSO_INITIAL_HOTSHOT_HEIGHT" ]; then
  echo "Error: ESPRESSO_INITIAL_HOTSHOT_HEIGHT environment variable is not set."
  exit 1
fi

if [ -z "$OP_NODE__RPC_ENDPOINT" ]; then
  echo "Error: OP_NODE__RPC_ENDPOINT environment variable is not set."
  exit 1
fi

echo "Waiting for op-geth to be fully synced..."
while true; do
  RESULT=$(curl -sf -X POST -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://op-geth:8545 2>/dev/null) || { echo "op-geth not reachable yet, retrying in 30s..."; sleep 30 & wait $!; continue; }

  if echo "$RESULT" | grep -q '"result":false'; then
    echo "op-geth is fully synced. Starting espresso-rollup-node-proxy..."
    break
  fi

  echo "op-geth still syncing, retrying in 30s..."
  sleep 30 & wait $!
done

ESPRESSO_TAG_FLAG=""
if [ -n "$ESPRESSO_TAG" ]; then
  ESPRESSO_TAG_FLAG="--espresso-tag=$ESPRESSO_TAG"
fi

exec espresso-rollup-node-proxy \
  --listen-addr=:8080 \
  --store-file-path=/home/proxyuser/espresso_store.json \
  $ESPRESSO_TAG_FLAG \
  --full-node-execution-rpc=http://op-geth:8545 \
  --l1-rpc="$OP_NODE__RPC_ENDPOINT" \
  --initial-hotshot-height="$ESPRESSO_INITIAL_HOTSHOT_HEIGHT" \
  --op.full-node-consensus-rpc=http://op-node:9545 \
  --op.query-service-url="$ESPRESSO_QUERY_SERVICE_URL" \
  --op.light-client-address="$ESPRESSO_LIGHT_CLIENT_ADDRESS" \
  --op.batcher-address="$TEE_BATCHER_ADDR" \
  --op.verification-interval=10ms \
  --op.batch-authenticator-address="$BATCH_AUTH_ADDR" \
  "$@"
