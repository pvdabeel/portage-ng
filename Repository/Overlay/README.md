# Test Overlay

A synthetic Portage repository containing 80 test categories (`test01`–`test80`), each with a small set of ebuilds designed to exercise a specific aspect of the portage-ng dependency resolver.

## Structure

```
test01/             ← category directory
  app/
    app-1.0.ebuild
  db/
    db-1.0.ebuild
  ...
metadata/
  md5-cache/        ← pre-generated metadata cache
    test01/
      app-1.0
      db-1.0
      ...
  layout.conf       ← masters = gentoo, thin-manifests = true
profiles/
  repo_name         ← "overlay"
```

## Usage

Register as a Portage repository:

```ini
[overlay]
location = /path/to/Repository/Overlay
masters = gentoo
auto-sync = no
```

Test documentation (descriptions, graphs, logs) lives in [`Documentation/Tests/`](../../Documentation/Tests/README.md).
