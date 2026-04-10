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


= Introduction
<introduction>
== The growing complexity of software
<the-growing-complexity-of-software>
portage-ng is not a package manager. It is a #strong[reasoning engine]
for software configuration management at scale.

To understand why this distinction matters, consider operating systems
as examples of complex software systems. An operating system is
assembled from thousands of interdependent components --- libraries,
compilers, language runtimes, desktop environments, system services ---
each of which evolves independently. The challenge of keeping all those
components working together has grown dramatically over the past three
decades, and the tools we use to manage that challenge have had to
evolve with it.

=== Binary software distribution
<binary-software-distribution>
In the earliest model --- still the dominant one for distributions like
Debian, Red Hat, and Ubuntu --- packages arrive as pre-built archives.
The distribution maintainers compile each package, test it against a
fixed set of other packages, and ship the result. The package manager's
job is essentially logistics: download the right set of archives and
unpack them into the filesystem. Order barely matters; as long as every
required archive is present at the end, inter-package linkage is correct
and the system works.

This model is simple and reliable. Because everyone receives the same
binaries, configurations are easy to reproduce, and commercial software
vendors can build and certify against a known, fixed set of packages.
The trade-off is that the user has little control: configuration choices
are made upstream, and customisation is limited to what the distribution
maintainers decided to provide.

=== Source-based systems
<source-based-systems>
Before Gentoo, installing software from source on Linux was a manual
undertaking. Projects like #strong[Linux From Scratch] (started 1999)
documented the process step by step, but every command was the user's
responsibility: download, patch, configure, compile, install --- by
hand, for every package.

The #strong[FreeBSD Ports] system (Jordan Hubbard, 1994) was the first
to automate source-based package management. #strong[Gentoo] (originally
Enoch, created by Daniel Robbins in 1999, inspired by FreeBSD Ports)
brought this idea to Linux. Gentoo 1.0 (March 2002) was the first Linux
distribution to provide fully automated source-based package management
as its primary mode of operation.

In its early days, Gentoo targeted a single platform (IA-32) and the
dependency problem was tractable: the package manager walked the
dependency graph, figured out which packages needed compiling, ordered
them, and built them one by one. Compiling from source meant binaries
were optimised for the exact hardware --- no lowest-common-denominator
builds --- and the performance advantage was real.

Tools like #strong[Portage] navigated these dependency graphs with an
imperative, trial-and-error approach: try a combination, detect
conflicts, adjust, and try again. For a single-platform distribution
with a moderately sized tree, this approach is adequate.

=== From packages to knowledge
<from-packages-to-knowledge>
As Gentoo grew --- thousands of packages, a dozen architectures,
multiple operating systems via #strong[Gentoo Prefix] --- simple graph
traversal was no longer sufficient. Each package now has
#strong[build-time options] (USE flags) that interact multiplicatively:
different CPUs to target, different compilers to use, different versions
of those compilers, different optional feature combinations. The space
of valid configurations is not merely large --- it is combinatorially
vast, and every point in that space must be internally consistent.

This is the #strong[metadistribution] concept. Gentoo does not
distribute binaries; it distributes #strong[knowledge] --- recipes
(ebuilds) that describe how to build every component of a system, and
configuration parameters (USE flags, keywords, profiles) that let the
user tailor the result. The word "package manager" does not do justice
to what this entails. Putting pre-built archives together is logistics.
Ensuring that thousands of packages, across multiple platforms, with
user-specified feature selections and hardware constraints, form an
internally consistent system --- that is #strong[configuration
management], and it requires more than a graph traversal algorithm.

Yesterday the system worked; today, after a routine update, it does not
--- and the answer is buried somewhere in the interaction of thousands
of constraints across hundreds of packages. A trial-and-error search
loop can tell you it #emph[failed], but not #emph[why].

=== From searching to proving
<from-searching-to-proving>
Solving this problem requires more than a better search loop. It
requires #strong[reasoning] --- the ability to derive consequences from
rules, to detect why a configuration is inconsistent, and to explain
what must change to make it consistent again.

portage-ng approaches the problem this way. Instead of #emph[searching]
for a plan, it #emph[proves] one. Every build plan portage-ng produces
is a formal proof --- a Prolog term that records, for every package,
which rule justified its inclusion and under what constraints. When no
fully valid plan exists, portage-ng does not give up: it makes explicit
assumptions (flag changes, keyword acceptance, unmasking), proves a plan
under those assumptions, and presents the assumptions as actionable
suggestions. The proof answers not only "what should I install?" but
also "why does this work?" --- and when something breaks, "what
changed?"

=== Declarative reasoning
<declarative-reasoning>
This is inherently a task for #strong[declarative reasoning]. We do not
want to prescribe a fixed sequence of imperative steps; we want to state
the rules of the domain and let a reasoning engine derive the
consequences.

Prolog --- an #strong[artificial intelligence] language built on exactly
this paradigm --- is a natural fit. You specify #emph[what] solution to
produce, not #emph[how] to produce it. The runtime --- unification,
backtracking, and proof search --- figures out the "how." Consider a
trivial example:

```prolog
os(linux).
os(darwin).
```

```prolog
?- os(Choice).
Choice = linux ;
Choice = darwin.
```

Prolog #strong[automatically] enumerates every valid binding for
`Choice`. This built-in #strong[backtracking] --- the ability to
systematically explore all alternatives --- is exactly what a
configuration engine needs. Traditional Portage did not originally have
backtracking at all; the retry mechanism it acquired later is not
designed to enumerate alternatives but to iteratively refine a single
solution by accumulating masks across restarts. In Prolog, backtracking
over alternatives is not a bolt-on feature --- it is a primitive of the
language.

The reasoning engine portage-ng implements is not inherently tied to
operating system management. We have chosen Gentoo because it captures
many of the hardest sub-problems --- figuring out the correct USE flag
combinations to satisfy user, system, and hardware constraints
simultaneously; resolving cyclic dependencies; managing co-installable
slots --- and any solution that works for Gentoo generalises to simpler
domains. But the same proof-based architecture could reason about any
domain where entities have capabilities, constraints, and dependencies
--- from cloud service composition to event-driven automation to
hardware design space exploration. Gentoo is the proving ground; the
ideas are general.

While source-based configuration management systems like Portage are
used by thousands of developers and organisations, the formal concepts
behind them --- constraint propagation, domain narrowing, proof
construction --- are understood by only a handful of people. portage-ng
aims to push forward the state of the art in this area and, by
expressing the resolver as a set of logical rules rather than an opaque
imperative algorithm, to make its inner workings more accessible and
easier to reason about.

This chapter explains why Gentoo is the right domain, why Prolog is the
right language, and how portage-ng's proof-based architecture addresses
the problem at a level that imperative package managers cannot reach.

== Why Gentoo?
<why-gentoo>
=== The metadistribution concept
<the-metadistribution-concept>
Most Linux distributions distribute #strong[binaries] --- fixed packages
with fixed configurations, tested together in a release cycle. Gentoo
distributes #strong[knowledge]: recipes (ebuilds) that describe how to
build every component of a complete system, and configuration parameters
(USE flags, keywords, profiles) that let the user tailor the result to
their hardware and requirements.

This is the #strong[metadistribution] concept. We no longer distribute
the output of a build process; we distribute the declarative
specification of the build process itself. The word "package manager"
does not do justice to what this entails. Putting pre-built packages
together is logistics. Ensuring that a complex, multi-dimensional
configuration space is internally consistent, constructing build plans
to realise a chosen configuration, and executing those plans with the
right ordering and parallelism --- that is #strong[configuration
management].

A single Portage tree contains roughly 32,000 ebuilds. Each ebuild
declares:

- #strong[Dependencies] --- what it needs at build time, run time, and
  post-install
- #strong[Use flags] --- optional features the user can enable or
  disable
- #strong[Slots] --- multiple versions that can coexist
- #strong[Keywords] --- which architectures the package is tested on
- #strong[Use constraints] --- restricting valid Use flag combinations

The number of valid configurations is combinatorially enormous. This is
not a bug --- it is the point. Gentoo's power comes from this
configurability. But it also means that reasoning about Gentoo packages
is reasoning about a large, richly structured constraint space.

=== Architectures and keywords
<architectures-and-keywords>
Gentoo was originally built for the IA-32 (x86) architecture. As
contributors ported it to other platforms --- PowerPC, ARM, SPARC, MIPS,
HPPA, and others, often available in 32-bit and 64-bit variants --- the
project developed the #strong[keyword] system to track per-architecture
stability. An ebuild can be marked `amd64` (stable on x86-64), `~arm`
(testing on ARM), or carry no keyword for a given architecture (meaning
it has not been validated there at all). Keywords turn architecture
support into a first-class constraint in the dependency graph: a package
that is stable on one architecture may be unstable or unavailable on
another, and the resolver must respect those boundaries.

Platforms beyond x86 Linux --- such as BSD, Solaris, and others --- were
handled as regular Gentoo targets with a different kernel and different
user-space libraries, using the same Portage machinery and ebuild
format. Google's #strong[ChromeOS] is a prominent example of such a
different platform delivered and managed entirely by Portage: ChromiumOS
maintains a fork of Portage alongside Gentoo-derived overlay
repositories (`portage-stable` for unmodified upstream ebuilds,
`chromiumos-overlay` for Google-specific packages), and changes flow
back to upstream Gentoo regularly.

The #strong[Gentoo Prefix] project (an outgrowth of the Gentoo for Mac
OS X effort) addressed a different challenge: installation #emph[within]
a pre-built operating system where root binaries cannot be modified. On
platforms like Mac OS X, Prefix installs Portage and all packages into a
user-defined offset directory rather than the filesystem root, allowing
a full Gentoo-managed software stack to coexist with the host system.

=== Real-world adoption
<real-world-adoption>
Gentoo's approach to source-based configuration management has been
adopted well beyond the Gentoo community:

- #strong[ChromiumOS / ChromeOS] (Google). ChromiumOS is the open-source
  project; ChromeOS is Google's proprietary product shipped on
  Chromebooks. Both are built using Gentoo's Portage, with overlay
  repositories (`portage-stable` for unmodified upstream ebuilds,
  `chromiumos-overlay` for Google-specific packages). In 2025, Google
  confirmed that ChromeOS and Android are merging into a unified
  platform (codenamed "Aluminium") for 2026, with Android's kernel as
  the foundation and ChromeOS's desktop interface layered on top.

- #strong[Container Linux] (CoreOS, later Flatcar). CoreOS Container
  Linux --- a lightweight, container-optimized operating system designed
  for cloud infrastructure --- was built on Gentoo foundations, using
  Portage and ebuilds for its build system. After CoreOS was
  discontinued in 2020, #strong[Flatcar Container Linux] continued the
  Gentoo-based lineage and is deployed at scale by organisations
  including Adobe (18,000+ nodes), Equinix, and numerous managed
  Kubernetes providers.

These adoptions are not cosmetic. ChromeOS and Flatcar use the same
ebuild format, the same Portage dependency resolver, and the same
overlay architecture as upstream Gentoo. The fact that this machinery
scales from a single developer's workstation to tens of thousands of
production nodes is evidence that Gentoo represents state-of-the-art
practice in large-scale software configuration management.

=== Reasoning about software at scale
<reasoning-about-software-at-scale>
When you ask "can I install Firefox with Wayland support on this
machine?", you are really asking: "does there exist a consistent
assignment of package versions, USE flags, and slot choices across my
entire dependency graph such that all constraints are satisfied?" That
is a #strong[satisfiability problem] over a structured domain.

portage-ng treats the Portage tree as what it truly is: a
#strong[declarative knowledge base]. Ebuilds are not build scripts to
execute --- they are propositions with preconditions. Dependencies are
not edges in a graph to traverse --- they are logical implications to
prove. Configuration choices are not switches to flip --- they are
constraints to satisfy.

This shift in perspective --- from "searching for a working set of
packages" to "proving that a consistent configuration exists" --- is
what makes portage-ng fundamentally different from Portage, Paludis, and
pkgcore --- the three existing package managers that operate on the same
ebuild base.

== A Prolog primer
<a-prolog-primer>
If you have never used Prolog, this section gives you enough to follow
the rest of the book. If you already know Prolog, skip to
#link(<why-prolog>)[Why Prolog?].

=== Facts and rules
<facts-and-rules>
Prolog programs are built from #strong[facts] and #strong[rules]. A fact
states something that is true:

```prolog
requires(browser, graphics).
requires(browser, networking).
requires(graphics, fonts).
```

This says: a browser requires graphics and networking; graphics requires
fonts. Each line is a fact --- something the system knows to be true.

A #strong[rule] says something is true #emph[if] certain conditions
hold:

```prolog
needs(X, Y) :- requires(X, Y).
needs(X, Y) :- requires(X, Z), needs(Z, Y).
```

Read `:-` as "if." The first clause says: X needs Y if X directly
requires Y. The second says: X needs Y if X requires some intermediate
Z, and Z in turn needs Y. Together, these two lines define transitive
dependency --- if the browser requires graphics and graphics requires
fonts, then the browser needs fonts.

=== Queries and unification
<queries-and-unification>
You ask Prolog questions by posing #strong[queries]. Prolog answers by
finding values that make the query true:

```prolog
?- needs(browser, What).
What = graphics ;
What = networking ;
What = fonts.
```

Prolog found everything the browser transitively needs. It did this
through #strong[unification] --- matching the variable `What` against
terms in the database --- and #strong[backtracking] --- systematically
trying every possibility.

Unification is more powerful than pattern matching. Two terms unify if
there exists a substitution that makes them identical:

```prolog
?- package(Name, stable) = package(editor, Status).
Name = editor, Status = stable.
```

Prolog figured out that `Name` must be `editor` and `Status` must be
`stable` for both sides to match. This works in both directions ---
Prolog does not distinguish between "input" and "output" arguments.

=== Backtracking
<backtracking>
When a Prolog query has multiple solutions, the runtime explores them
through #strong[backtracking]. Consider:

```prolog
color(red).
color(green).
color(blue).

?- color(X).
X = red ;
X = green ;
X = blue.
```

Each `;` triggers backtracking: Prolog undoes its last choice and tries
the next alternative. This search is built into the language --- you do
not write a search loop.

=== Compound terms
<compound-terms>
Prolog terms can be nested, forming structured data without defining
classes or schemas. For example, a package entry might look like:

```prolog
package(editor, version(2, 4, 1), [unicode, spellcheck]).
```

This single term captures a package name, a structured version, and a
list of enabled features. Because Prolog comparison (`compare/3`) works
structurally on compound terms, two versions can be compared directly
--- no custom comparator needed. portage-ng uses compound terms
extensively to represent versions, dependencies, and proof entries.

=== Lists and association lists
<lists-and-association-lists>
Prolog lists are linked lists built from `[Head|Tail]`:

```prolog
?- [a, b, c] = [H|T].
H = a, T = [b, c].
```

Looking up a value in a plain list requires walking it from head to tail
--- O(n) in the worst case. When a proof tree contains thousands of
entries, this becomes a bottleneck.

SWI-Prolog provides #strong[association lists] (AVL trees) via
`library(assoc)` as an efficient alternative. An AVL tree is a
self-balancing binary search tree: keys are kept in order, and the tree
is rebalanced after every insertion so that no branch is more than one
level deeper than its sibling.

To find a key, we do not scan every element. Instead, we compare the
target with the current node and follow the appropriate branch --- left
if the target is smaller, right if it is larger. The following diagram
shows how looking up "ssl" in a tree of seven entries requires only
three comparisons:

#figure(image("Diagrams/01-avl-tree.svg", alt: "AVL tree lookup"),
  caption: [
    AVL tree lookup
  ]
)

Because the tree stays balanced, every lookup follows a single path from
root to leaf. The length of that path is at most log₂(n) --- with 10,000
entries, an AVL lookup visits at most 14 nodes instead of scanning all
10,000.

portage-ng uses association lists extensively --- for the proof, the
model, the trigger set, and the constraint store:

```prolog
?- empty_assoc(E),
   put_assoc(editor, E, installed, A1),
   put_assoc(browser, A1, pending, A2),
   get_assoc(editor, A2, Status).
Status = installed.
```

All operations (`get_assoc`, `put_assoc`) are O(log n), which makes them
practical for the data structures at the heart of the prover.

=== Definite Clause Grammars
<definite-clause-grammars>
When portage-ng reads a package's dependency specification, it needs to
parse structured text like `>=dev-libs/openssl-1.1:0=` into Prolog terms
the prover can reason about. In most languages, writing a parser means
writing imperative code --- loops, state machines, error handling. In
Prolog, you can write the grammar itself as a program.

A #strong[DCG] (Definite Clause Grammar) lets you describe what valid
input looks like, declaratively. Prolog takes care of matching the input
against the grammar rules. For example, a simple grammar for a greeting:

```prolog
greeting --> [hello], name.
name --> [world].
name --> [prolog].
```

This reads naturally: "a greeting is the word `hello` followed by a
name; a name is either `world` or `prolog`." To check whether a sequence
matches:

```prolog
?- phrase(greeting, [hello, world]).
true.

?- phrase(greeting, [hello, cat]).
false.
```

The grammar #emph[is] the parser --- there is no separate parsing step.
portage-ng uses DCGs to parse the #strong[EAPI] (Ebuild API) dependency
specification language --- EAPI is the versioned interface that defines
the syntax and semantics of Gentoo's ebuild format, including version
ranges, Use conditionals, slot operators, and choice groups. The result
is a parser that reads like a specification of the language it accepts,
making it easier to verify, extend, and maintain.

=== Meta-programming
<meta-programming>
One of Prolog's most distinctive features is that programs and data are
made of the same material: #strong[terms]. A rule like
`requires(browser, graphics)` is not just an instruction --- it is a
data structure that a program can inspect, build, and pass around. This
blurs the line between "the program" and "the data it operates on" in a
way that is natural in Prolog but awkward in most other languages.

Why does this matter for portage-ng? Because the prover does not just
compute a plan --- it builds a #strong[proof] that explains why the plan
is correct. As the prover works, it constructs a term that records every
decision:

```prolog
proof(browser, [
  rule(requires(browser, graphics), [
    proof(graphics, [
      rule(requires(graphics, fonts), [
        proof(fonts, [fact])
      ])
    ])
  ])
]).
```

This proof term says: "the browser is in the plan because it requires
graphics, which is in the plan because it requires fonts, which is a
base fact." The proof is not a side effect or a log --- it is a
first-class Prolog term that can be queried, compared, and transformed
like any other data.

The same principle applies to assumptions. When the prover cannot
satisfy a dependency without, say, accepting a testing keyword, it
records that assumption as a term inside the proof:

```prolog
assumed(accept_keywords('~amd64', graphics))
```

At the end, portage-ng can walk the proof, collect all assumptions, and
present them to the user as actionable suggestions --- precisely because
assumptions are data, not scattered side effects.

This capability is called #strong[reification]: turning the process of
reasoning into data that can itself be reasoned about. It is what makes
the "every plan is a proof" architecture natural in Prolog.

== Why Prolog?
<why-prolog>
Now that you have seen the basics, here is why Prolog is not just a
possible implementation language but the #emph[right] one for building a
reasoning engine for software configuration management.

=== The primitives match the problem
<the-primitives-match-the-problem>
A reasoning engine for configuration management needs a small set of
core operations. In Prolog, these operations are built-in primitives
rather than library code:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Reasoning need]], [#strong[Prolog primitive]],),
    table.hline(),
    [Configuration rules], [Horn clauses],
    [Structured data], [Compound terms],
    [Search with backtracking], [Built-in backward chaining with
    backtracking],
    [Constraint propagation], [Unification and association lists],
    [Specification grammar], [Definite Clause Grammars],
    [Proof construction], [Terms as data (reification)],
    [Meta-programming], [Runtime assertion and introspection],
  )]
  , kind: table
  )

Imperative package managers must re-implement all of these. Portage's
`depgraph.py` implements its own retry loop with mask accumulation.
Paludis's `decider.cc` implements its own constraint accumulator with
exception-driven restart. Both re-invent mechanisms that Prolog provides
as proven primitives. By relying on these primitives, the codebase
becomes easier to read and understand --- developers can focus fully on
declaring domain knowledge rather than maintaining search and
backtracking machinery.

=== Meta-level reasoning
<meta-level-reasoning>
Beyond the primitives, Prolog enables #strong[meta-level reasoning] ---
the ability to reason about the reasoning process itself. For a
configuration management engine, this is the decisive advantage.

#strong[Reifying assumptions.] When the prover cannot satisfy a
dependency, it does not throw an error. It records an assumption as a
first-class term in the proof tree. The assumption carries structured
metadata: why it was made, what alternatives were tried, and what the
user can do about it. This is natural in Prolog because proofs are data.

Consider what happens when a package requires a keyword that is not
accepted. An imperative resolver would either fail or silently accept
the keyword. portage-ng records:

```prolog
rule(assumed(portage://dev-libs/foo-1.0:merge), [])
```

This assumption appears in the proof, flows through the planner, and is
presented to the user as: "I assumed dev-libs/foo-1.0 could be merged.
To make this work, I will add it for you to package.accept\_keywords."

#strong[Inspecting proof trees.] The explainer module queries the proof
AVL to answer "why is this package in the plan?" without re-running the
resolver. In an imperative resolver, this would require instrumenting
the search loop with logging and replaying it.

#strong[Learning from failures.] When a proof attempt fails, the prover
extracts a learned constraint --- a narrowed version domain --- from the
failure and carries it into the next attempt. This is analogous to CDCL
(Conflict-Driven Clause Learning) in SAT solvers, but expressed as
Prolog term manipulation rather than boolean clause generation.

=== Declarative vs.~imperative
<declarative-vs.-imperative>
The difference is not just stylistic. A declarative specification of
configuration rules is:

- #strong[Auditable] --- the rules can be read as logical statements
- #strong[Testable] --- individual rules can be queried in isolation
- #strong[Extensible] --- adding a new dependency type means adding
  clauses, not modifying control flow

In portage-ng, the entire EAPI specification --- hundreds of pages of
the PMS (Package Manager Specification, the formal document that defines
how Gentoo ebuilds, dependencies, USE flags, slots, and all related
metadata must be interpreted) --- is captured in a set of DCG grammar
rules and Prolog clauses. When EAPI 9 added new features, the
implementation required adding new grammar rules and clauses. The
reasoning engine --- prover, planner, and scheduler --- did not change
at all, because it is domain-agnostic.

=== Beyond pure Prolog
<beyond-pure-prolog>
Prolog's strengths --- backtracking, unification, reification ---
provide the foundation, but building a large-scale reasoning engine also
requires structure that pure Prolog does not offer out of the box.
portage-ng extends standard Prolog with two mechanisms: #strong[feature
terms] for carrying structured metadata through proofs, and
#strong[contexts] for organising code into encapsulated, independently
stateful components.

=== Feature logic and feature terms
<feature-logic-and-feature-terms>
In classical logic programming, a term is either an atom, a variable, or
a compound. That is enough for simple reasoning, but when the prover
needs to carry #emph[configuration alongside identity] --- "this
package, with these USE flags, in this slot, at this proof depth" --- a
flat compound quickly becomes unwieldy. Feature logic, originally
developed by Hassan Aït-Kaci and others for computational linguistics,
offers a cleaner model: a #strong[feature term] is a structured record
of named attributes (features) whose values may themselves be feature
terms. Two feature terms can be #strong[unified] (merged)
non-destructively, combining their information while checking for
consistency.

Andreas Zeller applied feature logic directly to software configuration
management, showing that features and feature unification provide a
natural formalism for describing and merging software configurations ---
capturing version selections, build options, and platform constraints as
feature terms rather than ad-hoc data structures. portage-ng builds on
this insight: USE flags, slot constraints, version domains, and proof
context are all represented as feature terms that the prover unifies as
it expands the dependency graph.

portage-ng uses the `?{}` notation to attach a feature term to any
literal. The syntax reads as "this literal, #emph[qualified by] these
features":

```prolog
portage://app-editors/neovim-0.12.0:run?{[]}
```

Here the feature term `{[]}` is empty --- no additional constraints
beyond the literal itself. As the prover expands dependencies and
resolves USE flags, the feature term accumulates information:

```prolog
portage://app-editors/neovim-0.12.0:run?{[nvimpager, naf(test)]}
```

The feature term `{[nvimpager, naf(test)]}` records that the `nvimpager`
USE flag is enabled and `test` is disabled (`naf` stands for "negation
as failure" --- the standard logic-programming notation for default
negation).

Feature unification is the operation that merges two feature terms. When
the prover encounters the same package from two different dependency
paths, each carrying its own feature term, unification combines them:

- #strong[Plain items] (like USE flags) are collected by union.
- #strong[Constrained sets] `{L}` use intersection semantics --- both
  paths must agree.
- #strong[Keyed values] (`feature:value` pairs) are unified recursively.
- If a term and its negation (`naf(X)` vs.~`X`) both appear, unification
  #strong[fails] --- this signals a genuine conflict in the dependency
  graph.

This mechanism is domain-agnostic: the unifier (`Source/Logic/unify.pl`)
does not mention USE flags, slots, or ebuilds. It operates on abstract
feature terms. The Gentoo domain layer maps USE flags, slot constraints,
and version domains onto feature terms; the unifier simply merges them.
A domain hook (`feature_unification:val_hook/3`) allows domain-specific
value types (e.g. version domain intersection) to participate in
unification without modifying the core.

The result is that every literal in a proof carries a complete,
machine-readable description of its resolved configuration. The planner
and printer can read this directly --- there is no need to re-derive
"which USE flags were active" after the fact.

=== Contextual object-oriented programming
<contextual-object-oriented-programming>
Prolog operates under the #strong[closed-world assumption]: what cannot
be derived from the program is considered false. In practice, this means
that reasoning about a predicate requires visibility of #emph[all] its
clauses --- the program is treated as a complete description of the
world. For a small program this is manageable, but in a system with tens
of thousands of packages, dozens of repositories, and overlapping
configurations, the "world" becomes very large. Not all of it is
relevant to every question.

Context-based reasoning addresses this directly: it partitions the
closed world into #strong[scoped contexts], each carrying only the facts
and rules that are relevant to a particular component. When reasoning
about a repository, only that repository's entries, configuration, and
constraints are in scope. The closed-world assumption still holds ---
but within a well-defined boundary, making reasoning both tractable and
modular.

Standard Prolog module systems offer some namespacing, but they were
designed for library organisation, not for modelling independent
entities that each carry their own state, rules, and encapsulation
boundaries. We need a way for each component to have its own context ---
its own facts, its own rules --- with explicit declarations of what is
public interface and what is private implementation. Different
repositories and different configurations must be able to coexist
without interfering with each other's reasoning.

In the object-oriented world, this problem was solved long ago with
encapsulation and access control. The challenge is bringing those
organisational benefits to Prolog without sacrificing its declarative
nature. The rules inside a context must remain ordinary logical clauses
--- directly translatable into traditional logic --- while the context
system provides the structure around them.

portage-ng needed object-oriented style programming --- classes,
instances, encapsulation, access control --- but at #strong[runtime],
because repositories and configurations are discovered and instantiated
at startup, not known at compile time. No existing Prolog library
provided this. #strong[Logtalk], the best-known approach to
object-oriented logic programming, works by compile-time translation:
source files are transformed into plain Prolog before execution. That
model does not fit a system that creates and composes objects
dynamically.

So portage-ng implements its own runtime object system called
#strong[context] (implemented in `context.pl`). The syntax is
deliberately Logtalk-like --- `::-` for method clauses, `::` for message
sends, `dpublic`, `dprotected`, `dprivate` for access control --- but
the underlying mechanism is entirely different: contexts are created,
cloned, and composed at runtime through Prolog's own assert/retract
machinery. There is no compilation step and no source-to-source
transformation.

To illustrate, here is a simplified example of a `person` context:

```prolog
:- module(person, []).
:- class.

:- dpublic([person/1, '~person'/0]).
:- dpublic([get_name/1, set_name/1]).
:- dpublic([get_age/1, set_age/1]).
:- dpublic([add_title/1, remove_title/1]).
:- dprivate(age/1).
:- dprivate(title/1).
:- dprotected(name/1).

person(Name) ::-
  :set_name(Name).

'~person' ::-
  :this(Context),
  write('Person destructor - '), write(Context), nl.

get_name(Name) ::-
  ::name(Name).

set_name(Name) ::-
  <=name(Name).

set_age(Age) ::-
  <=age(Age).

add_title(Title) ::-
  <+title(Title).

remove_title(Title) ::-
  <-title(Title).

age(Age) ::-
  number(Age), Age > 0.
```

Several things are worth noting. The `:- class` directive declares that
this module defines a context class. The `dpublic`, `dprotected`, and
`dprivate` directives specify access control --- just like in classical
OO, public predicates can be called by anyone, protected predicates only
by the class and its descendants, and private predicates only within the
class itself. The constructor `person/1` initialises the instance by
setting its name; the destructor `~person` is called when the instance
is destroyed. The `::-` operator (instead of Prolog's standard `:-`)
marks instance methods: their clauses are guarded at runtime so that
each instance operates on its own state. The `::` prefix reads instance
data, `<=` assigns it (replacing any previous value), `<+` adds a fact
to the instance, and `<-` removes one --- as shown by `add_title` and
`remove_title`, which allow a person to accumulate multiple titles. The
`:` prefix calls other methods on the same instance.

Using this class is straightforward:

```prolog
?- pieter:newinstance(person).
true.

?- pieter:person('Pieter').
true.

?- pieter:set_age(40).
true.

?- pieter:add_title('Dr.').
true.

?- pieter:add_title('Prof.').
true.

?- pieter:get_age(Age).
Age = 40.

?- pieter:get_title(Title).
Title = 'Dr.' ;
Title = 'Prof.'.
```

The `newinstance` call creates an instance named `pieter` from the
`person` class, and the constructor is invoked with
`pieter:person('Pieter')`. From that point on, `pieter` is a live
context with its own state. Setting the age and adding titles modifies
that instance's private data. Querying titles backtracks over all titles
that were added --- this is Prolog's backtracking working naturally
within the context system.

#figure(image("Diagrams/01-context-person.svg", alt: "Person class and instances"),
  caption: [
    Person class and instances
  ]
)

Each instance carries its own state: `pieter` has two titles and age 40,
`alice` has one title and age 35, `bob` has no titles and age 28. The
class defines the shape; each instance fills it independently.

In portage-ng, repositories are context objects: each has a name, a set
of entries, and operations like `sync`, `graph`, and `query` that are
dispatched through the context. The prover does not need to know which
repository it is reasoning about --- it receives a context and operates
through it.

#figure(image("Diagrams/01-context-repository.svg", alt: "Repository class and instances"),
  caption: [
    Repository class and instances
  ]
)

The `repository` class defines the interface --- `init`, `sync`,
`entry`, `query` --- while each instance holds its own path, protocol,
and entries. The prover queries `portage:entry(E)` and
`myoverlay:entry(E)` through the same module-qualified call; the context
system dispatches each call to the right instance's private data.

This approach brings encapsulation, polymorphism, and modularity to
Prolog while preserving its declarative core. The rules inside a context
are ordinary Prolog clauses; the context system simply controls
visibility and dispatches calls to the right instance. The full design
is covered in chapters 19 and 20.

=== Feature logic meets contextual logic
<feature-logic-meets-contextual-logic>
There is a natural synergy between feature logic and contextual logic
programming that is worth noting. A context --- with its named
attributes, access control levels, and instance-specific state --- can
be viewed as a special kind of feature term: a structured record of
features (name, age, title, path, protocol, …) augmented with meta-level
annotations (public, protected, private) that control which features are
visible to which parts of the program. Conversely, feature unification
can be seen as a restricted form of context composition: merging two
feature terms is analogous to combining two contexts, with consistency
checking playing the role of access control.

This perspective suggests that feature logic and contextual logic
programming are two views of the same underlying formalism --- one
emphasising data (feature terms as structured records) and the other
emphasising behaviour (contexts as encapsulated reasoning units). A
unified framework that captures both would be a natural extension:
feature terms with access-controlled attributes, or contexts whose state
is described and merged via feature unification. This remains an open
area for further exploration.

=== Pengines: contexts over the network
<pengines-contexts-over-the-network>
SWI-Prolog provides #strong[Pengines] (Prolog Engines) --- lightweight,
sandboxed Prolog instances that can be created, queried, and destroyed
over HTTP. Each Pengine is an isolated reasoning environment with its
own clause store, running inside a host server process. Clients on
remote machines can create a Pengine, send it a query, and receive
results --- all over a standard HTTPS connection.

The connection to contextual logic programming is direct: a Pengine is,
in essence, a #strong[remote context]. Just as a local context
encapsulates its own state and exposes a public interface, a Pengine
encapsulates a Prolog environment and exposes it over the network. The
access control that contexts provide locally (public, protected,
private) is mirrored by the Pengine sandbox, which restricts which
predicates the remote client may call.

portage-ng uses Pengines in its server mode. The server hosts the
knowledge base and exposes it through a Pengine application: clients and
workers create Pengines on the server, submit proving goals, and receive
plan results --- all without needing a local copy of the knowledge base.
From the client's perspective, the interaction looks like a local Prolog
query; the network transport is transparent. This is what makes
client--server mode practical for embedded and resource-constrained
devices: the full reasoning context lives on the server, and the client
merely drives it.

== The "every plan is a proof" philosophy
<the-every-plan-is-a-proof-philosophy>
These ideas come together in portage-ng's central insight: a build plan
should not be the output of a search algorithm that happens to
terminate. It should be a #strong[proof object] --- a term that records,
for every package, which rule justified its inclusion and under what
constraints.

This gives three properties that traditional resolvers lack:

+ #strong[Completeness.] If a valid plan exists, the prover finds it. If
  no valid plan exists, the prover completes with explicit assumptions
  that document exactly where the specification is unsatisfiable.

+ #strong[Explainability.] Every package in the plan can be traced back
  through the proof tree to the user's original target. "Why is this
  package here?" is answered by inspecting the proof, not by re-running
  the resolver.

+ #strong[Reproducibility.] The proof is a first-class Prolog term.
  Given the same Portage tree, VDB, and configuration, the same proof is
  produced every time.

== How portage-ng relates to other resolvers
<how-portage-ng-relates-to-other-resolvers>
portage-ng is not a rewrite of Portage in Prolog. It is a fundamentally
different approach to the same problem:

