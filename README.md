<a href="https://discord.gg/WhZmm46APN">
  <img src="https://img.shields.io/discord/852538978946383893?label=Discord&style=for-the-badge"
</a>
  
# RayGraph Output — Cardano Explorer API

RayGraph-Output is a dockered Cardano blockchain explorer API tool based on [Koios](https://koios.rest) and [Cardano-Db-Sync](https://github.com/input-output-hk/cardano-db-sync). Extended with GraphQL (Postgraphile custom resolvers). Visit [RayGraph.io](https://raygraph.io) for more information.

## Getting Started

``` console
git clone \
  --recurse-submodules \
  https://ray-robot@github.com/ray-network/raygraph-output.git \
  && cd raygraph-output
```
``` console
cp .env.example .env
```
  
#### Build and Run via Docker Compose
  
>If you are restoring the database (RESTORE_SNAPSHOT flag), make sure that the koios-lite container is stopped. It should be started as soon as cardano-db-sync picks up the last blocks from the node (you can check this with `docker compose logs cardano-db-sync`). And then run `docker compose start koios-lite`. [Issue #3](https://github.com/ray-network/raygraph-output/issues/3)
  
<details open>
  <summary><i>mainnet</i></summary>

Get the most recent weekly snapshot link [here](https://update-cardano-mainnet.iohk.io/cardano-db-sync/index.html#13.1/), and set it as `RESTORE_SNAPSHOT` below, or omit if you wish to sync from genesis.
``` console
RESTORE_SNAPSHOT=https://update-cardano-mainnet.iohk.io/cardano-db-sync/13.1/db-sync-snapshot-schema-13.1-block-8841781-x86_64.tgz \
docker compose up -d --build && \
docker compose stop koios-lite
```
</details>
  
<details>
  <summary><i>preprod</i></summary>

``` console
NETWORK=preprod \
KOIOS_LITE_PORT=8051 \
SUBMITTX_PORT=8701
OGMIOS_PORT=1338 \
docker compose -p preprod up -d --build && \
docker compose stop koios-lite
```

</details>
  
<details>
  <summary><i>preview</i></summary>

``` console
NETWORK=preview \
KOIOS_LITE_PORT=8052 \
SUBMITTX_PORT=8702
OGMIOS_PORT=1339 \
docker compose -p preview up -d --build &&\
docker compose stop koios-lite
```

</details>
