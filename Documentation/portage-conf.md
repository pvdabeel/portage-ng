# /etc/portage Configuration Support

portage-ng can read Gentoo's standard `/etc/portage/` configuration files,
making it a drop-in replacement for dependency resolution and plan computation.

## Quick start

Set `config:portage_confdir/1` in `Source/config.pl` to point at your
configuration directory:

```prolog
config:portage_confdir('/etc/portage').
```

For development, use the bundled templates:

```prolog
config:portage_confdir('Source/Config/Gentoo').
```

Comment the predicate out (or leave it undefined) to fall back to the
legacy `config:gentoo_env/2` and `config:gentoo_package_*/1-2` facts.

## Supported files

| File | Gentoo path | portage-ng mapping | Notes |
|------|-------------|-------------------|-------|
| `make.conf` | `/etc/portage/make.conf` | `gentoo:env/2` → feeds `preference:getenv/2` | USE, ACCEPT_KEYWORDS, ACCEPT_LICENSE, VIDEO_CARDS, INPUT_DEVICES, CPU_FLAGS_X86, PYTHON_TARGETS, etc. |
| `package.use` | `/etc/portage/package.use` | `preference:gentoo_package_use_soft/3`, `preference:package_use_override/4` | Per-package USE flag overrides |
| `package.mask` | `/etc/portage/package.mask` | `preference:masked/1` | User package masks |
| `package.unmask` | `/etc/portage/package.unmask` | Retracts `preference:masked/1` | Overrides profile-level masks |
| `package.accept_keywords` | `/etc/portage/package.accept_keywords` | `gentoo:package_keyword/2` | Per-package keyword acceptance |
| `package.license` | `/etc/portage/package.license` | `gentoo:package_license_entry/2` | Per-package license acceptance |

## File format

All files follow standard Gentoo syntax:

- Lines starting with `#` are comments
- Empty lines are ignored
- Inline `#` comments are stripped

### make.conf

Bash-style `KEY="value"` assignments. Parsed by the same engine that reads
profile `make.defaults` files (`profile:make_defaults_kv/2`).

```bash
USE="X alsa dbus -systemd"
ACCEPT_KEYWORDS="~amd64"
VIDEO_CARDS="intel"
```

### package.use / package.accept_keywords / package.license

One entry per line: a package atom followed by space-separated values.

```
# package.use
app-editors/vim        -X
>=sys-libs/gdbm-1.26   berkdb

# package.accept_keywords
=sys-apps/portage-3.0  ~amd64
dev-util/pkgdev        **

# package.license
app-text/calibre       BSD
```

### package.mask / package.unmask

One package atom per line (simple `cat/pkg` or versioned like `>=cat/pkg-1.0`).

```
sys-apps/systemd
>=dev-lang/python-3.13
```

## Directory layout support

All `package.*` files support both single-file and directory layouts, matching
Portage's convention:

```
/etc/portage/package.use           ← single file
/etc/portage/package.use/          ← directory
/etc/portage/package.use/custom    ← files read in sorted order
/etc/portage/package.use/gaming
```

When the path is a directory, all non-hidden files in it are read in sorted
(lexicographic) order.

## Precedence

The configuration precedence chain for environment-like settings (USE,
ACCEPT_KEYWORDS, etc.) from highest to lowest:

1. **CLI environment variables** (`interface:getenv/2`)
2. **make.conf values** (`gentoo:env/2`)
3. **config.pl facts** (`config:gentoo_env/2`)
4. **Built-in defaults** (`preference:default_env/2`)

For package masks and USE overrides, the application order in
`preference:init` is:

1. Gentoo profile tree (profile `package.mask`, `package.use`, `use.mask`, `use.force`)
2. `/etc/portage` files via `gentoo:load`
3. Legacy `config:gentoo_package_mask/1` and `config:gentoo_package_use/2` facts

## Architecture

```
Source/Config/gentoo.pl
  ├── load/0              main entry point
  ├── load_make_conf/1    KEY="value" → gentoo:env/2
  ├── load_package_use/1  → preference:register_gentoo_package_use/2
  ├── load_package_mask/1 → preference:mask_profile_atom/1
  ├── load_package_unmask/1 → preference:unmask_profile_atom/1
  ├── load_package_accept_keywords/1 → gentoo:package_keyword/2
  └── load_package_license/1 → gentoo:package_license_entry/2

preference.pl
  └── getenv/2  now consults gentoo:env/2 (between CLI and config.pl)
  └── init/0    calls gentoo:load before applying profile/gentoo overrides
```

## Template files

Development templates are provided in `Source/Config/Gentoo/`:

```
Source/Config/Gentoo/
  ├── make.conf
  ├── package.use
  ├── package.mask
  ├── package.unmask
  ├── package.accept_keywords
  └── package.license
```

These contain commented examples matching the values currently hardcoded in
`config.pl`.  On a real Gentoo system, copy `/etc/portage/` files to this
directory (or point `portage_confdir` directly at `/etc/portage`).

## Reused infrastructure

The file parsers reuse existing portage-ng infrastructure:

| Parser | Source | Reused for |
|--------|--------|------------|
| `profile:make_defaults_kv/2` | `profile.pl` | `make.conf` key=value parsing |
| `profile:profile_strip_comment/2` | `profile.pl` | Comment stripping (via `gentoo:strip_comment_and_trim`) |
| `preference:register_gentoo_package_use/2` | `preference.pl` | `package.use` entry registration |
| `preference:mask_profile_atom/1` | `preference.pl` | `package.mask` atom masking (supports versioned atoms via `eapi:qualified_target`) |
| `preference:unmask_profile_atom/1` | `preference.pl` | `package.unmask` atom unmasking |
