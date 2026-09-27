# Position in the Solver Literature

Chapter 23 compares portage-ng with Portage, pkgcore and Paludis, and
ends with a short list of the papers those mechanisms cite.  This
chapter is the longer version of that list.  It says which results
the prover actually uses, which neighbouring techniques it leaves
alone, and which problems in that literature are still open.

The work falls into two groups.  One grounds a logic program and then
searches the propositional theory.  The other narrows feature domains
and propagates before it branches.  The package managers in
production took the conflict-learning half of the first group and
specialised it to versions.  portage-ng took the goal-directed half,
kept the learned constraint, and stores that constraint as a version
domain.

A proof that starts from the target only builds the part of the theory
that the target can reach.  Packages outside the proof are not in the plan,
so grounding them first would add work and no candidates.


## Grounding and goal-directed proof

In 2005 the practical answer-set systems were smodels (Niemelä,
Simons, Syrjänen) and DLV (Leone and others).  Both compute stable
models of a program that a grounder — `lparse`, or DLV's own
instantiator — has already flattened.  smodels was fast because of
lookahead: at each node it trial-assigns the remaining literals, runs
the well-founded closure `expand`, and branches on the literal that
forces the most.  Patrik Simons' thesis, *Extending and Implementing
the Stable Model Semantics* (2000), describes the algorithm.  That
speed was real, and hard to recover from the propagation rules alone.
An ordered-logic solver from the same year, OLPS (Van Nieuwenborgh,
Heymans and Vermeir, PADL 2005), implements a 9-valued status lattice
and loses to smodels as soon as the constraint graph gets dense.

Flattening a Portage tree up front does not fit that design.  Every
version, every USE flag and every arm of every `||` would be
propositional before the first branch, including packages the target
will never touch.  The alternative is
[`Source/Logic/context.pl`](../Source/Logic/context.pl): a rule is
evaluated in the OO context where it is defined, so the global Prolog
namespace is never the Herbrand base.  See
[Chapter 21](21-doc-contextual-logic-programming.md).  The prover
tightens this further by proving outward from the target.  An ebuild
the goal never reaches costs nothing.

Answer-set systems are still working on instantiating less of an
arbitrary program.  clingo and DLV2 remain ground-then-solve.  Lazy
grounding, body-decoupled grounding, compilation of a rule into a
propagator, and papers such as FastFound and Diminution (2025) all
try to instantiate less of an arbitrary program.  Here the query is
the target, and the rules that can constrain a selection live on the
packages that selection names.  That only works because a Gentoo
dependency is an atom.  The same procedure does not ground an
arbitrary disjunctive program.


## Feature logic and ordered logic

Two older results are used as mechanisms.

**Zeller and Snelting** (*Handling Version Sets through Feature
Logic*, ESEC 1995; *Unified Versioning through Feature Logic*, TOSEM
1997) identify a version set with a feature term and configure it by
narrowing until one version remains.  `version_domain(Slots, Bounds)`
and `domain_meet` are that narrowing.  A learned `cn_domain` is their
feature implication, carried from one proof attempt to the next.  See
[Chapter 10](10-doc-version-domains.md).

**Van Nieuwenborgh and Vermeir** (*Preferred Answer Sets for Ordered
Logic Programs*, JELIA 2002; TPLP 2006) let a partial order decide
which rule yields when rules conflict.  Candidate order in
`cache:ordered_entry/5` is the single-order case: newer versions are
tried first.  The closer paper for the rest of the resolver is *On
Programs with Linearly Ordered Multiple Preferences* (Van
Nieuwenborgh, Heymans and Vermeir, ICLP 2004).  A stack of preference
relations keeps a solution that is best at level 1, then best at
level 2 among those, and a violation at a lower level is never traded
against a higher one.  `ranking:choice_criteria/1` is that stack,
compared lexicographically.  The five-tier fallback — strict, keyword
acceptance, blockers, unmask, keyword-and-unmask — works the same
way, and so does the split between hard `requires/2` and soft
`prefers/2`.

