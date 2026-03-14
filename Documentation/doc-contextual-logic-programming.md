# Contextual Logic Programming

CONTEXT is an object-oriented programming paradigm for Prolog, implemented in
[`Source/context.pl`](../Source/context.pl). It provides contexts (namespaces),
classes, and instances with public, protected, and private access control,
multiple inheritance, cloning, and declarative static typing of data members.

## Motivation

Standard Prolog uses a flat global namespace. As applications grow, name
collisions, uncontrolled access to dynamic predicates, and lack of modularity
become obstacles. CONTEXT addresses this by splitting the global namespace into
isolated contexts, each with their own facts and rules.

The key insight is that contexts can be **unified** and can serve as feature
terms describing software configurations -- directly connecting to Zeller's
*Unified Versioning through Feature Logic*. This makes CONTEXT both a
software engineering tool and a formal foundation for reasoning about
configurations.

## How it differs from Logtalk

The syntax is comparable to Logtalk, but the approach is fundamentally
different:

| | Logtalk | CONTEXT |
|---|---------|---------|
| **Approach** | Compile-time translation to plain Prolog | Runtime generation of guarded predicates |
| **Overhead** | Source-to-source compilation step | No compilation; contexts created dynamically |
| **Thread safety** | Varies by backend | Built-in; tokens are thread-local |
| **Feature unification** | Not supported | Contexts unify as feature terms |

Because CONTEXT works at runtime, contexts can be created, cloned, and
composed dynamically -- which portage-ng uses extensively to represent
repositories, ebuilds, and configurations as live objects.

## Core concepts

### Contexts

A context groups together clauses of a Prolog application. By default, clauses
are local to their context and invisible to other contexts unless explicitly
exported. Referencing a context is enough to create it (creation ex nihilo).

### Classes

A class is a special context that declares public, protected, and private
meta-predicates. These declarations control access during:

- **Instantiation** -- which predicates are copied into the instance
- **Inheritance** -- which predicates are visible to subclasses
- **Invocation** -- which predicates external callers may use

### Instances

Instances are dynamically created from a class. Private, public, and protected
predicates are guarded in the instance context to enforce access control.
Instances support data-member-like behaviour through special operators that
cache successful evaluations of unified context predicates.

### Operators

CONTEXT defines several operators for interacting with contexts:

| Operator | Meaning |
|----------|---------|
| `:Pred` | Call `Pred` in the current context (self-call) |
| `::Pred` | Access a data member (read) |
| `<=Pred` | Set a data member (write, replacing previous value) |
| `<+Pred` | Add a data member (append, keeping previous values) |
| `<-Pred` | Remove a data member |
| `Ctx://Pred` | Call `Pred` in a specific context |

## Example: a Person class

The following example (from [`Source/Examples/person.pl`](../Source/Examples/person.pl))
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
?- person::newinstance(pieter).
?- pieter::person('Pieter').
?- pieter::set_age(40).
?- pieter::get_name(Name).
Name = 'Pieter'.
?- pieter::get_age(Age).
Age = 40.
```

Private members like `age/1` cannot be accessed directly from outside the
instance -- only through the public interface.

## How portage-ng uses CONTEXT

portage-ng uses CONTEXT throughout its architecture:

- **Repositories** are context instances. Each Portage tree, overlay, or VDB
  is a live object with its own cached facts and query interface.
- **Ebuilds** carry context terms as feature-term lists. When the prover
  processes dependencies, contexts are merged via feature-unification,
  preserving provenance, USE constraints, slot locks, and ordering information.
- **Configuration** objects (profiles, `/etc/portage` settings) are contexts
  that can be composed and queried.

The connection to Zeller's feature logic is not just theoretical: the prover's
context-union operation (`sampler:ctx_union`) uses the same unification
semantics to merge dependency contexts, enabling prescient proving and
constraint propagation across the dependency graph.

## Further reading

- A. Zeller, *Unified Versioning through Feature Logic*, 1997
- [`Source/context.pl`](../Source/context.pl) -- full implementation
- [`Documentation/doc-context-terms.md`](doc-context-terms.md) -- how context
  terms flow through the prover
