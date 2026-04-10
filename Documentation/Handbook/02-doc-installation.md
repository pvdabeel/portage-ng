# Installation and Quick Start

## Prerequisites

### Required

The following tools must be present on every system that runs portage-ng.
SWI-Prolog is the runtime; the others are used during repository syncing,
metadata extraction, and distfile verification.

| **Dependency** | **Minimum version** | **Purpose** |
|:---|:---|:---|
| **SWI-Prolog** | 10.0.0 | Runtime interpreter.  Must be built with SSL, PCRE, editline, HTTP, crypto, and pengines support. |
| **bash** | 5 | Metadata extraction via `ebuild-depend.sh` and helper scripts. |
| **git** | any | Repository syncing (`--sync` with git protocol), version display. |
| **curl** | any | Mirror/distfile downloads, HTTP-based repository sync. |
| **openssl** CLI | any | Distfile hash verification (`openssl dgst`), TLS certificate generation for client–server encryption. |
| **Gentoo Portage tree** | — | A full Portage tree (ebuilds + md5-cache).  portage-ng reads the md5-cache for dependency resolution and requires the ebuilds for building. |

On most Gentoo systems these are already installed.  On non-Gentoo hosts
(e.g. macOS), SWI-Prolog and bash are the only items
you may need to install manually.

### Required for specific features

Some portage-ng features require additional tools.  These are only
needed for specific commands.

| **Dependency** | **Feature** | **Notes** |
|:---|:---|:---|
| **Graphviz** (>= 11) | `--graph` | The `dot` command generates interactive SVG dependency graphs. |
| **dns-sd** | Distributed mode | mDNS/Bonjour service discovery.  Built-in on macOS; use `avahi-browse` on Linux. |
| **ebuild** | `--merge` / `--build` | Actual package building delegates to Portage's ebuild infrastructure.  Not needed for `--pretend`. |
| **rsync** | `--sync` (rsync) | Only when using rsync-based repository sync. |
| **tar** | `--sync` (HTTP) | Only when using tarball-based repository sync. |

### Optional

The following are convenient but not required for core operation.

| **Dependency** | **Purpose** |
|:---|:---|
| **Python 3** | Timeout watchdog in the dev wrapper; comparison scripts in `Reports/Scripts/`. |
| **make** / **cmake** | Used by build helper scripts for packages that need them. |
| **aha** / **perl** | Pretty-print HTML output generation. |
| **pv** | Progress bars during batch graph generation. |
| **Ollama** | Local LLM inference and vector embeddings for `--search` / `--explain`. |

### Prolog build requirements

When compiling SWI-Prolog from source, ensure the following optional
components are enabled (they are usually built by default):

- **OpenSSL** — required for `library(crypto)`, `library(ssl)`,
  `library(http/http_ssl_plugin)`
- **PCRE** — required for `library(pcre)` (used in EAPI parsing)
- **GNU Readline / Editline** — required for `library(editline)`
  (interactive shell)
- **libgmp** — required for arbitrary-precision arithmetic
- **zlib** — required for qcompiled file support (`Knowledge/kb.qlf`)


## Building

From the project root:

```bash
make check    # verify SWI-Prolog is installed
make build    # create the portage-ng binary
make install  # install to /usr/local/bin (requires sudo)
```

The `build` target uses `swipl --stand_alone=true` to produce a
self-contained binary.


## First run

### Pretend (dry-run)

Generate a build plan without executing it:

```bash
portage-ng --pretend app-editors/neovim
```

portage-ng proves a dependency graph, plans it into parallel steps, and
presents the result:

```
>>> Emerging : portage://app-editors/neovim-0.12.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─ step 1 ─┤ download portage://dev-python/tree-sitter-0.25.2
            │           └─ file ─┤ 170.27 Kb  tree-sitter-0.25.2.gh.tar.gz
            │ download portage://dev-lua/mpack-1.0.13
            │           └─ file ─┤ 16.17 Kb   mpack-1.0.13.tar.gz

 └─ step 2 ─┤ install  portage://dev-lang/lua-5.1.5-r200
            │           └─ conf ─┤ USE = "readline deprecated"
            │                    │ SLOT = "5.1"
            │ install  portage://dev-libs/msgpack-6.0.0-r1
            │           └─ conf ─┤ USE = "-doc -examples -test"
            │                    │ SLOT = "0/2-c"
            ...

 └─ step 7 ─┤ install  portage://app-editors/neovim-0.12.0
            │           └─ conf ─┤ USE = "nvimpager -test"
            │                    │ LUA_SINGLE_TARGET = "luajit -lua5-1"

 └─ step 8 ─┤ run      portage://app-editors/neovim-0.12.0

Total: 59 actions (20 downloads, 19 installs, 1 update, 19 runs),
       grouped into 8 steps.
       18.82 Mb to be downloaded.
```

