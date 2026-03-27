#!/bin/sh
#
# Manage TLS certificates for portage-ng's mutual-TLS client/server mode.
#
# Usage:
#   sh Certificates/Scripts/generate.sh <hostname>            # generate CA + host certs
#   sh Certificates/Scripts/generate.sh --check [<hostname>]  # check expiry (all or one host)
#   sh Certificates/Scripts/generate.sh --renew [<hostname>]  # renew expired certs (all or one host)
#   sh Certificates/Scripts/generate.sh --renew-all           # renew all host certs unconditionally
#
# Outputs (in Certificates/):
#   - cakey.pem, cacert.pem           (local CA)
#   - <host>.server-key.pem           (server private key)
#   - <host>.server-cert.pem          (server certificate)
#   - <host>.client-key.pem           (client private key)
#   - <host>.client-cert.pem          (client certificate)
#
# Private keys are generated unencrypted. Key files (.pem) should NOT be
# committed to git (they are listed in .gitignore).

set -eu

CERT_DAYS=3650
RENEW_THRESHOLD_DAYS=30

SCRIPTDIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CERTDIR="$(CDPATH= cd -- "${SCRIPTDIR}/.." && pwd)"

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl not found in PATH" >&2
  exit 127
fi

# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------

need() { [ ! -f "$1" ]; }

ensure_ca() {
  if need "${CERTDIR}/cacert.pem" || need "${CERTDIR}/cakey.pem"; then
    echo "Generating local CA (cacert.pem, cakey.pem)..."
    openssl req -x509 -newkey rsa:4096 -nodes \
      -keyout "${CERTDIR}/cakey.pem" \
      -out "${CERTDIR}/cacert.pem" \
      -days "${CERT_DAYS}" \
      -sha256 \
      -subj "/C=XX/O=portage-ng/OU=Local CA/CN=portage-ng local CA"
  fi
}

gen_signed_cert() {
  HOST="$1"
  KIND="$2"   # client|server
  OU="$3"
  KEY="${CERTDIR}/${HOST}.${KIND}-key.pem"
  CSR="${CERTDIR}/${HOST}.${KIND}.csr"
  CRT="${CERTDIR}/${HOST}.${KIND}-cert.pem"

  if need "${KEY}"; then
    echo "  Generating ${KIND} key: ${HOST}.${KIND}-key.pem"
    openssl genrsa -out "${KEY}" 2048
    chmod 600 "${KEY}" || true
  fi

  echo "  Signing ${KIND} certificate: ${HOST}.${KIND}-cert.pem"
  openssl req -new -key "${KEY}" -out "${CSR}" \
    -subj "/C=XX/O=portage-ng/OU=${OU}/CN=${HOST}"

  openssl x509 -req -in "${CSR}" \
    -CA "${CERTDIR}/cacert.pem" -CAkey "${CERTDIR}/cakey.pem" -CAcreateserial \
    -out "${CRT}" \
    -days "${CERT_DAYS}" \
    -sha256 2>/dev/null

  rm -f "${CSR}"
}

generate_host() {
  HOST="$1"
  echo "Generating certificates for ${HOST}..."
  ensure_ca
  gen_signed_cert "${HOST}" "server" "Server - ${HOST}"
  gen_signed_cert "${HOST}" "client" "Client - ${HOST}"
  echo "Done: ${HOST}"
}

# Returns 0 if cert expires within $1 days, 1 otherwise.
cert_expiring() {
  CERT="$1"
  DAYS="${2:-${RENEW_THRESHOLD_DAYS}}"
  [ -f "${CERT}" ] || return 0
  if openssl x509 -in "${CERT}" -checkend "$((DAYS * 86400))" >/dev/null 2>&1; then
    return 1
  else
    return 0
  fi
}

cert_expiry_date() {
  openssl x509 -in "$1" -noout -enddate 2>/dev/null | sed 's/notAfter=//'
}

# List all hostnames that have cert files in the certificates directory.
list_hosts() {
  (cd "${CERTDIR}" && ls -1 *.client-cert.pem 2>/dev/null | sed 's/\.client-cert\.pem$//' | sort -u)
}

