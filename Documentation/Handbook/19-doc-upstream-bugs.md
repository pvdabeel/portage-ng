# Upstream and Bug Tracking

portage-ng integrates with external services to check upstream versions
and search for known issues, helping users identify outdated packages and
known dependency bugs.


## Git repository integration

portage-ng can connect directly to a Git repository and turn Git
metadata into Prolog facts.  This means it can inspect commit
history, changelogs, and file-level changes for any ebuild without
relying on separate tools.  The Git metadata is ingested alongside
the regular cache data, so queries like "when was this ebuild last
updated?" or "which ebuilds changed in the last sync?" can be
answered from within the resolver.


## Upstream version checking

The upstream module (`Source/Domain/Gentoo/upstream.pl`) checks package
versions against upstream releases via the Repology API.

### Usage

```bash
portage-ng --upstream sys-apps/portage
portage-ng --upstream @world
```

### How it works

1. For each target package, the module queries the Repology API
   (`https://repology.org/api/v1/project/<name>`) for version information.

2. The response includes version data across multiple distributions,
   which is compared against the version in the local Portage tree.

3. Results are categorized:
   - **Up to date** — local version matches or exceeds upstream
   - **Outdated** — a newer upstream version exists
   - **Unknown** — package not tracked by Repology

### Output

The upstream check displays a comparison table showing the local version,
the latest upstream version, and the status for each package.


## Gentoo Bugzilla integration

The bugs module (`Source/Domain/Gentoo/bugs.pl`) plays two roles: it is
the backend of the `bugzilla` repository type (a local, synced copy of
the public bug tracker), and it answers `--search-bugs` queries.

### The `bugzilla` repository type

Like `eapi` (a Portage tree), `vdb` (installed packages) or `binpkg`, a
repository instance can be declared with type `bugzilla`.  Its remote is
a Bugzilla instance, its location holds the raw pages fetched from the
REST API plus a resume state file, and its cache slot names the qcompiled
store the rest of portage-ng reads:

```prolog
:- bugzilla:newinstance(repository).
:- bugzilla:init('/var/cache/bugzilla',             % pages/ + state.pl
                 '/root/prolog/Knowledge/bugs.qlf',  % the bug store
                 'https://bugs.gentoo.org','rest','bugzilla').
:- kb:register(bugzilla).

config:repository_sync_limit(bugzilla, 1).           % network syncs per day
```

`--sync` (or `--sync bugzilla`) then runs the usual three phases:

1. `sync(repository)` — the network step.  The first run walks the whole
   public bug space by bug-id keyset (`f1=bug_id&o1=greaterthan`, ordered
   by id, `config:bugzilla_page_size/1` bugs per page, a
   `config:bugzilla_request_delay/1` pause between pages).  Every page is
   written to `<location>/pages/` and the state file advances after each
   one, so an interrupted crawl resumes where it stopped.  Once complete,
   later runs only fetch bugs whose `last_change_time` moved since the
   previous run (with a ten-minute overlap).
2. `sync(metadata)` — a no-op; the pages are the metadata.
3. `sync(kb)` — folds the pending pages onto the store (a bug delivered
   again replaces its earlier row), writes `Knowledge/bugs.raw`, qcompiles
   it to `Knowledge/bugs.qlf` and deletes the consumed pages.  With
   `config:bugzilla_scope(open)` closed bugs are dropped at this point;
   the default `all` keeps every public bug (about 600k rows, ~100 MB
   qlf).

The store is separate from `kb.qlf` and loaded lazily
(`bugs:ensure_loaded/0`) by its consumers.  Two fact families live in
module `bugsdata`:

- `bug(Id, Product, Component, Status, Resolution, Severity, Priority,
  Assignee, Created, Changed, Keywords, Summary)`
- `bug_atom(Id, Category, Name, Version)` — every `category/name[-version]`
  atom found in the summary or in `cf_stabilisation_atoms`, with
  Version a `version/7` term or `version_none`.  Categories are validated
  against the loaded tree so prose such as `usr/bin` is not indexed.

### Daily sync cap

