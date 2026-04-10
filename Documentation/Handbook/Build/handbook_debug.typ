#let horizontalrule = line(start: (25%,0%), end: (75%,0%))

#show terms.item: it => block(breakable: false)[
  #text(weight: "bold")[#it.term]
  #block(inset: (left: 1.5em, top: -0.4em))[#it.description]
]

#set table(
  inset: 6pt,
  stroke: none
)

#show figure.where(
  kind: table
): set figure.caption(position: top)

#show figure.where(
  kind: image
): set figure.caption(position: bottom)

#import "template.typst": conf

#show: doc => conf(
  title: [portage-ng],
  subtitle: [A declarative reasoning engine for large scale software
configuration management],
  authors: (
    ( name: [Pieter Van den Abeele],
      affiliation: [],
      email: [pvdabeel\@mac.com] ),
    ),
  date: [April 2026],
  abstract-title: [Abstract],
  paper: "a4",
  sectionnumbering: "1.1.1",
  pagenumbering: "1",
  cols: 1,
  doc,
)


= The Prover
<the-prover>
== Domain independence
<domain-independence>
The central design insight is easy to miss because portage-ng is
#emph[about] Gentoo packages: #strong[the prover does not know what a
"package" is.] It works only with abstract literals and rules (Logic).
That is deliberate. It means the reasoning core can be exercised and
tested without importing the whole Portage domain, and the same engine
could --- in principle --- prove goals in any domain that encodes its
constraints as Horn-style expansions behind a single hook.

The prover's only contract with the outside world is this: #strong[given
a literal, `rules:rule/2` (or the configured `rule/2` delegate) returns
a body --- a list of sub-literals that must hold for the head to hold.]
Everything that makes Gentoo "Gentoo" --- USE flags, slots, version
domains, PDEPEND side effects --- lives in the rule layer and in
proof-term annotations (`?{Context}`), not in the prover's control flow.
The prover walks literals; the domain explains what each literal means.

That separation is what keeps the implementation in
`Source/Pipeline/prover.pl` readable: backward chaining, cycle handling,
context merging, and bookkeeping --- not emerge policy.

The prover is the core reasoning engine of portage-ng. Given a list of
target literals, it constructs a formal proof that all dependencies can
be satisfied --- or completes with explicit assumptions documenting
exactly where the dependency specification is unsatisfiable.

== Why AVL trees?
<why-avl-trees>
The prover maintains its main state in #strong[four AVL trees] from
`library(assoc)` (Proof, Model, Constraints, and Triggers --- see the
module header in `prover.pl`). Plain hash tables would win on raw point
lookups, but assoc trees buy a property that matters more here: they are
#strong[persistent] (functional). Each `put_assoc/4` produces a
#emph[new] tree and leaves the previous one intact.

In Prolog, that lines up with #strong[backtracking]. When the prover
must undo a choice, variable bindings revert and the "old" assoc values
bound in earlier choice points are still the right snapshots. A mutable
hash map would need an explicit save/restore discipline on every failure
--- the sort of manual undo-stack work traditional Portage does in
places, with corresponding risk of subtle inconsistency. Here, the data
structures and Prolog's search rule stay aligned.

Complexity is #strong[O(log n)] per update and lookup. For on the order
of tens of thousands of literals, that is a small constant number of
comparisons (roughly fifteen for 32,000 entries) --- more than fast
enough compared with the cost of calling into domain rules and
unification.

== Inductive proof search
<inductive-proof-search>
The prover performs inductive proof search via backward chaining. For
each literal in the proof queue:

+ #strong[Check the model.] If the literal is already proven (present in
  the Model AVL), merge contexts via feature term unification and
  continue.

+ #strong[Check the cycle stack.] If the literal is currently being
  proved (on the stack), handle the cycle:

  - If `heuristic:cycle_benign/1` succeeds, treat it as already proven
    (benign cycle --- no assumption recorded).
  - Otherwise, record a cycle-break assumption (`assumed(rule(Lit))` in
    Proof, `assumed(Lit)` in Model).