#figure(
  align(center)[#table(
    columns: (20%, 20%, 20%, 20%, 20%),
    align: (left,left,left,left,left,),
    table.header([], [#strong[Portage]], [#strong[Paludis]], [#strong[pkgcore]], [#strong[portage-ng]],),
    table.hline(),
    [#strong[Language]], [Python], [C++], [Python], [SWI-Prolog],
    [#strong[Model]], [Greedy graph + retry], [Constraint accumulator +
    restart], [Same as Portage], [Inductive proof search],
    [#strong[Conflicts]], [Retries with mask accumulation], [Restarts
    with fresh state], [Same as Portage], [Iterative refinement with
    learned domains],
    [#strong[Completeness]], [Sometimes fails], [May exhaust
    restarts], [Sometimes fails], [Always produces a plan],
    [#strong[Guarantees]], [None], [None], [None], [Every plan is a
    proof],
  )]
  , kind: table
  )

For a detailed comparison of the reasoning models, see
#link("21-doc-resolver-comparison.md")[Chapter 21: Resolver Comparison].

== A brief history
<a-brief-history>
The author's involvement with Gentoo began in 2002 as the founder of the
first architecture port --- PowerPC. That work contributed to the
keyword system described above and to expanding the range of platforms
where Gentoo could run. In 2003, a formal top-level management structure
was implemented for the Gentoo project
(#link("https://www.gentoo.org/glep/glep-0004.html")[GLEP 4]). Under
this structure, the author served as a senior manager for Gentoo with
both strategic and operational responsibility for three areas: Gentoo on
alternative operating systems and LiveCD technology, developer tools,
and package manager research (Portage). That experience --- porting
across architectures, managing the resulting configuration complexity,
and researching the limits of Portage's imperative resolver ---
motivated the portage-ng project.

portage-ng began in 2005 as an experiment in applying logic programming
to software configuration management. The initial question was simple:
could Prolog's built-in search and backtracking replace the hand-written
solver in Portage?

The answer turned out to be deeper than expected. Prolog did not just
replace the solver --- it changed what was possible. The ability to
reify proofs meant build plans became inspectable objects. The ability
to record assumptions meant the resolver never had to give up. The
ability to parse grammars with DCGs meant the EAPI specification could
be expressed directly as code.

Over two decades of development, portage-ng has evolved from a
proof-of-concept into a full-featured configuration management front-end
with PMS 9 / EAPI 9 compliance, distributed proving, LLM-assisted plan
explanation, and measured correctness against Portage across the entire
Gentoo tree.

== Further reading
<further-reading>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- getting portage-ng running on your machine
- #link("04-doc-architecture.md")[Chapter 4: Architecture Overview] ---
  how the six pipeline stages fit together
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- the inductive
  proof engine in detail
- #link("21-doc-resolver-comparison.md")[Chapter 21: Resolver Comparison]
  --- deep dive into how portage-ng compares with Portage, Paludis, and
  pkgcore

= Installation and Quick Start
<installation-and-quick-start>
== Prerequisites
<prerequisites>
=== Required
<required>
The following tools must be present on every system that runs
portage-ng. SWI-Prolog is the runtime; the others are used during
repository syncing, metadata extraction, and distfile verification.

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Dependency]], [#strong[Minimum
      version]], [#strong[Purpose]],),
    table.hline(),
    [#strong[SWI-Prolog]], [10.0.0], [Runtime interpreter. Must be built
    with SSL, PCRE, editline, HTTP, crypto, and pengines support.],
    [#strong[bash]], [5], [Metadata extraction via `ebuild-depend.sh`
    and helper scripts.],
    [#strong[git]], [any], [Repository syncing (`--sync` with git
    protocol), version display.],
    [#strong[curl]], [any], [Mirror/distfile downloads, HTTP-based
    repository sync.],
    [#strong[openssl] CLI], [any], [Distfile hash verification
    (`openssl dgst`), TLS certificate generation for client--server
    encryption.],
    [#strong[Gentoo Portage tree]], [---], [A full Portage tree (ebuilds
    \+ md5-cache). portage-ng reads the md5-cache for dependency
    resolution and requires the ebuilds for building.],
  )]
  , kind: table
  )

On most Gentoo systems these are already installed. On non-Gentoo hosts
(e.g.~macOS), SWI-Prolog and bash are the only items you may need to
install manually.

=== Required for specific features
<required-for-specific-features>
Some portage-ng features require additional tools. These are only needed
for specific commands.

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Dependency]], [#strong[Feature]], [#strong[Notes]],),
    table.hline(),
    [#strong[Graphviz] (\>= 11)], [`--graph`], [The `dot` command
    generates interactive SVG dependency graphs.],
    [#strong[dns-sd]], [Distributed mode], [mDNS/Bonjour service
    discovery. Built-in on macOS; use `avahi-browse` on Linux.],
    [#strong[ebuild]], [`--merge` / `--build`], [Actual package building
    delegates to Portage's ebuild infrastructure. Not needed for
    `--pretend`.],
    [#strong[rsync]], [`--sync` (rsync)], [Only when using rsync-based
    repository sync.],
    [#strong[tar]], [`--sync` (HTTP)], [Only when using tarball-based
    repository sync.],
  )]
  , kind: table
  )

=== Optional
<optional>
The following are convenient but not required for core operation.

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Dependency]], [#strong[Purpose]],),
    table.hline(),
    [#strong[Python 3]], [Timeout watchdog in the dev wrapper;
    comparison scripts in `Reports/Scripts/`.],
    [#strong[make] / #strong[cmake]], [Used by build helper scripts for
    packages that need them.],
    [#strong[aha] / #strong[perl]], [Pretty-print HTML output
    generation.],
    [#strong[pv]], [Progress bars during batch graph generation.],
    [#strong[Ollama]], [Local LLM inference and vector embeddings for
    `--search` / `--explain`.],
  )]
  , kind: table
  )

=== Prolog build requirements
<prolog-build-requirements>
When compiling SWI-Prolog from source, ensure the following optional
components are enabled (they are usually built by default):

- #strong[OpenSSL] --- required for `library(crypto)`, `library(ssl)`,
  `library(http/http_ssl_plugin)`
- #strong[PCRE] --- required for `library(pcre)` (used in EAPI parsing)
- #strong[GNU Readline / Editline] --- required for `library(editline)`
  (interactive shell)
- #strong[libgmp] --- required for arbitrary-precision arithmetic
- #strong[zlib] --- required for qcompiled file support
  (`Knowledge/kb.qlf`)

== Building
<building>
From the project root:

```bash
make check    # verify SWI-Prolog is installed
make build    # create the portage-ng binary
make install  # install to /usr/local/bin (requires sudo)
```

The `build` target uses `swipl --stand_alone=true` to produce a
self-contained binary.

== First run
<first-run>
=== Pretend (dry-run)
<pretend-dry-run>
Generate a build plan without executing it:

```bash
portage-ng --pretend app-editors/neovim
```

portage-ng proves a dependency graph, plans it into parallel steps, and
presents the result:

```
>>> Emerging : portage://app-editors/neovim-0.12.0:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─ step 1 ─┤ download portage://dev-python/tree-sitter-0.25.2
            │           └─ file ─┤ 170.27 Kb  tree-sitter-0.25.2.gh.tar.gz
            │ download portage://dev-lua/mpack-1.0.13
            │           └─ file ─┤ 16.17 Kb   mpack-1.0.13.tar.gz

 └─ step 2 ─┤ install  portage://dev-lang/lua-5.1.5-r200
            │           └─ conf ─┤ USE = "readline deprecated"
            │                    │ SLOT = "5.1"
            │ install  portage://dev-libs/msgpack-6.0.0-r1
            │           └─ conf ─┤ USE = "-doc -examples -test"
            │                    │ SLOT = "0/2-c"
            ...

 └─ step 7 ─┤ install  portage://app-editors/neovim-0.12.0
            │           └─ conf ─┤ USE = "nvimpager -test"
            │                    │ LUA_SINGLE_TARGET = "luajit -lua5-1"

 └─ step 8 ─┤ run      portage://app-editors/neovim-0.12.0

Total: 59 actions (20 downloads, 19 installs, 1 update, 19 runs),
       grouped into 8 steps.
       18.82 Mb to be downloaded.
```

Actions within the same step can execute in parallel. The plan
distinguishes download, install, update, and run phases. Each package
shows its resolved configuration (Use flags, slot, target selection).

If portage-ng had to make assumptions during proving, they are reported
at the end with suggested fixes and draft bug reports.

=== Interactive shell
<interactive-shell>
Drop into a Prolog shell with the full knowledge base loaded:

```bash
portage-ng --shell
```

The shell provides direct access to the knowledge base. The built-in
`query:search/2` predicate offers a readable way to explore it.

#strong[Search for packages by name:]

```
?- query:search([name(neovim), description(D)], Repository://Entry).
D = "Vim-fork focused on extensibility and agility",
Repository = portage,
Entry = 'app-editors/neovim-9999'.
```

Press `;` to see the next result, or `.` to stop. Prolog backtracks
through all matching ebuilds automatically.

#strong[Look up slot and keywords:]

```
?- query:search([name(neovim), slot(S), keywords(K)], Repository://Entry).
S = '0',
K = unstable(amd64),
Repository = portage,
Entry = 'app-editors/neovim-0.12.0'.
```

#strong[Search across repositories:]

```
?- query:search([name(firefox), description(D)], Repository://Entry).
D = "Firefox Web Browser",
Repository = portage,
Entry = 'www-client/firefox-149.0'.
```

#strong[Count all ebuilds:]

```
?- aggregate_all(count, portage:entry(_), Total).
Total = 31535.
```

#strong[Read a single metadata field:]

```
?- cache:entry_metadata(portage, 'app-editors/neovim-0.12.0', description, D).
D = "Vim-fork focused on extensibility and agility".
```

The full cache schema and query language are documented in
#link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base].

=== Sync the Portage tree
<sync-the-portage-tree>
Sync the repository and regenerate the knowledge base cache:

```bash
portage-ng --sync
```

The sync performs three phases for each registered repository:

+ #strong[Repository sync] --- pulls the latest Portage tree (via git,
  rsync, or HTTP tarball depending on configuration).
+ #strong[Metadata sync] --- reads the md5-cache files and, if
  configured, regenerates cache entries for ebuilds that have changed.
+ #strong[Knowledge base sync] --- parses all cache entries into Prolog
  facts (the `cache:entry`, `cache:entry_metadata`, `cache:manifest`,
  etc. predicates) and saves the compiled knowledge base to disk.

```
>>> Syncing 1 registered repository

--- Syncing repository "portage" ---

 Syncing repository ... ok
 Syncing metadata   ... Ebuild: sys-apps/portage-2.3.99-r1
                        Ebuild: dev-lang/python-3.13.3
                        Ebuild: sys-libs/glibc-2.41
                        ...
                        Updated metadata.
 Syncing kb         ... Ebuild: acct-group/abrt-0
                        Ebuild: acct-group/adm-0
                        Ebuild: acct-group/audio-0
                        ...
                        Manifest: app-accessibility/at-spi2-core
                        Manifest: app-accessibility/brltty
                        ...
                        Updated prolog knowledgebase.

--- Syncing profile ---

 Saving knowledge base ... ok
```

During the knowledge base sync, every ebuild's metadata ---
dependencies, Use flags, keywords, slots, descriptions, manifests --- is
parsed and asserted as Prolog facts. The entire Gentoo repository (over
30,000 ebuilds) is held in memory as a native Prolog database, enabling
lightning-fast lookups without any disk I/O during reasoning.

SWI-Prolog's just-in-time (JIT) indexing further accelerates these
lookups. When a predicate like
`cache:entry_metadata(portage, 'app-editors/neovim-0.12.0', description, D)`
is first called, the runtime automatically builds hash indices on the
arguments that are bound. Subsequent calls with the same argument
pattern jump straight to matching clauses instead of scanning all
30,000+ entries linearly. This indexing is created on demand and updated
transparently as facts are asserted or retracted --- no manual index
declarations are needed.

Once syncing completes, the knowledge base is saved to disk using
SWI-Prolog's qcompile mechanism (`Knowledge/kb.qlf`). qcompile
serializes Prolog clauses into a compact binary format that can be
loaded back in a fraction of the time it takes to parse the original
source. On subsequent runs, portage-ng loads the `.qlf` file directly,
making startup near-instantaneous --- even for a repository with tens of
thousands of ebuilds.

== Running tests
<running-tests>
```bash
make test            # PLUnit tests
make test-overlay    # Overlay regression tests (80 scenarios)
```

See #link("23-doc-testing.md")[Chapter 23: Testing and Regression] for
details.

== Further reading
<further-reading-1>
- #link("03-doc-gentoo.md")[Chapter 3: Configuration] --- setting up
  Portage tree paths, `/etc/portage`, and profiles
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] --- full
  CLI reference
- #link("../Manpage/portage-ng.1.md")[`portage-ng(1)` manpage] ---
  exhaustive option reference

= Configuration
<configuration>
Dependency resolution only makes sense in #emph[your] environment: which
profile you use, which USE flags you set, which packages are already on
disk, and which extra trees you layered on top of Gentoo. portage-ng is
designed so you do not pay a "migration tax" to express any of that. It
reads the same files and databases as traditional Portage.

Configuration, in this chapter's sense, is the act of #strong[telling
portage-ng where your machine keeps that truth] (paths, repositories,
profile strategy) and #strong[which Gentoo-side files to honour]---so
the prover plans against the world you actually run, not a generic
default.

This chapter starts with the central configuration file (`config.pl`),
then shows how to register repositories and sync them into the knowledge
base, and finally covers the `/etc/portage/` files that control policy
(USE flags, masks, keywords).

== The configuration file
<the-configuration-file>
The central configuration file is `Source/config.pl`. It is a plain
Prolog source file --- every setting is a Prolog fact or rule that you
can read, query, or override. The file is organised into logical
sections; the most important ones for getting started are summarised
below.

=== General
<general>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:name/1`], [`'portage-ng-dev'`], [Program name shown in
    banners and logs.],
    [`config:hostname/1`], [\(auto-detected)], [Current hostname, used
    to select per-machine configuration.],
    [`config:installation_dir/1`], [\(from Prolog flag)], [Root of the
    portage-ng source tree. The knowledge base, certificates, and config
    files are resolved relative to this path.],
    [`config:number_of_cpus/1`], [\(auto-detected)], [Parallelism level
    for parsing, proving, and building.],
    [`config:verbosity/1`], [`debug`], [Verbosity level for runtime
    messages.],
  )]
  , kind: table
  )

=== Repository and metadata
<repository-and-metadata>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:trust_metadata/1`], [`true`], [When `true`, trust the
    repository-shipped md5-cache. When `false`, regenerate cache entries
    locally for every ebuild --- expensive, but useful for overlay
    development.],
    [`config:write_metadata/1`], [`true`], [Write on-disk cache entries
    for locally changed or new ebuilds during sync.],
  )]
  , kind: table
  )

=== Gentoo profile
<gentoo-profile>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:gentoo_profile/1`], [`'default/linux/amd64/23.0/...'`], [The
    Gentoo profile path relative to the Portage tree's `profiles/`
    directory. This must match the profile symlink on your Gentoo
    system.],
  )]
  , kind: table
  )

=== Profile loading strategy
<profile-loading-strategy>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:profile_loading/2`], [`standalone → live`], [Controls
    whether profile data is parsed from the Portage tree on every
    startup (`live`) or loaded from a pre-serialized cache (`cached`).
    Set per mode: standalone, daemon, worker, client, server.],
  )]
  , kind: table
  )

See #link(<profile-loading-strategy>)[Profile loading strategy] for
details on generating and using the profile cache.

=== Paths
<paths>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Setting]], [#strong[Purpose]],),
    table.hline(),
    [`config:portage_confdir/1`], [Path to the `/etc/portage` directory
    (or a development copy). Determines where `make.conf`,
    `package.use`, `package.mask`, etc. are read from. Comment out to
    use built-in fallback defaults.],
    [`config:pkg_directory/2`], [Per-hostname path to the VDB directory
    (`/var/db/pkg` on a standard Gentoo system).],
    [`config:world_file/1`], [Path to the world set file (auto-resolved
    from hostname).],
    [`config:graph_directory/2`], [Per-hostname output directory for
    generated dependency graphs and `.merge` files.],
    [`config:build_root/1`], [Root directory for build work (equivalent
    to Portage's `PORTAGE_TMPDIR`).],
    [`config:build_log_dir/1`], [Directory for per-package build logs.],
  )]
  , kind: table
  )

=== Machine selection
<machine-selection>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Setting]], [#strong[Purpose]],),
    table.hline(),
    [`config:systemconfig/1`], [Resolves the machine-specific
    configuration file. Looks for `Source/Config/<hostname>.local.pl`\;
    falls back to `Source/Config/default.pl` if not found.],
  )]
  , kind: table
  )

The machine config file is where repositories are created and registered
--- covered in the next section.

=== Proving
<proving>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:time_limit/1`], [`300` (seconds)], [Maximum time for a
    single proof/plan computation before aborting.],
    [`config:proving_target/1`], [`run`], [Proof depth: `install` for
    compile-time dependencies only, `run` to include runtime
    dependencies.],
    [`config:reprove_max_retries/1`], [`20`], [Maximum iterative
    learn-and-restart retries when the prover encounters conflicts.],
    [`config:avoid_reinstall/1`], [`false`], [When `true`, verify
    already-installed packages instead of re-merging them.],
  )]
  , kind: table
  )

=== Output
<output>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:default_printing_style/1`], [`'fancy'`], [Plan output
    style: `short`, `column`, or `fancy` (tree-structured with Unicode
    box drawing).],
    [`config:color_output/0`], [asserted], [ANSI colour in terminal
    output. Retract to disable.],
    [`config:color_palette/1`], [`full`], [Use flag colouring: `easy`
    (classic Portage red/blue) or `full` (reason-based, showing where
    each flag came from).],
  )]
  , kind: table
  )

=== Network (distributed mode)
<network-distributed-mode>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:server_host/1`], [`'mac-pro.local'`], [Server hostname for
    client-server mode.],
    [`config:server_port/1`], [`4000`], [HTTPS port for the Pengine
    server.],
    [`config:bonjour_service/1`], [`'_portage-ng._tcp.'`], [mDNS service
    name for automatic server/worker discovery.],
  )]
  , kind: table
  )

=== LLM integration (optional)
<llm-integration-optional>
LLM integration is entirely optional. If you do not need `--explain`,
`--chat`, or semantic search, the LLM modules can be removed from the
load graph without affecting core functionality (proving, planning,
building).

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:llm_default/1`], [`claude`], [Default LLM service for
    `--explain` and `--chat`.],
    [`config:llm_model/2`], [\(per service)], [Model version for each
    LLM provider (ChatGPT, Claude, Gemini, Ollama, etc.).],
    [`config:llm_use_tools/1`], [`true`], [Whether the LLM may execute
    Prolog code locally during a conversation.],
  )]
  , kind: table
  )

Most settings have sensible defaults. For a typical Gentoo system, the
main items to configure are `config:gentoo_profile/1`,
`config:portage_confdir/1`, and the repository definitions in the
machine config file.

== Configuring repositories
<configuring-repositories>
Not every literal in a proof refers to the same backing store.
portage-ng models #strong[several repository kinds] so the resolver can
combine "what exists upstream", "what is already installed", and "what I
added locally" without conflating them:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Name]], [#strong[Role]],),
    table.hline(),
    [`portage`], [The main Gentoo tree, backed by md5-cache --- the
    canonical source of buildable versions.],
    [`pkg`], [Installed packages (the VDB under `/var/db/pkg/`). Ground
    truth for what is already on the machine.],
    [`overlay`], [Additional ebuild trees (user overlays, testing repos,
    local layers), each with their own cache and sync rules.],
  )]
  , kind: table
  )

Each repository is a named #strong[OO instance] created with a directive
like:

```prolog
:- portage:newinstance(repository).
```

The name before `:newinstance` is the name you choose for the repository
--- `portage` here, but it could be anything:
`:- myoverlay:newinstance(repository).` would create a repository called
`myoverlay`. Each instance is specialised with a location, cache path,
remote URL, protocol, and type. This uses the same #strong[context-based
OO] machinery introduced in Chapter 1 (`Source/Logic/context.pl`): a
repository is an object that responds to `sync`, `find_metadata`,
`find_vdb_entry`, and so on, not a loose bag of paths.

#strong[Multiple repositories coexist in one proof.] If you registered
both `portage` and `myoverlay`, a dependency chain can span both: a
`portage://` literal may pull in a `myoverlay://` literal when only the
overlay carries a needed version. Installed packages participate too ---
a `pkg://` literal satisfies a runtime dependency without planning a
fresh merge. Keeping repositories separate avoids conflating "what is
available upstream", "what I added locally", and "what is already
installed", while still allowing the prover to relate them during
resolution.

Machine files in `Source/Config/` decide which of these instances exist
on your host; see #link(<machine-configuration>)[Machine configuration].

== Machine configuration
<machine-configuration>
Each machine has a configuration file under `Source/Config/` that
creates and registers repository instances. portage-ng looks for
`Source/Config/<hostname>.local.pl` first; if not found, it falls back
to `Source/Config/default.pl`.

A machine config file creates one or more repositories using
`newinstance`, initialises each with paths and a sync protocol, and
registers it with the knowledge base.

The five arguments to `init` are:

+ #strong[Local path] --- where the repository lives on disk.
+ #strong[Cache path] --- the md5-cache directory inside the repository.
+ #strong[Remote URL] --- the upstream to sync from.
+ #strong[Protocol] --- how to sync: `git`, `rsync`, or `http` (tarball
  download).
+ #strong[Type] --- the repository format: `eapi` for standard Gentoo
  ebuild trees.

The examples below show the supported options.

#strong[Portage tree via git] (the most common setup):

```prolog
:- portage:newinstance(repository).
:- portage:init('/usr/portage',
                '/usr/portage/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo',
                'git', 'eapi').
:- kb:register(portage).
```

#strong[Portage tree via rsync:]

```prolog
:- portage:newinstance(repository).
:- portage:init('/usr/portage',
                '/usr/portage/metadata/md5-cache',
                'rsync://rsync.gentoo.org/gentoo-portage',
                'rsync', 'eapi').
:- kb:register(portage).
```

#strong[Portage tree via HTTP snapshot:]

```prolog
:- portage:newinstance(repository).
:- portage:init('/usr/portage',
                '/usr/portage/metadata/md5-cache',
                'http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.bz2',
                'http', 'eapi').
:- kb:register(portage).
```

#strong[User overlay] (a second ebuild tree layered on top):

```prolog
:- myoverlay:newinstance(repository).
:- myoverlay:init('/var/db/repos/myoverlay',
                  '/var/db/repos/myoverlay/metadata/md5-cache',
                  '/var/db/repos/myoverlay/',
                  'rsync', 'eapi').
:- kb:register(myoverlay).
```

#strong[Local distfiles directory:]

```prolog
:- distfiles:newinstance(repository).
:- distfiles:init('/usr/portage/distfiles',
                  '', '', 'local', 'distfiles').
:- kb:register(distfiles).
```

Multiple repositories can be registered in the same file. During
proving, the resolver queries all registered repositories and
distinguishes them by their `portage://`, `pkg://`, or overlay prefix.

== Syncing the tree
<syncing-the-tree>
portage-ng does not crawl ebuild directories on every pretend merge. At
runtime it works from a #strong[compiled Prolog knowledge base] built
from the same #strong[md5-cache] files Portage uses: precomputed
metadata blobs (dependencies, slots, USE defaults, and so on) produced
by sourcing each ebuild through bash and extracting its declared
variables --- a process traditionally driven by Gentoo's `egencache`,
which writes the results under the repository's cache directory. Treat
the Portage tree, for resolver purposes, as #strong[a directory of cache
files] plus ebuilds; the cache is what makes bulk queries feasible.

```bash
portage-ng --sync
```

`--sync` is the umbrella operation that brings that picture up to date:
it syncs registered repositories (via git, rsync, or snapshot download),
regenerates on-disk metadata where configured, #strong[reloads]
md5-cache into dynamic Prolog facts (according to the structure defined
in `cache.pl`), and #strong[persists] the result to disk so subsequent
runs start near-instantaneously.

```bash
portage-ng --regen
```

`--regen` (alias `--metadata`) addresses a narrower problem:
#strong[refresh the on-disk md5-cache] without performing a network
sync. portage-ng can generate the md5-cache entirely on its own --- it
does not need traditional Portage or `egencache` for this step. Each
ebuild is sourced through bash and its metadata extracted in
incremental, parallel passes (see `repository:sync(metadata)` and
`config:trust_metadata/1` in the source). Traditional Portage is only
needed for the actual #emph[building] of packages, since portage-ng's
current focus is on the reasoning and planning side. Note that `--regen`
is not a substitute for loading facts into Prolog: after regenerating
the cache, run #strong[`--sync`] again so `Knowledge/kb.qlf` matches the
updated on-disk cache.

You can also sync a single repository by name:

```bash
portage-ng --sync myoverlay
```

This syncs only the `myoverlay` repository (and saves the knowledge base
afterwards). Useful when you have changed an overlay but the main Gentoo
tree is still up to date.

=== Repositories
<repositories>
In portage-ng's architecture, all repositories are registered with a
central #strong[knowledge base] (`knowledgebase.pl`). The command-line
interface talks to the knowledge base, which delegates sync operations
to each registered repository. After syncing the repositories, the
knowledge base also triggers a #strong[profile sync] --- this reads the
Gentoo profile directory (the chain of `make.defaults`, `package.mask`,
`use.mask`, etc. that define your system's baseline policy) and the
`/etc/portage/` user configuration files, loading them into `preference`
facts that the prover consults during resolution.

#figure(image("Diagrams/03-sync-architecture.svg", alt: "Sync architecture"),
  caption: [
    Sync architecture
  ]
)

The result is two serialised cache files:

- #strong[`Knowledge/kb.qlf`] --- all repository and cache facts
  (ebuilds, metadata, manifests).
- #strong[`Knowledge/profile.qlf`] --- all profile-derived data (USE
  terms, masks, per-package USE, license groups).

See #link(<profile-loading-strategy>)[Profile loading strategy] for
details on live vs.~cached profile loading.

=== Installed packages
<installed-packages>
To reason about what is already on the machine, portage-ng needs to know
which packages have been installed. Portage records this in the
#strong[VDB] (Var DataBase), a directory tree at `/var/db/pkg/` with one
subdirectory per installed `category/package-version`. Each subdirectory
contains metadata files that capture the state at install time:
dependency declarations (`DEPEND`, `RDEPEND`, `PDEPEND`), the active
`USE` flags, `SLOT`, `KEYWORDS`, compiler flags, a file manifest
(`CONTENTS`), and bookkeeping fields like `BUILD_TIME` and `SIZE`.

#figure(image("Diagrams/03-vdb-architecture.svg", alt: "VDB architecture"),
  caption: [
    VDB architecture
  ]
)

When `--sync` runs, the knowledge base syncs the `pkg` repository by
walking the VDB tree and loading each installed package into the same
in-memory fact structure used for available ebuilds. From that point on,
the prover queries installed and available packages through the same
interface --- the only difference is the prefix: `pkg://` for installed
packages, `portage://` for available ones.

This uniform representation means that during resolution, an
already-installed package can satisfy a dependency directly without
planning a fresh merge. In the plan output, these appear as `[nomerge]`
--- the prover verified the dependency is met by what is already on
disk.

== Gentoo configuration
<gentoo-configuration>
Gentoo users already curate policy in `/etc/portage/`: USE overrides,
masks, licences, and keywords. portage-ng #strong[reuses that
investment] --- it reads Gentoo's standard `/etc/portage/` configuration
files, making it a drop-in replacement for dependency resolution and
plan computation from a #emph[policy] perspective.

#figure(image("Diagrams/03-gentoo-files.svg", alt: "Gentoo on-disk files read by portage-ng"),
  caption: [
    Gentoo on-disk files read by portage-ng
  ]
)

The diagram shows the four on-disk sources portage-ng consults: user
configuration under `/etc/portage/`, the profile chain under the Portage
tree's `profiles/` directory, the installed-package database (VDB) under
`/var/db/pkg/`, and the Portage tree itself with its ebuilds and
md5-cache.

=== Supported files
<supported-files>
portage-ng recognises the following standard Gentoo configuration files.
Set `config:portage_confdir/1` in `Source/config.pl` to point at your
`/etc/portage` directory (or use the bundled templates under
`Source/Config/Gentoo/` during development).

#figure(
  align(center)[#table(
    columns: (40%, 60%),
    align: (left,left,),
    table.header([#strong[File]], [#strong[Purpose]],),
    table.hline(),
    [`make.conf`], [Global environment variables (USE flags, keywords,
    licenses, etc.).],
    [`package.use`], [Per-package USE flag overrides.],
    [`package.mask`], [User package masks.],
    [`package.unmask`], [Overrides profile-level masks.],
    [`package.accept_keywords`], [Per-package keyword acceptance.],
    [`package.license`], [Per-package license acceptance.],
  )]
  , kind: table
  )

All files are read from the directory set by `config:portage_confdir/1`
(typically `/etc/portage/`).

These files use standard Gentoo syntax, so existing `/etc/portage/`
directories work without modification.

=== File format
<file-format>
All files follow standard Gentoo syntax:

- Lines starting with `#` are comments
- Empty lines are ignored
- Inline `#` comments are stripped

==== make.conf
<make.conf>
Bash-style `KEY="value"` assignments. Parsed by the same engine that
reads profile `make.defaults` files (`profile:make_defaults_kv/2`).

```bash
USE="X alsa dbus -systemd"
ACCEPT_KEYWORDS="~amd64"
VIDEO_CARDS="intel"
```

==== package.use / package.accept\_keywords / package.license
<package.use-package.accept_keywords-package.license>
One entry per line: a package atom followed by space-separated values.

```
# package.use
app-editors/vim        -X
>=sys-libs/gdbm-1.26   berkdb

# package.accept_keywords
=sys-apps/portage-3.0  ~amd64
dev-util/pkgdev        **

# package.license
app-text/calibre       BSD
```

==== package.mask / package.unmask
<package.mask-package.unmask>
One package atom per line (simple `cat/pkg` or versioned like
`>=cat/pkg-1.0`).

```
sys-apps/systemd
>=dev-lang/python-3.13
```

=== Directory layout
<directory-layout>
All `package.*` files support both single-file and directory layouts,
matching Portage's convention:

```
/etc/portage/package.use           ← single file
/etc/portage/package.use/          ← directory
/etc/portage/package.use/custom    ← files read in sorted order
/etc/portage/package.use/gaming
```

When the path is a directory, all non-hidden files in it are read in
sorted (lexicographic) order.

=== Template files
<template-files>
For development without a real Gentoo system, portage-ng ships template
configuration files in `Source/Config/Gentoo/`:

```
Source/Config/Gentoo/
  ├── make.conf
  ├── package.use
  ├── package.mask
  ├── package.unmask
  ├── package.accept_keywords
  └── package.license
```

These contain commented examples that mirror a typical Gentoo setup. On
a real Gentoo system, point `config:portage_confdir/1` directly at
`/etc/portage` instead.

== Precedence
<precedence>
When the same setting appears in more than one place, portage-ng
resolves it by checking sources from most specific to most general. The
first match wins. For environment-like settings such as use flags,
keywords, licenses, etc., the lookup order is:

+ #strong[Command-line environment variables] --- values passed on the
  command line override everything else.
+ #strong[make.conf] --- your `/etc/portage/make.conf` settings come
  next.
+ #strong[Configuration templates] --- defaults provided by the
  portage-ng configuration templates (under `Source/Config/Gentoo/`).
  These serve as a development baseline when no real `/etc/portage/` is
  configured.
+ #strong[Built-in defaults] --- hard-coded baseline values when nothing
  else is specified.

Package masks and per-package USE overrides follow a similar layering.
Gentoo's profile tree is applied first (the chain of `package.mask`,
`package.use`, `use.mask`, and `use.force` files that define baseline
policy for your chosen profile). Your `/etc/portage/` files are applied
on top, so they can override profile-level decisions. Finally, fallback
defaults fill in anything left unspecified.

In practice this means your `/etc/portage/` customisations always take
priority over profile defaults, and anything you pass on the command
line takes priority over both.

== Profile loading strategy
<profile-loading-strategy-1>
Profile data (USE flags, masks, per-package USE, license groups) can be
loaded in two ways each time portage-ng starts:

- #strong[Live] --- the Gentoo profile tree is parsed from disk on every
  startup. This is the most accurate option because it always reflects
  the latest state of the profile, but it takes a moment longer to
  start.
- #strong[Cached] --- profile data is loaded from a pre-serialized cache
  file (`Knowledge/profile.qlf`). This makes startup near-instantaneous,
  but the cache must be regenerated (via `--sync`) whenever the profile
  changes.

The strategy is set per operating mode in `config.pl`. portage-ng
supports several modes of operation (standalone, daemon, worker, client,
server --- see
#link("14-doc-cli.md")[Chapter 14: Command-Line Interface] for details).
Each mode can use a different loading strategy:

```prolog
config:profile_loading(standalone, live).
config:profile_loading(daemon,     cached).
config:profile_loading(worker,     cached).
config:profile_loading(client,     live).
config:profile_loading(server,     cached).
```

If the cached strategy is set but `Knowledge/profile.qlf` does not exist
yet, portage-ng falls back to live loading automatically.

=== Generating the profile cache
<generating-the-profile-cache>
The `--sync` command generates `Knowledge/profile.qlf` automatically:

```bash
portage-ng --sync
```

After syncing all repositories, portage-ng walks the profile tree once
and serializes all profile-derived data to disk. Subsequent runs that
use the `cached` strategy load this file instead of re-parsing the
profile tree.

=== What gets cached
<what-gets-cached>
The profile cache captures the following data so it does not need to be
re-derived from the profile tree on each startup:

#figure(
  align(center)[#table(
    columns: (31.58%, 68.42%),
    align: (left,left,),
    table.header([#strong[Data]], [#strong[Source files]],),
    table.hline(),
    [USE flag defaults], [`make.defaults` along the profile chain],
    [USE masks and forced flags], [`use.mask`, `use.force`],
    [Package masks], [`package.mask`, `package.unmask`],
    [Per-package USE overrides], [`package.use`],
    [Per-package USE masks and forced flags], [`package.use.mask`,
    `package.use.force`],
    [License groups], [`license_groups`],
  )]
  , kind: table
  )

== World sets
<world-sets>
portage-ng maintains world sets --- the list of packages explicitly
requested by the user --- under `Source/Knowledge/Sets/world/`. Each
machine can have its own `.local` world set file. The `@world` target
resolves to all packages in the active world set. The format is the same
as Gentoo's `/var/lib/portage/world`, so you can point portage-ng at
your Gentoo system's world file and use Portage and portage-ng side by
side.

World set management is handled through the `set.pl` module, which
supports `world(Atom):register` and `world(Atom):unregister` proof
literals to add/remove packages during `--merge` operations.

After you change world membership or sync new tree data, rely on the
same #strong[sync workflow] described above: a standalone
#strong[`--sync`] refreshes `Knowledge/kb.qlf` (and the profile cache)
so resolution sees an up-to-date union of tree, VDB, and world-related
facts.

== Further reading
<further-reading-2>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- prerequisites and first run
- #link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache]
  --- how the Portage tree is loaded into Prolog facts
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] --- CLI
  options that interact with configuration

= Architecture Overview
<architecture-overview>
Reasoning about software configurations is not a single algorithm you
"run once." It is a chain of transformations: turn repository facts into
a logical problem, search for a proof that explains #emph[why] each step
is needed, turn that proof into an ordered plan, and finally render or
execute it. portage-ng is structured as a #strong[pipeline] because that
sequence is the natural shape of the work. Each stage has a clean
role---parse facts, prove a plan, schedule it, print (or build) it---and
can be characterized in isolation: the reader produces a fixed
vocabulary of literals; the prover produces a justified partial order of
dependencies; the planner and scheduler refine that into something a
human or a build system can follow. Treating the system as a pipeline is
therefore a #strong[design decision]: it keeps stages testable,
replaceable, and easier to reason about than a monolith where parsing,
search, ordering, and output are tangled together.

== The pipeline
<the-pipeline>
portage-ng processes a user request through a linear pipeline of six
stages:

#figure(image("Diagrams/04-pipeline-overview.svg", alt: "Pipeline overview"),
  caption: [
    Pipeline overview
  ]
)

```
reader/parser  →  prover  →  planner  →  scheduler  →  printer  →  builder
                  └──────── pipeline ────────┘
```

The prover produces four AVL trees --- #strong[Proof], #strong[Model],
#strong[Constraints], and #strong[Triggers] --- that flow through the
rest of the pipeline. Together they capture #emph[why] each literal was
accepted, #emph[what] is known, #emph[what restrictions] must hold, and
#emph[who depends on whom]. Section
#link(<data-structures>)[Data structures] describes each one in detail.

The prover, planner, and scheduler together form the `pipeline` module.
The standard entry point is:

