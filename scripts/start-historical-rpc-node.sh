#!/bin/sh
set -e

if [ "$NETWORK_NAME" != "op-mainnet" ]; then
  echo "Stopping historical-rpc-node for a non op-mainnet chain"
  exit
fi

if [ -n "${OP_GETH__HISTORICAL_RPC}" ]; then
  echo "Stopping historical-rpc-node for using an external historical RPC"
  exit
fi

# Start historical-rpc-node.
exec geth \
  --vmodule=eth/*=5,miner=4,rpc=5,rollup=4,consensus/clique=1 \
  --datadir=$DATADIR \
  --password=$DATADIR/password \
  --allow-insecure-unlock \
  --unlock=$BLOCK_SIGNER_ADDRESS \
  --mine \
  --miner.etherbase=$BLOCK_SIGNER_ADDRESS \
  --gcmode=$NODE_TYPE \
  --metrics \
  --metrics.influxdb \
  --metrics.influxdb.endpoint=http://influxdb:8086 \
  --metrics.influxdb.database=historical-rpc-node \
  $@
