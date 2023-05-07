#!/bin/bash
DB_NAME=cexplorer

echo "$(date +%F_%H:%M:%S) Running active stake cache update..."

# High level check in db to see if update needed at all (should be updated only once on epoch transition)
[[ $(psql ${DB_NAME} -qbt -c "SELECT grest.active_stake_cache_update_check();" | tail -2 | tr -cd '[:alnum:]') != 't' ]] &&
  echo "No update needed, exiting..." &&
  exit 0

logs_last_epoch_stakes_count=$(echo "${last_epoch_stakes_log}" | cut -d\  -f1)
logs_last_epoch_no=$(echo "${last_epoch_stakes_log}" | cut -d\  -f3)

db_last_epoch_no=$(psql ${DB_NAME} -qbt -c "SELECT MAX(NO) from EPOCH;" | tr -cd '[:alnum:]')
psql ${DB_NAME} -qbt -c "SELECT GREST.active_stake_cache_update(${db_last_epoch_no});" 2>&1 1>/dev/null

echo "$(date +%F_%H:%M:%S) Job done!"