```prolog
pipeline:prove_plan(Goals, Proof, Model, Plan, Triggers)
```

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Stage]], [#strong[Module]], [#strong[Input]], [#strong[Output]],),
    table.hline(),
    [#strong[Reader / Parser]], [`reader.pl`, `parser.pl`,
    `eapi.pl`], [Ebuild md5-cache files], [Prolog facts
    (`cache:entry/5`)],
    [#strong[Prover]], [`prover.pl`], [Goal literals (from
    user)], [Proof, Model, Constraints, Triggers],
    [#strong[Planner]], [`planner.pl`, `kahn.pl`], [Proof,
    Triggers], [Plan + Remainder],
    [#strong[Scheduler]], [`scheduler.pl`], [Plan, Remainder], [Plan
    (with SCC merge-sets)],
    [#strong[Printer]], [`printer.pl`, `Printer/`], [Proof, Model,
    Plan], [Terminal output, `.merge` files],
    [#strong[Builder]], [`builder.pl`, `Builder/`], [Plan], [Ebuild
    phase execution],
  )]
  , kind: table
  )

== Operating modes
<operating-modes>
portage-ng can run in several modes, each tailored to a different
deployment scenario. The mode determines which modules are loaded, how
the knowledge base is accessed, and whether proving happens locally or
is distributed across machines. The mode is selected with `--mode` on
the command line (e.g.~`portage-ng --mode server`). When no mode is
specified, standalone is used.

=== Standalone
<standalone>
The default and most common mode. A single process on a single machine
loads the full knowledge base, runs the complete pipeline (prover,
planner, scheduler, printer, builder), and produces results locally.
This is what you use for day-to-day `--pretend`, `--merge`, `--shell`,
and `--sync`.

#figure(image("Diagrams/04-mode-standalone.svg", alt: "Standalone mode"),
  caption: [
    Standalone mode
  ]
)

Everything happens in one process: the Portage tree, VDB, and
`/etc/portage/` configuration are synced into the knowledge base, and
the user's goal literals are proven, planned, and printed --- all on the
same machine.

=== Client and server
<client-and-server>
In client--server mode, the reasoning happens on a powerful server while
a lightweight client submits requests and displays results. The client
and server communicate over TCP/IP with SSL encryption (HTTPS), so they
can run on different machines --- potentially on different networks.

#figure(image("Diagrams/04-mode-clientserver.svg", alt: "Client–server mode"),
  caption: [
    Client--server mode
  ]
)

The server hosts the knowledge base and runs the full pipeline. The
client needs only the thin slice of printing and pipeline glue required
to render output. This makes client--server mode ideal for
#strong[embedded systems] and resource-constrained devices: the client
binary is small, uses minimal memory, and delegates all proving to the
server. Queries return in milliseconds because the knowledge base is
already loaded and indexed on the server side.

=== Daemon / IPC
<daemon-ipc>
Daemon mode is similar to standalone, but the process stays resident and
listens on a Unix socket for commands from local processes. Both the
daemon and its clients run on the #strong[same machine].

#figure(image("Diagrams/04-mode-daemon.svg", alt: "Daemon / IPC mode"),
  caption: [
    Daemon / IPC mode
  ]
)

The key advantage is #strong[startup performance]. In standalone mode,
every invocation loads the full knowledge base from disk --- tens of
thousands of Prolog facts --- before it can answer a single query. In
daemon mode, the knowledge base is loaded #strong[once] when the daemon
starts and stays in memory. Subsequent queries arrive over the Unix
socket and are answered in #strong[milliseconds], because there is no
parsing, no qcompile loading, no JIT indexing warmup --- just a direct
query against the already-loaded, already-indexed knowledge base. This
makes daemon mode well suited for interactive tooling, editor
integrations, and scripts that issue many small queries in quick
succession.

=== Workers
<workers>
Worker mode enables #strong[distributed proving] across multiple
machines. A central server advertises itself via #strong[Bonjour]
(mDNS/DNS-SD), and workers on the local network automatically discover
it without manual configuration.

#figure(image("Diagrams/04-mode-workers.svg", alt: "Worker mode"),
  caption: [
    Worker mode
  ]
)

Each worker machine maintains its own local copy of the Portage tree
(typically via a #strong[git snapshot]) and runs `--sync` locally to
build its own knowledge base. This ensures all workers reason against
the same set of ebuilds --- tree synchronisation is a prerequisite for
consistent results across the cluster.

Once a worker discovers the server, it polls the job queue for proving
tasks: the server breaks a large proof (e.g.~`@world`) into independent
sub-goals, distributes them to available workers, and collects the
results. Each worker runs the full pipeline locally (prover, planner,
scheduler), so proving scales horizontally --- adding more worker
machines reduces wall-clock time for large proof sets.

See #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] for the
full mode reference and
#link("17-doc-tls-certificates.md")[Chapter 17: Distributed Proving] for
TLS certificate setup and cluster configuration.

== Module load order
<module-load-order>
Each mode loads only the modules it needs. This keeps startup time,
memory footprint, and failure modes appropriate to the deployment:

The load order is defined in `Source/loader.pl`. Each operating mode
loads a different subset of modules:

```
load_common_modules        — SWI-Prolog libraries, OO context, config, OS,
                             interface, EAPI, reader, subprocess, bonjour,
                             feature unification, daemon

load_standalone_modules    — Full pipeline: KB (cache, repository, query),
                             Gentoo domain (version, rules, ebuild, VDB,
                             preference), prover, planner, scheduler,
                             printer, builder, grapher, writer, test

load_server_modules        — HTTP server, Pengines, sandbox

load_client_modules        — HTTP/socket client, subset of printer/pipeline

load_worker_modules        — Same pipeline as standalone + client + cluster

load_llm_modules           — LLM provider backends, explain, semantic search
```

== Domain-agnostic core vs Gentoo-specific rules
<domain-agnostic-core-vs-gentoo-specific-rules>
Traditional Portage couples the resolver tightly to Gentoo semantics:
USE flags, slots, profiles, and cache layout are not optional
details---they are woven through the same code paths as the search
strategy. That makes it hard to test "the resolver" without dragging the
entire domain along, and hard to experiment with alternative rule sets
or other package ecosystems.

portage-ng deliberately #strong[separates] a domain-agnostic core from a
Gentoo-specific rules layer. The prover does not know what a USE flag
#emph[is]. It sees abstract literals and Horn-style rules; expanding a
goal means calling a single hook-shaped interface and continuing the
search. The same engine could, in principle, reason about RPM packages,
Nix derivations, or Cargo crates---you would supply different `rule/2`
implementations and a different knowledge base, not a different prover.
That separation is intentional: it isolates #emph[how we search] from
#emph[what Gentoo means], so the core can be exercised and compared
without re-implementing Portage wholesale. Packages, USE flags, and
slots never appear as primitives in the core; they are interpreted
entirely inside the rules layer:

#figure(image("Diagrams/04-layer-separation.svg", alt: "Layer separation"),
  caption: [
    Layer separation
  ]
)

The #strong[`rule/2` interface] is the contract between the
domain-agnostic core and the domain-specific layer. Everything
Gentoo-specific---consulting the knowledge base, evaluating USE
conditionals, resolving candidates, emitting constraint terms---lives on
the far side of that boundary.

```prolog
rules:rule(Head, Body)
```

The prover calls `rule/2` to expand a literal into its dependencies. The
rules module implements this by consulting the knowledge base,
evaluating USE conditionals, resolving candidates, and emitting
constraint terms.

This separation means the same reasoning engine could be applied to a
different domain by supplying a different set of rules.

== Data structures
<data-structures>
#figure(image("Diagrams/04-data-structures.svg", alt: "Data structures"),
  caption: [
    Data structures
  ]
)

During proof search, the prover must answer four kinds of question at
once: #emph[why] was this literal accepted, #emph[what] is already
known, #emph[what restrictions] must remain consistent across branches,
and #emph[who depends on whom] when context or assumptions change. Four
balanced trees (AVL maps via `library(assoc)`) hold exactly those roles.
Together they capture the #strong[complete state] of a proof attempt:
the prover threads them through recursive expansion without relying on a
soup of unrelated global mutable flags for "current model" or "current
explanation."

- #strong[Proof] --- Records #emph[why] each literal was proven: the
  justification (which rule instance and body linked the head). Without
  it, you cannot explain the plan or reconstruct the dependency argument
  for the user.
- #strong[Model] --- Records #emph[what] has been proven: the current
  state of knowledge (each literal and its proof-term context). This is
  the structure that memoizes success: the same literal is not re-proved
  from scratch along every path.
- #strong[Constraints] --- Records #emph[restrictions] that must hold:
  version domains, slot locks, blockers, and similar invariants. They
  cross-cut the proof tree; they are not local to a single rule
  application.
- #strong[Triggers] --- Records #emph[which heads depend on which
  bodies]---a reverse-dependency index. When a context changes or
  delayed work fires, the prover uses triggers to find "who cares" about
  that body without scanning the entire proof.

The prover maintains these four structures during proof construction:

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Structure]], [#strong[Key]], [#strong[Value]], [#strong[Purpose]],),
    table.hline(),
    [#strong[Proof]], [`rule(Lit)` or
    `assumed(rule(Lit))`], [`dep(N, Body)`], [Which rule and body
    justified each literal; `N` is the dependency count],
    [#strong[Model]], [`Lit` or `assumed(Lit)`], [proven], [Every
    literal that has been established],
    [#strong[Constraints]], [e.g.~`cn_domain(dev-libs, openssl, 0)`], [`version_domain(...)`], [Accumulated
    invariants: version domains, slot locks (`slot(3)`), blockers],
    [#strong[Triggers]], [body
    literal], [`[head, ...]`], [Reverse-dependency index: which heads
    depend on this body literal],
  )]
  , kind: table
  )

The Proof and Model structures use different key schemes to distinguish
normal proofs from assumptions:

- `rule(Lit)` --- normally proven literal
- `assumed(rule(Lit))` --- prover cycle-break assumption
- `rule(assumed(Lit))` --- domain assumption (dependency cannot be
  satisfied)

See #link("05-doc-proof-literals.md")[Chapter 5: Proof Literals] for the
literal format and
#link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions] for the
assumption taxonomy.

== Architecture diagram
<architecture-diagram>
The following page shows the full system architecture in landscape
orientation, covering all layers from external inputs through the
knowledge base, prover, planner, and output pipeline.

#page(flipped: true, margin: (left: 15mm, right: 15mm, top: 20mm, bottom: 20mm))[
  #set text(size: 9pt)
  #align(center + horizon)[
    #text(font: "Helvetica Neue", size: 14pt, weight: "bold")[portage-ng: Full System Architecture]
    #v(8pt)
    #image("Diagrams/04-architecture-full.svg", width: 100%, height: auto, fit: "contain")
  ]
]
== Further reading
<further-reading-3>
- #link("05-doc-proof-literals.md")[Chapter 5: Proof Literals] --- the
  `Repo://Entry:Action?{Context}` term format
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- inductive proof
  search in detail
- #link("12-doc-planning.md")[Chapter 12: Planning and Scheduling] ---
  wave planning and SCC decomposition

= Proof Literals
<proof-literals>
== The universal literal format
<the-universal-literal-format>
Every term that flows through the portage-ng pipeline --- from rules to
prover to planner to printer --- uses the same universal format:

```
Repo://Entry:Action?{Context}
```

Each component answers a question that arises at a different stage of
the pipeline:

- #strong[`Repo`] --- #emph[where] does this fact come from? The
  #strong[rules] consult different repositories (the Portage tree, the
  VDB, an overlay) and the repository prefix travels with the literal so
  the prover never confuses an available package with an installed one.

- #strong[`Entry`] --- #emph[what] package version is meant? When the
  rules expand a dependency, they select a concrete cache entry
  (`'category/name-version'`). This identifier is the key the
  #strong[prover] uses to look up and store proof work --- two
  dependency paths that resolve to the same entry share the same proof
  node.

- #strong[`Action`] --- #emph[how] should the pipeline treat this entry?
  The rules assign an action (`:install`, `:run`, `:download`,
  `:update`, …) that tells the #strong[planner] which phase of work this
  literal represents and how to order it relative to others.

- #strong[`Context`] --- #emph[why] and #emph[under what conditions] was
  this literal introduced? As the prover expands the dependency graph,
  each literal accumulates a feature-term context: which parent
  introduced it (`self`), which USE flags are required
  (`build_with_use`), ordering constraints (`after`), slot locks, and so
  on. At join points where two dependency paths reach the same literal,
  the prover #strong[merges] their contexts via feature unification. The
  #strong[printer] reads the final context to display USE flags, slot
  information, and assumption reasons.

Traditional resolvers scatter this information across separate side
structures. portage-ng packs it into the literal itself, making every
term #strong[self-describing]: you can inspect a single literal and know
its repository, version, phase, and full provenance without consulting
external tables.

== Operator precedences
<operator-precedences>
The literal format is defined by three infix operators declared in
`Source/Logic/context.pl`. In SWI-Prolog, #strong[higher] precedence
means the operator becomes the #strong[principal functor] at that level
of the term --- i.e.~it sits #strong[higher] in the parse tree. The
ordering `://` (603) #strong[\>] `?` (602) #strong[\>] `:` (601) was
chosen so that the structure lines up with everyday use: you scope by
#strong[repository] first, then attach the #strong[context list] to the
#strong[ebuild core] (`Entry:Action`), with #strong[entry] and
#strong[action] paired at the innermost level. That makes the common
cases --- "everything in `portage`", or "this `category/name-version`
with this phase" --- parse in the way you read them. The `?{Context}`
annotation is intentionally the outer wrapper around the core (after
`://`) because #strong[context is what changes most often during proof
search]\; the repository and entry/action spine stay stable while USE,
ordering, and constraint features are merged and refined.

#figure(
  align(center)[#table(
    columns: 4,
    align: (left,left,left,left,),
    table.header([#strong[Operator]], [#strong[Precedence]], [#strong[Associativity]], [#strong[Parses
      as]],),
    table.hline(),
    [`://`], [603], [xfx], [`Repo :// Rest`],
    [`?`], [602], [xfx], [`Core ? {Context}`],
    [`:`], [601], [xfx], [`Entry : Action`],
  )]
  , kind: table
  )

Because `://` has the highest precedence, a full literal parses as:

```
Repo :// ((Entry : Action) ? {Context})
```

That is: repository scopes the whole term; the ebuild core is
`Entry : Action`\; the context list attaches to that core.

== `Repo` --- the repository
<repo-the-repository>
The leftmost component identifies which registered repository the
literal belongs to. It is an atom --- the same atom used when
registering the repository with the knowledge base:

```prolog
:- portage:newinstance(repository).
:- kb:register(portage).
```

Common repository atoms:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Atom]], [#strong[Meaning]],),
    table.hline(),
    [`portage`], [The main Gentoo Portage tree],
    [`pkg`], [The VDB (installed packages database)],
    [`overlay`], [A user or test overlay],
  )]
  , kind: table
  )

Literals from different repositories can coexist in the same proof. For
example, a `portage://...` literal might depend on a `pkg://...` literal
when an installed package satisfies a dependency.

== `Entry` --- the cache entry
<entry-the-cache-entry>
The middle component is the cache entry identifier --- a quoted atom in
the format `'category/name-version'`:

```
'sys-apps/portage-3.0.77-r3'
'dev-lang/python-3.13.2'
```

This atom maps directly to the second argument of `cache:entry/5`:

```prolog
cache:entry(portage, 'sys-apps/portage-3.0.77-r3', 'sys-apps', 'portage',
            version([3,0,77],'',...)).
```

The category, name, and version are also available as separate fields in
the cache, but the combined atom serves as the unique key for lookup.

== `Action` --- the phase
<action-the-phase>
The component after the entry (inside the `Entry : Action` pair)
specifies what operation the literal represents. Actions fall into three
categories:

=== Ebuild actions
<ebuild-actions>
These apply to `Repo://Entry` literals:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Action]], [#strong[Meaning]],),
    table.hline(),
    [`run`], [Full installation + runtime availability],
    [`install`], [Build and install (DEPEND + BDEPEND + RDEPEND)],
    [`download`], [Fetch source archives],
    [`fetchonly`], [Fetch only, do not build],
    [`reinstall`], [Reinstall an already-installed package],
    [`update`], [Update to a newer version],
    [`downgrade`], [Downgrade to an older version],
    [`upgrade`], [Upgrade (used in VDB context)],
    [`depclean`], [Remove an unneeded package],
    [`uninstall`], [Uninstall a package],
  )]
  , kind: table
  )

=== Dependency and validation actions
<dependency-and-validation-actions>
Before the prover can expand a package's full dependency tree, it first
needs to answer two questions: #emph[which dependencies are actually
active] given the package's USE flags, and #emph[is the USE
configuration itself consistent]? These questions are answered in two
dedicated phases --- `:config` and `:validate` --- that run
#strong[before] the main `:install` / `:run` expansion.

==== The `:config` phase --- computing the dependency model
<the-config-phase-computing-the-dependency-model>
When portage-ng resolves a package, it does not immediately try to prove
every dependency listed in the ebuild's metadata. Instead, it first
builds a #strong[dependency model]: a stable snapshot of which
dependencies are active under the current USE flag configuration.

An ebuild's metadata contains conditional dependencies guarded by USE
flags. For example, `dev-lang/python` might declare:

```
RDEPEND="ssl? ( dev-libs/openssl )
         readline? ( sys-libs/readline )
         !readline? ( sys-libs/libedit )"
```

The `:config` phase evaluates each dependency term against the effective
USE flags and retains only the #strong[active] dependencies. In the
example above, if `ssl` is enabled and `readline` is disabled, the model
will contain `dev-libs/openssl` and `sys-libs/libedit` --- the
`sys-libs/readline` dependency is dropped because its USE guard is not
satisfied. Self-references (a package listing itself as a dependency)
are silently skipped.

When a choice group or constraint forces a decision, the prover may also
#strong[assume] a flag --- for instance, if an `exactly_one_of` group
requires at least one member to be enabled and none currently is, the
prover picks the most likely candidate and records a domain assumption
so the user is informed.

The result is a #strong[model] whose keys are the surviving dependency
terms --- the ones that actually need resolving.

For choice groups (OR dependencies), the `:config` phase picks one
viable alternative:

```
RDEPEND="|| ( dev-db/postgresql dev-db/mariadb dev-db/sqlite )"
```

becomes a `choice_group(Deps):config?{Context}` literal. The rules try
each alternative, preferring already-installed packages, and commit to
one choice. The chosen dependency enters the model; the others are
discarded. This means that by the time the main proof begins, every OR
group has been resolved to a single concrete dependency.

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Action]], [#strong[Literal
      head]], [#strong[Meaning]],),
    table.hline(),
    [`config`], [grouped dependency], [Resolve a dependency group under
    USE flags],
    [`config`], [package dependency], [Check a single dependency],
    [`config`], [choice group], [Pick one alternative from an OR group],
    [`config`], [USE conditional], [Evaluate a USE-guarded block],
  )]
  , kind: table
  )

==== The `:validate` phase --- checking REQUIRED\_USE consistency
<the-validate-phase-checking-required_use-consistency>
Ebuilds can declare constraints on which USE flag combinations are
valid. For example:

```
REQUIRED_USE="^^ ( python_targets_python3_12 python_targets_python3_13 )"
```

This says "exactly one Python target must be selected." The `^^`
operator translates to an `exactly_one_of_group(...)` term. Before
expanding the package's dependencies, portage-ng wraps each
REQUIRED\_USE constraint as a `:validate` literal:

```prolog
exactly_one_of_group([required(python_targets_python3_12),
                      required(python_targets_python3_13)]):validate?{[
  self(portage://'dev-lang/python-3.13.2')
]}
```

The rules check whether the effective USE flags for the package
(identified by the `self(...)` context tag) satisfy the constraint. For
`exactly_one_of`, the check counts how many of the listed flags are
enabled and verifies the count is exactly one. If the constraint is
violated, the rules emit a domain assumption recording the conflict:

```prolog
assumed(conflict(required_use, exactly_one_of_group(Deps)))
```

The full set of REQUIRED\_USE operators:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Operator]], [#strong[Group
      term]], [#strong[Constraint]],),
    table.hline(),
    [`^^`], [`exactly_one_of_group(Deps)`], [Exactly one flag enabled],
    [any-of], [`any_of_group(Deps)`], [At least one flag enabled],
    [`??`], [`at_most_one_of_group(Deps)`], [At most one flag enabled],
    [\(none)], [`use_conditional_group(...)`], [Conditional: if A then
    B],
  )]
  , kind: table
  )

Each of these operators is wrapped as a `:validate` literal and checked
against the package's effective USE flags:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Action]], [#strong[Literal
      head]], [#strong[Meaning]],),
    table.hline(),
    [`validate`], [`exactly_one_of_group(...)`], [Check `^^`
    constraint],
    [`validate`], [`any_of_group(...)`], [Check any-of constraint],
    [`validate`], [`at_most_one_of_group(...)`], [Check `??`
    constraint],
  )]
  , kind: table
  )

=== Non-ebuild literal heads
<non-ebuild-literal-heads>
Some literals do not follow the `Repo://Entry` pattern:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Literal]], [#strong[Meaning]],),
    table.hline(),
    [`world(Atom):register`], [Add a package to the \@world set],
    [`world(Atom):unregister`], [Remove a package from the \@world set],
    [`target(Query, Arg):run`], [Top-level target resolution],
    [`target(Query, Arg):fetchonly`], [Top-level fetch-only target],
    [`target(Query, Arg):uninstall`], [Top-level uninstall target],
  )]
  , kind: table
  )

== `Context` --- the feature-term list
<context-the-feature-term-list>
The context is a Prolog list wrapped in `{}` and attached via the `?`
operator. It carries per-literal metadata that records provenance,
ordering, constraints, and USE requirements:

```prolog
portage://'dev-lang/python-3.13.2':install?{[
  self(portage://'sys-apps/portage-3.0.77-r3'),
  build_with_use:use_state([ssl, threads], []),
  after(portage://'sys-apps/portage-3.0.77-r3':install)
]}
```

Reading this literal: "install `dev-lang/python-3.13.2` from the portage
repository, because `sys-apps/portage` needs it (`self`), with USE flags
`ssl` and `threads` enabled (`build_with_use`), and schedule it after
the installation of `sys-apps/portage` (`after`)."

The context list is #strong[not] an unstructured bag of annotations. It
is the proof-side counterpart of #strong[feature terms] in the sense
used by Zeller-style feature logic (see
#link("20-doc-context-terms.md")[Chapter 20: Context Terms]): a
structured collection of features that can be #strong[merged] when two
dependency paths describe the same package under different conditions.
When two paths reach the same literal with different USE requirements or
other features, the prover does not arbitrarily pick one path's context
--- it #strong[combines] them using feature term unification
(`sampler:ctx_union/3`), which relies on the same feature machinery as
the rest of the context subsystem. That is why context lives in a
dedicated suffix of the literal: it is the part that must stay open to
#strong[merge] and #strong[refine] as the proof graph grows.

=== `self` --- who introduced this dependency
<self-who-introduced-this-dependency>
Every dependency in an ebuild comes from somewhere. The
`self(Repo://Entry)` tag records #emph[which package] introduced this
literal as a dependency. When the rules expand a package's dependency
list, they stamp every child literal with the parent's identity:

```prolog
portage://'dev-libs/openssl-3.4.1':install?{[
  self(portage://'dev-lang/python-3.13.2')
]}
```

This says "openssl is here because python depends on it." The `self` tag
serves three purposes:

+ #strong[Provenance tracking.] The printer can show #emph[why] a
  package appears in the plan --- who pulled it in.

+ #strong[USE flag resolution.] When checking whether a USE flag is
  enabled for a dependency, the rules look up the effective USE flags of
  the ebuild identified by `self`. This is how the `:validate` phase
  works: the `self` tag tells the REQUIRED\_USE checker which package's
  USE configuration to consult.

+ #strong[Self-dependency detection.] When a package lists itself as a
  dependency (which happens in practice), the rules recognise this by
  comparing the dependency target to the `self` entry, and skip circular
  resolution.

At most one `self` tag is present per context. When a literal is
stamped, any previous `self` is replaced --- the immediate parent is
what matters.

=== `build_with_use` --- requirements imposed by parent
<build_with_use-requirements-imposed-by-parent>
Gentoo dependency atoms can carry #emph[bracketed USE requirements]:
conditions that must hold on the dependency target. For example, in
`sys-apps/portage`'s metadata:

```
RDEPEND="dev-lang/python[ssl,threads]"
```

The brackets `[ssl,threads]` mean "I need python, and it must be built
with the `ssl` and `threads` USE flags enabled." The rules translate
this into a `build_with_use` context tag:

```prolog
portage://'dev-lang/python-3.13.2':install?{[
  build_with_use:use_state([ssl, threads], [])
]}
```

The `use_state(Enabled, Disabled)` term lists which flags must be on and
which must be off. Negative requirements like `[-test]` appear in the
disabled list:

```prolog
build_with_use:use_state([], [test])
```

When two dependency paths reach the same package with different USE
requirements, the prover merges them via feature unification. If portage
requires `python[ssl]` and another package requires `python[xml]`, the
merged context becomes:

```prolog
build_with_use:use_state([ssl, xml], [])
```

If two paths disagree --- one requires `[debug]` and another requires
`[-debug]` --- the unification detects the conflict and the constraint
system handles it (potentially triggering a reprove with different
candidate selection).

The `build_with_use` tag is distinct from the package's own USE flags. A
package's USE flags are determined by profile, user configuration, and
defaults. The `build_with_use` tag captures what #emph[other packages
demand of this package]. The printer reads both to display the final USE
flag set, marking flags that were pulled in by dependency requirements.

=== `after` --- ordering constraints
<after-ordering-constraints>
The planner needs to know the order in which actions should be
scheduled. The `after(Literal)` tag expresses a hard ordering
constraint: "this literal must come after the specified literal in the
final plan."

```prolog
portage://'dev-lang/python-3.13.2':download?{[
  after(portage://'sys-apps/portage-3.0.77-r3':install)
]}
```

Ordering constraints arise naturally from the dependency structure. When
package A depends on package B, the rules add `after(B:install)` to A's
download and dependency contexts. This ensures that B is installed
before A starts building.

The `after` tag #strong[propagates]: when it is set on a literal, it is
also injected into that literal's own children. If A must come after B,
then A's dependencies also implicitly come after B. This transitive
propagation ensures that entire subtrees are correctly ordered.

For cases where ordering should #emph[not] propagate, the `after_only`
variant exists. This is used primarily for PDEPEND (post-dependencies):
a package's post-dependencies must come after the package itself, but
the post-dependency's own children should not inherit that ordering
constraint.

```prolog
after_only(portage://'app-editors/neovim-0.12.0':run)
```

The planner reads both `after` and `after_only` from every literal's
context to build the dependency edges that drive Kahn's topological
sort.

=== Summary of context tags
<summary-of-context-tags>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Tag]], [#strong[Purpose]],),
    table.hline(),
    [`self(Repo://Entry)`], [The parent ebuild that introduced this
    dependency],
    [`build_with_use:use_state(En, Dis)`], [USE flags that must be
    enabled/disabled on this package],
    [`after(Literal)`], [Must come after this literal; propagates to
    children],
    [`after_only(Literal)`], [Must come after this literal; does not
    propagate],
    [`slot(C, N, Ss):{Candidate}`], [Slot lock from `:=` sub-slot
    rebuild semantics],
    [`replaces(pkg://Entry)`], [Which installed package this action
    replaces],
    [`assumption_reason(Reason)`], [Why a domain assumption was made],
    [`suggestion(Type, Detail)`], [Actionable suggestion (keyword,
    unmask, use change)],
    [`constraint(cn_domain(C,N):{D})`], [Inline version domain
    constraint],
    [`onlydeps_target`], [Marks a literal as an `--onlydeps` target],
    [`world_atom(Atom)`], [Planning marker for \@world set membership],
  )]
  , kind: table
  )

Contexts are merged at join points via feature term unification, which
uses Zeller-inspired feature unification. See
#link("20-doc-context-terms.md")[Chapter 20: Context Terms] for full
details.

== Canonical decomposition
<canonical-decomposition>
The prover stores literals in assoc/AVL structures keyed by a
#strong[stable] identity. That creates a design tension: during proof
search, the #strong[context] is constantly enriched --- new
`build_with_use` features appear, ordering constraints are propagated,
slot locks and learned domains are attached --- but the
#strong[underlying package and phase] (repository, cache entry, action)
are still the same logical goal. If the full term including context were
used as the key, every refinement would look like a #strong[new] node:
you would get duplicate entries for "the same" install step, incoherent
merging, and broken sharing of proof work.

#strong[Canonical decomposition] fixes that by splitting each literal
into a #strong[core] used for identity (`R://L:A`) and a #strong[context
list] carried as associated data. Two encounters of the same core with
different contexts collide on the same key; the prover then
#strong[merges] contexts (via feature term unification) instead of
forking duplicate keys.

Two predicates handle decomposition:

=== `prover:canon_literal/3`
<provercanon_literal3>
Strips the context from a literal, returning the core key and context
separately:

```prolog
canon_literal(R://(L:A),            R://L:A, {}).
canon_literal(R://(L:A?{Ctx}),      R://L:A, Ctx).
canon_literal(R://(L:A)?{Ctx},      R://L:A, Ctx).
canon_literal(R://(L:A?{C1})?{C2},  R://L:A, Merged).
```

The core `R://L:A` is used as the key in the Model AVL. The context is
stored as the value.

=== `prover:canon_rule/3`
<provercanon_rule3>
Similarly decomposes a rule head, producing a context-free key for the
Proof AVL.

This decomposition ensures that when a literal is re-encountered with a
different context, the prover can find the existing proof entry and
merge the contexts rather than creating a duplicate.

== How literals flow through the pipeline
<how-literals-flow-through-the-pipeline>
#figure(image("Diagrams/05-literal-flow.svg", alt: "Literal flow through the pipeline"),
  caption: [
    Literal flow through the pipeline
  ]
)

+ #strong[Rules] produce literals. The `target/2` rule resolves a user
  query to a `Repo://Entry:run?{Context}` literal. Dependency rules
  produce further literals with appropriate actions and contexts.

+ #strong[Prover] stores the core literal (`R://L:A`) as the key in the
  Model AVL and the context as the value. The Proof AVL uses
  `rule(R://L:A)` as the key, with the rule body and context as the
  value.

+ #strong[Planner] extracts rule heads from the Proof AVL, using
  `canon_literal/3` to get core literals. Kahn's algorithm schedules
  these into concurrent waves based on dependency edges.

+ #strong[Printer] reads the Plan (a list of waves), looks up each
  literal in the Model AVL to recover its context, and formats the
  output.

== Worked example
<worked-example>
Tracing `target('sys-apps/portage'):run?{[]}` through the pipeline:

```
1. User runs: portage-ng --pretend sys-apps/portage

2. Interface creates goal literal:
   [target('sys-apps'-'portage', []):run?{[]}]

3. Interface invokes the prover with this goal.

4. Prover uses rules to expand target/2:
   rule(target('sys-apps'-'portage', []):run?{[]},
        [portage://'sys-apps/portage-3.0.77-r3':run?{[]}])

5. Prover uses rules to expand :run:
   rule(portage://'sys-apps/portage-3.0.77-r3':run?{[]},
        [portage://'sys-apps/portage-3.0.77-r3':install?{[]},
         ...RDEPEND literals...])

6. Prover uses rules to expand :install:
   rule(portage://'sys-apps/portage-3.0.77-r3':install?{[]},
        [portage://'sys-apps/portage-3.0.77-r3':download?{[]},
         ...DEPEND/BDEPEND literals with self/1, build_with_use, after...])

7. Prover stores each proven literal in the Model AVL:
   Key: portage://'sys-apps/portage-3.0.77-r3':run
   Val: [] (context)

8. Planner places :download in wave 1, :install in wave 2, :run in wave 3

9. Printer outputs:
   [1] portage://sys-apps/portage-3.0.77-r3  download
   [2] portage://sys-apps/portage-3.0.77-r3  install
   [3] portage://sys-apps/portage-3.0.77-r3  run
```

== Further reading
<further-reading-4>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the prover
  uses these literals
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  rules produce literals
- #link("20-doc-context-terms.md")[Chapter 20: Context Terms] --- deep
  dive into context semantics and feature unification

= Knowledge Base and Cache
<knowledge-base-and-cache>
== From ebuild to fact: the metadata pipeline
<from-ebuild-to-fact-the-metadata-pipeline>
Every package in Gentoo begins life as an #strong[ebuild]: a bash script
in the Portage tree that declares metadata (dependencies, USE flags,
slot, license, and more). Portage-ng does not run those scripts.
Instead, it consumes a pre-digested form of the same information.

#strong[`egencache`] (or portage-ng's #strong[`--regen`]) walks the tree
and turns ebuilds into #strong[md5-cache] files: flat key--value text
blobs that summarize each ebuild's metadata. Portage-ng's reader and
parser then loads those files, runs their contents through the
#strong[EAPI DCG grammar] (see
#link("07-doc-eapi-grammar.md")[Chapter 7]), and #strong[asserts]
`cache:entry/5` (and related) facts into the in-memory knowledge base.
For fast startup, those facts are #strong[qcompiled] into
`Knowledge/kb.qlf`, so the next session reloads binary bytecode instead
of reparsing thousands of text files.

That end-to-end path --- ebuild → cache generation → md5-cache → grammar
→ Prolog facts → QLF --- is the #strong[metadata pipeline]. It is
deliberate: portage-ng never executes bash for package metadata; it
works #strong[entirely from metadata] that has already been extracted
and normalized.

#figure(image("Diagrams/06-metadata-generation.svg", alt: "Cache generation: ebuild to md5-cache"),
  caption: [
    Cache generation: ebuild to md5-cache
  ]
)

Once the md5-cache files exist on disk, portage-ng's reader parses each
one through the EAPI grammar and asserts the resulting terms as Prolog
facts:

#figure(image("Diagrams/06-metadata-ingestion.svg", alt: "Ingestion: md5-cache to Prolog facts"),
  caption: [
    Ingestion: md5-cache to Prolog facts
  ]
)

The knowledge base is the in-memory representation of the Gentoo Portage
tree at the end of that pipeline. It stores every ebuild's metadata as
Prolog facts that can be queried in sub-millisecond time.

== The cache data structure
<the-cache-data-structure>
The core data structure is `cache:entry/5`, a dynamic predicate with one
fact per ebuild:

```prolog
cache:entry(Repository, Id, Category, Name, Version).
```

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Argument]], [#strong[Example]], [#strong[Meaning]],),
    table.hline(),
    [`Repository`], [`portage`], [Registered repository atom],
    [`Id`], [`'sys-apps/portage-3.0.77-r3'`], [Full
    category/name-version string],
    [`Category`], [`'sys-apps'`], [Package category],
    [`Name`], [`'portage'`], [Package name],
    [`Version`], [`version([3,0,77],'',...)`], [Parsed version as
    `version/7` term],
  )]
  , kind: table
  )

Additional cache predicates store per-ebuild metadata:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Predicate]], [#strong[Content]],),
    table.hline(),
    [`cache:entry_metadata/3`], [EAPI, SLOT, KEYWORDS, LICENSE, etc.],
    [`cache:ordered_entry/5`], [Entries ordered by version (for
    candidate selection)],
    [`cache:provides/3`], [Virtual package mappings],
  )]
  , kind: table
  )

== Why this cache design?
<why-this-cache-design>
The shape of `cache:entry/5` is not arbitrary; it matches how Prolog and
the prover actually use the data.

#strong[Indexing and lookup.] Prolog's strength is pattern matching on
structured terms. `cache:entry/5` is arranged so that
#strong[first-argument indexing] on `Repository` and #strong[third- and
fourth-argument] access on `Category` and `Name` align with the most
common query shapes: "in this repo, what entries exist for this
category/name?"

#strong[Versions as terms.] The version is stored as a
#strong[`version/7` compound term] so that #strong[standard `compare/3`]
on the term gives correct version ordering #strong[without any runtime
conversion] to another representation. The prover and rules can treat
versions as ordinary Prolog data.

