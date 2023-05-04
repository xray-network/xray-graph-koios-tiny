#!/usr/bin/env bash

WORKDIR=$WORKDIR
DB_NAME=$(< "$POSTGRES_DB_FILE")
DB_USER=$(< "$POSTGRES_USER_FILE")
DB_PASSWORD=$(< "$POSTGRES_PASSWORD_FILE")

PGDATABASE=${DB_NAME}
export PGRST_DB_URI=postgres://${DB_USER}:${DB_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}

DB_SCRIPTS_DIR=./guild-operators/scripts/grest-helper-scripts/db-scripts
RPC_SCRIPTS_DIR=./koios-artifacts/files/grest/rpc
RPC_EXTRA_SCRIPTS_DIR=./rpc-extra
CRON_SCRIPTS_DIR=./koios-artifacts/files/grest/cron/jobs
CRON_DIR=/etc/cron.d
SHELLEY_GENESIS_JSON=./cardano-configurations/network/${NETWORK}/genesis/shelley.json
ALONZO_GENESIS_JSON=./cardano-configurations/network/${NETWORK}/genesis/alonzo.json

echo "${PGHOST}:${PGPORT}:${PGDATABASE}:${DB_USER}:${DB_PASSWORD}" > $PGPASSFILE
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

reset_grest_schema() {
  local reset_sql_url="${DB_SCRIPTS_DIR}/reset_grest.sql"

  if ! reset_sql=$(< $reset_sql_url); then
    err_exit "Failed to get reset grest SQL from ${reset_sql_url}."
  fi
  printf "\nResetting grest schema..."
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${reset_sql} 2>&1) && err_exit "${output}"
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
  ! is_dir "${CRON_SCRIPTS_DIR}" && mkdir -p "${CRON_SCRIPTS_DIR}"

  echo ""
  get_cron_job_executable "stake-distribution-update"
  set_cron_variables "stake-distribution-update"
  # Special condition for guild network (NWMAGIC=141) where activity and entries are minimal, and epoch duration is 1 hour
  ([[ ${NWMAGIC} -eq 141 ]] && install_cron_job "stake-distribution-update" "*/5 * * * *") ||
    install_cron_job "stake-distribution-update" "*/30 * * * *"

  get_cron_job_executable "stake-distribution-new-accounts-update"
  set_cron_variables "stake-distribution-new-accounts-update"
  ([[ ${NWMAGIC} -eq 141 ]] && install_cron_job "stake-distribution-new-accounts-update" "*/30 * * * *") ||
    install_cron_job "stake-distribution-new-accounts-update" "58 */6 * * *"

  get_cron_job_executable "pool-history-cache-update"
  set_cron_variables "pool-history-cache-update"
  ([[ ${NWMAGIC} -eq 141 ]] && install_cron_job "pool-history-cache-update" "*/5 * * * *") ||
    install_cron_job "pool-history-cache-update" "*/10 * * * *"

  get_cron_job_executable "epoch-info-cache-update"
  set_cron_variables "epoch-info-cache-update"
  ([[ ${NWMAGIC} -eq 141 ]] && install_cron_job "epoch-info-cache-update" "*/5 * * * *") ||
    install_cron_job "epoch-info-cache-update" "*/15 * * * *"

  get_cron_job_executable "active-stake-cache-update"
  set_cron_variables "active-stake-cache-update"
  ([[ ${NWMAGIC} -eq 141 ]] && install_cron_job "active-stake-cache-update" "*/5 * * * *") ||
    install_cron_job "active-stake-cache-update" "*/15 * * * *"

  get_cron_job_executable "stake-snapshot-cache"
  set_cron_variables "stake-snapshot-cache"
  install_cron_job "stake-snapshot-cache" "*/10 * * * *"

  get_cron_job_executable "populate-next-epoch-nonce"
  set_cron_variables "populate-next-epoch-nonce"
  install_cron_job "populate-next-epoch-nonce" "*/10 * * * *"

  get_cron_job_executable "asset-info-cache-update"
  set_cron_variables "asset-info-cache-update"
  install_cron_job "asset-info-cache-update" "* * * * *"

  # Only (legacy) testnet and mainnet asset registries supported
  # In absence of official messaging, current (soon to be reset) preprod/preview networks use same registry as testnet. TBC - once there is an update from IO on these
  # Possible future addition for the Guild network once there is a guild registry
  if [[ ${NWMAGIC} -eq 764824073 || ${NWMAGIC} -eq 1 || ${NWMAGIC} -eq 2 || ${NWMAGIC} -eq 141 ]]; then
    get_cron_job_executable "asset-registry-update"
    set_cron_variables "asset-registry-update"
    # Point the update script to testnet regisry repo structure (default: mainnet)
    [[ ${NWMAGIC} -eq 1 || ${NWMAGIC} -eq 2 || ${NWMAGIC} -eq 141 ]] && set_cron_asset_registry_testnet_variables
    install_cron_job "asset-registry-update" "*/10 * * * *"
  fi
}

deploy_rpc() {
  local rpc_sql_path=${1}
  local rpc_sql=$(< $rpc_sql_path)
  printf "\n      Deploying Function :   \e[32m$(basename ${rpc_sql_path})\e[0m"
#  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${rpc_sql} 2>&1) && printf "\n        \e[31mERROR\e[0m: ${output}"
}

deploy_query_updates() {
  printf "\n\n(Re)Deploying Postgres RPCs/views/schedule..."
  printf "\n\n  (Re)Deploying GRest objects to DBSync..."

  populate_genesis_table
  for d in $RPC_SCRIPTS_DIR/*/; do
    printf "\n\n    Execution pSQL from subdir \"$(basename $d)\""
    for f in $d*.sql; do
      deploy_rpc $f
    done
  done
#  setup_cron_jobs
  printf "\n\nAll RPC functions successfully added to DBSync!\n"
}

deploy_koios() {
  check_db_status
  if [[ $? -eq 1 ]]; then
    err_exit "Please wait for Cardano DBSync to populate PostgreSQL DB at least until Alonzo fork"
  fi
  printf "/nHEYHEYHEY"
  #reset_grest_schema
  #setup_db_basics
  deploy_query_updates

  echo "" > ./.success
  printf "\n\nSERVICES INSTALLED! ALL GOOD!\n\n\n"
}

deploy_extra_rpc() {
  printf "\n(Re)Deploying Extra RPC objects to DBSync..."
  check_db_status
  if [[ $? -eq 1 ]]; then
    err_exit "Please wait for Cardano DBSync to populate PostgreSQL DB at least until Alonzo fork"
  fi

  #extra_rpc

  printf "\n\nEXTRA RPCS INSTALLED! ALL GOOD!\n\n\n"
}

[[ ! -e .success ]] && deploy_koios
[[ $EXTRA = true && ! -e .success ]] && deploy_extra_rpc

postgrest ${WORKDIR}/postgrest.conf

