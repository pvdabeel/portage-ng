# Gentoo Domain Policy Cards

A **read-only** view of Gentoo resolver policy for newcomers.
These cards answer *what must hold*, not *how the search engine walks
candidates*. Procedural detail stays in
[`Source/Domain/Gentoo/Rules/Resolving/`](../../../Source/Domain/Gentoo/Rules/Resolving/)
and the narrative walkthrough in
[Chapter 12](../12-doc-resolution.md).

Each card uses the same skeleton:

| Field | Meaning |
| :--- | :--- |
| **Concern** | One Gentoo / PMS question |
| **PMS / Portage** | Informal package-manager meaning |
| **Literals** | `rule/2` heads and related proof literals |
| **Owns** | Module(s) that implement the policy |
| **Invariants** | Short declarative bullets (not control flow) |
| **Examples** | Overlay specimens from the [example index](examples.md) |

Keep cards in sync with overlay tests (`make test-overlay`) and the
[one-page map](map.md). Prefer updating a card when you change
visibility, ranking, USE, or assumption polarity — not only when docs
feel stale.


## Cards

| Card | Concern |
| :--- | :--- |
| [Visibility](visibility.md) | When is an ebuild admissible? |
| [Target resolution](target.md) | How does a CLI atom become a candidate? |
| [Install obligations](install.md) | What does `:install` require? |
| [Run and PDEPEND](run.md) | What does `:run` require? |
| [Dependency atoms](dependency.md) | Version / slot atoms → one selected CN |
| [Choice groups](choice.md) | `\|\|`, `^^`, `??` selection |
| [USE](use.md) | Conditionals, bracketed USE deps, merge |
| [REQUIRED_USE](requireduse.md) | Hard USE constraints on a package |
| [Slots](slot.md) | Slot / sub-slot operators and conflicts |
| [Blockers](blocker.md) | Soft `!` and hard `!!` |
| [Domain assumptions](assumption.md) | Positive vs negative domain assumptions |
| [Cycle breaks](cycle.md) | Prover cycle-break assumptions (benign) |


## Quick links

- [Example index (curriculum)](examples.md) — learn policy by specimen
- [One-page map](map.md) — `rule/2` head → schema → test → card
- [Full overlay matrix](../../Tests/README.md) — all 80 scenarios
- [Chapter 12: Resolution](../12-doc-resolution.md) — end-to-end resolution story
- [Chapter 9: Assumptions](../09-doc-prover-assumptions.md) — fallback / learning
- [Chapter 26: Testing](../26-doc-testing.md) — how to run the suite
