#!/usr/bin/env bash

SETUP=true

WORKDIR=/home/postgres
DB_NAME=$(cat "$POSTGRES_DB_FILE")
DB_USER=$(cat "$POSTGRES_USER_FILE")
DB_PASSWORD=$(cat "$POSTGRES_PASSWORD_FILE")

PGDATABASE=${DB_NAME}
export PGRST_DB_URI=postgres://${DB_USER}:${DB_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}
export PGPASSFILE=${WORKDIR}/.pgpass

CRON_SCRIPTS_DIR=./koios-artifacts/files/grest/cron/jobs/
CRON_DIR=/etc/cron.d

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
  local reset_sql_url="${DB_SCRIPTS_URL}/reset_grest.sql"

  if ! reset_sql=$(curl -s -f -m "${CURL_TIMEOUT}" "${reset_sql_url}" 2>&1); then
    err_exit "Failed to get reset grest SQL from ${reset_sql_url}."
  fi
  printf "\nResetting grest schema..."
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${reset_sql} 2>&1) && err_exit "${output}"
}

setup_db_basics() {
  local basics_sql_url="${DB_SCRIPTS_URL}/basics.sql"

  if ! basics_sql=$(curl -s -f -m "${CURL_TIMEOUT}" "${basics_sql_url}" 2>&1); then
    err_exit "Failed to get basic db setup SQL from ${basics_sql_url}"
  fi
  printf "\nAdding grest schema if missing and granting usage for web_anon..."
  ! output=$(psql "${PGDATABASE}" -v "ON_ERROR_STOP=1" -q <<<${basics_sql} 2>&1) && err_exit "${output}"
  return 0
}

setup_authenticator() {
  printf "\n[Re]Allowing Postgres access.."
  echo "${PGHOST}:${PGPORT}:${PGDATABASE}:${DB_USER}:${DB_PASSWORD}" > $PGPASSFILE
  chmod 0600 $PGPASSFILE
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
    ] | @tsv' <"${GENESIS_JSON}")
  ALGENESIS="$(jq -c . <"${ALONZO_GENESIS_JSON}")"

  insert_genesis_table_data "${ALGENESIS}" "${SHGENESIS[@]}"
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

deploy_query_updates() {
  printf "\n(Re)Deploying Postgres RPCs/views/schedule...\n"
  check_db_status
  if [[ $? -eq 1 ]]; then
    err_exit "Please wait for Cardano DBSync to populate PostgreSQL DB at least until Alonzo fork, and then re-run this setup script with the -q flag."
  fi

  printf "\n  Downloading DBSync RPC functions from Guild Operators GitHub store..."
  if ! rpc_file_list=$(curl -s -f -m ${CURL_TIMEOUT} https://api.github.com/repos/${G_ACCOUNT}/koios-artifacts/contents/files/grest/rpc?ref=v${SGVERSION} 2>&1); then
    err_exit "${rpc_file_list}"
  fi
  printf "\n  (Re)Deploying GRest objects to DBSync..."
  populate_genesis_table
  for row in $(jq -r '.[] | @base64' <<<${rpc_file_list}); do
    if [[ $(jqDecode '.type' "${row}") = 'dir' ]]; then
      printf "\n    Downloading pSQL executions from subdir $(jqDecode '.name' "${row}")"
      if ! rpc_file_list_subdir=$(curl -s -m ${CURL_TIMEOUT} "https://api.github.com/repos/${G_ACCOUNT}/koios-artifacts/contents/files/grest/rpc/$(jqDecode '.name' "${row}")?ref=v${SGVERSION}"); then
        printf "\n      \e[31mERROR\e[0m: ${rpc_file_list_subdir}" && continue
      fi
      for row2 in $(jq -r '.[] | @base64' <<<${rpc_file_list_subdir}); do
        deploy_rpc ${row2}
      done
    else
      deploy_rpc ${row}
    fi
  done
  setup_cron_jobs
  printf "\n  All RPC functions successfully added to DBSync! For detailed query specs and examples, visit ${API_DOCS_URL}!\n"
  printf "\nRestarting PostgREST to clear schema cache..\n"
  sudo systemctl restart ${CNODE_VNAME}-postgrest.service && printf "\nDone!!\n"
}

deploy_koios() {
  setup_authenticator
  check_db_status
  if [[ $? -eq 1 ]]; then
    err_exit "Please wait for Cardano DBSync to populate PostgreSQL DB at least until Alonzo fork, and then re-run this setup script with the -q flag."
  fi
  #reset_grest_schema
  #setup_db_basics
  #deploy_query_updates

  echo "SERVICES INSTALLED! ALL GOOD!"
}

[[ $SETUP = true ]] && deploy_koios 

postgrest ${WORKDIR}/postgrest.conf

