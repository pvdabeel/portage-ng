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
pkgcore's `merge_plan` implements its own frame stack and state
checkpoints for backtracking. Paludis's `decider.cc` implements its own
constraint accumulator with exception-driven restart. All three
re-invent mechanisms that Prolog provides as proven primitives. By
relying on these primitives, the codebase becomes easier to read and
understand --- developers can focus fully on declaring domain knowledge
rather than maintaining search and backtracking machinery.

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
rule(assumed(portage://dev-libs/foo-1.0:run), [])
```

\(The real literal's context also carries `assumption_reason(...)` and
`suggestion(accept_keyword, ...)` tags.) This assumption appears in the
proof, flows through the plan, and is presented to the user as: "I
assumed dev-libs/foo-1.0 could be merged. To make this work, I will add
it for you to package.accept\_keywords."

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
reasoning engine --- the prover and the ordering laws --- did not change
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
machine-readable description of its resolved configuration. The orderer
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
:- dpublic([get_title/1, add_title/1, remove_title/1]).
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

get_age(Age) ::-
  ::age(Age).

set_age(Age) ::-
  <=age(Age).

get_title(Title) ::-
  ::title(Title).

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
    table.header([], [#strong[Portage]], [#strong[pkgcore]], [#strong[Paludis]], [#strong[portage-ng]],),
    table.hline(),
    [#strong[Language]], [Python], [Python], [C++], [SWI-Prolog],
    [#strong[Model]], [Greedy graph + retry], [Frame-stack DFS +
    backtrack], [Constraint accumulator + restart], [Inductive proof
    search],
    [#strong[Conflicts]], [Retries with mask accumulation], [Backtrack
    to frame checkpoint; next choice], [Restarts with
    preloads], [Iterative refinement with learned domains],
    [#strong[Completeness]], [Sometimes fails], [Sometimes fails], [May
    exhaust restarts], [Always produces a plan],
    [#strong[Guarantees]], [None], [None], [None], [Every plan is a
    proof],
  )]
  , kind: table
  )

For a detailed comparison of the reasoning models, see
#link("23-doc-resolver-comparison.md")[Chapter 23: Resolver Comparison].

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
- #link("23-doc-resolver-comparison.md")[Chapter 23: Resolver Comparison]
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
    with SSL, PCRE, HTTP, crypto, and pengines support. Line editing
    (libedit or GNU readline) is optional; see below.],
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
    [#strong[Python 3]], [Timeout watchdog in the dev wrapper.],
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
- #strong[libedit or GNU readline] --- optional. Needed only for
  `--shell` line editing and history. portage-ng loads
  `library(editline)` first and falls back to `library(readline)`.
  `--shell` still starts if neither is present; up-arrow history is
  then unavailable. `--pretend` and `--merge` do not need either
  library. On Gentoo these are `dev-libs/libedit` (BSD libedit; SWI
  `USE=cli`) or `sys-libs/readline` (SWI `USE=readline`). Do not
  confuse BSD libedit with `dev-libs/editline` (Minix editline), which
  SWI does not use.
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

See #link("25-doc-testing.md")[Chapter 25: Testing and Regression] for
details.

== Further reading
<further-reading-1>
- #link("03-doc-configuration.md")[Chapter 3: Configuration] --- setting
  up Portage tree paths, `/etc/portage`, and profiles
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] --- full
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
    [`config:profile_loading/2`], [`standalone → cached`], [Controls
    whether profile data is parsed from the Portage tree on every
    startup (`live`) or loaded from a pre-serialized cache (`cached`).
    Set per mode: standalone, daemon, worker, client, server.],
    [`config:preference_cache/2`], [`standalone → cached`], [Controls
    whether `preference:init/0` reloads materialized state from
    `Knowledge/preference.qlf` when the stamp matches, or rebuilds from
    profile + `/etc/portage` on every startup.],
  )]
  , kind: table
  )

See #link(<profile-loading-strategy>)[Profile loading strategy] for
details on generating and using the profile cache. See
#link(<preference-cache>)[Preference cache] for the materialized
preference cache.

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
    [`config:pkg_directory/1`], [Path to the VDB directory
    (`/var/db/pkg` on a standard Gentoo system). Defined per host in
    `Source/Config/<host>.local.pl`.],
    [`config:world_file/1`], [Path to the world set file (auto-resolved
    from hostname).],
    [`config:set_dir/1`], [Directory of named set files (one atom list
    per file).],
    [`config:glsa_dir/1`], [Optional override for
    `$PORTDIR/metadata/glsa` (GLSA XML).],
    [`config:glsa_injected_file/1`], [Applied-GLSA id file (Portage
    `glsa_injected` equivalent).],
    [`config:preserved_libs_registry/1`], [Path to Portage's
    `preserved_libs_registry` JSON used by `@preserved-rebuild`. Default
    maps `…/db/pkg` → `…/lib/portage/preserved_libs_registry`.],
    [`config:preserved_libs_registry_override/1`], [Host-specific
    override for the preserve-libs registry path (multifile /
    dynamic).],
    [`config:graph_directory/1`], [Output directory for generated
    dependency graphs and `.merge` files. Defined per host in
    `Source/Config/<host>.local.pl`.],
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

=== Building
<building-1>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:build_transient_retry/1`], [`true`], [Retry a phase once
    when it fails with bash's PID-reuse race
    (`wait: pid N is not a child of this shell`).],
    [`config:build_serial_retry/1`], [`true`], [Retry a failed
    compile/test/install phase once with `MAKEOPTS=-j1` to rule out
    parallel-make races.],
    [`config:deconflict_collisions/1`], [`override`], [Merge-time file
    collision handling when a blocker atom is missing from metadata:
    `off` (fail as usual), `report` (fail, but surface the collision as
    a deconfliction assumption), or `override` (re-merge with collision
    protection disabled so the merge succeeds).],
    [`config:ghc_abi_repair/1`], [`true`], [Repair GHC ABI-hash breakage
    in-transaction: rebuild the packages listed by haskell-cabal's
    broken-package check, then re-run the failed phase (native
    `haskell-updater`).],
    [`config:ocaml_abi_repair/1`], [`true`], [Repair OCaml/findlib ABI
    breakage in-transaction: map stale compiled-unit errors to their
    installed owners via the VDB, rebuild them, then re-run the failed
    phase.],
    [`config:subslot_rebuild/1`], [`true`], [Plan same-version rebuilds
    of installed reverse dependencies when a sub-slot (`:=`) provider's
    ABI changes inside a transaction. Complementary to the
    `@preserved-rebuild` #emph[set] (FEATURES=preserve-libs consumers);
    this pass is automatic during prove/plan.],
    [`config:toolchain_reactivation/1`], [`true`], [Re-activate the
    toolchain right after a toolchain package merges, before dependent
    builds continue.],
  )]
  , kind: table
  )

See #link("16-doc-building.md")[Chapter 16: Building and Execution] for
how the retry chain and the domain exception fixups work.

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

=== Network
<network>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:server_host/1`], [`'mac-pro.local'`], [Server hostname pin
    for client/worker mode (Bonjour must match).],
    [`config:server_bind/1`], [`localhost`], [Interface the Pengine
    server binds (`localhost` or `*`).],
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
`--llm`, or semantic search, the LLM modules can be removed from the
load graph without affecting core functionality (resolving, ordering,
building).

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Setting]], [#strong[Default]], [#strong[Purpose]],),
    table.hline(),
    [`config:llm_default/1`], [`claude`], [Default LLM service for
    `--explain` and `--llm`.],
    [`config:llm_model/2`], [\(per service)], [Model version for each
    LLM provider (ChatGPT, Claude, Gemini, Ollama, etc.).],
    [`config:llm_use_tools/1`], [`true`], [Whether the LLM may execute
    Prolog code locally during a conversation.],
    [`config:llm_server_calls/1`], [`false`], [Allow Pengines clients to
    call `explainer:call_llm/3` on the server (uses server API keys).],
    [`config:curl_allow_http/1`], [`false`], [Permit cleartext http
    distfile mirrors (ftp never allowed).],
    [`config:file_integrity/1`], [`prefer`], [Knowledge sidecar policy:
    `prefer`, `require`, or `off`.],
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
- #strong[`Knowledge/glsa.qlf`] --- Gentoo Linux Security Advisories
  parsed from `metadata/glsa/` (see
  #link("20-doc-glsa.md")[Chapter 20]).
- #strong[`Knowledge/preference.qlf`] --- materialized preference state
  (built on first startup; see
  #link(<preference-cache>)[Preference cache]).

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

In client-server mode the server holds its #emph[own] `pkg` repository,
which may differ from the client's installed set. A client can upload
its local VDB with `--import-vdb`\; the server registers it as a
per-client repository (`pkg@<clienthost>`) and uses it for that client's
plans. With `config:client_auto_import_vdb(true)` (the default) this
happens automatically before each client command whenever the local VDB
changed. See #link("18-doc-distributed.md")[Chapter 18] for details.

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
#link("15-doc-cli.md")[Chapter 15: Command-Line Interface] for details).
Each mode can use a different loading strategy:

```prolog
config:profile_loading(standalone, cached).
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

== Preference cache
<preference-cache>
After profile and `/etc/portage` data are merged, `preference:init/0`
normally materializes a large set of dynamic facts (global USE, package
masks, per-package USE overrides, license groups, world snapshots). That
work can take a few seconds when profile masks must be matched against
the full portage cache.

To avoid repeating that on every startup, portage-ng can persist the
#strong[materialized preference state] to disk:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[File]], [#strong[Role]],),
    table.hline(),
    [`Knowledge/preference.raw`], [Textual serialization of preference
    facts (intermediate)],
    [`Knowledge/preference.qlf`], [QLF-compiled reload unit],
    [`Knowledge/preference.stamp`], [Fingerprint of inputs (file mtimes
    \+ env vars)],
  )]
  , kind: table
  )

The cache is #strong[regenerated automatically] when the stamp no longer
matches --- for example after `--sync` (which invalidates the cache when
`kb.qlf` / `profile.qlf` change), after editing `/etc/portage`, or when
`USE` / `ACCEPT_KEYWORDS` / `ACCEPT_LICENSE` change in the environment.

Control per mode in `config.pl`:

```prolog
config:preference_cache(standalone, cached).
config:preference_cache(daemon,     cached).
config:preference_cache(worker,     cached).
config:preference_cache(client,     live).
config:preference_cache(server,     cached).
```

Client mode keeps `live` rebuilding because preference facts are
injected from the server in distributed proving.

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
#strong[`--sync`] refreshes `Knowledge/kb.qlf` and the profile cache
(and invalidates the preference cache) so resolution sees an up-to-date
union of tree, VDB, and world-related facts.

== Further reading
<further-reading-2>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- prerequisites and first run
- #link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache]
  --- how the Portage tree is loaded into Prolog facts
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] --- CLI
  options that interact with configuration
- #link("20-doc-glsa.md")[Chapter 20: Gentoo Linux Security Advisories (GLSA)]
  --- `Knowledge/glsa.qlf` built during `--sync`

= Architecture Overview
<architecture-overview>
Reasoning about software configurations is not a single algorithm you
"run once." It is a chain of transformations: turn repository facts into
a logical problem, search for a proof that explains #emph[why] each step
is needed, turn that proof into an ordered plan, and finally render or
execute it. portage-ng is structured as a #strong[pipeline] because that
sequence is the natural shape of the work. Each stage has a clean
role---parse facts, resolve a configuration, order it, print (or build)
it---and can be characterized in isolation: the reader produces a fixed
vocabulary of literals; the resolver produces a justified configuration
with its dependencies; the orderer refines that into something a human
or a build system can follow. Treating the system as a pipeline is
therefore a #strong[design decision]: it keeps stages testable,
replaceable, and easier to reason about than a monolith where parsing,
search, ordering, and output are tangled together.

== The pipeline
<the-pipeline>
portage-ng processes a user request through a linear pipeline of five
stages:

#figure(image("Diagrams/04-pipeline-overview.svg", alt: "Pipeline overview"),
  caption: [
    Pipeline overview
  ]
)

```
reader/parser  →  resolver  →  orderer  →  printer  →  builder
                  └────── pipeline ─────┘
                     (both passes run on the generic prover)
```

