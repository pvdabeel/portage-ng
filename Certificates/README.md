# Certificates

TLS certificates and keys for portage-ng client/server mode.

## Generating certificates

Use the Makefile target from the project root:

```bash
make certs HOST=mac-pro.local
```

This runs `Certificates/Scripts/generate.sh`, which creates:

- A local CA (`cacert.pem` + `cakey.pem`)
- Per-host client and server certificate/key pairs

## Checking and renewing certificates

```bash
make certs-check    # show expiry status for all hosts
make certs-renew    # renew any certs expiring within 30 days
```

Or use the script directly for more control:

```bash
sh Certificates/Scripts/generate.sh --check              # check all hosts
sh Certificates/Scripts/generate.sh --check mac-pro.local # check one host
sh Certificates/Scripts/generate.sh --renew              # renew expired (all hosts)
sh Certificates/Scripts/generate.sh --renew mac-pro.local # renew expired (one host)
sh Certificates/Scripts/generate.sh --renew-all          # renew all unconditionally
```

## File layout

| File | Tracked | Description |
|------|---------|-------------|
| `cacert.pem` | Yes | CA certificate (shared across hosts) |
| `cakey.pem` | No | CA private key |
| `cacert.srl` | No | CA serial number file |
| `passwordfile` | Yes | HTTP digest authentication password file |
| `<host>.server-cert.pem` | Yes | Server certificate for `<host>` |
| `<host>.server-key.pem` | No | Server private key for `<host>` |
| `<host>.client-cert.pem` | Yes | Client certificate for `<host>` |
| `<host>.client-key.pem` | No | Client private key for `<host>` |
| `Scripts/generate.sh` | Yes | Certificate generation script |

Private keys (`*-key.pem`, `cakey.pem`) and the serial file (`cacert.srl`)
are excluded via `.gitignore`.

## Usage

Certificate paths are resolved at runtime by `config:certificate/2` and
`config:digest_passwordfile/1` in `Source/config.pl`. See
[Documentation/Handbook/doc-tls-certificates.md](../Documentation/Handbook/doc-tls-certificates.md)
for the full TLS setup guide.
