#!/bin/bash
# Ubuntu 26's archive ships SWI-Prolog 9.2.9. This project requires SWI 10.
# The devel PPA InRelease is signed twice, and one signature is the old
# 1024-bit Launchpad key. apt on Ubuntu 26 rejects that file, so a signed
# apt source never becomes a candidate. Fetch the package index and the
# swi-prolog-nox deb over HTTPS and let apt install it from disk.
#
# A Launchpad outage would otherwise fail every run, so the deb is kept in
# SWIPL_DEB_CACHE, a directory the workflow restores from and saves to the
# Actions cache. The index decides which deb is current: a kept copy with
# the index's SHA256 is installed without a download, and when Launchpad
# does not answer the kept copy is installed as it is.
set -euo pipefail

. /etc/os-release
arch=$(dpkg --print-architecture)
echo "OS ${PRETTY_NAME:-unknown} codename=${VERSION_CODENAME:-} arch=${arch}"

sudo apt-get update -q
sudo apt-get install -y ca-certificates curl

base="https://ppa.launchpadcontent.net/swi-prolog/devel/ubuntu"
store="${SWIPL_DEB_CACHE:-$(mktemp -d)}/${VERSION_CODENAME}-${arch}"
mkdir -p "$store"

# fetch URL FILE: timeouts and connection failures are retried.
fetch() {
  curl -fsSL --connect-timeout 15 --max-time 120 --retry 3 --retry-connrefused \
    -o "$2" "$1"
}

# sha_ok FILE SHA256
sha_ok() {
  [ -s "$1" ] && [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ]
}

ver=""; file=""; sha=""
idx=$(mktemp)
if fetch "${base}/dists/${VERSION_CODENAME}/main/binary-${arch}/Packages.gz" "$idx"; then
  read -r ver file sha < <(gzip -dc "$idx" | awk '
    BEGIN { RS=""; FS="\n" }
    $0 ~ /(^|\n)Package: swi-prolog-nox(\n|$)/ {
      ver=""; fn=""; sum=""
      for (i=1; i<=NF; i++) {
        if ($i ~ /^Version: 10\./) { sub(/^Version: /, "", $i); ver=$i }
        if ($i ~ /^Filename: /) { sub(/^Filename: /, "", $i); fn=$i }
        if ($i ~ /^SHA256: /) { sub(/^SHA256: /, "", $i); sum=$i }
      }
      if (ver != "" && fn != "" && sum != "") { print ver, fn, sum; exit }
    }
  ') || true
  if [ -z "$ver" ] || [ -z "$file" ] || [ -z "$sha" ]; then
    echo "No SWI-Prolog 10 candidate for ${VERSION_CODENAME} ${arch}"
    exit 1
  fi
else
  echo "Launchpad package index unreachable"
fi
rm -f "$idx"

deb=""; new=""
if [ -n "$file" ]; then
  want="${store}/${file##*/}"
  if sha_ok "$want" "$sha"; then
    echo "Using cached ${want##*/}"
    deb="$want"
  elif fetch "${base}/${file}" "${want}.part" && sha_ok "${want}.part" "$sha"; then
    rm -f "$store"/*.deb
    mv "${want}.part" "$want"
    deb="$want"; new=true
  else
    echo "Launchpad download failed or did not match its SHA256: ${file}"
    rm -f "${want}.part"
  fi
fi

if [ -z "$deb" ]; then
  for kept in "$store"/swi-prolog-nox_10.*.deb; do
    if [ -s "$kept" ]; then deb="$kept"; fi
  done
  if [ -z "$deb" ]; then
    echo "No SWI-Prolog 10 package: Launchpad did not deliver one and no copy is cached"
    exit 1
  fi
  echo "Launchpad did not deliver the package, installing cached ${deb##*/}"
fi

echo "Installing ${deb##*/}"
sudo apt-get install -y "$deb"

swipl --version
swipl -g 'current_prolog_flag(version,V),(V>=100000->halt(0);halt(1))' -t 'halt(1)'

# Only a deb that installed and runs is handed to the workflow's cache save.
if [ -n "$new" ] && [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "deb_new=true"
    echo "deb_name=${deb##*/}"
  } >> "$GITHUB_OUTPUT"
fi