The resolver and orderer are thin stage wrappers around one generic
proving engine, `prover.pl`. The prover knows nothing about resolving or
ordering: callers hand it a rule module together with the goals
(`prover:prove(Rules, ...)`). The resolver passes the `resolving` rule
set (pass 1: #emph[what] --- versions, USE, slots); the orderer passes
the `ordering` rule set (pass 2: #emph[when] --- waves).

The resolve pass produces four AVL trees --- #strong[Proof],
#strong[Model], #strong[Constraints], and #strong[Triggers] --- that
flow through the rest of the pipeline. Together they capture #emph[why]
each literal was accepted, #emph[what] is known, #emph[what
restrictions] must hold, and #emph[who depends on whom]. Section
#link(<data-structures>)[Data structures] describes each one in detail.

The resolver and orderer together form the `pipeline` module. Two
canonical entry points share the same 5-tier committed-choice
progressive relaxation (strict, keyword\_acceptance, blockers, unmask,
keyword\_unmask):

```prolog
pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers)
pipeline:prove_with_fallback(Goals, Proof, Model, Triggers)
```

The first runs the full pipeline (resolve + order) and is used by all
production paths. The second runs the resolve pass only and is used by
layered tests and `--bugs`.

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Stage]], [#strong[Module]], [#strong[Input]], [#strong[Output]],),
    table.hline(),
    [#strong[Reader / Parser]], [`reader.pl`, `parser.pl`,
    `eapi.pl`], [Ebuild md5-cache files], [Prolog facts
    (`cache:entry/5`)],
    [#strong[Resolver]], [`resolver.pl` → `prover.pl` +
    `resolving.pl`], [Goal literals (from user)], [Proof, Model,
    Constraints, Triggers],
    [#strong[Orderer]], [`orderer.pl` → `prover.pl` +
    `ordering.pl`], [Proof, Triggers], [Ordering proof + wave-list
    Plan],
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
loads the full knowledge base, runs the complete pipeline (resolver,
orderer, printer, builder), and produces results locally. This is what
you use for day-to-day `--pretend`, `--merge`, `--shell`, and `--sync`.

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
results. Each worker runs the full pipeline locally (resolver, orderer),
so proving scales horizontally --- adding more worker machines reduces
wall-clock time for large proof sets.

See #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] for the
full mode reference and
#link("18-doc-distributed.md")[Chapter 18: Distributed Proving] for TLS
certificate setup and cluster configuration.

== Module load order
<module-load-order>
Each mode loads only the modules it needs. This keeps startup time,
memory footprint, and failure modes appropriate to the deployment:

The load order is defined in `Source/loader.pl`. `load_modules/1`
selects a mode's groups from `loader:mode/3`:

```
load_modules(common)       — SWI-Prolog libraries, OO context, config, OS,
                             interface, EAPI, reader, subprocess, bonjour,
                             feature unification
                             (loaded before mode dispatch)

load_modules(standalone)   — Full pipeline: KB (cache, repository, query),
                             Gentoo domain (version, resolving, ordering,
                             ebuild, VDB, preference, exceptions), prover,
                             resolver, orderer, printer, builder, grapher,
                             writer, test
                             (also loads LLM backends unless
                             config:load_llm_modules(false))

load_modules(server)       — Standalone groups plus HTTP server, Pengines,
                             sandbox

load_modules(client)       — HTTP/socket client, subset of printer/pipeline

load_modules(worker)       — Same pipeline as standalone + client + cluster

load_modules(daemon)       — Standalone groups plus the daemon accept loop

load_modules(ipc)          — Ultralight IPC client (no LLM)
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
resolving:rule(Head, Body)
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
    `assumed(rule(Lit))`], [`dep(N, Body)?Ctx`], [Which rule and body
    justified each literal; `N` is the dependency count, `Ctx` the proof
    context],
    [#strong[Model]], [`Lit` or `assumed(Lit)`], [`Ctx`], [Every literal
    that has been established, mapped to the context under which it was
    proven],
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
knowledge base, prover, orderer, and output pipeline.

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
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  rule modules plug into the prover
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- pass 1: justified configuration
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- the second proving pass and wave projection

= Proof Literals
<proof-literals>
== The universal literal format
<the-universal-literal-format>
Every term that flows through the portage-ng pipeline --- from rules to
prover to orderer to printer --- uses the same universal format:

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
  `:update`, …) that tells the #strong[orderer] which phase of work this
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
satisfied. Same-slot self-references (a package listing itself as a
build dependency in the same slot) are treated as bootstrap dependencies
and checked against the VDB. Cross-slot self-references (same category
and name but a different slot) are resolved normally as regular
dependencies.

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

This commit is always final (a cut after the first viable alternative).
Variant exploration does not remove that cut: it #strong[re-runs the
prover] with thread-local branch-preference overrides
(`variant:use_override`, `variant:branch_prefer`) that reorder the
candidates, so the same cut selects a different branch on the re-proof
--- see
#link("08-doc-prover.md#multiple-stable-models")[Multiple stable models].

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
#link("22-doc-context-terms.md")[Chapter 22: Context Terms]): a
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
  build dependency in the same slot (which happens for bootstrap
  packages), the rules recognise this by comparing the dependency
  target's category, name, and slot to the `self` entry. Same-slot
  self-deps are checked against installed packages; cross-slot self-deps
  (e.g.~`antlr-tool:4` depending on `antlr-tool:3.5`) are treated as
  regular dependencies and resolved normally.

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
The ordering pass needs to know the order in which actions should be
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

The ordering bindings (`Source/Domain/Gentoo/Rules/ordering.pl`) read
both `after` and `after_only` from every literal's context to derive the
hard requirements and soft preferences that drive the second proving
pass (Chapter 13).

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
#link("22-doc-context-terms.md")[Chapter 22: Context Terms] for full
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

+ #strong[Orderer] treats each rule head in the Proof AVL as a plan step
  and proves `scheduled/1` for it through the planning laws; wave
  numbers are projected from the resulting availability proofs.

+ #strong[Printer] reads the Plan (a list of waves), looks up each
  literal in the Model AVL to recover its context, and formats the
  output.

== Worked example
<worked-example>
Tracing `target('sys-apps/portage'):run?{[]}` through the pipeline (term
shapes simplified: the real goal wraps a `qualified_target/6` term
parsed from the CLI argument, and the non-oneshot run-target rule also
adds a `world(...):register` condition):

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

8. Orderer places :download in wave 1, :install in wave 2, :run in wave 3

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
- #link("22-doc-context-terms.md")[Chapter 22: Context Terms] --- deep
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
    [`cache:entry_metadata/4`], [Per-entry key/value metadata: EAPI,
    SLOT, KEYWORDS, LICENSE, etc.],
    [`cache:ordered_entry/5`], [Entries ordered by version (for
    candidate selection)],
    [`cache:manifest/5`, `cache:manifest_metadata/6`], [Manifest files
    and their checksums],
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
#link("23-doc-resolver-comparison.md")[Chapter 23: Resolver Comparison]
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
portage:sync.                  % Sync from remote + regenerate caches
portage:update_cache.          % Re-read md5-cache into Prolog facts
portage:query(Query, Result).  % Query entries (delegates to query:search/2)
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
+ Invalidates `Knowledge/preference.qlf` (materialized preference cache;
  rebuilt on next startup)

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

When `config:preference_cache/2` is set to `cached` for the active mode,
the first `preference:init/0` after startup (or after invalidation)
writes `Knowledge/preference.qlf` and a companion
`Knowledge/preference.stamp`. Subsequent starts reload the materialized
preference state in milliseconds while the stamp matches (see
#link("03-doc-configuration.md")[Chapter 3: Configuration]).

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

=== `model(...)` queries --- dependency model construction
<model...-queries-dependency-model-construction>
Beyond simple metadata lookups, `query:search/2` also supports
#strong[model queries] that compute derived structures from the raw
cache data. The most important of these constructs the #strong[grouped
dependency model] for an ebuild:

```prolog
query:search(model(dependency(Merged, install)):config?{Ctx}, R://E).
query:search(model(dependency(Merged, run)):config?{Ctx}, R://E).
query:search(model(dependency(Merged, pdepend)):config?{Ctx}, R://E).
query:search(model(dependency(Merged, fetchonly)):config?{Ctx}, R://E).
```

Each of these is expanded at compile time into a sequence of:

+ #strong[Self-context injection] --- ensures `self(R://E)` is present
  in `Ctx`, so downstream rules can identify circular self-dependencies.
+ #strong[`findall` over raw dependency metadata] --- collects all
  `cache:entry_metadata/4` facts for the relevant dependency keys
  (BDEPEND, CDEPEND, DEPEND, IDEPEND, RDEPEND, and/or PDEPEND depending
  on the phase).
+ #strong[`prover:prove_model/6`] --- evaluates USE-conditional branches
  in the dependency specification, producing an AVL model of active
  dependency literals.
+ #strong[`group_dependencies/2`] --- groups the flat dependency list by
  category/name/slot/phase, producing the `grouped_package_dependency`
  terms that the rules layer consumes.

The result `Merged` is a list of grouped dependency terms ready for
resolution by the rules layer (see
#link("12-doc-resolution.md")[Chapter 12]).

#strong[How is this cached?] Model construction depends on mutable proof
state beyond the explicit context argument: `build_with_use` varies per
dependency path, `prover:assuming` flags change between fallback
attempts, and `memo:selected_cn_snap_` evolves during the proof. Two
early cache attempts that tried to #emph[clear] the cache when this
state changed were abandoned as unsound. The current design instead
encodes every mutable input #strong[in the cache key]: results are
memoised per proof in `memo:dep_model_cache_/5` under a key
(proof-context USE state, assumption flags, choice-group signature).
See the "Dependency-model cache
key" section in `Source/Knowledge/query.pl` for the full key design.

== Further reading
<further-reading-5>
- #link("07-doc-eapi-grammar.md")[Chapter 7: The EAPI Grammar] --- how
  md5-cache files are parsed into cache predicates
- #link("03-doc-configuration.md")[Chapter 3: Configuration] ---
  repository path setup
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the prover
  queries the knowledge base
- #link("20-doc-glsa.md")[Chapter 20: Gentoo Linux Security Advisories (GLSA)]
  --- sibling `Knowledge/glsa.qlf` store (not a package repository)

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
  version([3, 0], '', 4, 0, [], 0, '3.0'),
  [slot('0'), subslot('3'), equal],
  [use(enable(ssl), none), use(disable(test), none)])
```

The first argument (`install` / `run` / `compile`) records #emph[which]
PMS dependency class is being parsed, so the same DCG surface syntax
feeds slightly different typing in the abstract syntax: `install` for
DEPEND/BDEPEND/IDEPEND, `run` for RDEPEND/PDEPEND (PDEPEND is re-tagged
`pdepend` at the query layer), and `compile` for CDEPEND.

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
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- how dependency terms are consumed during proof construction
- #link("24-doc-dependency-ordering.md")[Chapter 24: Dependency Ordering]
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
a literal, `resolving:rule/2` (or the configured `rule/2` delegate)
returns a body --- a list of sub-literals that must hold for the head to
hold.] Everything that makes Gentoo "Gentoo" --- USE flags, slots,
version domains, PDEPEND side effects --- lives in the rule layer and in
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

  - If `heuristic:cycle_benign/2` (literal + cycle path) succeeds, treat
    it as already proven (benign cycle --- no assumption recorded).
  - Otherwise, record a cycle-break assumption (`assumed(rule(Lit))` in
    Proof, `assumed(Lit)` in Model).

+ #strong[Expand via `rule/2`.] Call `resolving:rule(Lit, Body)` to get
  the rule body --- the list of sub-literals that must be proven to
  justify `Lit`.

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
downstream consumers without having to recompute it: the explainer reads
it when reconstructing justifications, and the special value `-1` marks
cycle-break assumptions. Storing the count once, at proof time, avoids
repeated `length/2` calls over the same body list.

Special keys: - `assumed(rule(Lit))` with `dep(-1, Body)?Ctx` --- prover
cycle-break - `rule(assumed(Lit))` with `dep(0, [])?Ctx` --- domain
assumption

=== Concrete Proof AVL entry
<concrete-proof-avl-entry>
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

+ #strong[Plan generation.] The ordering pass and the printer read the
  model to determine which literals are in the proof and what contexts
  they carry.

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

```
First encounter:   openssl:install ?{use_state([ssl],       [])}
Second encounter:  openssl:install ?{use_state([threads],   [])}
After unification: openssl:install ?{use_state([ssl,threads],[])}
```

The merged context commits openssl to satisfying #strong[both] paths at
once. The prover then checks whether this wider context is still
consistent with every constraint the rules attach to that literal ---
profile masks, `REQUIRED_USE`, version domains, and so on.

- If the check #strong[succeeds], no full re-proof is needed. The prover
  re-expands the rule under the merged context and proves only the
  #strong[new] body literals that the wider context introduces beyond
  what was already established.
- If the check #strong[fails] (for example, contradictory flags --- a
  USE flag required both enabled and disabled), the merge is rejected
  and the prover #strong[backtracks] to try another candidate.

That is the sense in which the prover is "prescient": #strong[later
requirements are folded into the context of an earlier proof step]
through merging and targeted re-expansion, rather than discovering the
conflict only after committing to a too-narrow past choice.

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

=== Construction
<construction>
When the prover proves head literal #strong[A] with body #strong[\[B, C,
D\]], it extends the Triggers AVL with three reverse edges:

```
Proof (forward):     rule(A) → dep(3, [B, C, D])

Triggers (reverse):  B → [A, …]
                     C → [A, …]
                     D → [A, …]
```

In general, for a rule `rule(H, Body)` where `Body = [L₁, L₂, …, Lₙ]`,
the operation `add_triggers/4` inserts:

#quote(block: true)[
For each Lᵢ ∈ Body:   Triggers\[Lᵢ\] := \[H | Triggers\[Lᵢ\]\]
]

Each time a rule is recorded or re-recorded (including after a prescient
merge), these reverse edges are extended so the index stays consistent
with the current bodies.

=== Concrete example
<concrete-example>
Suppose the prover establishes:

```
rule(sys-apps/portage:install) → dep(3, [dev-lang/python:install,
                                          dev-libs/openssl:install,
                                          sys-libs/glibc:install])
```

The Triggers AVL then contains:

```
dev-lang/python:install  → [sys-apps/portage:install, …]
dev-libs/openssl:install → [sys-apps/portage:install, …]
sys-libs/glibc:install   → [sys-apps/portage:install, …]
```

If openssl's context later changes (prescient merge adds a new USE
flag), the prover can look up `Triggers[dev-libs/openssl:install]` in
O(log n) time and immediately find that `sys-apps/portage:install` needs
to be revisited.

=== Forward vs reverse lookup
<forward-vs-reverse-lookup>
The Proof and Triggers AVLs are #strong[duals] of each other:

#figure(
  align(center)[#table(
    columns: 4,
    align: (left,left,left,left,),
    table.header([#strong[Direction]], [#strong[AVL]], [#strong[Lookup]], [#strong[Answers]],),
    table.hline(),
    [Forward], [Proof], [`rule(H) → dep(N, Body)`], [What does H depend
    on?],
    [Reverse], [Triggers], [`L → [H₁, H₂, …]`], [Who depends on L?],
  )]
  , kind: table
  )

Together they form a #strong[bidirectional dependency graph]: Proof
walks forward from heads to bodies; Triggers walks backward from bodies
to heads.

=== Downstream use
<downstream-use>
Later phases --- the orderer (merge-order bias), diagnostics --- use
Triggers to answer #strong["if this literal moves, what else moves?"] in
logarithmic time per lookup. Without these reverse edges, nothing in the
pipeline could enumerate which install heads depended on a given
dependency literal, and the graph carried out of proving would be
incomplete for anything that walks dependencies backwards.

== Entry rules and the pipeline
<entry-rules-and-the-pipeline>
#figure(image("Diagrams/08-prove-plan.svg", alt: "prove_plan pipeline"),
  caption: [
    prove\_plan pipeline
  ]
)

The pipeline module provides two canonical entry points, both with the
same 5-tier committed-choice progressive relaxation (strict,
keyword\_acceptance, blockers, unmask, keyword\_unmask):

- `pipeline:prove_plan_with_fallback/5` --- full pipeline (prove +
  order). Used by production paths (`--pretend`, `--graph`, `--build`)
  and `pipeline:test_stats`.
- `pipeline:prove_with_fallback/4` --- resolve pass only. Used by
  layered tests (`resolver:test`, `orderer:test`) and `--bugs`. Each
  test layer adds its own stages on top.

Underneath, `prove_plan_basic/6` chains two stages (the trailing SCCs
argument is always `[]` --- the rule-based orderer leaves no remainder):

```prolog
pipeline:prove_plan_basic(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL, SCCs)
```

+ `resolver:resolve/9` --- hands the `resolving` rule set to
  `prover:prove/10`\; constructs Proof, Model, Constraints, and Triggers
+ `orderer:order/5` --- hands the `ordering` rule set to the same prover
  for a second proving pass; projects the wave-list plan (Chapter 13)

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
flag configuration space. Variants are explored by re-proving the target
under thread-local branch-preference overrides (`variant:use_override`,
`variant:branch_prefer`) that steer the committed choices --- the
choice-group cut is never removed within a single proof.

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
`heuristic:proof_obligation/4`.

== Choice-event log
<choice-event-log>
For debugging which `||` arm or version candidate the resolver tried,
use `--choice-log` via the `portage-ng-dev` wrapper. The wrapper passes
`-Dchoice_log=true` so emit/wrap sites are compiled in; without that
define, `goal_expansion` compiles them to `true` / the wrapped Goal
(zero overhead, same pattern as `--profile` / `instrumentation`).

Runtime arming still requires `--choice-log` (or `choicelog:arm/0`).
`choicelog` (`Source/Application/Performance/choicelog.pl`) records:

- `any_of` --- trying / succeeded / failed for choice-group arms
- `version` --- alternative multi-candidate binds (`index > 1` only)
- `reject` / `learn` / `reprove` / `assumption` --- sparse conflict path

After prove, a human-readable dump is written to stderr. From `--shell`
(with `-Dchoice_log=true`), `choicelog:events/1` returns the term list
and `choicelog:dump/0` reprints it. See also
#link("Policy/choice.md")[Policy: Choice].

== Further reading
<further-reading-7>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- the reprove mechanism and constraint learning
- #link("05-doc-proof-literals.md")[Chapter 5: Proof Literals] --- the
  literal format
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  `rule/2` and rule modules plug in
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- the `resolving` rule set
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
rules, constraint guards, progressive relaxation, assumption printing,
and the analogy to conflict-driven clause learning.

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

#figure(image("Diagrams/09-reprove-loop.svg", alt: "Reprove loop structure"),
  caption: [
    Reprove loop structure
  ]
)

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

=== Domain Assumptions (`rule(assumed(X))`)
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
`dep(0, [])?Ctx` - Model: `assumed(X)` → `Ctx` (the `assumed(X)` body
literal is proved as a regular literal; exit-code detection scans for
these keys) - Plan: rendered as "verify" steps + "Domain assumptions"
warning block

=== Prover Cycle-Break Assumptions (`assumed(rule(X))`)
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
`dep(-1, Body)?Ctx` - Model: `assumed(Lit)` → `Ctx` - Plan: ordered
normally by the ordering pass; cycle explanation via the printer's cycle
section (`Printer/Plan/cycle.pl`)

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
    [Model key], [`assumed(X)`], [`assumed(Lit)`],
    [dep count], [0], [-1],
    [Introduced by], [rules layer], [prover layer],
    [Represents], [unsatisfiable dependency], [cyclic dependency],
    [Printed as], ["Domain assumptions"], [cycle break],
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
    [`maybe_learn_wildcard_domain`], [Wildcard dep fails and parent
    already narrowed or single-version; learns upper-bound `cn_domain`
    from wildcard],
    [`maybe_learn_parent_narrowing`], [Parent introduced a dep that made
    (C,N) unsatisfiable; learns to exclude parent version],
    [`maybe_request_grouped_dep_reprove`], [Effective domain conflicts
    with selected CN; domain inconsistent; version/slot constraints
    present],
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
When `prove_with_retries` catches a `prover_reprove(Info)` exception, it
delegates to `heuristic:handle_reprove/2`, which proceeds in three
steps:

+ #strong[Record what went wrong.] The handler extracts the conflicting
  category, name, domain, and candidate list from `Info` and adds them
  to a reject set (`memo:cn_domain_reject_`). If the conflict was
  introduced by a specific parent, that origin is also recorded so the
  prover avoids the same path on the next attempt.

+ #strong[Decide whether to retry.] If new information was actually
  learned (`Added = true`) and the attempt count is still below
  `reprove_max_retries`, the handler restarts the proof from scratch by
  calling `prove_with_retries` with an incremented attempt counter. The
  learned rejects carry over, so the prover will not repeat the same
  conflict.

+ #strong[Give up gracefully.] If nothing new was learned, or the retry
  budget is exhausted, the handler calls `reprove_exhausted`, which
  #strong[clears] the reject set so the final attempt runs unbiased. It
  then invokes `prove_once` with reprove #strong[disabled] --- no
  further `prover_reprove` exceptions can be thrown, so the proof
  completes with assumptions where necessary.

=== Learned Constraint Store
<learned-constraint-store>
The `prover:learn/3` and `prover:learned/2` predicates maintain a
key-value store that #strong[persists across reprove retries] within the
same top-level `prove/10` invocation. This is distinct from the reject
set (which accumulates and is cleared on exhaustion).

The domain uses learned constraints for:

- #strong[Candidate narrowing] --- `grouped_dep_effective_domain`
  intersects the local+context domain with any learned domain.
- #strong[Conflict learning] --- constraint guards learn the domain when
  a conflict is detected.
- #strong[Parent narrowing] --- `maybe_learn_parent_narrowing` learns to
  exclude the parent version when a child dep cannot be satisfied.
- #strong[Wildcard failure learning] --- `maybe_learn_wildcard_domain`
  derives an upper-bound domain from a wildcard constraint
  (e.g.~`=pkg-0.6*` → `< 0.7`) when parent narrowing alone could not
  resolve the conflict.

=== Retry Budget
<retry-budget>
`reprove_max_retries` defaults to 20 (configurable via
`config:reprove_max_retries/1`). The final attempt runs with reprove
disabled so the proof can complete with assumptions if necessary.

== Use model violation flow
<use-model-violation-flow>
When a parent package forces USE flags on a dependency via bracketed USE
deps (e.g.~`cat/pkg[feature]`), and the dependency's `REQUIRED_USE`
forbids that flag combination, the REQUIRED\_USE violation mechanism
ensures the prover explores alternatives before assuming.

=== Step-by-step flow
<step-by-step-flow>
#figure(image("Diagrams/09-use-violation-flow.svg", width: 42.0%, alt: "Use model violation flow"),
  caption: [
    Use model violation flow
  ]
)

The diagram above shows the six stages the prover walks through when a
parent forces a USE flag that violates a dependency's REQUIRED\_USE.
Each step is explained below.

#strong[Step 1 --- USE propagation.] The parent atom `cat/app` depends
on `cat/lib[feature_z]`. The bracketed flag is carried forward as a
`build_with_use` context annotation, so every candidate version of `lib`
will be evaluated with `feature_z` enabled.

#strong[Step 2 --- Entry rule verification.] When `lib`'s `:install` (or
`:run`) entry rule fires, it computes the full USE model and calls
`use:verify_required_use_with_bwu` to check whether the resulting flag
set satisfies `lib`'s `REQUIRED_USE` expression.

#strong[Step 3 --- Fail, not assume.] If verification fails (e.g.~`lib`
declares `REQUIRED_USE=!feature_z`), the entry rule caches a structured
violation description via `memo:requse_violation_/3` and then
#strong[fails]. It does #emph[not] produce an assumption, because doing
so would hide the failure from the candidate selection logic and bypass
the entire reprove mechanism.

#strong[Step 4 --- Candidate backtracking.] The failure propagates back
to `grouped_package_dependency`, which tries the next candidate version
of `lib`. A different version may have a different `REQUIRED_USE` that
does not conflict with `feature_z`.

#strong[Step 5a --- Parent narrowing + reprove.] When all candidates are
exhausted, the fallback chain activates. `maybe_learn_parent_narrowing`
learns to exclude the current parent version (`app-1.0`) and throws
`prover_reprove`, giving the prover a chance to retry with a different
parent that may not force `feature_z`.

#strong[Step 5b --- Assumption with violation detail.] After all reprove
retries are exhausted, the prover falls through to the assumption path.
`explanation:assumption_reason_for_grouped_dep` retrieves the cached
`requse_violation_` info and enriches the assumption context with a
`required_use_violation(...)` tag.

#strong[Step 6 --- Warning output.] The printer recognises the enriched
context and emits a structured REQUIRED\_USE violation warning, showing
which flags were forced, what expression they violate, and which parent
triggered the conflict.

=== Memo cache
<memo-cache>
The violation info is cached via `memo:requse_violation_/3`
(thread-local, survives backtracking since `assertz` is side-effecting).
It is: - #strong[Asserted] in the entry rule before failing -
#strong[Consumed] in the `grouped_package_dependency` assumption path
(retracted after enriching the context) - #strong[Cleared] by
`memo:clear_caches/0` at the start of each proof run

== Entry rule structure
<entry-rule-structure>
Every `:install` and `:run` entry rule follows the same layered
structure. Understanding this structure is important because it explains
#emph[when] the prover fails, #emph[when] it assumes, and #emph[why] the
distinction matters.

#strong[Gate checks.] The rule begins with a deterministic cut (`!`) ---
there is exactly one entry-rule clause per literal form, so Prolog must
not search for alternatives at this level. Candidate alternatives are
provided one level up by `grouped_package_dependency`. After the cut,
three quick gate checks run in order:

+ #strong[Mask gate] --- if the ebuild is masked and the `unmask`
  relaxation tier is not active, the rule fails immediately.
+ #strong[Keyword gate] --- if no accepted keyword exists and
  `keyword_acceptance` is not active, the rule fails.
+ #strong[Already-installed short-circuit] --- if the package is already
  installed (and `--emptytree` was not requested) with USE flags that
  match the request, the rule succeeds with an empty condition list.
  When the installed USE differs, the entry is re-emitted as a
  transactional `:update` action instead (portage-ng\#85).

#strong[USE model verification.] When none of the gates apply, the rule
queries the ebuild's metadata and computes the full USE model (combining
profile defaults, user overrides, and `build_with_use` annotations from
the parent). It then checks the result against the ebuild's
`REQUIRED_USE` expression. If the check fails, the violation is cached
(`memo:requse_violation_/3`) and the rule fails --- #emph[not] assumes
--- so that backtracking can explore other candidate versions (see
section 9.8.1).

#strong[Dependency model construction.] If the USE model passes, the
rule builds the dependency model: it looks up cached or freshly computed
dependency lists, orders them, and returns the full condition list
(selected CN, constraints, download literal, dependency literals, etc.).

If the dependency model itself cannot be built --- for example because
every branch of an `any_of_group` is filtered out --- the rule produces
a domain assumption tagged with `issue_with_model`. This is deliberately
an assumption rather than a failure, because the problem is intrinsic to
the ebuild metadata, not something that trying a different candidate
version would resolve.

== Constraint guards and reprove integration
<constraint-guards-and-reprove-integration>
Every time the prover unifies a new constraint term into the proof, it
calls `heuristic:constraint_guard(Key, Constraints)` to verify that the
constraint is consistent with what has already been proved. The guard
has three possible outcomes:

- #strong[Succeed silently] --- the constraint is compatible and the
  proof continues normally.
- #strong[Fail] --- the constraint conflicts with the current proof
  state. Prolog's built-in backtracking explores an alternative within
  the same proof attempt (e.g.~a different candidate version).
- #strong[Throw `prover_reprove(...)`] --- the conflict cannot be
  resolved by simple backtracking. The prover catches the exception,
  records a learned constraint, and restarts the proof from scratch with
  the new knowledge (see section 9.7).

Three specialised guards in `cnselect.pl` cover the most common conflict
types:

- #strong[`selected_cn_unique_or_reprove`] checks that the selected
  category/name pair is consistent with prior selections. If two
  dependency paths select different versions of the same package in the
  same slot, this guard detects the inconsistency and triggers a reprove
  with a narrowed domain.
- #strong[`selected_cn_not_blocked_or_reprove`] enforces blocker
  constraints. When a package is blocked by another package that has
  already been selected, this guard triggers a reprove so the prover can
  learn to avoid the blocked combination.
- #strong[`maybe_request_cn_domain_reprove`] handles remaining domain
  inconsistencies. If the selected version falls outside the
  intersection of all accumulated version domains, the guard learns the
  correct domain and triggers a reprove.

The constraint guards above operate within a single proof attempt. But
what happens when the entire proof cannot succeed under strict
constraints? Rather than immediately falling through to assumptions, the
pipeline offers one more tool: progressive relaxation.

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

The mechanism lives in the pipeline's shared fallback driver
(`pipeline:fallback_tiers/1` + `pipeline:with_fallback/2`), used by both
`prove_plan_with_fallback/5` and `prove_with_fallback/4`. Each tier
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

The tiers are tried in order via Prolog's committed-choice if-then-else
(`->` / `;`) --- the first tier that succeeds commits and returns a
`FallbackUsed` tag (`false`, `keyword_acceptance`, `blockers`, `unmask`,
or `keyword_unmask`).

The same 5-tier fallback chain is shared by two canonical entry points
in the pipeline module:

- `prove_plan_with_fallback/5` --- full pipeline (prove + order), used
  by production paths (`--pretend`, `--graph`, `--build`).
- `prove_with_fallback/4` --- resolve pass only (no ordering pass), used
  by layered tests (`resolver:test`, `orderer:test`) and `--bugs`. Each
  test layer adds its own stages on top.

=== How `assuming/2` works
<how-assuming2-works>
`prover:assuming(Flag, Goal)` stores a dynamic flag
(`prover_assuming_<Flag>`) for the duration of `Goal`, using
`setup_call_cleanup` to guarantee cleanup even on exceptions. Domain
predicates test this flag with the unary `prover:assuming(Flag)`:

- #strong[`candidate:eligible/1`] --- when `keyword_acceptance` is
  active, candidates with any keyword are accepted; when `unmask` is
  active, masked candidates pass.
- #strong[`acceptance:accepted_keyword_candidate/7`] --- two fallback
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
`builder:dispatch_suggestions/3` can apply the suggestions automatically
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

Once the proof is complete --- whether strict or under assumptions ---
the results must be communicated to the user. The assumption printing
pipeline inspects the Proof AVL and translates each assumption into a
classified, actionable message.

== Assumption printing pipeline
<assumption-printing-pipeline>
After the proof is complete, the printer walks the Proof AVL and
collects every entry that represents an assumption. Assumptions fall
into two families, and the printer handles them differently.

#strong[Domain assumptions] are stored under `rule(assumed(X))` keys.
These represent situations where the prover could not find a real rule
and had to accept the literal on faith. When the printer encounters one,
it inspects the literal and its context to classify the assumption and
produce a meaningful message:

- #strong[REQUIRED\_USE violation] --- the context contains a
  `required_use_violation(...)` tag (see section 9.8.1). The printer
  emits a structured block showing which USE flags were forced, which
  `REQUIRED_USE` expression they violate, and which parent caused the
  conflict.
- #strong[Non-existent dependency] --- the literal is a
  `grouped_package_dependency` without context. This means no candidate
  version exists at all (the category/name is not in the repository).
- #strong[Grouped dependency with reason] --- the literal is a
  `grouped_package_dependency` with an `assumption_reason` tag in its
  context. The printer extracts the reason label (e.g.~"all candidates
  masked", "blocker conflict") and shows it alongside the dependency.
- #strong[Model unavailable] --- the context contains
  `issue_with_model`. The dependency model could not be built (e.g.~all
  `any_of_group` branches were filtered). The printer reports this as a
  metadata problem.
- #strong[Generic] --- any domain assumption that does not match the
  above patterns is printed with the raw literal for debugging.

#strong[Cycle-break assumptions] are stored under `assumed(rule(X))`
keys. These mark points where the prover broke a dependency cycle by
assuming a literal that was already being proved. The printer delegates
to `cycle:print_cycle_explanation`, which reconstructs the cycle path
and explains which packages form the loop.

=== Assumption type classification
<assumption-type-classification>
The classification logic lives in `assumption.pl`. Given an assumption
literal and its context, it returns a type tag that the warning printer
uses to select the appropriate output format:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Pattern]], [#strong[Type tag]],),
    table.hline(),
    [Context contains
    `required_use_violation`], [`required_use_violation`],
    [`grouped_package_dependency` (no
    context)], [`non_existent_dependency`],
    [`grouped_package_dependency` (with context)], [Extracted from
    `assumption_reason`],
    [`R://E:install`], [`assumed_installed`],
    [`R://E:run`], [`assumed_running`],
    [Blocker literal], [`blocker_assumption`],
    [Context contains `issue_with_model`], [`issue_with_model`],
  )]
  , kind: table
  )

The combination of learned constraints, constraint guards, and
progressive relaxation is reminiscent of a well-known technique from the
SAT solving world.

== Conflict-driven clause learning connection
<conflict-driven-clause-learning-connection>
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

With the proving and output mechanisms described, the following sections
cover practical aspects: a testing checklist to catch regressions, and a
source file map for navigating the codebase.

== Testing learned constraints
<testing-learned-constraints>
When testing changes to the reprove or assumption mechanism, the
following checklist helps catch regressions quickly:

- #strong[Exit code] --- the process exit code summarises the proof
  outcome:
  - `0` --- no assumptions at all (clean proof)
  - `1` --- only prover cycle-break assumptions
  - `2` --- at least one domain assumption (e.g.~missing dependency)
- #strong["Total: N actions"] --- this line must appear in the output,
  confirming that the proof completed and a plan was produced.
- #strong["non-existent" count] --- count the lines containing
  "non-existent" to check how many domain assumptions were made. An
  unexpected increase signals a regression.
- #strong[No "Unknown message"] --- the output should not contain
  "Unknown message" or unhandled exception traces. These indicate an
  assumption type that the printer does not recognise.
- #strong[Runtime] --- a single-target proof should complete within a
  few seconds. A significant increase compared to previous runs suggests
  excessive reprove retries or a learning bug.
- #strong[Test suite] --- the overlay and portage test suites
  (`resolver:test_stats/1`) should maintain their previous pass rate.
  Any drop indicates that a change has broken handling of a known edge
  case.

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
    [`Source/Domain/Gentoo/Rules/resolving.pl`], [Domain rules: entry
    rules, grouped deps, `rule(assumed(_),[])`],
    [`Source/Domain/Gentoo/Rules/Resolving/candidate.pl`], [Candidate
    selection and eligibility],
    [`Source/Domain/Gentoo/Rules/Resolving/cnselect.pl`], [Constraint
    guards, reprove triggers, parent narrowing, learned domains],
    [`Source/Domain/Gentoo/Rules/Resolving/heuristic.pl`], [Reprove
    state management, reject accumulation],
    [`Source/Domain/Gentoo/Rules/Resolving/memo.pl`], [Thread-local
    caches including `requse_violation_/3`],
    [`Source/Domain/Gentoo/Rules/Resolving/use.pl`], [`verify_required_use_with_bwu`,
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

== Further reading
<further-reading-8>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- the proof search
  algorithm
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  domain operations used by constraint learning
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- entry rules, fallback chains, and REQUIRED\_USE handling
- #link("23-doc-resolver-comparison.md")[Chapter 23: Resolver Comparison]
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
version(NumsNorm, Alpha, SuffixRank, SuffixNum, SuffixTail, Rev, Full)
```

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Field]], [#strong[Example]], [#strong[Meaning]],),
    table.hline(),
    [`NumsNorm`], [`[3,0,77]`], [Normalized numeric components],
    [`Alpha`], [`''` or `'a'`], [Alpha suffix (empty atom if none)],
    [`SuffixRank`], [`4`], [Numeric rank of first version suffix
    (`_alpha`=0, `_beta`=1, `_pre`=2, `_rc`=3, (final)=4, `_p`=5)],
    [`SuffixNum`], [`0`], [First suffix number (e.g.~`3` in `_rc3`)],
    [`SuffixTail`], [`[]` or `[s(5,2),s(4,0)]`], [Remaining suffixes as
    `s(Rank, Num)` pairs, closed by the `s(4,0)` "\(final)" terminator
    (`[]` if the version has no suffix)],
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
`SuffixTail` lists remaining suffixes as `s(Rank, Num)` pairs ending in
the `s(4,0)` "\(final)" terminator, so multi-suffix versions compare
pairwise per PMS (e.g.~`1_rc1_p2 > 1_rc1_pre1` and `1_rc1 > 1_rc1_pre1`)
\- `Rev` is a plain integer

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
#figure(image("Diagrams/10-domain-meet.svg", width: 70.0%, alt: "Domain meet examples"),
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

#strong[Example 1 --- overlapping range.]

#figure(image("Diagrams/10-domain-meet-ex1.svg", width: 35.0%, alt: "Meet example 1"),
  caption: [
    Meet example 1
  ]
)

Lower bound `>=1.0` and upper bound `<2.0` describe the half-open
interval #strong[\[1.0, 2.0)]. The meet is that interval: every version
that satisfies both operators is exactly a version at least 1.0 and
strictly below 2.0.

#strong[Example 2 --- two lower bounds.]

#figure(image("Diagrams/10-domain-meet-ex2.svg", width: 35.0%, alt: "Meet example 2"),
  caption: [
    Meet example 2
  ]
)

`>=1.0` meets `>=1.5`. The stricter requirement wins: the intersection
is #strong[`>=1.5`]. Anything below 1.5 was already ruled out by the
second constraint.

#strong[Example 3 --- disjoint constraints (conflict).]

#figure(image("Diagrams/10-domain-meet-ex3.svg", width: 35.0%, alt: "Meet example 3"),
  caption: [
    Meet example 3
  ]
)

`>=2.0` meets `<1.0`. No version can be simultaneously at least 2.0 and
below 1.0. `domain_meet/3` #strong[fails]: the normalised domain is
empty, and the prover must treat this as an unsatisfiable combined
requirement.

#strong[Example 4 --- tilde vs revision-aware lower bound.]

#figure(image("Diagrams/10-domain-meet-ex4.svg", width: 35.0%, alt: "Meet example 4"),
  caption: [
    Meet example 4
  ]
)

`~1.0` (in PMS terms: same main version as `1.0`, any revision)
restricts candidates to the #strong[1.0] line. Meeting that with
`>=1.0-r2` keeps you on that line but drops revisions below `-r2`: the
effective set is #strong[`>=1.0-r2` within the 1.0.x family], not a
broader branch of the package.

In all cases, when the meet succeeds, candidate selection and
consistency checks use the #strong[narrower] domain; when it fails,
there is no shared non-empty set of versions to choose from.

=== Consistency check
<consistency-check>
```prolog
version_domain:domain_inconsistent(Domain)
```

Detects structurally empty domains --- an empty slot set, conflicting
exact bounds, or a lower bound above an upper bound. The meet operation
rejects a result when this check succeeds
(`\+ domain_inconsistent(...)`); it is purely structural and never
consults the repository.

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
narrowed version information across reprove retries. Each learned
constraint is keyed by a category--name--slot triple:

```prolog
cn_domain(Category, Name, Slot)
```

=== Conflict detection and learning
<conflict-detection-and-learning>
When two dependency edges impose incompatible version requirements on
the same package, the constraint guard detects an empty intersection and
records a narrowed domain for future attempts.

#figure(image("Diagrams/10-learned-domain-conflict.svg", width: 45.0%, alt: "Conflict detection and domain learning"),
  caption: [
    Conflict detection and domain learning
  ]
)

The guard calls `domain_meet/3` on the two incoming domains. When the
result is empty (no version satisfies both), the guard stores the
narrowed domain via `prover:learn/3` and throws `prover_reprove` to
restart the proof with this new knowledge.

=== Applying learned domains on reprove
<applying-learned-domains-on-reprove>
On the next reprove attempt, `grouped_dep_effective_domain` intersects
the learned domain with the local domain coming from the current proof
context, #emph[before] candidate selection begins.

#figure(image("Diagrams/10-learned-domain-apply.svg", width: 50.0%, alt: "Applying learned domain on reprove"),
  caption: [
    Applying learned domain on reprove
  ]
)

If the intersection is #strong[non-empty], candidates are filtered
against the stricter combined domain --- avoiding the same dead-end
choice that caused the previous conflict. If the intersection is
#strong[empty], there is no compatible overlap left: the prover can skip
directly to assumption or failure handling instead of selecting
candidates from an empty domain.

Chapter 9 walks through the reprove and learning mechanics in full;
Chapter 12 ties domains into resolve-time rule evaluation and candidate
generation.

=== Wildcard domain learning
<wildcard-domain-learning>
When a wildcard dependency like `=dev-python/gast-0.6*` cannot be
satisfied, `cnselect:maybe_learn_wildcard_domain/4` derives an
upper-bound domain from the wildcard: the last numeric component is
incremented to produce an exclusive upper bound (e.g.~`0.6*` → `< 0.7`,
`1.2.3*` → `< 1.2.4`). The resulting
`version_domain(any, [bound(smaller, UpperVer)])` is learned via
`prover:learn/3` and triggers a reprove.

This mechanism is guarded: it only fires when the parent has already
been narrowed by a prior `maybe_learn_parent_narrowing` attempt (or when
the parent is a single-version package, making parent narrowing futile).
The guard ensures parent narrowing gets priority for multi-version
parents, correctly handling cross-package wildcard conflicts (e.g.~two
packages requiring different wildcard ranges of the same dependency).

=== Connection to feature logic
<connection-to-feature-logic>
This mechanism is inspired by Zeller's feature logic: version sets are
identified by feature terms and refined by incrementally narrowing the
set until each component resolves to a single version. Each successful
`learn` call tightens the feature, and each
`grouped_dep_effective_domain` call applies the accumulated tightening
--- a direct realisation of monotonic domain narrowing.

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
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- how version domains feed into candidate selection
- #link("23-doc-resolver-comparison.md")[Chapter 23: Resolver Comparison]
  --- Zeller's feature logic and CDCL connections

= Rules and Domain Logic
<rules-and-domain-logic>
== Prover and domain
<prover-and-domain>
The prover (#link("08-doc-prover.md")[Chapter 8]) works with abstract
literals and rules. It does not know what `:install` means for Gentoo
--- it only knows how to find a matching `rule/2` clause and prove its
body. The #strong[rules layer] is the bridge between that abstract proof
search and a concrete domain: ebuilds, USE flags, version constraints,
planning laws, or uninstall claims.

When the prover encounters a literal, it calls into whichever rule
module it was given:

```prolog
prover:prove(Rules, ...)
prover:prove_once(Rules, ...)
```

`Rules` is a module atom --- typically `resolving`, `ordering`, or
`unmerging`. The prover expands `Rules:rule(Head, Body)` and treats
`Body` as the next obligations. It never interprets what the literals
mean; all domain knowledge lives inside the rule clauses and the hooks
they register.

That separation is deliberate. The same proof engine answers three
different questions by loading a different rule module:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Question]], [#strong[Rule
      module]], [#strong[Stage wrapper]],),
    table.hline(),
    [What configuration satisfies the
    request?], [`resolving`], [`resolver:resolve/9`],
    [When can each action run?], [`ordering`], [`orderer:order/5`],
    [In what order may packages be removed?], [`unmerging`], [depclean /
    unmerge pass],
  )]
  , kind: table
  )

Callers outside a proving pass (for example query-side model
construction) fall back to `config:default_rules/1`, which is
`resolving`.

== The `rule/2` contract
<the-rule2-contract>
Every rule module exports the same interface:

```prolog
Module:rule(+Head, -Body)
```

The prover passes a literal as `Head`. The module returns a list of
sub-literals `Body` that must be proved to justify it. Failure means
"this expansion does not apply"\; success commits those obligations to
the proof search. Domain assumptions appear as `rule(assumed(X), [])`
--- an empty body that records a justified gap rather than aborting the
proof.

Because the contract is uniform, Gentoo-specific vocabulary never enters
the prover core. A new concern is almost always a new clause (or a new
rule module), not engine surgery in `prover.pl`.

== Rule modules in the pipeline
<rule-modules-in-the-pipeline>
The pipeline chains two proving passes over one goal set
(#link("04-doc-architecture.md")[Chapter 4],
#link("08-doc-prover.md")[Chapter 8]):

+ #strong[Pass 1 --- configuration.] `resolver:resolve/9` hands
  `resolving` to `prover:prove/10`. Choice lives here: versions, slots,
  USE flags, OR-group arms. The output is a Proof / Model / Constraints
  \/ Triggers quadruple --- a justified configuration.
+ #strong[Pass 2 --- plan.] `orderer:order/5` hands `ordering` to
  `prover:prove_once/…` over generic planning laws plus Gentoo bindings.
  The output is a second proof object; wave projection reads it into a
  parallel plan.

Depclean's uninstall order reuses the same planning laws with
`unmerging` bindings: steps are `:unmerge` actions, requirements are
claim releases, and the installed world provides no escape hatch.

So "rules and domain logic" is not a synonym for dependency resolution.
Resolution is one rule set. Ordering and unmerging are others. The
chapters that follow treat the two constructive passes as peers:

- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- pass 1: the `resolving` rule set and Gentoo policy
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- pass 2: planning laws, Gentoo bindings, wave projection

== What a rule body carries
<what-a-rule-body-carries>
Rule bodies are more than flat dependency lists. They thread
#strong[proof-term context] (`?{…}` lists on literals --- see
#link("05-doc-proof-literals.md")[Chapter 5] and
#link("22-doc-context-terms.md")[Chapter 22]): `build_with_use/1`,
`constraint/1`, `after/1`, slot information, and suggestion tags for
assumptions. Context is how parent requirements and local policy meet
without the prover understanding Gentoo.

Heads themselves encode domain speech acts. For `resolving`, typical
patterns include user `target/2` literals, action literals
(`Repo://Ebuild:install`, `:run`, `:download`), grouped dependency
atoms, REQUIRED\_USE validation literals, and the `assumed/1` catch-all.
For `ordering`, the language shrinks to `scheduled/1`, `available/2`,
and `assumed(unreachable/2)`. The full head tables live in the
pass-specific chapters.

== Domain hooks at the prover boundary
<domain-hooks-at-the-prover-boundary>
Besides `rule/2`, the domain may answer prover callbacks through
`heuristic:*` hooks (implemented for Gentoo under
`Rules/Resolving/heuristic.pl` and consulted during prove):

- #strong[`proof_obligation/4`] --- inject derived obligations after a
  literal succeeds (PDEPEND is handled this way in a single resolve
  pass).
- #strong[`cycle_benign/2`] --- classify a proof-search cycle as benign
  before the prover records a cycle-break assumption.
- #strong[Constraint guards / reprove helpers] --- learn domains or
  request a reprove when selected versions conflict (see
  #link("09-doc-prover-assumptions.md")[Chapter 9]).

Hooks keep cross-cutting behaviour out of the generic search loop while
still letting the domain steer search. Resolution and ordering each rely
on them differently; the mechanism is shared.

== Where the Gentoo resolve rules live
<where-the-gentoo-resolve-rules-live>
The `resolving` module is the public entry point
(`Source/Domain/Gentoo/Rules/resolving.pl`). Its implementation is split
across focused submodules under `Source/Domain/Gentoo/Rules/Resolving/`
--- candidate selection, USE evaluation, ranking, CN selection, target
resolution, and so on. The inventory and the end-to-end resolve
narrative belong in #link("12-doc-resolution.md")[Chapter 12].

The `ordering` and `unmerging` modules sit beside them under
`Source/Domain/Gentoo/Rules/`. They bind the generic planning laws to
Gentoo dependency classes and to VDB facts; see
#link("13-doc-planning.md")[Chapter 13].

== Twin framing: configuration proofs and plan proofs
<twin-framing-configuration-proofs-and-plan-proofs>
A successful run produces two proofs, not one algorithm output with a
post-pass:

- #strong[Configuration as proof] --- every chosen version, USE set, and
  dependency edge is justified by a `resolving` rule expansion (or an
  explicit domain assumption / cycle break).
- #strong[Plan as proof] --- every wave placement is justified by an
  `ordering` (or `unmerging`) expansion: a step is scheduled because its
  requirements are available from earlier steps or from the installed
  world.

Reading the handbook in that order --- rules contract, then resolution,
then ordering --- matches how the pipeline itself thinks.

== Further reading
<further-reading-10>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- proof search,
  models, triggers, pipeline entry points
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- domain assumptions, cycle breaks, progressive relaxation
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  version constraint representation used by resolve
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- the `resolving` rule set in depth
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- planning laws and wave projection

= Resolution: Configuration as Proofs
<resolution-configuration-as-proofs>
== Configuration as a first proving pass
<configuration-as-a-first-proving-pass>
The prover (#link("08-doc-prover.md")[Chapter 8]) answers a question
about the #strong[final world]: which packages, which versions, which
USE flags? Pass 1 gives that #emph[what] the same status that pass 2
gives the #emph[when] (#link("13-doc-planning.md")[Chapter 13]):
#strong[the configuration is a proof].

`resolver:resolve/9` hands the `resolving` rule set to
`prover:prove/10`. Every chosen candidate, every USE-conditional branch
taken or skipped, every OR-group arm, and every domain assumption is
justified by a `resolving:rule/2` expansion (or by an explicit prover
cycle break). There is no separate "resolver algorithm" whose output
must later be trusted --- the Proof / Model / Constraints / Triggers
quadruples #emph[are] the justified configuration.

The rules contract and the multi-module picture are in
#link("11-doc-rules.md")[Chapter 11]. This chapter is the Gentoo resolve
pass in depth: how a user target becomes an installed graph, how
candidates and USE are chosen, and what happens when the rules layer
must propose a configuration change.

== How dependency resolution works (end-to-end)
<how-dependency-resolution-works-end-to-end>
A typical run starts with a user query like `sys-apps/portage`. The
rules layer turns this into a `target/2` literal and resolves it to the
best eligible candidate --- the newest version that is not masked, has
an accepted keyword, and satisfies any slot constraints. This resolution
produces sub-literals that drive the rest of the proof.

The resolution then branches depending on the action:

- #strong[`:run`] resolves runtime dependencies (RDEPEND). PDEPEND is
  handled in the same pass through the prover's proof-obligation hook
  (see #link(<hooks>)[Hooks]).
- #strong[`:install`] resolves build-time dependencies (DEPEND and
  BDEPEND) and attaches ordering constraints (`after/1`) that express
  which packages must be installed before others.

Each dependency atom from the metadata becomes a
`grouped_package_dependency` literal. The candidate selection machinery
then applies version ranges, slot operators, keyword and mask policy,
and any learned constraints from prior reprove attempts (see
#link("09-doc-prover-assumptions.md")[Chapter 9] and
#link("10-doc-version-domains.md")[Chapter 10]).

USE-conditional dependencies are included only when the condition holds
in the effective USE set for that ebuild and path. For example,
`ssl? ( dev-libs/openssl )` adds `dev-libs/openssl` to the body only if
`ssl` is enabled; otherwise the branch is skipped entirely. When a
parent requires particular flags on a child, those requirements
propagate via `build_with_use` in the proof-term context (see
#link(<use-flags-in-depth>)[USE flags in depth]).

The prover walks this structure depth-first: each successful rule
expansion adds literals to the proof and updates the model. When a rule
fails, Prolog backtracks to try an alternative candidate or, ultimately,
records an assumption.

== The `resolving:rule/2` head patterns
<the-resolvingrule2-head-patterns>
The resolve pass uses the shared `rule/2` contract
(#link("11-doc-rules.md")[Chapter 11]) with Gentoo heads:

```prolog
resolving:rule(+Head, -Body)
```

Target rules translate a user query into a concrete ebuild. Action rules
(`:install`, `:run`, `:download`) expand an ebuild into its dependency
obligations. Dependency rules resolve individual atoms to candidates.
Validation rules enforce REQUIRED\_USE constraints. The catch-all
`assumed(X)` clause handles domain assumptions when no real rule
applies.

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
    [`assumed(X)`], [Catch-all for domain assumptions],
  )]
  , kind: table
  )

== Candidate resolution
<candidate-resolution>
When the rules layer encounters a dependency, it must choose a concrete
version of the target package. This process has three stages:
eligibility filtering, version-ordered selection, and a fallback chain
for when no candidate works.

=== Eligibility filtering
<eligibility-filtering>
Before a candidate version is considered, `candidate:eligible/1` checks
two things:

- #strong[Masking] --- is the ebuild masked by the profile or user
  configuration?
- #strong[Keyword acceptance] --- does the ebuild have an accepted
  keyword for the current architecture?

\(Installed status is a separate check, `candidate:installed/1`, used by
the entry rules' already-installed short-circuit.)

If a candidate fails these checks and no relaxation tier is active (see
#link("09-doc-prover-assumptions.md#progressive-relaxation")[Chapter 9, Progressive Relaxation]),
the entry rule fails and Prolog backtracks to try the next candidate.

=== Version-ordered selection
<version-ordered-selection>
`target:resolve_candidate/2` resolves a query to a specific
`Repository://Ebuild` pair. Candidates are tried newest-first via
`cache:ordered_entry/5`, so the prover naturally prefers the latest
eligible version.

=== Dependency ordering within a group
<dependency-ordering-within-a-group>
Before proving the dependencies of a package, `ranking:dep_priority/2`
sorts them so that tightly constrained siblings are proved first. This
reduces greedy conflicts where an unconstrained sibling selects a
version that later clashes with a tighter constraint:

#figure(
  align(center)[#table(
    columns: 3,
    align: (left,left,left,),
    table.header([#strong[BaseK]], [#strong[Constraint
      type]], [#strong[Example]],),
    table.hline(),
    [1], [Tight upper bound (range)], [`>=1.0 <2.0`],
    [4], [Tilde constraint], [`~dev-ruby/railties-8.1.1`],
    [8], [Wildcard constraint], [`=dev-python/gast-0.6*`],
    [999], [Unconstrained], [`dev-libs/openssl`],
  )]
  , kind: table
  )

Lower keys are proved first. Slot specificity is folded into the base
key via `min` --- a fully slot-qualified dependency (slot + subslot)
gets key 0 and outranks every tier above. The effect is that slotted,
tilde and wildcard dependencies lock their `selected_cn` before
unconstrained siblings pick a potentially conflicting version.

=== Self-dependencies and cross-slot handling
<self-dependencies-and-cross-slot-handling>
When a package lists itself as a build dependency (e.g.~`antlr-tool:4`
needing `antlr-tool:3.5` to bootstrap), the rules layer distinguishes
#strong[same-slot self-deps] from #strong[cross-slot self-deps].

Same-slot self-deps (same category, name, and slot as the parent) are
treated as bootstrap dependencies: if the package is already installed,
the dependency is satisfied; otherwise the rule fails so that
backtracking can reach a bootstrap alternative.

Cross-slot self-deps (same category and name but a #emph[different]
slot) are treated as #strong[regular dependencies] and resolved
normally. This prevents model build failures when the cross-slot version
is not yet installed.

=== Fallback chain
<fallback-chain>
When every candidate for a grouped dependency has been tried and none
succeeded, the rules layer activates a fallback chain before giving up:

- #strong[Wildcard domain learning] --- `maybe_learn_wildcard_domain`
  fires when a wildcard dependency (e.g.~`=dev-python/gast-0.6*`) fails
  resolution and the parent has already been narrowed by a prior
  parent-narrowing attempt, or the parent is a single-version package
  (where parent narrowing would be futile). It derives an upper-bound
  `cn_domain` from the wildcard constraint (e.g.~`< 0.7`) and learns it
  via `prover:learn/3`, then throws `prover_reprove`.
- #strong[Parent narrowing] --- `maybe_learn_parent_narrowing` records
  that the current parent version led to a dead end and throws
  `prover_reprove`, so the prover can retry with a different parent.
- #strong[Domain reprove] --- `maybe_request_grouped_dep_reprove` checks
  whether domain or constraint conflicts exist and, if so, triggers a
  reprove with learned constraints.
- #strong[Domain assumption] --- as a last resort, the rules layer emits
  `assumed(grouped_package_dependency(...))`. This records the failure
  as a domain assumption so the proof can still complete.

== Cycles and how portage-ng handles them
<cycles-and-how-portage-ng-handles-them>
Circular dependencies are a fact of life in the Portage tree. A language
runtime may be packaged with tooling that itself depends on that
runtime, creating a loop. The prover detects these cycles during its
depth-first proof search: it keeps track of which literals are currently
being proved, and if the same literal appears again while it is still on
the stack, a cycle has been found.

Before breaking a cycle with an assumption, the prover asks the domain
whether the cycle is #strong[benign]. The hook
`heuristic:cycle_benign/2` inspects the repeating literal and the cycle
path. If the hook succeeds, the literal is treated as already justified
and added to the model without a cycle-break assumption. If the hook
fails, the prover records a cycle-break assumption (`assumed(rule(Lit))`
in the proof, `assumed(Lit)` in the model). This is separate from domain
assumptions introduced by `rule(assumed(X), [])`.

The benign classification is conservative and pattern-based. For
example, cycles that pass through `:run` (RDEPEND paths) are often
treated as ordering-style cycles rather than hard failures --- mirroring
how traditional resolvers tolerate certain cyclic patterns.

After the proof is complete, the ordering pass
(#link("13-doc-planning.md")[Chapter 13]) resolves cyclic portions of
the graph by citing the installed world (VDB) where possible, so that
the merge ordering respects the cycle structure. For more on proof
search and assumptions, see #link("08-doc-prover.md")[Chapter 8] and
#link("09-doc-prover-assumptions.md")[Chapter 9].

== USE flags in depth
<use-flags-in-depth>
USE flags play a central role in dependency resolution. They determine
which dependency branches exist, which packages are eligible, and
whether REQUIRED\_USE constraints are satisfied.

=== Effective USE and conditionals
<effective-use-and-conditionals>
For each ebuild the rules layer computes an #strong[effective USE set]
--- the final set of flags that are active for this particular proof
path. USE-conditional dependencies like `ssl? ( dev-libs/openssl )` are
evaluated against this set: if the flag is active, the dependency is
included; otherwise it is skipped.

The key predicate is `use:effective_use_for_entry/3` (with the context
wrapper `use:effective_use_in_context/3`), which computes the full
effective USE set for an ebuild. Whether a USE-conditional group is
active is decided by the `candidate:eligible(use_conditional(...))`
clauses together with the `use_conditional_group` rules in
`resolving.pl`.

=== `build_with_use`
<build_with_use>
When a parent dependency requires specific USE flags on a child (e.g.
`dev-libs/openssl[threads]`), those requirements travel through the
proof as `build_with_use` context annotations. They influence how the
child's effective USE set is computed, ensuring that parent requirements
are not silently ignored.

=== `REQUIRED_USE`
<required_use>
Gentoo's REQUIRED\_USE expressions (e.g.~`^^ ( gtk qt5 )` meaning
"exactly one of gtk or qt5") are enforced through dedicated validation
literals. If the active USE set violates a REQUIRED\_USE expression, the
rule fails and the prover backtracks to try another candidate or records
an assumption (see
#link("09-doc-prover-assumptions.md#use-model-violation-flow")[Chapter 9, section 9.8]).

=== Priority order
<priority-order>
USE flags are resolved in priority order, highest priority first:

+ #strong[`build_with_use`] from the parent's dependency context
+ #strong[User configuration] (`/etc/portage/package.use`)
+ #strong[Profile defaults]
+ #strong[Ebuild IUSE defaults]

The most important consequence is that context wins over profile
defaults: a `build_with_use` requirement from the parent can force or
forbid a flag regardless of what the profile would normally choose. This
is why two proofs for the same package can produce different USE sets
--- they arrive through different dependency paths with different
context annotations.

=== Conflicts and backtracking
<conflicts-and-backtracking>
When USE-derived constraints conflict --- for example, REQUIRED\_USE
fails, a conditional branch does not apply as expected, or an
eligibility check fails --- the relevant rule fails. The prover then
backtracks: it tries another candidate version, another slot, or another
branch of the search tree. If no alternative succeeds, the candidate
layer records a domain assumption, often tagged with a suggestion for
which `package.use` change would resolve the conflict (see
#link(<assumptions-as-proposals>)[Assumptions as proposals]).

== Choice groups
<choice-groups-1>
Gentoo's PMS defines three choice-group operators that constrain how
many members of a set may be active at the same time. The rules layer
maps each operator to a dedicated validation literal that the prover
must satisfy as part of the proof:

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

If the validation literal fails (e.g.~two members of an `exactly_one_of`
group are both active), the prover backtracks to try a different USE
configuration or candidate version.

When a disjunctive dependency group (`||`, `^^`, `exactly_one_of`) must
#emph[select] an alternative, the candidate layer ranks the members with
`ranking:prioritize_deps_keep_all/3` and commits to the first arm that
passes config checks (see
#link(<any-of-arm-selection>)[Any-of (`||`) arm selection] below).
Profile-forced and installed preferences still dominate via
`is_preferred_dep/2` inside the `Rank` key; USE\_EXPAND target digits
(`ranking:use_expand_target_rank/2`) contribute to `Rank` / `UEScore`
--- `llvm_slot_20` → `20`, `python_single_target_python3_13` → `[3,13]`,
and so on.

== Any-of (`||`) arm selection
<any-of-arm-selection>
Gentoo ebuilds often write `|| ( arm1 arm2 … )`. The PMS only requires
that #emph[at least one] arm is satisfiable; it does not say which arm
to pick. Wrong order locks the prover onto a suboptimal (or
incompatible) branch --- for example cabal's
`|| ( ( >=text-1.2.3 <text-1.3 ) ( >=text-2 <text-2.2 ) )` must prefer
the text-2.x arm when that is the newest tree candidate
(portage-ng\#112).

=== Portage vs portage-ng entry points
<portage-vs-portage-ng-entry-points>
#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([], [#strong[Portage]], [#strong[portage-ng]],),
    table.hline(),
    [Mechanism], [`dep_zapdeps` ordered `choice_bins` + intra-bin
    upgrade promotion
    (`lib/portage/dep/dep_check.py`)], [`candidate:resolve(choice_group…)`
    → `ranking:prioritize_deps_keep_all/3` then first
    `any_of_config_dep_ok`],
    [Structure], [Nine preference bins (lists)], [One multi-key
    `keysort` (negated ints + original index)],
    [Graph reuse], [Digraph `all_in_graph`], [`selected_cn` snapshot
    (`SnapAll`)],
  )]
  , kind: table
  )

Ranking #emph[is] the preference policy: after the cut commits, later
arms are not tried unless the proof backtracks for another reason.

=== Preference keys (highest first)
<preference-keys-highest-first>
Implemented in `ranking:dep_choice_scores/3` and assembled in
`prioritize_deps_keep_all/3`. Higher scores win; the original ebuild
index `I` breaks remaining ties (left-to-right).

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Key]], [#strong[Intent]], [#strong[Emerge
      analogue]],),
    table.hline(),
    [`LicOk`], [Prefer license-acceptable arms], [Availability / license
    gate],
    [`UseSat`], [Prefer arms needing no USE flip on the arm's best
    candidate], [`preferred_*` vs `unsat_use_*`],
    [`UseUnmasked`], [Among USE-unsat arms, prefer flips that do not
    fight use.mask / use.force], [`all_use_unmasked` (masked →
    `other`)],
    [`Rank`], [Installed / preferred / `--favour` / `--avoid` /
    self-CN], [`preferred_installed` + favour],
    [`SnapAll`], [Prefer arms whose non-`virtual/` CNs are already in
    the proof snapshot], [`all_in_graph`],
    [`SlotScore`], [Prefer higher explicit package slot
    (`pkg:N`)], [`want_update` / higher-slot promotion],
    [`NoDowngrade`], [Demote arms whose newest admitted version is below
    installed or snap-selected], [`downgrade_probe` → `other`],
    [`InstScore`], [Prefer arms that reuse more installed
    CNs], [`other_installed` / `_some` / `_any_slot`],
    [`Overlap`], [Prefer arms that appear in several sibling `\|\|`
    groups], [Soft stand-in for minimize-slots pressure],
    [`VerScore`], [Prefer the arm that admits the newest tree version
    --- only active when #emph[all] arms target the same
    (C,N)], [Intra-bin `has_upgrade and not has_downgrade`],
    [`UEScore`], [Prefer USE\_EXPAND profile alignment], [Profile target
    preference],
    [index `I`], [Stable left-to-right when all else equal], [Ebuild
    order fallback],
  )]
  , kind: table
  )

Worked examples:

- `|| ( foo[a] foo[b] )` with `a` already effective → `UseSat` picks
  `foo[a]`.
- Cabal text ranges (above) → `VerScore` picks the text-2.x arm.
- `|| ( sys-devel/llvm:18 sys-devel/llvm:20 )` → `SlotScore` prefers
  `:20`.
- An arm whose packages are already in `selected_cn` beats a fresh CN →
  `SnapAll`.

`VerScore` is gated to same-CN groups because comparing newest tree
versions of #emph[different] packages is meaningless and overrides
ebuild order: `virtual/mta` would pick `notqmail` (a `-9999` live ebuild
inflates its score) over the intended `nullmailer`, and `virtual/jdk`
would pick source `dev-java/openjdk` over `openjdk-bin`
(portage-ng\#115, portage-ng\#116). Emerge never version-ranks across
CPs inside a choice; it falls back to ebuild order there.

`virtual/` atoms are skipped for `SnapAll`, `InstScore`, and
`NoDowngrade` (Portage's zero-cost treatment of virtuals in those
checks). Scores are computed once per arm per
`prioritize_deps_keep_all/3` call, with a short-lived per-call cache for
installed / reference-version lookups. Ranking must not walk the
ProofAVL; it only sees the proof-context list and memo snapshots (see
also #link("26-doc-performance.md")[Chapter 26]).

=== What we deliberately do not implement
<what-we-deliberately-do-not-implement>
These Portage mechanisms are #strong[design omissions], not open bugs.
The inductive prover and ordering pass already provide the effects they
target.

#strong[Overlapping-`||` DNF (`_overlap_dnf`) and `minimize_slots` /
`new_slot_count`.] Portage merges overlapping `||` groups that share a
CP into DNF, then sorts bins by ascending new-slot count. portage-ng
does not rewrite the dep tree into DNF: expansion is exponential in
overlapping width and does not belong on the per-`choice_group` hot
path. The prover already commits `selected_cn` / learned `cn_domain`
across the proof; later `||` sites reuse those choices via `SnapAll` and
constraint guards --- the same "prefer packages already chosen" effect
without a cross-product. `Overlap`, `InstScore`, and `SnapAll` cover the
common "don't pull a second redundant package" pressure. Remaining edge
cases (two overlapping `||`s neither yet selected) are rare relative to
cost; if tinderbox surfaces one, prefer a targeted heuristic over full
DNF.

#strong[Virtual expand (`_expand_new_virtuals`).] Portage expands
new-style virtuals into a newest-first `||` of providers before zapdeps.
portage-ng already resolves virtuals through the virtual-provider path
and `candidates_prefer_proven_providers/5`, and skips `virtual/` in the
scores above. A second expand-into-`||` pass would duplicate that work
and fight proven-provider reuse.

#strong[Circular-dep demotion inside `||`.] Portage demotes arms that
close a known cycle with the parent (or `--onlydeps` parent CP) into
`other`. portage-ng handles cycles in the prover and the ordering pass
(cycle-break assumptions, world citations, `unreachable` assumptions)
--- see #link("08-doc-prover.md")[Chapter 8],
#link("09-doc-prover-assumptions.md")[Chapter 9], and
#link("13-doc-planning.md")[Chapter 13]. Demoting at ranking time would
second-guess cycle-break polarity and needs a parent circular map that
the proof-context list does not carry.

#strong[Intra-choice `cp_map` slot consistency (Portage bug 600346).]
Portage keeps a per-choice CP→slot map so several atoms in one choice
stay slot-consistent. portage-ng arms are usually a single atom or a
same-CN `all_of_group` of version bounds; cross-CP multi-atom arms that
need `cp_map` are uncommon. Slot consistency is enforced later by
`selected_cn`, slot constraints, and constraint guards.

=== Validation
<validation>
- PLUnit: `ranking_any_of_version_branch`,
  `ranking_any_of_preference_keys` in `Source/Test/unittest.pl`.
- Overlay suite (`||` / USE / slot cases) and tinderbox-ng compare on
  USE-dep `||` and llvm/gcc/python slot packages.

== Slot operators
<slot-operators>
Dependency atoms can carry a slot operator that tells the rules layer
how to handle multi-slot packages. A package like `dev-lang/python` may
offer several slots (e.g.~`3.11`, `3.12`), and the slot operator
determines which slots are acceptable and whether a sub-slot change
should trigger a rebuild of the dependent package.

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Operator]], [#strong[Meaning]], [#strong[Context
      effect]],),
    table.hline(),
    [`:SLOT`], [Depend on a specific slot], [Filters candidates to that
    slot],
    [`:*`], [Any slot is acceptable], [No slot constraint applied],
    [`:=`], [Sub-slot rebuild trigger], [Records the selected sub-slot;
    a change triggers rebuild],
    [`:SLOT=`], [Specific slot + rebuild], [Combines slot filter with
    rebuild tracking],
  )]
  , kind: table
  )

