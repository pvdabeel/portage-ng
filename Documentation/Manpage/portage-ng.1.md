# PORTAGE-NG(1)

## NAME

portage-ng - a Prolog-based package dependency resolver and build system for Gentoo

## SYNOPSIS

**portage-ng** [**--mode** *MODE*] [*OPTIONS*] [*TARGETS* ...]

**portage-ng** **--mode standalone --shell**

**portage-ng** **--sync** [*REPOSITORY* ...]

## DESCRIPTION

**portage-ng** is a dependency resolver, planner, and build orchestrator for
Gentoo Linux package trees. It reads Gentoo ebuild metadata (md5-cache),
resolves dependency graphs using inductive proof search, generates ordered
build plans, and optionally executes them by invoking the standard **ebuild**(1)
command.

The resolver supports the full PMS (Package Manager Specification) dependency
language, including USE-conditional dependencies, slot operators, blockers,
sub-slots, and PDEPEND (post-merge dependencies).

**portage-ng** can operate in several modes: standalone (default, all
in-process), client-server (distributed proving via Pengines), or as a daemon
serving IPC clients.

## MODES

| Mode | Description |
|------|-------------|
| **standalone** | Default. All operations run in a single process. The knowledge base is loaded from a QLC-compiled cache on disk. |
| **daemon** | Persistent background process serving local IPC clients via a Unix domain socket. |
| **ipc** | Thin IPC client that connects to a running daemon. |
| **server** | HTTP/Pengine server for distributed proving across a network. |
| **client** | TCP/IP client connecting to a remote server. |
| **worker** | Compute node for distributed proving; polls the server for jobs. |

## ACTIONS

Actions control what **portage-ng** does with the given targets. Exactly one
action is performed per invocation.

### Dependency resolution (default)

| Flag | Description |
|------|-------------|
| **-m**, **--merge** | Resolve the full dependency closure and print the resulting plan. This is the default action when no other action flag is given. Equivalent to Portage's `emerge --pretend`. |
| **-u**, **--update** | Update the given targets. Resolves the full runtime closure and performs a transactional replace if needed. |
| **--upgrade** | Two-phase upgrade: first compute a fresh plan under `--emptytree` semantics, then run `--depclean` on the real installed graph. Defaults to `@world` when no targets are given. |

### Building

| Flag | Description |
|------|-------------|
| **--build** | Build target: resolve the plan, then execute it with live progress display. Downloads distfiles, runs ebuild phases, and shows per-phase status inline. The plan is saved to `Knowledge/resume.pl` so that an interrupted build can be continued with `--resume`. |
| **-r**, **--resume** | Resume a previously interrupted `--build` run. Loads the saved plan from `Knowledge/resume.pl` and re-executes only the packages that did not complete successfully. The `clean` phase is skipped so that ebuild can pick up from the preserved work directory. |
| **--skip** *PACKAGE* | Used with `--resume`. Skip the named package instead of re-executing it. The flag is repeatable. Additionally, when `--resume` is active, positional arguments are interpreted as packages to skip. |
| **-f**, **--fetchonly** | Only download source archives (distfiles) without building. |
| **-F**, **--fetch-all-uri** | Like `--fetchonly` but download all files listed in `SRC_URI` regardless of the current USE flag configuration. |

### Package management

| Flag | Description |
|------|-------------|
| **-C**, **--unmerge** | Unmerge (remove) the specified packages. |
| **-c**, **--depclean** | Remove packages that are not part of the dependency closure of the world set or of the given targets. |
| **--deselect** | Remove the given targets from the world set without unmerging them. |

### Information

