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
  
<details open>
  <summary>MAINNET</summary>

Get the most recent weekly snapshot link [here](https://update-cardano-mainnet.iohk.io/cardano-db-sync/index.html#13.1/), and set it as `RESTORE_SNAPSHOT` below, or omit if you wish to sync from genesis.
``` console
RESTORE_SNAPSHOT=https://update-cardano-mainnet.iohk.io/cardano-db-sync/13.1/db-sync-snapshot-schema-13.1-block-8841781-x86_64.tgz \
docker compose up -d --build && \
docker compose stop koios-lite
```
  
>If you are restoring the database (RESTORE_SNAPSHOT flag), make sure that the koios-lite container is stopped. It should be started as soon as cardano-db-sync picks up the last blocks from the node (you can check this with `docker compose logs cardano-db-sync`). This procedure takes about 4 hours with epoch 413 snapshot when using a fast NVMe SSD (~1M IOPS), keep that in mind. And then run `docker compose start koios-lite`. [Issue #3](https://github.com/ray-network/raygraph-output/issues/3)
  
</details>
  
<details>
  <summary>PREPROD</summary>

``` console
NETWORK=preprod \
KOIOS_LITE_PORT=8051 \
SUBMITTX_PORT=8701
OGMIOS_PORT=1338 \
docker compose -p preprod up -d --build
```

</details>
  
<details>
  <summary>PREVIEW</summary>

``` console
NETWORK=preview \
KOIOS_LITE_PORT=8052 \
SUBMITTX_PORT=8702
OGMIOS_PORT=1339 \
docker compose -p preview up -d --build
```

</details>


## OpenAPI Sandbox
  
Visit https://api.koios.rest/ for API testing and usage (accessing, filtering, sorting, etc...). CURL examples:
  
``` console
curl 0.0.0.0:8050/tip
```
``` console
curl 0.0.0.0:8050/blocks
```
  
## TypeScript Client
  
We recommend to use `koios-tiny-client`. Visit https://github.com/ray-network/koios-tiny-client for more information.
  
## Advanced Usage
  
<details>
  <summary>Nginx Template</summary>

By default, all container ports are bound to 127.0.0.1, so these ports are not available outside the server. Replace `127.0.0.1:${KOIOS_LITE_PORT:-8050}:8050` with `${KOIOS_LITE_PORT:-8050}:8050` if you want to open ports for external access.

Nginx should handle routes with this configuration (see `nginx.template` file):
  
``` nginx
server {
        listen 80;
        listen [::]:80;

        server_name mainnet.blockchain.raygraph.io;

        location = / {
                proxy_pass http://0.0.0.0:8050;
        }

        location / {
                proxy_pass http://0.0.0.0:8050/rpc/;
        }

        location ~ /(account_list\b|asset_list\b|asset_token_registry\b|blocks\b) {
                proxy_pass http://0.0.0.0:8050;
        }

        location /submittx {
                proxy_pass http://0.0.0.0:8700;
        }
}

server {
        listen 443 ssl;
        ssl_certificate /ssl/raygraph.io.crt;
        ssl_certificate_key /ssl/raygraph.io.key;

        server_name mainnet.blockchain.raygraph.io;

        location = / {
                proxy_pass http://0.0.0.0:8050;
        }

        location / {
                proxy_pass http://0.0.0.0:8050/rpc/;
        }

        location ~ /(account_list\b|asset_list\b|asset_token_registry\b|blocks\b) {
                proxy_pass http://0.0.0.0:8050;
        }

        location /submittx {
                proxy_pass http://0.0.0.0:8700;
        }
}
```

</details>
  
<details>
  <summary>Custom RPCs</summary>

Place the `.sql` files in the `koios-lite/rpc-extra` folder to register with Postgrest. Then rebuild the `koios-lite` container. Read more at https://postgrest.org/en/stable/references/api.html
  
</details>
 
<details>
  <summary>Custom Cron Tasks</summary>
  
Place the .sh files in `koios-lite/cron-jobs-extra` and edit the `koios-lite/cron-schedule`. Then rebuild the `koios-lite` container.
  
</details>
 
<details>
  <summary>GraphQL</summary>
  
The Ray Network team is busy with other projects, so Postgraphile graphql resolvers will be developed in the near future. Stay tuned!
  
</details>