+ #strong[Expand via `rule/2`.] Call `rules:rule(Lit, Body)` to get the
  rule body --- the list of sub-literals that must be proven to justify
  `Lit`.

+ #strong[Record in Proof.] Store `rule(Lit) → dep(N, Body)?Ctx` in the
  Proof AVL, where `N` is the dependency count.

+ #strong[Record in Model.] Store `Lit → Ctx` in the Model AVL.

+ #strong[Update Triggers.] For each body literal, add `Lit` to its
  trigger list in the Triggers AVL.

+ #strong[Recurse.] Add the body literals to the proof queue and
  continue.

Steps 1 and 6 are where #strong[prescient proving] and the
#strong[reverse-dependency index] connect; the sections below unpack
those ideas.

== Proof term structure
<proof-term-structure>
The Proof AVL maps rule keys to structured values:

```prolog
rule(Lit) → dep(DepCount, Body)?Ctx
```

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Field]], [#strong[Meaning]],),
    table.hline(),
    [`rule(Lit)`], [The literal that was proven],
    [`DepCount`], [Number of dependencies (body length)],
    [`Body`], [List of body literals],
    [`Ctx`], [Context under which the literal was proven],
  )]
  , kind: table
  )

The dependency count is stored alongside the body because it is used by
downstream stages without having to recompute it. The planner uses it to
determine the #strong[fan-out] of each node when building topological
waves: a literal with many dependencies is heavier to schedule than one
with few. The printer uses it to produce indentation and step counts in
the plan output. Storing the count once, at proof time, avoids repeated
`length/2` calls over the same body list during planning and printing.

Special keys: - `assumed(rule(Lit))` with `dep(-1, Body)?Ctx` --- prover
cycle-break - `rule(assumed(Lit))` with `dep(0, [])?Ctx` --- domain
assumption

=== Concrete Proof AVL entry (Gentoo-shaped)
<concrete-proof-avl-entry-gentoo-shaped>
The literal itself is still just a term the prover passes through; the
`portage://` prefix and atom naming are domain choices. A representative
Proof entry after expanding an install goal might look like this (body
shortened):

```prolog
rule(portage://'sys-apps/portage-3.0.77-r3':install)
  → dep(5,
        [ portage://'dev-lang/python-3.12.3':install,
          portage://'sys-libs/glibc-2.40-r5':install,
          … ])?{[ self(portage://'sys-apps/portage-3.0.77-r3'),
                … ]}
```

So the Proof AVL answers: #strong[which rule instance was used],
#strong[how many dependencies] it had, #strong[what the body literals
are], and #strong[under which `?{Context}` list] that expansion was
valid. The exact features inside `?{…}` are documented in
#link("05-doc-proof-literals.md")[Chapter 5: Proof Literals]\; the
prover treats them as data merged by feature term unification, not as
special cases.

== Model construction
<model-construction>
#figure(image("Diagrams/08-model-construction.svg", alt: "Model construction flow"),
  caption: [
    Model construction flow
  ]
)

The Model AVL records every proven literal with its context. It serves
two purposes:

+ #strong[Memoization.] When a literal is encountered again, the prover
  checks the model first. If found, it merges the new context with the
  existing one via feature term unification rather than re-proving the
  literal (when the incoming context is not already equivalent to the
  stored one --- see below).

+ #strong[Plan generation.] The planner reads the model to determine
  which literals are in the proof and what contexts they carry.

A lightweight variant, `prove_model`, skips Proof and Triggers
bookkeeping for internal query-side model construction where only the
model is needed.

=== Concrete Model AVL entry
<concrete-model-avl-entry>
Model entries are simpler: #strong[literal → context] under which it was
last committed to the proof.

```prolog
portage://'dev-libs/openssl-3.3.2':install
  → [ build_with_use:use_state([ssl], []),
      … ]
```

Multiple features can accumulate in that list as different dependency
paths impose different requirements; the merge semantics are defined by
the domain's feature term unification (`sampler:ctx_union/3`).

