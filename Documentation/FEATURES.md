# portage-ng — Feature highlights

## Reasoning engine

**Proof-based build plans.**
Every build plan is a formal proof.  Each package carries its justification --
which rule selected it, which constraints were imposed, and which assumptions
were made.  Plans are not heuristic guesses; they are derivations you can
inspect and replay.

**Feature-term unification.**
When the same package appears from multiple dependency paths, portage-ng merges
the accumulated constraints (USE flags, slot bindings, ordering) via
feature-term unification.  Only the difference is re-expanded -- no redundant
re-proving.

**Multiple solutions and variants.**
The engine reasons about the configuration space rather than committing to a
single path.  Different USE flag settings, version choices, and dependency
routes yield distinct proven plans.  `--variants` lets you compare how toggling
a flag or switching a slot changes the result.

**Constraint learning.**
Version domains are narrowed incrementally across retries.  Conflicts are
recorded as no-goods and the prover restarts with the additional knowledge --
closer to CDCL-style learning than to traditional Prolog backtracking.

**Progressive relaxation.**
Strict proving is attempted first.  If it fails, portage-ng progressively
relaxes: keyword acceptance, blocker resolution, unmasking, and combinations.
Each tier is a weaker proof that still carries formal guarantees.  Every
relaxation step is tracked and reported.

**Actionable suggestions.**
When relaxation is needed, the plan includes the exact changes required --
`package.accept_keywords`, `package.unmask`, `package.use` entries -- already
applied within the plan for you to review before committing.

**Always produces a plan.**
portage-ng succeeds for every target, including targets where traditional
resolvers give up.  Assumptions are explicit, never silent.

## Ordering and planning

**Plans as proofs.**
Ordering is a second pass of the same prover over a handful of generic
planning laws: a step is placed once everything it requires is available.
Every placement in the plan carries a human-readable justification.

**Wave planning.**
Wave numbers are projected from the availability proofs, exposing maximal
parallelism per wave.  Packages that can build concurrently are grouped
into the same step from the start -- parallelism is a first-class property of
the plan, not an afterthought.

**Action-level scheduling.**
Downloads, installs, runtime checks, and confirmations are independent actions.
Packages can install while others are still downloading.

**Cycle handling via the installed world.**
A dependency loop is bridged by citing an already-installed package (VDB),
the way Linux From Scratch reasons about its temporary toolchain.  Where
nothing bridges the loop, the plan reports an honest `unreachable`
assumption -- the genuine bootstrap boundary.

**Build-time estimation.**
`--estimate` predicts per-package and total build duration using VDB sizes and
historical `emerge.log` data, accounting for the parallelism in the plan.

## Knowledge base

**Md5-cache ingestion.**
The EAPI DCG grammar parses the Portage md5-cache directly into Prolog facts --
no bash evaluation, no external tooling.  Supports PMS 9 / EAPI 9.

**In-memory knowledge base.**
The entire Portage tree (~32,000 ebuilds) is held in memory as indexed Prolog
facts.  Queries resolve in microseconds.

**QLF binary cache.**
After `--sync`, the knowledge base is compiled to SWI-Prolog's QLF format for
instant cold-start loading.

**Compile-time query expansion.**
`goal_expansion/2` macros rewrite abstract queries into direct indexed fact
lookups at compile time, eliminating runtime dispatch overhead.

**Incremental cache regeneration.**
`--regen` regenerates the md5-cache incrementally and in parallel, replacing
`egencache` with a faster alternative that only processes changed or new
ebuilds.

## Gentoo domain

**Full PMS coverage.**
USE-conditional dependencies, slot operators (`:=`, `:`*), sub-slots, blockers,
PDEPEND, BDEPEND, IDEPEND, REQUIRED_USE -- all handled natively in the rules
layer.

**Profile and user configuration.**
Reads the full Gentoo configuration stack: `make.conf`, profiles, `package.use`,
`package.mask`, `package.unmask`, `package.accept_keywords`, `package.license`.
Profile data is cached for fast reload.

**VDB integration.**
Installed packages are modelled as a `pkg` repository.  The prover reasons
about installed state alongside the Portage tree -- upgrades, downgrades, and
`nomerge` decisions are part of the same proof.

**Sets and world.**
Standard Gentoo package sets (`@world`, `@system`, `@selected`) work as
resolution targets.

**Dependency cleanup.**
`--depclean` identifies orphaned packages through the same proof-based
reasoning -- no separate graph walk.

## Execution and building

**Portage-compatible execution.**
Actual package building delegates to Portage's own `ebuild` infrastructure
through a documented invocation contract (phases, `USE`, exit codes, merge
serialization — see Handbook Chapter 16).  The full ecosystem of ebuilds,
eclasses, and phase functions works unchanged; a future in-house ebuild
layer can replace the backend by satisfying the same interface.

**Live build display.**
During builds, a live terminal display shows slot states, phase progress,
colours, and log file locations.  The display refreshes in place.

