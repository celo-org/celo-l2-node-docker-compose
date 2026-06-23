#!/bin/sh
set -e

# Map NETWORK_NAME to the superchain-registry network name used by --network.
case "$NETWORK_NAME" in
  mainnet) CELO_NETWORK=celo-mainnet ;;
  celo-sepolia) CELO_NETWORK=celo-sepolia ;;
  *) echo "Unknown NETWORK_NAME: '$NETWORK_NAME'"; exit 1 ;;
esac

# Load the rollup config from the superchain-registry by network name.
export EXTENDED_ARG="${EXTENDED_ARG:-} --network=$CELO_NETWORK"

if [ -n "$OP_NODE__P2P_ADVERTISE_IP" ]; then
  export EXTENDED_ARG="${EXTENDED_ARG:-} --p2p.advertise.ip=$OP_NODE__P2P_ADVERTISE_IP"
fi

# OP_NODE_ALTDA_DA_SERVER is picked up by the op-node binary.
export OP_NODE_ALTDA_DA_SERVER=$EIGENDA_PROXY_ENDPOINT
if [ -z "$OP_NODE_ALTDA_DA_SERVER" ]; then
  OP_NODE_ALTDA_DA_SERVER="http://eigenda-proxy:4242"
fi

# Wait for the op-reth engine API before starting op-node. op-reth only binds
# port 8551 once `celo-reth node` is running, which is after any OP_RETH__SNAPSHOT
# download/import finishes (can take a long time on mainnet or a slow link).
# Without this, op-node exits after its ~10 internal connection retries and
# crash-loops until op-reth is ready. No timeout here on purpose: op-node waits
# as long as the snapshot takes and then starts, so the node always comes up on
# its own without operator intervention.
echo "Waiting for op-reth engine API (op-reth:8551)..."
while ! nc -z -w 3 op-reth 8551 2>/dev/null; do
  sleep 5
done
echo "op-reth engine is reachable; starting op-node."

# Start op-node.
exec op-node \
  --l1=$OP_NODE__RPC_ENDPOINT \
  --l2=http://op-reth:8551 \
  --l2.enginekind=reth \
  --rpc.addr=0.0.0.0 \
  --rpc.port=9545 \
  --l2.jwt-secret=/shared/jwt.txt \
  --l1.trustrpc \
  --l1.rpckind=$OP_NODE__RPC_TYPE \
  --l1.beacon=$OP_NODE__L1_BEACON \
  --metrics.enabled \
  --metrics.addr=0.0.0.0 \
  --metrics.port=7300 \
  --syncmode=execution-layer \
  --verifier.l1-confs=4 \
  --p2p.priv.path=/shared/op-node_p2p_priv.txt \
  --p2p.peerstore.path=/shared/opnode_peerstore_db \
  $EXTENDED_ARG $@