== Blockers
<blockers>
A blocker dependency says that two packages cannot coexist. Gentoo
distinguishes two strengths:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Type]], [#strong[Syntax]], [#strong[Behaviour]],),
    table.hline(),
    [Weak blocker], [`!cat/pkg`], [The blocked package should not be
    present; resolved at plan time],
    [Strong blocker], [`!!cat/pkg`], [The blocked package must not be
    present; the constraint guard fires immediately],
  )]
  , kind: table
  )

Internally, blockers produce `blocked_cn` constraint terms. These are
checked against `selected_cn` constraints by
`selected_cn_not_blocked_or_reprove`: if the blocked package has already
been selected elsewhere in the proof, the guard triggers a reprove so
the prover can learn to avoid the conflicting combination (see
#link("09-doc-prover-assumptions.md#constraint-guards-and-reprove-integration")[Chapter 9, section 9.10]).

== Hooks
<hooks>
PDEPEND (post-dependencies) represent packages that should be present at
runtime but are not required at build time. Unlike DEPEND and RDEPEND,
they do not block the build --- they are installed afterwards.

In portage-ng, PDEPEND is handled in a single pass inside the prover via
the `heuristic:proof_obligation/4` hook. Whenever a literal is
successfully proved, the hook checks whether the corresponding ebuild
has PDEPEND entries. If it does, those entries are injected as
additional proof obligations on the spot. This avoids a separate PDEPEND
resolution pass and ensures that post-dependencies are part of the same
proof and plan.

== Assumptions as proposals
<assumptions-as-proposals>
When strict resolution cannot satisfy every dependency, the rules layer
records a #strong[domain assumption] rather than giving up. From a user
perspective, an assumption is not a dead end --- it is a
#strong[proposal] for a configuration change.

The literal's proof-term context is annotated with #strong[suggestion]
tags that spell out exactly what to change. Common suggestions include:

- `suggestion(unmask, ...)` --- unmask a package
- `suggestion(accept_keyword, ...)` --- accept an unstable keyword
- `suggestion(use_change, ..., Changes)` --- adjust USE flags

The printer collects these tags and shows them next to the assumption,
so you can see which `/etc/portage` file to edit and what to put in it.
The plan is still constructed as if the change had already been applied:
the merge list is coherent under the stated proposal, and the output
tells you which configuration changes would make it real.

For the full story on assumptions and constraint learning, see
#link("09-doc-prover-assumptions.md")[Chapter 9].

== Rules submodules
<rules-submodules>
The `resolving` entry point is not a single monolithic file. It is split
across focused submodules under `Source/Domain/Gentoo/Rules/Resolving/`,
each handling a distinct concern:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Module]], [#strong[File]], [#strong[Purpose]],),
    table.hline(),
    [`acceptance`], [`acceptance.pl`], [Keyword, mask, and license
    acceptance; keyword-aware candidate enumeration],
    [`candidate`], [`candidate.pl`], [Grouped-dep resolution pipeline,
    blocker matching, eligibility protocol],
    [`cnselect`], [`cnselect.pl`], [CN-consistency: selected\_cn reuse,
    CN-domain reject map, learned-domain narrowing],
    [`dependency`], [`dependency.pl`], [Self-entry injection,
    USE-requirement collection, slot/BWU proof-context propagation],
    [`featureterm`], [`featureterm.pl`], [Proof-context list helpers
    (`after/1`, strip `build_with_use`, etc.)],
    [`heuristic`], [`heuristic.pl`], [Prover hooks: constraint guard,
    cycle classification, PDEPEND obligations, reprove state],
    [`memo`], [`memo.pl`], [Thread-local caching declarations,
    `clear_caches/0`],
    [`ranking`], [`ranking.pl`], [Dependency ordering
    (`dep_priority/2`), choice-group ranking, BWU memo seeding],
    [`slotmeta`], [`slotmeta.pl`], [Slot canonicalization, restriction
    merging, constraint queries],
    [`target`], [`target.pl`], [Target resolution, update/downgrade
    transactions, depclean, `--exclude` helpers],
    [`use`], [`use.pl`], [USE evaluation, conditionals,
    `build_with_use`, newuse, REQUIRED\_USE, BWU conflicts],
  )]
  , kind: table
  )

== Policy cards (declarative view)
<policy-cards-declarative-view>
This chapter walks #strong[how] resolution proceeds. For a
newbie-oriented view of #strong[what] Gentoo policy requires --- PMS
meaning, literals, owning modules, and short invariants --- start here:

- #link("Policy/README.md")[Policy cards hub]
- #link("Policy/examples.md")[Policy by example] --- curated overlay
  curriculum
- #link("Policy/map.md")[One-page map] --- `rule/2` head → schema → test
  → card

Prefer those cards when onboarding or reviewing a rules change; keep
this chapter for the end-to-end narrative and `||` ranking detail.

== Further reading
<further-reading-11>
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- the
  `rule/2` contract and how rule modules plug into the prover
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the prover
  calls `rule/2` and builds the proof
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions] --- the
  fallback chain, reprove mechanism, and progressive relaxation
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  how version constraints feed into candidate selection
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- pass 2
- #link("Policy/README.md")[Policy cards] --- declarative Gentoo policy
  surface

= Ordering: Plans as Proofs
<ordering-plans-as-proofs>
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
of a linear schedule. Parallelism falls out of the ordering proofs
themselves: two actions may share a wave exactly when neither one's
availability proof depends on the other.

On a multi-core machine with fast I/O, overlapping work this way can
dramatically reduce wall-clock time compared to a strictly sequential
narrative.

Planning is also at the #strong[action] level, not the package level.
The same logical package may appear as separate literals for download,
install, run, and so on. Those actions can therefore land in different
waves: one package can still be downloading while another is already
installing, whenever the dependency graph allows it.

== From proof to plan: a second proving pass
<from-proof-to-plan-a-second-proving-pass>
The prover (Chapter 8) answers a question about the #strong[final
world]: does a consistent solution exist --- which packages, which
versions, which USE flags? Its output is a proof, and every fact in that
proof carries a justification.

But a proof is not a plan. To execute anything, the actions must be
ordered in time. Earlier versions of portage-ng produced that ordering
with procedural graph algorithms (Kahn's topological sort for the
acyclic portion, Kosaraju SCC decomposition for cycles). The machinery
worked, but its answers came with no justification: a package landed in
wave 7 because "the algorithm said so", and diagnosing a mis-ordered
plan meant archaeology across several procedural passes.

The ordering engine (`Source/Pipeline/orderer.pl`) gives the #emph[when]
the same treatment as the #emph[what]: #strong[it runs the same prover
core a second time].

- #strong[Pass 1] proves a solution exists. It is the existing prover
  with the existing domain rules, completely unchanged. All
  #emph[choice] lives here --- versions, USE flags, OR-group selection.
- #strong[Pass 2] constructs an ordering of that solution. The prover
  core is re-entered over a small set of generic #strong[planning laws],
  with the pass-1 proof and the installed system (VDB) as its facts. Its
  output is a second proof object in which every placement is justified.

The pass-2 proof reads the way a Linux From Scratch book reads:
#emph[fontconfig can be built at step 8 because python-3.14.6 is already
installed; the new python is built at step 12]. A plan is no longer
certified by empirical testing of an algorithm's output --- the plan
#strong[is] a proof.

== The planning laws
<the-planning-laws>
Pass 2 needs only a handful of generic laws. They are the `rule/2`
clauses of the `ordering` module (`ordering.pl`, alongside the Gentoo
bindings) and own no Gentoo vocabulary at all:

```prolog
% A step can be placed once everything it requires is available:
rule(scheduled(H), Conds) :-
  ordering:step(H),
  findall(available(H, D), ordering:requires(H, D), Conds).

% A requirement is available when an earlier plan step provides it, or —
% failing that — when the world as it stands already provides it, or —
% failing that too — by recording the bootstrap failure as a negative
% domain assumption instead of failing the pass:
rule(available(H, D), Body) :-
  (   ordering:step(D),
      \+ prover:currently_proving(scheduled(D))
  ->  Body = [scheduled(D)]
  ;   ordering:world(H, D)
  ->  Body = []
  ;   Body = [assumed(unreachable(H, D))]
  ).

rule(assumed(unreachable(_, _)), []).
```

Three literals make up the entire pass-2 language:

- #strong[`scheduled(H)`] --- step #emph[H] can be placed; its proof is
  the placement justification.
- #strong[`available(H, D)`] --- hard requirement #emph[D] of step
  #emph[H] is satisfiable in time: by an earlier plan step, or by the
  installed world.
- #strong[`assumed(unreachable(H, D))`] --- a #strong[negative domain
  assumption]: no plan step and no installed package can provide
  #emph[D] for #emph[H]. This is the genuine bootstrap boundary,
  reported honestly instead of papered over.

The consumer #emph[H] appears in the availability literal on purpose:
whether a requirement can be bridged by the installed world depends on
the consumer's position in the derivation (cycle membership), so
availability proofs are never shared across consumers. `scheduled/1`
proofs are position-independent and memoize globally through the
prover's proven fast path --- each step is scheduled once, no matter how
many consumers cite it.

== The Gentoo bindings
<the-gentoo-bindings>
The laws ask three questions they cannot answer themselves: what is a
step, what does a step require, and what does the world already provide.
One domain file --- `Source/Domain/Gentoo/Rules/ordering.pl` --- answers
them by reading the pass-1 proof and the VDB:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([Binding], [Question answered], [Source],),
    table.hline(),
    [`step/1`], [What are the plan's steps?], [Pass-1 proof rule heads],
    [`requires/2`], [What must exist before a step?], [Build-time deps
    (DEPEND/BDEPEND) in the step's pass-1 rule body],
    [`prefers/2`], [What would we like earlier, without
    insisting?], [Runtime deps (RDEPEND), PDEPEND completion, ordering
    hints],
    [`world/2`], [What does the system already provide?], [VDB
    (installed packages)],
  )]
  , kind: table
  )

This is the same split that keeps Gentoo semantics out of the prover
core: the laws are the engine, the bindings are microcode loaded from
disk. An ordering quirk in the tree becomes a rule edit in
`ordering.pl`, never engine surgery in `orderer.pl`.

The orderer hands the `ordering` rule module directly to the generic
prover (`prover:prove_once(ordering, ...)`), so the prover core itself
needs no knowledge of which pass it is running --- it just expands
whatever rule set it was given.

== Dependency types and ordering strength
<dependency-types-and-ordering-strength>
Gentoo's dependency classes do not all impose the same ordering
strength. The bindings translate each class into either a hard
requirement or a soft preference:

- #strong[DEPEND] and #strong[BDEPEND] --- build-time dependencies. They
  must be satisfied before the build can start, so they become
  #strong[`requires/2`] edges: the consumer's `scheduled/1` proof waits
  on them.

- #strong[RDEPEND] --- runtime dependencies. They must be satisfied
  before the package is #emph[used], not before it is built. They become
  #strong[`prefers/2`] edges: honored whenever that closes no cycle,
  never allowed to force a world bridge or an unreachable assumption.

- #strong[PDEPEND] --- post-install dependencies. They are resolved
  inside the pass-1 proof (via `heuristic:proof_obligation/4`, see
  Chapter 8) and create no proof edge. The bindings add a
  #strong[completion preference]: a consumer of a PDEPEND provider
  prefers to wait for the provider's post-install group, matching
  emerge's behaviour (portage-ng\#18). The preference is dropped for
  consumers inside the provider's own PDEPEND cycle (portage-ng\#19).

- #strong[IDEPEND] --- install-time dependencies (EAPI 8+). They
  constrain ordering around the install phase and flow through the same
  context machinery as DEPEND.

For the exact mapping from PMS ordering semantics to internal edges, see
#link("24-doc-dependency-ordering.md")[Chapter 24: Dependency Ordering].

== Cycles: citing the installed world
<cycles-citing-the-installed-world>
Dependency cycles are where the rule-based engine differs most visibly
from its predecessor. Consider the classic loop: python depends on tk at
build time when built with `tk` support, tk depends on fontconfig, and
fontconfig needs python to build.

#figure(image("Diagrams/12-ordering-cycle.svg", alt: "Ordering a cycle through the installed world"),
  caption: [
    Ordering a cycle through the installed world
  ]
)

When pass 2 proves `scheduled(fontconfig:install)` and reaches the
requirement on python, the first clause of the availability law --- "an
earlier plan step provides it" --- is refused: the guard
`\+ prover:currently_proving(scheduled(D))` detects that python's own
scheduling proof is still open on the derivation stack, i.e.~citing it
would close a loop. The law falls through to the next question: does the
#emph[world as it stands] provide python?

- #strong[If an older python is installed], `world/2` answers yes, and
  the proof records a #strong[citation of the VDB entry]:
  #emph[fontconfig is buildable now because python-3.14.6 is already
  installed]. This is exactly how Linux From Scratch reasons about its
  temporary toolchain --- a fact about the present system, not a
  heuristic about graphs.

- #strong[If nothing bridges the loop] (a bare system bootstrapping from
  nothing), the plan reports an honest `unreachable` assumption --- the
  genuine bootstrap boundary --- instead of an arbitrary cut.

Note what disappeared: there is no SCC decomposition, no merge-set
post-pass, no progressive edge relaxation. A cycle is not a special case
to be repaired after the fact; it is simply the situation in which the
first clause of a law fails and the next one is consulted.

The pass-1 prover still records its own #strong[cycle-break assumptions]
(Chapter 9) --- those concern the existence proof. Pass-2 world
citations and `unreachable` assumptions concern the #emph[ordering] and
appear in the plan's assumption report separately.

== Preferences: honored exactly when safe
<preferences-honored-exactly-when-safe>
A preference is not a promise. Runtime-ish edges are collected
separately from hard requirements and are folded into the plan
#strong[after] the hard structure is fixed: each preference is accepted
exactly when it closes no cycle against the hard edges and the
previously accepted preferences. A preference that would deadlock the
plan is dropped silently --- matching how Portage treats runtime cycles
as freely orderable.

The bindings currently derive preferences from five sources:

+ #strong[RDEPEND groups] --- a package prefers its runtime providers
  earlier.
+ #strong[`order_after` hints] --- ordering-only constraints recorded in
  proof context by the rules layer (see Chapter 5).
+ #strong[PDEPEND completion] (portage-ng\#18/\#19) --- consumers of a
  PDEPEND provider prefer the provider's post-install group first.
+ #strong[Configure closure] (portage-ng\#21) --- an `:install` action
  prefers the runtime providers of its `:run` sibling, so packages whose
  configure phase probes runtime tools are ordered correctly.
+ #strong[Assumed-dep aliases] (portage-ng\#95) --- when a grouped
  dependency degraded to a domain assumption in pass 1 but a concrete
  action for the same package #emph[is] planned, the consumer prefers
  that action.

Within a wave, actions are finally reordered by #strong[merge-order
bias]: the actions other packages wait on most (highest reference count
in the Triggers AVL) are listed first, so the builder starts the
most-blocking work as early as possible.

== Wave projection and plan output
<wave-projection-and-plan-output>
The wave-list plan is a #strong[projection] over the pass-2 proofs ---
an evaluator, not a decider. Every ordering decision was already made
(and justified) during the proving pass; the projection merely assigns
wave numbers by reading availability proofs:

- a step whose requirements are all world-bridged or assumption-bridged
  can start in wave 1;
- a step that cites earlier plan steps lands one wave after the last of
  them;
- accepted preferences raise a step's wave further, never lower it.

#figure(image("Diagrams/12-wave-planning.svg", alt: "Wave plan produced by the ordering pass"),
  caption: [
    Wave plan produced by the ordering pass
  ]
)

