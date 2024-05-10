#!/bin/bash
HOME=/home/postgres

DB_NAME=cexplorer

tip=$(psql ${DB_NAME} -qbt -c "select extract(epoch from time)::integer from block order by id desc limit 1;" | xargs)

if [[ $(( $(date +%s) - tip )) -gt 300 ]]; then
  echo "$(date +%F_%H:%M:%S) Skipping as database has not received a new block in past 300 seconds!" && exit 1
fi

echo "$(date +%F_%H:%M:%S) Running pool explorer cache update..."
psql ${DB_NAME} -qbt -c "SELECT GREST.pool_explorer_cache_update();" 2>&1 1>/dev/null
echo "$(date +%F_%H:%M:%S) Job done!"
