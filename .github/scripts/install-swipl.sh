#!/bin/bash
# Ubuntu 26's archive ships SWI-Prolog 9.2.9. This project requires SWI 10.
# The devel PPA InRelease is signed twice, and one signature is the old
# 1024-bit Launchpad key. apt on Ubuntu 26 rejects that file, so a signed
# apt source never becomes a candidate. Fetch the package index and the
# swi-prolog-nox deb over HTTPS and let apt install it from disk.
set -euo pipefail

. /etc/os-release
arch=$(dpkg --print-architecture)
echo "OS ${PRETTY_NAME:-unknown} codename=${VERSION_CODENAME:-} arch=${arch}"

sudo apt-get update -q
sudo apt-get install -y ca-certificates curl

base="https://ppa.launchpadcontent.net/swi-prolog/devel/ubuntu"
pkgs=$(mktemp)
curl -fsSL "${base}/dists/${VERSION_CODENAME}/main/binary-${arch}/Packages.gz" | gzip -dc > "$pkgs"

read -r ver file < <(awk '
  BEGIN { RS=""; FS="\n" }
  $0 ~ /(^|\n)Package: swi-prolog-nox(\n|$)/ {
    ver=""; fn=""
    for (i=1; i<=NF; i++) {
      if ($i ~ /^Version: 10\./) { sub(/^Version: /, "", $i); ver=$i }
      if ($i ~ /^Filename: /) { sub(/^Filename: /, "", $i); fn=$i }
    }
    if (ver != "" && fn != "") { print ver, fn; exit }
  }
' "$pkgs")
rm -f "$pkgs"

if [ -z "${ver:-}" ] || [ -z "${file:-}" ]; then
  echo "No SWI-Prolog 10 candidate for ${VERSION_CODENAME} ${arch}"
  exit 1
fi

echo "Installing swi-prolog-nox ${ver}"
echo "From ${file}"
deb=$(mktemp --suffix=.deb)
curl -fsSL -o "$deb" "${base}/${file}"
sudo apt-get install -y "$deb"
rm -f "$deb"

swipl --version
swipl -g 'current_prolog_flag(version,V),(V>=100000->halt(0);halt(1))' -t 'halt(1)'