A few neighbouring papers describe machinery that is already in the
prover.  One of them lines up with an actual Gentoo rule:

| Result | What it describes | Where the prover does it |
| :--- | :--- | :--- |
| *Order and Negation as Failure* (ICLP 2003) | Order plus negation-as-failure adds nothing a preference order cannot already say | `naf_cycle` and the `currently_proving` guard.  A failed `not` on a cycle is an assumption, not a new kind of rule |
| *Ordered Diagnosis* and *Ordered Programs as Abductive Systems* (2003) | A preferred model is the set of rules you are willing to defeat so the rest stays consistent | Domain assumptions.  Positive ones are the defeats that repair the plan; negative ones have no such repair.  See [Chapter 9](09-doc-prover-assumptions.md) |
| *A Logic for Modeling Decision Making with Dynamic Preferences* (De Vos and Vermeir, JELIA 2000) | Earlier decisions update the preference order | USE forces (`bwu_force`, `eq_follow`), flushed as one batched reprove |
| *Specificity by Default* (Geerts and Vermeir, ECSQARU 1995) | When two defaults conflict, the more specific one wins, with no extra priority table | Portage's package.use rule: a more specific atom beats a broader one.  `preference:userconfig_use_match/3` is last-wins across matching specs |

Weighted answer sets (LPAR 2004) score violations with a number.
Preferences here are a declared list of criteria, compared in order,
so a new preference is another entry in that list.


## Answer-set solvers

The algorithm that replaced smodels settled around 2012.  Gebser,
Kaufmann and Schaub describe it in *Conflict-Driven Answer Set
Solving: From Theory to Practice*.  **clasp**, the solver inside
**clingo** (Potsdam), is conflict-driven nogood learning: watched
literals, first-UIP nogoods, activity heuristics and restarts, plus
one piece kept from smodels — a source-pointer unfounded-set check
that learns a loop nogood instead of recomputing the greatest
unfounded set.  **DLV2** (Calabria) pairs the I-DLV grounder with the
WASP solver.  It is the other production system, and the stronger of
the two on disjunctive programs.  smodels itself is historical.

What portage-ng uses from that design is the learned constraint.  A
learned `cn_domain` is a nogood whose atoms are versions.  A deferred
USE-force conflict already backjumps: the partial restart prunes the
Triggers closure of the forced providers and keeps the rest of a
finished pass.  On a deep stack that is most of the proof.
A `prover_reprove(cn_domain(...))` thrown in the middle of a pass
still restarts from scratch, because the pass never finished and the
cycle stack holds literals whose bodies are open.  Carrying the
partial restart over to that case is the clasp technique still
missing.  See `config:reprove_partial_restart/1`.

Three techniques from the same solvers were left out.  Each one is a
poor fit for the cost of a node in this search:

- **Lookahead.**  Trial-assigning every open literal is how smodels
  got its speed, and it is what clasp later dropped.  One trial here
  is a `rule/2` expansion plus a dependency-model build.
- **A greatest unfounded set.**  smodels decides `not` that way, over
  the grounded program.  The prover's `not` is the catch-all
  `rule(naf(_), [])` together with `prover:conflicts/2`: `naf(X)`
  holds unless `X` is already proved or already on the stack.  The
  test is order-dependent, and weaker than well-founded negation.  A
  plan can live with that.  It does not need a closed-world false for
  every package it left uninstalled.
- **Every stable model of a disjunction.**  smodels can return both
  models of a choice without a clause that walks the choice.  A `||`
  here yields a solution because a choice-group rule walks the arms
  and the criterion list keeps one.  The other arm would be a second
  plan for a dependency the first arm already satisfied.

