#!/usr/bin/env bash

WORKDIR=$HOME
PGDATABASE=${POSTGRES_DB}

SHELLEY_GENESIS_JSON=${WORKDIR}/cardano-configurations/network/${NETWORK}/genesis/shelley.json
ALONZO_GENESIS_JSON=${WORKDIR}/cardano-configurations/network/${NETWORK}/genesis/alonzo.json
DB_SCRIPTS_DIR=${WORKDIR}/db-scripts
RPC_SCRIPTS_DIR=${WORKDIR}/rpc
CRON_SCRIPTS_DIR=${WORKDIR}/cron

echo "${POSTGRES_HOST}:${POSTGRES_PORT}:${POSTGRES_DB}:${POSTGRES_USER}:${POSTGRES_PASSWORD}" > $PGPASSFILE
chmod 0600 $PGPASSFILE

err_exit() {
  printf "${FG_RED}ERROR${NC}: ${1}\n" >&2
  echo -e "Exiting...\n" >&2
  pushd -0 >/dev/null && dirs -c
  exit 1
}

check_db_status() {
  if ! command -v psql &>/dev/null; then
    err_exit "We could not find 'psql' binary in \$PATH , please ensure you've followed the instructions below:\n ${DOCS_URL}/Appendix/postgres"
  fi
  if [[ -z ${PGPASSFILE} || ! -f "${PGPASSFILE}" ]]; then
    err_exit "PGPASSFILE env variable not set or pointing to a non-existing file: ${PGPASSFILE}\n ${DOCS_URL}/Build/dbsync"
  fi
  if [[ "$(psql -qtAX -d ${PGDATABASE} -c "SELECT protocol_major FROM public.param_proposal WHERE protocol_major > 4 ORDER BY protocol_major DESC LIMIT 1" 2>/dev/null)" == "" ]]; then
    return 1
  fi

  return 0
}

kill_cron_psql_process() {
  local update_function=$(echo ${1} | tr '-' '_')
  output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -qt \
    -c "select grest.get_query_pids_partial_match('${update_function}');" |
      awk 'BEGIN {ORS = " "} {print $1}' | xargs echo -n)
  printf "\n      Process : ${update_function} PID: \e[32m${output}\e[0m"
  [[ -n "${output}" ]] && psql "${PGDATABASE}" -c "select pg_terminate_backend('${output}');" > /dev/null
}

reset_grest_schema() {
  printf "\nKilling related PSQL cron jobs..."
  kill_cron_psql_process "active-stake-cache-update"
  kill_cron_psql_process "asset-info-cache-update"
  kill_cron_psql_process "asset-registry-update"
  kill_cron_psql_process "epoch-info-cache-update"
  kill_cron_psql_process "pool-history-cache-update"
  kill_cron_psql_process "populate-next-epoch-nonce"
  kill_cron_psql_process "update-newly-registered-accounts-stake-distribution-cache"
  kill_cron_psql_process "stake-distribution-cache-update-check"
  kill_cron_psql_process "capture-last-epoch-snapshot"
  printf "\n  Done!"

  printf "\nResetting grest schema if exists from previous installations..."
  local reset_sql_url="${DB_SCRIPTS_DIR}/reset_grest.sql"
  if ! reset_sql=$(< $reset_sql_url); then
    err_exit "Failed to get reset grest SQL from ${reset_sql_url}."
  fi
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${reset_sql} 2>&1) && err_exit "${output}"
  printf "\n  Done!\n\n"
}

setup_db_basics() {
  local basics_sql_url="${DB_SCRIPTS_DIR}/basics.sql"

  if ! basics_sql=$(< $basics_sql_url); then
    err_exit "Failed to get basic db setup SQL from ${basics_sql_url}"
  fi
  printf "\nAdding grest schema if missing and granting usage for web_anon..."
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${basics_sql} 2>&1) && err_exit "${output}"
  return 0
}

insert_genesis_table_data() {
  local alonzo_genesis=$1
  shift
  local shelley_genesis=("$@")

  psql "${PGDATABASE}" -c "INSERT INTO grest.genesis VALUES (
    '${shelley_genesis[4]}', '${shelley_genesis[2]}', '${shelley_genesis[0]}',
    '${shelley_genesis[1]}', '${shelley_genesis[3]}', '${shelley_genesis[5]}',
    '${shelley_genesis[6]}', '${shelley_genesis[7]}', '${shelley_genesis[8]}',
    '${shelley_genesis[9]}', '${shelley_genesis[10]}', '${alonzo_genesis}'
  );" > /dev/null
}