`config:repository_sync_limit(Repository, PerDay)` bounds the number of
network syncs of any registered repository within a rolling 24-hour
window; stamps are kept in `Knowledge/<Repository>.sync`.  When the cap is
reached the network step is skipped with a notice and the metadata / kb
steps still rebuild from local data.  Repositories without a declaration
are unlimited.  The default host configs declare `bugzilla, 1`, which is
the intended way to stay well within
[Gentoo's bot policy](https://bugs.gentoo.org/bots.html) while keeping
the local store fresh.

### Searching (`--search-bugs`)

```bash
portage-ng --search-bugs dev-lang/rust
portage-ng --search-bugs "openssl segfault"
```

`config:bugzilla_search/1` selects the policy:

- `cache_first` (default) — a `category/name` term is answered from the
  atom index, anything else by a case-insensitive summary match, both
  against the local store (the output names the store's sync time).  The
  live REST quicksearch is only used when nothing matches locally or no
  store has been synced.
- `rest` — always query the Bugzilla REST API directly.

### Consumers of the store

- `--graph` renders a **bugs** page per ebuild (`<entry>-bugs.html`,
  `Source/Application/Output/Grapher/tracker.pl`): every bug naming the
  package, newest first, open bugs and bugs naming the page's exact
  version highlighted, each folding open to its stored columns.  The
  navigation bar's `bugs` pill counts the open bugs naming the package.
  See [Chapter 14](14-doc-output.md#graph-submodules).
- The plan printer lists up to three known open bugs (exact-version
  matches first) under every domain assumption that names a package,
  gated by `config:bugzilla_annotate/1`.  This is informational only: it
  changes neither the assumption nor the exit code.

Without a synced store all consumers stay silent, so hosts that never
register a `bugzilla` repository see no change.


## Automatic bug report drafts

The issue module (`Source/Domain/Gentoo/issue.pl`) generates structured
Gentoo Bugzilla bug report drafts when the prover detects unsatisfiable
dependencies.

A generated report includes:

- **Summary** — one-line description of the issue
- **Affected package** — the package atom
- **Unsatisfiable constraints** — the specific dependency that cannot be
  met
- **Observed state** — what the prover found (missing package, version
  conflict, REQUIRED_USE violation)
- **Suggested fix** — recommended action (add keyword, unmask, fix
  dependency)

These drafts can be used as starting points for filing bugs with the
Gentoo bug tracker.


## Bug report drafts from build-time discoveries

The prover-driven drafts above are generated at plan time from
unsatisfiable dependencies.  A second source of drafts comes from the
**missing-provider feedback loop** (portage-ng#102): when a build fails
because of an *undeclared* build dependency — a command, header,
library, or pkg-config module the ebuild needed but never listed in
`BDEPEND` — the builder records the discovery and re-derives a plan that
supplies it (see
[Chapter 16: Missing provider feedback](16-doc-building.md#missing-provider-feedback)).

Because every discovery carries structured evidence — the missing
symbol, the phase it surfaced in, the exit code, and the offending log
line — the printer proposes a bug report draft at the end of the build
for each dependency worked around this session:

```
>>> Missing build dependencies discovered (bug report drafts)

---
Summary: sec-policy/selinux-base: missing BDEPEND=sys-apps/semodule-utils (command semodule_package not found)

Affected package: portage://sec-policy/selinux-base
Missing dependency: sys-apps/semodule-utils (build-time / BDEPEND)
Observed:
  command semodule_package not found during the compile phase (exit 127):
    semodule_package: command not found
Potential fix (suggestion):
  Add BDEPEND="sys-apps/semodule-utils" to the ebuild or the responsible inherited eclass.
  (discovered by portage-ng missing-provider feedback, portage-ng#102)
```

Unlike the prover-driven drafts (which report a dependency that *cannot*
be satisfied), these report a dependency that *was* satisfied once
portage-ng learned it — so the draft is a ready-to-file "add
`BDEPEND=<provider>`" fix against the ebuild or its inherited eclass.
Both kinds of draft are gated by `config:bugreport_drafts_enabled/1`.


## Further reading

- [Chapter 15: Command-Line Interface](15-doc-cli.md) — `--upstream` and
  `--bugs` flags
- [Chapter 9: Assumptions and Constraint Learning](09-doc-prover-assumptions.md) —
  how unsatisfiable dependencies are detected
- [Chapter 16: Building and Execution](16-doc-building.md) — the
  missing-provider feedback loop that produces build-time bug drafts
- [Chapter 20: Gentoo Linux Security Advisories (GLSA)](20-doc-glsa.md) —
  security advisories and `@security` remediation sets