#strong[Splitting metadata.] Rich fields (EAPI, SLOT, KEYWORDS, LICENSE,
…) live in #strong[`cache:entry_metadata/3`] rather than bloating every
`entry/5` fact. That keeps the #strong[hot path] --- finding candidates
by repository, category, and name --- #strong[lightweight], while still
allowing full metadata when needed.

#strong[Pre-sorted candidates and version preference.]
#strong[`cache:ordered_entry/5`] holds entries #strong[pre-sorted by
version (newest first)] for candidate selection. Building that structure
once at load or regen time #strong[avoids repeated sorting during proof
search], where the same name may be considered many times under
different contexts.

The ordering is more than an optimisation --- it encodes
#strong[preference]. Prolog iterates over `ordered_entry/5` clauses in
assertion order, so the newest version is tried first. When the prover
searches for a candidate that satisfies a dependency, it encounters the
highest version before any older alternative. If that candidate passes
all constraint guards, it is selected without ever considering older
versions. If it fails (wrong slot, masked, REQUIRED\_USE violation),
Prolog's backtracking moves to the next clause --- the next-highest
version --- automatically.

This design has a formal counterpart in #strong[ordered logic programs]
as studied by Vermeir and Van Nieuwenborgh ("Preferred Answer Sets for
Ordered Logic Programs," JELIA 2002). In their framework, when multiple
rules can derive conflicting conclusions, a #strong[partial order over
rules] determines which one prevails. In portage-ng the "rules" are
candidate versions for a given category/name, and the partial order is
the version comparison: newer versions have higher priority. Prolog's
clause order directly implements this priority --- no separate
preference layer or scoring function is needed. The result is that the
prover naturally gravitates toward the newest compatible version, which
matches Gentoo's standard policy, while still falling back to older
versions when constraints demand it.

See
#link("21-doc-resolver-comparison.md")[Chapter 21: Resolver Comparison]
for more on Vermeir's ordered logic and its role alongside Zeller's
feature logic and CDCL-style conflict learning.

== Repositories and the knowledge base registry
<repositories-and-the-knowledge-base-registry>
Repositories are not just atoms: they are #strong[objects] in the OO
context system (`Source/Logic/context.pl`). Each repository has its own
#strong[identity], #strong[paths], #strong[sync method], and
#strong[cache] partition. The #strong[context] machinery provides
#strong[instance creation] (`newinstance`), #strong[method dispatch],
and #strong[visibility guards], so different repository kinds can share
an interface while differing in behavior --- for example, `portage:sync`
and `overlay:sync` can implement sync differently behind the same
method.

Repositories are registered via that OO context system. Each repository
is an instance of the `repository` class:

```prolog
:- portage:newinstance(repository).
:- kb:register(portage).
```

The knowledge base module (`knowledgebase.pl`) maintains a registry of
all loaded repositories. #strong[`kb:register/1`] records which
repositories are #strong[active] so the rest of the system can iterate
or dispatch over them. Multiple repositories can be registered
simultaneously --- for example, the main Portage tree (`portage`), the
VDB of installed packages (`pkg`), and user overlays (`overlay`).

Each repository instance manages its own cache facts. The `repository`
class provides methods for syncing, loading, and querying:

```prolog
portage:sync.          % Sync from remote
portage:read.          % Read md5-cache into Prolog facts
portage:search(Query). % Search entries
```

== Syncing and cache regeneration
<syncing-and-cache-regeneration>
#strong[`--sync`] performs a full repository synchronization. It is the
"wide" end of the metadata pipeline: it brings the tree up to date, then
materializes fresh cache facts and QLF artifacts.

+ Fetches the latest Portage tree (via git, rsync, or HTTP)
+ Reads md5-cache files via the EAPI grammar into cache predicates
+ Generates `Knowledge/kb.qlf` (qcompiled facts for fast reload)
+ Generates `Knowledge/profile.qlf` (serialized profile data)

#strong[`--regen`] regenerates the md5-cache incrementally. It replaces
`egencache`: only changed or new ebuilds are re-parsed, and regeneration
runs in parallel across available cores.

== Compiling knowledge
<compiling-knowledge>
On subsequent startups, portage-ng loads `Knowledge/kb.qlf` instead of
re-parsing the entire md5-cache directory. `qcompile` files are a
SWI-Prolog binary format that loads an order of magnitude faster than
parsing text files. That step closes the pipeline opened by ebuilds and
md5-cache: the #strong[authoritative] working set for proving is the
compiled fact base, not the shell sources.

The raw Prolog facts are also available as `Knowledge/kb.raw` for
debugging.

== Query layer
<query-layer>
The cache facts described above --- `cache:ordered_entry/5`,
`cache:entry_metadata/4`, and friends --- are ground relational tuples:
a flat, indexed collection of facts that describes the known world. In
database terminology, this is an #strong[extensional database] (EDB).
The query module (`Source/Knowledge/query.pl`) adds an
#strong[intensional] layer on top: it defines high-level query
predicates that are compiled down to direct lookups over the base
relations.

This architecture is closely related to #strong[Datalog], the
declarative query language that sits at the intersection of logic
programming and relational databases. In Datalog, ground facts form the
base relations and rules define derived views; queries are conjunctive
queries over those relations, with guaranteed termination. portage-ng's
query layer follows the same pattern: list queries compile into
conjunctions of cache lookups (conjunctive queries), every variable is
grounded through the EDB (the Datalog safety property), and the query
layer itself always terminates. Where the system goes beyond strict
Datalog is in its use of compound terms (`version/7`, `slot/1`) rather
than flat constants, and in the model queries that invoke the prover ---
at which point we leave the Datalog fragment and enter full recursive
Prolog reasoning.

Rather than interpreting queries at runtime through a generic search
function, portage-ng uses SWI-Prolog's #strong[`goal_expansion/2`] --- a
compile-time macro facility that acts as a Datalog-style query compiler
--- to rewrite high-level query goals into #strong[direct] calls to
indexed cache predicates before the program even runs.

=== Goal expansion by example
<goal-expansion-by-example>
Consider a rule that needs to find all ebuilds named `neovim`:

```prolog
query:search(name(neovim), Repository://Entry).
```

At load time, `goal_expansion/2` rewrites this into:

```prolog
cache:ordered_entry(Repository, Entry, _, neovim, _).
```

The high-level `search` call disappears entirely. What remains is a
direct call to the indexed cache predicate, where SWI-Prolog's
first-argument indexing on `Repository` and fourth-argument indexing on
`Name` make the lookup near-instantaneous. No dispatching, no
interpretation --- just a pattern match against the fact base.

A conjunctive query expands into a conjunction of cache calls:

```prolog
query:search([name(neovim), category('app-editors')], R://E).
```

becomes:

```prolog
cache:ordered_entry(R, E, 'app-editors', neovim, _).
```

The payoff shows up at scale: #strong[sub-millisecond] query behavior
across #strong[tens of thousands] of entries (on the order of 32,000+ in
a typical Portage tree), because the hot queries are specialised at
compile time.

=== `query:search` --- the main query predicate
<querysearch-the-main-query-predicate>
`query:search/2` is the primary interface for querying the knowledge
base. Its first argument describes what to search for; its second
argument binds the matching `Repository://Entry`:

```prolog
query:search(name(neovim), R://E).
query:search([category('dev-libs'), name(openssl)], R://E).
query:search(description(D), portage://'app-editors/neovim-0.12.0').
```

The following search terms are supported:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Search term]], [#strong[Matches]],),
    table.hline(),
    [`name(Name)`], [Package name],
    [`category(Cat)`], [Package category],
    [`entry(Id)`], [Full entry atom (`'category/name-version'`)],
    [`repository(Repo)`], [Repository atom],
    [`version(Ver)`], [Exact version term],
    [`slot(Slot)`], [Slot value],
    [`subslot(Sub)`], [Sub-slot value],
    [`keyword(KW)`], [Architecture keyword],
    [`description(D)`], [Package description],
    [`eapi(E)`], [EAPI version],
    [`license(L)`], [License],
    [`homepage(H)`], [Homepage URL],
    [`maintainer(M)`], [Package maintainer],
    [`eclass(E)`], [Inherited eclass],
    [`iuse(Flag)`], [USE flag declared in IUSE],
    [`masked(true/false)`], [Whether the package is masked],
  )]
  , kind: table
  )

Search terms can be combined as a list for conjunctive queries. The
`all(...)` wrapper collects all matching values, and `latest(...)`
returns only the first (highest-version) match.

=== `query:select` --- version and metadata comparison
<queryselect-version-and-metadata-comparison>
For queries that need comparison operators (not just equality),
portage-ng uses a `select(Key, Comparator, Value)` term inside `search`:

```prolog
query:search(select(version, greaterequal, Ver), R://E).
query:search(select(slot, equal, '3'), R://E).
query:search(select(keyword, wildcard, 'amd*'), R://E).
```

For version comparisons, the `select` clauses expand at compile time
into direct `cache:ordered_entry` lookups combined with
`eapi:version_compare/3`:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Comparator]], [#strong[Meaning]],),
    table.hline(),
    [`equal`], [Exact version match],
    [`smaller`], [Version strictly less than],
    [`greater`], [Version strictly greater than],
    [`smallerequal`], [Less than or equal],
    [`greaterequal`], [Greater than or equal],
    [`notequal`], [Not equal],
    [`wildcard`], [Wildcard match (e.g.~`3.0*`)],
    [`tilde`], [Fuzzy matching (same base version, any revision)],
  )]
  , kind: table
  )

For non-version keys, `select` falls through to `cache:entry_metadata/4`
lookups with the appropriate comparison. This keeps the version hot path
--- which is exercised thousands of times during candidate selection ---
fully indexed and compiled.

== Further reading
<further-reading-5>
- #link("07-doc-eapi-grammar.md")[Chapter 7: The EAPI Grammar] --- how
  md5-cache files are parsed into cache predicates
- #link("03-doc-gentoo.md")[Chapter 3: Configuration] --- repository
  path setup
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the prover
  queries the knowledge base

= The EAPI Grammar
<the-eapi-grammar>
The Gentoo #strong[Package Manager Specification] (PMS) defines a
dependency language that is easy to underestimate on first reading. A
single atom can carry a version comparator, a category and package name,
a Gentoo version string, slot and sub-slot operators, USE restrictions,
and---wrapped around lists of atoms---USE conditionals, choice groups,
and blockers. Traditional Portage implements this surface syntax with an
ad hoc parser written in Python.

portage-ng uses Prolog's built-in #strong[Definite Clause Grammar] (DCG)
notation to encode the same language directly
(`Source/Domain/Gentoo/eapi.pl`). The insight is simple: PMS dependency
syntax #emph[is] a grammar, so it should be expressed as one. DCG rules
describe that grammar directly; the parser is the grammar, not a
separate layer that tries to stay in sync with a prose spec. What PMS
says and what the executable parser accepts are one artifact---the rules
in `eapi.pl`---rather than a specification document drifting away from a
pile of regexes and special cases.

The grammar fully implements PMS 9 / EAPI 9.

== What gets parsed
<what-gets-parsed>
The EAPI grammar is exercised whenever md5-cache metadata is loaded.
Each file under the Portage tree's `metadata/md5-cache/` directory holds
#strong[one ebuild's] worth of metadata as a flat list of lines, each
line a single `KEY=VALUE` pair (PMS 9, §14.3). A typical fragment looks
like this:

```
BDEPEND=>=dev-build/cmake-3.16
DEFINED_PHASES=compile configure install prepare test
DEPEND=dev-libs/openssl:= dev-libs/libffi:=
EAPI=8
IUSE=debug doc test
KEYWORDS=~amd64 ~arm64
RDEPEND=dev-libs/openssl:= >=dev-lang/python-3.10[ssl,threads]
REQUIRED_USE=|| ( python_targets_python3_11 python_targets_python3_12 )
SLOT=0
```

The DCG is responsible for turning the #emph[values] of
dependency-related keys into structured terms: dependency strings
(`DEPEND`, `BDEPEND`, `RDEPEND`, `PDEPEND`, `IDEPEND`), USE-conditional
groups, version operators, slot operators, USE dependencies, and
`REQUIRED_USE` constraints. Other keys (`EAPI`, `SLOT`, `KEYWORDS`,
`DESCRIPTION`, …) use smaller, dedicated value rules in the same
module---still DCG-driven, but without the full dependency expression
machinery.

== A worked example: one dependency atom
<a-worked-example-one-dependency-atom>
Consider a single atom as it might appear in `RDEPEND` or `DEPEND`:

`>=dev-libs/openssl-3.0:0/3=[ssl,-test]`

#figure(image("Diagrams/07-dependency-atom.svg", alt: "Dependency atom anatomy"),
  caption: [
    Dependency atom anatomy
  ]
)

The core DCG rule for a package atom is `eapi:package_dependency/3` in
`eapi.pl`. Conceptually it composes the way PMS §8.3 suggests reading
the text: optional blocker, optional comparator, `category/package`,
optional version, optional slot restriction, optional USE dependency
list, with a small helper to merge "`=` + wildcard" into the dedicated
`wildcard` operator:

```prolog
eapi:package_dependency(T, _R://_E, Output) -->
  eapi:blocking(B),                                      % optional
  eapi:operator(O),                                      % optional
  eapi:category(C), eapi:separator, !, eapi:package(P),  % required
  eapi:version0(V, W),                                   % optional
  eapi:slot_restriction(S),                              % optional
  eapi:use_dependencies(U),                              % optional
  { eapi:select_operator(O, W, Op),
    Output = package_dependency(T, B, C, P, Op, V, S, U) }.
```

=== Matching each piece
<matching-each-piece>
+ #strong[`blocking`] --- No `!` or `!!` prefix, so this clause leaves
  the blocking marker as "none" (`no` in the concrete term).
+ #strong[`operator`] --- The leading `>=` matches the `greaterequal`
  operator.
+ #strong[`category`, `/`, `package`] --- Consumes `dev-libs`, the
  slash, and `openssl`.
+ #strong[`version0`] --- After the hyphen, parses `3.0` into a
  `version/7` term (and records that there is no `=*`-style wildcard
  suffix on this atom).
+ #strong[`slot_restriction`] --- The `:0/3=` fragment becomes a list
  describing the main slot, sub-slot, and trailing `=` (rebuild-on-slot
  change semantics).
+ #strong[`use_dependencies`] --- Bracket contents parse as a
  comma-separated list: `ssl` as an enable requirement, `-test` as a
  disable requirement.
+ #strong[`select_operator`] --- With no wildcard, the final operator
  remains `greaterequal`.

=== Intermediate state and difference lists
<intermediate-state-and-difference-lists>
Operationally, each DCG goal is expanded into an ordinary Prolog
predicate with two extra arguments: the #strong[current suffix] of the
input code list and the #strong[remaining suffix] after the rule
succeeds. That is the standard DCG #strong[difference-list] threading:
parsing advances by shortening the difference between "input seen so
far" and "still to read."

You can read the parse as a sequence of #strong[remaining input]
snapshots (conceptual, not a separate data structure the code prints):

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[After this part succeeds]], [#strong[Remaining
      input (conceptually)]],),
    table.hline(),
    [\(start)], [`>=dev-libs/openssl-3.0:0/3=[ssl,-test]`],
    [`operator`], [`dev-libs/openssl-3.0:0/3=[ssl,-test]`],
    [`category` + `/` + `package`], [`-3.0:0/3=[ssl,-test]`],
    [`version0`], [`:0/3=[ssl,-test]`],
    [`slot_restriction`], [`[ssl,-test]`],
    [`use_dependencies`], [\(empty --- parse succeeds)],
  )]
  , kind: table
  )

Calling `phrase(Rule, Codes)` wraps that pattern: it requires the rule
to consume all of `Codes` (or you supply an explicit remainder). There
is no hand-maintained cursor variable in application code---the DCG
expansion supplies it.

=== Final term
<final-term>
For the install-time dependency role (`package_d` in the grammar),
parsing the string above yields a `package_dependency/8` term of this
shape (as produced by the running grammar; minor formatting may vary):

```prolog
package_dependency(
  install,
  no,
  'dev-libs',
  openssl,
  greaterequal,
  version([3, 0], '', 4, 0, '', 0, '3.0'),
  [slot('0'), subslot('3'), equal],
  [use(enable(ssl), none), use(disable(test), none)])
```

The first argument (`install` / `run` / `compile`) records #emph[which]
PMS dependency class is being parsed (`DEPEND` vs `RDEPEND` vs
`BDEPEND`), so the same DCG surface syntax feeds slightly different
typing in the abstract syntax.

== Why DCG instead of regex or ad hoc code?
<why-dcg-instead-of-regex-or-ad-hoc-code>
The dependency language defined by PMS is recursive: USE conditionals
contain dependency lists, which themselves contain atoms, which may
carry nested USE restrictions. A regex or hand-coded string scanner can
handle flat patterns, but recursive structure calls for a recursive
formalism. Prolog's DCG notation is exactly that formalism, and it
brings several practical advantages.

#strong[Composition.] The package-atom rule is assembled from small,
self-contained nonterminals --- `blocking`, `operator`, `category`,
`separator`, `package`, `version0`, `slot_restriction`, and
`use_dependencies` --- each of which can be understood and tested in
isolation:

`dep_atom --> blocking, operator, category, '/', package, version_suffix, slot_suffix, use_deps.`

#strong[Local testing.] Every nonterminal is an ordinary Prolog
predicate, so you can call `phrase/2` on a single rule without loading
the cache or the full pipeline.

#strong[Free recursion.] USE conditionals and nested choice groups use
the same mechanism as every other rule: `eapi:dependencies//3` recurses
through lists of `eapi:dependency//3` alternatives, so nested
`flag? ( … )` structures need no separate stack machine.

#strong[Failure locality.] When parsing fails, the failure occurs at a
named nonterminal --- a clear indication of which part of the input was
unexpected, rather than a terse "pattern did not match" from a regex
engine.

#strong[Graceful evolution.] New PMS features tend to introduce new
alternatives or new rules (additional operators, value forms, EAPI-9
extensions), not a rewrite of central control flow. Adding a rule to a
DCG is a one-clause change; the equivalent in a Python parser is
typically a new branch in an `if eapi >= …` ladder spread across several
functions.

== DCG grammar design
<dcg-grammar-design>
The grammar is implemented in `Source/Domain/Gentoo/eapi.pl` as a set of
DCG rules. DCGs are a natural fit for dependency specifications because:

- Dependency atoms have recursive structure (USE conditionals nest).
- The grammar is context-free at the level PMS defines.
- DCG rules compose as Prolog predicates, so the parser
  #strong[constructs] Prolog terms while it reads text.

=== Dependency atoms
<dependency-atoms>
The table below summarizes how the surface syntax maps into fields of
the abstract atom (illustrated with the same running example):

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Component]], [#strong[Example]], [#strong[Parsed
      as]],),
    table.hline(),
    [Version operator], [`>=`], [Comparator atom (e.g.~`greaterequal`)],
    [Category], [`dev-libs`], [Atom],
    [Name], [`openssl`], [Atom],
    [Version], [`3.0`], [`version/7` term],
    [Slot operator], [`:0/3=`], [Slot + sub-slot + rebuild flag],
    [USE deps], [`[ssl,-test]`], [Enable/disable (and related)
    wrappers],
  )]
  , kind: table
  )

=== USE conditionals
<use-conditionals>
USE-conditional dependency groups use the syntax:

```
flag? ( deps... )      — include deps if flag is enabled
!flag? ( deps... )     — include deps if flag is disabled
```

These are parsed into conditional terms that the rules layer evaluates
against the USE model during proof construction.

=== Choice groups
<choice-groups>
PMS defines three choice operators for REQUIRED\_USE and dependency
specs:

- #strong[`||` (any-of)] --- `|| ( a b c )` --- at least one of the
  listed items must be satisfied
- #strong[`^^` (exactly-one-of)] --- `^^ ( a b c )` --- exactly one must
  be satisfied
- #strong[`??` (at-most-one-of)] --- `?? ( a b c )` --- at most one may
  be satisfied

== Reader/parser pipeline
<readerparser-pipeline>
Loading md5-cache is a small pipeline with clear separation of concerns.

The #strong[repository] side (`Source/Knowledge/repository.pl`) knows
where the cache lives: under each tree's `metadata/md5-cache/`
directory, with one file per `category/package-version` entry
(`repository:get_cache_file/2` resolves entry → path). Sync and
incremental updates decide #emph[which] entries need work; for each
entry that must be read, the repository opens the flat cache file.

#strong[`Source/Pipeline/reader.pl`] does one job: given a path (or
stream), it reads the file line by line into a list of strings---each
string is still a raw `KEY=VALUE` line, unchanged.

#strong[`Source/Pipeline/parser.pl`] walks that list. For each line it
converts the string to character codes and runs
`phrase(eapi:keyvalue(metadata, …), Codes)`. That single DCG entry point
dispatches on the key: dependency keys delegate to the full dependency
grammar (`DEPEND`, `BDEPEND`, `RDEPEND`, `PDEPEND`, `IDEPEND`,
`REQUIRED_USE`, …); non-dependency keys use lighter value rules (`EAPI`,
`SLOT`, `KEYWORDS`, `IUSE`, …).

So the data flow is:

```
md5-cache files  →  reader.pl (lines)  →  parser.pl  →  eapi.pl (DCG)  →  cache predicates
```

+ #strong[`reader.pl`] reads each md5-cache file into a list of lines
  (one key/value pair per line).

+ #strong[`parser.pl`] parses every line through `eapi:keyvalue/3`,
  which routes values to the appropriate DCG subtree.

+ #strong[`eapi.pl`] builds structured Prolog terms (e.g.~`depend(D)`,
  `rdepend(D)`, `slot(S)`, `eapi(E)`).

+ The results are asserted as `cache:entry/5` and related predicates,
  populating the knowledge base.

The reader supports incremental loading --- only new or changed files
need to be re-parsed when using `--regen`.

== Parsed output
<parsed-output>
After parsing, each ebuild is represented by a set of cache predicates.
The dependency model for an ebuild is a list of `package_dependency/8`
terms:

```prolog
package_dependency(DepType, Blocking, Category, Name, Operator, Version,
                   SlotInfo, UseInfo)
```

These terms are consumed by the rules layer during proof construction.
The EAPI grammar handles all PMS 9 / EAPI 9 constructs:

- Version operators: `=`, `>=`, `<=`, `>`, `<`, `~`, `=*` (wildcard)
- Slot operators: `:SLOT`, `:SLOT/SUBSLOT`, `:*`, `:=`
- USE dependencies: `[flag]`, `[-flag]`, `[flag=]`, `[!flag=]`,
  `[flag(+)]`, `[flag(-)]`
- Blockers: `!cat/pkg` (weak), `!!cat/pkg` (strong)
- All-of groups (implicit conjunction)
- Any-of groups (`|| ( ... )`)
- USE conditionals (`flag? ( ... )`, `!flag? ( ... )`)

== Further reading
<further-reading-6>
- #link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache]
  --- how parsed data is stored
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  dependency terms are consumed during proof construction
- #link("22-doc-dependency-ordering.md")[Chapter 22: Dependency Ordering]
  --- PMS dependency type semantics

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
<further-reading-7>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- the reprove mechanism and constraint learning
- #link("05-doc-proof-literals.md")[Chapter 5: Proof Literals] --- the
  literal format
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  `rule/2` works
- #link("04-doc-architecture.md")[Chapter 4: Architecture Overview] ---
  the full pipeline

= Assumptions and Constraint Learning
<assumptions-and-constraint-learning>
== Always a proof, never a dead end
<always-a-proof-never-a-dead-end>
Most dependency resolvers stop when they cannot satisfy a constraint: no
solution, no plan, and often little more than a terse error. portage-ng
takes a different stance. #strong[It does not give up.] When every
above-board alternative has been exhausted, the prover records an
#strong[assumption] --- effectively: "I am proceeding #emph[as if] this
dependency could be satisfied" --- and continues building the proof.

The outcome is #strong[always] a complete plan. Either the proof is
#strong[strict] (no assumptions), or it is a proof #strong[under
assumptions], with the unresolved fragments called out explicitly.
Assumptions are not treated as opaque failures; they are
#strong[proposals]. They tell you which pieces of configuration or tree
state would need to change for the same reasoning chain to become a
strict proof. This is the same habit of mind as in mathematics:
#emph["Assuming the Riemann hypothesis, we can prove …"] --- the
argument is valid #emph[conditional] on the assumptions; make them true,
and the condition disappears.

The sections below walk through a concrete missing-dependency example,
then explain how suggestion tags turn assumptions into actionable hints.
After that, the chapter documents the same mechanisms in technical
detail: assumption taxonomy, reprove loop, REQUIRED\_USE flow, entry
rules, constraint guards, printing, progressive relaxation, and the
analogy to CDCL.

== Worked assumption example: missing `dev-libs/foo`
<worked-assumption-example-missing-dev-libsfoo>
Suppose the user runs:

```text
portage-ng --pretend some-package
```

and some package in the graph depends on #strong[`dev-libs/foo`], which
has #strong[no ebuild] in any repository the knowledge base knows about.

#strong[What the prover does]

+ The #strong[grouped package dependency] rule tries to prove the
  dependency by enumerating candidates for category `dev-libs` and name
  `foo`.
+ #strong[Search returns no entries] --- there is nothing to install, so
  every candidate path fails.
+ After #strong[backtracking] exhausts those paths, the #strong[fallback
  chain] runs (parent narrowing, reprove with learned domains, and so
  on, as documented below). None of that invents a missing package.
+ The domain layer finally takes the #strong[assumption path]: it builds
  a condition whose head is `assumed(grouped_package_dependency(…))`,
  tags the proof-term context with a reason (and optional suggestions),
  and the catch-all rule `rule(assumed(_), [])` lets the prover close
  that branch of the proof.

#strong[What appears in the Proof AVL]

The proof tree stores a #strong[domain assumption] with a key of the
form `rule(assumed(Lit))`, where `Lit` is the grouped-dependency
literal. For example (category and name as atoms, dependency list
abbreviated):

```prolog
rule(assumed(grouped_package_dependency('dev-libs', 'foo', …):config?{Ctx}))
    → dep(0, [])?Ctx
```

The exact `Action` (`:config`, `:install`, `:run`, …) depends on which
phase of the grouped dependency is being proved; the important invariant
is the #strong[`rule(assumed(...))`] proof key (see
#link(<assumption-taxonomy>)[Assumption Taxonomy]).

#strong[What the user sees in the plan output]

The printer classifies this as a non-existent dependency and emits a
#strong[Domain assumptions] block, along the lines of:

```text
Domain assumptions: dev-libs/foo (non-existent)
```

#strong[Exit code]

When any #strong[domain] assumption is present, the CLI exit code is
#strong[`2`] (cycle-break-only assumptions alone yield #strong[`1`]\; a
fully strict proof yields #strong[`0`]).

#strong[How to read it]

The message is intentionally operational: #strong[to resolve this
assumption, ensure `dev-libs/foo` is available in your repository]
(overlay, third-party tree, or corrected package name). The plan is
still a single coherent merge order; the assumption marks the gap
between what the prover can justify from facts and what you must supply
from outside.

== Assumptions as actionable proposals
<assumptions-as-actionable-proposals>
Many assumptions carry #strong[`suggestion(Type, Detail)`] (and related)
tags in the literal's #strong[`?{Context}`] list. These encode
#strong[configuration changes] that would move the proof toward
strictness --- often the same changes the #strong[progressive
relaxation] tiers simulate when you widen `assuming/1` flags.

Typical shapes in the codebase include:

#figure(
  align(center)[#table(
    columns: (52.38%, 47.62%),
    align: (left,left,),
    table.header([#strong[Tag (representative)]], [#strong[User-facing
      intent]],),
    table.hline(),
    [`suggestion(keyword, '~amd64')`], [Accept the unstable keyword ---
    e.g.~add to #strong[`package.accept_keywords`] (in sources:
    `suggestion(accept_keyword, '~amd64')`)],
    [`suggestion(unmask, …)`], [Unmask the package ---
    e.g.~#strong[`package.unmask`] (`Repo://Entry` when known)],
    [`suggestion(use, …)`], [Adjust USE flags ---
    e.g.~#strong[`package.use`] (in sources:
    `suggestion(use_change, Repo://Entry, Changes)`)],
  )]
  , kind: table
  )

When you run in modes that #strong[apply] suggestions (see the builder's
`execute_suggestion/…` hooks), those changes are #strong[already
reflected in the plan]\; your job is to #strong[review and approve] them
in your real `/etc/portage` layout, or to treat the tags as a checklist
for manual edits.
#link(<progressive-relaxation>)[Progressive Relaxation] ties the same
ideas to the `assuming` tiers (`keyword_acceptance`, blockers,
`unmask`).

== Overview
<overview>
#figure(image("Diagrams/09-reprove-flow.svg", alt: "Reprove mechanism flow"),
  caption: [
    Reprove mechanism flow
  ]
)

The portage-ng prover builds a formal proof that a set of target
packages can be installed. The proof is an AVL tree mapping literals to
their justifications. When part of the dependency graph cannot be
satisfied, the prover records #emph[assumptions] --- lightweight markers
that let the proof complete while flagging the unresolved fragment for
the user.

Two fundamentally different kinds of assumptions exist, and a bounded
reprove mechanism allows the prover to retry the proof with accumulated
knowledge before resorting to assumptions.

```
                        ┌─────────────────┐
                        │   prove/9       │
                        │ (top-level)     │
                        └────────┬────────┘
                                 │
                     ┌───────────▼───────────┐
                     │  with_reprove_state   │
                     │  (save/restore        │
                     │   learned store)      │
                     └───────────┬───────────┘
                                 │
               ┌─────────────────▼─────────────────┐
               │   prove_with_retries              │
               │   catch(prove_once, prover_reprove│
               │         handle_reprove)           │
               └─────────┬──────────┬──────────────┘
                         │          │ prover_reprove(Info)
                  success│          │
                         │    ┌─────▼─────────────────┐
                         │    │ handle_reprove         │
                         │    │ Attempt < MaxRetries?  │
                         │    │   yes: learn + retry   │
                         │    │   no:  reprove_exhausted
                         │    │        prove_once      │
                         │    │        (disabled)      │
                         │    └───────────────────────┘
                         │
               ┌─────────▼────────┐
               │   prove_once     │
               │  with_cycle_stack│
               │  prove_recursive │
               └──────────────────┘
```

== Data Structures
<data-structures-1>
The prover maintains four AVL trees during proof construction:

#figure(
  align(center)[#table(
    columns: (14.12%, 43.53%, 42.35%),
    align: (left,left,left,),
    table.header([#strong[AVL]], [#strong[Key →
      Value]], [#strong[Purpose]],),
    table.hline(),
    [Proof], [`rule(Lit)` → `dep(N, Body)?Ctx`], [Which rule justified
    Lit],
    [Model], [`Lit` → `Ctx`], [Every proven literal + context],
    [Constraints], [constraint key → value], [Accumulated constraint
    terms],
    [Triggers], [`BodyLit` → `[HeadLit, …]`], [Reverse-dependency
    index],
  )]
  , kind: table
  )

== Assumption Taxonomy
<assumption-taxonomy>
#figure(image("Diagrams/09-assumption-taxonomy.svg", alt: "Assumption taxonomy"),
  caption: [
    Assumption taxonomy
  ]
)

The two kinds of assumptions are stored differently in the Proof and
Model trees. Confusing them leads to wrong statistics, wrong plan
output, or missed warnings.

=== 1. Domain Assumptions (`rule(assumed(X))`)
<domain-assumptions-ruleassumedx>
Introduced by the #strong[rules layer] when a dependency cannot be
satisfied --- for example, a package that does not exist in the tree, or
a REQUIRED\_USE violation that makes every candidate invalid.

#strong[How they are created:]

The `grouped_package_dependency` rule exhausts all candidates (via
Prolog backtracking), then the fallback chain (parent narrowing →
reprove → assumption), and finally emits:

```prolog
Conditions = [assumed(grouped_package_dependency(C,N,Deps):Action?{Ctx})]
```

The `assumed(X)` literal in the body is proved by the catch-all rule:

```prolog
rule(assumed(_), []) :- !.
```

This stores `rule(assumed(X))` in the Proof tree.

#strong[Where they appear:] - Proof: `rule(assumed(X))` →
`dep(0, [])?Ctx` - Model: the enclosing literal's entry (normal) - Plan:
rendered as "verify" steps + "Domain assumptions" warning block

=== 2. Prover Cycle-Break Assumptions (`assumed(rule(X))`)
<prover-cycle-break-assumptions-assumedrulex>
Introduced by the #strong[prover] when it detects a cycle during proof
search. If a literal is already on the cycle stack (currently being
proved), the prover cannot recurse further without diverging. Instead,
it records a cycle-break:

```prolog
put_assoc(assumed(rule(Lit)), Proof, dep(-1, OldBody)?Ctx, Proof1),
put_assoc(assumed(Lit), Model, Ctx, NewModel)
```

#strong[Where they appear:] - Proof: `assumed(rule(Lit))` →
`dep(-1, Body)?Ctx` - Model: `assumed(Lit)` → `Ctx` - Plan: SCC /
merge-set scheduling; cycle explanation via `cycle:*`

=== Summary Table
<summary-table>
#figure(
  align(center)[#table(
    columns: (30.12%, 34.94%, 34.94%),
    align: (left,left,left,),
    table.header([#strong[Property]], [#strong[Domain
      Assumption]], [#strong[Prover Cycle-Break]],),
    table.hline(),
    [Proof key], [`rule(assumed(X))`], [`assumed(rule(X))`],
    [Model key], [\(normal literal)], [`assumed(Lit)`],
    [dep count], [0], [-1],
    [Introduced by], [rules layer], [prover layer],
    [Represents], [unsatisfiable dependency], [cyclic dependency],
    [Printed as], ["Domain assumptions"], [cycle break (SCC)],
    [Exit code contribution], [2], [1],
  )]
  , kind: table
  )

== Reprove Mechanism
<reprove-mechanism>
When a conflict is detected during proof search, the domain layer does
not simply fail --- it records what went wrong and requests a retry with
refined knowledge.

=== Triggering Reprove
<triggering-reprove>
Several predicates can throw `prover_reprove(Info)`:

#figure(
  align(center)[#table(
    columns: (42.5%, 57.5%),
    align: (left,left,),
    table.header([#strong[Source]], [#strong[When]],),
    table.hline(),
    [`maybe_request_grouped_dep_reprove`], [Effective domain conflicts
    with selected CN; domain inconsistent; version/slot constraints
    present],
    [`maybe_learn_parent_narrowing`], [Parent introduced a dep that made
    (C,N) unsatisfiable; learns to exclude parent version],
    [`selected_cn_unique_or_reprove`], [CN-domain constraint conflicts
    with already-selected candidate (constraint guard)],
    [`selected_cn_not_blocked_or_reprove`], [Blocker detected via
    blocked source snapshot],
  )]
  , kind: table
  )

Each throws
`prover_reprove(cn_domain(C, N, RejectDomain, Candidates, Reasons))`.

=== Handling Reprove
<handling-reprove>
```
prover_reprove(Info) caught by prove_with_retries
        │
        ▼
heuristic:handle_reprove(Info, Added)
  ├── candidate:add_cn_domain_rejects(C, N, Domain, Candidates)
  │     → assertz(memo:cn_domain_reject_(Key, Rejected))
  ├── origin rejects from introduced_by reasons
  └── Added = true if new information learned
        │
        ├── Added = true, Attempt < MaxRetries
        │     → prove_with_retries(…, Attempt+1, MaxRetries)
        │       (restarts prove_once from scratch)
        │
        └── Added = false  OR  Attempt >= MaxRetries
              → heuristic:reprove_exhausted/0
                (clears cn_domain_reject_ so final attempt is unbiased)
              → with_reprove_disabled(prove_once(…))
                (final attempt; no new prover_reprove can be thrown)
```