OLPS's lattice `T₉` spells the intermediate statuses out: no
information, eventually true, founded true, the two false
counterparts, the two "not" values, settled-unknown, and
contradiction.  A finished proof records three of them.  A literal is in
the model, assumed, or absent.  Contradiction is `fail`, or a reprove
exception, rather than a value stored on the literal.  Adopting the
rest of the lattice would give those statuses names.  It would not
make the search cheaper.  See [Chapter 8](08-doc-prover.md).


## Why unused ebuilds can be skipped

Leaving the rest of the tree uninstantiated is sound for a reason
that does not hold for an arbitrary logic program.  An ebuild that no
selected package mentions cannot satisfy a dependency, and cannot
forbid one.  In Gentoo, satisfaction goes through an atom.

What still has to be considered, even when the target never named it,
is an installed package tied to something the proof did select.  Those
are read from the VDB:

- a `:=` consumer of a library being rebuilt, injected as a proof
  obligation once the provider is proved;
- a `PDEPEND`, injected the same way;
- a blocker atom inside an ebuild already selected, checked against
  what is installed;
- an installed reverse dependency that cannot accept a candidate,
  dropped by
  `candidate:candidate_reverse_deps_compatible_with_parent/2`;
- depclean and `@preserved-rebuild`, which start from the installed
  set and ask what `@world` still claims.

When one of those reverse edges is missing, the symptom is a wrong
plan for a package already in the proof.  That is how the hooks above
were added.  Each of them is an index over the installed system.
Papers on lazy grounding worry that a rule never instantiated might
have rejected the model.  On this tree that rule would have to mention
a selected package, and then one of these scans reaches it.


## Constraint programming

The Glasgow Subgraph Solver (McCreesh, Prosser, Trimble) comes at the
same family of problems from constraint programming.  Variables are
vertices of a small pattern.  Domains are bitsets of vertices in a
large target.  Before any branch, propagators shrink the bitsets,
including a bit-parallel `allDifferent`: five pattern vertices with
only four target vertices between them kill the node with no search.
Restarts are frequent and the nogoods are shallow, because a node is
a handful of bitset operations, and early guesses are the ones a
heuristic gets wrong.  Proof logs from the same group certify
that kind of cut.  Chapter 23 notes why a SAT solver struggles with
the same pattern: a pigeonhole needs an exponential resolution proof.

The prover has the per-package version of that cut.  `domain_meet`
intersects slot sets, and `slots([])` is inconsistent before any
candidate is tried.  There is no count across packages, because slots
are not a shared pool.  `gcc:12` and `gcc:13` belong to
`sys-devel/gcc` alone, the chosen version picks its own slot, and a
`:=` rebuild moves the occupant after the choice.  A collision is
learned as a `cn_domain` and the affected subtree is retried.  Timed
restarts in the Glasgow style would repeat the lookahead problem from
the previous section: a node here is a dependency model, not a bitset
intersection.  Chapter 23 makes the same comparison against
pkgcore's occupancy table.

Fail-first variable ordering is used, frozen into a declaration.
`ranking:tightness_classes/1` proves the tightest constraint first, so
`selected_cn` locks early.  Glasgow recomputes "smallest domain" at
every node.  The criterion list stays put for the whole search, which
is why two runs against the same tree produce the same plan.


## Package solvers

Almost no package manager runs clingo.  The solvers in production are
CDCL specialised to versions:

| Solver | Used by | What it kept from the ASP line |
| :--- | :--- | :--- |
| libsolv | DNF, Zypper | MiniSat-style CDCL over a pool of concrete packages |
| resolvo | rattler, pixi | The same algorithm, lazy about metadata |
| PubGrub | Dart, uv, Poetry, SwiftPM | A learned incompatibility rendered in English.  The authors cite Gebser, Kaminski, Kaufmann and Schaub, *Answer Set Solving in Practice* |
| mccs / CUDF | opam | MaxSAT, so a preference is an objective |
| clingo | Spack | The production package solver that stayed inside ASP |

