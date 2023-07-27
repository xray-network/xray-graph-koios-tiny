#!/bin/bash
HOME=/home/postgres

DB_NAME=cexplorer

echo "$(date +%F_%H:%M:%S) Running pool explorer cache update..."
psql ${DB_NAME} -qbt -c "SELECT GREST.pool_explorer_cache_update();" 2>&1 1>/dev/null
echo "$(date +%F_%H:%M:%S) Job done!"