=== Re-encountering a literal: feature term unification
<re-encountering-a-literal-feature-term-unification>
When the queue delivers the same `Lit` again with a #strong[new]
`?{Context}`:

+ The prover finds `Lit` in the Model AVL (with stored context
  `OldCtx`).
+ If the new context is semantically the same as the stored one
  (`prover:proven/3`), nothing more is done --- no second expansion.
+ Otherwise it merges contexts via feature term unification
  (`sampler:ctx_union/3`). If the merge fails (e.g.~conflicting USE
  enable/disable sets), the goal fails and ordinary Prolog backtracking
  retracts the choice that led to the clash.
+ If the merge succeeds, the prover may #strong[re-call `rule/2`] on a
  canonical literal carrying `MergedCtx`, #strong[subtract] the
  previously proven body from the new body, and prove only the
  #strong[difference] --- updating Proof, Model, and Triggers
  incrementally and storing `Lit → MergedCtx` in the Model.

So "seen before" does not mean "frozen forever"; it means
#strong[accumulate constraints and re-expand only what new information
demands.]

== Prescient proving
<prescient-proving>
#figure(image("Diagrams/08-prescient-proving.svg", alt: "Prescient proving"),
  caption: [
    Prescient proving
  ]
)

When a literal is re-encountered with a changed context (e.g.~new USE
requirements from a different dependency path), the prover merges
contexts via feature-unification and re-expands only the difference.
This is called #strong[prescient proving] because knowledge about
constraints imposed later in the proof is incorporated into earlier
decisions #strong[without] unwinding the whole branch and starting the
literal from scratch.

=== Walkthrough: two paths into `dev-libs/openssl`
<walkthrough-two-paths-into-dev-libsopenssl>
Imagine two dependency paths that both need `dev-libs/openssl:install`:

- Path A pulls it in with #strong[USE `ssl`] required in the build set.
- Path B pulls it in with #strong[USE `threads`] required.

#strong[Without] prescient-style merging, a naive story would be: prove
openssl once under path A's context; later, when path B arrives with
incompatible or extra requirements, discover that the earlier proof was
too weak and #strong[backtrack far enough to re-prove] openssl under a
wider or corrected context --- repeating work and thrashing the search.

#strong[With] prescient proving, the second encounter does not throw
away the first. The prover merges the proof-term contexts:

- First encounter:
  `dev-libs/openssl:install?{[build_with_use:use_state([ssl],[])]}`
- Second encounter:
  `dev-libs/openssl:install?{[build_with_use:use_state([threads],[])]}`
- After feature term unification:
  `dev-libs/openssl:install?{[build_with_use:use_state([ssl,threads],[])]}`

The merged context commits openssl to satisfying #strong[both] paths at
once. The prover then asks the domain: does this merged context still
satisfy every constraint the rules attach to that literal (profile,
`REQUIRED_USE`, version domains, and so on)? If #strong[yes], no full
re-proof from zero is needed --- only any #strong[new] body literals the
expanded rule introduces beyond what was already proved. If #strong[no]
(for example, contradictory flags after merge), the merge or subsequent
guard fails and the prover #strong[backtracks] to another candidate
world.

That is the sense in which portage-ng is "prescient": #strong[later
requirements are folded into the context of an earlier proof step]
through merging and targeted re-expansion, instead of only discovering
the conflict after committing to a too-narrow past choice.

For example (same openssl scenario in compact form): - First encounter:
`dev-libs/openssl:install?{[build_with_use:use_state([ssl],[])]}` -
Second encounter:
`dev-libs/openssl:install?{[build_with_use:use_state([threads],[])]}` -
After merge:
`dev-libs/openssl:install?{[build_with_use:use_state([ssl,threads],[])]}`

The merged context ensures openssl is built with both `ssl` and
`threads`, without backtracking. If the merge produces a contradiction
(a flag in both enable and disable sets), the merge fails and the prover
backtracks.

== Triggers and the reverse-dependency index
<triggers-and-the-reverse-dependency-index>
#figure(image("Diagrams/08-triggers.svg", alt: "Triggers reverse-dependency index"),
  caption: [
    Triggers reverse-dependency index
  ]
)

