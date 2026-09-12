# Command-Line Interface

portage-ng is meant to sit beside Portage, not replace it in name or habit.  Many
flags will feel immediately familiar: `--pretend`, `--verbose`, `--emptytree`,
and the usual resolution switches mirror what you already use with emerge-style
workflows.  On top of that, a proof-based resolver can expose tools that a
traditional dependency solver does not: `--explain` and `--llm` for plan
dialogue, `--diagnose` / `--log` for metacircular build-failure repair,
`--variants` for USE-sensitive alternatives, and `--search` that can
treat a phrase as a natural-language query when structured parsing does not
apply.

The CLI is organized around one idea: **every invocation either reasons about
packages or acts on them.**  Reasoning covers dry-runs, search, similarity,
estimates, upstream checks, Bugzilla lookup, and anything that inspects the
knowledge base without changing the system.  Acting covers merge, unmerge,
depclean, fetch-only, and sync-style maintenance.  Keeping that distinction in
mind makes it easier to choose flags and to script portage-ng safely (often
pairing `--pretend` with exploratory options before any real merge).


## Modes

portage-ng operates in one of six modes, selected with `--mode`:

| **Mode** | **Description** |
| :--- | :--- |
| `standalone` | Full local operation — the default and most common mode |
| `daemon` | Persistent daemon serving IPC clients via Unix socket |
| `ipc` | Thin IPC client forwarding requests to a running daemon |
| `client` | Remote RPC client connecting to a server over HTTPS |
| `worker` | Compute node for distributed proving (polls server for jobs) |
| `server` | HTTP + Pengines server with job/result queues |

### Standalone

The default mode.  Loads the full pipeline, knowledge base, LLM
modules, and domain logic into a single process.  All resolution,
planning, graph generation, and building happens locally.  Every CLI
action (`--pretend`, `--sync`, `--graph`, `--shell`, etc.) is
available.

### Daemon

Keeps the same in-memory footprint as standalone — full knowledge
base, resolver, orderer — but listens on a **Unix domain socket**
for incoming requests.  Use `--background` to fork the daemon into a
detached process.  The daemon avoids the startup cost of reloading
the knowledge base on every invocation, making repeated queries fast.

### IPC

A thin front-end that does **not** load the full resolver stack.
It connects to a running daemon over the Unix socket, forwards the
command-line arguments and environment, streams output back, and
exits with the daemon's exit code.  If `--background` auto-start is
configured and no daemon is listening, the IPC client can launch one
automatically.  Note that `--shell` is not supported in IPC mode.

### Client

A lightweight process that treats a remote **server** as the source
of truth for the knowledge base.  Local queries are proxied over
HTTPS using Pengine RPC (with TLS certificates and digest
authentication).  The client loads enough of the pipeline to drive
the CLI, but proving and KB access happen on the server side.  Use
`--host` and `--port` to specify the server.

### Server

Runs the full standalone pipeline first (local KB, resolver,
orderer), then adds an HTTPS Pengine server, TLS, and Bonjour
service advertisement.  The server exposes job and result message
queues so that workers can poll for proving tasks.  Use
`--background` to fork the server process.  See [Chapter 18:
Distributed Proving](18-doc-distributed.md).

### Worker

A compute node that loads the full proving pipeline locally (like
standalone) plus an RPC client for server communication.  On
startup, the worker discovers the server via Bonjour or explicit
`--host`/`--port`, syncs its local portage tree to the server's
snapshot, registers its CPU count, and spawns one thread per core.
Each thread polls the server for jobs, proves them locally, and
posts results back.  See [Chapter 18: Distributed
Proving](18-doc-distributed.md).


## Actions

Actions are grouped by area.  Use the tables below as a quick map from flags
to behaviour; the sections that follow add context on targets, search, and
everyday workflows.

### Merge and resolution

| **Flag** | **Action** |
| :--- | :--- |
| `--pretend` | Generate and display a build plan (dry-run) |
| `--merge` | Execute the build plan |
| `--unmerge <target>` | Remove a package |
| `--depclean` | Remove unneeded packages |
| `--fetchonly` / `-f` | Same `:run` proof as `--merge`; print and execute downloads (and unmask / keyword / USE / license pre-actions) only |
| `--fetch-all-uri` / `-F` | Same as `--fetchonly`, plus every `SRC_URI` regardless of USE |

`--fetchonly` is a **restriction on the merge plan**, not a second resolve.
The prover still proves `target:run` (same 5-tier fallback as `--merge`).
The `fetchonly` preference flag then:

