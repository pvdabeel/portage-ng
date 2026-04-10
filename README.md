# ::- portage-ng

A declarative reasoning engine for software configuration, applied to Gentoo Linux.


## Reasoning engine

portage-ng is a declarative reasoning engine for large-scale software
configurations like Gentoo Linux.  Implemented in Prolog, an artificial
intelligence programming language, it produces build plans that are formal
proofs -- recording which rule justified each package and under what
constraints.  When no fully valid plan exists, it makes explicit assumptions and
presents them as actionable suggestions as part of the plan: enabling or
disabling specific USE flags, keywording specific ebuilds, unmasking packages,
and so on.


## Highlights

- Proof-based plans with feature-term unification and constraint learning
- Multiple solutions and variant exploration
- Progressive relaxation with actionable suggestions
- Wave planning with optimal parallelism and SCC scheduling
- Semantic search, LLM integration, distributed proving
- Portage-compatible execution and pre-upgrade snapshots
- Domain-agnostic reasoning core -- Gentoo-specific logic is a pluggable rules layer

See the [handbook](Documentation/Handbook/portage-ng-handbook.pdf) for the full
architecture, internals, and feature reference.


## Quick start

**Prerequisites:** SWI-Prolog >= 9.3, a Gentoo Portage tree (or md5-cache snapshot).

```bash
# Build and install
make build && make install

# Pretend (dry-run) a build plan
portage-ng --mode standalone --pretend app-editors/neovim

# Interactive Prolog shell
portage-ng --mode standalone --shell

# Sync the Portage tree
portage-ng --mode standalone --sync
```

For the full command reference, see the
[`portage-ng(1)` manpage](Documentation/Manpage/portage-ng.1.md).


## Screenshots

![Build plan](Documentation/Images/proof.png)
![Merge plan](Documentation/Images/plan.png)
![Gantt chart](Documentation/Images/gantt.png)
![Dependency graph](Documentation/Images/depgraph.png)
![Detail view](Documentation/Images/detail.png)
![Package search](Documentation/Images/search.png)
![Bug search](Documentation/Images/bugs.png)
![Upstream version check](Documentation/Images/upstream.png)


## Handbook

The portage-ng handbook is available as a
[PDF](Documentation/Handbook/portage-ng-handbook.pdf) and as
[individual Markdown chapters](Documentation/Handbook/index.md):

- **Part I** -- Getting Started (introduction, installation, configuration)
- **Part II** -- Architecture and Internals (pipeline, prover, assumptions, version domains, rules, planning, output)
- **Part III** -- Features (CLI, building, LLM integration, distributed proving, upstream bugs)
- **Part IV** -- Foundations (contextual logic programming, context terms, resolver comparison, dependency ordering)
- **Part V** -- Development (testing, performance, contributing)


## License

BSD 2-Clause.  See [`LICENSE`](LICENSE).
