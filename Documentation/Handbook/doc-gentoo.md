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
`fallback:env/2` and `fallback:package_*/1-2` defaults.

## Supported files

| File | Gentoo path | portage-ng mapping | Notes |
|------|-------------|-------------------|-------|
| `make.conf` | `/etc/portage/make.conf` | `userconfig:env/2` → feeds `preference:getenv/2` | USE, ACCEPT_KEYWORDS, ACCEPT_LICENSE, VIDEO_CARDS, INPUT_DEVICES, CPU_FLAGS_X86, PYTHON_TARGETS, etc. |
| `package.use` | `/etc/portage/package.use` | `preference:userconfig_use_versioned/3`, `preference:userconfig_use/4` | Per-package USE flag overrides |
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
2. **make.conf values** (`userconfig:env/2`)
3. **fallback defaults** (`fallback:env/2`)
4. **Built-in defaults** (`preference:default_env/2`)

For package masks and USE overrides, the application order in
`preference:init` is:

1. Gentoo profile tree (profile `package.mask`, `package.use`, `use.mask`, `use.force`)
2. `/etc/portage` files via `gentoo:load`
3. Fallback defaults `fallback:package_mask/1` and `fallback:package_use/2`

## Profile loading strategy

Profile data (USE flags, masks, per-package USE, license groups) can be
loaded from the Portage tree at startup (`live`) or from a pre-serialized
cache (`cached`).  The strategy is configurable per mode:

```prolog
config:profile_loading(standalone, live).    % parse profile tree on each startup
config:profile_loading(daemon,     cached).  % load from Knowledge/profile.qlf (fast)
config:profile_loading(worker,     cached).
config:profile_loading(client,     live).
config:profile_loading(server,     cached).
```

When strategy is `cached` but `Knowledge/profile.qlf` is missing, falls back to `live`
automatically.

### Generating the profile cache

Run `--sync` to generate `Knowledge/profile.qlf`:

```sh
./Source/Application/Wrapper/portage-ng-dev --mode standalone --sync
```

This calls `profile:cache_save` after syncing the KB, which walks the profile
tree once and serializes all profile-derived data to `Knowledge/profile.qlf`.

### What gets cached

| Data | Live source | Cached source |
|------|-------------|---------------|
| Profile USE terms | `profile:profile_use_terms` → `make.defaults` | `profiledata:use_term/1` |
| USE mask/force | `profile:profile_use_mask/force` → `use.mask`, `use.force` | `profiledata:use_mask/1`, `use_force/1` |
| Package masks | `profile:profile_package_mask_atoms` → `package.mask/unmask` | `profiledata:package_mask_atom/1` |
| Per-package USE | `preference:apply_profile_package_use` → `package.use` | `profiledata:package_use/3` |
| Per-package USE mask/force | `preference:apply_profile_package_use_mask/force` | `profiledata:package_use_mask/2`, `package_use_force/2` |
| License groups | `preference:load_license_groups` → `license_groups` | `profiledata:license_group/2` |

## Architecture

```
Source/Config/gentoo.pl           /etc/portage configuration reader
  ├── load/0                      main entry point
  ├── load_make_conf/1            KEY="value" → userconfig:env/2
  ├── load_package_use/1          → preference:register_fallback_package_use/2
  ├── load_package_mask/1         → preference:mask_profile_atom/1
  ├── load_package_unmask/1       → preference:unmask_profile_atom/1
  ├── load_package_accept_keywords/1 → gentoo:package_keyword/2
  └── load_package_license/1      → gentoo:package_license_entry/2

Source/Domain/Gentoo/profile.pl                  profile reading + cache serialization/deserialization
  ├── cache_save/0                serialize profile tree → Knowledge/profile.qlf
  ├── cache_load/3                deserialize USE terms/mask/force
  ├── apply_cached_package_masks/0
  ├── apply_cached_package_use/0
  ├── apply_cached_package_use_mask/0
  ├── apply_cached_package_use_force/0
  └── apply_cached_license_groups/0

preference.pl
  ├── use_cached_profile/0        checks mode + config + cache availability
  ├── getenv/2                    consults userconfig:env/2 then fallback:env/2
  └── init/0                     uses cached or live profile based on config
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
