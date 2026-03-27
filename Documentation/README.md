This directory contains documentation for portage-ng.

- `Assets/` — static files copied into graph output directories
  - `.bash_profile` — example shell profile
  - `.index.css` — stylesheet for generated HTML index pages
  - `.proof.css` — stylesheet for proof HTML rendering
  - `.meslo.ttf` — Meslo font for proof rendering
- `Diagrams/` — architecture and flow visualizations
  - `architecture.dot` / `.svg` — module dependency diagram
  - `rules_assumptions_flow.dot` / `.svg` — BPMN-style flow diagram of the rules/prover assumption pipeline
- `Specifications/` — EAPI PMS specification references (see [PMS 9](https://projects.gentoo.org/pms/9/pms.html))
- `Tests/` — test case documentation
- `doc-context-terms.md` — how context terms evolve across dependencies (self, build_with_use, constraints, feature logic)
- `doc-dependency-ordering.md` — dependency ordering and planning documentation
- `doc-explainer.md` — explainer & explanation module usage guide
- `doc-gentoo.md` — Gentoo portage configuration and profile loading
- `doc-resolver-comparison.md` — comparison of Portage, Paludis, and portage-ng resolvers with academic foundations