**Parallel downloads.**
curl-based fetching with GLEP 75 mirror support, Manifest hash verification,
and `mirror://` resolution.

**Self-healing builds.**
Failed phases pass through a signature-keyed retry chain: transient
environment races (bash PID reuse, parallel-make scheduling) are retried
automatically, and packaging exceptions are repaired in-transaction by a
pluggable fixup registry (`Source/Domain/Gentoo/Exceptions/`).  Every recovery
is logged and reported in the build summary -- never silent.

**Native ABI rebuild and haskell-updater.**
Sub-slot (`:=`) ABI changes trigger same-version rebuilds of installed reverse
dependencies as part of the plan (`config:subslot_rebuild/1`).  The
`@preserved-rebuild` computed set separately targets consumers of libraries
kept only by FEATURES=preserve-libs (Portage `PreservedLibraryConsumerSet`).
GHC ABI-hash and OCaml/findlib breakage -- invisible to sub-slots -- are
detected from their compiler failure signatures and repaired mid-build by
rebuilding the broken packages before retrying the failed phase, where
traditional emerge fails and defers to a manual haskell-updater run (or, for
OCaml, to the user).

**Computed package sets.**
VDB/tree-derived sets mirror Portage `sets.conf` classes — including
`@security` (GLSA), `@preserved-rebuild`, `@changed-deps`, `@installed`,
`@live-rebuild`, `@changed-subslot`, and related names — via `sets:expand/2`.

**Collision deconfliction.**
Merge-time file collisions caused by missing blocker atoms are recognised and
resolved (configurable: off / report / override), letting tinderbox-style runs
proceed where emerge would refuse at the plan stage.

**Missing-provider feedback (derive, never patch).**
When a build dies because a required provider is missing -- a command, header,
library, or pkg-config module the ebuild never declared (e.g.
`semodule_package: command not found`, an undeclared `BDEPEND` on
`sys-apps/semodule-utils`) -- portage-ng does not inject a fix into the
in-flight plan.  It diagnoses the missing provider (a detector registry over
the failed phase's log), resolves it to a concrete package (the VDB
reverse-owner index, then a curated seed table), records it as durable learned
knowledge, and re-derives a fresh provable plan in which the provider is proved
and ordered *before* the target.  The plan stays `= prove_plan(Goals, KB)`;
everything already built satisfies from the VDB, so the retry pass only builds
the newly discovered provider and its target.  Each discovery doubles as an
upstream ebuild/eclass bug report.

