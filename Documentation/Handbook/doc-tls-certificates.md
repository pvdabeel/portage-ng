# TLS Certificates (client/server mode)

When running in `--mode server` or `--mode client`, portage-ng uses mutual TLS
authentication. It expects a local CA and per-host certificates under
`Certificates/`:

- `cacert.pem` / `cakey.pem`
- `<hostname>.server-cert.pem` / `<hostname>.server-key.pem`
- `<hostname>.client-cert.pem` / `<hostname>.client-key.pem`

These files are intentionally **not committed** to the repository.

## Generating certificates

To generate a full set of certificates locally:

```bash
make certs HOST="$(hostname)"
```

If your environment uses a `.local` hostname (e.g. `mac-pro.local`), pass that
exact value so it matches `config:hostname/1`:

```bash
make certs HOST="mac-pro.local"
```

## What gets generated

The `make certs` target creates:

1. A self-signed CA (`cacert.pem` + `cakey.pem`)
2. A server certificate and key signed by the CA
3. A client certificate and key signed by the CA

Both server and client certificates embed the hostname as the Common Name (CN),
which portage-ng verifies during the TLS handshake.

## Cluster usage

When running a distributed cluster (`--mode server` + `--mode worker`), every
node needs:

- A copy of the same `cacert.pem` (shared trust root)
- Its own host-specific server and/or client certificate pair

The mDNS/Bonjour discovery mechanism advertises the hostname, and TLS ensures
that only nodes sharing the same CA can join the cluster.
