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


## Planning and scheduling

**Wave planning.**
The proven dependency graph is scheduled using Kahn's algorithm, exposing
maximal parallelism per wave.  Packages that can build concurrently are grouped
into the same step from the start -- parallelism is a first-class property of
the plan, not an afterthought.

**Action-level scheduling.**
Downloads, installs, runtime checks, and confirmations are independent actions.
Packages can install while others are still downloading.

**SCC scheduling.**
Cyclic remainders from the wave planner are decomposed with Kosaraju's
algorithm.  Strongly Connected Components are scheduled with merge-set
semantics, matching PMS ordering requirements.

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
USE-conditional dependencies, slot operators (`:=`, `:*`), sub-slots, blockers,
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
Actual package building delegates to Portage's own `ebuild` infrastructure.
The full ecosystem of ebuilds, eclasses, and phase functions works unchanged.

**Live build display.**
During builds, a live terminal display shows slot states, phase progress,
colours, and log file locations.  The display refreshes in place.

**Parallel downloads.**
curl-based fetching with GLEP 75 mirror support, Manifest hash verification,
and `mirror://` resolution.

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
drafts with affected packages, constraints, and suggested fixes.

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
`--fetchonly`, `--buildpkg`, `--usepkg`, and dozens more -- familiar to any
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
detail.


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


## Architecture

**Domain-agnostic core.**
The prover, planner, and scheduler operate on abstract literals, rules, and
dependency graphs.  All Gentoo-specific logic lives in a pluggable rules layer
behind a `rule/2` hook.  The same engine could reason about any domain that
encodes its constraints as rules.

**Contextual logic programming.**
A runtime object system for Prolog with contexts, classes, instances,
inheritance, and access control -- used internally and available as a
general-purpose programming paradigm.

**Six-stage pipeline.**
Reader → Prover → Planner → Scheduler → Printer → Builder.  Each stage is
independently testable and replaceable.
