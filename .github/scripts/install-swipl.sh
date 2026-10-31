#!/bin/bash
# Ubuntu 26's archive ships SWI-Prolog 9.2.9 and keeps it as the apt
# candidate even after the devel PPA is enabled. directory_member/3 in
# 9.2.9 has no file_type(regular) clause, so os:find_files/3 matches
# nothing. This project requires SWI 10: install that version explicitly.
set -euo pipefail

. /etc/os-release
echo "OS ${PRETTY_NAME:-unknown} codename=${VERSION_CODENAME:-}"

sudo apt-get update -q
sudo apt-get install -y software-properties-common ca-certificates
sudo add-apt-repository -y ppa:swi-prolog/devel
sudo apt-get update
echo "---- policy ----"
apt-cache policy swi-prolog || true
echo "---- madison ----"
apt-cache madison swi-prolog || true

pkgver=$(apt-cache madison swi-prolog | awk '$3 ~ /^10\./ { print $3; exit }')
if [ -z "${pkgver}" ]; then
  echo "No SWI-Prolog 10 candidate for ${VERSION_CODENAME}"
  exit 1
fi

sudo apt-get install -y "swi-prolog=${pkgver}"
swipl --version
swipl -g 'current_prolog_flag(version,V),(V>=100000->halt(0);halt(1))' -t 'halt(1)'
