#!/bin/sh
set -e

# Create JWT if it doesn't exist or is empty. Uses od because the op-reth
# image doesn't ship xxd; op-reth fails to start on an empty JWT file.
if [ ! -s "/shared/jwt.txt" ]; then
  echo "Creating JWT..."
  mkdir -p /shared
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > /shared/jwt.txt
fi

# Refuse to start on an op-geth datadir. op-reth stores its data in MDBX
# format and cannot read geth chaindata.
if [ -d "/reth/geth" ]; then
  echo "The directory at DATADIR_PATH contains op-geth data, which op-reth cannot use."
  echo "Point DATADIR_PATH at an empty directory to sync from scratch."
  exit 1
fi

# Bootstrap an empty datadir from a published snapshot instead of syncing from
# scratch. Enabled with OP_RETH__SNAPSHOT=true; skipped once /reth holds data.
# celo-reth selects the snapshots.celo.org manifest for --chain automatically
# (celo-sepolia / mainnet), so no URL is needed.
if [ "$OP_RETH__SNAPSHOT" = "true" ] && [ ! -d "/reth/db" ]; then
  if [ "$NODE_TYPE" = "full" ]; then
    SNAPSHOT_PRESET="--full"
  else
    SNAPSHOT_PRESET="--archive"
  fi
  echo "No data in /reth; downloading ${SNAPSHOT_PRESET} snapshot for ${OP_RETH__CHAIN}..."
  celo-reth download --datadir=/reth --chain="$OP_RETH__CHAIN" "$SNAPSHOT_PRESET"
fi

# Check if either OP_RETH__HISTORICAL_RPC or HISTORICAL_RPC_DATADIR_PATH is set and if so set the historical rpc option.
if [ -n "$OP_RETH__HISTORICAL_RPC" ] || [ -n "$HISTORICAL_RPC_DATADIR_PATH" ] ; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --rollup.historicalrpc=${OP_RETH__HISTORICAL_RPC:-http://historical-rpc-node:8545}"
fi

# Permanent connections to well-known nodes, not subject to the peer limit.
if [ -n "$OP_RETH__TRUSTED_PEERS" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --trusted-peers=$OP_RETH__TRUSTED_PEERS"
fi

# A full node prunes historical state, an archive node keeps all of it.
if [ "$NODE_TYPE" = "full" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --full"
fi

# Operators forwarding logs to an aggregator can switch to structured output
# by adding --log.stdout.format=json to the command below.
# Start op-reth.
exec celo-reth node \
  --chain="$OP_RETH__CHAIN" \
  --datadir=/reth \
  --storage.v2=true \
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
  --metrics=0.0.0.0:9001 \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/shared/jwt.txt \
  --rollup.sequencer="$OP_RETH__SEQUENCER_URL" \
  --rollup.disable-tx-pool-gossip \
  --bootnodes="$OP_RETH__BOOTNODES" \
  --port="${PORT__OP_RETH_P2P:-30303}" \
  --discovery.port="${PORT__OP_RETH_P2P:-30303}" \
  --discovery.v5.port="${PORT__OP_RETH_P2P:-30303}" \
  --max-peers=100 \
  --nat="$OP_RETH__NAT" \
  --txpool.nolocals \
  --rpc.txfeecap=0 \
  -vvv \
  $EXTENDED_ARG $@
