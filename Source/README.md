# Source

Prolog source code for portage-ng, organized by architectural concern.

## Root files

| File | Description |
|------|-------------|
| `config.pl` | Paths, hostname, ports, graph directory, TTY size |
| `loader.pl` | Per-mode module loading (standalone, client, server, worker, LLM) |

## Directory structure

```
Source/
  config.pl, loader.pl                (foundational)

  Application/                         (application layer)
    interface.pl                       CLI core: option parsing, TTY init, request dispatching
    llm.pl                             LLM dispatch and provider selection
    Interface/                         Action handlers (15 CLI actions) and target resolution
    Mode/                              Operating modes: client, server, worker, daemon, cluster, stubs
    Security/                          Input sanitization and Pengine sandboxing
    System/                            OS abstraction, process spawning, mDNS, linkage, scripts
    Output/                            Message formatting, file writing, HTML graphing, reports
    Llm/                               LLM backends: Claude, ChatGPT, Gemini, Grok, Ollama,
                                         explain, semantic search
    Performance/                       Instrumentation and diagnostics (sampler)

  Pipeline/                            (reasoning pipeline — domain-agnostic)
    reader.pl, parser.pl               Ingestion: read md5-cache, parse via EAPI grammar
    prover.pl + Prover/                Inductive proof search with constraint learning
    planner.pl + Planner/              Wave planning (Kahn's algorithm) for acyclic graphs
    scheduler.pl                       SCC decomposition (Kosaraju) for cyclic remainders
    printer.pl + Printer/              Plan rendering: assumptions, warnings, suggestions
    builder.pl + Builder/              Build execution, downloads, jobserver, snapshots
    pipeline.pl                        Orchestration: prove → plan → schedule with fallback

  Logic/                               (reasoning framework)
    context.pl                         Declarative OOP: classes, instances, inheritance
    unify.pl                           Feature-term unification (context merging)
    constraint.pl                      Constraint store operations

  Domain/Gentoo/                       (Gentoo domain model)
    eapi.pl                            DCG grammar for PMS 9 / EAPI 9
    rules.pl + Rules/                  Domain rules: candidates, USE, dependencies, heuristics
    version.pl                         Version domain model (Zeller-style feature logic)
    profile.pl, preference.pl          Profile reading, USE/KEYWORDS/mask resolution
    vdb.pl                             Installed-package repository (VDB)
    set.pl                             Package sets (world file)
    ebuild.pl + Ebuild/                Ebuild helpers and execution
    depclean.pl                        Proof-based package removal
    mirror.pl, distfiles.pl            Distfile mirrors and download tracking
    variant.pl                         Build plan variants
    issue.pl, bugs.pl, upstream.pl     Tree issues, Bugzilla, upstream version checks

  Knowledge/                           (data layer)
    cache.pl                           Dynamic fact store (cache:entry/5, metadata, manifests)
    repository.pl                      Portage tree sync, load, save operations
    knowledgebase.pl                   Repository registration and serialization
    query.pl                           Goal-expanded queries with compile-time optimization
    stat.pl                            Progress tracking, timing, statistics
    Sets/                              Package set data files (world, system)

  Config/                              (per-host configuration)
    gentoo.pl                          Reads /etc/portage files (make.conf, package.use, etc.)
    Gentoo/                            Template files mirroring /etc/portage layout
    <hostname>.pl                      Machine-specific repository paths and settings
    Private/                           API keys and passwords (gitignored)

  Test/                                (testing)
    unittest.pl                        207 PLUnit tests
    test.pl                            Integration test cases and expectations
    tester.pl                          Test runner and trace utilities
```