=== Learned Constraint Store
<learned-constraint-store>
The `prover:learn/3` and `prover:learned/2` predicates maintain a
key-value store that #strong[persists across reprove retries] within the
same top-level `prove/9` invocation. This is distinct from the reject
set (which accumulates and is cleared on exhaustion).

The domain uses learned constraints for: 1. #strong[Candidate
narrowing]: `grouped_dep_effective_domain` intersects the local+context
domain with any learned domain. 2. #strong[Conflict learning]:
constraint guards learn the domain when a conflict is detected. 3.
#strong[Parent narrowing]: `maybe_learn_parent_narrowing` learns to
exclude the parent version when a child dep cannot be satisfied.

=== Retry Budget
<retry-budget>
`reprove_max_retries` defaults to 3 (configurable via
`config:reprove_max_retries/1`). The final attempt runs with reprove
disabled so the proof can complete with assumptions if necessary.

== REQUIRED\_USE Violation Flow
<required_use-violation-flow>
When a parent package forces USE flags on a dependency via bracketed USE
deps (e.g.~`cat/pkg[feature]`), and the dependency's `REQUIRED_USE`
forbids that flag combination, the REQUIRED\_USE violation mechanism
ensures the prover explores alternatives before assuming.

=== Step-by-Step Flow
<step-by-step-flow>
```
1. Parent "app" depends on "lib[feature_z]"
   → build_with_use propagates feature_z to lib's context

2. lib's :install/:run entry rule fires
   → use:build_with_use_resolve_required_use computes BWU state
   → use:verify_required_use_with_bwu checks REQUIRED_USE

3. Verification FAILS (lib has REQUIRED_USE=!feature_z)
   → use:describe_required_use_violation caches structured info
   → assertz(memo:requse_violation_(C, N, ViolDesc))
   → entry rule FAILS (not assumes!)

4. Prover backtracks to grouped_package_dependency
   → tries next candidate version of lib (if any)
   → all candidates exhausted

5. Fallback chain in grouped_package_dependency:
   a. maybe_learn_parent_narrowing
      → learns to exclude app-1.0, throws prover_reprove
   b. maybe_request_grouped_dep_reprove
      → may throw if domain/constraint conflicts exist
   c. Assumption path (after retries exhausted):
      → explanation:assumption_reason_for_grouped_dep classifies
      → checks memo:requse_violation_(C, N, ViolDesc)
      → enriches assumption context with required_use_violation(…)
      → Conditions = [assumed(grouped_package_dependency(…)?{Ctx})]

6. Warning printer:
   → "REQUIRED_USE violation:"
   → "  cat/lib"
   → "  USE deps force:   [feature_z]"
   → "  violates: !feature_z"
   → "  required by: overlay://cat/app-1.0"
```

=== Why Fail Instead of Assume?
<why-fail-instead-of-assume>
If the entry rule produced an assumption directly (as was done
initially), the `grouped_package_dependency` rule would see a successful
proof --- the assumption silently absorbs the failure. The entire
reprove mechanism (alternative candidates, parent narrowing, learned
constraint retries) would be #strong[bypassed].

By failing, the entry rule lets Prolog's backtracking explore: - Other
candidate versions (which may have different REQUIRED\_USE) - Parent
narrowing (which may find a parent version without the conflicting USE
dep) - Reprove retries with learned constraints

Only after #strong[all] alternatives are exhausted does the domain
assumption appear, carrying the REQUIRED\_USE violation detail for the
user.

=== Memo Cache
<memo-cache>
The violation info is cached via `memo:requse_violation_/3`
(thread-local, survives backtracking since `assertz` is side-effecting).
It is: - #strong[Asserted] in the entry rule before failing -
#strong[Consumed] in the `grouped_package_dependency` assumption path
(retracted after enriching the context) - #strong[Cleared] by
`memo:clear_caches/0` at the start of each proof run

== Entry Rule Structure
<entry-rule-structure>
Both `:install` and `:run` entry rules follow the same pattern:

```
rule(Repo://Ebuild:Action?{Context}, Conditions) :-
  !,
  ( masked, \+ assuming(unmask) -> fail
  ; no accepted keyword, \+ assuming(keyword_acceptance) -> fail
  ; installed, \+ emptytree -> Conditions = []
  ; ctx_take_after…,
    ( % Normal proof
      query metadata,
      compute required_use + build_with_use,

      % REQUIRED_USE guard: fail to allow reprove
      ( \+ verify_required_use_with_bwu(…) ->
          cache violation, fail
      ; true
      ),

      % Build dependency model
      ( memoized_search(dependency model),
        order deps,
        Conditions = [selected_cn, constraints, download, deps…]
      ; % Model-computation fallback
        Conditions = [assumed(…:Action?{issue_with_model})]
      )
    )
  ).
```

The key design decisions: - #strong[Cut (`!`)] after the head: only one
`:install` / `:run` rule clause exists per literal form; alternatives
come from different candidates in `grouped_package_dependency`. -
#strong[REQUIRED\_USE violation → fail]: propagates to candidate
selection for reprove. - #strong[Model-computation fallback → assume]:
when the dependency model itself cannot be built (e.g.~all
`any_of_group` branches filtered), the entry rule assumes rather than
failing, because this is a property of the ebuild metadata, not a
candidate selection issue.

== Constraint Guards and Reprove Integration
<constraint-guards-and-reprove-integration>
The prover calls `rules:constraint_guard(Key, Constraints)` after
unifying each constraint term. The guard may: - Succeed silently (no
conflict) - Fail (causes backtracking within the current proof attempt)
\- Throw `prover_reprove(…)` (triggers a retry with learned knowledge)

Key guard predicates in `candidate.pl`: -
`selected_cn_unique_or_reprove`: enforces CN-domain consistency -
`selected_cn_not_blocked_or_reprove`: enforces blocker constraints -
`maybe_request_cn_domain_reprove`: handles domain inconsistencies

== Assumption Printing Pipeline
<assumption-printing-pipeline>
```
Proof AVL
  │
  ├── rule(assumed(X))           → handle_assumption("domain")
  │     └── print_assumption_detail(rule(…))
  │           ├── required_use_violation in Ctx → REQUIRED_USE block
  │           ├── grouped_package_dependency    → reason label + detail
  │           ├── R://E:Action + issue_with_model → "Model unavailable"
  │           └── other                         → generic
  │
  └── assumed(rule(X))           → handle_assumption("cycle-break")
        └── cycle:print_cycle_explanation
```

=== Assumption Type Classification (`assumption.pl`)
<assumption-type-classification-assumption.pl>
```prolog
required_use_violation(Ctx)    →  required_use_violation
grouped_dep:Action             →  non_existent_dependency
grouped_dep:Action?{Ctx}       →  (from assumption_reason in Ctx)
R://E:install                  →  assumed_installed
R://E:run                      →  assumed_running
blocker(…)                     →  blocker_assumption
issue_with_model in Ctx        →  issue_with_model
```

== Testing Learned Constraints
<testing-learned-constraints>
When testing changes to the reprove/assumption mechanism, always verify:

+ #strong[Exit code]: 0 = no assumptions, 1 = cycle breaks only, 2 =
  domain assumptions
+ #strong["Total: N actions"] line present (proof completed)
+ #strong[Count of "non-existent"] lines (domain assumptions)
+ #strong[No "Unknown message"] or escaping exceptions
+ #strong[Runtime] \< 10 seconds for single targets (reprove retries can
  add latency; excessive retries suggest a learning bug)
+ #strong[Overlay test suite]: `prover:test_stats(overlay)` should
  process all 364 ebuilds / 316 packages at 100%

== Source File Map
<source-file-map>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[File]], [#strong[Role]],),
    table.hline(),
    [`Source/Pipeline/prover.pl`], [Core proof engine, reprove retry
    loop, cycle detection, learned store],
    [`Source/Domain/Gentoo/rules.pl`], [Domain rules: entry rules,
    grouped deps, `rule(assumed(_),[])`],
    [`Source/Domain/Gentoo/Rules/candidate.pl`], [Candidate selection,
    reprove triggers, parent narrowing],
    [`Source/Domain/Gentoo/Rules/heuristic.pl`], [Reprove state
    management, reject accumulation],
    [`Source/Domain/Gentoo/Rules/memo.pl`], [Thread-local caches
    including `requse_violation_/3`],
    [`Source/Domain/Gentoo/Rules/use.pl`], [`verify_required_use_with_bwu`,
    `describe_required_use_violation`],
    [`Source/Pipeline/Prover/explanation.pl`], [`assumption_reason_for_grouped_dep`
    diagnosis],
    [`Source/Pipeline/Prover/explainer.pl`], [`term_ctx/2`, "why"
    queries],
    [`Source/Pipeline/Printer/Plan/assumption.pl`], [Assumption type
    classification],
    [`Source/Pipeline/Printer/Plan/warning.pl`], [Assumption detail
    rendering],
  )]
  , kind: table
  )

== Progressive Relaxation
<progressive-relaxation>
#figure(image("Diagrams/09-progressive-relaxation.svg", alt: "Progressive relaxation tiers"),
  caption: [
    Progressive relaxation tiers
  ]
)

Not every dependency graph can be satisfied under the strictest
interpretation of the repository metadata. A package may exist only with
an unstable keyword, or be masked by the profile, or conflict with an
already-installed blocker. Rather than giving up at the first such
obstacle, the pipeline applies #strong[progressive relaxation]: it
re-runs the entire proof under successively weaker constraints until a
complete plan emerges.

The mechanism lives in `pipeline:prove_plan_with_fallback/6`. Each tier
wraps the prover call inside `prover:assuming/2`, which sets a dynamic
flag that the domain rules consult at decision points.

#figure(
  align(center)[#table(
    columns: (15%, 42.5%, 42.5%),
    align: (left,left,left,),
    table.header([#strong[Tier]], [#strong[`assuming`
      flag]], [#strong[What is relaxed]],),
    table.hline(),
    [1 (strict)], [none], [All masks, keywords, and blockers enforced],
    [2], [`keyword_acceptance`], [Unstable keywords (`~amd64`)
    accepted],
    [3], [`blockers`], [Blocker constraints downgraded to warnings],
    [4], [`unmask`], [Masked packages unmasked],
    [5], [`keyword_acceptance` + `unmask`], [Both relaxations combined
    (last resort)],
  )]
  , kind: table
  )

The tiers are tried in order via Prolog's semicolon (`;`) disjunction
--- a compact encoding that reads like an `if-elif-else` chain but
relies on backtracking. The first tier whose `prove_plan` succeeds
commits and returns a `FallbackUsed` tag (`false`, `keyword_acceptance`,
`blockers`, `unmask`, or `keyword_unmask`).

=== How `assuming/2` works
<how-assuming2-works>
`prover:assuming(Flag, Goal)` stores a dynamic flag
(`prover_assuming_<Flag>`) for the duration of `Goal`, using
`setup_call_cleanup` to guarantee cleanup even on exceptions. Domain
predicates test this flag with the zero-argument
`prover:assuming(Flag)`:

- #strong[`candidate:eligible/1`] --- when `keyword_acceptance` is
  active, candidates with any keyword are accepted; when `unmask` is
  active, masked candidates pass.
- #strong[`candidate:accepted_keyword_candidate/7`] --- two fallback
  clauses widen the candidate pool: one for unstable keywords, one for
  masked packages.
- #strong[`candidate:assume_blockers/0`] --- returns `true` when blocker
  constraints should become warnings instead of hard failures.

=== Suggestion tags
<suggestion-tags>
When a relaxation flag is active and a candidate is admitted under that
relaxation, the domain tags the literal's context with a
#strong[`suggestion/2`] term that records exactly which configuration
change would eliminate the need for the relaxation:

#figure(
  align(center)[#table(
    columns: (42.11%, 23.68%, 34.21%),
    align: (left,left,left,),
    table.header([#strong[Suggestion
      tag]], [#strong[Meaning]], [#strong[Target file]],),
    table.hline(),
    [`suggestion(accept_keyword, '~amd64')`], [Accept the unstable
    keyword], [`package.accept_keywords`],
    [`suggestion(unmask, R://E)`], [Unmask the
    package], [`package.unmask`],
    [`suggestion(use_change, R://E, Changes)`], [Adjust USE
    flags], [`package.use`],
  )]
  , kind: table
  )

These tags flow through the proof into the plan output. In builder mode,
`builder:dispatch_suggestions/1` can apply the suggestions automatically
(writing to `/etc/portage/package.*` files); in pretend mode, they
appear as actionable hints in the plan output.

=== Formal guarantee
<formal-guarantee>
Each tier still produces a #strong[complete proof] --- the plan is
always coherent and fully ordered. The relaxation only widens the
candidate pool; it does not skip proof obligations or bypass constraint
guards. The suggestion tags make it possible to #strong[trace back]
every relaxation to a concrete configuration change, so the weaker proof
can be strengthened incrementally.

== CDCL Connection
<cdcl-connection>
The learned constraint store is analogous to CDCL (Conflict-Driven
Clause Learning) in SAT solvers, but expressed as version domains rather
than boolean clauses:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[CDCL concept]], [#strong[portage-ng
      equivalent]],),
    table.hline(),
    [Conflict analysis], [Constraint guard detecting domain
    inconsistency],
    [Learned
    clause], [`prover:learn(cn_domain(C,N,S), NarrowedDomain, _)`],
    [Unit propagation], [`grouped_dep_effective_domain` applying learned
    domains],
    [Restart], [`prover_reprove` catch-and-retry loop],
    [Decision level], [Reprove attempt number],
  )]
  , kind: table
  )

The key difference is granularity: CDCL operates on boolean variables,
while portage-ng operates on version domains --- structured sets that
carry more information per constraint.

== Further reading
<further-reading-8>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- the proof search
  algorithm
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  domain operations used by constraint learning
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- entry
  rules, fallback chains, and REQUIRED\_USE handling
- #link("21-doc-resolver-comparison.md")[Chapter 21: Resolver Comparison]
  --- Zeller, Vermeir, and CDCL foundations

= Version Domains
<version-domains>
Version domains are the mechanism by which portage-ng reasons about
version constraints. Every version comparison, every dependency operator
(`>=`, `<=`, `~`, `=*`), and every learned constraint is expressed as an
operation on version domains.

== Why version domains matter
<why-version-domains-matter>
Picture two packages that both pull in `dev-libs/openssl`, but with
different requirements. Package A depends on `>=dev-libs/openssl-3.0`:
any OpenSSL from 3.0 upward is acceptable on that path. Package B
depends on `<dev-libs/openssl-3.2`: only versions strictly below 3.2 are
acceptable there. If both constraints apply to the same install, you are
not looking for a single magic number first --- you are asking which
versions lie in the overlap of two sets. Versions that satisfy both are
exactly those in #strong[3.0 ≤ v \< 3.2]: the half-open interval
#strong[\[3.0, 3.2)].

That overlap is the #strong[intersection] (in domain terms, the
#strong[meet]) of two version domains. Version domains represent
#strong[sets] of acceptable versions; combining constraints from
different dependency paths means intersecting those sets until you
obtain the tightest description still compatible with everything seen so
far. The rest of this chapter spells out how those sets are stored,
compared, and merged in code.

== Version representation
<version-representation>
Versions are stored as `version/7` compound terms:

```prolog
version(NumsNorm, Alpha, SuffixRank, SuffixNum, SuffixRest, Rev, Full)
```

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Field]], [#strong[Example]], [#strong[Meaning]],),
    table.hline(),
    [`NumsNorm`], [`[3,0,77]`], [Normalized numeric components],
    [`Alpha`], [`''` or `'a'`], [Alpha suffix (empty atom if none)],
    [`SuffixRank`], [`4`], [Numeric rank of version suffix (`_alpha`=1,
    `_beta`=2, `_pre`=3, `_rc`=4, (none)=5, `_p`=6)],
    [`SuffixNum`], [`0`], [Suffix number (e.g.~`3` in `_rc3`)],
    [`SuffixRest`], [`''`], [Additional suffix components],
    [`Rev`], [`3`], [Revision number (from `-r3`)],
    [`Full`], [`'3.0.77-r3'`], [Original version string],
  )]
  , kind: table
  )

Empty or absent versions use the atom `version_none`.

== Version comparison
<version-comparison>
Versions are compared using Prolog's standard `compare/3` directly on
the compound term. No runtime key conversion is needed --- the
`version/7` structure is designed so that standard term ordering
produces correct PMS version ordering:

```prolog
compare(Order, version([3,0,77],...), version([3,1,0],...))
% Order = (<)
```

This works because: - `NumsNorm` is a list of integers (lexicographic
list comparison) - `SuffixRank` maps suffixes to integers in PMS order -
`Rev` is a plain integer

== Version domain model
<version-domain-model>
A version domain represents a set of acceptable versions for a package.
It is stored as:

```prolog
version_domain(Slots, Bounds)
```

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Field]], [#strong[Type]], [#strong[Meaning]],),
    table.hline(),
    [`Slots`], [list or `any`], [Acceptable slots (or `any` for
    unconstrained)],
    [`Bounds`], [structured term], [Version bounds (upper, lower, exact,
    wildcard)],
  )]
  , kind: table
  )

The `none` atom represents an unconstrained domain (all versions
accepted).

== Domain operations
<domain-operations>
=== Domain meet (intersection)
<domain-meet-intersection>
#figure(image("Diagrams/10-domain-meet.svg", alt: "Domain meet examples"),
  caption: [
    Domain meet examples
  ]
)

When two dependency paths impose different version constraints on the
same package, the domains are intersected:

```prolog
version_domain:domain_meet(Domain1, Domain2, Intersection)
```

The intersection computes the tightest bounds that satisfy both
constraints. If the intersection is empty (no version satisfies both),
the goal fails: there is no `Intersection` term that stays consistent
with the combined bounds (and related checks such as slot
compatibility).

=== Worked examples (meet in practice)
<worked-examples-meet-in-practice>
The following sketches use dependency-style wording; internally each
side becomes a `version_domain/2` (or `none`) whose bounds are merged by
`domain_meet/3`. Intuitively, #strong[meet = AND] over acceptable
versions.

#strong[Example 1 --- overlapping range.] \ Lower bound `>=1.0` and
upper bound `<2.0` describe the half-open interval #strong[\[1.0, 2.0)].
The meet is that interval: every version that satisfies both operators
is exactly a version at least 1.0 and strictly below 2.0.

#strong[Example 2 --- two lower bounds.] \ `>=1.0` meets `>=1.5`. The
stricter requirement wins: the intersection is #strong[`>=1.5`].
Anything below 1.5 was already ruled out by the second constraint.

#strong[Example 3 --- disjoint constraints (conflict).] \ `>=2.0` meets
`<1.0`. No version can be simultaneously at least 2.0 and below 1.0.
`domain_meet/3` #strong[fails] (or equivalently, the normalized domain
is rejected as inconsistent): the prover must treat this as an
unsatisfiable combined requirement, not as a wider domain.

#strong[Example 4 --- tilde vs revision-aware lower bound.] \ `~1.0` (in
PMS terms: same main version as `1.0`, any revision) restricts
candidates to the #strong[1.0] line. Meeting that with `>=1.0-r2` keeps
you on that line but drops revisions below `-r2`: the effective set is
#strong[`>=1.0-r2` within the 1.0.x family], not a broader branch of the
package.

In all cases, when the meet succeeds, candidate selection and
consistency checks use the #strong[narrower] domain; when it fails,
there is no shared non-empty set of versions to choose from.

=== Consistency check
<consistency-check>
```prolog
version_domain:domain_consistent(Domain)
```

Verifies that a domain is non-empty --- that at least one version in the
repository satisfies the bounds.

== Feature logic intuition
<feature-logic-intuition>
In Zeller-style #strong[feature logic], a #emph[feature] describes a set
of objects that share certain properties --- not necessarily a single
object, but a well-bounded #emph[set] described by those properties. A
#strong[version domain] is the same idea at the version level: it is a
feature whose extension is the set of versions that satisfy given slot
and bound constraints (above a threshold, below a threshold, exact
match, tilde range, wildcard prefix, and so on).

#strong[Feature unification] --- meeting two features so that an object
must satisfy both --- corresponds directly to #strong[domain
intersection]. This is not merely a pedagogical analogy: portage-ng
wires version domains into the generic unification hook in
`feature_unification:val_hook/3`, so that merging domain values follows
the same meet operation as `version_domain:domain_meet/3`.

A practical consequence is #strong[monotonic narrowing]: along a
resolution path, domains only become #emph[tighter] (fewer acceptable
versions), never wider, unless explicitly reset by a broader reprove
strategy. Each successful refinement shrinks the search space; that is
why successive reprove attempts can be viewed as making measurable
progress toward either a concrete choice or a clear conflict.

== Learned domain narrowing
<learned-domain-narrowing>
The prover's learned constraint store uses version domains to carry
narrowed version information across reprove retries. The key format is:

```prolog
cn_domain(Category, Name, Slot)
```

When a conflict is detected (e.g.~two dependency edges require
incompatible versions), the constraint guard learns a narrowed domain:

```prolog
prover:learn(cn_domain(Category, Name, Slot), NarrowedDomain, Added)
```

#strong[How this interacts with the prover (briefly).] \ When the prover
hits a conflict, it can record a #strong[narrowed] version domain for
the affected category--name--(slot) key. On the #strong[next] reprove
attempt, `grouped_dep_effective_domain` intersects that learned domain
with the #strong[local] domain coming from the current proof context
before candidate selection. If the intersection is #strong[non-empty],
candidates are filtered against this stricter domain, which avoids
repeating the same dead-end choice. If the intersection is
#strong[empty], there is no compatible overlap left: the path is
inconsistent and the prover can skip directly to assumption (or the
corresponding failure handling) instead of selecting candidates from an
empty domain. Chapter 9 walks through the reprove and learning mechanics
in full; Chapter 11 ties domains into rule evaluation and candidate
generation.

This is inspired by Zeller's feature logic: version sets are identified
by feature terms and configured by incrementally narrowing the set until
each component resolves to a single version.

== Version operators
<version-operators>
The EAPI grammar supports the following version operators, each
producing a different domain constraint:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Operator]], [#strong[Syntax]], [#strong[Domain
      meaning]],),
    table.hline(),
    [`>=`], [`>=cat/pkg-1.0`], [Lower bound: version \>= 1.0],
    [`<=`], [`<=cat/pkg-2.0`], [Upper bound: version \<= 2.0],
    [`>`], [`>cat/pkg-1.0`], [Strict lower bound],
    [`<`], [`<cat/pkg-2.0`], [Strict upper bound],
    [`=`], [`=cat/pkg-1.0`], [Exact version match],
    [`~`], [`~cat/pkg-1.0`], [Version match ignoring revision (any
    `-rN`)],
    [`=*`], [`=cat/pkg-1*`], [Wildcard: any version starting with `1`],
  )]
  , kind: table
  )

== Further reading
<further-reading-9>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- how domains interact with the reprove mechanism
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  version domains feed into candidate selection
- #link("21-doc-resolver-comparison.md")[Chapter 21: Resolver Comparison]
  --- Zeller's feature logic and CDCL connections

= Rules and Domain Logic
<rules-and-domain-logic>
== How we resolve dependencies
<how-we-resolve-dependencies>
Suppose the prover is asked to justify a literal such as
`portage://'sys-apps/portage-3.0.77-r3':install`. The prover itself does
not know what "install" means for Gentoo; it only knows how to search
for a `rule/2` clause whose head unifies with that literal and then
prove the body. The #strong[rules layer] is where that abstract proof
search meets Gentoo reality.

Concretely, the rules layer must answer questions the cache and metadata
already encode but the prover does not interpret on its own: what are
this ebuild's #strong[DEPEND], #strong[BDEPEND], and #strong[RDEPEND]
lines? Which #strong[USE] flags are in effect for this path through the
graph? For each atom in those dependency strings, #strong[which
repository entries] are candidates, and which #strong[version, slot, and
keyword] constraints apply? USE-conditional blocks such as
`ssl? ( dev-libs/openssl )` must be evaluated against the effective USE
set. Blockers, choice groups from #strong[REQUIRED\_USE], and ordering
hints (`after/1`, PDEPEND behaviour) all live here. Everything that is
"Portage-shaped" is folded into rule bodies and into the small
#strong[proof-term context] (`?{...}` lists) threaded alongside
literals.

The sections below follow one resolution from user target to installed
graph, then cover cycles, USE semantics, and what happens when the rules
layer must stop short and record an #strong[assumption]---often together
with a #strong[suggestion] that tells you which config change would have
avoided it.

== How dependency resolution works (end-to-end)
<how-dependency-resolution-works-end-to-end>
A typical standalone run begins with a user query such as
`sys-apps/portage`. That becomes a #strong[`target/2`] literal; the
corresponding `rule/2` clause resolves the query to the #strong[best
eligible candidate] (version order, masks, keywords, installed state)
and yields literals that drive the rest of the proof.

From there, action-specific rules apply:

- #strong[`:run`] --- Runtime obligations: #strong[RDEPEND] (and PDEPEND
  is wired in via the prover's literal hook; see
  #link(<pdepend-hooks>)[PDEPEND hooks] below). This is the "is this
  runtime environment consistent?" side of the graph.
- #strong[`:install`] --- Build-time obligations: #strong[DEPEND] and
  #strong[BDEPEND], with #strong[`after/1`] (and related ordering)
  expressing install order constraints between body literals.

Each dependency atom from the metadata is not proved as a raw string; it
is turned into a #strong[`grouped_package_dependency`] literal (and
possibly #strong[`package_dependency`] for configuration). Candidate
selection applies version ranges, slot operators, keyword and mask
policy, and the learned constraint machinery described in
#link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
and #link("10-doc-version-domains.md")[Chapter 10: Version Domains].

USE-conditional dependencies are evaluated only when the condition holds
in the #strong[effective USE] set for that ebuild and path. For example,
`ssl? ( dev-libs/openssl )` contributes `dev-libs/openssl` to the body
only if `ssl` is enabled in that effective set; otherwise that branch is
skipped. If a parent requires particular USE settings on a child, those
requirements propagate via #strong[`build_with_use`] in the proof-term
context (see #link(<use-flags-in-depth>)[USE flags in depth]).

Together, this pipeline is what the prover's depth-first search is
"walking": each successful `rule/2` expansion adds structured literals
to the proof and updates the model; failures cause backtracking to
alternate candidates or assumptions.

== The `rule/2` interface
<the-rule2-interface>
```prolog
rules:rule(+Head, -Body)
```

Given a proof literal `Head`, the rule produces a list of sub-literals
`Body` that must be proven to justify `Head`. The prover calls this
predicate without understanding what the literals mean --- all Gentoo
semantics are encapsulated here.

The main rule clauses handle:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Head pattern]], [#strong[Purpose]],),
    table.hline(),
    [`target(Q, Arg):run`], [Resolve a user target to a candidate
    ebuild],
    [`target(Q, Arg):fetchonly`], [Fetch-only target resolution],
    [`target(Q, Arg):uninstall`], [Uninstall target resolution],
    [`Repo://Ebuild:install`], [Build and install an ebuild (DEPEND +
    BDEPEND)],
    [`Repo://Ebuild:run`], [Runtime availability (RDEPEND)],
    [`Repo://Ebuild:download`], [Fetch source archives],
    [`Repo://Ebuild:fetchonly`], [Fetch only],
    [`Repo://Ebuild:depclean`], [Remove unneeded package],
    [`grouped_package_dependency(...):Action`], [Resolve a grouped
    dependency],
    [`package_dependency(...):config`], [Configure a single dependency],
    [`exactly_one_of_group(...):validate`], [Validate REQUIRED\_USE
    `^^`],
    [`any_of_group(...):validate`], [Validate REQUIRED\_USE any-of],
    [`at_most_one_of_group(...):validate`], [Validate REQUIRED\_USE
    `??`],
    [`assumed(X)`], [Catch-all for domain assumptions:
    `rule(assumed(_), [])`],
  )]
  , kind: table
  )

== Candidate resolution
<candidate-resolution>
When the rules layer needs to select a specific version of a package, it
uses the candidate resolution protocol:

=== `candidate:eligible/1`
<candidateeligible1>
Checks whether a candidate is eligible for proving. This evaluates:

- Masking (`preference:masked/1`)
- Keyword acceptance (`preference:accepted_keyword/2`)
- Installed status (VDB check)

If a candidate is not eligible and the prover is not in an `assuming`
relaxation tier, the entry rule fails, allowing backtracking to try
other candidates.

=== `candidate:resolve/2`
<candidateresolve2>
Resolves a query to a specific `Repository://Ebuild` pair. Candidates
are tried in version order (newest first) via `cache:ordered_entry/5`.

=== Fallback chain
<fallback-chain>
When all candidates are exhausted for a grouped dependency:

+ `maybe_learn_parent_narrowing` --- learn to exclude the parent version
+ `maybe_request_grouped_dep_reprove` --- throw `prover_reprove` if
  domain/constraint conflicts exist
+ Domain assumption --- emit `assumed(grouped_package_dependency(...))`
  as a last resort

== Cycles and how portage-ng handles them
<cycles-and-how-portage-ng-handles-them>
Circular dependencies are a fact of life in the Portage tree. Classic
examples include bootstrap loops (e.g.~a language runtime packaged with
tooling that itself depends on that runtime). The prover performs
backward-chaining proof search and keeps track of which literals are
#strong[currently being proved]. If the same literal is encountered
again while still on that stack, a #strong[cycle] has been detected.

The prover then asks the domain whether the cycle is #strong[benign]
before it decides to break it with an assumption. The hook is
`heuristic:cycle_benign/2`, called with the repeating literal and the
computed #strong[cycle path]. If the hook succeeds, the literal is
treated as already justified: it is added to the model #strong[without]
a cycle-break assumption (no `assumed(rule(Lit))` in the proof). If the
hook fails (or is absent), the prover records a #strong[cycle-break
assumption]: in the proof that appears under the key
`assumed(rule(Lit))`, and in the model as `assumed(Lit)`. That taxonomy
is separate from #strong[domain] assumptions introduced by rules via
`rule(assumed(X), [])`.

Benign classification is deliberately conservative and pattern-based:
for example, dependency-group literals may be treated as benign, and
cycles that pass through #strong[`:run`] (RDEPEND-mediated paths) may be
treated as ordering-style cycles rather than hard failures---mirroring
how traditional resolvers often tolerate certain cyclic patterns.

After the proof exists, #strong[cyclic portions of the `:run` side] of
the graph are still scheduled sensibly: the scheduler groups them into
#strong[strongly connected components (SCCs)] so merge ordering respects
the cycle structure. For detail on proof search and assumptions, see
#link("08-doc-prover.md")[Chapter 8: The Prover] and
#link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning].

== USE flags in depth
<use-flags-in-depth>
USE flags are not a side note; they change which dependency branches
exist, which packages are eligible, and whether #strong[REQUIRED\_USE]
constraints are satisfied.

=== Effective USE and conditionals
<effective-use-and-conditionals>
The rules layer evaluates USE-conditional atoms against the USE model:

```prolog
use:effective_use/3       % Compute effective USE for an ebuild
use:evaluate_conditional/3 % Evaluate a USE conditional (flag? or !flag?)
```

=== `build_with_use`
<build_with_use>
When a dependency path requires building (or selecting) a child with
specific USE values, those requirements are carried in the
#strong[proof-term context] as `build_with_use/1` (and related
features). They constrain how the child's effective USE is computed and
how conditional dependency branches fire, so parent choices do not
silently ignore USE implications on dependents.

=== `REQUIRED_USE`
<required_use>
PMS #strong[REQUIRED\_USE] is enforced through dedicated validation
literals (`exactly_one_of_group`, `any_of_group`,
`at_most_one_of_group`) and the same USE machinery. If the active USE
set violates REQUIRED\_USE, the corresponding rule fails and the prover
can backtrack to another candidate or flag an assumption.

=== Priority order
<priority-order>
USE flags are resolved in priority order:

+ `build_with_use` from the dependency context (parent's USE
  requirements)
+ User configuration (`/etc/portage/package.use`)
+ Profile defaults
+ Ebuild IUSE defaults

#strong[Context wins over profile defaults]: a `build_with_use`
requirement from the parent path can force or forbid a flag regardless
of what the profile would otherwise choose. That is why two proofs for
the "same" package can differ: they may arrive with different proof-term
contexts.

=== Conflicts and backtracking
<conflicts-and-backtracking>
When USE-derived constraints conflict---REQUIRED\_USE fails, a
conditional branch does not apply as expected, or eligibility checks
fail---the relevant `rule/2` clause fails. The prover then
#strong[backtracks]: another candidate version, another slot choice, or
another branch of the search may succeed. If no branch succeeds without
relaxing policy, the candidate layer may emit a #strong[domain
assumption] (see
#link(<assumptions-as-proposals>)[Assumptions as proposals]), often
tagged with a concrete #strong[suggestion] for your `package.use` or
related config.

== Choice groups
<choice-groups-1>
PMS choice groups are handled as validation literals:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Operator]], [#strong[Rule
      clause]], [#strong[Semantics]],),
    table.hline(),
    [any-of ( a b c )], [`any_of_group(Deps):validate`], [At least one
    must be satisfied],
    [`^^ ( a b c )`], [`exactly_one_of_group(Deps):validate`], [Exactly
    one must be satisfied],
    [`?? ( a b c )`], [`at_most_one_of_group(Deps):validate`], [At most
    one may be satisfied],
  )]
  , kind: table
  )

== Slot operators
<slot-operators>
Slot operators in dependency atoms affect how the rules layer processes
dependencies:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Operator]], [#strong[Meaning]], [#strong[Context
      effect]],),
    table.hline(),
    [`:SLOT`], [Depend on a specific slot], [Filters candidates to
    slot],
    [`:*`], [Any slot acceptable], [No slot constraint],
    [`:=`], [Sub-slot rebuild], [Adds `slot(C,N,Ss):{Candidate}` to
    context],
    [`:SLOT=`], [Specific slot + rebuild], [Both slot filter and
    rebuild],
  )]
  , kind: table
  )

== Blockers
<blockers>
Blocker dependencies (`!cat/pkg` and `!!cat/pkg`) are processed by
`candidate.pl`:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Type]], [#strong[Syntax]], [#strong[Behavior]],),
    table.hline(),
    [Weak blocker], [`!cat/pkg`], [Package should not be present;
    resolved at plan time],
    [Strong blocker], [`!!cat/pkg`], [Package must not be present;
    constraint guard fires immediately],
  )]
  , kind: table
  )

Blockers emit `blocked_cn` constraint terms that interact with
`selected_cn` constraints via `selected_cn_not_blocked_or_reprove`.

== PDEPEND hooks
<pdepend-hooks>
PDEPEND dependencies are resolved single-pass inside the prover via
`rules:literal_hook/4`. When a literal is proven, the hook checks for
PDEPEND entries and injects them as proof obligations. This avoids a
separate PDEPEND resolution pass.

== Assumptions as proposals
<assumptions-as-proposals>
When strict resolution cannot finish without relaxing Gentoo policy, the
rules layer records #strong[domain assumptions] (proof key
`rule(assumed(X))`, distinct from prover cycle-break keys
`assumed(rule(Lit))`). From a user perspective, the important point is
that an assumption is not merely a dead end: the literal's
#strong[proof-term context] is often annotated with #strong[suggestion]
terms that spell out a concrete remediation.

Typical forms include `suggestion(unmask, ...)`,
`suggestion(accept_keyword, ...)`, and
`suggestion(use_change, ..., Changes)` (USE adjustments), among others.
The printer collects these tags and surfaces them next to the assumption
so you see #strong[what to change] in `/etc/portage` (or equivalent).
The #strong[plan is still constructed] as if that change had been
applied: the proof completes, the merge list is coherent under the
stated proposal, and the output tells you which configuration delta
would align the real system with that plan. For the full assumption and
learning story, see
#link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning].

