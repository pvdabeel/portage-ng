# Building and Execution

portage-ng is a self-contained dependency resolver and planner.  It
ships its own code for every stage up to the point where source code
must actually be compiled:

- **Cache generation** — portage-ng includes its own md5-cache
  generator, so it does not depend on Portage's `egencache` or any
  other external tool to produce the cache files it reasons over.
- **Dependency resolution and ordering** — the prover and the
  ordering engine are entirely internal (see Chapters 8-12).
- **Downloading** — source archive fetching, mirror selection, hash
  verification, and resume are handled by portage-ng's own download
  module (see [Download management](#download-management) below).

The only point where Portage is needed is the **execution of ebuild
build phases** (unpack, compile, install, merge, etc.).  That hand-off
is deliberate.  Everything before and after those phases — dependency
calculation, plan ordering, downloading, display, and recovery — is
owned by portage-ng; the phase bodies themselves remain Portage's.


## Why not our own `ebuild`?

It is natural to ask why a project that already replaced Portage's
resolver, planner, cache generation, and download path still shells out
to Portage's `ebuild` for the last mile.  The short answer is that
**portage-ng is a reasoning engine that happens to build packages**, not
a reimplementation of Gentoo's build runtime — and those are different
problems with different costs.

The hard problem this project set out to solve is *configuration as
proof*: which versions, which USE flags, which order, which assumptions,
and why.  That is where traditional emerge is weakest, and where a
Prolog prover earns its keep.  Phase execution is a different kind of
difficulty.  Making `src_compile` and `pkg_postinst` work for thirty
thousand ebuilds is less about elegant search and more about decades of
accumulated bash helpers, eclasses, sandbox policy, FEATURES knobs,
Prefix layout, binary-package merge, and VDB writes.  Portage already
ships that stack — on the order of many thousands of lines of
`ebuild.sh` helpers plus the Python merge path — and every real package
in the tree depends on it behaving exactly as maintainers expect.

Replacing it would not make plans better.  It would make portage-ng
responsible for a moving compatibility surface: every EAPI edge case,
every eclass quirk, every sandbox interaction that today "just works"
because the same `ebuild` that emerge uses is the one that runs.  An
in-house layer that is *almost* Portage becomes a permanent tax — a
second implementation forever chasing the first — without improving the
resolver metrics that actually distinguish this project.

So the design chooses a clean cut instead of a rewrite.  portage-ng
owns *which* phases run, *across which packages*, with *which USE*,
under *which concurrency rules*, and how failures are interpreted or
repaired.  Portage's `ebuild` owns *what happens inside a phase*.  That
cut is not an informal shell-out; it is the [ebuild contract](#the-ebuild-contract)
below — a fixed invocation shape, environment, vocabulary, and exit-code
semantics.  The builder and the execution modules speak only that
interface.  `config:ebuild_command/1` already names the backend, so a
future in-house layer can satisfy the same contract without touching the
planner, jobserver, display, or fixup registry.

In other words: **defer the runtime, own the reasoning.**  Shipping our
own `ebuild` remains a possible later step — for Prefix hygiene, for
dropping the sys-apps/portage dependency, or for tighter isolation —
but it is optional precisely because the contract keeps it optional.
Until then, the Gentoo tree builds with the ecosystem it was written
for, and portage-ng spends its depth where depth changes the outcome of
a prove.


## The ebuild contract

### Division of responsibility

| **Concern** | **Owner** | **Where** |
| :--- | :--- | :--- |
| md5-cache, VDB facts, preferences | portage-ng | reader / knowledge base |
| Dependency proof and ordered plan | portage-ng | resolver / orderer |
| Distfile fetch + Manifest verify | portage-ng | `Builder/download.pl` |
| Wave scheduling and `--jobs` tokens | portage-ng | `Builder/jobserver.pl` |
| Live display, logs, phase stats | portage-ng | `Builder/display.pl`, `ebuild_exec` |
| Per-package `USE=` string | portage-ng | `ebuild_exec:collect_use_string/4` |
| Phase sequence for a plan action | portage-ng | `ebuild_exec:action_phases/3` |
| Eclass stack, sandbox, `econf`/`emake`/`doins` | Portage `ebuild` | `ebuild.sh` + helpers |
| Image → live FS + VDB write | Portage `ebuild` | `merge` / `qmerge` |
| `FEATURES`, `ROOT`, `EPREFIX`, `PORTAGE_TMPDIR`, make.conf | Portage config stack | read by `ebuild`, not rewritten by portage-ng |
| Post-merge toolchain / `ghc-pkg` reactivation | portage-ng | hooks after a successful merge (see below) |
| Domain exception fixups and replans | portage-ng | `Exceptions/`, `builder:build_loop/2` |

portage-ng never reimplements ebuild phase bodies.  It chooses *which*
phases to run, *in what order across packages*, with *which USE*, and
interprets the exit code.  Portage's `ebuild` remains responsible for
*what happens inside a phase*.


### Invocation shape

Every source-build phase is started as:

```text
<ebuild_command> --skip-manifest <ebuild-path> <phase>
```

- **`<ebuild_command>`** — `config:ebuild_command/1` (default `ebuild`;
  override in the per-host config for Gentoo Prefix or a custom path).
- **`--skip-manifest`** — always passed.  Distfile integrity is already
  enforced by portage-ng's download stage; re-checking Manifest inside
  each phase would duplicate work and fight resume / mirror layouts.
- **`<ebuild-path>`** — absolute path of the `.ebuild` file for
  `Repo://Entry`, resolved via `Repo:get_ebuild_file/2`.
- **`<phase>`** — one atom from the allowlist in `sanitize:safe_phase/1`
  (`clean`, `setup`, `unpack`, `prepare`, `configure`, `compile`,
  `test`, `install`, `package`, `merge`, `unmerge`, …).  Unknown phase
  names are rejected before any process is spawned.

Logged / async runs wrap that argv in a **fixed** `sh -c` script whose
data travels only as positional parameters (`$1`…`$4`), never by
string interpolation — the same argv contract documented in
`Source/Application/Security/sanitize.pl`.  Bulk (no-progress) runs
call `process_create` on the ebuild binary directly with the phase list
as argv elements.


### Action → phase sequence

Plan actions map to a phase list in `ebuild_exec:action_phases/3`.
Build-shaped actions share one sequence from
`ebuild_exec:build_phases/1`:

| **Plan action** | **Phases** |
| :--- | :--- |
| `install` / `reinstall` / `update` / `downgrade` | see build sequence below |
| `uninstall` | `[unmerge]` |
| `run` | `[]` (no ebuild invocation) |

Default build sequence (source path):

```text
[clean?, setup, unpack, prepare, configure, compile, test?, install, package?, merge?]
```

Optional segments:

| **Segment** | **When included** |
| :--- | :--- |
| `clean` | omitted under `--resume` (`ebuild_exec:resuming`) so workdirs are reused |
| `test` | only when `FEATURES` contains positive `test` (`config:features_test_enabled`) |
| `package` | when `--buildpkg` or `--buildpkgonly` is set |
| `merge` | omitted under `--buildpkgonly` (binary package only) |

`merge` is the composite Portage phase: `pkg_preinst`, copy into the
live filesystem, unmerge of the old version on update/downgrade/
reinstall, VDB write, and `pkg_postinst`.  portage-ng therefore uses the
**same** phase list for install and for replacement actions — it does
not unmerge the old version before building (that would break
compile-time use of the installed predecessor).

Which of those phases actually run is further gated by
`config:build_live_phases/1`: a leading *live prefix* executes; the
trailing *stub tail* is displayed but not run.  An empty list stubs the
whole build (display-only).  The live prefix cannot skip a middle phase
and continue — `compute_live_prefix/4` stops at the first phase absent
from the config.


### Environment contract

portage-ng injects a small, explicit environment; everything else is
whatever Portage's `ebuild` would read on that host.

| **Variable** | **Set by** | **Meaning** |
| :--- | :--- | :--- |
| `USE` | portage-ng | Space-separated tokens (`flag` or `-flag`) matching the resolver's effective USE for this entry, including proof-context overrides (`build_with_use`, REQUIRED_USE assumptions, `suggestion(use_change, …)`). |
| `MAKEOPTS` | portage-ng (retry only) | Forced to `-j1` on the serial-make retry path; otherwise left to Portage / make.conf. |
| `FEATURES`, `ROOT`, `EPREFIX`, `PORTAGE_TMPDIR`, `PKGDIR`, … | Portage config stack | Not rewritten by the builder.  Prefix, temporary dirs, and feature flags come from the same `make.conf` / profile / `/etc/portage` that a bare `ebuild` would see. |

Agreement between planner and builder on `USE` is part of the contract:
`collect_use_string/4` resolves each IUSE flag through
`use:effective_use_for_entry/3` — the same predicate the prover uses —
then overlays proof-context forcing.  A mismatch here is a contract bug
(the plan says one thing; the ebuild runs another).


### Outcomes

Each action ends as one of:

| **Outcome** | **Meaning** |
| :--- | :--- |
| `done` | every live phase exited 0 |
| `failed(ExitCode)` | a phase exited non-zero (or setup could not locate the ebuild: `failed(no_ebuild)`) |
| `failed(qmerge_exit(N))` | binary path: `ebuild … qmerge` failed |

Per-phase progress callbacks (live display) use the states
`active`, `progress(Pct)`, `done`, `failed(ExitCode, LogPath)`,
`stub` (beyond live config), and `skipped` (after a failure).  Exit
status is the sole success signal; log size is used only for progress
estimates, never to infer whether a phase completed.


### Concurrency

Within a wave, independent packages may run phases in parallel under
the jobserver.  Two rules preserve Portage invariants:

1. **Compile-side parallelism is allowed.**  `clean` through `install`
   (and `package`) may overlap across workers.
2. **`merge` / `qmerge` are exclusive.**  Both take the
   `portage_pkg_merge` mutex.  Merge is not a pure file copy:
   `pkg_preinst` collision-protect reads the live tree, and
   `pkg_postinst` runs process-global updaters (`ldconfig`,
   `env-update`, preserved-libs, mime/icon/schema caches).  Traditional
   `emerge --jobs N` parallelizes compilation and serializes the merge
   into `${ROOT}`; portage-ng restores that invariant for the bare
   `ebuild` CLI.


### Post-merge hooks (outside the ebuild binary)

The bare `ebuild` CLI does not perform everything `emerge` does between
packages.  After a successful install-family action, portage-ng runs
domain hooks that keep the live root coherent for later phases in the
same plan:

- **Toolchain reactivation** (`maybe_reactivate_toolchain/4`, gated by
  `config:toolchain_reactivation/1`) — after merging `sys-devel/gcc`
  (and related toolchain CNs), re-select the gcc-config profile and/or
  run `env-update` so a later package's `pkg_setup` sees the new
  compiler (portage-ng#86, especially under `FEATURES=ccache`).
- **`ghc-pkg recache`** (`maybe_register_ghc_pkg/4`, gated by
  `config:ghc_pkg_register/1`) — after merging `dev-lang/ghc`, refresh
  the package DB so boot libraries are visible to subsequent
  `dev-haskell/*` configures (portage-ng#108).

These hooks are part of the *builder-side* half of the contract: a
replacement ebuild backend that already performed equivalent work could
no-op them, but today's Portage `ebuild` path relies on them.


### Binary packages (same contract, different entry)

When `config:use_binpkg/1` is enabled and
`binpkg_exec:available_for/4` finds a USE-/slot-/keyword-compatible
gpkg, the builder short-circuits the source phase list and drives:

```text
ebuild --skip-manifest <source-ebuild-path> qmerge
```

with environment including the resolver's `USE`, plus
`MERGE_TYPE=binary`, `PORTAGE_BINPKG_FILE=<gpkg>`, and
`PORTAGE_BUILDDIR=<builddir>`.  Extraction is owned by
`binpkg_extract`; VDB write and `pkg_*inst` remain inside Portage's
`qmerge`.  Failure outcomes and the merge mutex are shared with the
source path.  Producing binpkgs (`package` phase under `--buildpkg`)
stays on the source path in `ebuild_exec`.


### What a replacement backend must provide

To swap Portage's `ebuild` for an in-house layer without touching the
planner, a backend must:

1. Accept `--skip-manifest <ebuild-path> <phase>` (or be wrapped so the
   builder's argv stays unchanged via `config:ebuild_command/1`).
2. Honour the phase vocabulary and ordering above, including composite
   `merge` / `qmerge` semantics for live FS + VDB.
3. Treat process exit status as the sole success signal.
4. Read host Portage configuration for `FEATURES` / `ROOT` / `EPREFIX`
   / temporary directories until those knobs are lifted into portage-ng.
5. Tolerate `USE` (and optional `MAKEOPTS`) injected by the parent
   environment.
6. Remain safe under parallel compile-side workers with exclusive
   merge/qmerge.

Until that backend exists, `config:ebuild_command/1` points at
sys-apps/portage's `ebuild` (or a Prefix wrapper of it).


## Build orchestration

When executing a plan (via `--merge` rather than `--pretend`), the
builder walks the plan wave by wave, respecting the parallelism from
the ordering pass.  Within each wave, independent actions run
concurrently under the jobserver.  Each build-shaped action is handed
to `ebuild_exec:execute/5` or `execute_with_progress/6`, which speak
only the contract above.


## Build resilience: the per-phase retry chain

A failed phase is not necessarily a failed build.  After every phase,
`ebuild_exec` runs a chain of retry hooks, each keyed on a *signature*
found in the log segment written by the failed phase (never earlier
phases), so deterministic build failures never match and keep their
original semantics.  The chain has two layers:

1. **Environmental retries** (in `ebuild_exec.pl` itself) — failures
   caused by the build environment, not by the package:

   | **Retry** | **Signature** | **Recovery** | **Gate** |
   | :--- | :--- | :--- | :--- |
   | Transient (bash PID reuse) | `wait: pid N is not a child of this shell` | re-run the phase once | `config:build_transient_retry/1` |
   | Serial make (parallel-make race) | failed compile/test/install phase | re-run with `MAKEOPTS=-j1` | `config:build_serial_retry/1` |

2. **Domain exception fixups** (see next section) — failures caused by
   a problem that should really be fixed at the ebuild or metadata
   level.  The chain ends in a single generic dispatch,
   `fixup:maybe_phase_retry/9`, which offers the failure to every
   registered exception mechanism.

Every retry appends a marker line to the build log, so a recovered
build is never silent about how it recovered.


## Domain exception fixups

Some build failures are *packaging exceptions*: the build is failing
because of a gap in the ebuild or its metadata, not because of the
environment or the user's configuration.  Traditional emerge either
refuses such packages up front or fails and defers to a manual repair
tool.  portage-ng recovers them in-transaction through a small
registry of **exception mechanisms** under
`Source/Domain/Gentoo/Exceptions/`:

- **`fixup.pl`** — the generic registry and dispatcher.  A mechanism
  registers itself with three multifile hooks:
  - `fixup:mechanism/1` — identity (load order is dispatch and
    display order);
  - `fixup:phase_retry_hook/10` — the repair-and-retry logic for a
    failed phase;
  - `fixup:mechanism_note/3` — the note printed above the affected
    packages in the build summary.

  Applied fixups are recorded via `fixup:record/3` and reported
  generically by the build printer — adding a new exception mechanism
  never touches the builder or the printer.

Mechanisms come in two flavours.  Most (collision, GHC ABI, OCaml ABI)
are **in-place repairs**: they rebuild something mid-flight and re-run
the failed phase.  The missing-provider mechanism is different — it
**diagnoses but never repairs in place**: it records what it learned
and lets the pipeline re-derive a fresh plan (see
[Missing provider feedback](#missing-provider-feedback)
below).

### File collision deconfliction

Traditional emerge refuses, at the plan stage, to install a package
whose files are owned by a different installed provider — it is told
so by an explicit blocker atom in metadata (e.g. installed
`sys-apps/util-linux[hardlink]` carries `!app-arch/hardlink`).  When
that blocker atom is *missing*, the conflict only surfaces at merge
time as Portage's `pkg_preinst` collision-protect abort.  Gated by
`config:deconflict_collisions/1` (`off` | `report` | `override`), the
mechanism recognises the collision signature and re-runs the merge
with `FEATURES="-collision-protect -protect-owned"`, letting the
package overwrite the colliding files.  The plan printer already
announces this behaviour next to the soft-blocker list, and the build
summary lists every package that needed it.  The same recovery is
applied to binary-package `qmerge` merges.

### Haskell ABI repair

Gentoo encodes a Haskell package's identity in `ghc-pkg`'s ABI hash
(the suffix in e.g. `bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ`), not in
the ebuild sub-slot.  When a `dev-haskell` library is rebuilt, its
installed reverse-dependencies keep referencing the old hash, and the
next Haskell consumer aborts in `pkg_setup`/`configure` with
haskell-cabal.eclass's check:

```
installed package semigroupoids-5.3.7 is broken due to missing package
bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ
 * Detected broken packages: semigroupoids-5.3.7 semialign-1.3
 * //==-- Please, run 'haskell-updater' to fix broken packages --==//
```

Because the hash lives only in ghc-pkg's registry, there is no
sub-slot delta for the resolver to observe, and traditional emerge
fails the same configure and defers to a manual `haskell-updater`
run.  portage-ng does better: gated by `config:ghc_abi_repair/1`, the
mechanism parses the broken package list from the failed phase's log,
rebuilds each broken package from source at its installed version and
with its VDB-recorded USE configuration (never from a binary package —
a stale binpkg ABI is exactly what may be broken), and re-runs the
failed phase.  One additional bounded round covers cascading breakage
exposed by the repair itself.

The mechanism is bounded and observable: each package is rebuilt at
most once per session (it can never loop), repairs are serialized
across parallel build workers, and every repair leaves markers in
both the consumer's and the rebuilt package's build logs plus an
entry in the build summary.

### OCaml ABI repair

OCaml has the same problem: package identity lives in the compiled
interface digests (`.cmi` CRCs) checked by the compiler and in
findlib's registry, not in the ebuild sub-slot.  Unlike Haskell there
is no single eclass check enumerating the broken packages — a stale
consumer fails with heterogeneous compiler and ocamlfind messages:

```
Error: The files /usr/lib64/ocaml/site-lib/res/res.cmi
       and /usr/lib64/ocaml/stdlib.cmi
       make inconsistent assumptions over interface Stdlib
Error: Unbound module Camlp5
ocamlfind: Package `camlp5' not found
```

Gated by `config:ocaml_abi_repair/1`, the mechanism extracts the
stale compiled-unit paths and findlib package names from the failed
phase's log, maps them to their installed owners through the VDB
CONTENTS records (the active enumerator this domain lacks an eclass
check for), rebuilds those owners from source at their installed
version, and re-runs the failed phase — with the same boundedness
guarantees as the GHC repair: at most one rebuild per package per
session, at most two retry rounds, repairs serialized across workers,
and markers in every involved build log plus the build summary.  The
package being built and `dev-lang/ocaml` itself are never rebuild
candidates.

### Missing provider feedback

The three mechanisms above all repair reality in place: they rebuild a
package mid-transaction and re-run the failed phase.  That pattern is
wrong for a whole class of failures — a build that dies because a
required *provider* is missing (a command, header, library, or
pkg-config module that some package would supply but that the ebuild
never declared as a dependency).  The canonical case is
`sec-policy/selinux-base`, whose compile dies with

```
semodule_package: command not found
```

because `selinux-policy-2.eclass` never lists `sys-apps/semodule-utils`
in `BDEPEND`.  portage-ng built exactly what it was told to; the
dependency simply is not in the metadata, so the resolver never saw it.
Repairing this in place would decide ordering imperatively in the
builder, could not chase the provider's own transitive needs, would
break the invariant that the plan equals `prove_plan(Goals, KB)`, and
would forget the discovery so the next run fails again.

So `missing_provider.pl` (portage-ng#102), gated by
`config:missing_provider_feedback/1`, does the opposite of a repair:
**it emits a structured diagnostic, that diagnostic becomes learned
knowledge, the pipeline re-derives a fresh provable plan that orders the
provider before the target, and the builder resumes that new plan.**
Plans are derived, never patched.  It threads the failed phase's exit
code through unchanged — the phase legitimately still failed.

The diagnosis is split into two pluggable layers, each a multifile
registry so new failure shapes and resolution strategies are added as
clauses rather than by editing the dispatcher:

- **Detector registry** (`missing_provider:detector/3`) normalises the
  failed phase's log tail into a `symbol(Kind, Name)`.  Ships detectors
  for missing commands (bash `command not found`, dash `not found`,
  `env` exec failures), headers (`fatal error: X.h`), libraries
  (`cannot find -lX`), sonames, pkg-config modules, and python/perl
  modules.
- **Resolver chain** (`missing_provider:provider_of/4`) maps a symbol to
  a concrete `Category/Name` package: first the authoritative VDB
  `CONTENTS` reverse-owner index (the `qfile`/`equery belongs`
  equivalent, for providers that happen to be installed), then a small
  curated seed table (for the common case where the provider is *not*
  installed — that is precisely why the command was missing).  A symbol
  that maps to no concrete in-tree package is written to an unresolved
  backlog and the target fails cleanly — no guessing.

A concrete discovery is recorded through the `feedback` module
(`Source/Knowledge/feedback.pl`) as a durable `discovered_dep/4` fact,
persisted to `Knowledge/feedback.pl` (gitignored, consulted at startup
like the QLF cache) so a one-time runtime discovery becomes permanent
knowledge.  The only resolver change is in `query.pl`, which unions
`feedback:discovered_dep(Target, Provider, bdepend, _)` into the
target's build-dependency model.  The mechanism also distinguishes an
*undeclared* dependency (the upstream-gap case above — mint a discovery)
from a *declared-but-unbuilt* one (a genuine resolver ordering
bug — logged loudly, never papered over).

The control loop lives in the builder: `builder:build/1` is a bounded
replan loop (`builder:build_loop/2`, capped by
`config:missing_provider_max_replan/1`).  When a build pass fails *and*
recorded a new discovery, the builder re-enters the pipeline; on the
re-proof the provider is part of the closure, so the ordering pass
orders it — and its own transitive dependencies — before the
target.  Everything already built satisfies from the VDB via the
existing reconciliation fast path, so the retry pass only builds the
provider and recompiles the target.  Walkthrough for the selinux case:

1. `selinux-base` compile → `semodule_package: command not found`.
2. `missing_provider` maps the command to `sys-apps/semodule-utils`,
   records a `discovered_dep`, and persists it; the phase still fails.
3. The wave ends with `selinux-base` failed; `build_loop` sees the new
   discovery and re-enters the pipeline.
4. `rules`/`query` now yield
   `BDEPEND(selinux-base) ⊇ {sys-apps/semodule-utils}`; the prover
   proves it, the orderer places `semodule-utils` (and its transitive
   `sys-libs/libsepol`) first.
5. Retry pass: the provider builds, `selinux-base` recompiles, and the
   300+ downstream `selinux-*` packages never fail — the discovery is
   persisted before their turn.

Because the discovery carries structured evidence (the symbol, phase,
exit code, and log excerpt), the printer proposes a Gentoo Bugzilla bug
report draft at the end of the build for every dependency worked around
this session — the record doubles as an upstream ebuild/eclass bug
report (see [Chapter 19](19-doc-upstream-bugs.md)).

### USE-enable feedback

A closely related gap is when the provider *is* declared and even
installed, but was built with the wrong USE set — e.g.
`KX11Extras: No such file or directory` because
`kde-frameworks/kwindowsystem` was merged `-X` on a headless profile
(portage-ng#110).  Re-adding a bare `cat/name` BDEPEND (the #102 path)
is a no-op: the package is already in the plan/VDB.  What is missing is
a HARD `[flag]` usedep — an unconditional USE dependency, as opposed to
a `[flag?]` / `[flag=]` one that follows the consumer (terminology box,
Chapter 13).

`useenable.pl`, gated by `config:use_enable_feedback/1`, mirrors the
#102 three seams: detect a compile/configure symbol, resolve it via a
curated seed table to `Provider + HARD usedeps`, record a durable
`feedback:discovered_usedep/4`, and let `builder:build_loop/2`
re-derive.  On the next proof `query.pl` unions a
`package_dependency(..., UseDeps)` edge so the existing BWU /
`bwu_force` machinery rebuilds the provider with the flag.  Plans stay
derived — the hook never writes `/etc/portage/package.use` itself
(any `suggestion(use_change)` that the re-derived plan emits is a
consequence of proving, not an imperative patch).

### Build summary reporting

At the end of a build, the printer renders one block per mechanism
that applied fixups, using the mechanism's own note:

```
Total: 46 completed.

Deconfliction: collision protection was disabled to merge 1 package over
               files owned by other installed packages (portage-ng#90):
  - app-arch/hardlink-0.3.2

GHC ABI repair: 2 broken packages rebuilt in-transaction after a
                dependency ABI-hash change (portage-ng#93, haskell-updater equivalent):
  - dev-haskell/semialign-1.3
  - dev-haskell/semigroupoids-5.3.7

Missing provider: 1 package had an undeclared build dependency discovered at
                  build time and learned as BDEPEND (portage-ng#102):
  - sec-policy/selinux-base
```

Followed, for a missing-provider discovery, by the bug report draft:

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


## Live build display

During a `--merge` run, portage-ng keeps the terminal display
up-to-date so you can see exactly where the build process stands at
any moment.  The static plan that was printed during the `--pretend`
phase is reprinted once, and below it a live "Executing" area shows
the current state of every active build slot.

The following example shows the pretend output for
`sys-kernel/gentoo-sources`.  The plan has three steps: download the
source tarball plus patches, install the package, and register the
runtime phase.

```
>>> Emerging : portage://sys-kernel/gentoo-sources-6.19.11:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─[step  1]─┤ download  portage://sys-kernel/gentoo-sources-6.19.11
             │           └─ file ─┤ 877.73 Kb   genpatches-6.19-10.base.tar.xz
             │                    │ 4.22 Kb      genpatches-6.19-10.extras.tar.xz
             │                    │ 148.84 Mb    linux-6.19.tar.xz

 └─[step  2]─┤ install   portage://sys-kernel/gentoo-sources-6.19.11
             │           └─ conf ─┤ USE = "build symlink -experimental"
             │                    │ SLOT = "6.19.11"

 └─[step  3]─┤ run       portage://sys-kernel/gentoo-sources-6.19.11

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       149.70 Mb to be downloaded.
```

When the same target is merged with `--merge`, the display turns
into a live view.  Each step gains a phase line showing the
individual ebuild phases and their current state.  A snapshot
mid-build might look like this:

```
These are the packages being merged, in order:

Executing 3 actions, grouped into 3 steps...

 └─[step  1]─┤ download  portage://sys-kernel/gentoo-sources-6.19.11    ✓
             │           └─ file ─┤ 877.73 Kb   genpatches-6.19-10.base.tar.xz     ✓
             │                    │ 4.22 Kb      genpatches-6.19-10.extras.tar.xz   ✓
             │                    │ 148.84 Mb    linux-6.19.tar.xz                  ✓

 └─[step  2]─┤ install   portage://sys-kernel/gentoo-sources-6.19.11    ⣾
             │           └─ exec ─┤ ACTION = setup → unpack → prepare   (42%) 2/7
             │                    │ LOG = /var/log/portage/sys-kernel:gentoo-sources.log

 └─[step  3]─┤ run       portage://sys-kernel/gentoo-sources-6.19.11
```

In this snapshot, step 1 (download) has completed — each file shows
a green check mark on the right edge.  Step 2 (install) is active:
the action line shows a spinning indicator, and the phase line
reveals that `setup` and `unpack` have finished (shown in cyan)
while `prepare` is the current phase.  The right edge displays the
accumulated progress (`42%`) and a phase counter (`2/7`).  Step 3
(run) is still pending in dark grey, waiting for the install to
finish.

### Slot states and colours

Each slot in the live display represents one concurrent build.  The
slot line changes colour and icon as the build progresses:

| **State** | **Colour** | **Indicator** |
| :--- | :--- | :--- |
| Pending | Dark grey | Waiting for prerequisites |
| Active | Cyan (action) + green (target) | Spinning indicator on the right edge |
| Done | Green | Check mark |
| Failed | Red | Exclamation mark |
| Stub | Grey | Phase skipped (already satisfied) |

### Per-ebuild phase tracking

Below each slot line, the display shows the individual ebuild phases
(setup, unpack, prepare, configure, compile, install, merge — or
`qmerge` on the binary path) with their current status.  Each phase
word is coloured independently:

- **Dark grey** — pending (not yet started)
- **Cyan** — active or in progress
- **Green** — completed successfully
- **Red** — failed

The builder tracks phase state through `builder:exec_phase_state/3`,
which is updated by a callback from the ebuild execution module as
each phase starts, progresses, and finishes.

### Progress indicators

portage-ng shows progress at multiple levels:

- **Per-phase percentage** — during long phases like `compile`, the
  builder polls the build log every 0.5 seconds and computes a
  progress estimate.  This blends two signals: the growth of the log
  file (bytes written) and historical data from previous builds of
  the same package (stored in `Knowledge/phase_stats.pl`).
- **Overall progress** — the right edge of the display shows an
  accumulated percentage and a counter (`Current/Total`) reflecting
  how many actions have completed out of the total plan.  Stub
  actions (already satisfied) are excluded from the total.
- **Download progress** — for parallel downloads, each file shows a
  percentage and transfer speed.  Git clones show a separate
  percentage based on the git progress output.

### Log file locations

Each build action writes its output to a log file.  The path is
computed from the build log directory (`config:build_log_dir/1`) and
the ebuild name.  When `--logs` is enabled, the log path is displayed
below the phase line for each slot.  If a phase fails, the log path
turns red so you can quickly find the relevant output.

### Terminal refresh

The live display uses ANSI cursor movement to update individual lines
in place: the builder moves the cursor up to the target line,
redraws it, and moves back down.  This avoids flooding the terminal
with repeated full-screen redraws.  All display mutations go through
a `build_display` mutex to prevent concurrent workers from
interleaving their output.

In non-TTY environments (e.g. CI pipelines), cursor movement is
disabled and the builder falls back to sparse status lines.


## Build time estimation

The `buildtime.pl` module predicts build duration from two data sources:

1. **VDB sizes** — the installed file sizes from `/var/db/pkg/*/SIZE`
   correlate with build complexity.

2. **emerge.log history** — historical build times from
   `/var/log/emerge.log` provide empirical timing data for packages that
   have been built before.

The `--estimate` CLI option shows predicted build times in the plan output.


## Jobserver

The `jobserver.pl` module manages parallel build execution.  It implements
a token-based jobserver that limits concurrent builds to the number of
available cores (or a user-specified `--jobs` count).


## Download management

The `download.pl` module handles source archive fetching:

- Mirror layout detection via `curl`
- Parallel downloads across multiple mirrors
- Hash verification via `openssl dgst`
- Resume support for interrupted downloads

Downloads are scheduled as early as possible in the plan — `:download`
actions have no unmet requirements, so they land in the earliest waves
and packages can download while others are building.


## Snapshot support

Upgrades can go wrong — a new version may fail to compile, introduce
regressions, or break other packages.  portage-ng's snapshot module
(`Source/Pipeline/Builder/snapshot.pl`) lets you freeze the current
system state before a merge and roll back to it afterwards.

### How a snapshot is created

When a merge begins with `--snapshot` (or with `config:snapshot_enabled`
asserted in the per-machine config — snapshots are disabled by default),
portage-ng creates a snapshot identified by a timestamp
(e.g. `20260405-143012`).  The snapshot directory contains three files:

- **`manifest.pl`** — a Prolog fact file listing every package
  currently installed in the VDB, with category, name, version, and
  slot.
- **`world`** — a copy of the current world set file, so the set of
  explicitly requested packages can be restored exactly.
- **`actions.pl`** — the planned actions for the merge, recorded so
  that a rollback knows which packages were touched.

### Quickpkg: preserving the old version

The key to rollback is preserving the **binary package** of each
package that is about to be replaced.  Before portage-ng merges a
new version, the builder calls `snapshot:quickpkg_old/2`.  This runs
`ebuild --skip-manifest <old-ebuild> package` with `PKGDIR` pointed
at the snapshot's `binpkgs/` directory.  The result is a tarball
(`.tbz2` or `.gpkg.tar`) that contains the currently installed files
of the old version — essentially the same operation that Gentoo's
`quickpkg` tool performs.

Because this happens **per package, just before the upgrade**, the
snapshot accumulates exactly the set of binary packages needed to
reverse the merge.  Packages that were not touched are not
quickpkg'd; they remain unchanged on the system.

### Listing and diffing snapshots

`--snapshots` shows all available snapshots with their
timestamp, installed package count, and the number of binary
packages stored:

```
Available snapshots:
  20260405-143012       2026-04-05 14:30:12   1847 pkgs   12 binpkgs
  20260402-091544       2026-04-02 09:15:44   1843 pkgs    5 binpkgs
```

`--rollback <id> --pretend` compares a snapshot's manifest against the
current VDB and shows what changed — packages installed since the
snapshot, packages removed, and packages whose version changed:

```
Diff against snapshot "20260405-143012":

  Installed since snapshot (2):
    + dev-libs/newlib-4.5.0
    + dev-util/newtool-1.0

  Version changed since snapshot (3):
    ~ sys-libs/glibc  2.40-r2 -> 2.41
    ~ dev-lang/python  3.12.8 -> 3.13.1
    ~ app-editors/vim  9.1.1652-r2 -> 9.1.1700

  Summary: +2 -0 ~3 (3 binpkgs available for rollback)
```

### Rolling back

`--rollback <id>` reinstalls the saved binary packages
from the snapshot's `binpkgs/` directory and restores the world set
file.  Each binary package is merged back onto the system via
`ebuild <binpkg> merge`, downgrading the affected packages to their
pre-upgrade versions.  Combined with `--pretend`, the rollback
shows what would be reinstalled without actually making changes.

### Lifecycle

After the merge completes (whether successfully or not), the
snapshot remains on disk so it can be used for rollback at any
later time.  There is no delete flag; to reclaim disk space, call
`snapshot:delete(Id)` from `--shell` (or remove the snapshot
directory by hand).


## Further reading

- [Why not our own `ebuild`?](#why-not-our-own-ebuild) (this chapter) —
  design rationale for delegating phase execution
- [The ebuild contract](#the-ebuild-contract) (this chapter) — invocation,
  environment, outcomes, and what a replacement backend must provide
- [Chapter 13: Ordering — Plans as Proofs](13-doc-planning.md) — how the
  plan is constructed
- [Chapter 14: Output and Visualization](14-doc-output.md) — plan
  display and `.merge` file generation
- [Chapter 15: Command-Line Interface](15-doc-cli.md) — `--merge`,
  `--jobs`, `--estimate` flags
- `Source/Domain/Gentoo/Ebuild/ebuild_exec.pl` and
  `Source/Domain/Gentoo/Binpkg/binpkg_exec.pl` — implementation of the
  contract
- `Source/Application/Security/sanitize.pl` — argv / phase allowlist
  rules shared with download and other spawn sites
