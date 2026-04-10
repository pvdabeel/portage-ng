# Command-Line Interface

portage-ng is meant to sit beside Portage, not replace it in name or habit.  Many
flags will feel immediately familiar: `--pretend`, `--verbose`, `--emptytree`,
and the usual resolution switches mirror what you already use with emerge-style
workflows.  On top of that, a proof-based resolver can expose tools that a
traditional dependency solver does not: `--explain` and `--llm` for plan
dialogue, `--variants` for USE-sensitive alternatives, and `--search` that can
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
base, resolver, planner — but listens on a **Unix domain socket**
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
planner), then adds an HTTPS Pengine server, TLS, and Bonjour
service advertisement.  The server exposes job and result message
queues so that workers can poll for proving tasks.  Use
`--background` to fork the server process.  See [Chapter 17:
Distributed Proving](17-doc-distributed.md).

### Worker

A compute node that loads the full proving pipeline locally (like
standalone) plus an RPC client for server communication.  On
startup, the worker discovers the server via Bonjour or explicit
`--host`/`--port`, syncs its local portage tree to the server's
snapshot, registers its CPU count, and spawns one thread per core.
Each thread polls the server for jobs, proves them locally, and
posts results back.  See [Chapter 17: Distributed
Proving](17-doc-distributed.md).


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
| `--fetchonly` | Fetch source archives only |

### Information

| **Flag** | **Action** |
| :--- | :--- |
| `--search <query>` | Search packages (supports natural-language via embeddings) |
| `--similar <target>` | Find packages similar to target (vector similarity) |
| `--info` | Display repository statistics and configuration |
| `--installed` | List installed packages |

### Repository management

| **Flag** | **Action** |
| :--- | :--- |
| `--sync` | Sync the Portage tree and regenerate caches |
| `--regen` | Regenerate md5-cache incrementally |

### Visualization

| **Flag** | **Action** |
| :--- | :--- |
| `--graph` | Generate interactive SVG dependency graphs |
| `--estimate` | Show build time estimates |

### Diagnostics

| **Flag** | **Action** |
| :--- | :--- |
| `--bugs <target>` | Search Gentoo Bugzilla for known issues |
| `--upstream <target>` | Check upstream versions via Repology |
| `--explain` / `--llm` | Get AI-assisted plan explanation |
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

### Output options

| **Flag** | **Effect** |
| :--- | :--- |
| `--verbose` | Verbose output (show USE flags, slot info) |
| `--quiet` | Minimal output |
| `--ci` | Non-interactive CI mode (exit codes 0/1/2) |
| `--jobs N` | Number of parallel jobs |
| `--timeout N` | Kill after N seconds (requires Python 3) |


## Target syntax

Targets can be specified in several formats:

| **Format** | **Example** | **Meaning** |
| :--- | :--- | :--- |
| `cat/pkg` | `sys-apps/portage` | Resolve latest version |
| `=cat/pkg-ver` | `=sys-apps/portage-3.0.77` | Exact version |
| `>=cat/pkg-ver` | `>=dev-lang/python-3.10` | Version constraint |
| `@set` | `@world` | Package set |
| `pkg` | `portage` | Ambiguous name (searched across categories) |


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
prover:test_stats(portage).
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
  narrate the plan (see [Chapter 16: Semantic Search and LLM Integration](16-doc-llm.md)).

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
  prover:test_stats(portage).
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

- **Search Bugzilla**  
  `portage-ng --bugs cat/pkg` — Bugzilla-oriented diagnostics for the target.


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
[Chapter 16: Semantic Search and LLM Integration](16-doc-llm.md).

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
- [Chapter 13: Output and Visualization](13-doc-output.md) — what the output
  looks like
