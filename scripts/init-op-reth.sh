#!/bin/sh
set -e

# One-time datadir initialization for op-reth. On first start (an empty datadir)
# this downloads a pre-synced datadir snapshot so the node does not have to sync
# the whole chain from scratch. It runs as a dedicated container because the
# op-reth image is minimal and ships none of the download/decompression tooling
# used here.

DATADIR=/reth
ARCHIVE="$DATADIR/snapshot.tar.zst"

# Anything other than "full" is treated as an archive node, matching
# start-op-reth.sh. Archive and full nodes need different snapshots.
if [ "$NODE_TYPE" = "full" ]; then
  SNAPSHOT_NODE_TYPE=full
else
  SNAPSHOT_NODE_TYPE=archive
fi

# OP_RETH__SNAPSHOT_URL overrides the download location. When unset it falls back
# to the default derived from the network and node type; when set but empty the
# snapshot is skipped and op-reth syncs from scratch.
DEFAULT_SNAPSHOT_URL="https://snapshot.celo.org/${NETWORK_NAME}/${SNAPSHOT_NODE_TYPE}"
SNAPSHOT_URL="${OP_RETH__SNAPSHOT_URL-$DEFAULT_SNAPSHOT_URL}"

# Treat the datadir as already initialized if it holds anything other than a
# partially downloaded archive left behind by an interrupted run.
if [ -n "$(ls -A "$DATADIR" 2>/dev/null | grep -v '^snapshot\.tar\.zst$' || true)" ]; then
  echo "op-reth datadir at $DATADIR already contains data; skipping snapshot download."
  exit 0
fi

if [ -z "$SNAPSHOT_URL" ]; then
  echo "OP_RETH__SNAPSHOT_URL is empty; skipping snapshot download, op-reth will sync from scratch."
  exit 0
fi

echo "Initializing op-reth datadir from snapshot: $SNAPSHOT_URL"

# The op-reth image is minimal, so install the download/decompression tools here,
# where we control the base image.
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends curl zstd ca-certificates
rm -rf /var/lib/apt/lists/*

# A bounded number of retries means a wrong or missing URL fails the container
# loudly instead of hanging forever. -C - resumes a partial download, so an
# interrupted run can be retried with another `docker compose up`.
curl -fL --retry 5 --retry-delay 30 -C - -o "$ARCHIVE" "$SNAPSHOT_URL"

# The snapshot contains the datadir contents (db/, static_files/, ...) at the top
# level of the archive.
tar --use-compress-program=unzstd -xf "$ARCHIVE" -C "$DATADIR"
rm -f "$ARCHIVE"

echo "op-reth datadir initialized from snapshot."
