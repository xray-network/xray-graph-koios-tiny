<a href="https://discord.gg/WhZmm46APN"><img alt="Discord" src="https://img.shields.io/discord/852538978946383893?style=for-the-badge&logo=discord&label=Discord&labelColor=%231940ED&color=%233FCB9B"></a>

# XRAY/Graph Koios Tiny — Dockerized Koios (Cardano-Db-Sync)

XRAY/Graph Koios Tiny is a tool for fast and predictable deployment of [Koios](https://koios.rest/) (Cardano-Db-Sync) stack in a docker environment. Used in the [XRAY/Graph](https://xray.app/) distributed Cardano API provider.

## Getting Started

### Prepare Installation

``` console
git clone \
  --recurse-submodules \
  https://github.com/xray-network/xray-graph-koios-tiny.git \
  && cd xray-graph-koios-tiny
```
  
### MAINNET

``` console
NETWORK=mainnet \
POSTGRES_PASSWORD=your_secret_password \
docker compose -f docker-compose.yaml -p koios-tiny-mainnet up -d --build
```
  
### PREPROD

``` console
NETWORK=preprod \
POSTGRES_PASSWORD=your_secret_password \
POSTGRES_PORT=5433 \
OGMIOS_PORT=1338 \
CARDANO_PORT=3001 \
KOIOS_PORT=8051 \
OGMIOS_PROXY_PORT=8701 \
RAPIDOC_KOIOS_PORT=2701 \
docker compose -f docker-compose.yaml -p koios-tiny-preprod up -d --build
```

</details>
  
### PREVIEW

``` console
NETWORK=preview \
POSTGRES_PASSWORD=your_secret_password \
POSTGRES_PORT=5434 \
OGMIOS_PORT=1339 \
CARDANO_PORT=3002 \
KOIOS_PORT=8052 \
OGMIOS_PROXY_PORT=8702 \
RAPIDOC_KOIOS_PORT=2702 \
docker compose -f docker-compose.yaml -p koios-tiny-preview up -d --build
```

## Advanced Usage

<details>
  <summary><b>Restoring From Snapshot</b></summary>
  
## Step 0: Installing Dependencies

Installing dependepcies (if needed):
``` console
sudo apt update && sudo apt install zstd jq wget -y
```

## Step 1: Restoring Koios (cardano-db-sync) DB

1. Enter root dir:
``` console
cd xray-graph-koios-tiny
```

2. Download snapshot:
``` console
wget 'https://share.koios.rest/api/public/dl/xFdZDfM4/dbsync/mainnet-dbsyncsnap-latest.tgz' -O ./snapshot/mainnet-dbsyncsnap-latest.tgz
```

3. Run docker compose up (clean run):
``` console
RESTORE_SNAPSHOT=/snapshots/mainnet-dbsyncsnap-latest.tgz \
NETWORK=mainnet \
POSTGRES_PASSWORD=your_secret_password \
docker compose -f docker-compose.yaml -p koios-tiny-mainnet up -d --build
```

## Step 2: Restoring Cardano Node DB

1. Enter root dir:
``` console
cd xray-graph-koios-tiny
```

2. Stop cardano-node-ogmios container:
``` console
docker stop *container_id*
```

3. Download lates cardano-node-ogmios db:
``` console
wget -c -O - "https://downloads.csnapshots.io/mainnet/$(wget -qO- https://downloads.csnapshots.io/mainnet/mainnet-db-snapshot.json | jq -r .[].file_name)" | zstd -d -c | tar -x -C ./snapshots
```

4. Get node_db volume id:
``` console
docker volume ls
```

5. Remove cardano-node-ogmios db and copy downloaded:
```
sudo rm -rf /var/lib/docker/volumes/*cardano-node-ogmios_node_db-volume-id*/_data \
sudo mv ./snapshots/db /var/lib/docker/volumes/*cardano-node-ogmios_node_db-volume-id*/_data
```

6. Start cardano-node-ogmios container:

``` console
docker start *container_id*
```

</details>

<details>
  <summary><b>API Status Check</b></summary>

Raw CURL query examples:
  
``` console
curl 0.0.0.0:8050/rpc/tip
```
``` console
curl 0.0.0.0:8050/rpc/blocks
```

</details>

<details>
  <summary><b>TypeScript Client</b></summary>
  
We recommend to use `cardano-koios-client`. Visit [cardano-koios-client](https://github.com/xray-network/cardano-koios-client) repo for more information.

</details>

<details>
  <summary><b>Postgresql Config</b></summary>
  
Config files (see end of file): 

- mainnet: config/postgresql/postgresql.mainnet.conf
- preprod: config/postgresql/postgresql.preprod.conf
- preview: config/postgresql/postgresql.preview.conf

Use https://pgtune.leopard.in.ua/ to tune the database settings

</details>

<details>
  <summary><b>Updating Git Submodules</b></summary>

If you are upgrading a version, you may have to upgrade all the submodule dependencies

``` console
git submodule update --recursive --remote --merge
```

</details>

<details>
  <summary><b>Koios Custom RPCs & Cron Tasks</b></summary>
  
Place the `.sql` files in the `koios/extra-rpc` folder to register with Postgrest. Place the .sh files in `koios/extra-cron-jobs` and edit the `koios/cron-schedule`.

Then you must rebuild container with `--force-rebuild` command.

</details>

<details>
  <summary><b>Using in Graph Cluster (Traefik Reverse Proxy)</b></summary>

1. Clone and run Traefik:
``` console
git clone https://github.com/xray-network/traefik-docker.git \
&& cd traefik-docker \
&& docker compose -up d
```

2. Set `BEARER_RESOLVER_TOKEN` and `docker-compose.xray.yaml`:
``` console
NETWORK=mainnet \
POSTGRES_PASSWORD=your_secret_password \
BEARER_RESOLVER_TOKEN=your_access_token \
docker compose -f docker-compose.xray.yaml -p koios-tiny-mainnet up -d --build
```

</details>

## Documentation

* OpenAPI Schema - https://graph.xray.app/output/services/koios/mainnet/api/v1/
* XRAY/Graph — https://xray.app/
* TypeScript Client — https://github.com/xray-network/cardano-koios-client
* Original Koios — https://koios.rest/
* Original Koios OpenAPI Schema — https://api.koios.rest/
* Cardano-Db-Sync — https://github.com/IntersectMBO/cardano-db-sync/
* Ogmios — https://ogmios.dev/
* Traefik — https://traefik.io/traefik


## System Requirements
  
In general, this stack loads the system in the same way as `cardano-db-sync`, so the minimal system requirements will be the same:

* Any of the big well known Linux distributions (eg, Debian, Ubuntu, RHEL, CentOS, Arch etc).
* 64 Gigabytes of RAM or more.
* 4 CPU cores or more.
* Ensure that the machine has sufficient IOPS (Input/Output Operations per Second). Ie it should be 100k IOPS or better. Lower IOPS ratings will result in slower sync times and/or falling behind the chain tip.
* Minimum 1000 Gigabytes or more of SSD disk storage.
  
When building an application that will be querying the database, remember that for fast queries, low latency disk access is far more important than high throughput (assuming the minimal IOPS above is met).

