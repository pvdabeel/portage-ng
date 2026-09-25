# portage-ng Handbook

A comprehensive guide to portage-ng — a declarative reasoning engine for
software configuration, applied to Gentoo Linux.

## Part I — Getting Started

1. [Introduction](01-doc-introduction.md)
2. [Installation and Quick Start](02-doc-installation.md)
3. [Configuration](03-doc-configuration.md)

## Part II — Architecture and Internals

4. [Architecture Overview](04-doc-architecture.md)
5. [Proof Literals](05-doc-proof-literals.md)
6. [Knowledge Base and Cache](06-doc-knowledgebase.md)
7. [The EAPI Grammar](07-doc-eapi-grammar.md)
8. [The Prover](08-doc-prover.md)
9. [Assumptions and Constraint Learning](09-doc-prover-assumptions.md)
10. [Version Domains](10-doc-version-domains.md)
11. [Rules and Domain Logic](11-doc-rules.md)
12. [Resolution: Configuration as Proofs](12-doc-resolution.md)
    - [Policy cards](Policy/README.md) — what Gentoo policy requires
    - [Policy by example](Policy/examples.md) — overlay curriculum
    - [One-page map](Policy/map.md) — `rule/2` → schema → test → card
13. [Ordering: Plans as Proofs](13-doc-planning.md)
14. [Output and Visualization](14-doc-output.md)

## Part III — Features

15. [Command-Line Interface](15-doc-cli.md)
16. [Building and Execution](16-doc-building.md)
    - [Why not our own `ebuild`?](16-doc-building.md#why-not-our-own-ebuild) — why phase execution stays delegated
    - [The ebuild contract](16-doc-building.md#the-ebuild-contract) — builder ↔ Portage `ebuild` boundary
17. [Semantic Search and LLM Integration](17-doc-llm.md)
18. [Distributed Proving](18-doc-distributed.md)
19. [Upstream and Bug Tracking](19-doc-upstream-bugs.md)
20. [Gentoo Linux Security Advisories (GLSA)](20-doc-glsa.md)

## Part IV — Foundations

21. [Contextual Logic Programming](21-doc-contextual-logic-programming.md)
22. [Context Terms and Feature Unification](22-doc-context-terms.md)
23. [Resolver Comparison](23-doc-resolver-comparison.md)
24. [Dependency Ordering](24-doc-dependency-ordering.md)
29. [Position in the Solver Literature](29-doc-academic-position.md)

## Part V — Development

25. [Testing and Regression](25-doc-testing.md)
26. [Performance and Profiling](26-doc-performance.md)
27. [Contributing](27-doc-contributing.md)

## Closing

28. [Closing Thoughts](28-doc-closing.md)