Actions within the same step can execute in parallel.  The plan
distinguishes download, install, update, and run phases.  Each package
shows its resolved configuration (Use flags, slot, target selection).

If portage-ng had to make assumptions during proving, they are reported
at the end with suggested fixes and draft bug reports.


### Interactive shell

Drop into a Prolog shell with the full knowledge base loaded:

```bash
portage-ng --shell
```

The shell provides direct access to the knowledge base.  The built-in
`query:search/2` predicate offers a readable way to explore it.

**Search for packages by name:**

```
?- query:search([name(neovim), description(D)], Repository://Entry).
D = "Vim-fork focused on extensibility and agility",
Repository = portage,
Entry = 'app-editors/neovim-9999'.
```

Press `;` to see the next result, or `.` to stop.  Prolog backtracks
through all matching ebuilds automatically.

**Look up slot and keywords:**

```
?- query:search([name(neovim), slot(S), keywords(K)], Repository://Entry).
S = '0',
K = unstable(amd64),
Repository = portage,
Entry = 'app-editors/neovim-0.12.0'.
```

**Search across repositories:**

```
?- query:search([name(firefox), description(D)], Repository://Entry).
D = "Firefox Web Browser",
Repository = portage,
Entry = 'www-client/firefox-149.0'.
```

**Count all ebuilds:**

```
?- aggregate_all(count, portage:entry(_), Total).
Total = 31535.
```

**Read a single metadata field:**

```
?- cache:entry_metadata(portage, 'app-editors/neovim-0.12.0', description, D).
D = "Vim-fork focused on extensibility and agility".
```

The full cache schema and query language are documented in
[Chapter 6: Knowledge Base](06-doc-knowledgebase.md).


### Sync the Portage tree

Sync the repository and regenerate the knowledge base cache:

```bash
portage-ng --sync
```

The sync performs three phases for each registered repository:

1. **Repository sync** — pulls the latest Portage tree (via git, rsync, or
   HTTP tarball depending on configuration).
2. **Metadata sync** — reads the md5-cache files and, if configured,
   regenerates cache entries for ebuilds that have changed.
3. **Knowledge base sync** — parses all cache entries into Prolog facts
   (the `cache:entry`, `cache:entry_metadata`, `cache:manifest`, etc.
   predicates) and saves the compiled knowledge base to disk.

```
>>> Syncing 1 registered repository

--- Syncing repository "portage" ---

 Syncing repository ... ok
 Syncing metadata   ... Ebuild: sys-apps/portage-2.3.99-r1
                        Ebuild: dev-lang/python-3.13.3
                        Ebuild: sys-libs/glibc-2.41
                        ...
                        Updated metadata.
 Syncing kb         ... Ebuild: acct-group/abrt-0
                        Ebuild: acct-group/adm-0
                        Ebuild: acct-group/audio-0
                        ...
                        Manifest: app-accessibility/at-spi2-core
                        Manifest: app-accessibility/brltty
                        ...
                        Updated prolog knowledgebase.

--- Syncing profile ---

 Saving knowledge base ... ok
```

During the knowledge base sync, every ebuild's metadata — dependencies,
Use flags, keywords, slots, descriptions, manifests — is parsed and
asserted as Prolog facts.  The entire Gentoo repository (over 30,000
ebuilds) is held in memory as a native Prolog database, enabling
lightning-fast lookups without any disk I/O during reasoning.

SWI-Prolog's just-in-time (JIT) indexing further accelerates these
lookups.  When a predicate like `cache:entry_metadata(portage,
'app-editors/neovim-0.12.0', description, D)` is first called,
the runtime automatically builds hash indices on the arguments that
are bound.  Subsequent calls with the same argument pattern jump
straight to matching clauses instead of scanning all 30,000+ entries
linearly.  This indexing is created on demand and updated
transparently as facts are asserted or retracted — no manual index
declarations are needed.

Once syncing completes, the knowledge base is saved to disk using
SWI-Prolog's qcompile mechanism (`Knowledge/kb.qlf`).  qcompile
serializes Prolog clauses into a compact binary format that can be
loaded back in a fraction of the time it takes to parse the original
source.  On subsequent runs, portage-ng loads the `.qlf` file directly,
making startup near-instantaneous — even for a repository with tens of
thousands of ebuilds.


## Running tests

```bash
make test            # PLUnit tests
make test-overlay    # Overlay regression tests (80 scenarios)
```

See [Chapter 23: Testing and Regression](23-doc-testing.md) for details.


## Further reading

- [Chapter 3: Configuration](03-doc-gentoo.md) — setting up Portage tree
  paths, `/etc/portage`, and profiles
- [Chapter 14: Command-Line Interface](14-doc-cli.md) — full CLI reference
- [`portage-ng(1)` manpage](../Manpage/portage-ng.1.md) — exhaustive option
  reference