The output contract is unchanged from earlier releases: a list of waves,
each containing full-format pass-1 rule terms. All actions within a wave
are independent and can run concurrently. The printer renders the waves
as numbered steps (Chapter 14); the builder executes them with real
parallelism (Chapter 16). Neither consumer knows or cares that the waves
are now backed by proofs.

The plan is annotated per entry with:

- #strong[Wave number] --- which parallel wave it belongs to
- #strong[Action] --- download, install, run, etc.
- #strong[Literal] --- the full `Repo://Entry:Action?{Context}` term

== The same laws order uninstalls
<the-same-laws-order-uninstalls>
Depclean's uninstall order is the same three laws proved over a
different set of bindings (`Source/Domain/Gentoo/Rules/unmerging.pl`). A
step is the `:unmerge` of a removable package; what a step
#emph[requires] is the release of every claim on it --- each removable
consumer must be unmerged first; and the #emph[world] provides nothing,
because an installed consumer's claim is a present fact in the VDB ---
there is no "already provided" escape like merge ordering has.

Cyclic claim chains fall through the same `currently_proving` guard and
surface as #strong[retained-claim assumptions]: the report names exactly
which package still depends on which at its unmerge point, instead of a
bare "cycle detected" flag. The wave projection is reused unchanged, and
the flattened waves are the uninstall order (consumers first,
dependencies last). Kahn's topological sort --- the last procedural
survivor of the pre-proof planner --- was retired with this pass.

One binding detail is load-bearing: the claim index reads the VDB
dependency models through the query layer, whose inlined model
construction dispatches through the #emph[active] rule module. The index
is therefore prepared eagerly, before the unmerge prove scopes the rule
module to `unmerging` (see `unmerging:with_unmerge_pass/2`).

== Further reading
<further-reading-12>
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- how the Proof AVL
  is constructed
- #link("09-doc-prover-assumptions.md")[Chapter 9: Prover Assumptions]
  --- pass-1 cycle breaking
- #link("11-doc-rules.md")[Chapter 11: Rules and Domain Logic] --- how
  rule modules plug into the prover
- #link("12-doc-resolution.md")[Chapter 12: Resolution --- Configuration as Proofs]
  --- pass 1: the configuration being ordered
- #link("14-doc-output.md")[Chapter 14: Output and Visualization] ---
  how the plan is rendered
- #link("16-doc-building.md")[Chapter 16: Building and Execution] ---
  how the plan is executed
- #link("24-doc-dependency-ordering.md")[Chapter 24: Dependency Ordering]
  --- PMS ordering semantics

= Output and Visualization
<output-and-visualization>
After the prover completes and the ordering pass produces a parallel
plan, the next step is to present the result to the user. This happens
before any building --- even a `--pretend` run produces the full plan
output. portage-ng offers several output formats: a colour-coded
terminal plan, `.merge` files for regression testing, interactive SVG
dependency graphs, Gantt charts, and structured reports.

== Terminal plan display
<terminal-plan-display>
The most common output is the terminal plan, which resembles
`emerge -vp` but adds parallel wave information and richer detail. The
printer (`Source/Pipeline/printer.pl`) orchestrates the display,
delegating to submodules under `Source/Pipeline/Printer/`.

=== Merge list
<merge-list>
The plan is rendered as a merge list. Each line represents one action,
printed as a numbered step with a coloured #strong[action bubble] and
the full package atom.

A typical plan fragment looks like this:

```
 └─step 01─┤ install  portage://dev-libs/expat-2.6.4
             │ install  portage://dev-libs/libxml2-2.13.5

 └─step 02─┤ install  portage://dev-lang/python-3.12.3
             │ run      portage://dev-lang/python-3.12.3
             │ confirm  portage://dev-lang/python-3.12.3

 └─step 03─┤ update   portage://sys-apps/portage-3.0.77-r3
             │          (replaces portage-3.0.65)
             │ download https://.../portage-3.0.77-r3.tar.xz

 └─step 04─┤ verify   dev-python/tree-sitter
             │          (non-existent, assumed installed)
```

Actions within the same step can run concurrently --- the step number is
the wave. Each line shows:

- #strong[Step number] --- which parallel wave this action belongs to.
- #strong[Action bubble] --- a full word indicating the operation:
  - `install` --- new install
  - `update` --- version upgrade (shows the replaced version)
  - `downgrade` --- version downgrade (shows the replaced version)
  - `reinstall` --- reinstall of the same version
  - `run` --- runtime dependency check
  - `confirm` --- verify that a running dependency is available
  - `download` --- fetch source from a mirror
  - `fetchonly` --- fetch only, do not build
  - `verify` --- assumed dependency that needs manual verification
- #strong[Package atom] --- repository, category, name, and version
  (e.g. `portage://dev-libs/openssl-3.1.4`).
- #strong[Annotations] --- contextual notes such as `(replaces ...)` for
  upgrades/downgrades, `(~amd64)` for keyword-accepted packages,
  `(USE modified)` for USE flag changes, or
  `(non-existent, assumed installed)` for unresolvable dependencies.

Target packages --- the ones you explicitly asked to prove --- appear in
#strong[bold green] with a green action bubble. Non-target dependencies
use cyan text. Assumed or unresolvable dependencies use yellow or red
bubbles to draw attention.

=== Printing styles
<printing-styles>
portage-ng supports three printing styles, selectable via
`config:printing_style/1` (default: `fancy`):

- #strong[`fancy`] (default) --- the bubble style: a compact visual
  layout where each action line includes colour-coded indicators and
  right-edge annotations.
- #strong[`column`] --- a tabular layout that aligns version, slot, USE,
  and repository information in fixed columns for easy scanning.
- #strong[`short`] --- a minimal one-line-per-action format.

=== Pre-action steps
<pre-action-steps>
Before the merge list, the printer can show #strong[pre-action steps]
--- configuration changes that the plan assumes have been applied. These
correspond to the `suggestion` tags from the prover (see
#link("09-doc-prover-assumptions.md")[Chapter 9]):

- #strong[Accept keyword] --- packages that need `~arch` keyword
  acceptance.
- #strong[Unmask] --- packages that need unmasking.
- #strong[USE changes] --- flag changes needed in `package.use`.

Each pre-action step shows the exact line you would add to the
corresponding `/etc/portage/package.*` file.

=== Summary line
<summary-line>
At the bottom, a summary line shows the total number of actions (new
installs, upgrades, reinstalls, etc.), the step count, and the predicted
download sizes (to be downloaded vs.~already downloaded).

== Assumption and warning output
<assumption-and-warning-output>
After the merge list, the printer shows any assumptions the prover had
to make. These are grouped into two categories:

#strong[Domain assumptions] are situations where the prover could not
find a real solution and had to accept a literal on faith. Each
assumption is printed with:

- The package or dependency that could not be satisfied.
- A classification label (e.g.~"non-existent dependency", "REQUIRED\_USE
  violation", "model unavailable").
- An actionable suggestion showing how to resolve the issue.

#strong[Cycle breaks] are points where the prover broke a dependency
cycle. Each cycle break shows the cycle path (which packages form the
loop) and an explanation of why the cycle was broken rather than treated
as benign.

The assumption type classification is handled by
`Printer/Plan/assumption.pl`, and the detailed rendering by
`Printer/Plan/warning.pl`. For a full description of the assumption
taxonomy, see #link("09-doc-prover-assumptions.md")[Chapter 9].

== Writing module
<writing-module>
The writer (`Source/Application/Output/writer.pl`) generates `.merge`
files --- one per target package --- containing the portage-ng plan
output in a format comparable to `emerge -vp` output. These files are
stored in the graph directory configured by `config:graph_directory/1`
in `Source/Config/<host>.pl`.

`.merge` files serve two purposes:

- #strong[Regression testing] --- by comparing `.merge` files against
  `.emerge` files (the corresponding `emerge -vp` output for the same
  target), the compare tooling can detect regressions in dependency
  resolution accuracy. See #link("25-doc-testing.md")[Chapter 25] for
  the comparison workflow.
- #strong[Offline review] --- the files provide a persistent record of
  what portage-ng would do for each target, without needing to rerun the
  resolver.

== Dependency graph generation
<dependency-graph-generation>
The grapher (`Source/Application/Output/grapher.pl`) produces
interactive SVG dependency graphs that let you visually explore the
dependency tree for a target.

The generation process has three stages:

+ #strong[Edge extraction] --- the proof is traversed to collect all
  dependency edges (which package depends on which, and through what
  action).
+ #strong[DOT generation] --- a `.dot` file is written with nodes
  representing packages and edges representing dependencies. Nodes are
  colour-coded by action type and annotated with version and slot
  information.
+ #strong[SVG rendering] --- the `dot` command (Graphviz) renders the
  DOT file into an SVG. For large graphs, platform-specific scripts
  under `Source/Application/System/Scripts/` can run multiple renderings
  in parallel.

Graph generation is triggered by the `--graph` CLI flag. The resulting
SVGs include interactive navigation (zoom, pan, node highlighting) via a
built-in JavaScript theme (`navtheme` module).

The screenshot below shows a dependency tree for `app-editors/vim`. The
root package appears at the top with its dependencies fanning out below.
Nodes are colour-coded: the red-bordered root, grey nodes for
already-installed packages, and white nodes for packages that need to be
merged. The toolbar at the top allows filtering by dependency type
(BDEPEND, DEPEND, RDEPEND, etc.) and switching between graph views.

#figure(image("Diagrams/13-depgraph.png", width: 85.0%, alt: "Dependency graph for app-editors/vim"),
  caption: [
    Dependency graph for app-editors/vim
  ]
)

The #strong[detail view] shows a single package with its full metadata
--- USE flags (with conditionals), candidate versions, installed status,
and dependency atoms. This view is useful for understanding exactly
which candidates are available and how USE conditionals affect the
dependency tree.

#figure(image("Diagrams/13-detail.png", width: 85.0%, alt: "Detail view for app-shells/bash"),
  caption: [
    Detail view for app-shells/bash
  ]
)

=== Graph submodules
<graph-submodules>
#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Module]], [#strong[Purpose]],),
    table.hline(),
    [`dot`], [Graphviz DOT file generation with colour and layout],
    [`deptree`], [Hierarchical dependency tree visualisation],
    [`detail`], [Detailed single-package view with all metadata],
    [`gantt`], [Gantt chart rendering (see below)],
    [`terminal`], [Terminal-based ASCII graph rendering],
    [`navtheme`], [JavaScript navigation theme for interactive SVGs],
  )]
  , kind: table
  )

== Gantt charts
<gantt-charts>
The `gantt` module produces Gantt charts that visualise the parallel
build schedule computed by the ordering pass. Each horizontal bar
represents a package, positioned on a timeline according to its wave
assignment and estimated build duration.

The chart makes the parallelism visible: packages in the same wave
appear side by side, and you can see how downloads, installs, and
runtime checks overlap across waves. When build time estimates are
available (from VDB sizes or `emerge.log` history), the bar lengths
reflect predicted durations.

The screenshot below shows the execution plan for `app-editors/neovim`.
Each row is a package; colour-coded blocks show download (blue), install
(green), and run (light green) phases across ten steps. Dependency edges
are drawn as coloured curves linking the phases --- red for DEPEND, blue
for BDEPEND, green for RDEPEND --- making it easy to see which packages
gate others and where parallelism is exploited.

#figure(image("Diagrams/13-gantt.png", width: 95.0%, alt: "Gantt chart for app-editors/neovim"),
  caption: [
    Gantt chart for app-editors/neovim
  ]
)

== Report generation
<report-generation>
The report module (`Source/Application/Output/Report/report.pl`)
generates structured reports for analysis, typically as JSON files.
Reports can include:

- #strong[Plan summaries] --- total actions, waves, parallelism metrics.
- #strong[Assumption breakdowns] --- counts and details of domain
  assumptions, cycle breaks, and blocker conflicts.
- #strong[Performance statistics] --- proof time, plan time, cache hit
  rates, reprove retry counts.
- #strong[Comparison data] --- structured output consumed by the
  #link("https://github.com/pvdabeel/tinderbox-ng")[tinderbox-ng]
  compare harness (`tinderbox-ng compare` / `tinderbox-ng analyze`),
  which diffs portage-ng plans against emerge output.

== Printer submodules
<printer-submodules>
The printer pipeline is split across focused submodules:

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

== Further reading
<further-reading-13>
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- how waves and parallelism are computed
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--graph`, `--verbose`, `--quiet`, and other output flags
- #link("16-doc-building.md")[Chapter 16: Building and Execution] ---
  how the plan is executed
- #link("25-doc-testing.md")[Chapter 25: Testing and Regression] --- how
  `.merge` files are used for regression testing

= Command-Line Interface
<command-line-interface>
portage-ng is meant to sit beside Portage, not replace it in name or
habit. Many flags will feel immediately familiar: `--pretend`,
`--verbose`, `--emptytree`, and the usual resolution switches mirror
what you already use with emerge-style workflows. On top of that, a
proof-based resolver can expose tools that a traditional dependency
solver does not: `--explain` and `--llm` for plan dialogue, `--diagnose`
\/ `--log` for metacircular build-failure repair, `--variants` for
USE-sensitive alternatives, and `--search` that can treat a phrase as a
natural-language query when structured parsing does not apply.

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
portage-ng operates in one of six modes, selected with `--mode`:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Mode]], [#strong[Description]],),
    table.hline(),
    [`standalone`], [Full local operation --- the default and most
    common mode],
    [`daemon`], [Persistent daemon serving IPC clients via Unix socket],
    [`ipc`], [Thin IPC client forwarding requests to a running daemon],
    [`client`], [Remote RPC client connecting to a server over HTTPS],
    [`worker`], [Compute node for distributed proving (polls server for
    jobs)],
    [`server`], [HTTP + Pengines server with job/result queues],
  )]
  , kind: table
  )

=== Standalone
<standalone-1>
The default mode. Loads the full pipeline, knowledge base, LLM modules,
and domain logic into a single process. All resolution, planning, graph
generation, and building happens locally. Every CLI action (`--pretend`,
`--sync`, `--graph`, `--shell`, etc.) is available.

=== Daemon
<daemon>
Keeps the same in-memory footprint as standalone --- full knowledge
base, resolver, orderer --- but listens on a #strong[Unix domain socket]
for incoming requests. Use `--background` to fork the daemon into a
detached process. The daemon avoids the startup cost of reloading the
knowledge base on every invocation, making repeated queries fast.

=== IPC
<ipc>
A thin front-end that does #strong[not] load the full resolver stack. It
connects to a running daemon over the Unix socket, forwards the
command-line arguments and environment, streams output back, and exits
with the daemon's exit code. If `--background` auto-start is configured
and no daemon is listening, the IPC client can launch one automatically.
Note that `--shell` is not supported in IPC mode.

=== Client
<client>
A lightweight process that treats a remote #strong[server] as the source
of truth for the knowledge base. Local queries are proxied over HTTPS
using Pengine RPC (with TLS certificates and digest authentication). The
client loads enough of the pipeline to drive the CLI, but proving and KB
access happen on the server side. Use `--host` and `--port` to specify
the server.

=== Server
<server>
Runs the full standalone pipeline first (local KB, resolver, orderer),
then adds an HTTPS Pengine server, TLS, and Bonjour service
advertisement. The server exposes job and result message queues so that
workers can poll for proving tasks. Use `--background` to fork the
server process. See
#link("18-doc-distributed.md")[Chapter 18: Distributed Proving].

=== Worker
<worker>
A compute node that loads the full proving pipeline locally (like
standalone) plus an RPC client for server communication. On startup, the
worker discovers the server via Bonjour or explicit `--host`/`--port`,
syncs its local portage tree to the server's snapshot, registers its CPU
count, and spawns one thread per core. Each thread polls the server for
jobs, proves them locally, and posts results back. See
#link("18-doc-distributed.md")[Chapter 18: Distributed Proving].

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
    [`--info`], [System overview (version, hostname, repositories, world
    set) without arguments; per-package details with a target],
    [`--pretend @installed`], [List installed packages (via the computed
    `@installed` set)],
  )]
  , kind: table
  )

=== Repository management
<repository-management>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--sync`], [Sync the Portage tree and regenerate caches],
    [`--regen`], [Regenerate md5-cache incrementally],
    [`--import-vdb`], [Client mode: ship the local VDB to the server so
    remote plans reflect the client's installed packages (see
    #link("18-doc-distributed.md")[Chapter 18])],
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
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Action]],),
    table.hline(),
    [`--bugs <target>`], [Prove the target (resolve-only) and print
    Gentoo Bugzilla bug-report drafts for its domain assumptions],
    [`--search-bugs <term>`], [Search Gentoo Bugzilla for known issues],
    [`--upstream <target>`], [Check upstream versions via Repology],
    [`--explain` / `--llm`], [Get AI-assisted plan explanation],
    [`--diagnose` / `--log`], [Metacircular LLM diagnose of a failed
    build],
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
    columns: (50%, 50%),
    align: (left,left,),
    table.header([#strong[Flag]], [#strong[Effect]],),
    table.hline(),
    [`--verbose`], [Verbose output (show USE flags, slot info)],
    [`--quiet`], [Minimal output],
    [`--ci`], [Non-interactive CI mode (exit codes 0/1/2)],
    [`--jobs N`], [Number of parallel jobs],
    [`--timeout N`], [Abort proving/planning after N seconds (0 = no
    limit)],
  )]
  , kind: table
  )

== Target syntax
<target-syntax>
Targets can be specified in several formats:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Format]], [#strong[Example]], [#strong[Meaning]],),
    table.hline(),
    [`cat/pkg`], [`sys-apps/portage`], [Resolve latest version],
    [`=cat/pkg-ver`], [`=sys-apps/portage-3.0.77`], [Exact version],
    [`>=cat/pkg-ver`], [`>=dev-lang/python-3.10`], [Version constraint],
    [`@set`], [`@world`, `@security`, `@changed-deps`], [Package set
    (file-backed, profile, or computed)],
    [`pkg`], [`portage`], [Ambiguous name (searched across categories)],
  )]
  , kind: table
  )

== Package sets
<package-sets>
`@name` targets expand to concrete atoms via `eapi:substitute_sets/2`
before proving. File-backed sets (`@world`, `@system`, user sets under
`config:set_dir/1`) come from preference configuration. #strong[Computed
sets] are registered in `Source/Domain/Gentoo/Preference/sets.pl` and
resolved on demand by `sets:expand/2`.

```bash
portage-ng --mode standalone --list-sets
portage-ng --mode standalone --ci --pretend @security
portage-ng --mode standalone --ci --pretend @preserved-rebuild
portage-ng --mode standalone --ci --pretend @changed-deps
```

An empty computed set prints an informational line and exits 0 under
`--ci` (nothing to do), not a hard failure.

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Set]], [#strong[Atoms]], [#strong[Meaning]],),
    table.hline(),
    [`@world` / `@system`], [as configured], [Preference / profile
    sets],
    [`@installed`], [`cat/name:slot`], [Everything installed],
    [`@live-rebuild`], [`cat/name:slot`], [Installed `PROPERTIES=live`
    packages],
    [`@changed-subslot`], [`cat/name:slot`], [Subslot differs from
    highest visible ebuild],
    [`@downgrade`], [`cat/name:slot`], [Highest visible ebuild is older
    than installed],
    [`@unavailable`], [`cat/name:slot`], [No visible ebuild in the same
    slot],
    [`@rebuilt-binaries`], [`=cpv`], [Binpkg BUILD\_TIME ≠ installed
    BUILD\_TIME],
    [`@unavailable-binaries`], [`cat/name:slot`], [No binpkg for the
    installed version],
    [`@security`], [`=cpv`], [GLSA NewAffectedSet (default security
    set)],
    [`@affected` / `@new-affected` / `@new-glsa`], [`=cpv`], [Other
    Portage security-set filters],
    [`@preserved-rebuild`], [`cat/name:slot`], [Consumers of
    FEATURES=preserve-libs leftovers],
    [`@changed-deps`], [`=cpv`], [VDB RDEPEND/PDEPEND drifted from
    same-version ebuild],
  )]
  , kind: table
  )

#strong[`@preserved-rebuild`] reads Portage's `preserved_libs_registry`
JSON (default: derive from `config:pkg_directory/1` as
`…/lib/portage/preserved_libs_registry`\; override with
`config:preserved_libs_registry_override/1`) and matches consumers via
VDB `NEEDED.ELF.2`. It is complementary to the automatic
`config:subslot_rebuild/1` pass, which rebuilds `:=` reverse deps when a
provider's subslot changes inside a plan.

#strong[`@changed-deps`] compares installed RDEPEND/PDEPEND (from the
on-disk VDB) to the same-version tree ebuild after use-reduce and `:=`
stripping, with libc injects removed (emerge `--changed-deps`
semantics). The `--changed-deps` flag applies the same test while
resolving other targets.

GLSA details for `@security` and siblings:
#link("20-doc-glsa.md")[Chapter 20]. Full option text:
#link("../Manpage/portage-ng.1.md")[`portage-ng(1)`].

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
resolver:test_stats(portage).
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
  #link("17-doc-llm.md")[Chapter 17: Semantic Search and LLM Integration]).

- #strong[Diagnose a failed build with metacircular LLM repair] \
  `portage-ng --diagnose cat/pkg` (optional `--log path`) --- propose
  `feedback:*` learning from the build log; confirm before apply (same
  chapter).

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
  resolver:test_stats(portage).
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

- #strong[Draft bug reports] \ `portage-ng --bugs cat/pkg` --- prove the
  target (resolve-only) and print Bugzilla-style bug-report drafts for
  its domain assumptions.

- #strong[Search Bugzilla] \ `portage-ng --search-bugs term` --- query
  Gentoo Bugzilla for known issues.

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
#link("17-doc-llm.md")[Chapter 17: Semantic Search and LLM Integration].

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
<further-reading-14>
- #link("../Manpage/portage-ng.1.md")[`portage-ng(1)` manpage] ---
  exhaustive option reference
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- first run examples
- #link("14-doc-output.md")[Chapter 14: Output and Visualization] ---
  what the output looks like
- #link("20-doc-glsa.md")[Chapter 20: Gentoo Linux Security Advisories (GLSA)]
  --- `@security` and related GLSA computed sets
- #link("03-doc-configuration.md")[Chapter 3: Configuration] ---
  `config:preserved_libs_registry/1` and related paths

= Building and Execution
<building-and-execution>
portage-ng is a self-contained dependency resolver and planner. It ships
its own code for every stage up to the point where source code must
actually be compiled:

- #strong[Cache generation] --- portage-ng includes its own md5-cache
  generator, so it does not depend on Portage's `egencache` or any other
  external tool to produce the cache files it reasons over.
- #strong[Dependency resolution and ordering] --- the prover and the
  ordering engine are entirely internal (see Chapters 8-12).
- #strong[Downloading] --- source archive fetching, mirror selection,
  hash verification, and resume are handled by portage-ng's own download
  module (see #link(<download-management>)[Download management] below).

The only point where Portage is needed is the #strong[execution of
ebuild build phases] (unpack, compile, install, qmerge, etc.). These
phases rely on Portage's `ebuild` command and its ecosystem of eclasses
and phase functions. portage-ng delegates to that infrastructure so that
the full ebuild ecosystem works unchanged, but everything before and
after the build steps --- dependency calculation, plan ordering,
downloading, and output --- is handled independently.

== Build delegation
<build-delegation>
When executing a plan (via `--merge` rather than `--pretend`), the
builder module invokes the `ebuild` command for each action in the plan.
The command is configurable via `config:ebuild_command/1` (default:
`ebuild`).

The builder processes the plan wave by wave, respecting the parallelism
computed by the ordering pass. Within each wave, independent actions can
run concurrently.

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

== Build resilience: the per-phase retry chain
<build-resilience-the-per-phase-retry-chain>
A failed phase is not necessarily a failed build. After every phase,
`ebuild_exec` runs a chain of retry hooks, each keyed on a
#emph[signature] found in the log segment written by the failed phase
(never earlier phases), so deterministic build failures never match and
keep their original semantics. The chain has two layers:

+ #strong[Environmental retries] (in `ebuild_exec.pl` itself) ---
  failures caused by the build environment, not by the package:

  #figure(
    align(center)[#table(
      columns: (25%, 25%, 25%, 25%),
      align: (left,left,left,left,),
      table.header([#strong[Retry]], [#strong[Signature]], [#strong[Recovery]], [#strong[Gate]],),
      table.hline(),
      [Transient (bash PID
      reuse)], [`wait: pid N is not a child of this shell`], [re-run the
      phase once], [`config:build_transient_retry/1`],
      [Serial make (parallel-make race)], [failed compile/test/install
      phase], [re-run with
      `MAKEOPTS=-j1`], [`config:build_serial_retry/1`],
    )]
    , kind: table
    )

+ #strong[Domain exception fixups] (see next section) --- failures
  caused by a problem that should really be fixed at the ebuild or
  metadata level. The chain ends in a single generic dispatch,
  `fixup:maybe_phase_retry/9`, which offers the failure to every
  registered exception mechanism.

Every retry appends a marker line to the build log, so a recovered build
is never silent about how it recovered.

== Domain exception fixups
<domain-exception-fixups>
Some build failures are #emph[packaging exceptions]: the build is
failing because of a gap in the ebuild or its metadata, not because of
the environment or the user's configuration. Traditional emerge either
refuses such packages up front or fails and defers to a manual repair
tool. portage-ng recovers them in-transaction through a small registry
of #strong[exception mechanisms] under
`Source/Domain/Gentoo/Exceptions/`:

- #strong[`fixup.pl`] --- the generic registry and dispatcher. A
  mechanism registers itself with three multifile hooks:
  - `fixup:mechanism/1` --- identity (load order is dispatch and display
    order);
  - `fixup:phase_retry_hook/10` --- the repair-and-retry logic for a
    failed phase;
  - `fixup:mechanism_note/3` --- the note printed above the affected
    packages in the build summary.

  Applied fixups are recorded via `fixup:record/3` and reported
  generically by the build printer --- adding a new exception mechanism
  never touches the builder or the printer.