insert_genesis_table_data() {
  local alonzo_genesis=$1
  shift
  local shelley_genesis=("$@")

  psql "${PGDATABASE}" -c "INSERT INTO grest.genesis VALUES (
    '${shelley_genesis[4]}', '${shelley_genesis[2]}', '${shelley_genesis[0]}',
    '${shelley_genesis[1]}', '${shelley_genesis[3]}', '${shelley_genesis[5]}',
    '${shelley_genesis[6]}', '${shelley_genesis[7]}', '${shelley_genesis[8]}',
    '${shelley_genesis[9]}', '${shelley_genesis[10]}', '${alonzo_genesis}'
  );" > /dev/null
}

populate_genesis_table() {
  read -ra SHGENESIS <<<$(jq -r '[
    .activeSlotsCoeff,
    .updateQuorum,
    .networkId,
    .maxLovelaceSupply,
    .networkMagic,
    .epochLength,
    .systemStart,
    .slotsPerKESPeriod,
    .slotLength,
    .maxKESEvolutions,
    .securityParam
    ] | @tsv' <"${SHELLEY_GENESIS_JSON}")
  ALGENESIS="$(jq -c . <"${ALONZO_GENESIS_JSON}")"

  insert_genesis_table_data "${ALGENESIS}" "${SHGENESIS[@]}"
}

setup_cron_jobs() {
  printf "\n\n  (Re)Deploying Cron jobs..."
  printf "\n\n    Execution jobs..."

  for cron_file in $CRON_SCRIPTS_DIR/*.sh; do
    cron_file_name=$(basename $cron_file)
    cron_file_name_no_ext=${cron_file_name%.*}

    [[ ${PGDATABASE} != cexplorer ]] && sed -e "s@DB_NAME=.*@DB_NAME=${PGDATABASE}@" -i "$cron_file"
    sed -i "2i HOME=${WORKDIR}\n" "$cron_file"

    printf "\n      Updating Cron Variables:   \e[32m$cron_file_name_no_ext\e[0m"

    if [[ $cron_file_name_no_ext == "asset-registry-update" ]]; then
      if [[ $NETWORK == "mainnet" ]]
      then
        printf "\n        Custom Rule: Mainnet registry ENV updated!"
        [[ -d "/var/lib/postgresql/git/cnode-token-registry" ]] && find "/var/lib/postgresql/git/cnode-token-registry" -mindepth 2 -maxdepth 2 -type f -name "*.json" -exec touch {} +
      else
        printf "\n        Custom Rule: Testnet registry ENV updated!"
        sed -e "s@CNODE_VNAME=.*@CNODE_VNAME=cnode@" \
          -e "s@TR_URL=.*@TR_URL=https://github.com/input-output-hk/metadata-registry-testnet@" \
          -e "s@TR_SUBDIR=.*@TR_SUBDIR=registry@" \
          -i "${CRON_SCRIPTS_DIR}/asset-registry-update.sh"
      fi
      continue
    fi
  done

  pkill -f crond
  crond -b -l 8
}

deploy_rpc() {
  local rpc_sql_path=${1}
  local rpc_sql=$(< $rpc_sql_path)

  printf "\n      Deploying Function :   \e[32m$(basename ${rpc_sql_path})\e[0m"
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${rpc_sql} 2>&1) && printf "\n        \e[31mERROR\e[0m: ${output}"
}

deploy_rpcs() {
  printf "\n\n    Execution pSQL from subdir \"/\""
  for f in ${RPC_SCRIPTS_DIR}/*.sql; do
    deploy_rpc $f
  done

  for d in $RPC_SCRIPTS_DIR/*/; do
    printf "\n\n    Execution pSQL from subdir \"$(basename $d)\""
    for f in $d*.sql; do
      deploy_rpc $f
    done
  done
}

deploy_query_updates() {
  printf "\n\n(Re)Deploying Postgres RPCs/views/schedule..."
  printf "\n\n  (Re)Deploying GRest objects to DBSync..."

  populate_genesis_table
  deploy_rpcs
  setup_cron_jobs

  printf "\n\nAll RPC functions successfully added to DBSync!"
}

deploy_koios() {
  check_db_status
  if [[ $? -eq 1 ]]; then
    err_exit "Please wait for Cardano DBSync to populate PostgreSQL DB at least until Alonzo fork"
  fi

  reset_grest_schema
  setup_db_basics
  deploy_query_updates

  touch .success
  printf "\n\nSERVICES INSTALLED! ALL GOOD!\n\n\n"
}

# Check if success installation file not exist, and run the installation
[[ ! -e .success ]] && deploy_koios

postgrest ${WORKDIR}/postgrest.conf
