/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> QUERY
An implementation of a query language for the knowledge base
*/

:- module(query,[]).


% ******************
% QUERY declarations
% ******************

% Query essentially queries the cache facts, which are maintained
% by the knowledge base.
%
% All access to cache should happen through this module, as queries
% are optimized for efficiency.
%
% We deal with queries from command line:
%
%    1. qualified target searches
%    2. key=value search pairs
%
% As well as other queries from ebuild, printer, grapher, builder
% through a flexible query language which includes:
%
%    - negation (filtering of results)
%    - all (collecting all results)
%    - model (backtracks over solutions for a given statement))


% -------------
% Query: Search
% -------------

% Traverse a list of statements that narrow down the search results.


%! query:search(Query)

search([],_Repository://_Entry) :- !.
  % cache:ordered_entry(_Repository,_Entry,_,_,_).

search([Statement|Rest],Repository://Entry) :-
  !,
  search(Statement,Repository://Entry),
  search(Rest,Repository://Entry).


% Search predicates

% Case : a not statement

search(not(Statement),Repository://Entry) :-
  !,
  not(search(Statement,Repository://Entry)).


% Case : an all statement (single argument)

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values],
  !,
  findall(InnerValue,
          (InnerStatement =.. [Key,InnerValue],
           search([InnerStatement],
           Repository://Entry)),
          Values).


% Case : an all statement (dual argument)

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values,Filter],
  !,
  findall([InnerValueA,Filter],
          (InnerStatement =.. [Key,InnerValueA,Filter],
           search([InnerStatement],
           Repository://Entry)),
          Values).


% Case : a model statement,

search(model(Statement),Repository://Id) :-
  Statement =.. [Key,Model],
  !,
  StatementA =.. [Key,AllValues],
  query([all(StatementA)],Repository://Id),
  prover:model(AllValues,ModelValues),
  findall(V,
   (member(V,ModelValues),
    not(V =.. [package_dependency|_]),
    not(V =.. [use_conditional_group|_]),
    not(V =.. [exactly_one_of_group|_]),
    not(V =.. [any_of_group|_]),
    not(V =.. [all_of_group|_])),
   Model).


% Case : a latest statement, returs only latest version

search(latest(Statement),R://I) :-
  search(Statement,R://I),!.


% Case : world

search(world,R://I) :-
  preference:world(World),
  member(R://I:_,World).


% Case : set

search(set(Name),R://I) :-
  preference:set(Name,Set),
  member(R://I:_,Set).



% ------------------------------------
% Search: command line key=value pairs
% ------------------------------------

% Searching via command line key=value pairs

search(repository(notequal(R)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,_,_,_).

search(repository(equal(R)),R://I) :-
  !,
  cache:ordered_entry(R,I,_,_,_).

search(category(notequal(C)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,C,_,_).

search(category(equal(C)),R://I) :-
  !,
  cache:ordered_entry(R,I,C,_,_).

search(name(notequal(N)),R://I) :-
  !,
  \+ cache:ordered_entry(R,I,_,N,_).

search(name(equal(N)),R://I) :-
  !,
  cache:ordered_entry(R,I,_,N,_).

search(set(notequal(S)),R://I) :-
  !,
  preference:set(S,Set),
  \+ member(R://I:_,Set).

search(set(equal(S)),R://I) :-
  !,
  preference:set(S,Set),
  member(R://I:_,Set).

search(version(V),R://I) :-
  !,
  V =.. [Comparator,RequestedVersion],
  cache:ordered_entry(R,I,_,_,ProposedVersion),
  apply_version_filter(Comparator,ProposedVersion,RequestedVersion).


% ------------------------
% Search: Qualified target
% ------------------------

% A Qualified target is defined in the EAPI spec as:
%
%  <operator><repository>://<category/<package>-<version>:<slot>[<usedeps>]
%
% or
%
%  <operator><category><package>-<version>:<slot>[<usedeps>]
%
% or
%
%  <operator><package>-<version>:<slot>[<usedeps>]
%
% where <operator>, <version>, <slot> and <usedeps are optional.
%
% The provided EAPI parser converts this to a
%
%  qualified_target(operator,repository,category,package,version,filters)
%
% where filters is a list of slot and usedep constraints.
% where operator is one of:
%
%    - greaterequal
%    - greater
%    - smallerequal
%    - smaller
%    - tilde
%    - equal
%    - notequal
%    - none
%
% In case repository is not provided, it is supplied as an unbound variable
% In case category is not provided, it is supplied as an unbound variable
%
% Version is defined in EAPI spec and is essentially a list of:
%
%    - Numberpart, (an atom. e.g. 6.5.4)
%    - Alphapart, (an atom e.g. dev)
%    - Suffixpart, (an atom. e.g. _alpha, _beta, _pre, _rc, -r)
%    - Fullversion, (an atom combining number, alpha and suffix. E.g. 6.5.4dev-r1
%
% In case version is not provided, it is supplied as a list of empty atoms i.e. ['','','','']
%
% Filter is a list that can be empty. It contains lists as elements, each with filters.
% e.g. [[slot(4)],[usedep([positive(useflag),negative(otheruseflag)])]]


% Instead of using a generator, generating a lot of backtrack points, and filtering
% out options, we try to maximize usage of the JIT indexing of prolog.
%
% Essentially, repository, category, package name and even version can be hashed,
% permitting hash indexed-lookup or cache predicates, limiting the choicepoints.
%
% This search based on qualified_target makes lookup initial lookup very fast. We
% apply filtering on the remaining choicepoints.


% Case 1: No operator, no version

search(qualified_target(none,R,C,P,[[],'','','',''],F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,_),
   apply_filters(R://I,F).

% Case 2: No operator, version

search(qualified_target(none,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,V),
   apply_filters(R://I,F).

% Case 3: Operator, version

search(qualified_target(O,R,C,P,V,F),R://I) :-
   !,
   cache:ordered_entry(R,I,C,P,PV),
   apply_version_filter(O,PV,V),
   apply_filters(R://I,F).


% ----------------
% Search: Manifest
% ----------------

search(manifest(Type,Binary,Size),R://I) :-
   !,
   cache:ordered_entry(R,I,Category,Name,_),
   knowledgebase:query(all(src_uri(Model)),R://I),
   member(uri(_,_,Binary),Model),
   cache:manifest(R,P,_,Category,Name),
   cache:manifest_metadata(R,P,Type,Binary,Size,_Checksums).


% ------------
% Search: iuse
% ------------

search(iuse(Iuse),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Value),
  eapi:strip_use_default(Value,Iuse).


% --------------------------------
% Search: iuse with use flag state
% --------------------------------

search(iuse(Iuse,State:Reason),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Value),
  eapi:categorize_use(Value,State,Reason),
  eapi:strip_use_default(Value,Iuse).

% -------------------------------
% Search: iuse without use_expand
% -------------------------------

search(iuse_filtered(Iuse),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:strip_use_default(Arg,Iuse),
  not(eapi:check_use_expand_atom(Iuse)).


% ----------------------------------------------------
% Search: iuse without use_expand, with use flag state
% ----------------------------------------------------

search(iuse_filtered(Iuse,State:Reason),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:categorize_use(Arg,State,Reason),
  eapi:strip_use_default(Arg,Iuse),
  not(eapi:check_use_expand_atom(Iuse)).


% ------------------
% Search: use expand
% ------------------

search(Statement,R://I) :-
  Statement =.. [Key,Value],
  eapi:use_expand(Key),!,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:strip_use_default(Arg,ArgB),
  eapi:check_prefix_atom(Key,ArgB),
  eapi:strip_prefix_atom(Key,ArgB,Value).


% --------------------------------------
% Search: use expand with use flag state
% --------------------------------------

search(Statement,R://I) :-
  Statement =.. [Key,Value,State:Reason],
  eapi:use_expand(Key),!,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:categorize_use(Arg,State,Reason),
  eapi:strip_use_default(Arg,ArgB),
  eapi:check_prefix_atom(Key,ArgB),
  eapi:strip_prefix_atom(Key,ArgB,Value).


% ----------------
% Search: Metadata
% ----------------

% metadata can be anything, so this needs to be at the bottom

search(Q,R://I) :-
  !,
  Q =.. [Key,Value],
  Value =.. [equal,PureValue],
  cache:entry_metadata(R,I,Key,PureValue).


% -------------------------
% Search: Filter predicates
% -------------------------


% Filter out versions based on comparison

apply_version_filter(greater,ProposedVersion,Version) :-
  !,
  compare(>,ProposedVersion,Version).

apply_version_filter(greaterequal,ProposedVersion,Version) :-
  !,
  compare(=,ProposedVersion,Version);
  compare(>,ProposedVersion,Version).

apply_version_filter(smaller,ProposedVersion,Version) :-
  !,
  compare(<,ProposedVersion,Version).

apply_version_filter(smallerequal,ProposedVersion,Version) :-
  !,
  compare(=,ProposedVersion,Version);
  compare(<,ProposedVersion,Version).

apply_version_filter(notequal,VersionA,VersionB) :-
  VersionA == VersionB -> fail;true.

apply_version_filter(equal,Version,Version) :-
  !.

apply_version_filter(tilde,[Version,_,_,_,_],[Version,_,_,_,_]) :-
  !.


% Filtering of slot & usedep for qualified_target

apply_filters(_R://_I,[]) :- !.

apply_filters(R://I,[H|T]) :-
  !,
  apply_filter(R://I,H),
  apply_filters(R://I,T).

apply_filter(_R://_I,[]) :- !.