The Triggers AVL is the piece that makes prescient updates
#strong[addressable]: it records, for each body literal, #strong[which
rule heads depend on it].

Concretely, when the prover proves head literal #strong[A] with body
`[B, C, D]`, it extends Triggers so that #strong[B], #strong[C], and
#strong[D] each map to a list that includes #strong[A] (typically
prepended if not already present). In other words, it stores edges
#strong[B → A], #strong[C → A], #strong[D → A] --- a
#strong[reverse-dependency index].

In the proof loop, a head #strong[H] is usually #strong[revisited]
because #strong[H] itself shows up again on the queue with a wider
`?{Context}` after feature term unification (the `dev-libs/openssl`
pattern above). The Triggers tree is still what makes that dependency
web #strong[legible]: Proof maps `rule(H) → dep(_, Body)` forward, but
only Triggers maps #strong[each body literal B] back to #strong[every
head A] that ever listed #strong[B]. Each time a rule is recorded or
re-recorded (including after a prescient merge), `add_triggers/4`
extends that reverse index so the artefact stays consistent with the
current bodies.

Later phases --- planners, schedulers, diagnostics --- use Triggers to
ask "if this literal moves, what else moves?" in logarithmic assoc time
per lookup. Without #strong[B → A] edges maintained alongside Proof,
nothing in the pipeline could mechanically enumerate #strong[which
install heads depended on a given dependency literal], and the graph
carried out of proving would be incomplete for anything that walks
dependencies backwards.

Together, #strong[Model + feature term unification] (merge contexts when
the #strong[same] literal is met again) and #strong[Triggers] (reverse
edges for every `rule(Head, Body)` expansion) document how constraints
flow through the graph without requiring a full restart for every new
edge.

== Entry rules and `prove_plan/5`
<entry-rules-and-prove_plan5>
#figure(image("Diagrams/08-prove-plan.svg", alt: "prove_plan pipeline"),
  caption: [
    prove\_plan pipeline
  ]
)

The standard pipeline entry point is:

```prolog
pipeline:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL)
```

This calls:

+ `prover:prove/9` --- constructs Proof, Model, Constraints, and
  Triggers
+ `planner:plan/5` --- wave planning for the acyclic portion
+ `scheduler:schedule/6` --- SCC/merge-set scheduling for the remainder

The prover is wrapped in `with_reprove_state` which saves and restores
the learned constraint store across reprove retries. Inside that,
`prove_with_retries` catches `prover_reprove` exceptions and restarts up
to `reprove_max_retries` times (default 3).

See
#link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
for the reprove mechanism in detail.

== Multiple stable models
<multiple-stable-models>
#figure(image("Diagrams/08-stable-models.svg", alt: "Multiple stable models"),
  caption: [
    Multiple stable models
  ]
)

The prover can produce different solutions (stable models) of the USE
flag configuration space. Using Prolog's built-in backtracking,
different valid configurations of the same target can be explored and
compared.

For example, a `REQUIRED_USE="|| ( linux macos )"` constraint yields two
stable models:

```
Model A:  USE="linux -macos"     Model B:  USE="-linux macos"
```

The `--variants` CLI option enables this mode, running the prover with
different USE flag configurations via `variant:use_override` and
`variant:branch_prefer`.

== Proof obligations
<proof-obligations>
After a literal is proven, the prover queries the domain for additional
proof obligations via `heuristic:proof_obligation/4`. This lets the
domain inject derived obligations --- extra literals to be appended to
the proof queue --- without the prover understanding domain-specific
semantics.

PDEPEND dependencies are handled this way: they are discovered only
after a literal is resolved and are injected as proof obligations via
`rules:literal_hook/4`.

== Further reading
<further-reading>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- the reprove mechanism and constraint learning
- #link("05-doc-proof-literals.md")[Chapter 5: Proof Literals] --- the
  literal format
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  `rule/2` works
- #link("04-doc-architecture.md")[Chapter 4: Architecture Overview] ---
  the full pipeline
