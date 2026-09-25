# Position in the Solver Literature

portage-ng sits between two research programmes that split around 2005
and have not rejoined.  One programme grounds a logic program and
searches the propositional theory.  The other narrows feature domains
and propagates before it branches.  Package managers took the
conflict-learning half of the first programme and specialised it to
versions.  portage-ng took the goal-directed half, kept the learned
constraint, and stores that constraint as a version domain.

The result is not a new logic.  It is a demonstration that, for a
Gentoo tree, a proof from the target replaces the ground program, and
that the models nothing in the target refers to were never the ones
the plan needed.  This chapter says what was taken from each line,
what was refused, and which open academic problem is actually left.


## The fork

In 2005 the practical answer-set systems were smodels (Niemelä,
Simons, Syrjänen) and DLV (Leone and others).  Both compute stable
models of a program that a grounder — `lparse`, or DLV's own
instantiator — has already flattened.  smodels was fast because of
lookahead: at each node it trial-assigns the remaining literals, runs
the well-founded closure `expand`, and branches on the literal that
forces the most.  Patrik Simons' thesis, *Extending and Implementing
the Stable Model Semantics* (2000), describes the algorithm.  The
speed was real and hard to reproduce from the propagation rules
alone.  An ordered-logic solver of that year, OLPS (Van
Nieuwenborgh, Heymans and Vermeir, PADL 2005), implements a 9-valued
status lattice and loses to smodels as soon as the constraint graph
gets dense.

Grounding the Portage tree does not survive that design.  Every
version, every USE flag and every arm of every `||` would be
propositional before the first branch, including packages the target
will never touch.  [`Source/Logic/context.pl`](../Source/Logic/context.pl)
is the cut made instead: a rule is evaluated in the OO context where
it is defined, so the global Prolog namespace is never the Herbrand
base.  See [Chapter 21](21-doc-contextual-logic-programming.md).  The
prover then makes the cut stricter.  It proves outward from the
target.  An ebuild the goal never reaches costs nothing.

That is the same move the ASP literature is still publishing as an
open problem.  clingo and DLV2 remain ground-then-solve.  Lazy
grounding, body-decoupled grounding, hybrid compilation into
propagators, and 2025 papers such as FastFound and Diminution all try
to instantiate less of an arbitrary program.  portage-ng does not
instantiate the program.  The query is the target, and the rules that
can constrain a selection live on the packages that selection names.


## Feature logic and ordered logic

Two older results are used as mechanisms, not as slogans.

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
compared lexicographically.  So is the five-tier fallback — strict,
keyword acceptance, blockers, unmask, keyword-and-unmask — and the
separation of hard `requires/2` from soft `prefers/2`.

A few neighbouring results describe machinery that is already in the
prover, and one of them points at a real Gentoo rule:

| Result | What it describes | Where the prover does it |
| :--- | :--- | :--- |
| *Order and Negation as Failure* (ICLP 2003) | Order plus negation-as-failure adds nothing a preference order cannot already say | `naf_cycle` and the `currently_proving` guard.  A failed `not` on a cycle is an assumption, not a new kind of rule |
| *Ordered Diagnosis* and *Ordered Programs as Abductive Systems* (2003) | A preferred model is the set of rules you are willing to defeat so the rest stays consistent | Domain assumptions.  Positive ones are the defeats that repair the plan; negative ones have no such repair.  See [Chapter 9](09-doc-prover-assumptions.md) |
| *A Logic for Modeling Decision Making with Dynamic Preferences* (De Vos and Vermeir, JELIA 2000) | Earlier decisions update the preference order | USE forces (`bwu_force`, `eq_follow`), flushed as one batched reprove |
| *Specificity by Default* (Geerts and Vermeir, ECSQARU 1995) | When two defaults conflict, the more specific one wins with no extra priority table | Portage's package.use rule: a more specific atom beats a broader one.  `preference:userconfig_use_match/3` is last-wins across matching specs |

Weighted answer sets (LPAR 2004) score violations numerically.  That
design was refused.  Preferences in portage-ng are a declared
criterion list.


## Answer-set solvers

The algorithm that replaced smodels froze around 2012 and is written
up by Gebser, Kaufmann and Schaub in *Conflict-Driven Answer Set
Solving: From Theory to Practice*.  **clasp**, inside **clingo**
(Potsdam), is conflict-driven nogood learning: watched literals,
first-UIP nogoods, activity heuristics, restarts, plus one piece kept
from smodels, a source-pointer unfounded-set check that learns a loop
nogood instead of recomputing the greatest unfounded set.  **DLV2**
(Calabria) is the I-DLV grounder plus the WASP solver, the other
production system, strongest on disjunctive programs.  smodels itself
is historical.