- hides install / run / update / downgrade / reinstall from the printer
- lets the builder execute only the remaining download (and pre-action) steps
- skips `@world` registration, even on a real (non-pretend) run

`-F` uses that same filter and additionally asks `ebuild:distfile_scope/1`
for every file listed in `SRC_URI`. Combine with `--build` to actually
fetch; without `--build` the filtered plan is printed only (same split as
`--merge` vs `--build`).

### Information

| **Flag** | **Action** |
| :--- | :--- |
| `--search <query>` | Search packages (supports natural-language via embeddings) |
| `--similar <target>` | Find packages similar to target (vector similarity) |
| `--info` | System overview (version, hostname, repositories, world set) without arguments; per-package details with a target |
| `--pretend @installed` | List installed packages (via the computed `@installed` set) |

### Repository management

| **Flag** | **Action** |
| :--- | :--- |
| `--sync` | Sync the Portage tree and regenerate caches |
| `--regen` | Regenerate md5-cache incrementally |
| `--import-vdb` | Client mode: ship the local VDB to the server so remote plans reflect the client's installed packages (see [Chapter 18](18-doc-distributed.md)) |

### Visualization

| **Flag** | **Action** |
| :--- | :--- |
| `--graph` | Generate interactive SVG dependency graphs |
| `--estimate` | Show build time estimates |

### Diagnostics

