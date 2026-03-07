#!/bin/sh
#
# Generate a local CA + per-host client/server keypairs and certificates for
# portage-ng's mutual-TLS client/server mode.
#
# Usage:
#   sh Source/Certificates/generate.sh <hostname>
#
# Outputs (in Source/Certificates/):
#   - cakey.pem
#   - cacert.pem
#   - <hostname>.server-key.pem
#   - <hostname>.server-cert.pem
#   - <hostname>.client-key.pem
#   - <hostname>.client-cert.pem
#
# Notes:
# - Private keys are generated unencrypted for ease-of-use.
# - These files should NOT be committed to git.

set -eu

HOST="${1:-}"
if [ -z "${HOST}" ]; then
  echo "error: missing hostname argument" >&2
  echo "usage: sh Source/Certificates/generate.sh <hostname>" >&2
  exit 2
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl not found in PATH" >&2
  exit 127
fi

CERTDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "${CERTDIR}"

need() { [ ! -f "$1" ]; }

echo "Certificates dir: ${CERTDIR}"
echo "Host: ${HOST}"

if need "cacert.pem" || need "cakey.pem"; then
  echo "Generating local CA (cacert.pem, cakey.pem)..."
  # CA key + self-signed CA certificate
  openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout cakey.pem \
    -out cacert.pem \
    -days 3650 \
    -sha256 \
    -subj "/C=XX/O=portage-ng/OU=Local CA/CN=portage-ng local CA"
else
  echo "CA already exists (cacert.pem, cakey.pem)."
fi

gen_signed_cert() {
  KIND="$1"   # client|server
  OU="$2"
  KEY="${HOST}.${KIND}-key.pem"
  CSR="${HOST}.${KIND}.csr"
  CRT="${HOST}.${KIND}-cert.pem"

  if need "${KEY}"; then
    echo "Generating ${KIND} key: ${KEY}"
    openssl genrsa -out "${KEY}" 2048
    chmod 600 "${KEY}" || true
  else
    echo "${KIND} key exists: ${KEY}"
  fi

  echo "Generating ${KIND} CSR..."
  openssl req -new -key "${KEY}" -out "${CSR}" \
    -subj "/C=XX/O=portage-ng/OU=${OU}/CN=${HOST}"

  echo "Signing ${KIND} certificate: ${CRT}"
  openssl x509 -req -in "${CSR}" \
    -CA cacert.pem -CAkey cakey.pem -CAcreateserial \
    -out "${CRT}" \
    -days 3650 \
    -sha256

  rm -f "${CSR}"
}

gen_signed_cert "server" "Server - ${HOST}"
gen_signed_cert "client" "Client - ${HOST}"

echo "Done."
