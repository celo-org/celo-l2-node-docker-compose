#!/bin/sh
set -e

# Map NETWORK_NAME to the superchain-registry network name used by --op-network.
case "$NETWORK_NAME" in
  mainnet) CELO_NETWORK=celo-mainnet ;;
  celo-sepolia) CELO_NETWORK=celo-sepolia ;;
  *) echo "Unknown NETWORK_NAME: '$NETWORK_NAME'"; exit 1 ;;
esac

# Create JWT if it doesn't exist
if [ ! -f "/shared/jwt.txt" ]; then
  echo "Creating JWT..."
  mkdir -p /shared
  dd bs=1 count=32 if=/dev/urandom of=/dev/stdout | xxd -p -c 32 > /shared/jwt.txt
fi

# Check if either OP_GETH__HISTORICAL_RPC or HISTORICAL_RPC_DATADIR_PATH is set and if so set the historical rpc option.
if [ -n "$OP_GETH__HISTORICAL_RPC" ] || [ -n "$HISTORICAL_RPC_DATADIR_PATH" ] ; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --rollup.historicalrpc=${OP_GETH__HISTORICAL_RPC:-http://historical-rpc-node:8545}"
fi

if [ -n "$IPC_PATH" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --ipcpath=$IPC_PATH"
fi

# Determine syncmode based on NODE_TYPE
if [ -z "$OP_GETH__SYNCMODE" ]; then
  if [ "$NODE_TYPE" = "full" ]; then
    export OP_GETH__SYNCMODE="snap"
  else
    export OP_GETH__SYNCMODE="full"
  fi
fi

METRICS_ARGS="--metrics"
if [ "$MONITORING_ENABLED" = "true" ]; then
  METRICS_ARGS="$METRICS_ARGS \
    --metrics.influxdb \
    --metrics.influxdb.endpoint=http://influxdb:8086 \
    --metrics.influxdb.database=opgeth"
fi

# Start op-geth.
exec geth \
  --datadir="$BEDROCK_DATADIR" \
  --op-network="$CELO_NETWORK" \
  --http \
  --http.corsdomain="*" \
  --http.vhosts="*" \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=web3,debug,eth,txpool,net,engine \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.origins="*" \
  --ws.api=debug,eth,txpool,net,engine,web3 \
  $METRICS_ARGS \
  --syncmode="$OP_GETH__SYNCMODE" \
  --gcmode="$NODE_TYPE" \
  --authrpc.vhosts="*" \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/shared/jwt.txt \
  --rollup.sequencerhttp="$BEDROCK_SEQUENCER_HTTP" \
  --rollup.disabletxpoolgossip=true \
  --bootnodes="$GETH_BOOTNODES" \
  --port="${PORT__OP_GETH_P2P:-39393}" \
  --discovery.port="${PORT__OP_GETH_P2P:-39393}" \
  --nat=$OP_GETH__NAT \
  --snapshot=true \
  --verbosity=3 \
  --history.transactions=0 \
  --txpool.nolocals \
  $EXTENDED_ARG $@

