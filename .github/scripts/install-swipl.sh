#!/bin/bash
# Ubuntu 26's archive ships SWI-Prolog 9.2.9. This project requires SWI 10,
# from the swi-prolog/devel PPA. directory_member/3 in 9.2.9 has no
# file_type(regular) clause, so os:find_files/3 matches nothing.
set -euo pipefail

. /etc/os-release
echo "OS ${PRETTY_NAME:-unknown} codename=${VERSION_CODENAME:-}"

sudo apt-get update -q
sudo apt-get install -y ca-certificates curl gnupg software-properties-common

key=$(curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xE8B739E3753FF4A12360BA6A4AB3A5F60EA9AEB3")
sudo mkdir -p /etc/apt/keyrings
printf '%s\n' "$key" | gpg --batch --yes --dearmor -o /tmp/swi-prolog-devel.gpg
sudo mv /tmp/swi-prolog-devel.gpg /etc/apt/keyrings/swi-prolog-devel.gpg

sudo tee /etc/apt/sources.list.d/swi-prolog-devel.sources >/dev/null <<EOF
Types: deb
URIs: https://ppa.launchpadcontent.net/swi-prolog/devel/ubuntu
Suites: ${VERSION_CODENAME}
Components: main
Signed-By: /etc/apt/keyrings/swi-prolog-devel.gpg
EOF

sudo apt-get update
echo "---- madison after deb822 ----"
apt-cache madison swi-prolog || true

pkgver=$(apt-cache madison swi-prolog | awk '$3 ~ /^10\./ { print $3; exit }')
if [ -z "${pkgver}" ]; then
  echo "deb822 source did not publish a SWI 10 candidate; trying add-apt-repository"
  sudo add-apt-repository -y ppa:swi-prolog/devel
  sudo apt-get update
  echo "---- madison after add-apt-repository ----"
  apt-cache madison swi-prolog || true
  pkgver=$(apt-cache madison swi-prolog | awk '$3 ~ /^10\./ { print $3; exit }')
fi

if [ -z "${pkgver}" ]; then
  echo "No SWI-Prolog 10 candidate for ${VERSION_CODENAME}"
  exit 1
fi

sudo apt-get install -y "swi-prolog=${pkgver}"
swipl --version
swipl -g 'current_prolog_flag(version,V),(V>=100000->halt(0);halt(1))' -t 'halt(1)'
