# Closing Thoughts

This book opened with a question that has quietly shaped every
chapter since: as software systems grow more complex, can the tools
that manage them keep up?

portage-ng's answer is to treat package management not as a logistics
problem — downloading and unpacking files — but as a **reasoning
problem**.  Dependencies become proof obligations.  Configuration
choices become constraints.  Conflicts become learning opportunities
that narrow the search space for the next attempt.  The result is a
system that can walk tens of thousands of packages, resolve their
interdependencies, and produce a buildable plan — often in a single
pass.


## What we covered

The book traced this idea from concept to implementation:

- **Part I** set the stage: the growing complexity of source-based
  distributions, the limits of imperative solvers, and how Prolog's
  backtracking and unification provide a natural fit for dependency
  reasoning.

- **Part II** unpacked the architecture: how the knowledge base stores
  and indexes package metadata; how the EAPI grammar parses dependency
  specifications; how the prover searches for consistent models; how
  assumptions, constraint learning, and version domains handle
  conflicts; how rules encode Gentoo's domain logic; and how the
  planner and scheduler turn a proof into a concrete build order.

- **Part III** covered the features built on top of that foundation:
  the command-line interface, build execution, semantic search with
  LLM integration, distributed proving across clusters, and upstream
  bug tracking.

- **Part IV** explored the theoretical underpinnings: contextual logic
  programming, feature unification, and the comparison with other
  resolvers — showing how portage-ng's approach relates to Portage's
  progressive relaxation, Paludis's constraint accumulation, and
  academic work on feature logic and ordered logic programs.

- **Part V** described the practical side of development: testing
  strategies, performance profiling, and contribution guidelines.


## Design principles worth remembering

A few recurring themes run through the design and are worth calling
out explicitly:

- **Declarative over imperative.**  The prover does not maintain mutable
  state that must be carefully unwound on failure.  AVL trees are
  persistent; backtracking is automatic; learned constraints accumulate
  naturally.  This makes the system easier to reason about and extend.

- **Single-pass where possible, learning where not.**  Most packages
  resolve in one pass.  When conflicts arise, the system learns from
  them — narrowing version domains, recording rejects — so the next
  attempt is better informed.  This is fundamentally different from
  starting over with a blank slate on each retry.

- **Separation of concerns.**  The prover knows nothing about Gentoo.
  The rules layer knows nothing about proof search.  The planner knows
  nothing about dependency types.  Each layer has a clean interface,
  and domain-specific knowledge stays in domain-specific modules.

- **Transparency.**  Assumptions are not silent failures — they are
  classified, explained, and reported.  The explainer can trace any
  package's presence in the plan back through the proof to the
  original dependency that required it.  When something goes wrong,
  the system tells you why.


## Looking ahead

portage-ng is a living project.  Several directions remain open for
exploration:

- **Broader platform support.**  The reasoning engine is not tied to
  Gentoo — any system that can express its dependencies as structured
  rules could use the same prover and planner.

- **Richer learning.**  The current constraint learning mechanism
  handles version domains and parent narrowing.  More sophisticated
  strategies — learning across multiple proof runs, or sharing learned
  constraints between cluster workers — could further reduce proving
  time.

- **Tighter LLM integration.**  The explainer already bridges proof
  traces and natural language.  Future work could let users ask
  higher-level questions ("why is my build slow?", "what changed since
  last week?") and receive answers grounded in the formal proof
  structure.

- **Binary package support.**  As Gentoo's binary package
  infrastructure matures, portage-ng could reason about mixed
  source/binary strategies — deciding which packages to build from
  source and which to install from pre-built archives.


## Thank you

If you have read this far, you have a thorough understanding of how
portage-ng works and why it was built this way.  Whether you are using
it to manage a Gentoo system, studying it as an example of applied
logic programming, or contributing to its development — thank you for
your interest, and welcome to the project.
