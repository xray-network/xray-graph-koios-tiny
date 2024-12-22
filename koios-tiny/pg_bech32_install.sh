#!/usr/bin/env bash

printf "Installing pg_bech32 extension.."
mkdir	~/git
pushd ~/git >/dev/null || err_exit
if command -v apt-get >/dev/null; then
  pkg_installer="env NEEDRESTART_MODE=a env DEBIAN_FRONTEND=noninteractive env DEBIAN_PRIORITY=critical apt-get"
  pkg_list="curl git build-essential make gcc g++ autoconf autoconf-archive automake libtool pkg-config postgresql-server-dev-all"
fi
${pkg_installer} update && ${pkg_installer} -y install ${pkg_list} --upgrade >/dev/null || err_exit "'${pkg_installer} -y install ${pkg_list}' failed!"
[[ ! -d "libbech32" ]] && git clone https://github.com/whitslack/libbech32 >/dev/null
pushd libbech32 || err_exit
mkdir -p build-aux/m4
curl -sf https://raw.githubusercontent.com/NixOS/patchelf/master/m4/ax_cxx_compile_stdcxx.m4 -o build-aux/m4/ax_cxx_compile_stdcx.m4
autoreconf -i
./configure >/dev/null
make clean >/dev/null
make > /dev/null
make install >/dev/null
export LD_LIBRARY_PATH=/usr/local/lib:$LD_LIBRARY_PATH
export PKG_CONFIG_PATH=/usr/local/lib:$PKG_CONFIG_PATH
ldconfig
pushd ~/git >/dev/null || err_exit
[[ ! -d "pg_bech32" ]] && git clone https://github.com/cardano-community/pg_bech32 >/dev/null
cd pg_bech32 || err_exit
make clean && make >/dev/null
make install >/dev/null
