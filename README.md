# <img src="Documentation/Images/icon.svg" alt="" width="28" height="28" align="absmiddle" style="vertical-align:middle"> portage-ng

portage-ng is a declarative reasoning engine for large scale software configurations, applied to Gentoo Linux. It uses logical reasoning to produce a plan, recording which rule justified each package and under what constraints.

[portage-ng.ai](https://portage-ng.ai)

## Reasoning engine

Assembling thousands of interdependent components with user-specified feature
selections is configuration management, not logistics — it calls for
reasoning, not graph traversal. The result: no graph-traversal errors to
decipher, but actionable plans where others fail.

## Highlights

- Proof-based plans with feature-term unification and constraint learning
- Multiple solutions and variant exploration
- Progressive relaxation with actionable suggestions
- Wave planning with optimal parallelism and SCC scheduling
- Builder-to-prover feedback: undeclared build dependencies discovered at build time are learned
- Semantic search, LLM integration, distributed proving
- Portage-compatible execution and pre-upgrade snapshots
- Domain-agnostic reasoning core -- Gentoo-specific logic is a pluggable rules layer

See the full [feature list](Documentation/FEATURES.md) and the
[handbook](Documentation/Handbook/portage-ng-handbook.pdf) for architecture,
internals, and reference documentation.

## Quick start

**Prerequisites:** SWI-Prolog >= 10.0.0, a Gentoo Portage tree.

```bash
# Build and install
make build && make install

# Sync the Portage tree (builds Knowledge/kb.qlf — not shipped)
portage-ng --mode standalone --sync

# Pretend (dry-run) a build plan
portage-ng --mode standalone --pretend app-editors/neovim

# Interactive Prolog shell
portage-ng --mode standalone --shell
```

For the full command reference, see the
[`portage-ng(1)` manpage](Documentation/Manpage/portage-ng.1.md).

## Handbook

The portage-ng handbook is available as a
[PDF](Documentation/Handbook/portage-ng-handbook.pdf) and as
[individual Markdown chapters](Documentation/Handbook/index.md):

- **Part I** -- Getting Started (introduction, installation, configuration)
- **Part II** -- Architecture and Internals (pipeline, prover, assumptions, version domains, rules, planning, output)
- **Part III** -- Features (CLI, building, LLM integration, distributed proving, upstream bugs)
- **Part IV** -- Foundations (contextual logic programming, context terms, dependency ordering)
- **Part V** -- Development (testing, performance, contributing)