Spack's concretizer generates an encoding and lets clingo choose
compilers, variants and providers.  That pays off when the question is
the best assignment under many soft preferences, and when the encoding
of one spec is the whole program.  Gentoo's question is the newest
acceptable plan, in Portage's order, including the build order.  A
Gentoo atom is an awkward boolean variable: USE conditionals, slot
operators, `:=` rebuilds and blockers all have to be interpreted, and
the preferred solution comes from the order of search.

PubGrub is the closest of these.  It looks for one solution, newest
version first, and on failure it gives a reason a person can act on.
A learned `cn_domain` is that incompatibility, stored as a domain
instead of as a clause.  The printed split between positive assumptions
(unmask, keyword, license, blocker) and negative ones (missing package,
slot conflict, unsatisfiable USE) comes from the same requirement.
PubGrub stops at a set of packages.  Pass 2 here is a second proof, of
`scheduled` and `available`, so the build order is not a separate graph
walk over a finished set.  See [Chapter 13](13-doc-planning.md).


## Current work

Recent papers have mostly moved on from the CDCL core.  The active
work sits in three places.

**Grounding.**  Lazy grounding, body-decoupled grounding, compiling a
rule into a propagator instead of instantiating it, and multi-shot
grounding that reuses one ground program across queries.  On a package
tree the proof never builds the theory, which is the outcome that work
is aiming at for arbitrary programs.  The method here stays tied to a
dependency atom that names its package.

**Certificates.**  Checking that a set is an answer set is polynomial
for a normal program.  Checking that none exists is not, and
disjunctive programs sit one level higher.  ASP-QRAT (KR 2024)
certifies both the consistent and the inconsistent case by a
translation to quantified boolean formulas.  VeriPB, from the same
line as the Glasgow proof logs, is becoming a shared format for SAT,
pseudo-Boolean solving, constraint programming and subgraph
isomorphism, with a formally verified checker alongside it.  The Proof
AVL records why a plan was derived.  An independent checker still
cannot reject a wrong `domain_meet` or a wrong cycle-break.  That
checker is the piece still missing.  The comparison with Portage in
Chapter 23 does not need it.

**Hybrids.**  Theory propagators, difference constraints, and ASP
modulo SMT keep the stable-model loop and let a foreign theory post
nogoods back into it.  In clingo, preferences became weak constraints
and priority levels.  Ordered logic programs are no longer a research
programme of their own.  The priority levels here are the fallback
tiers and the criterion list, evaluated during the proof rather than
passed to a MaxSAT solver as an objective.


## Summary

The comparison with Portage, pkgcore and Paludis is in
[Chapter 23](23-doc-resolver-comparison.md).  Most targets finish in
one pass.  A conflict leaves a narrower domain for the next attempt,
as well as any mask that was recorded.

Against the solvers in this chapter, the useful points are these:

- A goal-directed proof at the scale of a repository never builds the
  ground program.  Every constraint that can change the plan is
  attached to a selected package, or to an installed reverse edge.
- The learned nogood is a version domain.  Narrowing it is how a
  conflict propagates.
- One preferred plan is the result.  Other ways of satisfying the same
  choice are left unexplored, and packages the proof never mentions
  are simply absent.
- The build order is a second run of the same prover, under the
  planning rules.

A few of those mechanisms are local to this codebase, rather than a
direct reading of Zeller or of clasp.  The nogood is a version domain.
When a pass has already finished, a USE-force conflict restarts only
along that pass's trigger closure.  Sub-slot rebuilds, `PDEPEND`, and
soft preferences that would close a cycle are all proved, so nothing
has to be patched onto the plan afterwards.

A few related problems are left to those other solvers.  There is no
grounding procedure for an arbitrary answer-set program.  Negation is
the stack test described under answer-set solvers, which is weaker
than smodels' well-founded check.  A slot collision is learned and
retried; packages do not share a pool of slots the way an
`allDifferent` constraint expects.  The prover returns one plan.  The
Proof AVL is the explanation of that plan, and a separate checker
cannot yet reject a bad `domain_meet` or a bad cycle-break.
