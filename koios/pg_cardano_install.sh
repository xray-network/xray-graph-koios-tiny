#!/usr/bin/env bash

pushd ~/tmp >/dev/null || err_exit
ARCH=$(uname -m)
pgcardano_asset_url="https://share.koios.rest/api/public/dl/xFdZDfM4/bin/pg_cardano_linux_${ARCH}_v1.0.5-p2.tar.gz"
if curl -sL -f -m 10 -o pg_cardano.tar.gz "${pgcardano_asset_url}"; then
  tar xf pg_cardano.tar.gz &>/dev/null && rm -f pg_cardano.tar.gz
  pushd pg_cardano >/dev/null || err_exit
  [[ -f install.sh ]] || err_exit "pg_cardano tar downloaded but install.sh script not found after attempting to extract package!"
  ./install.sh
fi