| Flag | Description |
|------|-------------|
| **-i**, **--info** | Without arguments, show system information: portage-ng version, profile, registered repositories, and world set contents. With targets, show detailed package metadata. |
| **-s**, **--search** | Search the knowledge base for matching packages using `key=value` queries (see [SEARCH SYNTAX](#search-syntax) below), or natural-language queries via semantic search (requires Ollama). |
| **--bugs** | Print Gentoo Bugzilla bug report drafts for unresolvable dependencies (domain assumptions) of the given targets. |
| **--search-bugs** | Search Gentoo Bugzilla for bugs matching the given term. |
| **-V**, **--version** | Print version information for portage-ng and all registered repositories. |

### Repository management

| Flag | Description |
|------|-------------|
| **--sync** | Synchronise the portage tree, regenerate the md5-cache, load the knowledge base, and (in standalone mode) save it to disk. Optional positional arguments restrict the sync to specific repository names. |
| **--regen** [*REPOSITORY*...] | Regenerate the ebuild metadata cache (md5-cache) on disk without performing a network sync (no git pull). Equivalent to running **egencache**. |
| **--metadata** | Alias for `--regen`. |
| **--list-sets** | List all available package sets (@world, user-defined sets). |
| **--check-news** | Check for and display GLEP 42 news items from the portage repository's `metadata/news/` directory. |
| **--graph** | Generate dependency graph output. Accepts sub-commands: `modified`, `full`, `build modified`, `build full`. |
| **--clear** | Clear the in-memory knowledge base. |
| **--save** | Save the knowledge base to disk (client mode). |
| **--load** | Load the knowledge base from disk (client mode). |
| **--shell** | Start an interactive Prolog shell with the full portage-ng environment loaded. |

### VDB queries

| Flag | Description |
|------|-------------|
| **--contents** | List the files installed by one or more packages. Equivalent to Paludis `cave contents`. |
| **--owner** | Find which installed package owns a given file. Accepts full paths or basenames. Equivalent to Paludis `cave owner`. |
| **--size** | Show the total disk space consumed by an installed package's files. Equivalent to Paludis `cave size`. |
| **--verify** | Verify that an installed package's files have not been modified since installation. Equivalent to Paludis `cave verify`. |
| **--executables** | List executables (binaries in PATH directories) provided by an installed package. Equivalent to Paludis `cave executables`. |

### Maintenance

| Flag | Description |
|------|-------------|
| **--fix-linkage** | Scan installed packages for broken shared library linkage. Equivalent to Paludis `cave fix-linkage`. |
| **--report** | Display a summary of potential problems with installed packages. Equivalent to Paludis `cave report`. |
| **--rdeps** | Show reverse dependencies. Equivalent to Paludis `cave print-dependent-ids`. |
| **--unused-distfiles** | List distfiles not referenced by any installed package. Equivalent to Paludis `cave print-unused-distfiles`. |
| **--import** | Track manually installed software as a package in the VDB. Equivalent to Paludis `cave import`. |
| **--unmanaged-files** [*DIR* ...] | Find files on the filesystem not owned by any installed package. Default directory: `/usr`. Equivalent to Paludis `cave print-unmanaged-files`. |

## OPTIONS

### Dependency resolution options

| Flag | Description |
|------|-------------|
| **-a**, **--ask** | Ask for confirmation before proceeding with the merge. |
| **-p**, **--pretend** | Pretend mode. Show what would be done without making changes. |
| **-d**, **--deep** | Also consider (rebuild) dependencies, not just the direct targets. |
| **-e**, **--emptytree** | Pretend no other packages are installed when resolving dependencies. |
| **-N**, **--newuse** | Include packages whose USE flags or declared IUSE set have changed since installation. |
| **-U**, **--changed-use** | Include packages whose effective USE flags have changed since installation. More conservative than `--newuse`. |
| **--changed-deps** | Rebuild packages whose runtime dependencies have changed since they were installed. |
| **--changed-slot** | Rebuild packages whose SLOT value has changed since installation. |
| **--selective** | Do not reinstall packages that are already installed and satisfy all dependency constraints. Implied by `--update` and `--newuse`. |
| **-n**, **--noreplace** | Skip packages that are already installed. Equivalent to `--selective`. |
| **-O**, **--nodeps** | Merge the target without resolving any of its dependencies. |
| **-o**, **--onlydeps** | Only merge the dependencies of the given targets, not the targets themselves. |
| **--with-bdeps** *y*\|*n* | Include or exclude build-time dependencies (BDEPEND). Default: `y`. |
| **--with-test-deps** *y*\|*n* | Include or exclude test dependencies. Default: `n`. |
| **--dynamic-deps** *y*\|*n* | Use dependency information from the repository ebuild rather than from the installed VDB. Default: `y`. |
| **--rebuild-if-new-rev** | Rebuild installed packages when a newer revision is available. |
| **--rebuild-if-new-ver** | Rebuild installed packages when any newer version is available. |
| **--rebuild-if-new-slot** | Rebuild packages when slot-operator dependencies have changed. |
| **--rebuild-if-unbuilt** | Rebuild dependencies of packages that have been rebuilt from source. |
| **--update-if-installed** | Like `--update` but only consider packages that are already installed. |
| **--exclude** *ATOM* | Exclude the given atom from the merge operation. Repeatable. |
| **-1**, **--oneshot** | Do not add the target packages to the world set. |
| **--select** | Add target packages to the world set after merging (default). Use `--select=n` as alternative to `--oneshot`. |

### Binary package options

| Flag | Description |
|------|-------------|
| **-k**, **--usepkg** | Use binary packages from `PKGDIR` when available. Falls back to building from source. |
| **-K**, **--usepkg-only** | Use only binary packages. Fails if no binary package is available. |
| **-g**, **--getbinpkg** | Download binary packages from a remote `BINHOST`. |
| **-G**, **--getbinpkg-only** | Use only remote binary packages from `BINHOST`. |
| **--usepkg-exclude** *ATOM* | Exclude the given atom from binary package usage. Repeatable. |
| **--usepkg-include** *ATOM* | Force binary package usage for the given atom. Repeatable. |
| **--usepkg-exclude-live** | Do not use binary packages for live ebuilds (version 9999). |
| **--binpkg-changed-deps** | Ignore binary packages whose dependency tree has changed. |
| **--binpkg-respect-use** | Ignore binary packages whose USE flags do not match current settings. |
| **--rebuilt-binaries** | Replace installed packages with more recently rebuilt binary packages. |

### Build options

| Flag | Description |
|------|-------------|
| **-j**, **--jobs** *N* | Limit the number of parallel build jobs. 0 (default) = auto-detect. |
| **--load-average** *N* | Do not start new jobs while load average exceeds *N*. 0 = disabled. |
| **-b**, **--buildpkg** | Create binary packages after building from source. |
| **-B**, **--buildpkgonly** | Like `--buildpkg` but do not merge to the live filesystem. |
| **--fail-clean** | Clean the build directory when a package build fails. |
| **-l**, **--logs** | Show build log file paths in `--build` output. |
| **--timeout** *SECONDS* | Abort proving and planning after *SECONDS* seconds. 0 = no limit. |
| **--variants** *MODE* | Show alternative build plans with `--pretend`. Modes: `none` (default), `auto`, `all`, or *flag1,flag2,...* |

### Plan explanation (requires LLM)

| Flag | Description |
|------|-------------|
| **--explain** [*QUESTION*] | Ask questions about the build plan using a configured LLM service. Must be combined with `--pretend`. Without a question, enters interactive mode. |
| **--llm** [*SERVICE*] | Start an interactive chat session with a large language model. Services: `claude`, `grok`, `chatgpt`, `gemini`, `ollama`. |
| **--train-model** | Build the semantic search embedding index from the current knowledge base. Requires a locally running Ollama instance with the `nomic-embed-text` model. GPU-accelerated on Apple Silicon via Metal. |
| **--similar** | Find semantically similar packages to the given target(s). Uses the pre-built embedding index; does not require Ollama at query time. |
| **--estimate** | Show estimated build time for the given packages, using VDB installed sizes and historical emerge.log data when available. |

### Upstream version checking

| Flag | Description |
|------|-------------|
| **--upstream** | Check whether newer versions are available upstream via the Repology API. |

### Snapshot and rollback

| Flag | Description |
|------|-------------|
| **--snapshot** [*ID*] | Record a snapshot before the merge operation begins. Captures VDB state, world set, and creates binary packages of packages about to be replaced. |
| **--rollback** *ID* | Roll back to a previously created snapshot. With `--pretend`, shows a diff without making changes. |
| **--snapshots** | List all available snapshots. |

### Resolver hints

| Flag | Description |
|------|-------------|
| **--favour** *ATOM* | Favour the specified package when resolving `\|\|` (any-of) dependencies. Repeatable. Equivalent to Paludis `cave resolve --favour`. |
| **--avoid** *ATOM* | Avoid the specified package when resolving `\|\|` (any-of) dependencies. Repeatable. Equivalent to Paludis `cave resolve --avoid`. |
| **--permit-downgrade** | Allow the resolver to select older package versions. Equivalent to Paludis `cave resolve --permit-downgrade`. |
| **--preset** *SPEC* | Pin a specific version during resolution. Repeatable. Equivalent to Paludis `cave resolve --preset`. |
| **--hide** *SPEC* | Pretend that matching packages do not exist during resolution. Repeatable. Equivalent to Paludis `cave resolve --hide`. |
| **--early** *SPEC* | Schedule matching packages earlier in the build plan. Repeatable. Equivalent to Paludis `cave resolve --early`. |
| **--late** *SPEC* | Schedule matching packages later in the build plan. Repeatable. Equivalent to Paludis `cave resolve --late`. |
| **--show-descriptions** *MODE* | Show USE flag descriptions. Modes: `none` (default), `new`, `all`. Equivalent to Paludis `cave resolve --show-option-descriptions`. |
| **--continue-on-failure** *MODE* | Control whether the builder continues after a failure. Modes: `never` (default), `if-satisfied`, `if-independent`, `always`. Equivalent to Paludis `cave resolve --continue-on-failure`. |

### Convenience presets

| Flag | Description |
|------|-------------|
| **--lazy** | Minimal work. Shorthand for `--noreplace --nodeps`. |
| **--complete** | Full update. Shorthand for `--deep --newuse --with-bdeps y`. |
| **--everything** | Reinstall everything. Shorthand for `--emptytree --deep`. |

### Output options

| Flag | Description |
|------|-------------|
| **-A**, **--alert** | Ring the terminal bell when an operation completes or when user attention is required. |
| **-v**, **--verbose** | Enable verbose output with additional diagnostic information. |
| **-q**, **--quiet** | Reduced output. |
| **--color** *y*\|*n* | Enable or disable colored output. Default: `y`. |
| **--style** *STYLE* | Set the printing style. One of: `fancy` (default), `column`, or `short`. |
| **--read-news** | When used with `--ask`, display news items before the confirmation prompt. |
| **--ci** | CI mode: non-interactive, exit with a nonzero exit code when the plan contains assumptions. |
| **--profile** | Enable instrumentation (sampler, debug hooks). |

### Network options (client/server modes)

| Flag | Description |
|------|-------------|
| **--host** *HOSTNAME* | Set the server hostname (client mode). |
| **--port** *PORT* | Set the server port (client or server mode). Default: 4000. |

### Lifecycle options (daemon/server modes)

| Flag | Description |
|------|-------------|
| **--background** | Fork to background (daemon and server modes). |
| **--status** | Check if the daemon or server is running (ipc and client modes). |
| **--cmd** *COMMAND* | Send a command to the daemon or server. Commands: `halt`, `relaunch`. |

### Build prefix

| Flag | Description |
|------|-------------|
| **--prefix** *DIR* | Set the installation prefix directory. Default: `/`. |

## TARGETS

Targets identify which packages to operate on. Several formats are supported:

| Format | Example | Description |
|--------|---------|-------------|
| *name* | `vim` | Unqualified package name. Resolves to the best visible version. |
| *category/name* | `app-editors/vim` | Category-qualified name. |
| *category/name-version* | `app-editors/vim-9.1.0` | Exact version. |
| *@set* | `@world` | A package set. Built-in sets include `@world` and `@system`. |

## SEARCH SYNTAX

The `--search` flag accepts two kinds of queries:

1. **Structured queries** -- one or more `key=value` arguments combined
   conjunctively (AND). Each argument has the form `key comparator value`.

2. **Semantic queries** -- free-form natural-language text (e.g. *text editor
   with syntax highlighting*). When the query does not parse as a structured
   expression, portage-ng falls back to semantic search: the query is embedded
   using a locally running Ollama model and matched against a pre-built vector
   index of all package descriptions. The index is built with `--train-model`
   (requires Ollama with `nomic-embed-text`). On Apple Silicon machines,
   embedding generation is GPU-accelerated via Metal.

### Search keys

| Key | Description |
|-----|-------------|
| **name** | Package name (e.g. `gcc`, `vim`) |
| **category** | Package category (e.g. `sys-devel`, `app-editors`) |
| **repository** | Repository name (e.g. `portage`, `guru`) |
| **version** | Package version |
| **eapi** | EAPI version number |
| **slot** | Package slot |
| **subslot** | Package sub-slot |
| **eclass** | Inherited eclass name |
| **eclasses** | Inherited eclasses (alternative form) |
| **keywords** | Architecture keyword (e.g. `amd64`, `~amd64`) |
| **iuse** | USE flag, searched with prefix stripped |
| **download** | Source download filename |
| **maintainer** | Package maintainer email address (e.g. `dev@gentoo.org`). Matches any maintainer in the package's metadata. |
| **masked** | Boolean: `masked=true` or `masked=false` |

### Comparators

| Operator | Description |
|----------|-------------|
| `=` | Exact match |
| `!=` | Not equal |
| `<` | Smaller than (version/eapi) |
| `>` | Greater than (version/eapi) |
| `<=` | Smaller than or equal |
| `>=` | Greater than or equal |
| `~` | Fuzzy match (approximate spelling) |
| `:=` | Wildcard match using `*` and `?` glob patterns |

### Search examples

```bash
# Find all versions of packages named gcc
portage-ng -s name=gcc

# Find gcc in the sys-devel category
portage-ng -s category=sys-devel name=gcc

# Find packages with "python" anywhere in the name
portage-ng -s name:=*python*

# Fuzzy match — finds gcc despite the typo
portage-ng -s name~gkc

# Find all packages that declare the wayland USE flag
portage-ng -s iuse=wayland

# Find packages with the amd64 keyword on EAPI 8 or later
portage-ng -s keywords=amd64 eapi>=8

# List masked packages in dev-lang
portage-ng -s masked=true category=dev-lang

# Find python packages in slot 0
portage-ng -s slot=0 name=python
```

## EBUILD PHASES

When `--build` is active, **portage-ng** executes the following ebuild phases
via the **ebuild**(1) command:

```
clean → setup → unpack → prepare → configure → compile → test → install → merge
```

When `--buildpkg` is also active, the `package` phase is inserted between
`install` and `merge`:

```
clean → ... → install → package → merge
```

The `merge` phase is a composite operation that internally runs `pkg_preinst`,
merges files to the live filesystem, unmerges the old version (for updates and
downgrades), and runs `pkg_postinst`.

When `--resume` is active, the `clean` phase is omitted so that the work
directory from the previous attempt is preserved.

## DOWNLOADING

**portage-ng** downloads source archives (distfiles) from a local HTTP mirror
using the GLEP 75 layout. When the mirror download fails, it falls back to the
upstream SRC_URI.

`mirror://` URIs in SRC_URI are resolved through the portage tree's
`profiles/thirdpartymirrors` file.

For live ebuilds (version 9999, inheriting `git-r3`), **portage-ng** clones or
fetches the upstream git repository into a local bare cache under
`distdir/git3-src/`, with real-time progress display.

Fetch-restricted ebuilds (`RESTRICT=fetch`) are detected and reported as
requiring manual download.

## CONFIGURATION

### Machine-specific configuration

`Source/Config/<hostname>.pl` — Per-machine configuration: portage tree
location, md5-cache path, VDB path, and repository registration.

### Portage configuration

`Source/Config/gentoo.pl` — Reads standard Gentoo `/etc/portage` files:
`make.conf`, `package.use`, `package.mask`, etc.

### Build configuration

| Directive | Description |
|-----------|-------------|
| `config:build_live_phases/1` | Controls which ebuild phases are actually executed during `--build`. |
| `config:mirror_url/1` | HTTP base URL of the local distfiles mirror. |
| `config:build_log_dir/1` | Directory for build log files. |

## EXIT STATUS

| Code | Meaning |
|------|---------|
| **0** | Success. The plan was resolved with no assumptions. |
| **1** | The plan was resolved but contains prover cycle-break assumptions only. |
| **2** | The plan contains domain assumptions (e.g. missing or non-existent packages). |

## EXAMPLES

```bash
# Resolve dependencies for vim in pretend mode
portage-ng --mode standalone --pretend vim

# Build irssi with live progress (oneshot, do not add to world)
portage-ng --mode standalone --build --oneshot irssi

# Build gcc and create a binary package
portage-ng --mode standalone --build --buildpkg gcc

# Resume a previously interrupted build
portage-ng --mode standalone --resume

# Resume, skipping two packages
portage-ng --mode standalone --resume --skip dev-lang/python-3.12.0 --skip sys-apps/portage-2.3.99

# Same, using positional arguments
portage-ng --mode standalone --resume dev-lang/python-3.12.0 sys-apps/portage-2.3.99

# Fetch sources only, without building
portage-ng --mode standalone --fetchonly firefox

# Synchronise the portage tree
portage-ng --mode standalone --sync

# Start an interactive Prolog shell
portage-ng --mode standalone --shell

# CI run with 60-second timeout
portage-ng --mode standalone --ci --pretend --timeout 60 kde-apps-meta

# Show variant plans with auto-detected pivot points
portage-ng --pretend --variants auto dev-libs/gtk+

# Explore how toggling wayland and X affects a plan
portage-ng --pretend --variants wayland,X dev-libs/gtk+

# Ask why a package is in the plan
portage-ng --pretend --explain "Why is dev-libs/openssl in the plan?" vim

# Interactive plan explanation
portage-ng --pretend --explain @world

# Merge vim with a snapshot (auto-generated ID)
portage-ng --snapshot vim

# Merge with a named snapshot
portage-ng --snapshot before-kde-update --update @world

# List available snapshots
portage-ng --snapshots

# Preview what a rollback would change
portage-ng --pretend --rollback 20260309-143022

# Execute a rollback
portage-ng --rollback 20260309-143022

# Start a chat session with the default LLM
portage-ng --llm

# Chat with a specific LLM service
portage-ng --llm grok

# Check upstream versions for specific packages
portage-ng --upstream sys-apps/portage dev-lang/python

# Check upstream versions for the world set
portage-ng --upstream @world

# Build the semantic search index (requires Ollama)
portage-ng --train-model

# Semantic search: find packages by description
portage-ng --search text editor with syntax highlighting

# Find packages similar to vim
portage-ng --similar app-editors/vim

# Estimate build time for packages
portage-ng --estimate dev-qt/qtcore sys-devel/gcc

# Search Bugzilla for bugs matching a term
portage-ng --search-bugs "openssl segfault"

# Upgrade the world set
portage-ng --mode standalone --upgrade
```

## FILES

| Path | Description |
|------|-------------|
| `portage-ng.pl` | Main entry point and module load graph. |
| `Source/Application/Wrapper/portage-ng-dev` | Development launcher script with timeout and instrumentation support. |
| `Knowledge/kb.qlf` | QLC-compiled knowledge base cache (generated by `--sync`). |
| `Knowledge/profile.qlf` | Cached profile data (generated by `--sync`). |
| `Knowledge/embeddings.pl` | Semantic search vector index (generated by `--train-model`). |
| `Source/Config/` | Machine-specific and Gentoo configuration files. |
| `Source/Config/Gentoo/` | Template files mirroring the `/etc/portage` layout. |

## ARCHITECTURE

**portage-ng** follows a pipeline architecture:

| Stage | Source |
|-------|--------|
| **Reader/Parser** | Reads ebuild md5-cache files using a PMS-conformant DCG grammar (`Source/Domain/Gentoo/eapi.pl`) and builds Prolog cache facts. |
| **Prover** | Performs inductive proof search over the dependency rules to produce a proof tree, model, constraint set, and trigger map (`Source/Pipeline/prover.pl`). |
| **Planner** | Generates a topologically sorted, wave-based build plan from the proof (`Source/Pipeline/planner.pl`). |
| **Scheduler** | Post-processes cyclic remainder: SCC decomposition (Kosaraju) and merge-set computation (`Source/Pipeline/scheduler.pl`). |
| **Printer** | Renders the plan with assumptions and warnings (`Source/Pipeline/Printer/`). |
| **Builder** | Orchestrates downloads and ebuild phase execution with a job server (`Source/Pipeline/builder.pl`). |

## SEE ALSO

**emerge**(1), **ebuild**(1), **ebuild**(5), **make.conf**(5), **portage**(5)

## AUTHORS

Pieter Van den Abeele <pvdabeel@mac.com>

## COPYRIGHT

Copyright (c) 2005-2026 Pieter Van den Abeele.
Distributed under the terms of the LICENSE file in the project root.