== Rules submodules
<rules-submodules>
The rules layer is split across several submodules under
`Source/Domain/Gentoo/Rules/`:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Module]], [#strong[File]], [#strong[Purpose]],),
    table.hline(),
    [`memo`], [`memo.pl`], [Thread-local caches (selected candidates,
    violations)],
    [`use`], [`use.pl`], [USE flag evaluation, REQUIRED\_USE checking],
    [`candidate`], [`candidate.pl`], [Candidate selection, eligibility,
    reprove triggers],
    [`heuristic`], [`heuristic.pl`], [Reprove state, retry budgets,
    cycle benignity],
    [`dependency`], [`dependency.pl`], [Dependency model construction,
    context threading],
    [`target`], [`target.pl`], [Target resolution (query to candidate)],
    [`featureterm`], [`featureterm.pl`], [Context stripping for
    memoization],
  )]
  , kind: table
  )

== Further reading
<further-reading-10>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the prover
  calls `rule/2`
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  how version constraints feed into candidate selection
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- the fallback chain in detail

= Planning and Scheduling
<planning-and-scheduling>
== Why parallel planning?
<why-parallel-planning>
Traditional package managers (Portage, apt, and similar) typically
expose a #strong[sequential] plan to the user: install #emph[A], then
#emph[B], then #emph[C]. Even when the underlying resolver knows that
#emph[B] does not depend on #emph[A], the presented order is often a
single linear timeline.

portage-ng takes a different stance: it produces #strong[parallel] plans
from the start. Wave 1 might download #emph[A], #emph[B], and #emph[C]
concurrently; wave 2 might install #emph[A] while #emph[D] is still
downloading; wave 3 might install #emph[B] and #emph[C] together, and so
on. This is #strong[not] a post-processing optimization layered on top
of a linear schedule. Parallelism is computed #strong[during] planning,
as a natural consequence of Kahn's topological sort: at each step, every
literal whose prerequisites are satisfied is eligible at once, and that
set is exactly one parallel wave.

On a multi-core machine with fast I/O, overlapping work this way can
dramatically reduce wall-clock time compared to a strictly sequential
narrative.

Planning is also at the #strong[action] level, not the package level.
The same logical package may appear as separate literals for download,
install, run, and so on. Those actions can therefore land in different
waves: one package can still be downloading while another is already
installing, whenever the dependency graph allows it.

After the prover completes, the proof must be converted into an
executable plan --- an ordered sequence of actions with maximal
parallelism. This is done in two stages: wave planning for the acyclic
portion, and SCC scheduling for any cyclic remainder.

== Dependency types and scheduling
<dependency-types-and-scheduling>
Gentoo's dependency classes do not all impose the same ordering
strength. The rules layer records that distinction in #strong[proof-term
context] (`?{…}` on each literal): dependency edges and ordering hints
are derived from markers such as `after/1` and `after_only/1`. The
planner turns those into edges in its dependency graph (including
ordering-only constraints where appropriate).

Roughly:

- #strong[DEPEND] and #strong[BDEPEND] --- build-time dependencies. They
  must be satisfied before the build can start, so they contribute
  #strong[hard ordering]: the consumer's build-related actions wait on
  the resolved dependencies.

- #strong[RDEPEND] --- runtime dependencies. They must be satisfied
  before the package can be #emph[used] at runtime. The ordering is
  #strong[looser] than pure build ordering: the prover and feature-term
  layer can represent this with `after_only/1` so that runtime ordering
  is enforced where needed without treating every runtime edge like a
  build blocker.

- #strong[PDEPEND] --- post-install dependencies. They are resolved
  #strong[after] the main proof pass (via hooks in the rules layer).
  That late binding can introduce or surface #strong[cycles] that wave
  planning alone cannot schedule; those literals become
  #strong[remainder] work for the SCC scheduler.

- #strong[IDEPEND] --- install-time dependencies (EAPI 8+). They
  constrain ordering around the install phase specifically, again
  flowing through the same context and planner machinery as the other
  classes.

For the exact mapping from PMS ordering to internal edges and
constraints, see
#link("22-doc-dependency-ordering.md")[Chapter 22: Dependency Ordering].
The implementation detail lives in the rules and `featureterm` helpers:
`after/1` propagates as a real dependency relation, while `after_only/1`
can be lowered to ordering constraints (for example
`constraint(order_after(…))`) that the planner respects without
overstating build-time blocking.

== Wave planning (Kahn's algorithm)
<wave-planning-kahns-algorithm>
#figure(image("Diagrams/12-wave-planning.svg", alt: "Wave planning example"),
  caption: [
    Wave planning example
  ]
)

The planner (`Source/Pipeline/planner.pl`) uses Kahn's algorithm to
produce a topological ordering of the proof graph with parallelism
computed from the start.

=== Why Kahn's algorithm?
<why-kahns-algorithm>
Kahn's algorithm is simple, correct for DAGs, and #strong[naturally]
exposes parallelism. At each iteration it collects every node whose
#strong[in-degree] has dropped to zero --- that set is precisely the set
of actions that may run #strong[concurrently] at that stage. No second
pass is required to "discover" parallel groups.

A common alternative is a #strong[DFS-based] topological sort. That
yields a #strong[single] linear ordering (one valid sequence), but it
does #strong[not] identify which steps are independent: you get #emph[a]
order, not #emph[all] maximal parallel layers. For a build planner that
wants explicit waves, Kahn's layer-by-layer behavior is the better fit.

=== How it works
<how-it-works>
+ #strong[Build dependency counts.] For each rule in the Proof AVL,
  count how many of its body literals are "real" dependencies (not
  already installed, not assumed).

+ #strong[Initialize the ready queue.] Literals with zero dependencies
  form the first wave --- they can be executed immediately.

+ #strong[Process waves.] For each wave:

  - Remove all ready literals from the graph.
  - Decrement dependency counts for all heads that depended on them.
  - Literals whose count reaches zero join the next wave.

+ #strong[Repeat] until no more literals can be scheduled.

The result is a list of waves, where all literals within a wave can be
executed concurrently:

```
Wave 1: [download(A), download(B), download(C)]
Wave 2: [install(A), download(D)]
Wave 3: [install(B), install(C)]
Wave 4: [install(D), run(A)]
```

=== Parallelism
<parallelism>
Actions within a wave are independent and can run in parallel. The
planner computes the maximum parallelism at each wave, enabling the
printer to show concurrent execution groups and the builder to schedule
actual parallel builds.

=== Remainder
<remainder>
Literals that are part of cycles cannot be scheduled by Kahn's algorithm
(their dependency counts never reach zero). These are returned as the
#strong[remainder] for the scheduler to handle.

== SCC decomposition (Kosaraju)
<scc-decomposition-kosaraju>
#figure(image("Diagrams/12-scc-scheduling.svg", alt: "SCC scheduling example"),
  caption: [
    SCC scheduling example
  ]
)

The scheduler (`Source/Pipeline/scheduler.pl`) processes the remainder
using Kosaraju's algorithm for Strongly Connected Component (SCC)
decomposition.

=== Why Kosaraju for cycles?
<why-kosaraju-for-cycles>
Some dependency graphs contain #strong[genuine cycles] (for example
mutual runtime-style dependencies such as Python ↔ setuptools). Kahn's
algorithm never schedules nodes inside a directed cycle: their in-degree
inside that subgraph never all reaches zero at once in a way that drains
the cycle, so those literals stall as #strong[remainder].

#strong[Kosaraju's algorithm] computes #strong[strongly connected
components] --- maximal sets of nodes that are mutually reachable along
directed edges. Each SCC is either acyclic internally (a single node) or
a true "blob" of mutual dependence. For #strong[`:run`] SCCs
(runtime-oriented cycles), the scheduler forms #strong[merge-sets]:
packages that must be treated as #strong[available together], which
aligns with #strong[PMS] semantics for runtime cycles (Portage and
Paludis handle this class similarly). Thus Kosaraju is not an arbitrary
graph ornament; it is the bridge between "Kahn left these literals
behind" and "here is the semantically correct grouped handling for
cyclic runtime dependencies."

=== How it works
<how-it-works-1>
+ #strong[Build the dependency graph] from the remainder rules.
+ #strong[Compute SCCs] using Kosaraju's two-pass algorithm:
  - First pass: DFS on the original graph, recording finish order.
  - Second pass: DFS on the transposed graph in reverse finish order.
  - Each DFS tree in the second pass is an SCC.
+ #strong[Classify SCCs:]
  - Single-node SCCs are scheduled directly.
  - Multi-node SCCs are checked for merge-set eligibility.

=== Merge-sets
<merge-sets>
For `:run` SCCs (runtime-only cycles), the scheduler produces a
merge-set --- a group of packages that must be merged together. This
matches PMS semantics: runtime dependency cycles are not
ordering-significant (both Portage and Paludis handle them similarly).

The merge-set is added to the plan as a special group, and the printer
renders it with a cycle explanation.

== Plan output
<plan-output>
The final plan is a list of entries, each annotated with:

- #strong[Wave number] --- which parallel wave it belongs to
- #strong[Action] --- download, install, run, etc.
- #strong[Literal] --- the full `Repo://Entry:Action?{Context}` term
- #strong[Group] --- for merge-sets, which SCC group it belongs to

The plan is consumed by the printer for terminal output and by the
builder for execution.

== Further reading
<further-reading-11>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the Proof AVL
  is constructed
- #link("13-doc-building.md")[Chapter 13: Building and Execution] ---
  how the plan is executed
- #link("15-doc-output.md")[Chapter 15: Output and Visualization] ---
  how the plan is rendered
- #link("22-doc-dependency-ordering.md")[Chapter 22: Dependency Ordering]
  --- PMS ordering semantics

= Building and Execution
<building-and-execution>
portage-ng focuses on reasoning --- proving, planning, and scheduling.
Actual package building is delegated to Portage's own ebuild
infrastructure, so the full ecosystem of ebuilds, eclasses, and phase
functions works unchanged.

== Build delegation
<build-delegation>
When executing a plan (via `--merge` rather than `--pretend`), the
builder module invokes the `ebuild` command for each action in the plan.
The `ebuild` command is configurable via `config:ebuild_command/1`
(default: `ebuild`).

The builder processes the plan wave by wave, respecting the parallelism
computed by the planner. Within each wave, independent actions can run
concurrently.

== Ebuild phase execution
<ebuild-phase-execution>
The `ebuild_exec.pl` module handles the actual invocation of ebuild
phases:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Phase]], [#strong[ebuild
      command]], [#strong[When]],),
    table.hline(),
    [`setup`], [`ebuild <path> setup`], [Before building],
    [`unpack`], [`ebuild <path> unpack`], [Extract source archives],
    [`prepare`], [`ebuild <path> prepare`], [Apply patches],
    [`configure`], [`ebuild <path> configure`], [Run configure scripts],
    [`compile`], [`ebuild <path> compile`], [Build from source],
    [`install`], [`ebuild <path> install`], [Install to staging area],
    [`qmerge`], [`ebuild <path> qmerge`], [Merge to live filesystem],
  )]
  , kind: table
  )

Phases are executed via `process_create` with output captured for
logging. The builder uses `sh` to wrap `ebuild` calls with redirection
for asynchronous, logged execution.

== Build time estimation
<build-time-estimation>
The `buildtime.pl` module predicts build duration from two data sources:

+ #strong[VDB sizes] --- the installed file sizes from
  `/var/db/pkg/*/SIZE` correlate with build complexity.

+ #strong[emerge.log history] --- historical build times from
  `/var/log/emerge.log` provide empirical timing data for packages that
  have been built before.

The `--estimate` CLI option shows predicted build times in the plan
output.

== Jobserver
<jobserver>
The `jobserver.pl` module manages parallel build execution. It
implements a token-based jobserver that limits concurrent builds to the
number of available cores (or a user-specified `--jobs` count).

== Download management
<download-management>
The `download.pl` module handles source archive fetching:

- Mirror layout detection via `curl`
- Parallel downloads across multiple mirrors
- Hash verification via `openssl dgst`
- Resume support for interrupted downloads

Downloads are scheduled as early as possible in the plan --- the planner
treats `:download` actions as the first wave, so packages can download
while others are building.

== Snapshot support
<snapshot-support>
The `snapshot.pl` module provides system state snapshot and restore:

- `--snapshot` saves the current VDB state
- Snapshots can be restored to roll back failed builds
- Uses `ebuild <path> quickpkg` for binary package creation

== Further reading
<further-reading-12>
- #link("12-doc-planning.md")[Chapter 12: Planning and Scheduling] ---
  how the plan is constructed
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] ---
  `--merge`, `--jobs`, `--estimate` flags
- #link("15-doc-output.md")[Chapter 15: Output and Visualization] ---
  build progress display

= Command-Line Interface
<command-line-interface>
portage-ng is meant to sit beside Portage, not replace it in name or
habit. Many flags will feel immediately familiar: `--pretend`,
`--verbose`, `--emptytree`, and the usual resolution switches mirror
what you already use with emerge-style workflows. On top of that, a
proof-based resolver can expose tools that a traditional dependency
solver does not: `--explain` and `--llm` for plan dialogue, `--variants`
for USE-sensitive alternatives, and `--search` that can treat a phrase
as a natural-language query when structured parsing does not apply.

The CLI is organized around one idea: #strong[every invocation either
reasons about packages or acts on them.] Reasoning covers dry-runs,
search, similarity, estimates, upstream checks, Bugzilla lookup, and
anything that inspects the knowledge base without changing the system.
Acting covers merge, unmerge, depclean, fetch-only, and sync-style
maintenance. Keeping that distinction in mind makes it easier to choose
flags and to script portage-ng safely (often pairing `--pretend` with
exploratory options before any real merge).

== Modes
<modes>
portage-ng operates in one of five modes, selected with `--mode`:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Mode]], [#strong[Description]],),
    table.hline(),
    [`standalone`], [Full local operation --- the default and most
    common mode],
    [`daemon` / `ipc`], [IPC daemon accessible via Unix socket],
    [`client`], [Remote RPC client connecting to a server],
    [`worker`], [Compute node for distributed proving (polls server for
    jobs)],
    [`server`], [HTTP + Pengines server with job/result queues],
  )]
  , kind: table
  )

=== Standalone
<standalone-1>
Loads the full pipeline, knowledge base, and domain modules. All
resolution, planning, and building happens locally.

=== Client/Server
<clientserver>
The server hosts the knowledge base and distributes proving jobs.
Workers connect, poll for jobs, prove them locally, and return results.
See
#link("17-doc-tls-certificates.md")[Chapter 17: Distributed Proving].

== Actions
<actions>
Actions are grouped by area. Use the tables below as a quick map from
flags to behaviour; the sections that follow add context on targets,
search, and everyday workflows.

=== Merge and resolution
<merge-and-resolution>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--pretend`], [Generate and display a build plan (dry-run)],
    [`--merge`], [Execute the build plan],
    [`--unmerge <target>`], [Remove a package],
    [`--depclean`], [Remove unneeded packages],
    [`--fetchonly`], [Fetch source archives only],
  )]
  , kind: table
  )

=== Information
<information>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--search <query>`], [Search packages (supports natural-language
    via embeddings)],
    [`--similar <target>`], [Find packages similar to target (vector
    similarity)],
    [`--info`], [Display repository statistics and configuration],
    [`--installed`], [List installed packages],
  )]
  , kind: table
  )

=== Repository management
<repository-management>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--sync`], [Sync the Portage tree and regenerate caches],
    [`--regen`], [Regenerate md5-cache incrementally],
  )]
  , kind: table
  )

=== Visualization
<visualization>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--graph`], [Generate interactive SVG dependency graphs],
    [`--estimate`], [Show build time estimates],
  )]
  , kind: table
  )

=== Diagnostics
<diagnostics>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--bugs <target>`], [Search Gentoo Bugzilla for known issues],
    [`--upstream <target>`], [Check upstream versions via Repology],
    [`--explain` / `--llm`], [Get AI-assisted plan explanation],
    [`--variants`], [Show plan variants with different USE
    configurations],
    [`--shell`], [Drop into an interactive Prolog shell],
  )]
  , kind: table
  )

== Options
<options>
=== Resolution options
<resolution-options>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Effect]],),
    table.hline(),
    [`--emptytree`], [Prove all dependencies from scratch (ignore VDB)],
    [`--onlydeps`], [Prove only dependencies, not the target itself],
    [`--deep`], [Deep dependency resolution],
    [`--newuse`], [Detect USE flag changes requiring rebuilds],
    [`--update`], [Update to newest version],
  )]
  , kind: table
  )

=== Output options
<output-options>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Effect]],),
    table.hline(),
    [`--verbose`], [Verbose output (show USE flags, slot info)],
    [`--quiet`], [Minimal output],
    [`--ci`], [Non-interactive CI mode (exit codes 0/1/2)],
    [`--jobs N`], [Number of parallel jobs],
    [`--timeout N`], [Kill after N seconds (requires Python 3)],
  )]
  , kind: table
  )

== Target syntax
<target-syntax>
Targets can be specified in several formats:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Format]], [#strong[Example]], [#strong[Meaning]],),
    table.hline(),
    [`cat/pkg`], [`sys-apps/portage`], [Resolve latest version],
    [`=cat/pkg-ver`], [`=sys-apps/portage-3.0.77`], [Exact version],
    [`>=cat/pkg-ver`], [`>=dev-lang/python-3.10`], [Version constraint],
    [`@set`], [`@world`], [Package set],
    [`pkg`], [`portage`], [Ambiguous name (searched across categories)],
  )]
  , kind: table
  )

== CI mode
<ci-mode>
Use `--ci` for non-interactive automation. Exit codes indicate plan
quality:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Code]], [#strong[Meaning]],),
    table.hline(),
    [0], [Plan completed with no assumptions],
    [1], [Plan completed with prover cycle-break assumptions only],
    [2], [Plan completed with domain assumptions (e.g.~missing deps)],
  )]
  , kind: table
  )

Example:

```bash
portage-ng --ci --pretend sys-apps/portage
echo $?  # 0, 1, or 2
```

By default, portage-ng runs in standalone mode. Other modes (distributed
client, server, worker) are covered in the advanced topics chapters.

== The dev wrapper
<the-dev-wrapper>
When running from a source checkout, use the dev wrapper instead of the
installed binary:

```bash
./Source/Application/Wrapper/portage-ng-dev --pretend sys-apps/portage
```

The wrapper sets up the correct load paths, stack limits, and Prolog
flags. It also supports `--timeout N` (requires Python 3) to kill the
process after N seconds. For reproducible, non-interactive runs, pipe
queries via a here-doc:

```bash
./Source/Application/Wrapper/portage-ng-dev --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL
```

== Tips and tricks
<tips-and-tricks>
Short recipes that match how people actually use the tool:

- #strong[What does portage-ng think about this package?] \
  `portage-ng --pretend --verbose cat/pkg` --- full plan with enough
  detail to compare against emerge-style output.

- #strong[Why is this package in my plan?] \
  `portage-ng --pretend --explain cat/pkg` --- ask the explainer/LLM
  path to narrate the plan (see
  #link("16-doc-explainer.md")[Chapter 16: Semantic Search and LLM Integration]).

- #strong[What would change if I enabled this USE flag?] \
  `portage-ng --pretend --variants cat/pkg` --- surface alternative
  proofs when USE sets differ.

- #strong[Find packages related to #emph[X]] \ `portage-ng --search "X"`
  --- natural-language / semantic search when the query is not
  structured (requires embeddings; same chapter as above). For an exact
  package name, use a structured atom such as `name=vim` (the same
  intent as "`name:X`" in prose, but the CLI grammar uses `=` for
  equality, not a single `name:X` token). Category and other fields work
  the same way (`category=…`); see
  #link(<search-query-language>)[Search query language] below.

- #strong[Show me similar packages] \ `portage-ng --similar cat/pkg` ---
  vector similarity from the same embedding stack as semantic search.

- #strong[Quick scripted session] \ Here-doc into the Prolog shell so
  the full load graph matches interactive use:

  ```sh
  portage-ng --mode standalone --shell <<'PL'
  prover:test_stats(portage).
  halt.
  PL
  ```

- #strong[CI / automation] \ `portage-ng --ci --pretend cat/pkg` ---
  non-interactive; interpret exit codes: `0` no assumptions, `1`
  cycle-break assumptions only, `2` domain assumptions present.

- #strong[Estimate build time] \ `portage-ng --estimate cat/pkg` ---
  build-time hints from VDB and history.

- #strong[Check for upstream updates] \ `portage-ng --upstream cat/pkg`
  --- Repology-oriented upstream comparison.

- #strong[Search Bugzilla] \ `portage-ng --bugs cat/pkg` ---
  Bugzilla-oriented diagnostics for the target.

== Search query language
<search-query-language>
The `--search` flag accepts #strong[structured] queries built from one
or more command-line atoms. Each atom is a #emph[key], a
#emph[comparator], and a #emph[value] (see
#link(<fuzzy-and-wildcard-search>)[Fuzzy and wildcard search] for the
comparators). When the argument list does #strong[not] parse as that
structured form, the text is joined and passed to #strong[semantic]
(natural-language) search instead.

```bash
portage-ng --search name=vim category=app-editors
portage-ng --search license=GPL-2 keywords=amd64
portage-ng --search "text editor with syntax highlighting"  # semantic search
```

Semantic search requires Ollama with a loaded embedding model. See
#link("16-doc-explainer.md")[Chapter 16: Semantic Search and LLM Integration].

=== Fuzzy and wildcard search
<fuzzy-and-wildcard-search>
Structured search uses explicit comparators on the key:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Comparator]], [#strong[Meaning]], [#strong[Example]],),
    table.hline(),
    [`=`], [Exact match on the value], [`name=vim`],
    [`~`], [Fuzzy match (approximate / substring-style,
    key-dependent)], [`name~vim`],
    [`:=`], [Wildcard match (`*` in the value)], [`name:=*vim*`],
  )]
  , kind: table
  )

#strong[Exact search] --- constrain the package name or another field
precisely, e.g. `--search name=vim` (exact package name). In
documentation you may see this described informally as `name:vim`\; on
the command line the equality comparator is `=` (`:` introduces the `:=`
wildcard operator instead).

#strong[Category filter] --- `category=app-editors` (or combine with
other atoms on the same command line).

#strong[Natural language] --- a query that does not parse as structured
keys, e.g. `--search "text editor with syntax highlighting"`, uses
vector embeddings over the knowledge base (when enabled and indexed).

#strong[Wildcard] --- use `:=` so `*` is interpreted as a glob-style
wildcard, e.g. `name:=*vim*` for any package name containing `vim`.
Quote the atom if the shell would expand `*`
(e.g.~`--search 'name:=*vim*'`).

#strong[Combined filters] --- pass several atoms; each narrows the
result set, e.g. `category=dev-libs name:=*ssl*`.

== Further reading
<further-reading-13>
- #link("../Manpage/portage-ng.1.md")[`portage-ng(1)` manpage] ---
  exhaustive option reference
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- first run examples
- #link("15-doc-output.md")[Chapter 15: Output and Visualization] ---
  what the output looks like

= Output and Visualization
<output-and-visualization>
portage-ng produces several forms of output: terminal plan display,
`.merge` files, interactive SVG graphs, Gantt charts, and reports.

== Printer pipeline
<printer-pipeline>
The printer (`Source/Pipeline/printer.pl`) orchestrates plan output. It
delegates to submodules under `Source/Pipeline/Printer/`:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Module]], [#strong[File]], [#strong[Responsibility]],),
    table.hline(),
    [`plan`], [`Printer/Plan/plan.pl`], [Plan rendering (waves, actions,
    USE flags)],
    [`assumption`], [`Printer/Plan/assumption.pl`], [Assumption
    classification and display],
    [`cycle`], [`Printer/Plan/cycle.pl`], [Cycle explanation rendering],
    [`warning`], [`Printer/Plan/warning.pl`], [Assumption detail and
    warning blocks],
    [`timing`], [`Printer/Plan/timing.pl`], [Build time display],
    [`index`], [`Printer/index.pl`], [Package index display],
    [`info`], [`Printer/info.pl`], [Package info display],
    [`stats`], [`Printer/stats.pl`], [Statistics display],
    [`state`], [`Printer/state.pl`], [State tracking during printing],
    [`news`], [`Printer/News/news.pl`], [Gentoo news item display],
  )]
  , kind: table
  )

=== Plan output
<plan-output-1>
The plan is rendered as a merge list showing:

- Wave number (parallel group)
- Action type (N = new, U = update, R = reinstall, etc.)
- Package atom with version
- USE flag changes (with color coding)
- Slot and sub-slot information
- Repository source

=== Assumption printing
<assumption-printing>
Assumptions are printed in two sections:

+ #strong[Domain assumptions] --- warnings about packages that could not
  be resolved (missing, masked, keyword-filtered, REQUIRED\_USE
  violations). Each includes an actionable suggestion.

+ #strong[Cycle breaks] --- SCCs that required merge-set scheduling,
  with cycle path explanation.

== Writer module
<writer-module>
The writer (`Source/Application/Output/writer.pl`) generates `.merge`
files --- one per target package --- containing the portage-ng plan
output in a format comparable to `emerge -vp` output. These files are
stored in the graph directory and used for regression comparison against
emerge output.

== Dependency graph generation
<dependency-graph-generation>
The grapher (`Source/Application/Output/grapher.pl`) produces
interactive SVG dependency graphs via Graphviz:

+ The proof is traversed to extract dependency edges.
+ A `.dot` file is generated with nodes (packages) and edges
  (dependencies).
+ The `dot` command renders SVG output.

Graph generation is triggered by `--graph` and uses platform-specific
scripts under `Source/Application/System/Scripts/` for parallel
rendering.

=== Submodules
<submodules>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Module]], [#strong[Purpose]],),
    table.hline(),
    [`dot`], [Graphviz DOT file generation],
    [`deptree`], [Dependency tree visualization],
    [`detail`], [Detailed package view],
    [`gantt`], [Gantt chart with parallel build steps],
    [`terminal`], [Terminal-based graph rendering],
    [`navtheme`], [Navigation theme for interactive SVGs],
  )]
  , kind: table
  )

== Gantt charts
<gantt-charts>
The `gantt` module produces Gantt charts showing the parallel build
schedule. Each bar represents a package, positioned in its wave with
estimated duration. This visualizes the parallelism computed by the
planner.

== Report generation
<report-generation>
The report module (`Source/Application/Output/Report/report.pl`)
generates structured reports for analysis. Reports can include:

- Plan summaries
- Assumption breakdowns
- Performance statistics
- Comparison data

== Further reading
<further-reading-14>
- #link("12-doc-planning.md")[Chapter 12: Planning and Scheduling] ---
  how waves and parallelism are computed
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] ---
  `--graph`, `--verbose`, `--quiet` flags
- #link("23-doc-testing.md")[Chapter 23: Testing and Regression] --- how
  `.merge` files are used for regression testing

= Semantic Search and LLM Integration
<semantic-search-and-llm-integration>
portage-ng integrates with large language models for two purposes:
#strong[semantic search] over the knowledge base using vector
embeddings, and #strong[plan explanation] using natural-language
generation.

== Semantic search
<semantic-search>
The semantic search module (`Source/Application/Llm/semantic.pl`)
enables natural-language queries over the package knowledge base.

=== How it works
<how-it-works-2>
+ Package descriptions are converted to vector embeddings via Ollama's
  embedding API (default endpoint: `http://localhost:11434`).
+ Embeddings are stored in an in-memory index.
+ At query time, the search query is embedded and compared against all
  package embeddings using cosine similarity.
+ Results are ranked by similarity score.

=== Usage
<usage>
```bash
# Natural-language search
portage-ng --search "text editor with syntax highlighting"

# Find packages similar to a known package
portage-ng --similar app-editors/neovim
```

On Apple Silicon, Ollama leverages the GPU and Neural Engine for
accelerated embedding computation.

=== Prerequisites
<prerequisites-1>
Semantic search requires: - A running Ollama instance - A loaded
embedding model (configured via `config:embedding_model/1`)

== LLM-assisted plan explanation
<llm-assisted-plan-explanation>
The `--explain` / `--llm` flags send proof artifacts to an LLM for
human-readable interpretation of build plans and assumptions.

=== Provider backends
<provider-backends>
portage-ng supports multiple LLM providers, each implemented as a
separate module in `Source/Application/Llm/`:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Module]], [#strong[Provider]], [#strong[Notes]],),
    table.hline(),
    [`ollama.pl`], [Ollama], [Local inference; also provides
    embeddings],
    [`claude.pl`], [Anthropic Claude], [Requires API key],
    [`chatgpt.pl`], [OpenAI ChatGPT], [Requires API key],
    [`gemini.pl`], [Google Gemini], [Requires API key],
    [`grok.pl`], [xAI Grok], [Requires API key],
  )]
  , kind: table
  )

The default provider is set via `config:llm_default/1`. API keys and
endpoints are configured in `Source/config.pl` or via
`Source/Config/Private/` template files.

== Explainer architecture
<explainer-architecture>
```
explainer.pl                 explanation.pl
+--------------------------+ +----------------------------+
| why_in_proof/3,4         |>| why_in_proof_hook/2        |
| why_in_plan/5,6          |>| why_in_plan_hook/2         |
| why_assumption/4,5       |>| why_assumption_hook/2      |
|                          | | assumption_reason_for_     |
| assumption_content_...   | |   grouped_dep/6            |
| assumption_normalize/2   | +----------------------------+
| **term_ctx/2** |
|                          |
| explain/2,3  -----> LLM  |
| format_why_prompt/2      |
+--------------------------+
```

explainer.pl explanation.pl +--------------------------+
\+----------------------------+ | why\_in\_proof/3,4 |\>|
why\_in\_proof\_hook/2 | | why\_in\_plan/5,6 |\>| why\_in\_plan\_hook/2
| | why\_assumption/4,5 |\>| why\_assumption\_hook/2 | | | |
assumption\_reason\_for\_ | | assumption\_content\_… | | grouped\_dep/6
| | assumption\_normalize/2 | +----------------------------+ |
#strong[term\_ctx/2] | | | | explain/2,3 -----\> LLM | |
format\_why\_prompt/2 | +--------------------------+

````

`explainer.pl` is the generic, domain-agnostic introspection layer.
It answers "why" questions by inspecting proof artifacts (ProofAVL,
ModelAVL, Plan, TriggersAVL) without embedding Gentoo/Portage policy.

`explanation.pl` is the domain-specific companion. It implements enrichment
hooks that inject Gentoo/Portage context (masking, keyword filtering,
slot constraints) into the generic Why terms. It also provides
`assumption_reason_for_grouped_dep/6` for diagnosing why a dependency
resolution failed.

Each `why_*` predicate returns a structured Prolog term. The `explain/2,3`
predicates send that term to an LLM for human-readable interpretation.


## Query families

Three families of queries are supported:

- **why_in_proof**: given a literal, find how it was proven (normal rule,
  domain assumption, or prover cycle-break) and extract its body/deps.
- **why_in_plan**: given a literal and a plan, locate it in the wave-plan
  and trace a reverse-dependency path (via TriggersAVL) back to a root.
- **why_assumption**: given an assumption key, classify it (domain vs
  cycle-break vs model-only) and extract any reason tags.


## Usage

All predicates are called with the `explainer:` module prefix.


### Step 1: Obtain proof artifacts

Run the prover/planner pipeline to get the proof, model, plan, and triggers:

