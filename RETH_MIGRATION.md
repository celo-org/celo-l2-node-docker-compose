# Migrating a Celo Mainnet Node from op-geth to op-reth

A general, deployment-agnostic reference for moving a **Celo mainnet** L2 node from
**op-geth** to **op-reth** (`celo-reth`), the Rust execution client. It is written for
node operators and for AI agents assisting with the upgrade.

The concrete flags, images, and values below are taken from a known-good celo-mainnet
setup. This repository's Docker Compose stack is one working implementation of exactly
these steps — see the [README](README.md) if you want a ready-made version — but nothing
here is specific to Docker; the same steps apply to bare-metal, systemd, or Kubernetes
deployments. For Celo Sepolia, substitute the chain/network values noted inline.

---

## TL;DR

- Only the **execution client** changes: op-geth → op-reth. Your **op-node (consensus)
  stays**; you repoint it at op-reth and add **`--l2.enginekind=reth`**.
- **op-reth cannot reuse an op-geth datadir** (different on-disk format: MDBX + static
  files). You start from an **empty datadir** and sync fresh.
- op-reth **executes every block — there is no snap sync**, so **bootstrap from a
  published snapshot** (`https://snapshots.celo.org`) rather than syncing from genesis.
- Run the new stack alongside the old one, verify it reaches the tip, then cut traffic
  over and decommission op-geth.

---

## What changes vs. what stays

| | op-geth | op-reth |
| --- | --- | --- |
| Execution client | op-geth (Go) | `celo-reth` (Rust) |
| On-disk format | geth (LevelDB/Pebble) | reth MDBX + static files — **not compatible** |
| Datadir reuse | — | **No.** Fresh, empty datadir required |
| Initial sync | snap sync possible | executes every block; **bootstrap from snapshot** |
| Consensus client | op-node | **op-node (unchanged)**, with `--l2.enginekind=reth` |
| L1 / EigenDA / JWT | as configured | **unchanged** — same op-node L1, beacon, alt-DA, and JWT |

The migration touches only the EL and the two op-node flags that point at it. Everything
else in your op-node configuration (L1 RPC, L1 beacon, EigenDA/alt-DA, network) is
carried over as-is.

---

## Component images (celo-mainnet)

| Component | Image (repository:tag) | Digest |
| --- | --- | --- |
| **op-reth** | `us-west1-docker.pkg.dev/devopsre/celo-blockchain-public/op-reth:celo-v1.0.0` | `sha256:b0fdd2dcd0623faa5f1015eb6432b035397ba14ca84e64a76afc77b5f6909543` |
| **op-node** | `us-west1-docker.pkg.dev/devopsre/celo-blockchain-public/op-node:celo-v2.2.1` | `sha256:2504e8fbba5984372ea67645c493852461e6170c98e21fa5f91d47225e76a389` |

Use the `@sha256:...` digest form to pin a reproducible deployment, e.g.
`...op-reth:celo-v1.0.0@sha256:b0fdd2dcd0623faa5f1015eb6432b035397ba14ca84e64a76afc77b5f6909543`.
Use an op-node build of **`celo-v2.2.1` or newer** — earlier op-node versions do not
support driving a reth execution engine.

---

## Prerequisites