| **Flag** | **Action** |
| :--- | :--- |
| `--bugs <target>` | Prove the target (resolve-only) and print Gentoo Bugzilla bug-report drafts for its domain assumptions |
| `--search-bugs <term>` | Search for known issues: local bug store first, then Gentoo Bugzilla (policy `config:bugzilla_search/1`, see [Chapter 19](19-doc-upstream-bugs.md#searching-search-bugs)) |
| `--upstream <target>` | Check upstream versions via Repology |
| `--explain` / `--llm` | Get AI-assisted plan explanation |
| `--diagnose` / `--log` | Metacircular LLM diagnose of a failed build |
| `--variants` | Show plan variants with different USE configurations |
| `--shell` | Drop into an interactive Prolog shell |


## Options

### Resolution options

| **Flag** | **Effect** |
| :--- | :--- |
| `--emptytree` | Prove all dependencies from scratch (ignore VDB) |
| `--onlydeps` | Prove only dependencies, not the target itself |
| `--deep` | Deep dependency resolution |
| `--newuse` | Detect USE flag changes requiring rebuilds |
| `--update` | Update to newest version |
| `--optimize parallelism` | Plan ordering strategy (default): a soft requirement (preference, e.g. RDEPEND-before-consumer) whose two ends lie on a common loop is void, so the loop's members merge side by side; preferences between loops are all kept. Shallower plans, order-independent |
| `--optimize soft-requirements` | Hand every preference to the planner, which honors as many as it can and drops only those that would close a loop; loop members merge one per step, resembling `emerge`'s linear listing |

Both `--optimize` strategies satisfy every hard requirement; they differ
only in what happens to soft requirements (preferences) that contradict
each other.  See [Chapter 13](13-doc-planning.md), "Preferences: soft
requirements", for a worked example with diagrams.

### Output options

| **Flag** | **Effect** |
| :--- | :--- |
| `--verbose` | Verbose output (show USE flags, slot info) |
| `--quiet` | Minimal output |
| `--ci` | Non-interactive CI mode (exit codes 0/1/2) |
| `--jobs N` | Number of parallel jobs |
| `--timeout N` | Abort proving/planning after N seconds (0 = no limit) |


## Target syntax

Targets can be specified in several formats:

| **Format** | **Example** | **Meaning** |
| :--- | :--- | :--- |
| `cat/pkg` | `sys-apps/portage` | Resolve latest version |
| `=cat/pkg-ver` | `=sys-apps/portage-3.0.77` | Exact version |
| `>=cat/pkg-ver` | `>=dev-lang/python-3.10` | Version constraint |
| `@set` | `@world`, `@security`, `@changed-deps` | Package set (file-backed, profile, or computed) |
| `pkg` | `portage` | Ambiguous name (searched across categories) |


## Package sets

`@name` targets expand to concrete atoms via `eapi:substitute_sets/2`
before proving. File-backed sets (`@world`, `@system`, user sets under
`config:set_dir/1`) come from preference configuration. **Computed sets**
are registered in `Source/Domain/Gentoo/Preference/sets.pl` and resolved
on demand by `sets:expand/2`.

```bash
portage-ng --mode standalone --list-sets
portage-ng --mode standalone --ci --pretend @security
portage-ng --mode standalone --ci --pretend @preserved-rebuild
portage-ng --mode standalone --ci --pretend @changed-deps
```

An empty computed set prints an informational line and exits 0 under
`--ci` (nothing to do), not a hard failure.

| **Set** | **Atoms** | **Meaning** |
| :--- | :--- | :--- |
| `@world` / `@system` | as configured | Preference / profile sets |
| `@installed` | `cat/name:slot` | Everything installed |
| `@live-rebuild` | `cat/name:slot` | Installed `PROPERTIES=live` packages |
| `@changed-subslot` | `cat/name:slot` | Subslot differs from highest visible ebuild |
| `@downgrade` | `cat/name:slot` | Highest visible ebuild is older than installed |
| `@unavailable` | `cat/name:slot` | No visible ebuild in the same slot |
| `@rebuilt-binaries` | `=cpv` | Binpkg BUILD_TIME ≠ installed BUILD_TIME |
| `@unavailable-binaries` | `cat/name:slot` | No binpkg for the installed version |
| `@security` | `=cpv` | GLSA NewAffectedSet (default security set) |
| `@affected` / `@new-affected` / `@new-glsa` | `=cpv` | Other Portage security-set filters |
| `@preserved-rebuild` | `cat/name:slot` | Consumers of FEATURES=preserve-libs leftovers |
| `@changed-deps` | `=cpv` | VDB RDEPEND/PDEPEND drifted from same-version ebuild |

**`@preserved-rebuild`** reads Portage’s `preserved_libs_registry` JSON
(default: derive from `config:pkg_directory/1` as
`…/lib/portage/preserved_libs_registry`; override with
`config:preserved_libs_registry_override/1`) and matches consumers via
VDB `NEEDED.ELF.2`. It is complementary to the automatic
`config:subslot_rebuild/1` pass, which rebuilds `:=` reverse deps when a
provider’s subslot changes inside a plan.

**`@changed-deps`** compares installed RDEPEND/PDEPEND (from the on-disk
VDB) to the same-version tree ebuild after use-reduce and `:=` stripping,
with libc injects removed (emerge `--changed-deps` semantics). The
`--changed-deps` flag applies the same test while resolving other
targets.

GLSA details for `@security` and siblings:
[Chapter 20](20-doc-glsa.md). Full option text:
[`portage-ng(1)`](../Manpage/portage-ng.1.md).


## CI mode

Use `--ci` for non-interactive automation.  Exit codes indicate plan
quality:

| **Code** | **Meaning** |
|:------|:---------|
| 0 | Plan completed with no assumptions |
| 1 | Plan completed with prover cycle-break assumptions only |
| 2 | Plan completed with domain assumptions (e.g. missing deps) |

Example:

```bash
portage-ng --ci --pretend sys-apps/portage
echo $?  # 0, 1, or 2
```

By default, portage-ng runs in standalone mode.  Other modes (distributed
client, server, worker) are covered in the advanced topics chapters.


## The dev wrapper

When running from a source checkout, use the dev wrapper instead of the
installed binary:

```bash
./Source/Application/Wrapper/portage-ng-dev --pretend sys-apps/portage
```

The wrapper sets up the correct load paths, stack limits, and Prolog flags.
It also supports `--timeout N` (requires Python 3) to kill the process after
N seconds.  For reproducible, non-interactive runs, pipe queries via a
here-doc:

```bash
./Source/Application/Wrapper/portage-ng-dev --shell --timeout 60 <<'PL'
resolver:test_stats(portage).
halt.
PL
```


## Tips and tricks

Short recipes that match how people actually use the tool:

- **What does portage-ng think about this package?**  
  `portage-ng --pretend --verbose cat/pkg` — full plan with enough detail to
  compare against emerge-style output.

- **Why is this package in my plan?**  
  `portage-ng --pretend --explain cat/pkg` — ask the explainer/LLM path to
  narrate the plan (see [Chapter 17: Semantic Search and LLM Integration](17-doc-llm.md)).

- **Diagnose a failed build with metacircular LLM repair**  
  `portage-ng --diagnose cat/pkg` (optional `--log path`) — propose
  `feedback:*` learning from the build log; confirm before apply
  (same chapter).

- **What would change if I enabled this USE flag?**  
  `portage-ng --pretend --variants cat/pkg` — surface alternative proofs when
  USE sets differ.

- **Find packages related to *X***  
  `portage-ng --search "X"` — natural-language / semantic search when the
  query is not structured (requires embeddings; same chapter as above).  For
  an exact package name, use a structured atom such as `name=vim` (the same
  intent as “`name:X`” in prose, but the CLI grammar uses `=` for equality, not
  a single `name:X` token).  Category and other fields work the same way
  (`category=…`); see [Search query language](#search-query-language) below.

- **Show me similar packages**  
  `portage-ng --similar cat/pkg` — vector similarity from the same embedding
  stack as semantic search.

- **Quick scripted session**  
  Here-doc into the Prolog shell so the full load graph matches interactive
  use:

  ```sh
  portage-ng --mode standalone --shell <<'PL'
  resolver:test_stats(portage).
  halt.
  PL
  ```

- **CI / automation**  
  `portage-ng --ci --pretend cat/pkg` — non-interactive; interpret exit codes:
  `0` no assumptions, `1` cycle-break assumptions only, `2` domain
  assumptions present.

- **Estimate build time**  
  `portage-ng --estimate cat/pkg` — build-time hints from VDB and history.

- **Check for upstream updates**  
  `portage-ng --upstream cat/pkg` — Repology-oriented upstream comparison.

- **Draft bug reports**  
  `portage-ng --bugs cat/pkg` — prove the target (resolve-only) and print
  Bugzilla-style bug-report drafts for its domain assumptions.

- **Search Bugzilla**  
  `portage-ng --search-bugs term` — look up known issues.  With a synced
  `bugzilla` repository the local bug store answers first (a `cat/name`
  term uses the package atom index); the live REST quicksearch is the
  fallback, or the only source with `config:bugzilla_search(rest)`.

- **Keep the local bug store fresh**  
  `portage-ng --sync bugzilla` — fetch changed bugs into
  `Knowledge/bugs.qlf`; `config:repository_sync_limit(bugzilla, 1)` caps
  the network step at one run per day.


## Search query language

The `--search` flag accepts **structured** queries built from one or more
command-line atoms.  Each atom is a *key*, a *comparator*, and a *value* (see
[Fuzzy and wildcard search](#fuzzy-and-wildcard-search) for the comparators).
When the argument list does **not** parse as that structured form, the text is
joined and passed to **semantic** (natural-language) search instead.

```bash
portage-ng --search name=vim category=app-editors
portage-ng --search license=GPL-2 keywords=amd64
portage-ng --search "text editor with syntax highlighting"  # semantic search
```

Semantic search requires Ollama with a loaded embedding model.  See
[Chapter 17: Semantic Search and LLM Integration](17-doc-llm.md).

### Fuzzy and wildcard search

Structured search uses explicit comparators on the key:

| **Comparator** | **Meaning** | **Example** |
| :--- | :--- | :--- |
| `=` | Exact match on the value | `name=vim` |
| `~` | Fuzzy match (approximate / substring-style, key-dependent) | `name~vim` |
| `:=` | Wildcard match (`*` in the value) | `name:=*vim*` |

**Exact search** — constrain the package name or another field precisely, e.g.
`--search name=vim` (exact package name).  In documentation you may see this
described informally as `name:vim`; on the command line the equality comparator
is `=` (`:` introduces the `:=` wildcard operator instead).

**Category filter** — `category=app-editors` (or combine with other atoms on
the same command line).

**Natural language** — a query that does not parse as structured keys, e.g.
`--search "text editor with syntax highlighting"`, uses vector embeddings over
the knowledge base (when enabled and indexed).

**Wildcard** — use `:=` so `*` is interpreted as a glob-style wildcard, e.g.
`name:=*vim*` for any package name containing `vim`.  Quote the atom if the
shell would expand `*` (e.g. `--search 'name:=*vim*'`).

**Combined filters** — pass several atoms; each narrows the result set, e.g.
`category=dev-libs name:=*ssl*`.


## Further reading

- [`portage-ng(1)` manpage](../Manpage/portage-ng.1.md) — exhaustive option
  reference
- [Chapter 2: Installation and Quick Start](02-doc-installation.md) — first run
  examples
- [Chapter 14: Output and Visualization](14-doc-output.md) — what the output
  looks like
- [Chapter 20: Gentoo Linux Security Advisories (GLSA)](20-doc-glsa.md) —
  `@security` and related GLSA computed sets
- [Chapter 3: Configuration](03-doc-configuration.md) —
  `config:preserved_libs_registry/1` and related paths