Mechanisms come in two flavours. Most (collision, GHC ABI, OCaml ABI)
are #strong[in-place repairs]: they rebuild something mid-flight and
re-run the failed phase. The missing-provider mechanism is different ---
it #strong[diagnoses but never repairs in place]: it records what it
learned and lets the pipeline re-derive a fresh plan (see
#link(<missing-provider-feedback>)[Missing provider feedback] below).

=== File collision deconfliction
<file-collision-deconfliction>
Traditional emerge refuses, at the plan stage, to install a package
whose files are owned by a different installed provider --- it is told
so by an explicit blocker atom in metadata (e.g.~installed
`sys-apps/util-linux[hardlink]` carries `!app-arch/hardlink`). When that
blocker atom is #emph[missing], the conflict only surfaces at merge time
as Portage's `pkg_preinst` collision-protect abort. Gated by
`config:deconflict_collisions/1` (`off` | `report` | `override`), the
mechanism recognises the collision signature and re-runs the merge with
`FEATURES="-collision-protect -protect-owned"`, letting the package
overwrite the colliding files. The plan printer already announces this
behaviour next to the soft-blocker list, and the build summary lists
every package that needed it. The same recovery is applied to
binary-package `qmerge` merges.

=== Haskell ABI repair
<haskell-abi-repair>
Gentoo encodes a Haskell package's identity in `ghc-pkg`'s ABI hash (the
suffix in e.g.~`bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ`), not in the
ebuild sub-slot. When a `dev-haskell` library is rebuilt, its installed
reverse-dependencies keep referencing the old hash, and the next Haskell
consumer aborts in `pkg_setup`/`configure` with haskell-cabal.eclass's
check:

```
installed package semigroupoids-5.3.7 is broken due to missing package
bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ
 * Detected broken packages: semigroupoids-5.3.7 semialign-1.3
 * //==-- Please, run 'haskell-updater' to fix broken packages --==//
```

Because the hash lives only in ghc-pkg's registry, there is no sub-slot
delta for the resolver to observe, and traditional emerge fails the same
configure and defers to a manual `haskell-updater` run. portage-ng does
better: gated by `config:ghc_abi_repair/1`, the mechanism parses the
broken package list from the failed phase's log, rebuilds each broken
package from source at its installed version and with its VDB-recorded
USE configuration (never from a binary package --- a stale binpkg ABI is
exactly what may be broken), and re-runs the failed phase. One
additional bounded round covers cascading breakage exposed by the repair
itself.

The mechanism is bounded and observable: each package is rebuilt at most
once per session (it can never loop), repairs are serialized across
parallel build workers, and every repair leaves markers in both the
consumer's and the rebuilt package's build logs plus an entry in the
build summary.

=== OCaml ABI repair
<ocaml-abi-repair>
OCaml has the same problem: package identity lives in the compiled
interface digests (`.cmi` CRCs) checked by the compiler and in findlib's
registry, not in the ebuild sub-slot. Unlike Haskell there is no single
eclass check enumerating the broken packages --- a stale consumer fails
with heterogeneous compiler and ocamlfind messages:

```
Error: The files /usr/lib64/ocaml/site-lib/res/res.cmi
       and /usr/lib64/ocaml/stdlib.cmi
       make inconsistent assumptions over interface Stdlib
Error: Unbound module Camlp5
ocamlfind: Package `camlp5' not found
```

Gated by `config:ocaml_abi_repair/1`, the mechanism extracts the stale
compiled-unit paths and findlib package names from the failed phase's
log, maps them to their installed owners through the VDB CONTENTS
records (the active enumerator this domain lacks an eclass check for),
rebuilds those owners from source at their installed version, and
re-runs the failed phase --- with the same boundedness guarantees as the
GHC repair: at most one rebuild per package per session, at most two
retry rounds, repairs serialized across workers, and markers in every
involved build log plus the build summary. The package being built and
`dev-lang/ocaml` itself are never rebuild candidates.

=== Missing provider feedback
<missing-provider-feedback>
The three mechanisms above all repair reality in place: they rebuild a
package mid-transaction and re-run the failed phase. That pattern is
wrong for a whole class of failures --- a build that dies because a
required #emph[provider] is missing (a command, header, library, or
pkg-config module that some package would supply but that the ebuild
never declared as a dependency). The canonical case is
`sec-policy/selinux-base`, whose compile dies with

```
semodule_package: command not found
```

because `selinux-policy-2.eclass` never lists `sys-apps/semodule-utils`
in `BDEPEND`. portage-ng built exactly what it was told to; the
dependency simply is not in the metadata, so the resolver never saw it.
Repairing this in place would decide ordering imperatively in the
builder, could not chase the provider's own transitive needs, would
break the invariant that the plan equals `prove_plan(Goals, KB)`, and
would forget the discovery so the next run fails again.

So `missing_provider.pl` (portage-ng\#102), gated by
`config:missing_provider_feedback/1`, does the opposite of a repair:
#strong[it emits a structured diagnostic, that diagnostic becomes
learned knowledge, the pipeline re-derives a fresh provable plan that
orders the provider before the target, and the builder resumes that new
plan.] Plans are derived, never patched. It threads the failed phase's
exit code through unchanged --- the phase legitimately still failed.

The diagnosis is split into two pluggable layers, each a multifile
registry so new failure shapes and resolution strategies are added as
clauses rather than by editing the dispatcher:

- #strong[Detector registry] (`missing_provider:detector/3`) normalises
  the failed phase's log tail into a `symbol(Kind, Name)`. Ships
  detectors for missing commands (bash `command not found`, dash
  `not found`, `env` exec failures), headers (`fatal error: X.h`),
  libraries (`cannot find -lX`), sonames, pkg-config modules, and
  python/perl modules.
- #strong[Resolver chain] (`missing_provider:provider_of/4`) maps a
  symbol to a concrete `Category/Name` package: first the authoritative
  VDB `CONTENTS` reverse-owner index (the `qfile`/`equery belongs`
  equivalent, for providers that happen to be installed), then a small
  curated seed table (for the common case where the provider is
  #emph[not] installed --- that is precisely why the command was
  missing). A symbol that maps to no concrete in-tree package is written
  to an unresolved backlog and the target fails cleanly --- no guessing.

A concrete discovery is recorded through the `feedback` module
(`Source/Knowledge/feedback.pl`) as a durable `discovered_dep/4` fact,
persisted to `Knowledge/feedback.pl` (gitignored, consulted at startup
like the QLF cache) so a one-time runtime discovery becomes permanent
knowledge. The only resolver change is in `query.pl`, which unions
`feedback:discovered_dep(Target, Provider, bdepend, _)` into the
target's build-dependency model. The mechanism also distinguishes an
#emph[undeclared] dependency (the upstream-gap case above --- mint a
discovery) from a #emph[declared-but-unbuilt] one (a genuine resolver
ordering bug --- logged loudly, never papered over).

The control loop lives in the builder: `builder:build/1` is a bounded
replan loop (`builder:build_loop/2`, capped by
`config:missing_provider_max_replan/1`). When a build pass fails
#emph[and] recorded a new discovery, the builder re-enters the pipeline;
on the re-proof the provider is part of the closure, so the ordering
pass orders it --- and its own transitive dependencies --- before the
target. Everything already built satisfies from the VDB via the existing
reconciliation fast path, so the retry pass only builds the provider and
recompiles the target. Walkthrough for the selinux case:

+ `selinux-base` compile → `semodule_package: command not found`.
+ `missing_provider` maps the command to `sys-apps/semodule-utils`,
  records a `discovered_dep`, and persists it; the phase still fails.
+ The wave ends with `selinux-base` failed; `build_loop` sees the new
  discovery and re-enters the pipeline.
+ `rules`/`query` now yield
  `BDEPEND(selinux-base) ⊇ {sys-apps/semodule-utils}`\; the prover
  proves it, the orderer places `semodule-utils` (and its transitive
  `sys-libs/libsepol`) first.
+ Retry pass: the provider builds, `selinux-base` recompiles, and the
  300+ downstream `selinux-*` packages never fail --- the discovery is
  persisted before their turn.

Because the discovery carries structured evidence (the symbol, phase,
exit code, and log excerpt), the printer proposes a Gentoo Bugzilla bug
report draft at the end of the build for every dependency worked around
this session --- the record doubles as an upstream ebuild/eclass bug
report (see #link("19-doc-upstream-bugs.md")[Chapter 19]).

=== USE-enable feedback
<use-enable-feedback>
A closely related gap is when the provider #emph[is] declared and even
installed, but was built with the wrong USE set --- e.g.
`KX11Extras: No such file or directory` because
`kde-frameworks/kwindowsystem` was merged `-X` on a headless profile
(portage-ng\#110). Re-adding a bare `cat/name` BDEPEND (the \#102 path)
is a no-op: the package is already in the plan/VDB. What is missing is a
HARD `[flag]` usedep.

`useenable.pl`, gated by `config:use_enable_feedback/1`, mirrors the
\#102 three seams: detect a compile/configure symbol, resolve it via a
curated seed table to `Provider + HARD usedeps`, record a durable
`feedback:discovered_usedep/4`, and let `builder:build_loop/2`
re-derive. On the next proof `query.pl` unions a
`package_dependency(..., UseDeps)` edge so the existing BWU /
`bwu_force` machinery rebuilds the provider with the flag. Plans stay
derived --- the hook never writes `/etc/portage/package.use` itself (any
`suggestion(use_change)` that the re-derived plan emits is a consequence
of proving, not an imperative patch).

=== Build summary reporting
<build-summary-reporting>
At the end of a build, the printer renders one block per mechanism that
applied fixups, using the mechanism's own note:

```
Total: 46 completed.

Deconfliction: collision protection was disabled to merge 1 package over
               files owned by other installed packages (portage-ng#90):
  - app-arch/hardlink-0.3.2

GHC ABI repair: 2 broken packages rebuilt in-transaction after a
                dependency ABI-hash change (portage-ng#93, haskell-updater equivalent):
  - dev-haskell/semialign-1.3
  - dev-haskell/semigroupoids-5.3.7

Missing provider: 1 package had an undeclared build dependency discovered at
                  build time and learned as BDEPEND (portage-ng#102):
  - sec-policy/selinux-base
```

Followed, for a missing-provider discovery, by the bug report draft:

```
>>> Missing build dependencies discovered (bug report drafts)

---
Summary: sec-policy/selinux-base: missing BDEPEND=sys-apps/semodule-utils (command semodule_package not found)

Affected package: portage://sec-policy/selinux-base
Missing dependency: sys-apps/semodule-utils (build-time / BDEPEND)
Observed:
  command semodule_package not found during the compile phase (exit 127):
    semodule_package: command not found
Potential fix (suggestion):
  Add BDEPEND="sys-apps/semodule-utils" to the ebuild or the responsible inherited eclass.
  (discovered by portage-ng missing-provider feedback, portage-ng#102)
```

== Live build display
<live-build-display>
During a `--merge` run, portage-ng keeps the terminal display up-to-date
so you can see exactly where the build process stands at any moment. The
static plan that was printed during the `--pretend` phase is reprinted
once, and below it a live "Executing" area shows the current state of
every active build slot.

The following example shows the pretend output for
`sys-kernel/gentoo-sources`. The plan has three steps: download the
source tarball plus patches, install the package, and register the
runtime phase.

```
>>> Emerging : portage://sys-kernel/gentoo-sources-6.19.11:run?{[]}

These are the packages that would be merged, in order:

Calculating dependencies... done!

 └─[step  1]─┤ download  portage://sys-kernel/gentoo-sources-6.19.11
             │           └─ file ─┤ 877.73 Kb   genpatches-6.19-10.base.tar.xz
             │                    │ 4.22 Kb      genpatches-6.19-10.extras.tar.xz
             │                    │ 148.84 Mb    linux-6.19.tar.xz

 └─[step  2]─┤ install   portage://sys-kernel/gentoo-sources-6.19.11
             │           └─ conf ─┤ USE = "build symlink -experimental"
             │                    │ SLOT = "6.19.11"

 └─[step  3]─┤ run       portage://sys-kernel/gentoo-sources-6.19.11

Total: 3 actions (1 download, 1 install, 1 run), grouped into 3 steps.
       149.70 Mb to be downloaded.
```

When the same target is merged with `--merge`, the display turns into a
live view. Each step gains a phase line showing the individual ebuild
phases and their current state. A snapshot mid-build might look like
this:

```
These are the packages being merged, in order:

Executing 3 actions, grouped into 3 steps...

 └─[step  1]─┤ download  portage://sys-kernel/gentoo-sources-6.19.11    ✓
             │           └─ file ─┤ 877.73 Kb   genpatches-6.19-10.base.tar.xz     ✓
             │                    │ 4.22 Kb      genpatches-6.19-10.extras.tar.xz   ✓
             │                    │ 148.84 Mb    linux-6.19.tar.xz                  ✓

 └─[step  2]─┤ install   portage://sys-kernel/gentoo-sources-6.19.11    ⣾
             │           └─ exec ─┤ ACTION = setup → unpack → prepare   (42%) 2/7
             │                    │ LOG = /var/log/portage/sys-kernel:gentoo-sources.log

 └─[step  3]─┤ run       portage://sys-kernel/gentoo-sources-6.19.11
```

In this snapshot, step 1 (download) has completed --- each file shows a
green check mark on the right edge. Step 2 (install) is active: the
action line shows a spinning indicator, and the phase line reveals that
`setup` and `unpack` have finished (shown in cyan) while `prepare` is
the current phase. The right edge displays the accumulated progress
(`42%`) and a phase counter (`2/7`). Step 3 (run) is still pending in
dark grey, waiting for the install to finish.

=== Slot states and colours
<slot-states-and-colours>
Each slot in the live display represents one concurrent build. The slot
line changes colour and icon as the build progresses:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[State]], [#strong[Colour]], [#strong[Indicator]],),
    table.hline(),
    [Pending], [Dark grey], [Waiting for prerequisites],
    [Active], [Cyan (action) + green (target)], [Spinning indicator on
    the right edge],
    [Done], [Green], [Check mark],
    [Failed], [Red], [Exclamation mark],
    [Stub], [Grey], [Phase skipped (already satisfied)],
  )]
  , kind: table
  )

=== Per-ebuild phase tracking
<per-ebuild-phase-tracking>
Below each slot line, the display shows the individual ebuild phases
(setup, unpack, prepare, configure, compile, install, qmerge) with their
current status. Each phase word is coloured independently:

- #strong[Dark grey] --- pending (not yet started)
- #strong[Cyan] --- active or in progress
- #strong[Green] --- completed successfully
- #strong[Red] --- failed

The builder tracks phase state through `builder:exec_phase_state/3`,
which is updated by a callback from the ebuild execution module as each
phase starts, progresses, and finishes.

=== Progress indicators
<progress-indicators>
portage-ng shows progress at multiple levels:

- #strong[Per-phase percentage] --- during long phases like `compile`,
  the builder polls the build log every 0.5 seconds and computes a
  progress estimate. This blends two signals: the growth of the log file
  (bytes written) and historical data from previous builds of the same
  package (stored in `Knowledge/phase_stats.pl`).
- #strong[Overall progress] --- the right edge of the display shows an
  accumulated percentage and a counter (`Current/Total`) reflecting how
  many actions have completed out of the total plan. Stub actions
  (already satisfied) are excluded from the total.
- #strong[Download progress] --- for parallel downloads, each file shows
  a percentage and transfer speed. Git clones show a separate percentage
  based on the git progress output.

=== Log file locations
<log-file-locations>
Each build action writes its output to a log file. The path is computed
from the build log directory (`config:build_log_dir/1`) and the ebuild
name. When `--logs` is enabled, the log path is displayed below the
phase line for each slot. If a phase fails, the log path turns red so
you can quickly find the relevant output.

=== Terminal refresh
<terminal-refresh>
The live display uses ANSI cursor movement to update individual lines in
place: the builder moves the cursor up to the target line, redraws it,
and moves back down. This avoids flooding the terminal with repeated
full-screen redraws. All display mutations go through a `build_display`
mutex to prevent concurrent workers from interleaving their output.

In non-TTY environments (e.g.~CI pipelines), cursor movement is disabled
and the builder falls back to sparse status lines.

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

Downloads are scheduled as early as possible in the plan --- `:download`
actions have no unmet requirements, so they land in the earliest waves
and packages can download while others are building.

== Snapshot support
<snapshot-support>
Upgrades can go wrong --- a new version may fail to compile, introduce
regressions, or break other packages. portage-ng's snapshot module
(`Source/Pipeline/Builder/snapshot.pl`) lets you freeze the current
system state before a merge and roll back to it afterwards.

=== How a snapshot is created
<how-a-snapshot-is-created>
When a merge begins with `--snapshot` (or with `config:snapshot_enabled`
asserted in the per-machine config --- snapshots are disabled by
default), portage-ng creates a snapshot identified by a timestamp
(e.g.~`20260405-143012`). The snapshot directory contains three files:

- #strong[`manifest.pl`] --- a Prolog fact file listing every package
  currently installed in the VDB, with category, name, version, and
  slot.
- #strong[`world`] --- a copy of the current world set file, so the set
  of explicitly requested packages can be restored exactly.
- #strong[`actions.pl`] --- the planned actions for the merge, recorded
  so that a rollback knows which packages were touched.

=== Quickpkg: preserving the old version
<quickpkg-preserving-the-old-version>
The key to rollback is preserving the #strong[binary package] of each
package that is about to be replaced. Before portage-ng merges a new
version, the builder calls `snapshot:quickpkg_old/2`. This runs
`ebuild --skip-manifest <old-ebuild> package` with `PKGDIR` pointed at
the snapshot's `binpkgs/` directory. The result is a tarball (`.tbz2` or
`.gpkg.tar`) that contains the currently installed files of the old
version --- essentially the same operation that Gentoo's `quickpkg` tool
performs.

Because this happens #strong[per package, just before the upgrade], the
snapshot accumulates exactly the set of binary packages needed to
reverse the merge. Packages that were not touched are not quickpkg'd;
they remain unchanged on the system.

=== Listing and diffing snapshots
<listing-and-diffing-snapshots>
`--snapshots` shows all available snapshots with their timestamp,
installed package count, and the number of binary packages stored:

```
Available snapshots:
  20260405-143012       2026-04-05 14:30:12   1847 pkgs   12 binpkgs
  20260402-091544       2026-04-02 09:15:44   1843 pkgs    5 binpkgs
```

`--rollback <id> --pretend` compares a snapshot's manifest against the
current VDB and shows what changed --- packages installed since the
snapshot, packages removed, and packages whose version changed:

```
Diff against snapshot "20260405-143012":

  Installed since snapshot (2):
    + dev-libs/newlib-4.5.0
    + dev-util/newtool-1.0

  Version changed since snapshot (3):
    ~ sys-libs/glibc  2.40-r2 -> 2.41
    ~ dev-lang/python  3.12.8 -> 3.13.1
    ~ app-editors/vim  9.1.1652-r2 -> 9.1.1700

  Summary: +2 -0 ~3 (3 binpkgs available for rollback)
```

=== Rolling back
<rolling-back>
`--rollback <id>` reinstalls the saved binary packages from the
snapshot's `binpkgs/` directory and restores the world set file. Each
binary package is merged back onto the system via
`ebuild <binpkg> merge`, downgrading the affected packages to their
pre-upgrade versions. Combined with `--pretend`, the rollback shows what
would be reinstalled without actually making changes.

=== Lifecycle
<lifecycle>
After the merge completes (whether successfully or not), the snapshot
remains on disk so it can be used for rollback at any later time. There
is no delete flag; to reclaim disk space, call `snapshot:delete(Id)`
from `--shell` (or remove the snapshot directory by hand).

== Further reading
<further-reading-15>
- #link("13-doc-planning.md")[Chapter 13: Ordering --- Plans as Proofs]
  --- how the plan is constructed
- #link("14-doc-output.md")[Chapter 14: Output and Visualization] ---
  plan display and `.merge` file generation
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--merge`, `--jobs`, `--estimate` flags

= Semantic Search and LLM Integration
<semantic-search-and-llm-integration>
portage-ng integrates with large language models for three purposes:
#strong[semantic search] over the knowledge base using vector
embeddings, #strong[plan explanation] using natural-language generation,
and #strong[metacircular self-repair] that proposes build-time learning
from failed build logs (human-confirmed `feedback:*` records, optional
fixup drafts).

== Semantic search
<semantic-search>
The semantic search module (`Source/Application/Llm/semantic.pl`)
enables natural-language queries over the package knowledge base.

=== How it works
<how-it-works>
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
embedding model (configured via `config:semantic_model/1`)

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

== Calling LLMs
<calling-llms>
portage-ng offers three ways to interact with an LLM.

=== Interactive chat (`--llm`)
<interactive-chat---llm>
The `--llm` flag opens an interactive chat session with the default (or
a named) LLM service. The session maintains conversation history, so
follow-up questions have context:

```bash
# Chat with the default LLM (configured in config.pl)
portage-ng --llm

# Chat with a specific service
portage-ng --llm claude
portage-ng --llm ollama
```

Inside the session, the LLM streams its response word by word to the
terminal. Type `quit` or `exit` to leave.

=== Plan explanation (`--explain`)
<plan-explanation---explain>
The `--explain` flag resolves a target first, then feeds the full build
plan to the LLM as structured context. The user can then ask questions
about the plan in a conversational loop:

```bash
# Explain a build plan interactively
portage-ng --pretend --explain dev-libs/openssl

# Single-shot question
portage-ng --pretend --explain "Why is zlib in the plan?" dev-libs/openssl
```

The plan context includes targets, every package with its action type
and USE flags, dependency chains traced back to the root, and any
assumptions the prover made. The LLM sees the full picture and can
answer questions like "why is this package included?", "what would
happen if I disabled this USE flag?", or "which assumptions were made?"

=== Programmatic access
<programmatic-access>
From the Prolog shell, any LLM can be called directly:

```prolog
% Call a specific service
claude("Explain what dev-libs/openssl does", Response).
ollama("What is a USE flag?", Response).
grok("Compare DEPEND and RDEPEND", Response).

% Or use the generic dispatcher
explainer:call_llm(claude, "Your question here", Response).
```

Each service maintains its own conversation history, so subsequent calls
build on previous context.

== Grounding: how the LLM learns portage-ng
<grounding-how-the-llm-learns-portage-ng>
Ordinary chat injects short `config:llm_capability/2` primers
(`context`, `architecture`, `chat`, `code`). Those are not enough to
invent APIs safely, so the LLM is steered to a #strong[read-only
knowledge pack]:

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([Predicate], [Purpose],),
    table.hline(),
    [`llmknowledge:list_topics/0`], [Catalogue curated digests],
    [`llmknowledge:print_topic/1`], [`architecture`, `proof`,
    `assumptions`, `learning`, `code_map`, …],
    [`llmknowledge:print_handbook/1`], [Bounded Handbook chapter
    (`prover`, `rules`, `building`, …)],
    [`llmknowledge:print_source/3`], [Whitelisted `Source/…` or Handbook
    excerpt by line range],
  )]
  , kind: table
  )

Call these from `<call:swi_prolog>` (sandboxed). Paths outside the
whitelist and `..` traversal are rejected. Caps:
`config:llm_knowledge_max_bytes/1`,
`config:llm_knowledge_max_source_lines/1`.

Metacircular `--diagnose` additionally injects the `learning` and
`code_map` digests into its prompt. A future step can embed Handbook +
source for vector retrieval; the knowledge pack is the always-on path
that does not require Ollama.

Module: `Source/Application/Llm/knowledge.pl`.

== Code execution in the sandbox
<code-execution-in-the-sandbox>
One of portage-ng's most distinctive LLM features is that an LLM can
#strong[execute Prolog code] inside the running system and receive the
output. This turns the LLM from a passive question-answerer into an
active investigator that can query the knowledge base, inspect proof
artifacts, and verify its own answers.

#figure(image("Diagrams/16-llm-interaction.svg", width: 80.0%, alt: "LLM interaction and code execution"),
  caption: [
    LLM interaction and code execution
  ]
)

=== How it works
<how-it-works-1>
When an LLM responds, portage-ng scans the response for XML-style call
tags. Two kinds are recognized:

- #strong[`<call:swi_prolog>` … `</call:swi_prolog>`] --- the enclosed
  Prolog code is executed in a temporary, sandboxed module. The output
  (both standard output and error) is captured and sent back to the LLM
  as a function response.
- #strong[`<call:claude>` / `<call:grok>` / etc.] --- the enclosed
  message is forwarded to another LLM service, and that service's
  response is sent back. This allows LLMs to consult each other.

The LLM is informed of these capabilities through a system prompt
assembled from `config:llm_capability/2` clauses. The prompt explains
the available tags and how to use them, without the user needing to know
about the mechanism.

=== Sandbox safety
<sandbox-safety>
Code execution is sandboxed by default
(`config:llm_sandboxed_execution(true)`). The code runs in a temporary
module created by SWI-Prolog's `in_temporary_module/3`, with
`sandboxed(true)` ensuring that only safe predicates are accessible. The
module is destroyed after execution. This means the LLM can:

- Query the knowledge base (`cache:ordered_entry/5`, `query:search/2`)
- Inspect proof artifacts if they are in scope
- Perform computations and formatting
- Write output that gets captured and returned

But it #strong[cannot] modify the file system, execute shell commands,
or alter the running system's state.

=== Example interaction
<example-interaction>
The diagram below traces a single round trip. The user asks a question;
portage-ng forwards it (with a system prompt listing the available
capabilities) to the LLM. The LLM responds with embedded Prolog code
wrapped in a `<call:swi_prolog>` tag. portage-ng detects the tag,
executes the code in a sandboxed temporary module, captures the output,
and sends it back to the LLM as a function result. The LLM then
incorporates the verified fact into its final answer, which is streamed
back to the user.

#figure(image("Diagrams/16-code-execution.svg", width: 50.0%, alt: "Code execution round trip"),
  caption: [
    Code execution round trip
  ]
)

Concretely, a user asks "How many ebuilds are in the tree?" The LLM
responds with:

```
<call:swi_prolog>
:- aggregate_all(count, cache:ordered_entry(portage, _, _, _, _), N),
   format('The portage tree contains ~w ebuilds.~n', [N]).
</call:swi_prolog>
```

portage-ng executes this code, captures the output ("The portage tree
contains 32,147 ebuilds."), and sends it back to the LLM. The LLM then
incorporates this verified fact into its final answer to the user.

=== Inter-LLM communication
<inter-llm-communication>
The same tag mechanism allows LLMs to delegate questions to each other.
The diagram below shows the flow: the primary LLM (Claude in this
example) embeds a `<call:ollama>` tag in its response. portage-ng
detects the tag, forwards the enclosed message to Ollama, collects
Ollama's response, and sends it back to Claude as a function result.
Claude then weaves both perspectives into its final answer.

#figure(image("Diagrams/16-inter-llm.svg", width: 75.0%, alt: "Inter-LLM communication"),
  caption: [
    Inter-LLM communication
  ]
)

For example, a Claude session might embed
`<call:ollama>Summarize this dependency chain</call:ollama>` to get a
local model's perspective, or
`<call:grok>What is the latest version of openssl?</call:grok>` to
cross-check information. Each delegated call maintains the target
service's own conversation history.

== Suggestions and explanations
<suggestions-and-explanations>
Beyond answering questions, the LLM integration supports two practical
workflows: #strong[plan explanation] and #strong[failure diagnosis].

=== Plan explanation
<plan-explanation>
When `--explain` is active, portage-ng assembles a structured context
from the proof artifacts that includes:

- #strong[Targets] --- the packages the user requested
- #strong[Plan entries] --- every package in the merge plan with its
  step number, action type (install/run/download), USE flags (with
  annotations for user-set, profile-forced, and resolver-changed flags),
  slot information, and dependency chain
- #strong[Reverse dependency paths] --- for each package, the chain of
  dependencies tracing back to the root target ("zlib is needed by
  openssl, which is needed by python, which is the target")
- #strong[Assumptions] --- any domain assumptions or cycle breaks, with
  classified reasons (missing package, masked, keyword-filtered, slot
  mismatch, version conflict)

This context allows the LLM to give precise, grounded answers rather
than generic advice. When a user asks "why is zlib in the plan?", the
LLM can point to the exact dependency chain rather than guessing.

=== Failure diagnosis
<failure-diagnosis>
When the resolver cannot satisfy a dependency, it records an
`assumption_reason` in the proof context. The explainer's
`assumption_reason_for_grouped_dep/6` predicate diagnoses the failure by
progressively filtering candidates through existence checks, mask
checks, slot restrictions, version constraints, and keyword acceptance.
The classified reason (e.g.~`missing`, `masked`, `keyword_filtered`,
`version_conflict`) is attached to the assumption and included in the
LLM context.

When the `--llm` flag is combined with a failing target, portage-ng
sends a specialized diagnostic prompt (`config:llm_support/1`) to the
LLM, providing the failure details and asking for help identifying the
correct package atom or diagnosing the issue.

== Metacircular self-repair
<metacircular-self-repair>
When a build phase fails and deterministic fixups
(`fixup:phase_retry_hook/10`) do not mint new `feedback:*` knowledge,
portage-ng can ask the configured LLM to diagnose the failure and
propose structured repair actions. The module is
`Source/Application/Llm/metacircular.pl`.

=== Loop
<loop>
+ Builder records failed `Repo://Entry` + log path
  (`builder:last_failed/3`).
+ If `should_replan` would not fire (no new deterministic discoveries),
  and `config:llm_metacircular(true)` with an interactive TTY (not
  `--ci`), metacircular assembles context: plan summary, polarity-tagged
  assumptions, fallback tier, feedback backlog, learned `cn_domain`, and
  a bounded log tail.
+ The LLM receives `config:llm_capability(metacircular, …)` (excluded
  from ordinary `--llm` chat prompts) and must reply with a single term:

```prolog
repair_proposal([
  action(record_discovery, Repo://Entry, 'cat/pkg', bdepend, Evidence),
  action(record_usedep, Repo://Entry, 'cat/pkg', [use(enable(foo),none)], Evidence),
  action(record_excluded_version, Cat, Name, Ver, Evidence),
  action(record_kernel_config, Repo://Entry, ['CONFIG_FOO'], Evidence),
  action(draft_fixup, MechanismName, Synopsis, SketchBody)
]).
```

#block[
#set enum(numbering: "1.", start: 4)
+ Actions are validated (in-tree providers only; at most
  `config:llm_metacircular_max_actions/1`, default 3). Each accepted
  action is confirmed interactively; confirmed feedback writes go
  through `feedback:record_*` so the existing replan loop re-derives the
  plan.
+ `draft_fixup` writes a sketch under `Knowledge/drafts/` (gitignored);
  it is never auto-loaded. A human must review and commit under
  `Source/Domain/Gentoo/Exceptions/`.
]

=== Safety model
<safety-model>
- Mutations happen #strong[host-side after confirm], never via
  `<call:swi_prolog>`.

- Sandbox may #strong[read] `feedback:*`,
  `missing_provider:package_in_tree/1`, and parse helpers; it cannot
  call `feedback:record_*`.

- New package edges belong in `feedback:*`, not `prover:learn/3`
  (version/USE domains only).

- Kill-switch: `config:llm_metacircular(false)`.

- Skip loading LLM modules entirely: `config:load_llm_modules(false)`.
  Builder and CLI then no-op diagnose paths (stubs + soft
  `explainer:call_llm/3`); no existence errors.

- #strong[`explainer:call_llm/3` on the server is opt-in.] Default
  `config:llm_server_calls(false)` keeps it off the Pengines safelist so
  authenticated clients cannot burn server API keys or exfiltrate
  prompts. LLM features are then #strong[host-local]: run `--explain` /
  `--diagnose` / `--llm` on standalone or client processes (own
  `Source/Config/Private/api_key.pl`). To allow server-side LLM via RPC
  on a trusted cluster, set in a host config or
  `Source/Config/Private/`:

  ```prolog
  :- asserta(config:llm_server_calls(true)).
  ```

  The server must also load LLM modules
  (`config:load_llm_modules(true)`) and hold valid keys in its
  `api_key.pl`.

=== CLI
<cli>
```bash
# Offline diagnose of a failed package (uses default log path)
portage-ng --diagnose cat/pkg

# Explicit log
portage-ng --diagnose --log /var/tmp/portage-ng/logs/cat--pkg-1.2.3.log cat/pkg
```

During an interactive `--build`, diagnose runs automatically after a
failed pass with no new deterministic discoveries (same confirm gate).

== Explainer architecture
<explainer-architecture>
#figure(image("Diagrams/16-explainer-arch.svg", width: 90.0%, alt: "Explainer architecture"),
  caption: [
    Explainer architecture
  ]
)

The explainer is split into two modules with clearly separated
responsibilities.

=== Domain-agnostic introspection
<domain-agnostic-introspection>
`explainer.pl` answers "why" questions by inspecting the proof artifacts
(ProofAVL, ModelAVL, Plan, TriggersAVL) without knowing anything about
Gentoo or Portage. It provides three families of queries:

- #strong[`why_in_proof/3,4`] --- given a literal, look it up in the
  ProofAVL and report how it was proved: via a normal rule, a domain
  assumption, or a prover cycle-break. Returns the body literals and the
  proof-term context.
- #strong[`why_in_plan/5,6`] --- given a literal and a plan, locate it
  in the wave schedule and trace a reverse-dependency path (via
  TriggersAVL) back to a root target. The result explains #emph[why]
  this package is in the plan (e.g.~"required by X, which is required by
  the target Y").
- #strong[`why_assumption/4,5`] --- given an assumption key, classify it
  (domain assumption, cycle-break, or model-only) and extract any
  `assumption_reason` tags from the context.

The utility predicate #strong[`term_ctx/2`] extracts the `?{Ctx}`
context list from any literal-shaped term. This is how the explainer
accesses the structured tags (USE state, slot info, suggestions,
assumption reasons) attached to each literal during the proof.

=== Domain-specific hooks
<domain-specific-hooks>
`explanation.pl` provides #strong[enrichment hooks] that inject
Gentoo-specific context into the generic Why terms produced by
`explainer.pl`. The hooks are multifile predicates, so the domain layer
plugs into the generic layer without modifying it:

- #strong[`why_in_proof_hook/2`] --- if the proof context contains
  domain reasons (masking info, keyword filtering, slot constraints), it
  appends a `domain_reasons(Reasons)` tag to the Why term.
- #strong[`why_in_plan_hook/2`] --- reserved for future plan-level
  Gentoo annotations (currently identity).
- #strong[`why_assumption_hook/2`] --- enriches assumption Why terms
  with domain reasons extracted from the assumption's context.

The module also provides #strong[`assumption_reason_for_grouped_dep/6`],
which diagnoses #emph[why] a grouped dependency resolution failed. It
inspects the candidate pool and classifies the failure (missing package,
all candidates masked, keyword-filtered, slot mismatch, version
conflict, etc.). This diagnosis is cached and feeds the
`assumption_reason` tags that appear in the proof context.

=== LLM dispatch
<llm-dispatch>
Both modules produce structured Prolog terms. When the user wants a
human-readable explanation, the `explain/2,3` predicates in
`explainer.pl` convert the structured Why term into a text prompt via
`format_why_prompt/2` (which uses `term_to_atom/2` and prepends a system
preamble), then dispatch it to an LLM backend via `call_llm/3`. The LLM
backend is configurable (`config:llm_default/1`) and can be Ollama,
Claude, or any other service that implements the expected interface.

A separate, richer LLM path exists in `explain.pl`
(`Source/Application/Llm/explain.pl`), which builds a multi-section text
context from the entire plan (targets, actions, USE flags, assumptions)
and sends it as a conversational prompt. This is used by `--explain` and
the interactive `explain_plan_interactive/5` mode, where the user can
ask follow-up questions about the plan.

== Query families
<query-families>
Three families of queries are supported:

- #strong[why\_in\_proof]: given a literal, find how it was proven
  (normal rule, domain assumption, or prover cycle-break) and extract
  its body/deps.
- #strong[why\_in\_plan]: given a literal and a plan, locate it in the
  wave-plan and trace a reverse-dependency path (via TriggersAVL) back
  to a root.
- #strong[why\_assumption]: given an assumption key, classify it (domain
  vs cycle-break vs model-only) and extract any reason tags.

== Usage
<usage-1>
All predicates are called with the `explainer:` module prefix.

=== Step 1: Obtain proof artifacts
<step-1-obtain-proof-artifacts>
Run the pipeline to get the proof, model, plan, and triggers:

```prolog
Goals = [portage://'dev-libs/openssl-3.5.4':run?{[]}],
pipeline:prove_plan_with_fallback(Goals, ProofAVL, ModelAVL, Plan, TriggersAVL).
```

Or from a `--shell` session after loading a repository:

```prolog
pipeline:prove_plan_with_fallback([portage://'dev-libs/openssl-3.5.4':run?{[]}],
                                  Proof, Model, Plan, Triggers).
```

=== Step 2: Ask "why" questions
<step-2-ask-why-questions>
#strong[Why is a package in the proof?]

```prolog
Target = portage://'dev-libs/libffi-3.5.2':install,
explainer:why_in_proof(ProofAVL, Target, Why).
% Why = why_in_proof(
%          portage://'dev-libs/libffi-3.5.2':install,
%          proof_key(rule(portage://'dev-libs/libffi-3.5.2':install)),
%          depcount(3),
%          body([portage://'sys-devel/gcc-15.2.0':install, ...]),
%          ctx([...]),
%          domain_reasons([...]))      % <-- added by explanation hook
```

#strong[Why is a package in the plan?]

```prolog
Proposal = [portage://'dev-libs/openssl-3.5.4':run?{[]}],
explainer:why_in_plan(Proposal, Plan, ProofAVL, TriggersAVL,
                      portage://'sys-libs/zlib-1.3.1-r1':install, Why).
% Why = why_in_plan(
%          portage://'sys-libs/zlib-1.3.1-r1':install,
%          location(step(1), portage://'sys-libs/zlib-1.3.1-r1':install?{...}),
%          required_by(path([portage://'sys-libs/zlib-1.3.1-r1':install,
%                           portage://'dev-libs/openssl-3.5.4':install,
%                           portage://'dev-libs/openssl-3.5.4':run])))
```

#strong[Why is something assumed?]

```prolog
Key = assumed(portage://'dev-foo/bar-1.0':install),
explainer:why_assumption(ModelAVL, ProofAVL, Key, Type, Why).
% Type = domain,
% Why  = why_assumption(
%          assumed(portage://'dev-foo/bar-1.0':install),
%          type(domain),
%          term(portage://'dev-foo/bar-1.0':install?{[assumption_reason(missing)]}),
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

== Assumption diagnosis
<assumption-diagnosis>
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
  [self(portage://'app-misc/foo-1.0')],         % Context
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
<further-reading-16>
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- assumption taxonomy that the explainer queries
- #link("08-doc-prover.md")[Chapter 8: The Prover] --- proof artifacts
  consumed by the explainer
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--search`, `--similar`, `--explain` flags

