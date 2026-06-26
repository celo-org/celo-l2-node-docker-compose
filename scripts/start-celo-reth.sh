#!/bin/sh
set -e

# Create JWT if it doesn't exist
if [ ! -f "/shared/jwt.txt" ]; then
  echo "Creating JWT..."
  mkdir -p /shared
  openssl rand -hex 32 > /shared/jwt.txt
fi

# Determine the chain spec: use genesis.json for custom chains, otherwise built-in "celo"
if [ -n "${IS_CUSTOM_CHAIN}" ] && [ -f /chainconfig/genesis.json ]; then
  CHAIN_ARG="--chain=/chainconfig/genesis.json"
else
  CHAIN_ARG="--chain=celo"
fi

# Check if either OP_GETH__HISTORICAL_RPC or HISTORICAL_RPC_DATADIR_PATH is set and if so set the historical rpc option.
if [ -n "$OP_GETH__HISTORICAL_RPC" ] || [ -n "$HISTORICAL_RPC_DATADIR_PATH" ] ; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --rollup.historicalrpc=${OP_GETH__HISTORICAL_RPC:-http://historical-rpc-node:8545}"
fi

if [ -n "$IPC_PATH" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --ipcpath=$IPC_PATH"
fi

# Init the datadir if it's a custom chain and the datadir is empty
if [ -n "${IS_CUSTOM_CHAIN}" ] && [ -z "$(ls -A "$BEDROCK_DATADIR")" ]; then
  echo "Initializing custom chain genesis..."
  if [ ! -f /chainconfig/genesis.json ]; then
    echo "Missing genesis.json file: Either update the repo to pull the published genesis.json or migrate your Celo L1 datadir to generate genesis.json."
    exit 1
  fi
  celo-reth init $CHAIN_ARG --datadir="$BEDROCK_DATADIR"
fi

# In reth, --full enables pruning for a non-archive node.
# Without --full, reth keeps all historical state (archive mode).
FULL_ARG=""
if [ "$NODE_TYPE" = "full" ]; then
  FULL_ARG="--full"
fi

METRICS_ARGS="--metrics=0.0.0.0:9001"

# Start celo-reth.
exec celo-reth node \
  $CHAIN_ARG \
  --datadir="$BEDROCK_DATADIR" \
  $FULL_ARG \
  --http \
  --http.corsdomain="*" \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=web3,debug,eth,txpool,net \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.origins="*" \
  --ws.api=debug,eth,txpool,net,web3 \
  $METRICS_ARGS \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/shared/jwt.txt \
  --rollup.sequencer="$BEDROCK_SEQUENCER_HTTP" \
  --rollup.disable-tx-pool-gossip \
  --bootnodes="$GETH_BOOTNODES" \
  --port="${PORT__OP_GETH_P2P:-30303}" \
  --nat="$OP_GETH__NAT" \
  --txpool.nolocals \
  -vvv \
  $EXTENDED_ARG "$@"