- A **fresh, empty datadir** on a disk sized for your node type (see [Node types &
  snapshots](#node-types--snapshots)).
- A **JWT secret** (32 random bytes, hex) shared between op-reth and op-node — the same
  as your existing op-geth ↔ op-node JWT contract.
- A **p2p secret key** for op-reth (32-byte hex; auto-generated on first start if not
  provided) and a p2p key for op-node.
- **L1 (Ethereum) execution + beacon RPC endpoints** for op-node — unchanged from your
  op-geth setup.
- Your existing **EigenDA / alt-DA** setup for op-node (unchanged).

---

## Migration steps

1. **Provision a new op-reth node on an empty datadir.** Do not point it at your op-geth
   datadir — `celo-reth` refuses to start on geth chaindata and would need to re-sync
   anyway.
2. **Bootstrap the datadir from a snapshot** (strongly recommended on mainnet):
   ```sh
   celo-reth download --datadir=<datadir> --chain=celo --<minimal|full|archive>
   ```
   `celo-reth` automatically selects the correct `https://snapshots.celo.org` manifest
   for the chain. The tier (`--minimal` / `--full` / `--archive`) must match how you
   intend to run the node. To sync from genesis instead, skip this and start op-reth on
   an empty datadir (slow — full mainnet execution).
   *(Celo Sepolia: use `--chain=celo-sepolia`.)*
3. **Start op-reth** with the celo-mainnet configuration in
   [Reference: op-reth](#reference-op-reth-run-configuration-celo-mainnet).
4. **Repoint op-node at op-reth** and set the engine kind — see
   [Reference: op-node](#reference-op-node-run-configuration-celo-mainnet). Only two
   lines change from your op-geth setup:
   - `--l2=http://<op-reth-host>:8551` (op-reth's authenticated engine API)
   - `--l2.enginekind=reth`
   Keep the **same JWT** on both sides.
5. **Let it sync and verify.** op-reth boots its engine API (port `8551`) only after the
   snapshot import finishes; op-node then drives it to the chain tip. Confirm the head
   advances to the network tip and that JSON-RPC on `:8545` answers correctly (compare a
   few `eth_blockNumber` / `eth_getBalance` / receipt queries against your op-geth node
   or a public endpoint like `https://forno.celo.org`).
6. **Cut over and decommission op-geth.** Once op-reth is at the tip and serving RPC
   correctly, move downstream traffic (load balancer, dApps, indexers) to op-reth, then
   retire the op-geth node.

> **Zero-downtime option:** run op-reth + its op-node as a parallel stack (separate
> datadir and ports) while op-geth keeps serving, and only switch traffic after op-reth
> is verified at the tip.

---

## Reference: op-reth run configuration (celo-mainnet)

Known-good `celo-reth node` invocation for a **full** mainnet node. Replace the
`<...>` placeholders. The prune profile flag at the end selects the node type.

```sh
celo-reth node \
  --chain=celo \
  --datadir=<datadir> \
  --storage.v2=true \
  --http --http.addr=0.0.0.0 --http.port=8545 --http.api=web3,debug,eth,txpool,net \
  --ws   --ws.addr=0.0.0.0   --ws.port=8546   --ws.api=debug,eth,txpool,net,web3 \
  --metrics=0.0.0.0:9001 \
  --authrpc.addr=0.0.0.0 --authrpc.port=8551 --authrpc.jwtsecret=<jwt-file> \
  --rollup.sequencer=https://cel2-sequencer.celo.org \
  --rollup.disable-tx-pool-gossip \
  --bootnodes=<celo-mainnet-bootnodes> \
  --port=30303 --discovery.port=30303 --discovery.v5.port=30303 \
  --max-peers=100 \
  --nat=extip:<your-public-ip> \
  --txpool.nolocals \
  --rpc.txfeecap=0 \
  --full            # node-type flag: --full (default) | --minimal | omit for archive
```

Notes:
- **`--chain=celo`** loads the built-in Celo mainnet spec (`celo-sepolia` for Sepolia).
- **`--nat`** controls the public IP advertised for discovery. `extip:<your-public-ip>`
  is the most reliable; other values: `any | none | upnp | publicip | extip:<IP> |
  stun:<IP:PORT>`. Without a correct value your node will not be discoverable/reachable.
  Query what it resolved with the `admin_nodeInfo` RPC.
- **P2P port `30303`** (TCP **and** UDP) must be open/reachable.
- **`--bootnodes`** are the cLabs-operated celo-mainnet nodes (they also work as
  `--trusted-peers`, bypassing the peer limit). The full list is in the
  [Appendix](#appendix-celo-mainnet-op-reth-bootnodes).
- **Node type** = prune profile: `--full` (retains ~10,064 recent blocks, default),
  `--minimal` (most aggressive pruning), or **no flag** for `archive` (retains all
  historical state).

---

## Reference: op-node run configuration (celo-mainnet)

Your op-node config is carried over from op-geth; the **only migration changes** are
`--l2` (now op-reth's engine endpoint) and **`--l2.enginekind=reth`**.

```sh
op-node \
  --l1=<l1-execution-rpc> \
  --l2=http://<op-reth-host>:8551 \      # ← op-reth authenticated engine API
  --l2.enginekind=reth \                 # ← REQUIRED: drive a reth EL (this is the key change)
  --l2.jwt-secret=<jwt-file> \           # same JWT as op-reth --authrpc.jwtsecret
  --rpc.addr=0.0.0.0 --rpc.port=9545 \
  --l1.trustrpc \
  --l1.rpckind=<basic|alchemy|quicknode|erigon> \
  --l1.beacon=<l1-beacon-rpc> \
  --metrics.enabled --metrics.addr=0.0.0.0 --metrics.port=7300 \
  --syncmode=consensus-layer \
  --verifier.l1-confs=4 \
  --network=celo-mainnet \
  --p2p.advertise.ip=<your-public-ip> \
  --p2p.priv.path=<op-node-p2p-key-file> \
  --p2p.peerstore.path=<op-node-peerstore-dir>
```

Plus your existing **alt-DA (EigenDA)** flags, unchanged from the op-geth setup:

```sh
  --altda.enabled=true \
  --altda.da-service=true \
  --altda.verify-on-read=false \
  --altda.da-server=<eigenda-proxy-endpoint>
```

Notes:
- **`--l2.enginekind=reth`** is the single most-forgotten step. Without it op-node will
  not drive op-reth correctly.
- **`--network=celo-mainnet`** loads the rollup config from the superchain registry
  (`celo-sepolia` for Sepolia).
- **`--syncmode=consensus-layer`**: op-node derives blocks from L1 and feeds them to
  op-reth over the engine API. This suits op-reth, which has no snap sync.
- op-node P2P port `9222` (TCP **and** UDP) must be open for discovery.

---

## Node types & snapshots

`celo-reth` bootstraps from published snapshots at **<https://snapshots.celo.org>** —
see that page for the **current list of available snapshots, block heights, tiers, and
exact sizes**. The tier you download must match how you run the node.

| Tier | reth run mode | Purpose | Approx. celo-mainnet size (download / on disk) |
| --- | --- | --- | --- |
| `minimal` | `--minimal` | Latest-state RPC, smallest disk, limited history | ~65 GB / ~130 GB |
| `full` | `--full` (default) | dApp backends / personal nodes; recent history | ~215 GB / ~355 GB |
| `archive` | (no prune flag) | Indexers / historical RPC; complete state | ~390 GB / ~1.35 TB |

Sizes are approximate and grow over time — always confirm against
<https://snapshots.celo.org>. Provision disk for the **extracted** size plus headroom
(archive grows continuously).

---

## Optional: historical proofs

Serving `eth_getProof` for an older block normally forces reth to rebuild that block's
state by reverting diffs from the tip — slow at depth and can OOM the node, even on an
archive node. op-reth ships an optional **historical-proofs sidecar** that answers deep
`eth_getProof` from a precomputed, bounded-window store instead.

- Initialize once against a datadir that is **already synced past genesis**
  (`celo-reth proofs init --datadir=<datadir> --chain=celo
  --proofs-history.storage-path=<proofs-dir> --proofs-history.storage-version=v2`), then
  run op-reth with `--proofs-history --proofs-history.storage-path=<proofs-dir>
  --proofs-history.storage-version=v2 --proofs-history.window=<blocks>`.
- The window defaults to `1296000` blocks (~15 days at 1s blocks); proofs fill **forward
  only** from the anchor and cannot be backfilled.
- A snapshot-bootstrapped or already-synced datadir can initialize immediately; a
  from-genesis node must sync first, then restart to initialize.
- Keep the proofs DB on a **separate volume** from the chaindata; it is sized by the
  window and can be large.

See the [historical proofs operator guide](https://docs.celo.org/infra-partners/operators/historical-proofs).

---

## Gotchas / pre-cutover checklist

- [ ] **Fresh datadir** — an op-geth datadir cannot be reused; start op-reth empty.
- [ ] **`--l2.enginekind=reth`** set on op-node.
- [ ] **Same JWT** on op-reth (`--authrpc.jwtsecret`) and op-node (`--l2.jwt-secret`).
- [ ] **Snapshot tier matches node type** (`minimal` / `full` / `archive`).
- [ ] **P2P reachability**: correct `--nat` (op-reth) and `--p2p.advertise.ip` (op-node),
      with ports `30303` (op-reth) and `9222` (op-node) open on **both TCP and UDP**.
- [ ] **Disk** sized for the extracted snapshot plus growth; archive is the largest.
- [ ] **Verified at the tip** and RPC parity checked before cutting traffic over.
- [ ] **Pre-migration (Celo L1) history**: op-reth's datadir only holds post-migration
      (L2) blocks. If you must serve state from before the L2 migration, run/point to a
      separate legacy Celo L1 archive node — see the
      [Celo operator docs](https://docs.celo.org/infra-partners/operators/run-node).

---

## Appendix: celo-mainnet op-reth bootnodes

cLabs-operated nodes; also usable as `--trusted-peers`. Confirm the current list against
the Celo network-config docs.

<details>
<summary>enode list</summary>

```text
enode://28f4fcb7f38c1b012087f7aef25dcb0a1257ccf1cdc4caa88584dc25416129069b514908c8cead5d0105cb0041dd65cd4ee185ae0d379a586fb07b1447e9de38@34.169.39.223:30303
enode://a9077c3e030206954c5c7f22cc16a32cb5013112aa8985e3575fadda7884a508384e1e63c077b7d9fcb4a15c716465d8585567f047c564ada2e823145591e444@34.169.212.31:30303
enode://029b007a7a56acbaa8ea50ec62cda279484bf3843fae1646f690566f784aca50e7d732a9a0530f0541e5ed82ba9bf2a4e21b9021559c5b8b527b91c9c7a38579@34.82.139.199:30303
enode://f3c96b73a5772c5efb48d5a33bf193e58080d826ba7f03e9d5bdef20c0634a4f83475add92ab6313b7a24aa4f729689efb36f5093e5d527bb25e823f8a377224@34.82.84.247:30303
enode://daa5ad65d16bcb0967cf478d9f20544bf1b6de617634e452dff7b947279f41f408b548261d62483f2034d237f61cbcf92a83fc992dbae884156f28ce68533205@34.168.45.168:30303
enode://c79d596d77268387e599695d23e941c14c220745052ea6642a71ef7df31a13874cb7f2ce2ecf5a8a458cfc9b5d9219ce3e8bc6e5c279656177579605a5533c4f@35.247.32.229:30303
enode://4151336075dd08eb6c75bfd63855e8a4bd6fd0f91ae4a81b14930f2671e16aee55495c139380c16e1094a49691875e69e40a3a5e2b4960c7859e7eb5745f9387@35.205.149.224:30303
enode://ab999db751265c714b171344de1972ed74348162de465a0444f56e50b8cfd048725b213ba1fe48c15e3dfb0638e685ea9a21b8447a54eb2962c6768f43018e5c@34.79.3.199:30303
enode://9d86d92fb38a429330546fe1aefce264e1f55c5d40249b63153e7df744005fa3c1e2da295e307041fd30ab1c618715f362c932c28715bc20bed7ae4fc76dea81@34.77.144.164:30303
enode://c82c31f21dd5bbb8dc35686ff67a4353382b4017c9ec7660a383ccb5b8e3b04c6d7aefe71203e550382f6f892795728570f8190afd885efcb7b78fa398608699@34.76.202.74:30303
enode://3bad5f57ad8de6541f02e36d806b87e7e9ca6d533c956e89a56b3054ae85d608784f2cd948dc685f7d6bbd5a2f6dd1a23cc03e529ea370dd72d880864a2af6a3@104.199.93.87:30303
enode://1decf3b8b9a0d0b8332d15218f3bf0ceb9606b0efe18f352c51effc14bbf1f4f3f46711e1d460230cb361302ceaad2be48b5b187ad946e50d729b34e463268d2@35.240.26.148:30303
```

</details>

---

## Related documentation

- [README](README.md) — a working Docker Compose implementation of these steps.
- [MIGRATION.md](MIGRATION.md) — legacy **Celo L1 → L2** data migration (separate topic).
- [Celo operator docs](https://docs.celo.org/infra-partners/operators/run-node)
- [Snapshots](https://snapshots.celo.org)
