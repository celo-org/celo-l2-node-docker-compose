#!/bin/sh
set -e

# In-container paths. docker-compose bind-mounts the host DATADIR_PATH and
# PROOFS_HISTORY_DATADIR_PATH onto these.
DATADIR=/reth
PROOFS_STORAGE_PATH=/proofs

# Create JWT if it doesn't exist or is empty. Uses od because the op-reth
# image doesn't ship xxd; op-reth fails to start on an empty JWT file.
if [ ! -s "/shared/jwt.txt" ]; then
  echo "Creating JWT..."
  mkdir -p /shared
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > /shared/jwt.txt
fi

# Refuse to start on an op-geth datadir. op-reth stores its data in MDBX
# format and cannot read geth chaindata.
if [ -d "$DATADIR/geth" ]; then
  echo "The directory at DATADIR_PATH contains op-geth data, which op-reth cannot use."
  echo "Point DATADIR_PATH at an empty directory to sync from scratch."
  exit 1
fi

# Bootstrap an empty datadir from a published snapshot instead of syncing from
# scratch. On by default (OP_RETH__SNAPSHOT=true); set it to false to sync from
# genesis. Skipped once /reth already holds data. celo-reth selects the
# snapshots.celo.org manifest for --chain automatically (celo-sepolia / mainnet).
if [ "$OP_RETH__SNAPSHOT" = "true" ] && [ ! -d "$DATADIR/db" ]; then
  # NODE_TYPE doubles as the snapshot tier, matching celo-reth's download
  # presets: minimal | full | archive. Defaults to full.
  # ponytail: no validation of the value — celo-reth rejects a bad --<tier>.
  SNAPSHOT_PRESET="--${NODE_TYPE:-full}"
  echo "No data in $DATADIR; downloading ${SNAPSHOT_PRESET} snapshot for ${OP_RETH__CHAIN}..."
  celo-reth download --datadir="$DATADIR" --chain="$OP_RETH__CHAIN" "$SNAPSHOT_PRESET"
fi

# Check if either OP_RETH__HISTORICAL_RPC or HISTORICAL_RPC_DATADIR_PATH is set and if so set the historical rpc option.
if [ -n "$OP_RETH__HISTORICAL_RPC" ] || [ -n "$HISTORICAL_RPC_DATADIR_PATH" ] ; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --rollup.historicalrpc=${OP_RETH__HISTORICAL_RPC:-http://historical-rpc-node:8545}"
fi

# Permanent connections to well-known nodes, not subject to the peer limit.
if [ -n "$OP_RETH__TRUSTED_PEERS" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --trusted-peers=$OP_RETH__TRUSTED_PEERS"
fi

# NODE_TYPE also selects reth's prune profile: --minimal (most aggressive) or
# --full. An archive node passes no flag and retains all historical state.
if [ "$NODE_TYPE" != "archive" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --${NODE_TYPE:-full}"
fi

# Historical proofs (deep eth_getProof within a bounded window). When enabled,
# initialize the proofs storage against the datadir before starting the node,
# then run with --proofs-history. The storage must be anchored on a datadir
# synced past genesis: anchoring at genesis wedges the node with repeated
# StateRootMismatch errors (the packed trie is only materialized once the node
# executes blocks).
#
# The synced head lives in static files, not the MDBX CanonicalHeaders table, so
# read it from the Headers static-file block range that `db stats` reports (e.g.
# "0..=28493895"). The range start is the genesis block (0 on Sepolia, the L2
# migration block on Mainnet) and the end is the head; head > genesis means
# synced past genesis. (The static-file *filenames* use fixed 500k ranges and
# overshoot the real head, so we read the range `db stats` gets from each file's
# header instead.) It fails closed (skip, run without proofs) so an un-synced
# node never anchors proofs at genesis.
if [ "$OP_RETH__PROOFS_HISTORY_ENABLED" = "true" ]; then
  PROOFS_READY=false
  RANGE="$(celo-reth db --datadir="$DATADIR" --chain="$OP_RETH__CHAIN" stats 2>/dev/null |
    grep -E '^\|[[:space:]]*Headers[[:space:]]*\|[[:space:]]*[0-9]+\.\.=[0-9]+' |
    grep -oE '[0-9]+\.\.=[0-9]+' | head -1 || true)"
  GENESIS_BLOCK="$(printf '%s' "$RANGE" | grep -oE '[0-9]+' | head -1)"
  HEAD_BLOCK="$(printf '%s' "$RANGE" | grep -oE '[0-9]+' | tail -1)"
  if [ -n "$HEAD_BLOCK" ] && [ -n "$GENESIS_BLOCK" ] && [ "$HEAD_BLOCK" -gt "$GENESIS_BLOCK" ]; then
    # proofs init is idempotent: it no-ops when the storage already has its
    # anchor, so restarts do not re-backfill.
    echo "Datadir synced past genesis (head ${HEAD_BLOCK} > genesis ${GENESIS_BLOCK}); ensuring proofs history is initialized (idempotent)..."
    if celo-reth proofs init --datadir="$DATADIR" --chain="$OP_RETH__CHAIN" --proofs-history.storage-path="$PROOFS_STORAGE_PATH" --proofs-history.storage-version=v2; then
      PROOFS_READY=true
    else
      echo "ERROR: 'celo-reth proofs init' failed; starting op-reth WITHOUT historical proofs. Investigate and restart to retry."
    fi
  else
    echo "WARNING: op-reth datadir is not synced past genesis yet (head=${HEAD_BLOCK:-unknown}); skipping proofs history."
    echo "WARNING: op-reth will start without it. Once it has synced, restart to initialize and enable proofs."
  fi
  if [ "$PROOFS_READY" = "true" ]; then
    export EXTENDED_ARG="${EXTENDED_ARG:-} --proofs-history --proofs-history.storage-path=$PROOFS_STORAGE_PATH --proofs-history.storage-version=v2 --proofs-history.window=${OP_RETH__PROOFS_HISTORY_WINDOW:-1296000}"
    echo "Historical proofs enabled (storage=$PROOFS_STORAGE_PATH, window=${OP_RETH__PROOFS_HISTORY_WINDOW:-1296000}); starting op-reth..."
  fi
fi

# Operators forwarding logs to an aggregator can switch to structured output
# by adding --log.stdout.format=json to the command below.
# Start op-reth.
exec celo-reth node \
  --chain="$OP_RETH__CHAIN" \
  --datadir="$DATADIR" \
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