= Distributed Proving
<distributed-proving>
For testing purposes, the full Gentoo tree must be walked through the
resolver --- tens of thousands of ebuilds --- and even on capable
hardware that adds up. On a single machine,
`resolver:test_stats(portage)` typically finishes proving every single
ebuild in #strong[a few minutes] on a twenty-eight-core workstation ---
fast enough for day-to-day development, but not the only shape the
problem takes.

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
#figure(image("Diagrams/17-cluster-architecture.svg", width: 85.0%, alt: "Cluster architecture"),
  caption: [
    Cluster architecture
  ]
)

The diagram above shows the three roles. The #strong[server] is the
central hub: it holds the in-memory knowledge base, exposes an HTTP
interface via Pengines (described below), and multiplexes proof jobs
across workers through a job queue and result queue.

#strong[Workers] are symmetric compute nodes. Each worker carries its
own copy of the knowledge base and runs the full proving pipeline
locally. You can add as many workers as you need --- they scale
horizontally, and the server distributes work evenly.

The #strong[client] submits target packages and collects results. It
does not need the knowledge base itself; it talks to the server over
HTTPS and receives completed proofs as JSON.

=== Interaction flow
<interaction-flow>
#figure(image("Diagrams/17-cluster-flow.svg", width: 85.0%, alt: "Cluster interaction flow"),
  caption: [
    Cluster interaction flow
  ]
)

The numbered steps show how a proof request travels through the system:

#strong[Steps 1-3 (client to server).] The client sends a target package
(e.g.~`sys-apps/portage`) to the server over HTTPS. The server creates a
Pengine (a sandboxed Prolog engine) to handle the request and adds the
target to its job queue.

#strong[Steps 4-6 (worker loop).] Workers continuously poll the job
queue for work. When a worker picks up a job, it runs the full proving
pipeline locally --- proof search (resolving) and ordering --- using its
own copy of the knowledge base. When the proof is complete, the worker
posts the result back to the server.

#strong[Steps 7-8 (results back to client).] The server stores the
completed proof in its result queue. The client retrieves the result as
a JSON document over HTTPS.

=== Server
<server-1>
The server is the central coordination point. It runs an HTTP server
backed by SWI-Prolog's Pengines library and manages four things: the
knowledge base (the full Portage tree loaded in memory), a job queue of
proof targets waiting to be processed, a result queue of completed
proofs, and the Pengine sandbox that controls what remote callers can
execute.

=== Worker
<worker-1>
Each worker is an independent OS process with its own Prolog VM. On
startup it loads the knowledge base, then enters a poll loop: it asks
the server for the next job, runs the full pipeline (resolve and order),
and posts the result back. Workers are stateless between jobs, so you
can add or remove them at any time without affecting other workers or
the server.

=== Client
<client-1>
The client is a thin request layer. It does not carry the knowledge base
--- it simply submits target packages to the server and collects the
completed proofs. This makes it suitable for lightweight machines or
scripts that want to drive resolution remotely.

=== Cluster orchestration
<cluster-orchestration>
The cluster module sits above the individual roles and provides
high-level orchestration: distributing a batch of targets across
available workers, collecting results as they arrive, and handling
failures (retrying jobs that a worker did not complete).

== Pengines: Prolog as a network service
<pengines-prolog-as-a-network-service>
Pengines ("Prolog engines as a web service") is a library that ships
with SWI-Prolog. It turns Prolog query execution into an HTTP-friendly
protocol, and portage-ng uses it as the communication layer between
clients and the server.

When a client sends a proof request, the server does not run the query
in its main thread. Instead, it creates a #strong[Pengine] --- a fresh,
isolated Prolog engine dedicated to that interaction. The Pengine can
read the shared knowledge base (the Portage tree loaded in the server
process), but it runs inside a #strong[sandbox] that prevents it from
modifying the knowledge base or calling dangerous predicates. Remote
callers cannot reshape the server's state.

Answers are streamed back as JSON over HTTP. This means a client does
not need to be a full Prolog application --- any language that can make
HTTP requests and parse JSON can drive proof search. From the outside,
portage-ng looks like an ordinary web service that happens to do
dependency resolution internally.

== Repository state across modes
<repository-state-across-modes>
An important design question for distributed proving is: how does each
mode access the Portage tree? The answer is portage-ng's object-oriented
context system (see
#link("21-doc-contextual-logic-programming.md")[Chapter 21]). Each
repository is an instance created through that system, and methods like
`portage:read` populate the cache facts.

In #strong[server mode], repository instances live in the shared server
process. All Pengine threads see the same instances and the same loaded
knowledge --- one tree in memory, many sandboxes reading it.

In #strong[worker mode], each worker is a separate OS process with its
own Prolog VM. It creates its own repository instances and loads its own
copy of the knowledge base. Nothing is shared with the server's address
space.

The benefit is that the call sites are identical everywhere: the same
`portage:read` call appears in standalone, server, and worker code. The
object system dispatches to the right backing store depending on the
mode, so distributed proving does not require a separate set of
data-loading predicates.

== Client installed state: `--import-vdb`
<client-installed-state---import-vdb>
By default the server proves against its #strong[own] VDB (the in-memory
`pkg` repository loaded by its `kb:load`). For a remote client whose
installed set differs from the server's, that would produce wrong
`[nomerge]`, rebuild, and `replaces` decisions. The `--import-vdb`
client action closes this gap:

```console
$ portage-ng --mode client --import-vdb
```

The client parses its local VDB (`config:pkg_directory/1`, typically
`/var/db/pkg`) through the regular repository sync path, serializes the
resulting `cache:` facts as a Prolog term stream with a snapshot stamp
(entry count + content hash), and POSTs the payload to the authenticated
`/import-vdb` endpoint (same digest + client-certificate TLS as
`/sync`).

The server validates the payload (whitelisted fact shapes, sanitized
hostname, capped counts) and registers the facts atomically as a
per-client repository named `pkg@<clienthost>`, recording the stamp.

At prove time, every rule that consults the installed set goes through a
single accessor, `knowledgebase:vdb_repository/1`:

- In #strong[standalone], #strong[server], and #strong[worker] mode it
  resolves to the local `pkg` repository --- the behaviour is unchanged
  (the lookup is memoized per thread, so there is no hot-path cost).
- Inside a #strong[Pengine] serving a client request it resolves to that
  client's `pkg@<clienthost>` repository, using the repository name and
  import stamp the client ships with each RPC.

Stale or missing imports are loud, never silent: if a client has not
imported its VDB (or the stamp no longer matches what the server holds),
the server prints an explicit warning and falls back to its own `pkg`
repository, telling the user to (re-)run `--import-vdb`.

With `config:client_auto_import_vdb(true)` (the default) the import
happens automatically: before the first RPC of a client command
(`--pretend`, `--merge`, `--search`, …) the client re-imports its VDB
whenever no import record exists for the target server or the local VDB
changed since the last import. Freshness is detected with a cheap mtime
check over the VDB root and its category directories, so an up-to-date
import adds no noticeable overhead. Set the flag to `false` to ship the
VDB only on an explicit `--import-vdb`.

Filesystem-level VDB reads (CONTENTS listings, on-disk SIZE files,
binpkg live-VDB re-stat) can never work for a remote client; those paths
detect a per-client repository and degrade to the imported in-memory
snapshot, or are skipped. Worker mode is out of scope: workers load
their own knowledge base and assume a homogeneous fleet.

== mDNS/Bonjour discovery
<mdnsbonjour-discovery>
Workers and servers discover each other automatically via
#strong[mDNS/Bonjour] service advertisement, so there is no need to
hand-configure IP addresses.

#figure(image("Diagrams/17-bonjour-discovery.svg", width: 95.0%, alt: "Bonjour discovery flow"),
  caption: [
    Bonjour discovery flow
  ]
)

The discovery protocol has three steps:

+ #strong[Register] --- when the server starts, it advertises a
  `_portage-ng._tcp` service on the local network, making its hostname
  and port visible to any device on the same link.
+ #strong[Browse] --- workers browse for that service type and
  automatically receive the server's address and port.
+ #strong[Connect] --- a connection is established from the discovery
  data, with no manual configuration required.

This is the same zero-configuration networking mechanism used by
AirPrint, AirPlay, and many other network services.

=== Platform support
<platform-support>
On #strong[macOS], the `dns-sd` command ships with the system. The
`bonjour.pl` module uses `dns-sd -R` to register the service and
`dns-sd -B` to browse for peers.

On #strong[Linux], the same `dns-sd` command is available through
#strong[Avahi] (typically in the `avahi-utils` package). The `bonjour`
module hides the platform difference behind a single Prolog interface
(`subprocess:dns_sd/...`), so the rest of portage-ng does not need to
know which implementation is in use.

After discovery, all traffic is encrypted and mutually authenticated via
TLS (see the following sections).

== Sandbox and security
<sandbox-and-security>
Because Pengines allow remote Prolog execution, the server must control
what clients can do. The sandbox module
(`Source/Application/Security/sandbox.pl`) enforces a whitelist: only
predicates explicitly registered as safe via `sandbox:safe_primitive/1`
and `sandbox:safe_meta/2` can be called remotely. Everything else is
blocked.

A separate sanitise module (`Source/Application/Security/sanitize.pl`)
validates the structure of incoming queries before they reach the
sandbox, rejecting malformed or unexpected input early.

== TLS certificates
<tls-certificates>
All communication between server, workers, and clients is encrypted and
mutually authenticated using TLS. Mutual authentication means that
#strong[both sides] present a certificate during the handshake --- the
server proves its identity to the client, and the client proves its
identity to the server. This prevents unauthorized nodes from joining
the cluster.

=== Certificate hierarchy
<certificate-hierarchy>
portage-ng uses a private Certificate Authority (CA) that acts as the
trust root for the entire cluster. Every host-specific certificate is
signed by this CA, so any node holding the CA's public certificate can
verify any other node's identity.

#figure(image("Diagrams/17-cert-hierarchy.svg", width: 80.0%, alt: "Certificate hierarchy"),
  caption: [
    Certificate hierarchy
  ]
)

The CA is a self-signed RSA 4096-bit certificate valid for 10 years
(`CERT_DAYS=3650`). Each host receives two certificates signed by the
CA:

- A #strong[server certificate] --- presented when the host runs in
  `--mode server`. The Common Name (CN) is set to the hostname and the
  Organizational Unit (OU) to "Server".
- A #strong[client certificate] --- presented when the host connects to
  a server as a worker or client. The CN is the local hostname and the
  OU is "Client".

Both certificates use RSA 2048-bit keys and SHA-256 signatures.

=== File layout
<file-layout>
All certificate files live under the `Certificates/` directory at the
project root. The table below shows which files are tracked in git
(public certificates) and which are excluded (private keys):

#figure(
  align(center)[#table(
    columns: (30.77%, 38.46%, 30.77%),
    align: (left,center,left,),
    table.header([#strong[File]], [#strong[Tracked]], [#strong[Description]],),
    table.hline(),
    [`cacert.pem`], [Yes], [CA public certificate (shared trust root)],
    [`cakey.pem`], [No], [CA private key (never distributed)],
    [`<host>.server-cert.pem`], [Yes], [Server certificate for
    `<host>`],
    [`<host>.server-key.pem`], [No], [Server private key],
    [`<host>.client-cert.pem`], [Yes], [Client certificate for
    `<host>`],
    [`<host>.client-key.pem`], [No], [Client private key],
    [`passwordfile`], [No], [HTTP digest authentication passwords
    (`make passwordfile`)],
  )]
  , kind: table
  )

Private keys and the CA serial file are excluded via `.gitignore`. The
public certificates are committed so that nodes can verify each other
without manual file copying --- only the shared `cacert.pem` needs to be
distributed out-of-band.

=== Mutual TLS handshake
<mutual-tls-handshake>
When a worker or client connects to the server, a mutual TLS handshake
takes place. Both sides verify the other's certificate against the
shared CA before any data is exchanged.

#figure(image("Diagrams/17-tls-handshake.svg", width: 80.0%, alt: "Mutual TLS handshake"),
  caption: [
    Mutual TLS handshake
  ]
)

The handshake proceeds in five steps:

+ The #strong[server] presents its server certificate
  (`server.local.server-cert.pem`), signed by the CA.
+ The #strong[worker] verifies this certificate against its local copy
  of `cacert.pem`. If verification fails (wrong CA, expired, CN
  mismatch), the connection is refused.
+ The #strong[worker] presents its client certificate
  (`worker.local.client-cert.pem`), also signed by the same CA.
+ The #strong[server] verifies this certificate against its own
  `cacert.pem`. This step is what makes the authentication #emph[mutual]
  --- the server confirms the worker is a legitimate cluster member, not
  just any TLS client.
+ Both sides accept the connection and begin encrypted communication.

On the server side, the TLS context is configured in
`server:start_server` with `peer_cert(true)` to require client
certificates, and `cacerts([file(CaCert)])` to set the trust anchor. On
the client/worker side, `client:rpc_execute` configures the same CA and
presents the local client certificate.

An additional layer of security is provided by #strong[HTTP digest
authentication] (`passwordfile`), so even a node with a valid
certificate must also know the correct username and password. Set the
plaintext once in `Source/Config/Private/passwords.pl`, then derive the
hashed server file (it is not committed):

```bash
cp Source/Config/Private/template_passwords.pl \
   Source/Config/Private/passwords.pl
# edit config:digest_password/2
make passwordfile
```

Ship the same `passwords.pl` to every client and worker.

=== How certificates are resolved at runtime
<how-certificates-are-resolved-at-runtime>
Certificate paths are computed at runtime by `config:certificate/2` and
`config:certificate/3`. Given a certificate name like `server-cert.pem`,
the predicate prepends the installation directory and `Certificates/` to
form the full path. For host-specific certificates, the hostname is
prepended to the filename (e.g.~`mac-pro.local.server-cert.pem`).

When TLS files are missing, both `server:require_tls_files/4` and
`client:require_tls_files/4` print an error message listing the expected
file paths and the `make certs` command needed to generate them.

== Generating certificates
<generating-certificates>
To generate a full set of certificates for a host:

```bash
make certs HOST="$(hostname)"
```

If your hostname includes a `.local` suffix (common on macOS), pass the
full name so it matches `config:hostname/1`:

```bash
make certs HOST="mac-pro.local"
```

This runs `Certificates/Scripts/generate.sh`, which creates three
things:

+ A #strong[self-signed CA] (`cacert.pem` + `cakey.pem`) --- created
  only if it does not already exist, so adding a second host reuses the
  same CA.
+ A #strong[server certificate and key] signed by that CA, with the
  hostname embedded as the Common Name (CN).
+ A #strong[client certificate and key] signed by the same CA.

=== Checking and renewing
<checking-and-renewing>
Certificates are valid for 10 years, but the generation script also
supports health checks and renewal:

```bash
make certs-check                # show expiry status for all hosts
make certs-renew                # renew certs expiring within 30 days
```

The `--check` subcommand prints each certificate's expiry date and flags
any that are missing or expiring soon. The `--renew` subcommand
regenerates only the certificates that need it, reusing the existing CA
and private keys.

== Encrypted two-node cluster: step-by-step
<encrypted-two-node-cluster-step-by-step>
The following walkthrough shows how to set up a minimal cluster with one
server and one worker on a local network.

#strong[Step 1 --- Generate certificates on each machine.]

On the server host (e.g.~`server.local`):

```bash
make certs HOST="server.local"
```

On the worker host (e.g.~`worker.local`):

```bash
make certs HOST="worker.local"
```

Each machine now has its own certificate and key, signed by a locally
created CA.

#strong[Step 2 --- Share the trust root.]

By default, each machine creates its own CA. For mutual authentication
to work, all nodes must trust the same CA. Copy `cacert.pem` from the
server to the worker (or designate one machine as the cluster CA and
distribute its `cacert.pem` to all nodes). Each node keeps its own
host-specific certificate and key.

#strong[Step 3 --- Start the server.]

```text
portage-ng --mode server
```

The server loads the knowledge base and listens on
`config:server_bind/1`:`config:server_port/1` (default
#strong[localhost:4000]). Mutating POSTs (`/sync`, `/clear`, `/load`, …)
therefore stay off the public network. Widen the bind
(`config:server_bind(*)`) only on a trusted VPN/LAN --- with a shared
cluster CA, mTLS alone is not a strong gate; digest + bind scope are.

#strong[Step 4 --- Start the worker.]

```text
portage-ng --mode worker --host server.local
```

Prefer an explicit `--host` (or a matching `config:server_host/1` pin).
Bonjour discovery is allowed only as a convenience lookup that still
must match that pin --- the worker never connects to the first untrusted
advertisement on a hostile LAN.

Before tree sync, fetch the portage git objects from your
#strong[trusted remote] (not from the Pengine server). The server
advertises a full commit SHA; the worker checks it out only when that
object already exists locally (`git cat-file -e`). There is no
fetch-from-server path.

#strong[Step 5 --- Discovery (optional).]

If mDNS/Bonjour is available, the worker may resolve `_portage-ng._tcp`
advertisements, but only a host that matches `config:server_host/1` is
accepted.

#strong[Step 6 --- Mutual TLS handshake.]

When the worker connects, both sides present certificates signed by the
shared CA. portage-ng verifies the Common Name and role, so only nodes
with valid credentials can join the cluster. Digest auth is still
required on top of mTLS.

#strong[Step 7 --- Proving.]

The worker polls the server's job queue, runs the full proving pipeline
for each target, and posts results back. The server collects completed
proofs and makes them available to clients.

== Cluster usage
<cluster-usage>
To run a distributed cluster, every node needs two things:

- A copy of the same `cacert.pem` (the shared trust root).
- Its own host-specific certificate and key pair.

The server is started with `--mode server`, and each worker with
`--mode worker --host <pinned-server>`. Pin `config:server_host/1` on
workers; Bonjour is only a lookup aid against that pin. TLS ensures
peers share the same CA, and digest auth supplies the shared secret. You
can add more workers at any time --- they connect to the pinned server
and start picking up jobs immediately.

== Further reading
<further-reading-17>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- dns-sd and openssl prerequisites
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--mode` flags
- #link("04-doc-architecture.md")[Chapter 4: Architecture Overview] ---
  module load order for different modes

= Upstream and Bug Tracking
<upstream-and-bug-tracking>
portage-ng integrates with external services to check upstream versions
and search for known issues, helping users identify outdated packages
and known dependency bugs.

== Git repository integration
<git-repository-integration>
portage-ng can connect directly to a Git repository and turn Git
metadata into Prolog facts. This means it can inspect commit history,
changelogs, and file-level changes for any ebuild without relying on
separate tools. The Git metadata is ingested alongside the regular cache
data, so queries like "when was this ebuild last updated?" or "which
ebuilds changed in the last sync?" can be answered from within the
resolver.

== Upstream version checking
<upstream-version-checking>
The upstream module (`Source/Domain/Gentoo/upstream.pl`) checks package
versions against upstream releases via the Repology API.

=== Usage
<usage-2>
```bash
portage-ng --upstream sys-apps/portage
portage-ng --upstream @world
```

=== How it works
<how-it-works-2>
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
<usage-3>
```bash
portage-ng --bugs sys-apps/portage
```

=== How it works
<how-it-works-3>
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

== Bug report drafts from build-time discoveries
<bug-report-drafts-from-build-time-discoveries>
The prover-driven drafts above are generated at plan time from
unsatisfiable dependencies. A second source of drafts comes from the
#strong[missing-provider feedback loop] (portage-ng\#102): when a build
fails because of an #emph[undeclared] build dependency --- a command,
header, library, or pkg-config module the ebuild needed but never listed
in `BDEPEND` --- the builder records the discovery and re-derives a plan
that supplies it (see
#link("16-doc-building.md#missing-provider-feedback")[Chapter 16: Missing provider feedback]).

Because every discovery carries structured evidence --- the missing
symbol, the phase it surfaced in, the exit code, and the offending log
line --- the printer proposes a bug report draft at the end of the build
for each dependency worked around this session:

```
>>> Missing build dependencies discovered (bug report drafts)

---
Summary: sec-policy/selinux-base: missing BDEPEND=sys-apps/semodule-utils (command semodule_package not found)

Affected package: portage://sec-policy/selinux-base
Missing dependency: sys-apps/semodule-utils (build-time / BDEPEND)
Observed:
  command semodule_package not found during the compile phase (exit 127):
    semodule_package: command not found
Potential fix (suggestion):
  Add BDEPEND="sys-apps/semodule-utils" to the ebuild or the responsible inherited eclass.
  (discovered by portage-ng missing-provider feedback, portage-ng#102)
```

Unlike the prover-driven drafts (which report a dependency that
#emph[cannot] be satisfied), these report a dependency that #emph[was]
satisfied once portage-ng learned it --- so the draft is a ready-to-file
"add `BDEPEND=<provider>`" fix against the ebuild or its inherited
eclass. Both kinds of draft are gated by
`config:bugreport_drafts_enabled/1`.

== Further reading
<further-reading-18>
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--upstream` and `--bugs` flags
- #link("09-doc-prover-assumptions.md")[Chapter 9: Assumptions and Constraint Learning]
  --- how unsatisfiable dependencies are detected
- #link("16-doc-building.md")[Chapter 16: Building and Execution] ---
  the missing-provider feedback loop that produces build-time bug drafts
- #link("20-doc-glsa.md")[Chapter 20: Gentoo Linux Security Advisories (GLSA)]
  --- security advisories and `@security` remediation sets

= Gentoo Linux Security Advisories (GLSA)
<gentoo-linux-security-advisories-glsa>
Gentoo publishes #strong[GLSAs] --- XML advisories that describe which
package versions are vulnerable and which versions are safe. Traditional
Portage exposes them mainly through `glsa-check` and the `@security`
package set. portage-ng treats the same advisories as a
#strong[first-class knowledge artifact]: parsed into Prolog facts,
optionally qcompiled for fast reload, queryable from the shell, and
expanded into ordinary remediation atoms that the existing prove/plan
pipeline consumes unchanged.

== Design choice: knowledge, not a repository
<design-choice-knowledge-not-a-repository>
A natural first idea is to register GLSAs as another
`repository://entry` and search them with `query:search`. That fights
the architecture.

Package repositories (`portage`, `pkg`, `binpkg`) identify entries by
#strong[CPVN] --- category, package name, and `version/7` --- via
`cache:ordered_entry/5`. Every prover, orderer, and rules consumer
assumes that shape. A GLSA id such as `202501-03` is not a package
version; inventing a fake `glsa://…` CPVN would either pollute those
paths or require permanent exclusion filters.

Non-package knowledge already lives outside the package-repo model:

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([Concern], [Pattern],),
    table.hline(),
    [Profile], [Own facts + `Knowledge/profile.qlf`],
    [News], [Filesystem read (display-only)],
    [Named / computed sets], [`preference:set/2` / `sets:expand/2`],
  )]
  , kind: table
  )

#strong[GLSAs follow the profile pattern:] a sibling knowledge store
with its own facts and cache file, plus a small query surface. Package
repos stay the only `Repo://Entry` units. Security sets are a
#emph[view] over that store, not the primary API.

```
  metadata/glsa/*.xml
        │
        ▼
  glsa:cache_save  ──────►  Knowledge/glsa.qlf
        │
        ▼
  glsa:advisory / package / range facts
        │
        ├── glsa:search/2          (advisory queries)
        ├── query:search bridges   (vulnerable/1, glsa/1 on pkg entries)
        └── sets:expand/2          (@security → =cat/pkg-ver atoms)
                                        │
                                        ▼
                              prove_plan_with_fallback
```

== On-disk source and cache
<on-disk-source-and-cache>
Advisories live in the Portage tree at `$PORTDIR/metadata/glsa/` as
files named `glsa-YYYYMM-NN.xml`. Override the directory with
`config:glsa_dir/1` when needed.

During `--sync`, portage-ng calls `glsa:cache_save/0` next to
`profile:cache_save/0`. That walk:

+ Parses every `glsa-*.xml` (DTD-safe string extraction --- no network
  DTD fetch, same rule as `metadata.xml` maintainers).
+ Writes `Knowledge/glsa.raw` and qcompiles `Knowledge/glsa.qlf`.
+ Loads the facts into the running process.

At runtime, `glsa:ensure_loaded/0` prefers the qlf cache and falls back
to a live parse of `metadata/glsa/` when the cache is missing. Cold live
parse of a full tree (\~3.8k advisories) is well under a second; qlf
reload is near-instant.

Parsing skips non-`ebuild` product types and tolerates individual
malformed files so one bad advisory never aborts `@security` or sync.

== Fact schema
<fact-schema>
The hot store is three dynamic predicates (also serialized into the
`glsadata` module inside `glsa.qlf`):

```prolog
glsa:advisory(Id, Title).
glsa:package(Id, Category, Name, ArchSpec).
glsa:range(Id, Category, Name, Kind, Op, Version, Slot).
```

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([Field], [Meaning],),
    table.hline(),
    [`Id`], [Advisory id (`'202501-03'`)],
    [`Kind`], [`vulnerable` or `unaffected`],
    [`Op`], [GLSA range token: `le`, `lt`, `eq`, `gt`, `ge`, `rge`,
    `rle`, `rgt`, `rlt`],
    [`Version`], [Bound as a `version/7` term],
    [`Slot`], [Slot atom, or `*` for any],
    [`ArchSpec`], [`*` or a space-separated arch list],
  )]
  , kind: table
  )

Synopsis and body text are intentionally omitted from the hot store; set
expansion and vulnerability checks only need package/range rows. A
future dump/CLI can add richer fields without changing the set path.

== Matching installed packages
<matching-installed-packages>
Vulnerability is decided by joining advisory ranges against the
#strong[VDB] (installed packages) and the #strong[tree] (visible
upgrades):

+ #strong[ARCH] --- `*` always matches; otherwise the host arch from
  `userconfig:current_arch/1` (or `ARCH` / `ACCEPT_KEYWORDS`) must
  appear in the package's arch list. Unknown arch ⇒ only `*` matches
  (conservative).
+ #strong[Vulnerable range] --- installed version matches a `vulnerable`
  range for that C/N/slot.
+ #strong[Not unaffected] --- the same installed version must #emph[not]
  match an `unaffected` range.
+ #strong[Upgrade exists] --- a visible tree ebuild in the same slot
  matches an `unaffected` range and is greater than the installed
  version. Among such upgrades, portage-ng picks the
  #strong[least-change] (lowest) version, matching Portage's
  `getMergeList(least_change=true)`.

Ordinary comparisons (`le`/`lt`/`eq`/`gt`/`ge`) use
`eapi:version_compare/3` on `version/7` terms. Revision-limited ops
(`rge`/`rle`/`rgt`/`rlt`) require the same base version and compare only
the revision field --- Portage's `revisionMatch` semantics.

Remediation atoms are exact pins: `=category/name-version`. Those atoms
enter the normal target rules; the prover is not GLSA-aware.

== Security computed sets
<security-computed-sets>
Portage's `sets.conf` defaults `@security` to `NewAffectedSet`.
portage-ng registers four computed set names in
`Source/Domain/Gentoo/Preference/sets.pl`:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([Set], [Portage class], [Meaning],),
    table.hline(),
    [`@security`], [`NewAffectedSet` (default)], [Vulnerable installs
    from GLSAs not yet applied],
    [`@new-affected`], [`NewAffectedSet`], [Same, explicit name],
    [`@affected`], [`AffectedSet`], [Vulnerable installs, including
    applied GLSAs],
    [`@new-glsa`], [`NewGlsaSet`], [Unapplied GLSAs (atoms still only
    appear when an upgrade exists)],
  )]
  , kind: table
  )

Related non-GLSA computed sets live in the same registry
(`Preference/sets.pl`); see
#link("15-doc-cli.md#package-sets")[Chapter 15: CLI --- Package sets]
for the full table (`@preserved-rebuild`, `@changed-deps`, `@installed`,
…).

Expansion is #strong[VDB-driven]: walk installed packages, look up
matching advisory rows, emit upgrade atoms, then reduce per
`cat/name:slot` to the highest remediation version (Portage `_reduce`).
This stays near- linear in installed CPV count rather than scanning
every advisory for `is_vulnerable`.

```bash
portage-ng --mode standalone --pretend @security
portage-ng --mode standalone --list-sets   # includes security sets
```

When no installed package is vulnerable (or every matching GLSA is
already injected), `@security` expands to the empty list and the CLI
reports that the set is empty --- exit 0, not a hard failure.

== Applied / injected tracking
<applied-injected-tracking>
Portage records applied GLSA ids in
`$EROOT/var/lib/portage/glsa_injected`. portage-ng mirrors that with
`config:glsa_injected_file/1` (default:
`Source/Knowledge/Sets/glsa_injected/<hostname>`).

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([Predicate], [Role],),
    table.hline(),
    [`glsa:applied(+Id)`], [True when `Id` is listed in the inject
    file],
    [`glsa:inject(+Id)`], [Append `Id` if not already present],
  )]
  , kind: table
  )

`NewAffectedSet` / `NewGlsaSet` filters consult this file. A dedicated
`glsa-check`-style inject CLI is not required for set expansion; the
predicates are ready for a thin follow-up action.

== Query surface
<query-surface>
=== Advisory search --- `glsa:search/2`
<advisory-search-glsasearch2>
```prolog
glsa:search([package('dev-python', pip), applied(false), vulnerable(true)], Id).
glsa:search(title(Title), Id).
```

Accepted constraints: `id/1`, `title/1`, `package/2`, `applied/1`,
`vulnerable/1`. Queries run against `glsa:*` facts (and VDB joins for
`vulnerable`), not against `cache:ordered_entry`.

=== Package bridges --- `query:search`
<package-bridges-querysearch>
Two compile-time sugar keys join advisories onto an existing
`Repo://Entry` (typically the VDB):

#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([Query], [Meaning],),
    table.hline(),
    [`vulnerable(true)`], [Some non-filtered GLSA covers this installed
    entry and an upgrade exists],
    [`glsa(Id)`], [Advisory `Id` covers this entry's C/N/version/slot],
  )]
  , kind: table
  )

```prolog
?- knowledgebase:vdb_repository(V),
   query:search([vulnerable(true), category(C), name(N)], V://E).
```

These bridges do #strong[not] invent `glsa://` entries. Prefer
`glsa:search/2` inside set logic so the package query hot path stays
free of advisory scans unless asked.

== Module map
<module-map>
#figure(
  align(center)[#table(
    columns: (50%, 50%),
    align: (left,left,),
    table.header([File], [Role],),
    table.hline(),
    [`Source/Domain/Gentoo/glsa.pl`], [Parse, facts, cache, match,
    search, set atoms],
    [`Source/Domain/Gentoo/Preference/sets.pl`], [Registers `@security`
    and siblings],
    [`Source/Knowledge/query.pl`], [`vulnerable/1` and `glsa/1`
    bridges],
    [`Source/Application/Interface/Action/sync.pl`], [Calls
    `glsa:cache_save` during `--sync`\; lists computed sets],
    [`Source/config.pl`], [`config:glsa_dir/1`,
    `config:glsa_injected_file/1`],
  )]
  , kind: table
  )

Loaded with the domain modules (`loader:group(domain_modules)`), after
preference and before `sets.pl`.

== What this is not
<what-this-is-not>
- #strong[Not a package repository.] No `kb:register(glsa)`, no GLSA
  rows in `kb.qlf`.
- #strong[Not prover logic.] No new rules, assumptions, or fallback
  tiers. Remediations are ordinary `=cpv` targets.
- #strong[Not a full `glsa-check` clone (yet).] List/dump/mail/fix modes
  can wrap the same facts later; set expansion and search are the v1
  surface.
- #strong[Not network-fetched.] Advisories arrive with the tree after
  the user runs `--sync`.

== Further reading
<further-reading-19>
- #link("06-doc-knowledgebase.md")[Chapter 6: Knowledge Base and Cache]
  --- package `kb.qlf` vs sibling caches such as `profile.qlf` /
  `glsa.qlf`
- #link("03-doc-configuration.md")[Chapter 3: Configuration] --- sync,
  profile cache, and host-local paths
- #link("15-doc-cli.md")[Chapter 15: Command-Line Interface] ---
  `--pretend`, `--list-sets`, target `@set` syntax
- #link("10-doc-version-domains.md")[Chapter 10: Version Domains] ---
  `version/7` comparison used by GLSA range matching
- Portage reference: `lib/portage/glsa.py`,
  `lib/portage/_sets/security.py`

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
as feature terms describing software configurations --- directly
connecting to Zeller's #emph[Unified Versioning through Feature Logic].
This makes #strong[context] both a software engineering tool and a
formal foundation for reasoning about configurations.

