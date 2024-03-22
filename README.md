<a href="https://discord.gg/WhZmm46APN"><img alt="Discord" src="https://img.shields.io/discord/852538978946383893?style=for-the-badge&logo=discord&label=Discord&labelColor=%231940ED&color=%233FCB9B"></a>

# XRAY | Graph | Koios Tiny — Cardano Explorer API

> [!NOTE]
> XRAY | Graph | Koios Tiny is a dockered Cardano blockchain explorer API tool based on [Koios](https://koios.rest) and [Cardano-Db-Sync](https://github.com/input-output-hk/cardano-db-sync). With some custom RPCs added.

## Getting Started

``` console
git clone \
  --recurse-submodules \
  https://github.com/xray-network/xray-graph-koios-tiny.git \
  && cd xray-graph-koios-tiny
```
``` console
cp .env.example .env
```
  
#### Build and Run via Docker Compose
  
<details open>
  <summary><b>MAINNET</b></summary>

Default

Get the most recent weekly snapshot link [here](https://snapshots.koios.rest/db-sync-13.1-mainnet/) (with db-sync started with `--consumed-tx-out` flag) or [here](https://update-cardano-mainnet.iohk.io/cardano-db-sync/index.html#13.1/) (without flag, takes a lot longer to restore), and set it as `RESTORE_SNAPSHOT` below, or omit if you wish to sync from genesis.
``` console
RESTORE_SNAPSHOT=https://snapshots.koios.rest/db-sync-13.1-mainnet/db-sync-snapshot-schema-13.1-block-9684674-x86_64.tgz \
docker compose up -d --build
```

> Restoring from snapshot takes about 5 hours on epoch 413 with using a fast NVMe SSD (~1M IOPS). Also after restoring db-sync snapshot, it will take some time to run koios cron jobs, about 6 hours, so keep that in mind. 

</details>
  
<details>
  <summary><b>PREPROD</b></summary>

Default

``` console
NETWORK=preprod docker compose up -d --build
```

Advanced usage (ports mapping, containers name change)

``` console
NETWORK=preprod \
CARDANO_NODE_PORT=3001 \
KOIOS_TINY_PORT=8051 \
OGMIOS_PORT=1338 \
POSTGRES_PORT=5433 \
docker compose -p preprod up -d --build
```

</details>
  
<details>
  <summary><b>PREVIEW</b></summary>

Default

``` console
NETWORK=preview docker compose up -d --build
```

Advanced usage (ports mapping, containers name change)

``` console
NETWORK=preview \
CARDANO_NODE_PORT=3002 \
KOIOS_TINY_PORT=8052 \
OGMIOS_PORT=1339 \
POSTGRES_PORT=5434 \
docker compose -p preview up -d --build
```

</details>


## Endpoints List
  
* Koios — https://api.koios.rest/
* Ogmios — https://ogmios.dev/api/

Differences with the original Koios:

* `/submittx` endpoint: not available, use XRAY | Graph | Turbo Tx Send API
* `/ogmios` endpoint: not available, use XRAY | Graph | Ogmios API

## API Status Check
  
Raw CURL query examples:
  
``` console
curl 0.0.0.0:8050/rpc/tip
```
``` console
curl 0.0.0.0:8050/rpc/blocks
```
  
## TypeScript Client
  
We recommend to use `koios-tiny-client`. Visit [koios-tiny-client](https://github.com/xray-network/koios-tiny-client) repo for more information.
  
## Advanced Usage
 
<details>
  <summary>Postgresql Config</summary>
  
Config file (see end of file): [postgresql.conf](https://github.com/xray-network/xray-graph-output/blob/main/config/postgresql/postgresql.conf)<br/>
Use https://pgtune.leopard.in.ua/ to tune the database settings

</details>

<details>
  <summary>Koios Custom RPCs & Cron Tasks</summary>

Place the `.sql` files in the `koios-tiny/extra-rpc` folder to register with Postgrest. Then rebuild the `koios-tiny` container. Read more at https://postgrest.org/en/stable/references/api.html

Place the .sh files in `koios-tiny/extra-cron-jobs` and edit the `koios-tiny/cron-schedule`. Then rebuild the `koios-tiny` container.

Rebuild: `docker compose up -d --build --force-recreate koios-tiny`.
  
</details>

## System Requirements
  
In general, this stack loads the system in the same way as `cardano-db-sync`, so the minimal system requirements will be the same:

* Any of the big well known Linux distributions (eg, Debian, Ubuntu, RHEL, CentOS, Arch etc).
* 64 Gigabytes of RAM or more.
* 4 CPU cores or more.
* Ensure that the machine has sufficient IOPS (Input/Output Operations per Second). Ie it should be 100k IOPS or better. Lower IOPS ratings will result in slower sync times and/or falling behind the chain tip.
* Minimum 1000 Gigabytes or more of SSD disk storage.
  
When building an application that will be querying the database, remember that for fast queries, low latency disk access is far more important than high throughput (assuming the minimal IOPS above is met).

