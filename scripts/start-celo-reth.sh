#!/bin/sh
# Mirrors infrastructure/ansible/roles/celo_op_reth/templates/run-op-reth.sh.j2
# (devops Hetzner deployment) trimmed to the sepolia full-node case: no
# historical-rpc (sepolia is an L2-native chain), no proofs-history ExEx
# (PoC), no engine RAM tuning (default suffices for a non-archive node).
set -e

# JWT bootstrap. Shared volume with op-node (and op-geth, when running).
# `-s` regenerates if a previous run left a zero-byte file. Uses od+tr
# instead of xxd: the celo-kona-reth image (ubuntu:24.04 + ca-certs + wget)
# doesn't ship xxd, and `set -e` doesn't catch failures inside pipelines —
# the missing tool silently produced an empty JWT and reth crashed with
# "0 digits key provided".
if [ ! -s "/shared/jwt.txt" ]; then
  echo "Creating JWT..."
  mkdir -p /shared
  od -An -N32 -tx1 /dev/urandom | tr -d ' \n' > /shared/jwt.txt
fi

# Reuse OP_GETH__NAT so a single env var configures discovery for either EL.
# celo-reth accepts: any|none|upnp|publicip|extip:<IP>|stun:<IP:PORT>.
NAT_ARG=""
if [ -n "$OP_GETH__NAT" ]; then
  NAT_ARG="--nat=$OP_GETH__NAT"
fi

TRUSTED_PEERS_ARG=""
if [ -n "$CELO_RETH__TRUSTED_PEERS" ]; then
  TRUSTED_PEERS_ARG="--trusted-peers=$CELO_RETH__TRUSTED_PEERS"
fi

# Honor NODE_TYPE so celo-reth matches op-geth's full/archive semantics.
# Reth defaults to archive; `--full` enables pruning to match op-geth's
# `--gcmode=full --syncmode=snap`.
FULL_ARG=""
if [ "$NODE_TYPE" = "full" ]; then
  FULL_ARG="--full"
fi

exec /usr/local/bin/celo-reth node \
  --chain="$CELO_RETH__CHAIN" \
  --datadir=/celo/data \
  --authrpc.addr=0.0.0.0 \
  --authrpc.port=8551 \
  --authrpc.jwtsecret=/shared/jwt.txt \
  --http \
  --http.addr=0.0.0.0 \
  --http.port=8545 \
  --http.api=eth,net,web3,debug,txpool \
  --http.corsdomain='*' \
  --ws \
  --ws.addr=0.0.0.0 \
  --ws.port=8546 \
  --ws.api=eth,net,web3,debug,txpool \
  --ws.origins='*' \
  --rollup.sequencer="$CELO_RETH__SEQUENCER_URL" \
  --rollup.disable-tx-pool-gossip \
  --metrics=0.0.0.0:6060 \
  --port=30303 \
  --txpool.nolocals \
  --min-suggested-priority-fee=2500000000 \
  --rpc.txfeecap=0 \
  $NAT_ARG \
  $TRUSTED_PEERS_ARG \
  $FULL_ARG \
  -vvv $@