In practical terms, this is how portage-ng can treat a Portage tree, an
overlay, and a VDB as separate objects that share the same interface but
carry independent state --- and how dependency contexts can be merged,
intersected, and propagated through the proof tree.

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
cloned, and composed dynamically --- which portage-ng uses extensively
to represent repositories, ebuilds, and configurations as live objects.

== Core concepts
<core-concepts>
=== Contexts
<contexts>
A context groups together clauses of a Prolog application. By default,
clauses are local to their context and invisible to other contexts
unless explicitly exported. Referencing a context is enough to create it
(creation ex nihilo).

Context rules are evaluated in the context in which they are defined. An
exception are clauses declared as "transparent", which inherit their
context from the predicate that is calling them --- the same mechanism
SWI-Prolog uses for meta-predicates, but applied at the context level.

=== Classes
<classes>
A class is a special context that declares public, protected, and
private meta-predicates. These declarations control access at three
levels:

- #strong[Instantiation] --- which predicates are copied into the
  instance and how they are guarded.
- #strong[Inheritance] --- which predicates are visible to subclasses.
  Private predicates are not inherited; public and protected ones are.
- #strong[Invocation] --- which predicates external callers may use.
  Only public predicates can be called from outside; protected and
  private predicates throw a `permission_error` if accessed without a
  valid access token.

A class is declared with `:- class.` (or `:- class([Parent1, Parent2])`
for multiple inheritance). Predicate visibility is declared with
`:- dpublic(name/1).`, `:- dprotected(age/1).`, and
`:- dprivate(secret/1).`

=== Instances
<instances>
Instances are dynamically created from a class via `newinstance/1`. The
creation process has four stages:

+ #strong[Metadata registration] --- the instance is marked as
  `type(instance(Parent))` in its `$__meta` store.
+ #strong[Predicate inheritance] --- all declared predicates from the
  parent class are copied. Each predicate is wrapped in a #strong[guard]
  that checks an access token before execution.
+ #strong[Freeze] --- the generated predicates are compiled via
  `compile_predicates/1` for optimal performance (no more interpretation
  overhead).
+ #strong[Constructor call] --- if the class declares a constructor
  predicate (same name as the class), it is called with the arguments
  passed to `newinstance/1`.

#figure(image("Diagrams/19-class-instance.svg", width: 55.0%, alt: "Class and instance lifecycle"),
  caption: [
    Class and instance lifecycle
  ]
)

Each instance is a fully independent Prolog module with its own dynamic
facts. Multiple instances of the same class coexist without interference
--- for example, `portage` and `overlay` are both instances of the
`repository` class, but each carries its own cached ebuilds, location
paths, and sync state.

=== Destruction
<destruction>
An instance is destroyed by calling `~Instance`. The destructor (if
declared) runs first, then all dynamic predicates in the instance module
are abolished. Static contexts (built-in Prolog modules) cannot be
destroyed --- attempting to do so raises a `permission_error`.

=== Access control and thread safety
<access-control-and-thread-safety>
The access control mechanism uses #strong[thread-local tokens]. When an
external caller invokes a public predicate on an instance, the system
asserts a `$_token(thread_access)` fact in the instance's module. The
guarded implementations of protected and private predicates check for
this token:

- #strong[Public] --- the token is asserted before the call and
  retracted afterwards (via `call_cleanup`). Any code called during the
  public predicate's execution can access protected and private
  predicates because the token exists.
- #strong[Protected] --- the guard checks that the token exists. If it
  does (i.e.~the call originates from a public predicate on the same
  instance), execution proceeds. Otherwise, a `permission_error` is
  thrown.
- #strong[Private] --- same check as protected. The difference is
  conceptual: private predicates are not inherited by subclasses, while
  protected ones are.
- #strong[Static] --- the call is forwarded to the parent class
  directly, bypassing the instance.

Because the token is `thread_local`, concurrent threads can call public
predicates on the same instance without interfering with each other's
access grants.

== Operators
<operators>
#strong[context] defines several operators for interacting with
contexts. The diagram below shows how they relate to an instance's
internal structure:

#figure(image("Diagrams/19-operators.svg", width: 80.0%, alt: "Context operators"),
  caption: [
    Context operators
  ]
)

#figure(
  align(center)[#table(
    columns: 2,
    align: (left,left,),
    table.header([#strong[Operator]], [#strong[Meaning]],),
    table.hline(),
    [`:Pred`], [Call `Pred` in the current context (self-call)],
    [`::Pred`], [Read a cached data member],
    [`<=Pred`], [Set a data member (evaluate, retract old, assert new)],
    [`<+Pred`], [Add a data member (evaluate, assert if not exists)],
    [`<-Pred`], [Remove a data member],
    [`Ctx://Pred`], [Call `Pred` in a specific context],
  )]
  , kind: table
  )

=== Data members
<data-members>
The `::`, `<=`, `<+`, and `<-` operators implement data-member-like
behaviour. Under the hood, they work with `$__meta(cache(...))` facts:

- #strong[`Ctx::Pred`] --- looks up `cache(Pred)` in the instance's
  metadata. If found, calls the predicate (which succeeds immediately
  because the cached value has already been evaluated). This is a
  #strong[read] operation.
- #strong[`Ctx<=Pred`] --- evaluates `Pred` in the instance, retracts
  any existing cache for the same functor/arity, and asserts the new
  result. This is a #strong[write-replace] operation.
- #strong[`Ctx<+Pred`] --- evaluates `Pred` and asserts the result as a
  new cache entry without removing existing ones. This is an
  #strong[append] operation, useful for multi-valued data members.
- #strong[`Ctx<-Pred`] --- retracts all cache entries matching `Pred`.
  This is a #strong[delete] operation.

=== The `://` operator
<the-operator>
The `://` operator is the primary way to call a predicate in another
context. It is defined simply as
`'://'(Context, Predicate) :- Context:Predicate.` --- a thin wrapper
that resolves the context module and dispatches the call. This operator
appears throughout portage-ng in forms like `portage://entry(E)` or
`kb://query(Q, R)`.

== Example: a Person class
<example-a-person-class>
A complete worked example of a context class --- including a
constructor, destructor, public/protected/private members, and instance
creation --- is presented in
#link("01-doc-introduction.md")[Chapter 1, section 1.7]. The example
defines a `person` class with name and age accessors, title management,
and demonstrates how instances carry their own state independently.

== How portage-ng uses context
<how-portage-ng-uses-context>
portage-ng uses #strong[context] throughout its architecture. The
diagram below shows the two main classes (`repository` and
`knowledgebase`), their instances, and how the prover accesses them.

#figure(image("Diagrams/19-portage-usage.svg", width: 80.0%, alt: "portage-ng context usage"),
  caption: [
    portage-ng context usage
  ]
)

=== Repository instances
<repository-instances>
The `repository` class (`Source/Knowledge/repository.pl`) declares a
rich public interface for working with package repositories: syncing
from remote sources, reading metadata, querying entries, and generating
graphs. Protected members hold configuration (location, cache path,
remote URL, sync protocol).

Each repository on disk becomes a named instance:

- #strong[`portage`] --- the main Gentoo Portage tree (30,000+ ebuilds),
  synced via git, with md5-cache metadata.
- #strong[`pkg`] --- the VDB (installed packages) at `/var/db/pkg`, a
  local read-only repository.
- #strong[`overlay`] --- a local overlay with custom ebuilds.
- #strong[`distfiles`] --- the source archive download cache.

Instance creation and configuration happens in the host-specific config
file (e.g.~`Source/Config/mac-pro.local.pl`):

```prolog
:- portage:newinstance(repository).
:- portage:init('/Volumes/Storage/Repository/portage-git',
                '/Volumes/Storage/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo/gentoo.git',
                'git', 'eapi').

:- pkg:newinstance(repository).
:- pkg:init('/Volumes/Storage/Repository/pkg', '', '', 'local', 'vdb').
```

Because all instances share the same class, the prover does not need to
know whether a dependency comes from the main tree, an overlay, or the
VDB --- the same `Repo://entry(E)` call works for all of them.

=== Knowledge base instance
<knowledge-base-instance>
The `knowledgebase` class (`Source/Knowledge/knowledgebase.pl`) acts as
a registry. Its `register/1` predicate adds repository instances, and
its `query/2` predicate searches across all registered repositories. The
instance `kb` is created at startup and populated by the configuration
file.

In #strong[client mode], the knowledge base instance is created with a
hostname and port: `kb:newinstance(knowledgebase(Host, Port))`. This
switches the instance into proxy mode, where queries are forwarded to
the remote server via Pengine RPC --- but the calling code sees the same
`kb://query(Q, R)` interface as in standalone mode.

=== Context terms in the prover
<context-terms-in-the-prover>
Beyond the OOP use, the context system's unification semantics flow into
the prover. Every literal in the proof tree carries a context list
`?{[...]}` that accumulates constraints as the proof deepens. These
context terms are merged via feature unification --- the same algebraic
operation that the context system uses for its data members. This
connection is explored in detail in
#link("22-doc-context-terms.md")[Chapter 22: Context Terms and Feature Unification].

== Serialization
<serialization>
Context instances support serialization through the knowledge base's
`save` and `load` predicates. When `kb://save` is called, the cached
facts from all registered repository instances are written to a QLF file
(`Knowledge/kb.qlf`). On the next startup, `kb://load` reads the
compiled file back, restoring all repository instances to their previous
state without re-parsing the Portage tree from disk. This is what makes
portage-ng's startup fast --- the full knowledge base (30,000+ ebuilds
with all metadata) loads from the QLF file in under a second.

== Further reading
<further-reading-20>
- A. Zeller, #emph[Unified Versioning through Feature Logic], 1997
- #link("../Source/Logic/context.pl")[`Source/Logic/context.pl`] ---
  full implementation
- #link("22-doc-context-terms.md")[`Documentation/Handbook/22-doc-context-terms.md`]
  --- how context terms flow through the prover

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
    [Plain term], [`self(R://E)`], [Identity match; duplicates dropped],
    [Feature:Value], [`build_with_use:use_state(En,Dis)`], [Value-merged
    by `val_hook/3`],
    [Feature:Compound], [`slot(C,N,Ss):{...}`], [Compound feature key],
  )]
  , kind: table
  )

For example, `self(portage://sys-apps/portage-3.0.77-r3)` is a plain
term that identifies the parent ebuild.
`build_with_use:use_state([foo],[bar])` is a Feature:Value pair whose
value is merged when two contexts meet.
`slot(sys-apps,portage,0/0):{Candidate}` is a compound feature key used
for sub-slot rebuild tracking.

=== Common context tags
<common-context-tags>
The following tags appear most frequently in proof-term contexts. Each
tag is a Prolog term added to the context list during rule evaluation.

#strong[`self(Repo://Entry)`] --- set by
`dependency:add_self_to_dep_contexts`. Identifies the parent ebuild that
introduced this dependency edge.

#strong[`build_with_use:use_state(En,Dis)`] --- set by
`dependency:process_build_with_use`. Carries bracketed USE constraints
from the dependency atom (e.g.~`dev-libs/foo[bar,-baz]`).

#strong[`slot(C,N,Ss):{Candidate}`] --- set by
`dependency:process_slot`. Records a slot lock from `:=` (subslot
rebuild) semantics.

#strong[`after(Literal)`] --- seeded at world-set anchors
(`world(Arg):register?{[after(Repo://Ebuild:run)]}`) and propagated into
dependency contexts by `featureterm:add_after_to_dep_contexts`. Ordering
hint: this subtree should come after `Literal` in the plan. Propagates
to children.

#strong[`after_only(Literal)`] --- injected on PDEPEND edges (via
`featureterm:add_after_only_to_dep_contexts`). Becomes an `order_after`
soft preference honored by the pass-2 orderer; does #strong[not]
propagate to children.

#strong[`replaces(pkg://Entry)`] --- set by install/update rules.
Records which installed package this action replaces.

#strong[`assumption_reason(Reason)`] --- set by the domain assumption
fallback. Records why a domain assumption was made (e.g.~`missing`,
`masked`, `keyword_filtered`).

#strong[`suggestion(Type[, Detail...])`] --- set by the relaxation
fallback. Records an actionable suggestion; arity varies with the
suggestion type (e.g.~`suggestion(unmask)`,
`suggestion(accept_keyword, Kw)`,
`suggestion(use_change, Ebuild, Changes)`).

#strong[`domain_reason(cn_domain(C,N,Tags))`] --- set by
`cnselect:add_domain_reason_context/5`. Diagnostic tags for version
domain narrowing.

#strong[`constraint(cn_domain(C,N,Slot):{Domain})`] --- set by the
constraint system. Carries an inline per-slot constraint for domain
scoping.

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
       │                                 build_with_use:use_state([ssl,threads],[])}
       │    └─ dep(dev-libs/openssl):install?{self(portage://dev-lang/python-3.13),
       │                                       build_with_use:use_state([],[])}
       └─ dep(app-arch/tar):install?{self(portage://sys-apps/portage-3.0.77-r3)}
```

\(Had the goal been seeded from a world-set anchor ---
`world(Arg):register?{[after(Repo://Ebuild:run)]}` --- an `after/1`
marker would additionally flow down every dependency edge.)

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
  `featureterm:drop_build_with_use_and_assumption_reason/2`).

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
featureterm:strip_planning(Context0, Context)
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

=== Post dependencies
<post-dependencies>
On PDEPEND edges, `build_with_use` is dropped because PDEPEND
dependencies are resolved at runtime, not build time, so build-time USE
constraints do not apply.

== Constraints vs contexts
<constraints-vs-contexts>
The proof system uses two complementary mechanisms for carrying
information, and it is easy to confuse them. #strong[Contexts] are
local: each literal in the proof carries its own context list
(`?{...}`), recording where it came from, what USE flags were requested,
and how it should be ordered. #strong[Constraints] are global: they live
in a shared ConstraintsAVL that spans the entire proof and track
cross-cutting invariants like "only one version of this package may be
selected" or "this package is blocked by another."

The table below summarises the key differences:

#figure(image("Diagrams/20-context-vs-constraint.svg", alt: "Context vs constraint interaction"),
  caption: [
    Context vs constraint interaction
  ]
)

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
Although contexts and constraints have different scopes, they are not
isolated --- information flows between them in both directions.

#strong[From context to constraint.] When the rules layer selects a
candidate version for a dependency, it emits constraint terms into the
global ConstraintsAVL. For example, selecting `dev-libs/openssl-3.1.4`
produces a `selected_cn(dev-libs, openssl)` constraint and a `cn_domain`
constraint recording the version domain. These global constraints ensure
that if another dependency path also needs `dev-libs/openssl`, the
prover will detect any conflict.

#strong[From constraint to context.] Sometimes a parent dependency wants
to narrow the version domain for a child before candidate selection even
begins. It does this by placing an inline constraint term like
`constraint(cn_domain(C,N,Slot):{Domain})` directly in the context list.
When the child's rule fires, it reads this term and applies the domain
restriction.

#strong[Constraint guards.] After each new constraint is merged into the
global store, `heuristic:constraint_guard/2` fires to check consistency.
The guard verifies that version domains are compatible with selected
candidates, that each slot has at most one selected version, and that no
selected package is blocked by another.

#strong[Constraint learning.] When a guard detects an inconsistency, it
can record a narrowed domain via `prover:learn/3`. This learned
constraint persists across reprove retries, preventing the prover from
repeating the same dead-end choice (see
#link("09-doc-prover-assumptions.md")[Chapter 9] and
#link("10-doc-version-domains.md")[Chapter 10]).

== Ordering: `after` vs `after_only`
<ordering-after-vs-after_only>
Both influence ordering in the plan, but they differ in origin and
propagation:

#figure(
  align(center)[#table(
    columns: (16.07%, 48.21%, 35.71%),
    align: (left,left,left,),
    table.header([#strong[Marker]], [#strong[Propagates to child
      deps?]], [#strong[Origin / use case]],),
    table.hline(),
    [`after(Lit)`], [Yes], [World-set anchors: the package and all its
    deps should come after `Lit`],
    [`after_only(Lit)`], [No], [PDEPEND completion: only this package
    (not its deps) prefers to come after `Lit`],
  )]
  , kind: table
  )

In `after_only` mode the marker is rewritten to a
`constraint(order_after(...):{[]})` term --- an ordering-only
#strong[soft preference] that the pass-2 orderer (`prefers/2` in
`Source/Domain/Gentoo/Rules/ordering.pl`) honors exactly when doing so
closes no cycle. Neither marker is minted per DEPEND/RDEPEND edge;
build-time vs runtime ordering is decided in pass 2 by the ordering rule
set (`requires/2` / `prefers/2`), not by context markers.

=== Extraction
<extraction>
```prolog
featureterm:get_after_with_mode(Context, After, AfterForDeps, ContextRest)
```

- If `after(X)` → `After = X`, `AfterForDeps = X` (propagate).
- If `after_only(X)` → `After = X`, `AfterForDeps = none` (don't
  propagate).
- If neither → both `none`.

== Example: full context evolution
<example-full-context-evolution>
The following example traces how context evolves as the prover walks
from a user target (`sys-apps/portage`) through two levels of
dependencies. The diagram shows the key context tags at each step.

#figure(image("Diagrams/20-context-evolution.svg", width: 60.0%, alt: "Context evolution through a dependency chain"),
  caption: [
    Context evolution through a dependency chain
  ]
)

=== Step 1 --- Target resolution
<step-1-target-resolution>
The user runs `emerge sys-apps/portage`. The target rule selects the
best visible candidate (`portage-3.0.77-r3`). At this point the context
is empty --- there is no parent, no USE requirement, and no ordering
constraint.

=== Step 2 --- Expanding portage's dependencies
<step-2-expanding-portages-dependencies>
The install rule for portage expands its DEPEND and RDEPEND. Each
dependency atom gets its own context, built from three operations:

- #strong[`add_self_to_dep_contexts`] adds
  `self(portage://portage-3.0.77-r3)` to record that portage is the
  parent.
- #strong[`process_build_with_use`] translates bracketed USE flags from
  the atom. For `dev-lang/python[ssl,threads]`, this produces
  `build_with_use:use_state([ssl,threads],[])`. For `app-arch/tar` (no
  brackets), the USE state is empty.
- #strong[`featureterm:get_after_with_mode`] +
  #strong[`featureterm:add_after_to_dep_contexts`] propagate any
  incoming `after/1` marker (e.g.~from an `@world` anchor) into the dep
  contexts. No new markers are minted here --- DEPEND and RDEPEND atoms
  are treated alike; their relative ordering is a pass-2 concern.

=== Step 3 --- Resolving python
<step-3-resolving-python>
The candidate `python-3.13.2` is selected. A `selected_cn` constraint is
emitted into the global ConstraintsAVL (not the context). The context
itself is passed down unchanged from the grouped dependency.

=== Step 4 --- Expanding python's dependencies
<step-4-expanding-pythons-dependencies>
Python's own dependencies get fresh contexts. Notice how each tag is
rebuilt at this level:

- #strong[`self`] now points to `python-3.13.2`, not to portage. The
  `self` tag always records the immediate parent, never accumulates.
- #strong[`build_with_use`] is replaced based on the new atom.
  `dev-libs/openssl:=` has no bracketed flags, so the USE state becomes
  empty.
- #strong[`after`] --- if an `after/1` marker arrived with the incoming
  context (e.g.~the target was an `@world` anchor), it is propagated
  onward into python's dep contexts.
- #strong[Slot lock] --- the `:=` operator on `dev-libs/openssl:=` adds
  a `slot(dev-libs,openssl,0/3.4.1)` tag to the context, recording the
  sub-slot for rebuild tracking.
- #strong[`after_only`] --- had python carried a PDEPEND, that edge
  would get `after_only(python:install)`, later rewritten to an
  `order_after` soft preference that does not propagate to the child's
  own deps.

=== Key observations
<key-observations>
- #strong[`self/1`] always points to the immediate parent, never
  accumulates along the chain.
- #strong[`build_with_use`] is replaced at each edge based on the
  dependency atom's bracketed flags.
- #strong[`after/1`] (from world-set anchors) propagates down the tree;
  #strong[`after_only/1`] (from PDEPEND edges) does not.
  DEPEND-vs-RDEPEND ordering is decided in pass 2, not by context
  markers.
- #strong[Slot locks] (`:=`) add `slot/3` entries to the context.
- #strong[Constraint emissions] (e.g.~`selected_cn`) go into the global
  ConstraintsAVL, not into the context.

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

= Dependency Resolver Comparison
<dependency-resolver-comparison>
== Architecture Overview
<architecture-overview-1>
All four resolvers solve the same problem: given a set of requested
packages, figure out which concrete versions to install and in what
order. Where they differ is in how they handle #strong[conflicts] ---
situations where the first choice turns out to be wrong.

Each subsection below describes the resolver's strategy and illustrates
its conflict-resolution loop.

=== Portage (Python)
<portage-python>
Portage takes the most straightforward approach. It builds a dependency
graph by walking every dependency and picking the newest stable
candidate for each. If two packages end up claiming the same slot,
Portage detects the conflict after the graph is already built.

Its recovery strategy is blunt: mask the conflicting package so it won't
be picked again, throw away the entire graph, and rebuild it from
scratch. Each retry adds one more mask. The masks accumulate across
retries, but no other information carries over --- the graph starts
clean every time. Portage allows up to 20 retries by default
(configurable with `--backtrack=N`).

#figure(image("Diagrams/21-portage-loop.svg", width: 40.0%, alt: "Portage conflict-resolution loop"),
  caption: [
    Portage conflict-resolution loop
  ]
)

Because each retry rebuilds everything, this approach is the slowest of
the four. Complex dependency tangles --- like the OCaml Jane Street
ecosystem --- can require more than a dozen retries before Portage finds
a consistent graph.

=== pkgcore (Python)
<pkgcore-python>
pkgcore's `pmerge` resolver is also Python, but it does #strong[not]
copy Portage's rebuild-with-masks loop. Resolution is a depth-first walk
over an explicit #strong[frame stack] (`resolver_stack` /
`resolver_frame` in `pkgcore.resolver.plan`): each atom pushes a frame,
tries a choice, and walks that choice's dependency set.

When a choice fails --- inserting it into the plan state fails, or a
dependency under it cannot be satisfied --- pkgcore #strong[backtracks
to the frame's checkpoint] (`state.backtrack(start_point)`), advances to
the next remaining package for that atom (`force_next_pkg`), and
continues inside the same `merge_plan`. Failed alternatives can also be
pruned from the choice set (`reduce_solutions`). There is no global mask
list carried into a fresh graph, and no Paludis-style preload that names
the winning candidate for the next full restart.

#figure(image("Diagrams/21-pkgcore-loop.svg", width: 40.0%, alt: "pkgcore conflict-resolution loop"),
  caption: [
    pkgcore conflict-resolution loop
  ]
)

Relative to Portage, this is a real improvement: work already done above
the failing frame is kept, and only the open choice point is revisited.
Relative to Paludis and portage-ng, the guidance is still mostly
#strong[negative and local] --- "try the next candidate" --- rather than
a positively learned domain or a computed "use this package next time."
Deep, blocked search spaces can still explore a large fraction of the
choice tree (and historically could blow the Python recursion limit
before the frame rewrite moved the stack out of the call stack).

=== Paludis (C++)
<paludis-c>
Paludis is smarter about what it remembers. Instead of masking wrong
candidates, it identifies the #strong[right] one. When a new constraint
conflicts with an earlier decision, Paludis evaluates all accumulated
constraints for that package simultaneously and determines which
candidate satisfies them all.

It then records a #emph[preload] --- an instruction that says "use this
specific candidate next time." The resolver is discarded and a fresh one
is created, but the preloads travel with it. This means the next attempt
starts with positive guidance rather than just a list of things to
avoid.

#figure(image("Diagrams/21-paludis-loop.svg", width: 40.0%, alt: "Paludis conflict-resolution loop"),
  caption: [
    Paludis conflict-resolution loop
  ]
)

Because Paludis carries forward the right answer instead of just
rejecting the wrong one, it typically needs fewer restarts than Portage.
However, each restart still creates a brand-new resolver, so the
dependency walk itself is repeated.

=== portage-ng (SWI-Prolog)
<portage-ng-swi-prolog>
portage-ng avoids the restart-from-scratch pattern altogether. It uses a
depth-first proof search: each dependency becomes a proof obligation,
and selecting a candidate adds constraints to a global store. Constraint
guards monitor the store and fire immediately when a conflict appears.

When a guard fires, three things happen in sequence:

+ The conflicting domain is #strong[learned] --- the version set for
  that package is narrowed to exclude impossible choices.
+ The current candidate is #strong[rejected] so it won't be tried again.
+ Only the affected #strong[subtree is retried], with the learned domain
  already in place to guide candidate selection.

#figure(image("Diagrams/21-portage-ng-loop.svg", width: 40.0%, alt: "portage-ng conflict-resolution loop"),
  caption: [
    portage-ng conflict-resolution loop
  ]
)

For the vast majority of packages (over 99%), no conflict arises at all
and the proof completes in a single pass. When conflicts do occur, the
combination of learned domains (positive guidance) and rejects (negative
filtering) resolves them without rebuilding the entire proof tree. This
makes portage-ng the fastest of the four resolvers.

== Comparison Table
<comparison-table>
#figure(
  align(center)[#table(
    columns: (20%, 20%, 20%, 20%, 20%),
    align: (left,left,left,left,left,),
    table.header([#strong[Aspect]], [#strong[Portage]], [#strong[pkgcore]], [#strong[Paludis]], [#strong[portage-ng]],),
    table.hline(),
    [Language], [Python], [Python], [C++], [SWI-Prolog],
    [Conflict detection], [Post-hoc (after graph built)], [Incremental
    (during frame / choice walk)], [Incremental (on constraint
    add)], [Incremental (constraint guard)],
    [What carries across retries], [Masks (negative)], [Remaining
    choices in the frame (negative pruning)], [Preloads
    (positive)], [Learned domains (positive) + Rejects (negative)],
    [Fresh state each retry?], [Yes (new depgraph)], [No --- backtrack
    to frame checkpoint], [Yes (new Resolver)], [Partial (reject set
    accumulates, learned store accumulates)],
    [Finding the right candidate], [Brute force
    (mask+retry)], [`force_next_pkg` after
    backtrack], [`_try_to_find_decision_for` with ALL
    constraints], [Domain narrowing (Zeller) + priority resolution
    (Vermeir)],
    [Performance], [Slowest (full rebuild)], [Faster than Portage (keeps
    parent frames)], [Fast (targeted restarts)], [Fastest (single-pass
    for most targets)],
    [Package-specific code], [None], [None], [None], [None],
  )]
  , kind: table
  )

== Academic Foundations
<academic-foundations>
=== Zeller & Snelting: Feature Logic (ESEC 1995, TOSEM 1997)
<zeller-snelting-feature-logic-esec-1995-tosem-1997>
"Handling Version Sets through Feature Logic" (ESEC 1995, LNCS 989) and
its expanded journal version "Unified Versioning Through Feature Logic"
(TOSEM 1997, Vol. 6 No.~4) --- version sets are identified by feature
terms and configured by incrementally narrowing the set until each
component resolves to a single version. portage-ng's `version_domain`
with `domain_meet` (intersection) is essentially Zeller's feature term
narrowing. The learned constraint store implements Zeller's feature
implication propagation: constraints discovered in one proof attempt
propagate to narrow version sets in the next attempt.

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

=== Any-of (`||`) arm preference
<any-of-arm-preference>
Portage's `dep_zapdeps` `choice_bins` and portage-ng's
`ranking:prioritize_deps_keep_all/3` multi-key sort are compared in
detail in
#link("12-doc-resolution.md#any-of-arm-selection")[Chapter 12, Any-of (`||`) arm selection]
(including why overlapping-`||` DNF, virtual expand, and circular
demotion inside `||` are not mirrored as ranking keys).

= Dependency Ordering
<dependency-ordering>
When a package manager installs several packages at once, the order in
which they are merged matters. A compiler must be installed before the
packages that need it for building; a shared library must be present
before the programs that link against it can run. The Gentoo Package
Manager Specification (PMS) defines five dependency types, each with
different ordering strength. Portage, Paludis, and portage-ng all
interpret these types, but they differ in how strictly they enforce
ordering --- especially when cycles make a perfect order impossible.

== Dependency types
<dependency-types>
The PMS (Chapter 8) groups dependencies into five classes based on
#emph[when] the dependency must be available.

- #strong[DEPEND / BDEPEND] --- build-time dependencies. These must be
  installed and usable before `pkg_setup` runs and throughout the
  `src_*` build phases. BDEPEND (introduced in EAPI 7) targets the build
  host (CBUILD), while DEPEND targets the target host (CHOST). Both
  create #strong[hard ordering constraints]: the dependency must be
  merged before the dependent can be built.

- #strong[RDEPEND] --- runtime dependencies. These must be installed
  before the package is "treated as usable." This is a #strong[soft
  ordering constraint]: ideally satisfied before the dependent is
  merged, but the constraint can be relaxed when cycles exist.

- #strong[PDEPEND] --- post-dependencies. These only need to be
  installed "before the package manager finishes the batch." This is the
  #strong[weakest constraint] --- there is no requirement that the
  post-dependency is merged before the dependent.

- #strong[IDEPEND] --- install-time dependencies (EAPI 8+). Needed
  during `pkg_preinst` and `pkg_postinst`. Treated similarly to runtime
  dependencies for ordering purposes.

== Phase functions and dependency availability
<phase-functions-and-dependency-availability>
Different ebuild phases have access to different dependency classes:

/ #strong[Build phases] (`src_unpack` through `src_install`): #block[
DEPEND, BDEPEND
]

/ #strong[Install phases] (`pkg_preinst`, `pkg_postinst`, `pkg_prerm`, `pkg_postrm`): #block[
RDEPEND, IDEPEND
]

/ #strong[Configuration] (`pkg_config`): #block[
RDEPEND, PDEPEND
]

== Portage's approach
<portages-approach>
Portage builds a single dependency graph where every package is a node
and every dependency creates a directed edge. Each edge carries a
#emph[priority] that records how hard the ordering constraint is:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Dependency]], [#strong[Priority]], [#strong[Breakable?]],),
    table.hline(),
    [DEPEND / BDEPEND], [buildtime (highest)], [Never],
    [RDEPEND with `:=` slot op], [runtime\_slot\_op], [Only when
    cross-compiling],
    [RDEPEND], [runtime], [Yes, for cycles],
    [PDEPEND], [runtime\_post (lowest)], [Yes, first to break],
  )]
  , kind: table
  )

=== Progressive relaxation
<progressive-relaxation-1>
When Portage runs its topological sort and cannot find a leaf node (a
package with no unsatisfied dependencies), it progressively drops weaker
edges until a leaf appears. The relaxation proceeds in four passes:

#figure(image("Diagrams/22-portage-relaxation.svg", width: 85.0%, alt: "Portage progressive edge relaxation"),
  caption: [
    Portage progressive edge relaxation
  ]
)

+ #strong[All edges respected] --- standard topological sort.
+ #strong[Drop optional edges] --- removes edges for optional
  dependencies.
+ #strong[Drop PDEPEND edges] --- the weakest real dependency type is
  discarded.
+ #strong[Drop RDEPEND edges] --- runtime edges are relaxed, freeing
  most remaining cycles.

If no leaf is found even after dropping RDEPEND edges, the remaining
cycle involves only build-time dependencies. This is a hard error ---
Portage cannot resolve it and reports the cycle to the user.

=== What this means in practice
<what-this-means-in-practice>
In the common (acyclic) case, Portage merges all dependencies ---
including RDEPEND --- before the packages that need them. When cycles
exist, PDEPEND edges are broken first, then RDEPEND edges. Build-time
edges are never broken.

== Paludis's approach
<paludiss-approach>
Paludis takes a different view. It builds a Node-Adjacency Graph (NAG)
where edges carry two boolean flags: `build()` for build-time
dependencies and `run()` for runtime dependencies. Notably,
#strong[PDEPEND creates no edge at all]. The Paludis source comments
explain the reasoning: most post-dependencies already depend on the
thing requiring them anyway, so adding a backwards edge would just
create unnecessary cycles.

=== SCC-based cycle handling
<scc-based-cycle-handling>
Rather than relaxing edges progressively, Paludis uses Tarjan's
algorithm to find strongly connected components (SCCs) and then
classifies each one:

- #strong[Single-node SCC] --- no cycle, scheduled directly.
- #strong[Runtime-only SCC] (no build edges) --- ordered arbitrarily.
  Paludis treats runtime-only cycles as having no ordering significance
  at all.
- #strong[Build-dep SCC] --- Paludis tries to break the cycle by
  removing edges whose dependencies are already satisfied
  (`build_all_met` or `run_all_met`). If the SCC is still cyclic after
  that, it is marked as unorderable.

The key insight from Paludis is stronger than Portage's progressive
relaxation: runtime-only cycles are not just #emph[breakable] --- they
are #emph[free to order however is convenient].

== portage-ng's approach
<portage-ngs-approach>
portage-ng models dependencies as a two-phase proof tree. Each package
has an `:install` action (building) and a `:run` action (being usable).
The different dependency types map naturally onto this structure.

=== Intra-group dependency ordering
<intra-group-dependency-ordering>
Before proving the dependencies within a single package,
`ranking:dep_priority/2` sorts them by constraint tightness. Tightly
constrained dependencies are proved first so that their `selected_cn`
locks early, preventing greedy conflicts where an unconstrained sibling
picks a version that later clashes. The priority ladder (lower = proved
first): tight upper bound (1) → tilde (4) → wildcard (8) → unconstrained
(999). Within each tier, slot specificity further refines the order. See
#link("12-doc-resolution.md")[Chapter 12] for details.

#figure(image("Diagrams/22-portage-ng-model.svg", width: 55.0%, alt: "portage-ng two-phase dependency model"),
  caption: [
    portage-ng two-phase dependency model
  ]
)

- #strong[DEPEND / BDEPEND] create edges to `:install` actions with
  `after()` context tags that propagate down the dependency chain. These
  are hard ordering constraints.
- #strong[RDEPEND] create edges to `:run` actions with `after_only()`
  context tags that stop at the immediate children. This makes them
  naturally softer.
- #strong[PDEPEND] are handled by the `heuristic:proof_obligation/4`
  hook in a single pass during proof search, without creating explicit
  ordering edges in the proof.

When cycles appear, the ordering pass (Chapter 13) resolves them at
proof time: a requirement whose provider is still being scheduled falls
through to a citation of the installed world (VDB), or --- when nothing
bridges the loop --- to an honest `unreachable` assumption. Runtime-only
cycles never bind at all, because RDEPEND edges are soft preferences
(matching Paludis's insight) that are simply dropped when they would
close a cycle.

=== PDEPEND completion ordering
<pdepend-completion-ordering>
Although PDEPEND creates no edge during proof search, a package `P` that
declares PDEPEND is only fully functional once its post-dependencies are
merged. If another package consumes `P` and starts building before `P`'s
PDEPEND closure is installed, its build can fail (e.g.~a Ruby
extension's `extconf.rb` hits a `LoadError`, or a CMake
`CMAKE_C_COMPILER` check fails because a toolchain component is not yet
on `PATH`).

The ordering bindings close this gap with a #strong[completion
preference] (`ordering:prefers/2` in
`Source/Domain/Gentoo/Rules/ordering.pl`): a consumer whose dependency
carries an `order_after` anchor on a PDEPEND provider prefers the
install heads of that provider's PDEPEND targets --- i.e.~it is ordered
after `P`'s whole post-install group, matching emerge's behaviour
(portage-ng\#18).

Because this is a #emph[preference], not a hard requirement, it is
inherently cycle-safe: the wave projection accepts each preference
exactly when it closes no cycle against the hard edges and the
previously accepted preferences. A consumer that is itself a member of
the provider's PDEPEND group is therefore never bumped --- the
preference back onto its own group would close a cycle and is dropped
silently (portage-ng\#19). Densely cyclic toolchain closures (e.g.~LLVM)
are safe for the same reason: no preference can collapse the ordering of
an acyclic chain elsewhere in the plan (portage-ng\#26).

A per-pass PDEPEND anchor index makes the preference lookup cheap; plans
without any PDEPEND provider pay only an empty index probe.

== How the three approaches compare
<how-the-three-approaches-compare>
The diagram below traces how each PMS dependency type is implemented
across the three resolvers. Blue indicates hard (build-time)
constraints, green indicates soft (runtime) constraints, and yellow
indicates the weakest (post-dependency) constraints.

#figure(image("Diagrams/22-dep-edge-mapping.svg", width: 60.0%, alt: "Dependency type mapping across resolvers"),
  caption: [
    Dependency type mapping across resolvers
  ]
)

#figure(
  align(center)[#table(
    columns: (25%, 25%, 25%, 25%),
    align: (left,left,left,left,),
    table.header([#strong[Aspect]], [#strong[Portage]], [#strong[Paludis]], [#strong[portage-ng]],),
    table.hline(),
    [DEPEND/BDEPEND], [Hard edge, never broken], [Hard edge, never
    broken], [`:install` + `after()`, hard],
    [RDEPEND], [Soft edge, broken for cycles], [Soft edge, cycles freely
    ordered], [`:run` + `after_only()`, soft],
    [PDEPEND], [Weak edge, first to break], [No edge at all], [proof
    obligation hook, no proof edge; completion preference in ordering
    pass],
    [Cycle strategy], [Progressive relaxation], [SCC
    classification], [World citation (VDB) or `unreachable` assumption],
    [Build-time cycles], [Error / merge group], [Relax met edges, then
    error], [Bridged by installed world; honest bootstrap boundary
    otherwise],
  )]
  , kind: table
  )

== Annex: overlay test cases
<annex-overlay-test-cases>
portage-ng ships with a synthetic overlay (`Repository/Overlay/`)
containing 80 test cases that exercise the resolver in isolation. Each
test uses tiny packages with carefully crafted dependency relationships,
making it easy to see exactly how the resolvers behave. The five cases
below illustrate the ordering concepts discussed in this chapter. For
each case we show the dependency graph, a short description, and the
captured output from both Portage (`emerge -vp`) and portage-ng
(`--pretend`).

=== Annex A --- Basic ordering (test01)
<annex-a-basic-ordering-test01>
Four packages with a clean dependency chain: `web` depends on `app`,
`db`, and `os`\; `app` depends on `db` and `os`\; `db` depends on `os`.
No cycles, no special dependency types.

#figure(image("Diagrams/22-test01.svg", width: 50.0%, alt: "test01 — Basic dependency ordering"),
  caption: [
    test01 --- Basic dependency ordering
  ]
)

Both resolvers produce the same order: `os` first (no dependencies),
then `db` and `app` (whose dependencies are now satisfied), and finally
`web`. portage-ng additionally shows the two-phase `:install` / `:run`
structure and groups downloads into a parallel first step.

#strong[Portage output:]

```
[ebuild  N     ] test01/os-1.0::overlay   0 KiB
[ebuild  N     ] test01/db-1.0::overlay   0 KiB
[ebuild  N     ] test01/app-1.0::overlay  0 KiB
[ebuild  N     ] test01/web-1.0::overlay  0 KiB

Total: 4 packages (4 new)
```

#strong[portage-ng output:]

```
  step  1 | download  overlay://test01/web-1.0
          | download  overlay://test01/os-1.0
          | download  overlay://test01/db-1.0
          | download  overlay://test01/app-1.0

  step  2 | install   overlay://test01/os-1.0
  step  3 | run       overlay://test01/os-1.0
  step  4 | install   overlay://test01/db-1.0
  step  5 | run       overlay://test01/db-1.0
  step  6 | install   overlay://test01/app-1.0
  step  7 | run       overlay://test01/app-1.0
  step  8 | install   overlay://test01/web-1.0
  step  9 | run       overlay://test01/web-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs)
```

=== Annex B --- Transitive RDEPEND (test50)
<annex-b-transitive-rdepend-test50>
`app` has a compile-time dependency on `foo`, and `foo` has a runtime
dependency on `bar`. The question is whether `bar` --- a transitive
runtime dependency of a build dependency --- appears in the merge plan.

#figure(image("Diagrams/22-test50.svg", width: 40.0%, alt: "test50 — Transitive RDEPEND"),
  caption: [
    test50 --- Transitive RDEPEND
  ]
)

Both resolvers correctly include all three packages. The ordering is
`bar` first (so `foo` can run), then `foo` (so `app` can build), then
`app`.

#strong[Portage output:]

```
[ebuild  N     ] test50/bar-1.0::overlay  0 KiB
[ebuild  N     ] test50/foo-1.0::overlay  0 KiB
[ebuild  N     ] test50/app-1.0::overlay  0 KiB

Total: 3 packages (3 new)
```

#strong[portage-ng output:]

```
  step  1 | download  overlay://test50/foo-1.0
          | download  overlay://test50/bar-1.0
          | download  overlay://test50/app-1.0

  step  2 | install   overlay://test50/bar-1.0
  step  3 | run       overlay://test50/bar-1.0
  step  4 | install   overlay://test50/foo-1.0
  step  5 | install   overlay://test50/app-1.0
  step  6 | run       overlay://test50/app-1.0

Total: 8 actions (3 downloads, 3 installs, 2 runs)
```

=== Annex C --- Runtime cycle (test07)
<annex-c-runtime-cycle-test07>
Same four-package graph as Annex A, but `os` adds a #strong[runtime]
dependency back on `web`, creating a cycle. The back-edge is an RDEPEND,
so both resolvers treat the cycle as benign.

#figure(image("Diagrams/22-test07.svg", width: 50.0%, alt: "test07 — Indirect cycle (runtime)"),
  caption: [
    test07 --- Indirect cycle (runtime)
  ]
)

Portage reports the cycle as a warning but still produces a valid merge
list (using 1 backtrack). portage-ng classifies it as benign and
produces a clean plan with no assumptions --- notice that `web`, `app`,
and `db` are installed in parallel in step 3 because the runtime cycle
makes their relative order irrelevant.

#strong[Portage output:]

```
[ebuild  N     ] test07/web-1.0::overlay  0 KiB
[ebuild  N     ] test07/app-1.0::overlay  0 KiB
[ebuild  N     ] test07/db-1.0::overlay   0 KiB
[ebuild  N     ] test07/os-1.0::overlay   0 KiB

Total: 4 packages (4 new)

 * Error: circular dependencies:
(test07/os-1.0::overlay) depends on
 (test07/web-1.0::overlay) (runtime)
  (test07/os-1.0::overlay) (buildtime)
```

#strong[portage-ng output:]

```
  step  1 | download  overlay://test07/web-1.0
          | download  overlay://test07/os-1.0
          | download  overlay://test07/db-1.0
          | download  overlay://test07/app-1.0

  step  2 | install   overlay://test07/os-1.0
  step  3 | install   overlay://test07/web-1.0
          | install   overlay://test07/app-1.0
          | install   overlay://test07/db-1.0
  step  4 | run       overlay://test07/web-1.0
          | run       overlay://test07/app-1.0
          | run       overlay://test07/db-1.0
  step  5 | run       overlay://test07/os-1.0

Total: 12 actions (4 downloads, 4 installs, 4 runs)
```

=== Annex D --- PDEPEND (test66)
<annex-d-pdepend-test66>
`app` depends on `lib` (compile-time), and `lib` declares `plugin` as a
PDEPEND. The plugin should be resolved, but it does not need to be
installed before `lib`.

#figure(image("Diagrams/22-test66.svg", width: 40.0%, alt: "test66 — PDEPEND (post-merge)"),
  caption: [
    test66 --- PDEPEND (post-merge)
  ]
)

Portage merges `plugin` first (it has no hard dependencies), then `lib`,
then `app`. portage-ng installs `lib` and `plugin` in parallel in step
2, since PDEPEND creates no ordering constraint between them here. The
plugin's `:run` action comes last, after the main target. (When a
package #emph[outside] the PDEPEND closure consumes the provider, the
ordering pass's
#link(<pdepend-completion-ordering>)[PDEPEND completion preference]
additionally orders that consumer after the provider's post-install
group; this minimal test has no such external consumer.)

#strong[Portage output:]

```
[ebuild  N     ] test66/plugin-1.0::overlay  0 KiB
[ebuild  N     ] test66/lib-1.0::overlay     0 KiB
[ebuild  N     ] test66/app-1.0::overlay     0 KiB

Total: 3 packages (3 new)
```

#strong[portage-ng output:]

```
  step  1 | download  overlay://test66/plugin-1.0
          | download  overlay://test66/lib-1.0
          | download  overlay://test66/app-1.0

  step  2 | install   overlay://test66/lib-1.0
          | install   overlay://test66/plugin-1.0
  step  3 | run       overlay://test66/lib-1.0
  step  4 | install   overlay://test66/app-1.0
  step  5 | run       overlay://test66/app-1.0
  step  6 | run       overlay://test66/plugin-1.0

Total: 9 actions (3 downloads, 3 installs, 3 runs)
```

=== Annex E --- PDEPEND cycle (test79)
<annex-e-pdepend-cycle-test79>
`server` has an RDEPEND on `client`, and `client` has a PDEPEND back on
`server`. This creates a cycle, but since PDEPEND creates no ordering
edge, the cycle is naturally broken.

#figure(image("Diagrams/22-test79.svg", width: 40.0%, alt: "test79 — PDEPEND cycle"),
  caption: [
    test79 --- PDEPEND cycle
  ]
)

Portage handles this cleanly --- the PDEPEND obligation is already
satisfied because `server` was merged as part of the same batch.
portage-ng's proof obligation mechanism resolves the PDEPEND in a single
pass with no assumptions needed.

#strong[Portage output:]

```
[ebuild  N     ] test79/client-1.0::overlay  0 KiB
[ebuild  N     ] test79/server-1.0::overlay  0 KiB

Total: 2 packages (2 new)
```

#strong[portage-ng output:]

```
  step  1 | download  overlay://test79/server-1.0
          | download  overlay://test79/client-1.0

  step  2 | install   overlay://test79/client-1.0
  step  3 | run       overlay://test79/client-1.0
  step  4 | install   overlay://test79/server-1.0
  step  5 | run       overlay://test79/server-1.0

Total: 6 actions (2 downloads, 2 installs, 2 runs)
```

== References
<references>
- PMS Chapter 8: #link("https://projects.gentoo.org/pms/8/pms.html")
- Portage source: `lib/_emerge/depgraph.py` (method `_serialize_tasks`)
- Portage priorities: `lib/_emerge/DepPriorityNormalRange.py`
- Paludis orderer: `paludis/resolver/orderer.cc`
- Paludis classifier: `paludis/resolver/labels_classifier.cc`
- Full overlay test suite: `Documentation/Tests/README.md` (80 test
  cases)

= Testing and Regression
<testing-and-regression>
portage-ng uses multiple testing strategies: PLUnit tests for unit
logic, overlay regression tests for end-to-end scenario validation, and
merge-vs-emerge comparison for correctness measurement against Portage.

== PLUnit tests
<plunit-tests>
Standard SWI-Prolog unit tests in `Source/Test/unittest.pl`:

```bash
make test
```

These test individual predicates in isolation --- version comparison,
domain operations, context merging, EAPI parsing, etc.

== Overlay regression tests
<overlay-regression-tests>
The overlay test suite (`make test-overlay`) runs 80 curated scenarios
against a test overlay in `Repository/Overlay/`. Each scenario has a
specific dependency story and expected behavior.

For onboarding, treat a subset as #strong[policy specimens] (not only
CI): see #link("Policy/examples.md")[Policy by example] and the
#link("Policy/README.md")[policy cards].

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

=== Failure testing
<failure-testing>
Test 58 is explicitly marked as an expected failure (XFAIL) via
`test:xfail/2` --- it exercises PROVIDE-based virtuals, deprecated in
PMS; a documented limitation that will not be fixed.

== Merge vs emerge comparison
<merge-vs-emerge-comparison>
The primary correctness metric is comparison against Portage's `emerge`
output across the entire Portage tree. The comparison harness now lives
in the #link("https://github.com/pvdabeel/tinderbox-ng")[tinderbox-ng]
repository, which drives both engines through identical sessions and
analyses the resulting plan logs.

=== Running a comparison
<running-a-comparison>
Per-target compare (plan only, fresh sessions on both sides):

```sh
tinderbox-ng compare www-servers/apache
```

Whole-tree matrix run plus aggregate analysis:

```sh
tinderbox-ng new regress
tinderbox-ng exec regress -- \
  tinderbox-matrix resolver \
  /usr/local/share/tinderbox-ng/share/tinderbox-ng/manifest-1000.txt
tinderbox-ng analyze \
  --md5-cache /srv/tinderbox-ng/baseline/var/db/repos/gentoo/metadata/md5-cache
```

`tinderbox-ng analyze` feeds each `portage-ng.plan.log` /
`emerge.plan.log` pair through
`share/tinderbox-ng/compare-merge-emerge.py` (inside the tinderbox-ng
repo) and writes `analysis.json` + `analysis.txt` into the matrix run
directory.

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
For a single package, use `--target-regex` on `tinderbox-ng analyze`:

```sh
sudo tinderbox-ng analyze --target-regex '^sys-apps/portage-3.0.77-r3$'
```

Or run a one-off per-target compare directly:

```sh
tinderbox-ng compare sys-apps/portage
```

== Bulk plan fingerprint comparison
<bulk-plan-fingerprint-comparison>
`Source/Test/plancompare.pl` fingerprints the full pipeline (resolve +
order) for every ebuild in a repository. Use it to verify that a
resolver change produces identical plans before committing:

```sh
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
load_files(portage('Source/Test/plancompare'), [if(true)]).
plancompare:run(portage, '/tmp/plan-compare.tsv').
halt.
PL
```

Compare two TSV files from before/after runs:

```sh
plancompare:diff('/tmp/before.tsv', '/tmp/after.tsv').
```

== md5-cache extractor regression
<md5-cache-extractor-regression>
`md5cache_validate/0,1` (in `Source/Test/unittest.pl`) runs the
standalone bash extractor at
`Source/Domain/Gentoo/Ebuild/ebuild-depend.sh --batch` over every
md5-cache entry in the configured Portage tree and diffs the produced
metadata against the on-disk cache, key by key.

```sh
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
load_files(portage('Source/Test/unittest'), [if(true)]).
md5cache_validate([limit(50), verbose(true)]).
halt.
PL
```

Options: `repo(Atom)` (default `portage`), `limit(N)` (0 = all),
`verbose(Bool)`, `out(Path)` (writes a Prolog-term report).

== Further reading
<further-reading-21>
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- `make test` commands
- #link("26-doc-performance.md")[Chapter 26: Performance and Profiling]
  --- `resolver:test_stats` for bulk testing
- #link("27-doc-contributing.md")[Chapter 27: Contributing] ---
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
#strong[instrumentation] (the sampler), #strong[bulk testing], and a
#strong[performance comparison] between portage-ng and Portage.

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

#strong[Companion caches.] `Knowledge/profile.qlf` (profile tree data,
built by `--sync`) and `Knowledge/preference.qlf` (materialized
preference state after `preference:init/0`, built on first startup and
invalidated by `--sync` or input changes) further reduce startup work.
After `kb.qlf` loads, `knowledgebase:load/0` also primes the JIT index
on `cache:entry_metadata/4` for slotted profile-mask lookups so the
first `preference:init/0` does not pay a multi-second penalty on atoms
such as `dev-qt/qtimageformats:5`.

== Pillar 2: Goal expansion macros
<pillar-2-goal-expansion-macros>
High-level queries in the knowledge layer are written for clarity; at
#strong[compile time] they are rewritten into #strong[direct cache
access], so the runtime path never pays for meta-interpretation over
generic search.

A module-local `query:goal_expansion/2` hook in
`Source/Knowledge/query.pl` performs this rewrite (deliberately
#emph[not] `user:goal_expansion/2`, so only code compiled inside the
`query` module is affected --- portage-ng\#59). It expands
`search(Query, Repo://Id)` goals at compile time: `compile_query_list/3`
\/ `compile_query_compound/3` translate each query term into direct
indexed cache lookups such as `cache:ordered_entry/5` conjunctions.

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
proof tree. That trade-off shows up again in practice when proof trees
grow large.

== Pillar 4: Prescient proving (avoiding backtracking)
<pillar-4-prescient-proving-avoiding-backtracking>
Naive proof search can exhibit #strong[O(2ⁿ)] behaviour in the worst
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
narrowing behaviour improving, runtime suffers.

== Sampler module
<sampler-module>
The sampler (`Source/Application/Performance/sampler.pl`) is the main
place to #strong[measure] whether the pillars above are behaving as
intended in production-like runs.

=== Hook performance
<hook-performance>
```prolog
sampler:phase_walltime(-T)
```

Captures a wall-clock snapshot. The pipeline takes three snapshots ---
before resolving, between resolving and ordering, and after ordering.

```prolog
sampler:phase_record(T0, T1, T2)
```

Computes and records the per-phase deltas (resolve ms, order ms) from
the three snapshots for later retrieval.

=== Test statistics
<test-statistics>
```prolog
resolver:test_stats(Repository)
resolver:test_stats_pkgs(Repository, PackageList)
```

Run the resolver across all packages (or a specific list) in a
repository and collect aggregate statistics:

- Totals: entries processed, proved, failed
- Share of entries with domain assumptions and with cycle breaks (as
  percentages)
- Failure and assumption-type breakdowns
- Slowest entries and packages

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
resolver:test_stats(portage).
halt.
PL
```

For specific packages:

```bash
./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
resolver:test_stats_pkgs(portage, ['kde-apps'-'kde-apps-meta']).
halt.
PL
```

== Performance comparison: portage-ng vs Portage
<performance-comparison-portage-ng-vs-portage>
The numbers below put the five pillars in perspective with measured data
from a full Portage tree comparison. Both resolvers start from the same
input: an identical Portage tree snapshot (roughly 32,000 ebuilds), the
same VDB (installed package database), and the same `/etc/portage`
configuration. The measurement is #strong[dependency resolution time
only] --- how long it takes to produce a merge plan, not how long the
actual builds take.

- #strong[Portage] uses `emerge -vp <target>`, which runs the Python
  `depgraph.py` resolver with greedy selection and backtracking.
- #strong[portage-ng] uses `--mode standalone --pretend <target>`, which
  runs the Prolog prover and ordering pass.

=== Resolution speed (emerge\_ok packages)
<resolution-speed-emerge_ok-packages>
The comparison covers #strong[31,331 packages] resolved by both tools.
For the #strong[22,781] packages where Portage itself reports a clean
result (`emerge_ok`), portage-ng is faster in #strong[100%] of cases:

#figure(
  align(center)[#table(
    columns: 4,
    align: (left,right,right,right,),
    table.header([], [#strong[Portage]], [#strong[portage-ng]], [#strong[Speedup]],),
    table.hline(),
    [Average], [1,239 ms], [32 ms], [#strong[38x]],
    [Median], [1,159 ms], [6 ms], [#strong[193x]],
    [95th percentile], [1,679 ms], [165 ms], [#strong[10x]],
    [Maximum], [11,165 ms], [920 ms], [#strong[12x]],
    [Cumulative (22,781 pkgs)], [7.84 hours], [12.3
    minutes], [#strong[38x]],
  )]
  , kind: table
  )

The median package resolves in #strong[6 milliseconds] in portage-ng
versus #strong[1.16 seconds] in Portage --- nearly a two-hundred-fold
improvement. Even at the 95th percentile (complex packages with deep
dependency chains), portage-ng finishes in 165 ms while Portage needs
nearly 1.7 seconds. portage-ng is faster in every single `emerge_ok`
pair --- no exceptions.

=== Resolution speed (all packages)
<resolution-speed-all-packages>
Across all #strong[31,331] packages (including those where Portage
reports errors), portage-ng is faster in #strong[99.7%] of cases:

#figure(
  align(center)[#table(
    columns: 4,
    align: (left,right,right,right,),
    table.header([], [#strong[Portage]], [#strong[portage-ng]], [#strong[Speedup]],),
    table.hline(),
    [Average], [1,302 ms], [71 ms], [#strong[18x]],
    [Median], [1,161 ms], [11 ms], [#strong[106x]],
    [95th percentile], [2,069 ms], [264 ms], [#strong[8x]],
    [Maximum], [11,165 ms], [9,107 ms], [#strong[1.2x]],
    [Cumulative (31,331 pkgs)], [11.33 hours], [37.2
    minutes], [#strong[18x]],
  )]
  , kind: table
  )

The 103 cases (0.3%) where Portage finishes faster are all packages
where #strong[Portage itself fails] (`emerge_notok`). In those cases
Portage exits early with an error while portage-ng still performs a full
resolution attempt. Among the `emerge_ok` population --- the
apples-to-apples comparison --- portage-ng wins 100% of cases.

=== Why portage-ng is faster
<why-portage-ng-is-faster>
The performance gap is not about language speed (Prolog vs Python). It
comes from architectural differences that compound across thousands of
packages:

#figure(
  align(center)[#table(
    columns: (33.33%, 33.33%, 33.33%),
    align: (left,left,left,),
    table.header([#strong[Factor]], [#strong[Portage]], [#strong[portage-ng]],),
    table.hline(),
    [Startup cost], [Python interpreter + module imports per
    invocation], [Qcompiled cache loads once, shared across all
    queries],
    [Graph construction], [Build full graph, then check for
    conflicts], [Single-pass proof --- no separate graph phase],
    [Conflict recovery], [Discard entire graph, rebuild from
    scratch], [Retry only the affected subtree with learned
    constraints],
    [Repeated queries], [Each `emerge -vp` starts cold], [In-memory
    facts persist; subsequent queries are instant],
    [Parallelism], [Sequential graph walk], [Ordering pass identifies
    parallel waves automatically],
  )]
  , kind: table
  )

The largest single factor is the #strong[qcompiled cache] (Pillar 1):
once loaded, all 32,000 ebuilds are in memory as indexed Prolog facts,
and queries hit first-argument indexing directly. Portage re-reads and
re-parses metadata structures on each invocation.

The second factor is #strong[single-pass proving] (Pillar 4): for over
99% of packages, portage-ng needs no backtracking at all. Portage's
greedy approach works well for simple cases but scales poorly when
conflicts require multiple backtracks --- each of which rebuilds the
entire dependency graph.

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

+ #strong[Run compare analysis] to detect regressions. The compare
  harness lives in the
  #link("https://github.com/pvdabeel/tinderbox-ng")[tinderbox-ng]
  repository and generates its own plan logs in fresh sessions (the
  legacy `--graph` + `.merge` regeneration loop is no longer part of
  this workflow):

  ```sh
  # Whole-tree matrix run (on the tinderbox host):
  sudo tinderbox-ng compare-matrix
  sudo tinderbox-ng analyze

  # Or a quick per-target compare while iterating locally:
  tinderbox-ng compare <category>/<package>
  ```

  `tinderbox-ng analyze` produces `analysis.json` + `analysis.txt` in
  the matrix run directory, replacing the old
  `compare-<date>-<hash>.json.gz` snapshots.

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
resolver:test_stats(portage).
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

- Exceptions (grandfathered, do not add new ones): `portage-ng.pl`
  (project entry point / name); `binpkg_exec.pl`, `binpkg_index.pl`,
  `binpkg_extract.pl`, `ebuild_exec.pl` and `missing_provider.pl`
  (underscore-named for readability of their prefixes; module names
  match the filenames). Host-local templates under
  `Source/Config/Private/` are configuration, not source modules, and
  are also exempt.

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
Regression tooling is hosted in two places:

- #strong[Merge-vs-emerge plan comparison] --- driven by
  #link("https://github.com/pvdabeel/tinderbox-ng")[tinderbox-ng] via
  `tinderbox-ng compare` / `tinderbox-ng compare-matrix` /
  `tinderbox-ng analyze`. The underlying Python script lives at
  `share/tinderbox-ng/compare-merge-emerge.py` in that repository and is
  invoked automatically by `tinderbox-ng analyze`. Outputs are
  `analysis.json` + `analysis.txt` in the matrix run directory.
- #strong[md5-cache extractor regression] --- `md5cache_validate/0,1` in
  `Source/Test/unittest.pl` (re-extracts metadata via
  `Source/Domain/Gentoo/Ebuild/ebuild-depend.sh --batch` and diffs the
  result key by key against the on-disk md5-cache).

Do not create ad-hoc compare scripts outside these two locations.

== Further reading
<further-reading-22>
- #link("25-doc-testing.md")[Chapter 25: Testing and Regression] ---
  testing methodology
- #link("26-doc-performance.md")[Chapter 26: Performance and Profiling]
  --- performance testing
- #link("02-doc-installation.md")[Chapter 2: Installation and Quick Start]
  --- build and run instructions

= Closing Thoughts
<closing-thoughts>
This book opened with a question that has quietly shaped every chapter
since: as software systems grow more complex, can the tools that manage
them keep up?

portage-ng's answer is to treat package management not as a logistics
problem --- downloading and unpacking files --- but as a
#strong[reasoning problem]. Dependencies become proof obligations.
Configuration choices become constraints. Conflicts become learning
opportunities that narrow the search space for the next attempt. The
result is a system that can walk tens of thousands of packages, resolve
their interdependencies, and produce a buildable plan --- often in a
single pass.

== What we covered
<what-we-covered>
The book traced this idea from concept to implementation:

- #strong[Part I] set the stage: the growing complexity of source-based
  distributions, the limits of imperative solvers, and how Prolog's
  backtracking and unification provide a natural fit for dependency
  reasoning.

- #strong[Part II] unpacked the architecture: how the knowledge base
  stores and indexes package metadata; how the EAPI grammar parses
  dependency specifications; how the prover searches for consistent
  models; how assumptions, constraint learning, and version domains
  handle conflicts; how rules encode Gentoo's domain logic; and how a
  second proving pass over planning laws turns a proof into a concrete
  build order.

- #strong[Part III] covered the features built on top of that
  foundation: the command-line interface, build execution, semantic
  search with LLM integration, distributed proving across clusters, and
  upstream bug tracking.

- #strong[Part IV] explored the theoretical underpinnings: contextual
  logic programming, feature unification, and the comparison with other
  resolvers --- showing how portage-ng's approach relates to Portage's
  progressive relaxation, pkgcore's frame-stack backtracking, Paludis's
  constraint accumulation, and academic work on feature logic and
  ordered logic programs.

- #strong[Part V] described the practical side of development: testing
  strategies, performance profiling, and contribution guidelines.

== Design principles worth remembering
<design-principles-worth-remembering>
A few recurring themes run through the design and are worth calling out
explicitly:

- #strong[Declarative over imperative.] The prover does not maintain
  mutable state that must be carefully unwound on failure. AVL trees are
  persistent; backtracking is automatic; learned constraints accumulate
  naturally. This makes the system easier to reason about and extend.

- #strong[Single-pass where possible, learning where not.] Most packages
  resolve in one pass. When conflicts arise, the system learns from them
  --- narrowing version domains, recording rejects --- so the next
  attempt is better informed. This is fundamentally different from
  starting over with a blank slate on each retry.

- #strong[Separation of concerns.] The prover knows nothing about
  Gentoo. The rules layer knows nothing about proof search. The planning
  laws know nothing about dependency types. Each layer has a clean
  interface, and domain-specific knowledge stays in domain-specific
  modules.

- #strong[Transparency.] Assumptions are not silent failures --- they
  are classified, explained, and reported. The explainer can trace any
  package's presence in the plan back through the proof to the original
  dependency that required it. When something goes wrong, the system
  tells you why.

== Looking ahead
<looking-ahead>
portage-ng is a living project. Several directions remain open for
exploration:

- #strong[Broader platform support.] The reasoning engine is not tied to
  Gentoo --- any system that can express its dependencies as structured
  rules could use the same prover and ordering laws.

- #strong[Richer learning.] The current constraint learning mechanism
  handles version domains and parent narrowing. More sophisticated
  strategies --- learning across multiple proof runs, or sharing learned
  constraints between cluster workers --- could further reduce proving
  time.

- #strong[Tighter LLM integration.] The explainer already bridges proof
  traces and natural language. Future work could let users ask
  higher-level questions ("why is my build slow?", "what changed since
  last week?") and receive answers grounded in the formal proof
  structure.

- #strong[Binary package support.] As Gentoo's binary package
  infrastructure matures, portage-ng could reason about mixed
  source/binary strategies --- deciding which packages to build from
  source and which to install from pre-built archives.

== Thank you
<thank-you>
If you have read this far, you have a thorough understanding of how
portage-ng works and why it was built this way. Whether you are using it
to manage a Gentoo system, studying it as an example of applied logic
programming, or contributing to its development --- thank you for your
interest, and welcome to the project.
