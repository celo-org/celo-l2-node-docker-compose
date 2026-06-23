# L1 Data Migration

> ⚠️ Migrated datadirs are in geth format and cannot be used with op-reth, the execution client used by this setup. Run your node with an empty `DATADIR_PATH` instead; pre-L2 history is served via the historical-rpc-node service or `OP_RETH__HISTORICAL_RPC`. The instructions below are kept for reference.
>
> For detailed migration instructions, refer to the [official migration guide](https://docs.celo.org/infra-partners/operators/migrate-node).

If you need to migrate existing Celo L1 data to L2, you have two options:

## Option 1: Download Pre-Migrated Data

Download migrated datadirs from the official sources listed in the [Celo Docs](https://docs.celo.org/infra-partners/operators/migrate-node).

## Option 2: Migrate Your Own Data

> ⚠️ IMPORTANT
>
> - Make sure your node is stopped before running the migration.
> - You should not attempt to migrate archive node data, only full node data.

If you've been running a full node and wish to continue using the same datadir, you can migrate the data as follows:

```sh
./migrate.sh full <network> <source_L1_datadir> [dest_L2_datadir]
```

Where `<network>` is `mainnet`, the source datadir is the value that would be set with the `--datadir` flag of the celo-blockchain node, and the destination datadir is written in geth format.

If the destination datadir is omitted `./envs/<network>/datadir` will be used.

### Troubleshooting

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