portage-ng took the learning and left the search.

A learned `cn_domain` is a nogood whose atoms are versions.  A
deferred USE-force conflict already backjumps: the partial restart
prunes the Triggers closure of the forced providers and keeps the
rest of a finished pass.  On a deep stack that is most of the proof.
A `prover_reprove(cn_domain(...))` thrown in the middle of a pass
still restarts from scratch, because the pass never finished and the
cycle stack holds literals whose bodies are open.  Extending the
partial restart to that throw is the clasp move that is not taken
yet.  See `config:reprove_partial_restart/1`.

What was refused, and why:

- **Lookahead.**  Trial-assigning every open literal is how smodels
  was fast, and it is what clasp dropped.  One trial here is a
  `rule/2` expansion and a dependency-model build.
- **A greatest unfounded set.**  smodels decides `not` that way, over
  the grounded program.  The prover's `not` is the catch-all
  `rule(naf(_), [])` together with `prover:conflicts/2`: `naf(X)`
  holds unless `X` is already proved or already on the stack.  That
  is order-dependent, and weaker than well-founded negation.  It is
  enough, because the plan does not need a closed-world false for
  every package it did not install.
- **Every stable model of a disjunction.**  smodels returns both
  models of a choice without a clause that walks the choice.  A `||`
  in portage-ng produces a solution only because a choice-group rule
  walks the arms and the criterion list keeps one.  The other arm is
  a second plan of a dependency the first arm already satisfied.

OLPS's lattice `T₉` makes those statuses explicit: no information,
eventually true, founded true, the two false counterparts, the two
"not" values, settled-unknown, and contradiction.  A finished
portage-ng proof keeps three of them.  In the model, assumed, or
absent.  Contradiction is `fail` or a reprove exception, not a value
stored on the literal.  Adopting the lattice would name the statuses
and would not make the search cheaper.  See [Chapter 8](08-doc-prover.md).


## Packages nothing refers to

Skipping grounding is sound here for a reason that does not hold for
an arbitrary logic program.  An ebuild that no selected package
mentions cannot satisfy a dependency and cannot forbid one.  Gentoo
satisfaction goes through an atom.

The cases that matter without being named by the target are installed
packages coupled to something the proof did select.  They are read
from the VDB, not recovered by instantiating the tree:

- a `:=` consumer of a library being rebuilt, injected as a proof
  obligation after the provider is proved;
- a `PDEPEND`, injected the same way;
- a blocker atom inside an ebuild already selected, checked against
  what is installed;
- an installed reverse dependency that cannot accept a candidate,
  dropped by `candidate:candidate_reverse_deps_compatible_with_parent/2`;
- depclean and `@preserved-rebuild`, which start from the installed
  set and ask what nothing in `@world` still claims.

A missed reverse edge shows up as a wrong plan for a package already
in the proof.  That is how those hooks were added.  Each one is an
index over the installed system.  Lazy-grounding papers worry that a
rule never instantiated might have rejected the model.  Here that
rule would have to mention a selected package, and then one of these
scans reaches it.


## Constraint programming

The Glasgow Subgraph Solver (McCreesh, Prosser, Trimble) is the other
bet.  Variables are vertices of a small pattern.  Domains are bitsets
of vertices in a large target.  Before any branch, propagators shrink
the bitsets, including a bit-parallel `allDifferent`: five pattern
vertices with only four target vertices between them kill the node
with no search.  Restarts are frequent and the nogoods are shallow,
because a node is a handful of bitset operations and early guesses are
the ones a heuristic gets wrong.  The same group's proof-logging work
certifies that kind of cut.  Chapter 23 records why a SAT solver is
weak at it: a pigeonhole needs an exponential resolution proof.

portage-ng has the unary case.  `domain_meet` intersects slot sets,
and `slots([])` is inconsistent before any candidate is tried.  It
does not count across packages.  Slots are not a shared pool.
`gcc:12` and `gcc:13` belong to `sys-devel/gcc` alone, the chosen
version picks its own hole, and a `:=` rebuild moves the occupant
after the choice.  A collision is learned as a `cn_domain` and
retried.  Glasgow-style timed restarts would be the lookahead mistake
again: a prover node is a dependency model, not a bitset intersection.

The variable-ordering cousin that *is* used is fail-first, frozen
into a declaration.  `ranking:tightness_classes/1` proves the tightest
constraint first so `selected_cn` locks early.  Glasgow recomputes
"smallest domain" at every node.  The criterion list does not move
with the search, which is what keeps two runs on the same tree on the
same plan.


## Package solvers after clasp

Almost no package manager runs clingo.  The solvers in production are
CDCL specialised to versions:

| Solver | Used by | What it kept from the ASP line |
| :--- | :--- | :--- |
| libsolv | DNF, Zypper | MiniSat-style CDCL over a pool of concrete packages |
| resolvo | rattler, pixi | The same algorithm, lazy about metadata |
| PubGrub | Dart, uv, Poetry, SwiftPM | A learned incompatibility rendered in English.  The authors cite Gebser, Kaminski, Kaufmann and Schaub, *Answer Set Solving in Practice* |
| mccs / CUDF | opam | MaxSAT, so a preference is an objective |
| clingo | Spack | The one production package solver that stayed inside ASP |

Spack is the road not taken.  Its concretizer generates an encoding
and lets clingo optimise compilers, variants and providers.  That
pays when the question is the best assignment under many soft
preferences and the encoding of one spec is the program.  Gentoo's
question is the newest acceptable plan, in Portage's order, including
the build order.  A Gentoo atom is a bad boolean variable: USE
conditionals, slot operators, `:=` rebuilds and blockers have to be
interpreted, and the preferred solution is defined by search order
rather than by satisfiability.

PubGrub is the closest cousin.  It wants one solution, newest version
first, and on failure a reason a person can act on.  A learned
`cn_domain` is its incompatibility, stored as a domain.  The printed
split between positive assumptions (unmask, keyword, license,
blocker) and negative ones (missing package, slot conflict,
unsatisfiable USE) is the same product requirement as that error
chain.  PubGrub stops at a set of packages.  Pass 2 of portage-ng is
a second proof, of `scheduled` and `available`, so the build order is
not a graph algorithm run on a finished set.  See
[Chapter 13](13-doc-planning.md).


## What the field is working on

The CDCL core is not the research problem any more.  Three fronts are.

**Grounding.**  Lazy grounding, body-decoupled grounding, compiling a
rule into a propagator instead of instantiating it, and multi-shot
grounding that reuses a ground program across queries.  portage-ng
has the result those papers are approaching, for this problem: the
proof never builds the theory.  It does not transfer to an arbitrary
disjunctive program, and it does not claim to.

**Certificates.**  Checking that a set is an answer set is
polynomial for a normal program.  Checking that none exists is not,
and disjunctive programs sit one level higher.  ASP-QRAT (KR 2024)
certifies both the consistent and the inconsistent case via a
translation to quantified boolean formulas.  VeriPB, from the same
line as the Glasgow proof logs, is becoming the shared format for
SAT, pseudo-Boolean solving, constraint programming and subgraph
isomorphism; a formally verified checker accompanies it.  The Proof
AVL shows why a plan was derived.  An independent checker cannot yet
reject a wrong `domain_meet` or a wrong cycle-break.  That is the
open piece.  The resolver does not need it to be ahead of Portage.

**Hybrids.**  Theory propagators, difference constraints, ASP modulo
SMT.  The stable-model loop stays and a foreign theory posts nogoods
back.  Preferences survived here as clingo's weak constraints and
priority levels.  Ordered logic programs did not survive as a
research programme.  portage-ng's priority levels are the fallback
tiers and the criterion list, evaluated inside the proof rather than
as an objective handed to a MaxSAT solver.


## The claim

Against Portage, pkgcore and Paludis the comparison is empirical and
lives in [Chapter 23](23-doc-resolver-comparison.md).  Most targets
finish in one pass.  A conflict leaves a narrower domain, not only a
mask.

Against the solver literature the claim is narrower, and it is the
one worth making outside Gentoo:

- A goal-directed proof at repository scale avoids the grounding
  bottleneck, because every constraint that can affect the plan is
  attached to a selected package or to an installed reverse edge.
- The learned nogood is a version domain.  Narrowing it is the
  propagation step.
- One preferred plan is the answer.  The other stable models of a
  choice, and the closed-world falsehoods for packages never
  mentioned, are not missing solutions.
- The build order is the same prover under a second rule set.

The techniques inside that claim that are not just a citation of
Zeller or of clasp are the domain-shaped nogood, the partial restart
along the proof's trigger closure, and the refusal to patch the plan
after the proof: sub-slot rebuilds, `PDEPEND`, and soft preferences
that void when they would close a cycle all stay inside the
derivation.


## What this is not

portage-ng does not solve grounding for arbitrary answer-set
programs.  It does not decide negation the way smodels does, and the
gap is accepted.  It does not propagate `allDifferent` across
packages.  It does not enumerate models, and it does not optimise a
numeric objective.  It does not emit a checkable refutation.

Those are the boundaries of the result.  Inside them, the
positioning is that the 2005 choice — prove from the goal, in the
context that is relevant, and learn a domain when the goal was wrong
— is the one the later systems were walking back toward, and that a
Gentoo tree is large enough to show it holds.