```prolog
Goals = [portage://'dev-libs'-'openssl':run?{[]}],
printer:prove_plan(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL).
````

Or from a `--shell` session after loading a repository:

```prolog
printer:prove_plan([portage://'dev-libs'-'openssl':run?{[]}],
                   Proof, Model, Plan, Triggers).
```

=== Step 2: Ask "why" questions
<step-2-ask-why-questions>
#strong[Why is a package in the proof?]

```prolog
Target = portage://'dev-libs'-'libffi':install,
explainer:why_in_proof(ProofAVL, Target, Why).
% Why = why_in_proof(
%          portage://'dev-libs'-'libffi':install,
%          proof_key(rule(portage://'dev-libs'-'libffi':install)),
%          depcount(3),
%          body([portage://'sys-devel'-'gcc':install, ...]),
%          ctx([...]),
%          domain_reasons([...]))      % <-- added by explanation hook
```

#strong[Why is a package in the plan?]

```prolog
Proposal = [portage://'dev-libs'-'openssl':run?{[]}],
explainer:why_in_plan(Proposal, Plan, ProofAVL, TriggersAVL,
                      portage://'sys-libs'-'zlib':install, Why).
% Why = why_in_plan(
%          portage://'sys-libs'-'zlib':install,
%          location(step(1), portage://'sys-libs'-'zlib'-'1.3.1':install?{...}),
%          required_by(path([portage://'sys-libs'-'zlib':install,
%                           portage://'dev-libs'-'openssl':install,
%                           portage://'dev-libs'-'openssl':run])))
```

#strong[Why is something assumed?]

```prolog
Key = assumed(portage://'dev-foo'-'bar':install),
explainer:why_assumption(ModelAVL, ProofAVL, Key, Type, Why).
% Type = domain,
% Why  = why_assumption(
%          assumed(portage://'dev-foo'-'bar':install),
%          type(domain),
%          term(portage://'dev-foo'-'bar':install?{[assumption_reason(missing)]}),
%          reason(missing),
%          domain_reasons([...]))      % <-- added by explanation hook
```

=== Step 3 (optional): Get a human-readable explanation via LLM
<step-3-optional-get-a-human-readable-explanation-via-llm>
```prolog
explainer:why_in_proof(ProofAVL, Target, Why),
explainer:explain(claude, Why, Response).
% Response = "openssl requires libffi as a build dependency because..."

% Or use the default LLM (from config:llm_default/1):
explainer:explain(Why, Response).
```

Available LLM services: claude, grok, chatgpt, gemini, ollama. The
default is set via `config:llm_default/1`. See `config.pl` for API keys,
models, and endpoints.

== Assumption diagnosis (explanation.pl)
<assumption-diagnosis-explanation.pl>
`explanation:assumption_reason_for_grouped_dep/6` is called on the
fallback path when no candidate satisfies all constraints. It
progressively filters candidates through:

+ Existence check → `missing`
+ Self-hosting restriction → `installed_required`
+ Mask check → `masked`
+ Slot restriction → `slot_unsatisfied`
+ Version constraints → `version_no_candidate(O,V)` / `version_conflict`
+ ACCEPT\_KEYWORDS → `keyword_filtered`
+ Fallback → `unsatisfied_constraints`

#strong[Example:]

```prolog
explanation:assumption_reason_for_grouped_dep(
  install,                                      % Action
  'dev-libs', 'missing-pkg',                    % Category, Name
  [package_dependency(install,no,'dev-libs','missing-pkg',
                      none,version_none,[],[])],
  [self(portage://'app-misc'-'foo'-'1.0')],     % Context
  Reason).
% Reason = missing
```

== Hook mechanism
<hook-mechanism>
The explainer module calls `explanation:why_*_hook(Why0, Why)` after
building its generic Why term. If the hook succeeds, the enriched Why
replaces the generic one. Each hook extracts
`domain_reason(cn_domain(C, N, Tags))` tags from the proof context and
appends them as `domain_reasons(Reasons)`.

The hooks are called automatically --- no direct invocation needed.

== Further reading
<further-reading-15>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- assumption taxonomy that the explainer queries
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- proof artifacts
  consumed by the explainer
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] ---
  `--search`, `--similar`, `--explain` flags

= Distributed Proving
<distributed-proving>
Proving the Gentoo tree is serious work. Roughly thirty-two thousand
ebuilds must be walked through the resolver, and even on capable
hardware that adds up. On a single machine, `prover:test_stats(portage)`
typically finishes in #strong[under a minute] on a twenty-eight-core
workstation --- fast enough for day-to-day development, but not the only
shape the problem takes.

What if you want the full tree proved #strong[faster] than one box
allows, or you want to drive resolution from a #strong[thin client] that
does not carry the whole knowledge base? portage-ng answers with a
#strong[client--server--worker] architecture: a #strong[server] holds
the Portage knowledge base and hands out proof jobs; #strong[workers]
pull work, run the proving pipeline, and push results back;
#strong[clients] submit targets and collect outcomes over the network.
The sections below explain how that stack is wired, how discovery and
TLS secure it, and how the same repository abstractions work whether you
run standalone, on the server, or on a worker.

== Architecture
<architecture>
#figure(image("Diagrams/17-cluster-architecture.svg", alt: "Cluster architecture"),
  caption: [
    Cluster architecture
  ]
)

At a glance, traffic flows like this:

```
┌────────────┐     ┌────────────┐     ┌────────────┐
│   Client   │────▶│   Server   │◀────│   Worker   │
│ (requests) │     │ (KB + jobs)│     │ (proves)   │
└────────────┘     └────────────┘     └────────────┘
                         ▲
                         │
                   ┌─────┴──────┐
                   │   Worker   │
                   │ (proves)   │
                   └────────────┘
```

The server is the hub: it exposes HTTP (with Pengines, described below),
owns the in-memory knowledge base, and multiplexes jobs across however
many workers attach. Workers are symmetric compute nodes; you can scale
them horizontally as long as each one can complete a proof job with the
same inputs the server would use locally.

=== Server (`Source/Application/Mode/server.pl`)
<server-sourceapplicationmodeserver.pl>
The server runs an HTTP server with Pengines (Prolog engines as a
service). It manages:

- The knowledge base (Portage tree loaded in-memory)
- A job queue of proof targets
- A result queue of completed proofs
- Pengine sandboxing for safe remote execution

=== Worker (`Source/Application/Mode/worker.pl`)
<worker-sourceapplicationmodeworker.pl>
Workers connect to the server, poll for proof jobs, execute them using
the full pipeline, and return results. Each worker loads the knowledge
base independently.

=== Client (`Source/Application/Mode/client.pl`)
<client-sourceapplicationmodeclient.pl>
Clients submit proof requests and retrieve results. They connect to the
server via HTTP(S).

=== Cluster orchestration (`Source/Application/Mode/cluster.pl`)
<cluster-orchestration-sourceapplicationmodecluster.pl>
The cluster module provides high-level orchestration for distributing
proof targets across available workers. It handles work distribution,
result collection, and failure recovery.

== Pengines: Prolog as a network service
<pengines-prolog-as-a-network-service>
#strong[Pengines] are #emph["Prolog engines as a web service"] --- a
library shipped with SWI-Prolog that turns query execution into an
HTTP-friendly protocol. In portage-ng's server mode, each incoming
client interaction is handled by creating a #strong[Pengine]: an
#strong[isolated Prolog engine] that runs the user's query inside a
#strong[sandbox], separate from the server's top-level state.

Conceptually:

- The #strong[server] creates a #strong[Pengine for each client request]
  (each one is a fresh, isolated engine for that interaction).
- That Pengine can #strong[see] the shared knowledge base predicates
  loaded into the server process, but the sandbox #strong[does not]
  grant arbitrary `assert`/`retract` or other dangerous primitives ---
  remote callers cannot reshape the KB at will.
- #strong[Answers stream back as JSON] over HTTP, which is how a
  non-Prolog client (or a thin Prolog stub) can drive proof search
  without linking the whole application.
- From the outside, portage-ng therefore exposes #strong[Prolog proof
  search as a network service], while the sandbox ensures #strong[remote
  clients cannot execute arbitrary Prolog predicates] beyond what the
  security layer explicitly whitelists.

The next section ties this to how repository state is shared or
replicated across threads and processes; the
#link(<sandbox-and-security>)[Sandbox and security] section lists the
concrete modules that enforce the whitelist.

== OO context and the same `portage::read` everywhere
<oo-context-and-the-same-portageread-everywhere>
The codebase distinguishes #strong[OO context] (the Logtalk-style
#strong[context] meta-object protocol in `Source/Logic/context.pl`) from
proof-term context and Pengines sandbox context. For distributed
proving, the important part is the #strong[OO context]: each
#strong[repository] is an #strong[instance] created through that system,
with methods such as the reads that populate cache facts.

- #strong[Server mode:] repository instances live in the #strong[shared
  server process]. All Pengines threads #strong[share] those instances
  and the loaded knowledge --- one tree in memory, many sandboxes
  reading it.
- #strong[Worker mode:] each worker is its #strong[own OS process] (and
  Prolog VM). It constructs #strong[its own] repository instances; that
  state is #strong[thread-local] to that worker's threads, not magically
  shared with the server's address space.

The payoff is #strong[uniform call sites]: the same `portage::read` (and
related instance messages) appear in standalone, server, and worker code
paths. #strong[Dispatch through the OO abstraction] selects the right
backing store and visibility rules for the mode you are in, so
distributed mode does not fork into a parallel universe of ad hoc
file-loading predicates.

== mDNS/Bonjour discovery
<mdnsbonjour-discovery>
You should not have to hand-edit IP addresses every time a laptop joins
the lab network. Workers and servers #strong[discover each other
automatically] via #strong[mDNS/Bonjour] service advertisement, wrapped
for Prolog in `Source/Application/System/bonjour.pl`:

+ The server #strong[registers] a `_portage-ng._tcp` service (hostname
  and port become visible on the local link).
+ Workers #strong[browse] for that service type and receive the server's
  reachability details.
+ A connection is established from that discovery data --- #strong[no
  manual IP configuration] for the common case.

#strong[On macOS], #strong[`dns-sd`] ships with the system. In this
project, `Source/Application/System/bonjour.pl` drives
#strong[`dns-sd -R`] to #strong[register] the service (host name,
`_portage-ng._tcp`, port) and #strong[`dns-sd -B`] with the configured
service type to #strong[browse] for peers --- the same
#strong[zero-configuration networking] idea that #strong[AirPrint],
#strong[AirPlay], and many other #strong[Bonjour] services use:
advertise a typed service on the LAN and resolve it without hand-entered
addresses.

#strong[On Linux], the same #strong[`dns-sd`] command is often available
through #strong[Avahi] (e.g.~`avahi-utils`); #strong[`avahi-browse`] is
the CLI many admins use for the equivalent #strong[browse] operation
when debugging. Either way, the #strong[`bonjour`] module keeps
discovery behind #strong[`subprocess:dns_sd/...`] so the rest of
portage-ng sees a single Prolog interface.

After discovery, traffic should be #strong[encrypted and mutually
authenticated]\; the following sections describe TLS material, then a
concrete two-node walkthrough.

== Sandbox and security
<sandbox-and-security>
The Pengines sandbox (`Source/Application/Security/sandbox.pl`)
restricts what predicates remote clients can call. Only predicates
registered via `sandbox:safe_primitive/1` and `sandbox:safe_meta/2` are
accessible.

The sanitize module (`Source/Application/Security/sanitize.pl`) provides
input validation for remote queries.

== TLS certificates
<tls-certificates>
When running in `--mode server` or `--mode client`, portage-ng uses
mutual TLS authentication. It expects a local CA and per-host
certificates under `Certificates/`:

- `cacert.pem` / `cakey.pem`
- `<hostname>.server-cert.pem` / `<hostname>.server-key.pem`
- `<hostname>.client-cert.pem` / `<hostname>.client-key.pem`

These files are intentionally #strong[not committed] to the repository.

== Generating certificates
<generating-certificates>
To generate a full set of certificates locally:

```bash
make certs HOST="$(hostname)"
```

If your environment uses a `.local` hostname (e.g.~`mac-pro.local`),
pass that exact value so it matches `config:hostname/1`:

```bash
make certs HOST="mac-pro.local"
```

== What gets generated
<what-gets-generated>
The `make certs` target creates:

+ A self-signed CA (`cacert.pem` + `cakey.pem`)
+ A server certificate and key signed by the CA
+ A client certificate and key signed by the CA

Both server and client certificates embed the hostname as the Common
Name (CN), which portage-ng verifies during the TLS handshake.

== Encrypted two-node cluster: step-by-step
<encrypted-two-node-cluster-step-by-step>
The following sequence ties together certificate generation, shared
trust, process roles, discovery, mutual TLS, and the worker loop. Adjust
host names to match your LAN (`.local` names are common on small
networks).

#strong[Step 1 --- Generate certificates on each machine.] On the
machine that will run the server (example hostname `server.local`):

```bash
make certs HOST="server.local"
```

On the machine that will run the worker (`worker.local`):

```bash
make certs HOST="worker.local"
```

Each host ends up with its #strong[own] server and client key pairs, all
signed by #strong[its] freshly created CA if you run `make certs` in
isolation --- see step 2 for the trust model you actually want.

#strong[Step 2 --- Establish a shared trust root.] Copy
#strong[`cacert.pem` from the server] (or from whichever machine you
designate as the #strong[cluster CA]) to the worker, replacing or
merging with the worker's notion of the CA so that #strong[both sides
trust the same `cacert.pem`]. Every node in the cluster must agree on
that #strong[single CA] while keeping #strong[host-specific] cert and
key files.

#strong[Step 3 --- Start the server] on the KB host (paths and wrapper
as in #link("14-doc-cli.md")[Chapter 14: Command-Line Interface]):

```text
portage-ng --mode server
```

#strong[Step 4 --- Start the worker] on the compute host:

```text
portage-ng --mode worker
```

#strong[Step 5 --- Discovery.] With Bonjour/mDNS working on the LAN, the
worker #strong[finds the server automatically] via `_portage-ng._tcp`
--- no static IP configuration is required for typical setups (see
#link(<mdnsbonjour-discovery>)[mDNS/Bonjour discovery]).

#strong[Step 6 --- Mutual TLS.] When the worker connects, #strong[both
ends present certificates] chained to the #strong[shared CA]. portage-ng
verifies #strong[CNs and roles] so that only nodes holding credentials
issued under that CA participate --- strangers on the coffee-shop Wi-Fi
cannot impersonate your cluster.

#strong[Step 7 --- Prove and return.] The worker #strong[polls the
server's job queue], runs the #strong[full proving pipeline] for each
target, and #strong[posts results] back. The server aggregates completed
work for clients and orchestration (see
`Source/Application/Mode/cluster.pl`).

== Cluster usage
<cluster-usage>
When running a distributed cluster (`--mode server` + `--mode worker`),
every node needs:

- A copy of the same `cacert.pem` (shared trust root)
- Its own host-specific server and/or client certificate pair

The mDNS/Bonjour discovery mechanism advertises the hostname, and TLS
ensures that only nodes sharing the same CA can join the cluster.

== Further reading
<further-reading-16>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- dns-sd and openssl prerequisites
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] ---
  `--mode` flags
- #link("04-doc-architecture.md")[Chapter 4: Architecture Overview] ---
  module load order for different modes

= Upstream and Bug Tracking
<upstream-and-bug-tracking>
portage-ng integrates with external services to check upstream versions
and search for known issues, helping users identify outdated packages
and known dependency bugs.

== Upstream version checking
<upstream-version-checking>
The upstream module (`Source/Domain/Gentoo/upstream.pl`) checks package
versions against upstream releases via the Repology API.

=== Usage
<usage-1>
```bash
portage-ng --upstream sys-apps/portage
portage-ng --upstream @world
```

=== How it works
<how-it-works-3>
+ For each target package, the module queries the Repology API
  (`https://repology.org/api/v1/project/<name>`) for version
  information.

+ The response includes version data across multiple distributions,
  which is compared against the version in the local Portage tree.

+ Results are categorized:

  - #strong[Up to date] --- local version matches or exceeds upstream
  - #strong[Outdated] --- a newer upstream version exists
  - #strong[Unknown] --- package not tracked by Repology

=== Output
<output-1>
The upstream check displays a comparison table showing the local
version, the latest upstream version, and the status for each package.

== Gentoo Bugzilla integration
<gentoo-bugzilla-integration>
The bugs module (`Source/Domain/Gentoo/bugs.pl`) searches Gentoo's
Bugzilla instance for known issues related to packages.

=== Usage
<usage-2>
```bash
portage-ng --bugs sys-apps/portage
```

=== How it works
<how-it-works-4>
+ The module queries Gentoo Bugzilla's REST API for bugs matching the
  package atom.

+ Results are filtered and displayed with bug number, summary, status,
  and assignee.

This helps users identify whether a dependency resolution failure is due
to a known upstream bug rather than a portage-ng issue.

== Automatic bug report drafts
<automatic-bug-report-drafts>
The issue module (`Source/Domain/Gentoo/issue.pl`) generates structured
Gentoo Bugzilla bug report drafts when the prover detects unsatisfiable
dependencies.

A generated report includes:

- #strong[Summary] --- one-line description of the issue
- #strong[Affected package] --- the package atom
- #strong[Unsatisfiable constraints] --- the specific dependency that
  cannot be met
- #strong[Observed state] --- what the prover found (missing package,
  version conflict, REQUIRED\_USE violation)
- #strong[Suggested fix] --- recommended action (add keyword, unmask,
  fix dependency)

These drafts can be used as starting points for filing bugs with the
Gentoo bug tracker.

== Further reading
<further-reading-17>
- #link("14-doc-cli.md")[Chapter 14: Command-Line Interface] ---
  `--upstream` and `--bugs` flags
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- how unsatisfiable dependencies are detected

= Contextual Logic Programming
<contextual-logic-programming>
#strong[context] is an object-oriented programming paradigm for Prolog,
implemented in
#link("../Source/Logic/context.pl")[`Source/Logic/context.pl`]. It
provides contexts (namespaces), classes, and instances with public,
protected, and private access control, multiple inheritance, cloning,
and declarative static typing of data members.

== Motivation
<motivation>
Standard Prolog uses a flat global namespace. As applications grow, name
collisions, uncontrolled access to dynamic predicates, and lack of
modularity become obstacles. #strong[context] addresses this by
splitting the global namespace into isolated contexts, each with their
own facts and rules.

The key insight is that contexts can be #strong[unified] and can serve
as feature terms describing software configurations -- directly
connecting to Zeller's #emph[Unified Versioning through Feature Logic].
This makes #strong[context] both a software engineering tool and a
formal foundation for reasoning about configurations.

== How it differs from Logtalk
<how-it-differs-from-logtalk>
The syntax is comparable to Logtalk, but the approach is fundamentally
different:

#figure(
  align(center)[#table(
    columns: (16.67%, 41.67%, 41.67%),
    align: (left,left,left,),
    table.header([], [#strong[Logtalk]], [#strong[context]],),
    table.hline(),
    [#strong[Approach]], [Compile-time translation to plain
    Prolog], [Runtime generation of guarded predicates],
    [#strong[Overhead]], [Source-to-source compilation step], [No
    compilation; contexts created dynamically],
    [#strong[Thread safety]], [Varies by backend], [Built-in; tokens are
    thread-local],
    [#strong[Feature unification]], [Not supported], [Contexts unify as
    feature terms],
  )]
  , kind: table
  )

Because #strong[context] works at runtime, contexts can be created,
cloned, and composed dynamically -- which portage-ng uses extensively to
represent repositories, ebuilds, and configurations as live objects.

== Core concepts
<core-concepts>
=== Contexts
<contexts>
A context groups together clauses of a Prolog application. By default,
clauses are local to their context and invisible to other contexts
unless explicitly exported. Referencing a context is enough to create it
(creation ex nihilo).

=== Classes
<classes>
A class is a special context that declares public, protected, and
private meta-predicates. These declarations control access during:

- #strong[Instantiation] -- which predicates are copied into the
  instance
- #strong[Inheritance] -- which predicates are visible to subclasses
- #strong[Invocation] -- which predicates external callers may use

=== Instances
<instances>
Instances are dynamically created from a class. Private, public, and
protected predicates are guarded in the instance context to enforce
access control. Instances support data-member-like behaviour through
special operators that cache successful evaluations of unified context
predicates.

=== Operators
<operators>
#strong[context] defines several operators for interacting with
contexts:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Operator]], [#strong[Meaning]],),
    table.hline(),
    [`:Pred`], [Call `Pred` in the current context (self-call)],
    [`::Pred`], [Access a data member (read)],
    [`<=Pred`], [Set a data member (write, replacing previous value)],
    [`<+Pred`], [Add a data member (append, keeping previous values)],
    [`<-Pred`], [Remove a data member],
    [`Ctx://Pred`], [Call `Pred` in a specific context],
  )]
  , kind: table
  )

== Example: a Person class
<example-a-person-class>
The following example (from
#link("../Source/Logic/Examples/person.pl")[`Source/Logic/Examples/person.pl`])
shows a simple class with public, protected, and private members:

```prolog
:- module(person, []).

:- class.

:- dpublic('person'/1).
:- dpublic([get_name/1, set_name/1]).
:- dpublic(get_age/1).
:- dpublic(set_age/1).

:- dprotected(name/1).
:- dprivate(age/1).

person(Name) ::-
  :set_name(Name).

get_name(Name) ::-
  ::name(Name).

set_name(Name) ::-
  <=name(Name).

set_age(Age) ::-
  <=age(Age).

name(Name) ::-
  atom(Name).

age(Age) ::-
  number(Age),
  Age > 0.
```

Creating and using an instance:

```prolog
?- pieter:newinstance(person).
?- pieter:person('Pieter').
?- pieter:set_age(40).
?- pieter:get_name(Name).
Name = 'Pieter'.
?- pieter:get_age(Age).
Age = 40.
```

Private members like `age/1` cannot be accessed directly from outside
the instance -- only through the public interface.

== How portage-ng uses context
<how-portage-ng-uses-context>
portage-ng uses #strong[context] throughout its architecture:

- #strong[Repositories] are context instances. Each Portage tree,
  overlay, or VDB is a live object with its own cached facts and query
  interface.
- #strong[Ebuilds] carry context terms as feature-term lists. When the
  prover processes dependencies, contexts are merged via
  feature-unification, preserving provenance, USE constraints, slot
  locks, and ordering information.
- #strong[Configuration] objects (profiles, `/etc/portage` settings) are
  contexts that can be composed and queried.

The connection to Zeller's feature logic is not just theoretical: the
prover's feature term unification operation uses the same semantics to
merge dependency contexts, enabling prescient proving and constraint
propagation across the dependency graph.

== Further reading
<further-reading-18>
- A. Zeller, #emph[Unified Versioning through Feature Logic], 1997
- #link("../Source/Logic/context.pl")[`Source/Logic/context.pl`] -- full
  implementation
- #link("20-doc-context-terms.md")[`Documentation/Handbook/20-doc-context-terms.md`]
  -- how context terms flow through the prover

= Context Terms in portage-ng
<context-terms-in-portage-ng>
How contexts are created, propagated, and merged across the dependency
graph.

== Overview
<overview-1>
Every literal in the prover carries a #strong[context] --- a list of
tagged terms that records provenance, ordering, constraints, and USE
requirements as the proof expands through dependencies. The literal
format is:

```
Literal:Action?{Context}
```

Contexts are not opaque blobs; they are structured as
#strong[feature-term lists] and are merged using a Zeller-inspired
feature-unification algorithm. This gives them lattice semantics:
merging two contexts produces a well-defined meet that preserves all
non-contradictory information from both sides.

== Anatomy of a context
<anatomy-of-a-context>
A context is a Prolog list. Each element is either a plain term or a
`Feature:Value` pair. The distinction matters for merging:

#figure(
  align(center)[#table(
    columns: (20%, 28.57%, 51.43%),
    align: (left,left,left,),
    table.header([#strong[Form]], [#strong[Example]], [#strong[Merge
      behaviour]],),
    table.hline(),
    [Plain
    term], [`self(portage://sys-apps/portage-3.0.77-r3)`], [Identity
    match; duplicates dropped],
    [Feature:Value], [`build_with_use:use_state([foo],[bar])`], [Value-merged
    by `val_hook/3`],
    [Feature:Compound], [`slot(sys-apps,portage,0/0):{…}`], [Compound
    feature key],
  )]
  , kind: table
  )

=== Common context tags
<common-context-tags>
#figure(
  align(center)[#table(
    columns: (24%, 36%, 40%),
    align: (left,left,left,),
    table.header([#strong[Tag]], [#strong[Set by]], [#strong[Purpose]],),
    table.hline(),
    [`self(Repo://Entry)`], [`dependency:add_self_to_dep_contexts`], [Identifies
    the parent ebuild that introduced this dependency edge],
    [`build_with_use:use_state(En,Dis)`], [`dependency:process_build_with_use`], [Bracketed
    USE constraints from the dep atom (e.g.~`dev-libs/foo[bar,-baz]`)],
    [`slot(C,N,Ss):{Candidate}`], [`dependency:process_slot`], [Slot
    lock from `:=` (subslot rebuild) semantics],
    [`after(Literal)`], [`rules:ctx_add_after`], [Ordering constraint:
    this dep must come after `Literal` in the plan; propagates to
    children],
    [`after_only(Literal)`], [`rules:add_after_only_to_dep_contexts`], [Ordering
    constraint that does #strong[not] propagate to children],
    [`replaces(pkg://Entry)`], [Install/update rules], [Records which
    installed package this action replaces],
    [`assumption_reason(Reason)`], [Domain assumption
    fallback], [Records why a domain assumption was made
    (e.g.~`missing`, `masked`, `keyword_filtered`)],
    [`suggestion(Type,Detail)`], [Relaxation fallback], [Records an
    actionable suggestion (e.g.~`accept_keyword`, `unmask`,
    `use_change`)],
    [`domain_reason(cn_domain(C,N,Tags))`], [`candidate:add_domain_reason_context`], [Diagnostic
    tags for version domain narrowing],
    [`constraint(cn_domain(C,N):{Domain})`], [Constraint
    system], [Carries an inline constraint for domain scoping],
  )]
  , kind: table
  )

== Context lifecycle
<context-lifecycle>
#figure(image("Diagrams/20-context-lifecycle.svg", alt: "Context lifecycle"),
  caption: [
    Context lifecycle
  ]
)

=== 1. Creation (root)
<creation-root>
At the top level, the prover starts with an empty context (`{}` or
`[]`). The first rule expansion --- typically `target/2` → `install` ---
begins populating it.

=== 2. Extension (downward propagation)
<extension-downward-propagation>
As rules expand dependencies, contexts grow:

```
target(sys-apps/portage)?{}
  └─ install(portage://sys-apps/portage-3.0.77-r3):install?{...}
       ├─ dep(dev-lang/python):install?{self(portage://sys-apps/portage-3.0.77-r3),
       │                                 build_with_use:use_state([ssl,threads],[]),
       │                                 after(install(portage://...))}
       │    └─ dep(dev-libs/openssl):install?{self(portage://dev-lang/python-3.13),
       │                                       build_with_use:use_state([],[]),
       │                                       after(install(portage://dev-lang/python-3.13))}
       └─ dep(app-arch/tar):install?{self(portage://sys-apps/portage-3.0.77-r3),
                                      after(install(portage://...))}
```

Key propagation rules:

- #strong[`self/1`] is set to the current ebuild at each dependency
  edge. It does #strong[not] accumulate --- each edge replaces the
  previous `self`.
- #strong[`build_with_use`] is per-edge: the child gets a fresh
  `build_with_use` from its dep atom, not the parent's `build_with_use`.
- #strong[`after/1`] propagates transitively (children inherit it).
- #strong[`after_only/1`] does #strong[not] propagate (ordering is local
  to this edge).
- #strong[`assumption_reason`] and #strong[`build_with_use`] are dropped
  on PDEPEND edges (via
  `ctx_drop_build_with_use_and_assumption_reason`).

=== 3. Merging (join points)
<merging-join-points>
When the prover encounters a literal that was already proven with a
different context, it merges the old and new contexts via feature term
unification:

```prolog
sampler:ctx_union(OldCtx, NewCtx, MergedCtx)
```

The merge algorithm:

+ #strong[Strip `self/1`] from the old context entirely.
+ #strong[Extract one `self/1`] from the new context (keep it aside).
+ #strong[Unify] the remaining lists via `feature_unification:unify/3`.
+ #strong[Prepend] the extracted `self/1` back onto the result.

This guarantees: - At most one `self/1` in the merged result (from the
new/incoming side). - Feature:Value pairs with the same key are merged
by `val_hook/3`. - Plain terms present in either side appear in the
result (union semantics).

=== 4. Stripping for memoisation
<stripping-for-memoisation>
Before checking whether a literal has already been proven, planning
markers are stripped so they don't pollute the memoisation key:

```prolog
rules:ctx_strip_planning(Context0, Context)
```

This removes `after/1` and `world_atom/1` --- ordering and planning
concerns that should not affect whether a proof is reusable.

== Feature unification in detail
<feature-unification-in-detail>
`feature_unification:unify/3` implements a #strong[horizontal
unification] algorithm inspired by Zeller's feature logic:

+ Normalise both terms (`{}` → `[]`).
+ Walk both lists. For each `Feature:Value` pair in list A, check if
  list B has the same `Feature`.
+ If both sides have `Feature`, merge values via `val/3` (or
  `val_hook/3` for domain-specific merge).
+ If only one side has `Feature`, include it in the result.
+ Plain terms are matched by identity; duplicates are dropped.

=== Value merge rules
<value-merge-rules>
#figure(
  align(center)[#table(
    columns: (16.13%, 16.13%, 29.03%, 38.71%),
    align: (left,left,left,left,),
    table.header([#strong[V1]], [#strong[V2]], [#strong[Result]], [#strong[Semantics]],),
    table.hline(),
    [`{L1}`], [`{L2}`], [`{Intersection}`], [Set intersection (must be
    non-empty)],
    [`[L1]`], [`[L2]`], [`[Union]`], [Sorted union (fails on
    contradictions)],
    [atom `V`], [`{L}`], [`{V}` if `V ∈ L`], [Singleton intersection],
    [`V`], [`V`], [`V`], [Identity],
  )]
  , kind: table
  )

=== Domain-specific hooks (`val_hook/3`)
<domain-specific-hooks-val_hook3>
#figure(
  align(center)[#table(
    columns: (26.32%, 26.32%, 47.37%),
    align: (left,left,left,),
    table.header([#strong[Feature]], [#strong[Hook in]], [#strong[Merge
      behaviour]],),
    table.hline(),
    [`build_with_use`], [`use.pl`], [`use_state(En1,Dis1)` ⊔
    `use_state(En2,Dis2)` = union of enable/disable sets; #strong[fails]
    if a flag appears in both enable and disable],
    [`cn_domain`], [`version.pl`], [`version_domain` meet (intersection
    of version bounds); `none` is identity],
  )]
  , kind: table
  )

== `self/1` --- parent provenance
<self1-parent-provenance>
The `self/1` tag identifies #strong[which ebuild introduced this
dependency]. It is critical for:

- #strong[USE evaluation]: `use:effective_use_in_context/3` looks up the
  USE model of the ebuild in `self/1` to evaluate USE conditionals.
- #strong[Blocker source]: `candidate:make_blocker_constraint/5` uses
  `self/1` to determine who is blocking whom.
- #strong[Parent narrowing]: `candidate:maybe_learn_parent_narrowing/4`
  uses `self/1` to learn that the parent version should be excluded when
  a child dependency cannot be satisfied.
- #strong[REQUIRED\_USE]: `query:with_required_use_validate/3` annotates
  REQUIRED\_USE terms with `:validate?{[self(...)]}` so the prover knows
  the ebuild context.

=== Invariant: at most one `self/1`
<invariant-at-most-one-self1>
Without bounding, `self/1` would stack along dependency chains:

```
[self(A), self(B), self(C), ...]  ← unbounded growth
```

The system prevents this at two levels:

+ #strong[`dependency:ctx_set_self/3`] replaces any existing `self/1`
  when setting a new parent.
+ #strong[Feature term unification] (`ctx_union_raw/3`) strips all
  `self/1` from the old context and keeps only one from the new context.

== `build_with_use` --- bracketed USE requirements
<build_with_use-bracketed-use-requirements>
When a dependency atom carries USE requirements (e.g.
`dev-lang/python[ssl,threads]`), they are recorded as:

```prolog
build_with_use:use_state([ssl, threads], [])
```

The enable list contains flags that must be ON; the disable list
contains flags that must be OFF.

=== Per-edge, not inherited
<per-edge-not-inherited>
Each dependency edge computes its own `build_with_use` from the dep
atom. The parent's `build_with_use` is #strong[removed] before computing
the child's:

```prolog
dependency:process_build_with_use(MergedUse, ContextDep, NewContext, ...)
```

This prevents a grandparent's USE requirements from leaking to
grandchildren.

=== Merge semantics
<merge-semantics>
When feature term unification merges two contexts with `build_with_use`,
the `val_hook` in `use.pl` takes the #strong[union] of enable sets and
the #strong[union] of disable sets. If a flag appears in both enable and
disable, the merge #strong[fails] (contradiction), forcing the prover to
backtrack.

=== PDEPEND edge
<pdepend-edge>
On PDEPEND edges, `build_with_use` is dropped because PDEPEND
dependencies are resolved at runtime, not build time, so build-time USE
constraints do not apply.

== Constraints vs contexts
<constraints-vs-contexts>
#figure(image("Diagrams/20-context-vs-constraint.svg", alt: "Context vs constraint interaction"),
  caption: [
    Context vs constraint interaction
  ]
)

Contexts and constraints serve different purposes:

#figure(
  align(center)[#table(
    columns: (28.12%, 31.25%, 40.62%),
    align: (left,left,left,),
    table.header([#strong[Aspect]], [#strong[Context]], [#strong[Constraint]],),
    table.hline(),
    [Scope], [Per-literal (local)], [Global (across proof)],
    [Storage], [List attached to `?{...}`], [AVL in ConstraintsAVL],
    [Growth], [Bounded by design], [Grows with proof],
    [Purpose], [Provenance, ordering, USE], [Version selection, slot
    locks, blockers],
  )]
  , kind: table
  )

=== How they interact
<how-they-interact>
+ #strong[Context → Constraint]: When a candidate is selected,
  constraints are #strong[emitted] into the global ConstraintsAVL
  (e.g.~`selected_cn(C,N)`, `cn_domain(C,N)`, `slot(C,N,S)`).

+ #strong[Constraint → Context]: Inline constraint terms like
  `constraint(cn_domain(C,N):{Domain})` can appear in contexts, passed
  down from parent deps that want to scope the version domain for a
  child.

+ #strong[Constraint guards]: After a constraint is merged into the
  global store, `rules:constraint_guard/2` fires to check consistency:

  - `cn_domain` ↔ `selected_cn` compatibility
  - `selected_cn` uniqueness (per slot)
  - `blocked_cn` ↔ `selected_cn` conflict detection

+ #strong[Constraint learning]: When a constraint guard detects a
  conflict, it can `prover:learn/3` a narrowed domain that persists
  across reprove retries (Zeller-style incremental narrowing).

== Ordering: `after` vs `after_only`
<ordering-after-vs-after_only>
Both create ordering edges in the plan, but they differ in propagation:

#figure(
  align(center)[#table(
    columns: (19.15%, 57.45%, 23.4%),
    align: (left,left,left,),
    table.header([#strong[Marker]], [#strong[Propagates to child
      deps?]], [#strong[Use case]],),
    table.hline(),
    [`after(Lit)`], [Yes], [Build deps: the package and all its deps
    must come after `Lit`],
    [`after_only(Lit)`], [No], [Runtime deps: only this package (not its
    deps) must come after `Lit`],
  )]
  , kind: table
  )

=== Extraction
<extraction>
```prolog
rules:ctx_take_after_with_mode(Context, After, AfterForDeps, ContextRest)
```

- If `after(X)` → `After = X`, `AfterForDeps = X` (propagate).
- If `after_only(X)` → `After = X`, `AfterForDeps = none` (don't
  propagate).
- If neither → both `none`.

== Example: full context evolution
<example-full-context-evolution>
Starting from `emerge sys-apps/portage`:

```
1. target(sys-apps/portage)?{}
   │
   │  [target rule: select best visible candidate]
   │
2. install(portage://sys-apps/portage-3.0.77-r3):install?{}
   │
   │  [install rule: compute USE model, expand deps]
   │  Context gains: nothing yet (root)
   │
   ├─ DEPEND: dev-lang/python[ssl,threads]
   │  │
   │  │  [add_self_to_dep_contexts]
   │  │  [process_build_with_use]
   │  │  [ctx_add_after]
   │  │
   │  grouped_dep(dev-lang/python):install?{
   │    self(portage://sys-apps/portage-3.0.77-r3),
   │    build_with_use:use_state([ssl,threads],[]),
   │    after(install(portage://sys-apps/portage-3.0.77-r3))
   │  }
   │  │
   │  │  [candidate selected: python-3.13.2]
   │  │  [constraint emitted: selected_cn(dev-lang,python)]
   │  │  [slot constraint: slot(dev-lang,python,3.13)]
   │  │
   │  3. install(portage://dev-lang/python-3.13.2):install?{
   │       self(portage://sys-apps/portage-3.0.77-r3),
   │       build_with_use:use_state([ssl,threads],[]),
   │       after(install(portage://sys-apps/portage-3.0.77-r3))
   │     }
   │     │
   │     ├─ DEPEND: dev-libs/openssl:=
   │     │  │
   │     │  │  [self replaced: now python-3.13.2]
   │     │  │  [build_with_use replaced: openssl has no USE reqs → empty]
   │     │  │  [after propagated from parent]
   │     │  │  [slot processed: := adds slot lock]
   │     │  │
   │     │  grouped_dep(dev-libs/openssl):install?{
   │     │    self(portage://dev-lang/python-3.13.2),
   │     │    build_with_use:use_state([],[]),
   │     │    slot(dev-libs,openssl,0/3.4.1):{portage://dev-libs/openssl-3.4.1},
   │     │    after(install(portage://sys-apps/portage-3.0.77-r3))
   │     │  }
   │     │
   │     └─ RDEPEND: app-misc/mime-types
   │        │
   │        │  [RDEPEND: after_only (no propagation)]
   │        │  [build_with_use: fresh (no USE reqs)]
   │        │
   │        grouped_dep(app-misc/mime-types):install?{
   │          self(portage://dev-lang/python-3.13.2),
   │          build_with_use:use_state([],[]),
   │          after_only(install(portage://dev-lang/python-3.13.2))
   │        }
   │
   └─ RDEPEND: app-arch/tar
      │
      │  [RDEPEND: after_only]
      │
      grouped_dep(app-arch/tar):install?{
        self(portage://sys-apps/portage-3.0.77-r3),
        build_with_use:use_state([],[]),
        after_only(install(portage://sys-apps/portage-3.0.77-r3))
      }
```

Key observations: - `self/1` always points to the #strong[immediate]
parent, never accumulates. - `build_with_use` is replaced at each edge
based on the dep atom's `[flags]`. - `after/1` from DEPEND propagates
down; `after_only/1` from RDEPEND does not. - Slot locks (`:=`) add
`slot/3` entries to the context. - Constraint emissions
(e.g.~`selected_cn`) go into the global store, not the context.

== Design rationale
<design-rationale>
=== Why feature unification?
<why-feature-unification>
Traditional dependency solvers use flat constraint lists or SAT clauses.
portage-ng uses feature-term unification because:

+ #strong[Composability]: Contexts from different proof branches merge
  naturally at join points without ad-hoc conflict resolution.
+ #strong[Bounded growth]: The `self/1` stripping in feature term
  unification and the per-edge `build_with_use` replacement prevent
  unbounded context growth along dependency chains.
+ #strong[Domain extensibility]: New context tags can be added without
  changing the merge infrastructure --- just add a `val_hook/3` clause
  if domain-specific merge is needed.
+ #strong[Conflict detection]: The merge fails (backtracks) on
  contradictions (e.g.~a flag in both enable and disable), providing
  natural constraint propagation.

=== Why separate contexts and constraints?
<why-separate-contexts-and-constraints>
Contexts are #strong[local] (per-literal, scoped to a proof branch)
while constraints are #strong[global] (shared across the entire proof).
This separation allows:

- #strong[Contexts] to carry provenance information that should not leak
  across unrelated proof branches.
- #strong[Constraints] to enforce global invariants (e.g.~only one
  version of a package can be selected) that must hold across the entire
  proof.