**USE-enable feedback (derive, never patch).**
When a build dies because a provider was merged with the wrong USE set (e.g.
`KX11Extras: No such file` after `kwindowsystem` built `-X`), re-adding a bare
`cat/name` BDEPEND is a no-op.  `useenable` learns a HARD `[flag]` usedep,
records `discovered_usedep`, and re-derives so BWU forcing rebuilds the
provider with the flag (portage-ng#110).  No imperative `package.use` write
from the hook.

**Snapshots.**
Before upgrading, `--snapshot` creates quickpkg-style binary archives of
installed packages, enabling `--rollback` to a known-good state if an upgrade
causes problems.

## Search, discovery, and diagnostics

**Semantic search.**
`--search` accepts natural-language queries ("text editor with syntax
highlighting") using vector embeddings via Ollama, accelerated on Apple
Silicon's GPU and Neural Engine.  `--similar` finds related packages from the
embedding index.

**Upstream version check.**
`--upstream` compares installed versions against Repology data, highlighting
outdated packages at a glance.

**Bug search and report drafts.**
`--bugs` and `--search-bugs` query the Gentoo Bugzilla REST API.  When the
prover detects unsatisfiable dependencies, it generates structured bug report
drafts with affected packages, constraints, and suggested fixes.  The
missing-provider feedback loop adds a second source of drafts: every undeclared
build dependency discovered at build time is proposed as an
"add `BDEPEND=<provider>`" report against the ebuild or its inherited eclass.

**Interactive Prolog shell.**
`--shell` drops into a live SWI-Prolog session with the full knowledge base
loaded -- useful for ad-hoc queries, debugging, and exploration.

**Graph generation.**
`--graph` produces interactive SVG dependency graphs and Gantt charts via
Graphviz, with detail, dependency-type, and merge/fetch views.

## LLM integration

**Plan explanation.**
`--explain` feeds the completed plan and its assumptions to an LLM for a
human-readable explanation of what will be built and why.

**Interactive chat.**
`--llm` opens a streaming conversation with a language model, with the plan
and knowledge base available as context.

**Multiple providers.**
Ollama, Claude, ChatGPT, Gemini, and Grok are supported as backends.

**Sandboxed code execution.**
LLMs can execute Prolog queries against the knowledge base through a sandboxed
Pengine interface -- safe introspection without arbitrary code execution.

## Distributed proving

**Client / server / worker architecture.**
The server exposes a Pengine-based HTTPS API with job and result queues.
Workers poll for targets, run the full pipeline locally, and post results.
Clients submit targets and render results without needing the full knowledge
base.

**mDNS / Bonjour discovery.**
Servers and workers advertise themselves via `dns-sd`.  Cluster formation is
automatic -- no manual configuration of endpoints.

**Mutual TLS.**
Server, worker, and client authenticate with certificates (CA, server, client).
All traffic is encrypted.

**Daemon and IPC.**
`--background` runs portage-ng as a Unix-socket daemon for lightweight local
IPC without the overhead of TLS.

## Modes

**Standalone.**
Full local pipeline -- the default mode for single-machine use.

**Daemon.**
Persistent background process accepting commands over a Unix socket.

**Client / Server.**
TLS-secured remote proving.  The server holds the knowledge base; clients
submit targets.

**Worker.**
Compute node for distributed proving.  Polls the server, proves locally,
returns results.

**Cluster.**
Orchestration layer that distributes targets across discovered workers and
collects results.

## CLI ergonomics

**Emerge-compatible flags.**
`--pretend`, `--ask`, `--verbose`, `--deep`, `--newuse`, `--emptytree`,
`--fetchonly` (same `:run` proof as `--merge`, then download-only
print/execute), `--buildpkg`, `--usepkg`, and dozens more -- familiar to any
Gentoo user.

**Resolver hints.**
`--favour`, `--avoid`, `--preset`, `--early`, `--late`, `--permit-downgrade`
give fine-grained control over version and ordering preferences.

**CI mode.**
`--ci` maps plan quality to exit codes (0 = clean, 1 = cycle breaks only,
2 = domain assumptions), suitable for automated pipelines.

**Unknown-flag suggestions.**
Mistyped flags get "did you mean?" suggestions.

**Output styles.**
`--style fancy`, `--style column`, `--style short` -- choose the level of
detail. Fancy mode draws Powerline action bubbles; install
[MesloLGS NF](https://www.nerdfonts.com/font-downloads) for Terminal.app
— see [Handbook ch. 14](Handbook/14-doc-output.md#powerline-bubbles-meslolgs-nf).

## Performance and quality

**Measured correctness.**
Correctness is measured against Portage for every ebuild in the tree, using an
identical Portage tree, VDB, and `/etc/portage` configuration.  Detailed
comparison reports track regressions across commits.

**Instrumentation.**
`--profile` enables phase timings, hook counters, timeout traces, and
context-union sampling for performance analysis.

**Test suite.**
PLUnit tests and overlay regression scenarios verify resolver behaviour across
dependency patterns.

## Performance comparison: package managers (pm-bench)

Process wall-clock for cold `--pretend` / resolve-only (not builds), measured
on `vm-linux.local` with `pm-bench` against the same Portage tree, VDB, and
`/etc/portage`.  portage-ng IPC uses a **warm daemon**; timed work is client
connect + prove + print.


| **Tool**    | **Median** | **Total (emerge plan pkgs)** | **Median speedup** |
| ----------- | ---------: | ---------------------------: | -----------------: |
| emerge      |  1,234 ms  |                   6.09 hours |              1.0×  |
| cave        |    520 ms  |                   6.22 hours |              2.4×  |
| pmerge      |    245 ms  |                   1.28 hours |              5.0×  |
| ng-ipc      |     82 ms  |                 32.4 minutes |          **15.1×** |
| ng-ipc-cpp  |     55 ms  |                 25.0 minutes |          **22.4×** |


Subset: **16,313** packages where `emerge -vp` exited 0.  `ng-ipc` is the
ultralight SWI `ipclient.pl`; `ng-ipc-cpp` is the native Unix-socket client.
Full tables and methodology: [Handbook ch. 27](Handbook/27-doc-performance.md).

### Why portage-ng is faster

| **Factor**         | **Traditional PMs**                                | **portage-ng (daemon + IPC)**                            |
| ------------------ | -------------------------------------------------- | -------------------------------------------------------- |
| Startup cost       | Interpreter + imports + metadata each invoke       | KB loaded once; thin client (~3–30 ms)                   |
| Graph construction | Build full graph, then check for conflicts         | Single-pass proof -- no separate graph phase             |
| Conflict recovery  | Discard / restart large parts of the search        | Retry the affected subtree with learned constraints      |
| Repeated queries   | Each pretend starts cold                           | In-memory facts persist across IPC requests              |
| Parallelism        | Sequential graph walk                              | Ordering pass identifies parallel waves                  |


The largest interactive factor is the **resident daemon** plus **qcompiled
cache**; the second is **single-pass proving** (no retries for over 99% of
packages).

## Architecture

**Domain-agnostic core.**
The prover and the planning laws operate on abstract literals and rules.
All Gentoo-specific logic lives in pluggable rules and ordering bindings
behind a `rule/2` hook.  The same engine could reason about any domain that
encodes its constraints as rules.

**Contextual logic programming.**
A runtime object system for Prolog with contexts, classes, instances,
inheritance, and access control -- used internally and available as a
general-purpose programming paradigm.

**Five-stage pipeline.**
Reader → Prover → Orderer → Printer → Builder.  Each stage is
independently testable and replaceable.