# Docker Compose Setup for Running a Celo L2 Node

A simple Docker Compose setup for running Celo L2 nodes.

> ⚠️ The instructions in this README are for illustrative purposes only. Please refer to the official [Celo Docs](https://docs.celo.org/cel2/operators/run-node) for the most up-to-date information on running Celo L2 nodes.

## Installation and Configuration

### Install Docker and Docker Compose

- **Linux:** Follow [Docker's official install guide](https://docs.docker.com/engine/install/). To run Docker without `sudo`, also complete the [Linux post-install steps](https://docs.docker.com/engine/install/linux-postinstall/).
- **macOS / Windows:** Install [Docker Desktop](https://www.docker.com/products/docker-desktop/).

Docker Compose v2 is included with all of the above; verify with `docker compose version`.

> On macOS, you may need to raise Docker Desktop's virtual disk limit to fit the chaindata directory: Settings → Resources → Advanced → Disk image size.

### Clone the Repository

```sh
git clone https://github.com/celo-org/celo-l2-node-docker-compose.git
cd celo-l2-node-docker-compose
```

### Configure Your Node

1. **Choose your network** and copy the corresponding environment file:

   ```sh
   # Celo Sepolia is recommended for testing
   export NETWORK=<celo-sepolia or mainnet>
   cp $NETWORK.env .env
   ```

   The `.env` file contains all the necessary configuration options for your node and is pre-configured for a full (non-archive) node.

2. **Configure P2P networking** (required for production):
   Edit your `.env` file and set these variables for external connectivity.

   ```text
   OP_NODE__P2P_ADVERTISE_IP=<your-public-ip>
   OP_RETH__NAT=extip:<your-public-ip>
   ```

3. **Optional: Configure L1 RPC endpoints**
   For better reliability, consider using paid RPC services instead of the defaults:

   ```text
   OP_NODE__RPC_ENDPOINT=<your-ethereum-rpc-url>
   OP_NODE__L1_BEACON=<your-ethereum-beacon-rpc-url>
   ```

## Advanced Node Configuration

### Key Environment Variables

- **NODE_TYPE** - The node tier, which sets both the snapshot download size and the prune mode. One of `minimal`, `full`, or `archive` (see [Snapshot modes](#snapshot-modes)):
  - `minimal` - Runs reth's most aggressive prune profile (`--minimal`): prunes transaction lookups fully and keeps only ~64 blocks of receipts. Smallest disk, limited historical RPC.
  - `full` - Runs reth's standard full-node prune profile (`--full`): retains ~10,064 blocks of history. Default.
  - `archive` - Stores historical state for the entire history of the blockchain.
- **OP_NODE__RPC_ENDPOINT** - Layer 1 RPC endpoint (e.g., Ethereum mainnet). For reliability, use paid plans or self-hosted nodes.
- **OP_NODE__L1_BEACON** - Layer 1 beacon endpoint. For reliability, use paid plans or self-hosted nodes.
- **OP_NODE__RPC_TYPE** - Service provider type for the L1 RPC endpoint:
  - `alchemy` - Alchemy
  - `quicknode` - Quicknode (ETH only)
  - `erigon` - Erigon
  - `basic` - Other providers
- **HEALTHCHECK__REFERENCE_RPC_PROVIDER** - Public healthcheck RPC endpoint for the Layer 2 network.
- **HISTORICAL_RPC_DATADIR_PATH** - Datadir path to use for legacy archive node to serve pre-L2 historical state. If set, a Celo L1 node will be run in archive mode to serve requests requiring state for blocks prior to the L2 migration and op-reth will be configured to proxy those requests to the Celo L1 node.
- **OP_RETH__HISTORICAL_RPC** - RPC Endpoint for fetching pre-L2 historical state. If set, op-reth will proxy requests requiring state prior to the L2 hardfork there. If set, this overrides the use of a local Celo L1 node via **HISTORICAL_RPC_DATADIR_PATH**, which means that no local Celo L1 node will be run.
- **DATADIR_PATH** - Use a custom datadir instead of the default at `./envs/<network>/datadir`. Must be empty on first start; datadirs written by op-geth cannot be reused.
- **OP_RETH__SNAPSHOT** - When `true`, bootstrap an empty datadir from a published snapshot (`snapshots.celo.org`) instead of syncing from scratch. The tier downloaded is set by `NODE_TYPE`. Skipped once the datadir already contains data.
- **IMAGE_TAG[...]__** - Use a custom Docker image for specified components.
- **MONITORING_ENABLED** - Enables the following services when set to `true`: `healthcheck`, `prometheus`, `grafana`, `influxdb`.

### Node Types

op-reth syncs by executing every block, there is no snap sync. `NODE_TYPE` selects the snapshot tier (see [Snapshot modes](#snapshot-modes)) and, for `archive`, whether full historical state is retained.

- **Minimal node**: runs reth's most aggressive prune profile (`--minimal`) — prunes transaction lookups fully and keeps only the most recent receipts. Smallest disk footprint; serves latest-state RPC but limited historical RPC.

   ```text
   NODE_TYPE=minimal
   ```

- **Full node**: prunes historical state, keeping it only for recent blocks.

   ```text
   NODE_TYPE=full
   ```

- **Archive node**: Stores complete historical state for the L2 chain.

   ```text
   NODE_TYPE=archive
   ```

  Additionnally, you need to configure pre-migration data access. You have 3 options:
  - Provide the path to an existing pre-migration archive datadir. The script will automatically start a legacy archive node with that datadir and connect it to your L2 node.

    ```text
    HISTORICAL_RPC_DATADIR_PATH=<path to your pre-migration archive datadir>
    ```

  - Not provide a path to an existing pre-migration archive datadir. The script will automatically start a legacy archive node which will begin syncing from the Celo genesis block. Note that syncing the legacy archive node will take some time, during which pre-migration archive access will not be available.

    ```text
    HISTORICAL_RPC_DATADIR_PATH=
    ```

  - Provide the RPC URL of a running legacy archive node. This will override any value set for HISTORICAL_RPC_DATADIR_PATH and a legacy archive node will not be launched when you start your L2 node.

    ```text
    OP_RETH__HISTORICAL_RPC=<historical rpc node endpoint>
    ```

### Snapshot modes

When `OP_RETH__SNAPSHOT=true` (the default), a fresh datadir is bootstrapped from a published snapshot (`snapshots.celo.org`) instead of syncing from genesis. The tier sets how much history is included:

- **minimal** - State and recent headers. Syncs to tip, validates consensus, and serves latest-state RPC (e.g. `eth_call`, `eth_getBalance` at head); limited historical RPC. Smallest and fastest.
- **full** - Adds post-merge transactions, recent receipts, and recent state history. Suited to dApp backends and personal nodes.
- **archive** - Complete history: all transactions, senders, receipts, and indices. For indexers and historical RPC providers.

`NODE_TYPE` selects the tier directly — `minimal`, `full`, or `archive` — and maps to reth's matching node run mode: `--minimal` (most aggressive pruning), `--full` (standard full-node pruning), or archive (no pruning, keeps complete history).

Approximate sizes (compressed download / extracted on disk):

| Tier | celo-sepolia | celo-mainnet |
| --- | --- | --- |
| minimal | ~7 GB / ~20 GB | ~65 GB / ~130 GB |
| full | ~11 GB / ~30 GB | ~215 GB / ~355 GB |
| archive | ~13 GB / ~50 GB | ~390 GB / ~1.35 TB |

### P2P Networking Environment Variables

> ⚠️ If these options are not configured correctly, your node will not be discoverable or reachable to other nodes on the network.

- **OP_NODE__P2P_ADVERTISE_IP** - Public IP to be shared via discovery so that other nodes can connect to your node.
- **PORT__OP_NODE_P2P** - Port for op-node P2P discovery. Defaults to `9222`.
- **OP_RETH__NAT** - Controls how op-reth determines its public IP. Use `extip:<your-public-ip>` for most reliable setup. Other values: `(any|none|upnp|publicip|extip:<IP>|stun:<IP:PORT>)`.
- **PORT__OP_RETH_P2P** - Port for op-reth P2P discovery. Defaults to `30303`.
- **PORT[...]__** - Other custom ports that may be specified.

## Operating the Node

### Start

```sh
docker compose up -d --build
```

This will start the node in a detatched shell (`-d`), meaning the node will continue to run in the background. We recommended to add `--build` to make sure that latest changes are being applied.

### Stop

```sh
docker compose down
```

This will shut down the node without wiping any volumes. You can safely run this command and then restart the node again.

### Restart

```sh
docker compose restart
```

This will restart the node safely with minimal downtime but without upgrading the node.

### Upgrade

```sh
git pull
docker compose pull
docker compose up -d --build
```

This will pull the latest changes from GitHub and Docker Hub, rebuild the container, and start the node again.

### Wipe Data (⚠️ DANGER)

```sh
docker compose down -v
```

This will shut down the node and WIPE ALL DATA. Proceed with caution!

### Monitor

**View logs:**

```sh
# All containers
docker compose logs -f --tail 10

# Specific container
docker compose logs op-reth -f --tail 10
docker compose logs op-node -f --tail 10
docker compose logs eigenda-proxy -f --tail 10
```

**Check sync progress:**

```sh
# Install foundry: https://book.getfoundry.sh/getting-started/installation
./progress.sh
```

**Grafana Dashboard:**

If monitoring is enabled (`MONITORING_ENABLED=true`), Grafana is available at [http://localhost:3000](http://localhost:3000).

Login details:

- Username: `admin`
- Password: `celo`

The "Simple Node Dashboard" (available at Dashboards > Manage > Simple Node Dashboard) shows basic node information and sync status.

The "Celo node monitoring" dashboard (available at Dashboards > Browse > Celo node monitoring) shows op-reth and op-node health: chain/safe/finalized heads, peers, gas throughput, database size, and op-node L1/L2 derivation status.

![metrics dashboard gif](https://user-images.githubusercontent.com/14298799/171476634-0cb84efd-adbf-4732-9c1d-d737915e1fa7.gif)

And the "Succinct Challenger" dashboard (available at Dashboards > Browse > Succinct Challenger) shows information about the challenger activity.

---

## L1 Data Migration

> ⚠️ Migrated datadirs are in geth format and cannot be used with op-reth, the execution client used by this setup. Run your node with an empty `DATADIR_PATH` instead; pre-L2 history is served via the historical-rpc-node service or `OP_RETH__HISTORICAL_RPC`. The instructions below are kept for reference.
>
> For detailed migration instructions, refer to the [official migration guide](https://docs.celo.org/cel2/operators/migrate-node).

If you need to migrate existing Celo L1 data to L2, you have two options:

### Option 1: Download Pre-Migrated Data

Download migrated datadirs from the official sources listed in the [Celo Docs](https://docs.celo.org/cel2/operators/migrate-node).

### Option 2: Migrate Your Own Data

> ⚠️ IMPORTANT
>
> - Make sure your node is stopped before running the migration.
> - You should not attempt to migrate archive node data, only full node data.

If you've been running a full node and wish to continue using the same datadir, you can migrate the data as follows:

```sh
./migrate.sh full <network> <source_L1_datadir> [dest_L2_datadir]
```

Where `<network>` is one of `mainnet` or `celo-sepolia`, the source datadir is the value that would be set with the `--datadir` flag of the celo-blockchain node, and the destination datadir is written in geth format.

If the destination datadir is omitted `./envs/<network>/datadir` will be used.

#### Troubleshooting

If you encounter this error during migration...

```log
CRIT [03-19|10:38:17.229] error in celo-migrate err="failed to run full migration: failed to get head header: failed to open database at \"/datadir/celo/chaindata\" err: failed to open leveldb: EOF"
```

...start up the celo-blockchain client with the same datadir, wait for it to fully load, then shut it down. This repairs inconsistent shutdown states.

Alternatively, open a console and exit:

```sh
geth console --datadir <datadir>
# Wait for console to load, then exit
```

It seems that this issue is caused by the celo-blockchain client sometimes shutting down in an inconsistent state, which is repaired upon the next startup.

## Running a challenger

> ⚠️ The instructions in this README are for illustrative purposes only. Please make your own assessments about trust assumptions, required services and configurations when running a challenger.

Running a challenger is essentially the same as operating a L2 node, with an additional service that compares the proposed dispute game L2 state root with its locally synced L2 state. Whenever the proposed state root does not match the operator's local state, the challenger publishes a challenge to L1 and the proposer is required to compute a zk-proof for the proposed state root.
This mechanism requires the challenger operator to run as much of the L2 infrastructure as possible locally and to avoid relying on third-party services without independently deriving consensus.
Because the state root must be compared to historical state roots up to approximately one week old, the operator must run a local L2 archive node.
In order to ensure the ability to fully derive the L2 state from consensus L1 data, the challenger operator should also run a dedicated EigenDA proxy service rather than connecting to a public S3-backed batch cache.

## Challenger requirements

- Ethereum (L1) execution node
  - configure trusted remote RPC execution endpoint
  - configuration and service not included in this setup
- Ethereum (L1) consensus node
  - configure trusted remote RPC consensus endpoint
  - configuration and service not included in this setup
- Celo (L2) execution node
  - archive node
  - full sync recommended
- Celo (L2) consensus node
  - consensus node with alt-da derivation
  - execution-sync
  - (consensus-sync for advanced trust assumptions, setup not supported in this configuration)
- eigenda-proxy
  - local proxy for L2 consensus node alt-da derivation backend
  - connected to disperser for blob-retrieval
  - not connected to Celo's public blob archive bucket
- challenger account
  - ethereum private-key with "challenger" permission on succinct dispute-game [AccessManager](https://etherscan.io/address/0xF59a19c5578291cB7fd22618D16281aDf76f2816#readContract#F6)
  - funded with at least 0.01 Eth [challenger-bond](https://etherscan.io/address/0x113f434f82FF82678AE7f69Ea122791FE1F6b73e#readContract#F5) (better multiples of) plus `challenge()` transaction gas costs

## Installation and Configuration

Refer to the [previous instructions](#installation-and-configuration) and the [Celo Docs](https://docs.celo.org/cel2/operators/run-node) on how to run a node and configure it as an archive node.

### Required steps

Modify the `.env` file that you copied over with the following options:

```sh
NODE_TYPE=archive

# disable fetching blobs from cache
EIGENDA_LOCAL_ARCHIVE_BLOBS=

CHALLENGER__ENABLED=true
```

### Optional changes

```sh
# Reduces load on the L1 node. Since game timeouts are on the order of days, this is generally acceptable from a network security perspective.
# Note, however, that submitting challenges is on a first-come, first-served basis. Configuring a higher value than other
# operators will significantly reduce the likelihood of being the one to submit the challenge.
# Conversely, lowering this value increases the probability of successfully submitting a challenge, but also increases load on the L1 node.
CHALLENGER__FETCH_INTERVAL_SECONDS=120

# Maximum time (seconds) the challenger waits for an L1 transaction (e.g. a `challenge()` call) to be confirmed.
# Raise this if your L1 RPC is slow or commonly under load.
CHALLENGER__TX_CONFIRMATION_TIMEOUT_SECONDS=180

# Use a specific version of the challenger image
# See https://github.com/celo-org/op-succinct/releases for the latest releases
IMAGE_TAG__CHALLENGER=v1.0.0

# L1 node that the op-node (Bedrock) will get chain data from.
# To ensure reliability node operators may wish to change this to point at a service they trust.
# This is configured within the container, so requires a DNS-resolvable path to the url from there
OP_NODE__RPC_ENDPOINT=https://<local-layer-1-execution-rpc-endpoint>

# L1 beacon endpoint, you can setup your own or use Quicknode.
# To ensure reliability node operators may wish to change this to point at a service they trust.
# This is configured within the container, so requires a DNS resolvable path to the url from there
OP_NODE__L1_BEACON=https://<local-layer-1-beacon-rpc-endpoint>

# Type of RPC that op-node is connected to, see README
OP_NODE__RPC_TYPE=basic


# Start the monitoring services (Grafana, Prometheus, Influxdb)
MONITORING_ENABLED=true

# Configure the exposed ports for the metrics to non-defaults
PORT__PROMETHEUS=9091

```

### Disable monitor-only mode

The challenger runs in _monitor-only_ mode by default. This means that detected mismatches in the L2 state root do not
cause a `challenge()` transaction to be submitted to the dispute game contracts, but this mismatch is logged with a
warning log message. No on-chain transactions are sent in monitor-only mode.

If you want to disable this mode, you can modify the `.env` file:

```sh
CHALLENGER__DISABLE_MONITOR_ONLY_MODE=true

# modify to your key with challenger permissions
CHALLENGER__PRIVATE_KEY="0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
```

If you want to actively challenge proposals, it is required that the `CHALLENGER__PRIVATE_KEY` corresponds to an address that has challenger permissions on the network’s dispute game AccessManager contract and is funded with at least the required challenge bond.
It is recommended that this address be funded with a multiple of the challenge bond amount (see [challenger requirements](#challenger-requirements).

### Monitor challenger logs:

```bash
docker compose logs challenger -f --tail 10
```

### Alerting for challenges

If you are running `MONITORING_ENABLED=true` or ingesting the challenger metrics in any other form,
you can set up the following Prometheus datasource metrics in order to track challenges and errors in challenging:

- `op_succinct_fp_challenger_games_challenged`
  - gauge that increases by 1 after a challenge transaction has successfully been sent to the L1,
  - in monitor-only mode, this increases after the challenge transaction would have been called but was skipped
- `op_succinct_fp_challenger_game_challenging_error`
  - gauge the increases by 1 if a challenge trasaction could not be successfully send to the L1
  - in monitor-only mode, this will only increase due to serialization issues in the challenge transaction preparation