check_host() {
  HOST="$1"
  rc=0
  for KIND in server client; do
    CRT="${CERTDIR}/${HOST}.${KIND}-cert.pem"
    if [ ! -f "${CRT}" ]; then
      printf "  %-40s  MISSING\n" "${HOST}.${KIND}-cert.pem"
      rc=1
    elif cert_expiring "${CRT}"; then
      printf "  %-40s  EXPIRED/EXPIRING  (expires %s)\n" "${HOST}.${KIND}-cert.pem" "$(cert_expiry_date "${CRT}")"
      rc=1
    else
      printf "  %-40s  OK  (expires %s)\n" "${HOST}.${KIND}-cert.pem" "$(cert_expiry_date "${CRT}")"
    fi
  done
  return ${rc}
}

# ---------------------------------------------------------------------------
#  Subcommands
# ---------------------------------------------------------------------------

cmd_check() {
  HOST="${1:-}"
  echo "Certificate status (threshold: ${RENEW_THRESHOLD_DAYS} days):"

  if [ -f "${CERTDIR}/cacert.pem" ]; then
    if cert_expiring "${CERTDIR}/cacert.pem"; then
      printf "  %-40s  EXPIRED/EXPIRING  (expires %s)\n" "cacert.pem" "$(cert_expiry_date "${CERTDIR}/cacert.pem")"
    else
      printf "  %-40s  OK  (expires %s)\n" "cacert.pem" "$(cert_expiry_date "${CERTDIR}/cacert.pem")"
    fi
  else
    printf "  %-40s  MISSING\n" "cacert.pem"
  fi

  any_bad=0
  if [ -n "${HOST}" ]; then
    check_host "${HOST}" || any_bad=1
  else
    HOSTS="$(list_hosts)"
    if [ -z "${HOSTS}" ]; then
      echo "  No host certificates found."
    else
      for h in ${HOSTS}; do
        check_host "${h}" || any_bad=1
      done
    fi
  fi
  return ${any_bad}
}

cmd_renew() {
  HOST="${1:-}"
  ensure_ca

  if [ -n "${HOST}" ]; then
    HOSTS="${HOST}"
  else
    HOSTS="$(list_hosts)"
  fi

  if [ -z "${HOSTS}" ]; then
    echo "No host certificates found to renew."
    exit 0
  fi

  renewed=0
  for h in ${HOSTS}; do
    needs_renewal=false
    for KIND in server client; do
      CRT="${CERTDIR}/${h}.${KIND}-cert.pem"
      if [ ! -f "${CRT}" ] || cert_expiring "${CRT}"; then
        needs_renewal=true
        break
      fi
    done
    if [ "${needs_renewal}" = true ]; then
      echo "Renewing certificates for ${h}..."
      gen_signed_cert "${h}" "server" "Server - ${h}"
      gen_signed_cert "${h}" "client" "Client - ${h}"
      renewed=$((renewed + 1))
    else
      echo "Skipping ${h} (not expiring within ${RENEW_THRESHOLD_DAYS} days)."
    fi
  done
  echo "Renewed: ${renewed} host(s)."
}

cmd_renew_all() {
  ensure_ca

  HOSTS="$(list_hosts)"
  if [ -z "${HOSTS}" ]; then
    echo "No host certificates found to renew."
    exit 0
  fi

  for h in ${HOSTS}; do
    echo "Renewing certificates for ${h}..."
    gen_signed_cert "${h}" "server" "Server - ${h}"
    gen_signed_cert "${h}" "client" "Client - ${h}"
  done
  echo "Done: renewed all hosts."
}

# ---------------------------------------------------------------------------
#  Dispatch
# ---------------------------------------------------------------------------

case "${1:-}" in
  --check)
    shift
    cmd_check "${1:-}"
    ;;
  --renew)
    shift
    cmd_renew "${1:-}"
    ;;
  --renew-all)
    cmd_renew_all
    ;;
  --help|-h)
    sed -n '2,/^[^#]/{ /^#/s/^# \{0,1\}//p; }' "$0"
    ;;
  -*)
    echo "error: unknown option: $1" >&2
    echo "usage: sh $0 [--check|--renew|--renew-all] [hostname]" >&2
    exit 2
    ;;
  "")
    echo "error: missing hostname or subcommand" >&2
    echo "usage: sh $0 <hostname>  OR  sh $0 --check|--renew|--renew-all [hostname]" >&2
    exit 2
    ;;
  *)
    generate_host "$1"
    ;;
esac