- #strong[Constraint learning] to persist across reprove retries,
  narrowing the search space incrementally.

= Dependency Resolver Comparison: Portage, Paludis, portage-ng
<dependency-resolver-comparison-portage-paludis-portage-ng>
== Architecture Overview
<architecture-overview-1>
=== Portage (Python, `depgraph.py`)
<portage-python-depgraph.py>
#strong[Model:] Greedy graph builder with retroactive backtracking.

Portage builds a dependency graph incrementally. For each dependency,
`_select_pkg_highest_available_imp` picks the best candidate (newest
stable). A `PackageTracker` detects slot conflicts when two packages
compete for the same slot.

When a conflict is detected: 1. `_process_slot_conflict` identifies the
conflicting packages 2. `_slot_confict_backtrack` masks ONE package via
`runtime_pkg_mask` 3. `Backtracker` creates a new `BacktrackNode` with
the mask 4. The entire dependency graph is rebuilt from scratch 5.
Repeat up to `--backtrack=N` times (default 20)

#strong[Key characteristics:] - Full graph rebuild per backtrack attempt
\- Masks (negative filtering) accumulate across attempts - No
package-specific heuristics - Each attempt adds ONE mask - 14 backtracks
needed for OCaml Jane Street async\_kernel

#strong[Source:] `lib/_emerge/depgraph.py`,
`lib/_emerge/resolver/backtracking.py`

=== Paludis (C++, `decider.cc`)
<paludis-c-decider.cc>
#strong[Model:] Constraint accumulator with exception-driven restart.

Paludis maintains a `Resolution` per `Resolvent`
(package+slot+destination). Each Resolution accumulates `Constraints`
and has a `Decision` (chosen candidate). Dependencies are added
incrementally.

When a new constraint conflicts with an existing decision: 1.
`_verify_new_constraint` detects the incompatibility 2.
`_made_wrong_decision` finds the CORRECT candidate via
`_try_to_find_decision_for` (evaluates ALL accumulated constraints) 3.
`_suggest_restart_with` throws `SuggestRestart` carrying: - The correct
decision - A "preloading constraint" for the next resolver 4. The main
loop catches `SuggestRestart`, adds the preset, creates a brand new
`Resolver`, and retries

#strong[Key characteristics:] - Positive guidance (preloads correct
candidate, not rejects wrong one) - Brand new resolver each restart
(fresh state) - `_try_to_find_decision_for` evaluates ALL constraints
simultaneously - Typically fewer restarts than Portage - Up to 9000
restarts allowed

#strong[Source:] `paludis/resolver/decider.cc`,
`src/clients/cave/resolve_common.cc`

=== portage-ng (SWI-Prolog, `prover.pl` + `rules.pl`)
<portage-ng-swi-prolog-prover.pl-rules.pl>
#strong[Model:] Inductive proof search with constraint guards and
learned constraint refinement.

portage-ng uses a Prolog proof tree. Each `grouped_package_dependency`
is a rule that selects a candidate, adds `selected_cn` and `cn_domain`
constraints, and recursively proves the candidate's subtree. Constraint
guards fire during constraint unification and detect conflicts.

When a conflict is detected: 1. The constraint guard learns the domain
constraint via `prover:learn` 2. Throws `rules_reprove_cn_domain` for
the existing reprove mechanism 3. The handler adds rejects and retries
with the learned constraint applied 4. On retry,
`grouped_dep_effective_domain` intersects the learned domain with the
local domain, narrowing candidates before selection 5. For inconsistent
domains, the Vermeir-style clause identifies the "adjustable origin" and
narrows it further 6. For wrong-level assumptions,
`maybe_learn_parent_narrowing` learns to exclude the parent version that
introduced the unsatisfiable constraint

#strong[Key characteristics:] - Single-pass proof for 99%+ of targets
(fastest resolver) - Learned constraints (positive guidance via domain
narrowing) - Existing reject mechanism for backward compatibility -
Slot-scoped domain learning (cn\_domain(C,N,Slot)) - Vermeir-style
priority resolution for inconsistent domains - No package-specific code

#strong[Source:] `Source/Pipeline/prover.pl`,
`Source/Domain/Gentoo/rules.pl`

== Comparison Table
<comparison-table>
#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Aspect]], [#strong[Portage]], [#strong[Paludis]], [#strong[portage-ng]],),
    table.hline(),
    [Language], [Python], [C++], [SWI-Prolog],
    [Conflict detection], [Post-hoc (after graph built)], [Incremental
    (on constraint add)], [Incremental (constraint guard)],
    [What carries across retries], [Masks (negative)], [Preloads
    (positive)], [Learned domains (positive) + Rejects (negative)],
    [Fresh state each retry?], [Yes (new depgraph)], [Yes (new
    Resolver)], [Partial (reject set accumulates, learned store
    accumulates)],
    [Finding the right candidate], [Brute force
    (mask+retry)], [`_try_to_find_decision_for` with ALL
    constraints], [Domain narrowing (Zeller) + priority resolution
    (Vermeir)],
    [Performance], [Slowest (full rebuild)], [Fast (targeted
    restarts)], [Fastest (single-pass for most targets)],
    [Package-specific code], [None], [None], [None],
  )]
  , kind: table
  )

== Academic Foundations
<academic-foundations>
=== Zeller & Snelting: Feature Logic (ESEC 1995, TOSEM 1997)
<zeller-snelting-feature-logic-esec-1995-tosem-1997>
"Unified Versioning Through Feature Logic" --- version sets are
identified by feature terms and configured by incrementally narrowing
the set until each component resolves to a single version. portage-ng's
`version_domain` with `domain_meet` (intersection) is essentially
Zeller's feature term narrowing. The learned constraint store implements
Zeller's feature implication propagation: constraints discovered in one
proof attempt propagate to narrow version sets in the next attempt.

=== Vermeir & Van Nieuwenborgh: Ordered Logic Programs (JELIA 2002)
<vermeir-van-nieuwenborgh-ordered-logic-programs-jelia-2002>
"Preferred Answer Sets for Ordered Logic Programs" --- when rules
conflict, a partial order determines which yields. portage-ng's
`find_adjustable_origin` implements this: when a domain is inconsistent
(two bounds that can't be simultaneously satisfied), the bound from the
"adjustable" origin (the package that already has a learned constraint)
is dropped, and the origin is narrowed further.

=== CDCL / PubGrub / SAT-based approaches
<cdcl-pubgrub-sat-based-approaches>
Modern package resolvers (libsolv, Resolvo, PubGrub) encode version
constraints as boolean satisfiability problems. portage-ng's approach is
different: it uses proof search with domain narrowing rather than SAT
encoding. The learned constraint store is analogous to CDCL's learned
clauses, but expressed as version domains rather than boolean clauses.

= Dependency Ordering: PMS, Portage, Paludis, and portage-ng
<dependency-ordering-pms-portage-paludis-and-portage-ng>
This document describes how Gentoo's dependency types affect package
merge ordering, comparing the PMS specification with the implementations
in Portage, Paludis, and portage-ng.

== Dependency Types (PMS Chapter 8)
<dependency-types-pms-chapter-8>
The Package Manager Specification defines five dependency classes:

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Type]], [#strong[PMS
      Definition]], [#strong[When required]], [#strong[Binary compat]],),
    table.hline(),
    [DEPEND], [Build dependencies], [Before `pkg_setup` and throughout
    `src_*` phases], [CHOST],
    [BDEPEND], [Build dependencies (EAPI 7+)], [Same as
    DEPEND], [CBUILD],
    [RDEPEND], [Runtime dependencies], [Before the package is treated as
    usable], [CHOST],
    [PDEPEND], [Post dependencies], [Before the package manager finishes
    the batch], [CHOST],
    [IDEPEND], [Install-time dependencies (EAPI 8+)], [During
    `pkg_preinst` and `pkg_postinst`], [CBUILD],
  )]
  , kind: table
  )

=== Phase functions and dependency availability
<phase-functions-and-dependency-availability>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Phase functions]], [#strong[Available
      dependency classes]],),
    table.hline(),
    [`src_unpack`, `src_prepare`, `src_configure`, `src_compile`,
    `src_test`, `src_install`], [DEPEND, BDEPEND],
    [`pkg_preinst`, `pkg_postinst`, `pkg_prerm`,
    `pkg_postrm`], [RDEPEND, IDEPEND],
    [`pkg_config`], [RDEPEND, PDEPEND],
  )]
  , kind: table
  )

=== Ordering implications
<ordering-implications>
- #strong[DEPEND/BDEPEND]: "Must be installed and usable before
  `pkg_setup`." These create #strong[hard ordering constraints] -- the
  dependency must be merged before the dependent can be built. Neither
  Portage nor Paludis will break these edges for cycle resolution.

- #strong[RDEPEND]: "Must be installed and usable before the results of
  an ebuild merging are treated as usable." This is a #strong[soft
  ordering constraint] -- ideally the dependency is merged before the
  dependent, but both Portage and Paludis will break these edges when
  cycles exist.

- #strong[PDEPEND]: "Must be installed at some point before the package
  manager finishes the batch of installs." This is the #strong[softest
  constraint] -- Portage treats it as a very low priority edge, and
  Paludis creates no ordering edge at all.

- #strong[IDEPEND]: Available during install-time phases. Treated
  similarly to runtime dependencies for ordering purposes.

== Portage Implementation
<portage-implementation>
Source: `lib/_emerge/depgraph.py`, `lib/_emerge/DepPriority.py`,
`lib/_emerge/DepPriorityNormalRange.py`

=== Edge priority system
<edge-priority-system>
Portage builds a single dependency graph where every package is a node
and every dependency creates a directed edge. Edges carry a priority
that determines how "hard" they are:

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Dependency]], [#strong[Priority
      flag]], [#strong[Priority value]], [#strong[Breakable?]],),
    table.hline(),
    [DEPEND/BDEPEND], [`buildtime=True`], [-1], [No (hard)],
    [RDEPEND (`:=` slot op)], [`runtime_slot_op=True`], [-2], [Only if
    cross-compiling],
    [RDEPEND], [`runtime=True`], [-3], [Yes (for cycles)],
    [PDEPEND], [`runtime_post=True`], [-4], [Yes (first to break)],
    [Optional], [`optional=True`], [-5], [Yes (always breakable)],
  )]
  , kind: table
  )

=== Cycle-breaking algorithm
<cycle-breaking-algorithm>
Portage's `_serialize_tasks` method performs topological sort with
progressive edge relaxation:

```
Pass 1: Respect all edges (NONE priority)
Pass 2: Ignore optional dependencies (SOFT)
Pass 3: Ignore PDEPEND edges (MEDIUM_SOFT)
Pass 4: Ignore RDEPEND edges (MEDIUM)
         (except runtime_slot_op, unless cross-compiling)
```

If no leaf nodes are found after all passes, the remaining cycle
involves only build-time dependencies and is treated as an error or
merged as a group.

=== RDEPEND handling
<rdepend-handling>
RDEPEND creates ordering edges: Portage tries to merge runtime
dependencies before their dependents. However, when cycles exist,
RDEPEND edges are broken before build-time edges. This means:

- In the common (acyclic) case: RDEPEND is satisfied before the
  dependent
- In cyclic cases: RDEPEND may be merged after the dependent

=== PDEPEND handling
<pdepend-handling>
PDEPEND creates `runtime_post` edges with very low priority. Portage
adds PDEPEND nodes to an `asap_nodes` list to merge them as early as
possible after the dependent, but the ordering constraint is very weak.

== Paludis Implementation
<paludis-implementation>
Source: `paludis/resolver/orderer.cc`,
`paludis/resolver/labels_classifier.cc`

=== NAG (Node-Adjacency Graph)
<nag-node-adjacency-graph>
Paludis builds a NAG where edges carry two boolean flags:

```cpp
NAGEdgeProperties {
    build()        // true for DEPEND/BDEPEND
    build_all_met  // true if build dep already satisfied
    run()          // true for RDEPEND
    run_all_met    // true if runtime dep already satisfied
}
```

=== Dependency type mapping
<dependency-type-mapping>
#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[Dependency]], [#strong[Classifier
      flag]], [#strong[Edge created?]],),
    table.hline(),
    [DEPEND/BDEPEND], [`includes_buildish`], [Yes: `build()=true`],
    [RDEPEND], [`includes_non_post_runish`], [Yes: `run()=true`],
    [PDEPEND], [`includes_postish`], [#strong[No edge created]],
  )]
  , kind: table
  )

PDEPEND explicitly creates no ordering edge. From the source: \> "we
won't add a backwards edge, since most post deps dep upon the thing \>
requiring them anyway"

=== Cycle handling (Tarjan's SCC)
<cycle-handling-tarjans-scc>
Paludis uses Tarjan's algorithm to find strongly connected components,
then classifies each SCC:

+ #strong[Single-node SCC]: Scheduled directly (no cycle).
+ #strong[Runtime-only SCC] (no build edges): Ordered arbitrarily.
  Paludis explicitly treats runtime-only cycles as
  non-ordering-significant.
+ #strong[Build-dep SCC]: Try removing edges where `build_all_met` or
  `run_all_met` is true and recompute. If still cyclic, mark as
  "unorderable" with a cycle-breaking note.

The key insight from Paludis is that #strong[runtime-only dependency
cycles have no ordering significance]. This is a stronger statement than
Portage's progressive relaxation -- Paludis says these cycles are
flat-out free to order however is convenient.

== Comparison
<comparison>
```mermaid
graph LR
    subgraph PMS["PMS Specification"]
        PMShard["DEPEND/BDEPEND: before building"]
        PMSsoft["RDEPEND: before usable"]
        PMSpost["PDEPEND: before batch ends"]
    end

    subgraph Portage["Portage"]
        Pbuild["buildtime edge (hard)"]
        Prun["runtime edge (soft, breakable)"]
        Ppost["runtime_post edge (softest)"]
    end

    subgraph Paludis["Paludis"]
        PalBuild["build()=true (hard)"]
        PalRun["run()=true (cycles free)"]
        PalPost["no edge created"]
    end

    PMShard --> Pbuild
    PMShard --> PalBuild
    PMSsoft --> Prun
    PMSsoft --> PalRun
    PMSpost --> Ppost
    PMSpost --> PalPost
```

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Aspect]], [#strong[PMS]], [#strong[Portage]], [#strong[Paludis]],),
    table.hline(),
    [DEPEND/BDEPEND ordering], [Before building (hard)], [`buildtime`
    edge, never broken], [`build()=true`, never broken],
    [RDEPEND ordering], [Before usable (soft)], [`runtime` edge, broken
    for cycles], [`run()=true`, runtime cycles free],
    [PDEPEND ordering], [Before batch ends], [`runtime_post` edge, first
    to break], [No edge at all],
    [Cycle strategy], [Not specified], [Progressive priority
    relaxation], [SCC classification],
    [Graph model], [Not specified], [Single graph + priorities], [NAG +
    Tarjan's SCC],
    [Build-time cycles], [Not specified], [Treated as error/group], [Try
    relaxing met edges, then error],
  )]
  , kind: table
  )

== portage-ng Current Model and Diagnosis
<portage-ng-current-model-and-diagnosis>
=== Architecture
<architecture-1>
portage-ng uses a two-phase model with `:install` and `:run` actions:

```mermaid
graph TD
    target["Target:run"]
    target -->|"requires"| install["Target:install"]
    target -->|"RDEPEND"| rdep["RDep:run"]

    install -->|"DEPEND/BDEPEND"| bdep["BDep:install"]
    install -->|"RDEPEND (incorrect)"| rdep2["RDep2:run"]
    install -->|"requires"| download["Target:download"]

    rdep -->|"requires"| rdep_install["RDep:install"]

    bdep -->|"DEPEND"| bdep2["BDep2:install"]
```

=== Current dependency model (`query.pl`)
<current-dependency-model-query.pl>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Model]], [#strong[Dependency types included]],),
    table.hline(),
    [`:install`], [BDEPEND, CDEPEND, DEPEND, IDEPEND, #strong[RDEPEND]],
    [`:run`], [IDEPEND, RDEPEND],
  )]
  , kind: table
  )

````

## References

- PMS Chapter 8: https://projects.gentoo.org/pms/8/pms.html
- Portage source: `lib/_emerge/depgraph.py` (method `_serialize_tasks`)
- Portage priorities: `lib/_emerge/DepPriorityNormalRange.py`
- Paludis orderer: `paludis/resolver/orderer.cc`
- Paludis classifier: `paludis/resolver/labels_classifier.cc`

# Testing and Regression

portage-ng uses multiple testing strategies: PLUnit tests for unit logic,
overlay regression tests for end-to-end scenario validation, and
merge-vs-emerge comparison for correctness measurement against Portage.


## PLUnit tests

Standard SWI-Prolog unit tests in `Source/Test/unittest.pl`:

```bash
make test
````

These test individual predicates in isolation --- version comparison,
domain operations, context merging, EAPI parsing, etc.

== Overlay regression tests
<overlay-regression-tests>
The overlay test suite (`make test-overlay`) runs 80 curated scenarios
against a test overlay in `Repository/Overlay/`. Each scenario has a
specific dependency story and expected behavior.

=== Running
<running>
```bash
make test-overlay
```

Or from the interactive shell:

```prolog
test:run(cases).
```

=== Test scenario anatomy
<test-scenario-anatomy>
Each test under `Documentation/Tests/testNN/` contains:

- #strong[`README.md`] --- description of the dependency story and
  expected outcome
- #strong[`testNN.svg`] --- dependency graph visualization
- #strong[Collapsible transcripts] --- `emerge -vp` vs
  `portage-ng --pretend` output for comparison

=== Coverage areas
<coverage-areas>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Area]], [#strong[Tests]],),
    table.hline(),
    [Basic ordering / default version], [01-02],
    [Cycles (self, indirect, 3-way, PDEPEND)], [03-08, 47, 61-64, 79],
    [Missing dependencies], [09-11],
    [Keywords (stable vs unstable)], [12],
    [Version operators (`=`, `>=`, `~`, `<=`)], [13, 55-56, 69-70, 80],
    [USE conditionals], [14-15],
    [Choice groups (`^^`, `||`, `??`)], [17-25],
    [Blockers (strong/weak)], [26-31, 60],
    [REQUIRED\_USE], [32, 40],
    [USE dependencies (`[flag]`, `[-flag]`, `=`)], [33-39],
    [Slots (`:*`, `:=`, sub-slot)], [41-44],
    [Conflicts (USE, slot, diamond)], [45-46, 48-49, 51],
    [USE merge (shared deps)], [52-53],
    [Virtuals], [57-58],
    [Installed / VDB operations], [65, 73-77],
    [PDEPEND], [66, 79],
    [BDEPEND / IDEPEND], [67, 72],
    [Multi-slot co-install], [68],
    [Fetch-only], [71],
    [Onlydeps], [78],
  )]
  , kind: table
  )

=== XFAIL tests
<xfail-tests>
Tests 58, 59, and 60 are explicitly marked as expected failures (XFAIL)
in the test matrix --- known limitations that are documented but not yet
fixed.

== Merge vs emerge comparison
<merge-vs-emerge-comparison>
The primary correctness metric is comparison against Portage's `emerge`
output across the entire Portage tree.

=== Running a comparison
<running-a-comparison>
```bash
python3 -u Reports/Scripts/compare-merge-emerge.py \
  --root /Volumes/Storage/Graph/portage \
  --full-lists \
  --out Reports/compare-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).json
```

=== Metrics
<metrics>
The comparison produces several accuracy metrics:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Metric]], [#strong[Formula]], [#strong[Meaning]],),
    table.hline(),
    [#strong[CN]], [`100 * inter_cn / union_cn`], [Category/Name match
    (ignoring version)],
    [#strong[CN+V]], [`100 * inter_cnv / union_cnv`], [Category/Name+Version
    match],
    [#strong[CN+V+U]], [`100 * inter_cnvu / union_cnvu`], [Full match
    including USE flags],
    [#strong[Order%]], [`100 * (pairs - inversions) / pairs`], [Ordering
    concordance],
  )]
  , kind: table
  )

Additional counts (from `emerge_ok` pairs only):

- `#blockers` --- total blocker assumptions
- `#cycle breaks` --- total prover cycle-break assumptions
- `#domain assumptions` --- total domain assumptions

=== Targeted comparison
<targeted-comparison>
For a single package:

```bash
python3 -u Reports/Scripts/compare-merge-emerge.py \
  --root /Volumes/Storage/Graph/portage \
  --target-regex '^sys-apps/portage-3.0.77-r3$' \
  --full-lists \
  --out Reports/compare-targeted.json
```

== Prover fail-set comparison
<prover-fail-set-comparison>
Compare two `prover:test(portage)` logs to detect regressions:

```bash
python3 Reports/Scripts/compare-prover-failset.py \
  --baseline baseline.log \
  --candidate candidate.log \
  --out Reports/prover_failset_compare.json
```

== Further reading
<further-reading-19>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- `make test` commands
- #link("24-doc-performance.md")[Chapter 24: Performance and Profiling]
  --- `prover:test_stats` for bulk testing
- #link("25-doc-contributing.md")[Chapter 25: Contributing] ---
  development workflow with regression testing

= Performance and Profiling
<performance-and-profiling>
portage-ng loads on the order of #strong[32,000 ebuilds] into memory and
reasons about their dependencies with #strong[formal proof search]. That
combination is easy to make slow: naive parsing, interpreted queries,
imperative undo stacks, exponential backtracking, and repeated failed
branches can each dominate runtime on their own. The design question is
not "which single trick wins?" but #strong[how we stack complementary
strategies] so the whole pipeline stays responsive.

The answer is #strong[the five pillars of portage-ng performance]:
compiled knowledge (qcompiled cache), compile-time query expansion,
persistent AVL structures for proof state, prescient proving that avoids
redundant work, and incremental learning that narrows the search after
failures. Together they explain why the tree can load with sub-second
queries and why a full prove across all packages can finish in under a
minute on a strong multi-core machine---while leaving room for profiling
and targeted optimization.

This chapter walks those pillars in order, then covers
#strong[instrumentation] (the sampler), #strong[bulk testing],
#strong[known bottlenecks], and a #strong[performance testing
checklist]. For broader testing methodology, see
#link("23-doc-testing.md")[Chapter 23: Testing and Regression].

== Pillar 1: Compiled knowledge (qcompiled `.qlf` files)
<pillar-1-compiled-knowledge-qcompiled-.qlf-files>
The Portage tree is #strong[not] parsed from scratch on every startup.
During `--sync`, metadata is read and the knowledge base is written in a
form that SWI-Prolog can #strong[qcompile] into a binary load
unit---`Knowledge/kb.qlf` (source facts live in `Knowledge/kb.raw`). The
next time the application starts, it loads that #strong[binary]
representation instead of re-parsing large textual artifacts.

That is the #strong[largest single speedup] in the system: startup drops
from #strong[tens of seconds] of parsing and assertion to #strong[under
a second] for the compiled cache, after which reasoning works directly
over in-memory facts. Everything else in this chapter assumes that this
first pillar is in place; without it, no amount of clever proving would
feel fast enough.

== Pillar 2: Goal expansion macros
<pillar-2-goal-expansion-macros>
High-level queries in the knowledge layer are written for clarity; at
#strong[compile time] they are rewritten into #strong[direct cache
access], so the runtime path never pays for meta-interpretation over
generic search.

`goal_expansion/2` in `Source/Knowledge/query.pl` performs this rewrite.
For example, a search by repository, category, and package name expands
straight to an ordered cache entry lookup:

```prolog
user:goal_expansion(query:search(R, C, N), cache:ordered_entry(R, _, C, N, _)).
```

The expanded code calls the indexed predicate #strong[directly].
SWI-Prolog's #strong[first-argument indexing] on `cache:entry/5` (and
related entry predicates) makes those lookups #strong[O(1) amortized] in
typical use: the prover's inner loop sees plain deterministic cache
reads, not a slow interpretive layer.

For how the knowledge base and query surface fit together, see
#link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache].

== Pillar 3: Persistent AVL trees
<pillar-3-persistent-avl-trees>
Proof search maintains large associative structures---proof literals,
models, constraints, triggers---using #strong[`library(assoc)` AVL
trees]. Lookups and updates are #strong[O(log n)]\; for about
#strong[32,000] entries that is on the order of #strong[fifteen
comparisons] per operation, which is cheap enough to live in the inner
loop of dependency proving.

The deeper win is #strong[persistence]: AVL trees in Prolog are
#strong[immutable structures] threaded through the search.
#strong[Backtracking] automatically restores the previous tree without
hand-written save/restore stacks or explicit undo logs---the kind of
machinery imperative resolvers often maintain by hand. That keeps the
prover's control flow simple while remaining safe under deep
choicepoints.

#strong[Practical caveat:] Proof and Model AVLs still #strong[grow with
proof size]. Algorithms should avoid #strong[full traversals] when a
more local structure suffices; the Triggers AVL (see the next pillar)
exists partly so reverse lookups do not devolve into scanning the entire
proof tree. That trade-off shows up again under
#link(<known-bottlenecks>)[Known bottlenecks] below.

== Pillar 4: Prescient proving (avoiding backtracking)
<pillar-4-prescient-proving-avoiding-backtracking>
Naive proof search can exhibit #strong[O(2^n)] behaviour in the worst
case: each wrong choice is explored and then undone by backtracking.
portage-ng pushes hard in the other direction by #strong[merging proof
context] when the same literal is encountered again with #strong[refined
constraints]---via mechanisms such as #strong[feature term
unification]---so the system does not blindly re-prove from scratch
every time the dependency graph revisits a head under slightly different
assumptions.

In practice, for most real packages, that style of #strong[prescient]
handling yields #strong[O(n) amortized] proof steps rather than
exponential churn. The #strong[Triggers AVL] complements this: it
supports #strong[efficient identification of affected heads] when
something downstream changes, instead of linear scans over the whole
proof.

The sampler's #strong[`ctx_union` sampling] (documented later in this
chapter) exists precisely to spot #strong[hot merge paths]---a sign that
context merging is working harder than it should and that some literals
may still be reproved more often than necessary.

== Pillar 5: Incremental learning (avoiding repeated failures)
<pillar-5-incremental-learning-avoiding-repeated-failures>
When a proof attempt fails, portage-ng does not always forget what went
wrong. #strong[Learned constraints] from failed branches can
#strong[persist across reprove retries], #strong[narrowing domains] so
the same conflict is not hit twice the same way. Together with a
#strong[reject set] that records candidates already ruled out, the
prover avoids thrashing on the same dead ends.

That closes the loop with
#link("08-doc-prover.md")[Chapter 8: The Prover]: reprove and learning
are part of the same story as performance. If retries explode without
narrowing behaviour improving, runtime suffers---see
#link(<reprove-retries>)[Reprove retries] under known bottlenecks.

== Sampler module
<sampler-module>
The sampler (`Source/Application/Performance/sampler.pl`) is the main
place to #strong[measure] whether the pillars above are behaving as
intended in production-like runs.

=== Hook performance
<hook-performance>
```prolog
sampler:phase_walltime(Phase, Goal)
```

Wraps `Goal` and records wall-clock time for the named `Phase`. Used by
the pipeline to time each stage (prove, plan, schedule).

```prolog
sampler:phase_record(Phase, Duration)
```

Records a phase timing for later retrieval.

=== Test statistics
<test-statistics>
```prolog
prover:test_stats(Repository)
prover:test_stats_pkgs(Repository, PackageList)
```

Run the prover across all packages (or a specific list) in a repository
and collect aggregate statistics:

- Total packages attempted
- Success rate (no assumptions)
- Cycle-break-only rate
- Domain assumption rate
- Average proof time

=== Feature term unification sampling
<feature-term-unification-sampling>
The sampler tracks feature term unification operations to identify hot
paths in context merging. Excessive merges can indicate redundant
re-proving.

== Bulk testing workflow
<bulk-testing-workflow>
The standard performance testing workflow uses the `--shell` here-doc
pattern:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL
```

For specific packages:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
prover:test_stats_pkgs(portage, ['kde-apps'-'kde-apps-meta']).
halt.
PL
```

== Known bottlenecks
<known-bottlenecks>
=== `memoized_search` (25-30% of proving time)
<memoized_search-25-30-of-proving-time>
`query:memoized_search/2` accounts for 25-30% of total proving time,
with up to 88% of calls redundant for complex packages. The function is
not actually memoized (despite its name) because model construction
depends on mutable proof state:

+ `build_with_use` context varies per dependency path
+ `prover:assuming` flags change between fallback attempts
+ `memo:selected_cn_snap_` evolves during the proof
+ `variant:use_override` / `variant:branch_prefer` change during variant
  mode

A future caching strategy would need to key on all four dimensions.

=== Proof/Model AVL traversals
<proofmodel-avl-traversals>
The Proof and Model AVLs grow linearly with proof size. Full traversals
should be avoided when possible --- use the Triggers AVL for reverse
lookups instead of scanning the Proof tree.

=== Reprove retries
<reprove-retries>
Each reprove retry restarts the proof from scratch. For most targets,
the proof completes in a single pass. Excessive retries (visible as
runtime \> 10 seconds for a single target) suggest a learning bug where
constraints are not being effectively narrowed.

== Performance testing checklist
<performance-testing-checklist>
When testing changes that may affect performance:

+ #strong[Single target runtime] --- should be \< 10 seconds for typical
  packages
+ #strong[`prover:test_stats(portage)`] --- full tree should complete in
  \< 60 seconds on a 28-core machine
+ #strong[Reprove count] --- check that complex packages don't trigger
  excessive retries
+ #strong[Exit codes] --- verify 0/1/2 distribution hasn't regressed

== Further reading
<further-reading-20>
- #link("23-doc-testing.md")[Chapter 23: Testing and Regression] --- the
  full testing methodology
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- proof search
  algorithm and reprove mechanism
- #link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache]
  --- query layer and goal expansion

= Contributing
<contributing>
This chapter covers the development workflow, coding conventions, and
testing practices for contributing to portage-ng.

== Development workflow
<development-workflow>
+ #strong[Start from clean committed state.] Always begin development
  with no uncommitted changes.

+ #strong[Make changes] using the project wrapper for testing:

  ```bash
  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --pretend <target>
  ```

+ #strong[Run tests] to verify correctness:

  ```bash
  make test            # PLUnit tests
  make test-overlay    # Overlay regression tests
  ```

+ #strong[Regenerate `.merge` files] by asking the maintainer to run
  `--graph` to produce updated `.merge` output for the graph directory.

+ #strong[Run compare analysis] to detect regressions:

  ```bash
  python3 -u Reports/Scripts/compare-merge-emerge.py \
    --root /Volumes/Storage/Graph/portage \
    --full-lists \
    --out Reports/compare-$(date +%Y-%m-%d)-$(git rev-parse --short HEAD).json
  ```

+ #strong[Review the comparison table] for regressions in CN, CN+V,
  CN+V+U match percentages, ordering concordance, and assumption counts.

+ #strong[Commit] when regression-free.

== How to run
<how-to-run>
=== Dev wrapper
<dev-wrapper>
Always use the dev wrapper for testing --- never run ad-hoc
`swipl -g "..."` snippets, as they miss required operator definitions,
libraries, and module load order:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --pretend <target>
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell
```

=== Scripted sessions (here-doc pattern)
<scripted-sessions-here-doc-pattern>
For reproducible, non-interactive debugging:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell --timeout 60 <<'PL'
prover:test_stats(portage).
halt.
PL
```

=== CI mode
<ci-mode-1>
For automated checks:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --ci --pretend <target>
echo $?  # 0 = no assumptions, 1 = cycle breaks, 2 = domain assumptions
```

Always include `--pretend` to avoid mutating local state.

== Source file documentation style
<source-file-documentation-style>
Every `.pl` source file follows a strict layout. Use
`Source/Application/System/bonjour.pl` as the canonical reference.

=== File header
<file-header>
```prolog
/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/
```

=== Module documentation (PlDoc)
<module-documentation-pldoc>
```prolog
/** <module> MODULE_NAME_UPPERCASE
Short one-line description.

Optional longer description.
*/
```

Module name in the `<module>` tag is UPPERCASE.

=== Module declaration
<module-declaration>
```prolog
:- module(modulename, []).
```

=== Chapter header (one per file)
<chapter-header-one-per-file>
```prolog
% =============================================================================
% MODULE_NAME_UPPERCASE declarations
% =============================================================================
```

Exactly one `=====` chapter per file, immediately after `:- module`.

=== Section headers
<section-headers>
```prolog
% -----------------------------------------------------------------------------
% Section title
% -----------------------------------------------------------------------------
```

All subsequent sections use `-----` dashes.

=== Predicate documentation
<predicate-documentation>
```prolog
%! module:predicate_name(+Arg1, -Arg2)
%
% Short description of what the predicate does.

module:predicate_name(Arg1, Arg2) :-
  body.
```

=== Spacing rules
<spacing-rules>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Element]], [#strong[Blank lines after]],),
    table.hline(),
    [File header `*/`], [1],
    [PlDoc module comment `*/`], [1],
    [`:- module(...)` declaration], [1],
    [`=====` chapter header], [1],
    [`-----` section header], [1],
    [Predicate doc + last clause], [2],
    [Between clauses of same predicate], [0],
    [End of file], [0 (no trailing blank line)],
  )]
  , kind: table
  )

== Naming conventions
<naming-conventions>
- Source filenames must NOT contain hyphens (`-`) or underscores (`_`).
  Use concatenated lowercase words: `knowledgebase.pl`, not
  `knowledge_base.pl`.

- Exception: `portage-ng.pl` (project entry point).

- Prolog module names follow the same rule: `:- module(gentoo, [])`.

- Subdirectory names under `Source/` may use CamelCase: `Application/`,
  `Domain/`, `Config/`, `Pipeline/`.

== Comment guidelines
<comment-guidelines>
Do not add comments that just narrate what the code does. Comments
should only explain non-obvious intent, trade-offs, or constraints.
Avoid:

```prolog
% Get the version     ← redundant
version:get(V).
```

Prefer:

```prolog
% Suffix rank maps PMS suffix ordering to integers for compare/3
suffix_rank('_alpha', 1).
```

== Compare tooling
<compare-tooling>
Comparison scripts live in `Reports/Scripts/`:

- `compare-merge-emerge.py` --- merge-vs-emerge plan comparison
- `compare-prover-failset.py` --- prover fail-set regression detection

Report filenames follow the format:
`compare-<YYYY-MM-DD>-<short-commit-hash>.json`

Do not create ad-hoc compare scripts outside `Reports/Scripts/`.

== Things to avoid
<things-to-avoid>
- Do NOT run `--sync` or `--graph` from inside sandbox/CI --- the user
  will run these externally.
- Do NOT create `metadata/md5-cache/*` manually --- `--sync` produces
  those.
- Do NOT use direct `tty_size/2` calls --- use
  `config:printing_tty_size/2` (safe in non-tty environments).
- Do NOT run ad-hoc `swipl -g "..."` snippets --- always use the dev
  wrapper.

== Further reading
<further-reading-21>
- #link("23-doc-testing.md")[Chapter 23: Testing and Regression] ---
  testing methodology
- #link("24-doc-performance.md")[Chapter 24: Performance and Profiling]
  --- performance testing
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- build and run instructions


#context {
  let figs = query(figure)
  for fig in figs {
    let loc = fig.location()
    let page = counter(page).at(loc).first()
    // Only show figures on pages 88-94
    if page >= 88 and page <= 94 {
      [Page #page: #fig.caption.body]
    }
  }
}
