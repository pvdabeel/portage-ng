/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------


/** <module> EAPI
A  DCG Grammar for Parsing Gentoo EAPI Metadata
-----------------------------------------------

This file implements a Definite Clause Grammar (DCG) for parsing metadata in
Gentoo's md5-cache and Manifest files, compatible with EAPI version 8 and earlier
(verified against the PMS specifications for EAPI 8, Sections 7, 12.1, and 12.2).

It is part of portage-ng, a next-generation replacement for Gentoo's Portage
package manager, written in SWI-prolog.

-------------------------------------------------------------------------------
 * Overview
-------------------------------------------------------------------------------

The Gentoo ebuild repository consists of a directory structure containing ebuild
(bash scripts) and a metadata/md5-cache subdirectory. Each ebuild defines
environment variables that represent metadata about a software package. The
md5-cache directory contains files corresponding to each ebuild, capturing the
values of these environment variables after the ebuild is processed by bash
(sourcing its eclasses and functions).

These cache files are distributed with ebuilds to end-users for package
installation. If an md5-cache file is missing or outdated (e.g., due to an ebuild
update), the package manager will regenerate it.

Additionally, Gentoo repositories include Manifest files in each category/package
directory, which store information for files referenced by ebuilds.

This DCG grammar parses both md5-cache and Manifest files, converting their
metadata into prolog facts which are stored in the cache database structure.
(Cfr. cache.pl).

The knowledge base ensures these predicates remain synchronized with the md5-cache
files in the repository, and will regenerate missing or outdated md5-cache.


-------------------------------------------------------------------------------
 * Valid input
-------------------------------------------------------------------------------

1. md5-cache Files

Location: Inside the metadata/md5-cache directory of a Gentoo repository.
Purpose:  Store metadata for each ebuild, reflecting.
Format:   Each file contains KEY=VALUE pairs, with one pair per line (PMS EAPI 8,
          Section 12.1).


2. Manifest Files

Location: In each category/package directory of the repository.
Purpose:  Contain hash information for files referenced by ebuilds in the
          category/package.
Format:   Each file contains KEY VALUE pairs, with one pair per line (PMS EAPI 8,
          Section 12.2).


-------------------------------------------------------------------------------
 * Grammar Specifications
-------------------------------------------------------------------------------

The DCG grammar adheres to the specifications in the PMS EAPI 8 document
(pms-8.pdf), located in the project's documentation directory.


-------------------------------------------------------------------------------
 * Reading & Parsing
-------------------------------------------------------------------------------

These lines are read by the reader (cfr. reader.pl) and then parsed by the parser
(cfr. parser.pl) using the grammar described in this file. The output is stored
in the cache (cfr. cache.pl) by during execution of the knowledgebase (cfr
knowledgebase.pl) sync command.


-------------------------------------------------------------------------------
 * Output
-------------------------------------------------------------------------------

The grammar produces SWI-Prolog facts representing the metadata from md5-cache
and Manifest files. These facts are stored in dynamic cache predicates, which
the portage-ng knowledge base keeps synchronized with the repository's md5-cache
files.
*/

:- module(eapi, []).


% =============================================================================
%  EAPI declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  EAPI abstract syntax
% -----------------------------------------------------------------------------

% The result of parsing my contain the following abstract syntax constructs:

eapi:abstract_syntax_construct(package_dependency(_,_,_,_,_,_,_,_)) :- !.
eapi:abstract_syntax_construct(use_conditional_group(_,_,_,_)) :- !.
eapi:abstract_syntax_construct(any_of_group(_)) :- !.
eapi:abstract_syntax_construct(all_of_group(_)) :- !.
eapi:abstract_syntax_construct(at_most_one_of_group(_)) :- !.
eapi:abstract_syntax_construct(exactly_one_of_group(_)) :- !.

% See cache.pl for the data structure in the parser output is stored.


% -----------------------------------------------------------------------------
%  EAPI parse
% -----------------------------------------------------------------------------

%! eapi:parse(+Type, +Repository://+Entry, +Codes, -Metadata)
%
% Predicate used to invoke the parser on a list of character codes
% (PMS EAPI 8, Sections 12.1 and 12.2).
%
% Type:       Manifest or Metadata
%
% Repository: An atom describing the Repository being parsed
% Entry:      An atom describing the Entry being parsed
%
% Codes:      A list of codes, representing a line in a cache file
%             A line contains a key=value pair.
%
% Metadata:   A Prolog predicate, i.e., key(value)

eapi:parse(Type, Repository://Entry, Codes, Metadata) :-
  phrase(eapi:keyvalue(Type, Repository://Entry, Metadata), Codes).


% -----------------------------------------------------------------------------
%  EAPI keyvalue structure
% -----------------------------------------------------------------------------

%! DCG eapi:keyvalue/1
%
% Predicate used to turn EAPI 'key=value' and 'key value' pairs into Prolog
% key(value) pairs (PMS EAPI 8, Sections 12.1 and 12.2).

eapi:keyvalue(Type, Repository://Entry, Metadata) -->
  eapi:key(Type, Key), !,
  eapi:value(Key, Repository://Entry, Metadata).


% -----------------------------------------------------------------------------
%  EAPI metadata key structure
% -----------------------------------------------------------------------------

%! DCG eapi:key/3
%
% Predicate used to retrieve the key from an EAPI 'key=value' pair or 'key value'
% manifest (PMS EAPI 8, Sections 12.1 and 12.2).
%
% private predicate

eapi:key(metadata, Key) -->
  eapi:chars_to_equal(Cs),
  { atom_codes(Key, Cs), ! }.

eapi:key(manifest, Key) -->
  eapi:chars_to_space(Cs),
  { atom_codes(Key, Cs), ! }.

eapi:key(query, [Key, M]) -->
  eapi:chars_to_comparator(Cs, M),
  { atom_codes(Key, Cs), ! }.


% -----------------------------------------------------------------------------
%  EAPI value structure
% -----------------------------------------------------------------------------

%! DCG eapi:value/3
%
% Predicate used to retrieve the value corresponding to a given key.
% Also returns corresponding Prolog declaration (PMS EAPI 8, Section 7).
%
% private predicates

% PMS EAPI 8, Section 7.2.2
eapi:value('DEFINED_PHASES', _, defined_phases(P)) -->
  !,
  eapi:functions(P).

% PMS EAPI 8, Section 7.2.3
eapi:value('DEPEND', R://E, depend(D)) -->
  !,
  eapi:depend(R://E, D).

% PMS EAPI 8, Section 7.2.4
eapi:value('DESCRIPTION', _, description(D)) -->
  !,
  eapi:description(D).

% PMS EAPI 8, Section 7.2.5
eapi:value('EAPI', _, eapi(E)) -->
  !,
  eapi:eapi(E).

% PMS EAPI 8, Section 7.2.6
eapi:value('HOMEPAGE', _, homepage(H)) -->
  !,
  eapi:homepage(H).

% PMS EAPI 8, Section 7.2.7
eapi:value('IUSE', R://E, iuse(I)) -->
  !,
  eapi:iuse(R://E, I).

% PMS EAPI 8, Section 7.2.8
eapi:value('KEYWORDS', _, keywords(K)) -->
  !,
  eapi:keywords(K).

% PMS EAPI 8, Section 7.2.9
eapi:value('LICENSE', R://E, license(L)) -->
  !,
  eapi:license(R://E, L).

% PMS EAPI 8, Section 7.2.3
eapi:value('RDEPEND', R://E, rdepend(D)) -->
  !,
  eapi:rdepend(R://E, D).

% PMS EAPI 8, Section 7.2.11
eapi:value('SLOT', _, slot(S)) -->
  !,
  eapi:slot(S).

% PMS EAPI 8, Section 7.2.12
eapi:value('SRC_URI', R://E, src_uri(S)) -->
  !,
  eapi:src_uri(R://E, S).

% PMS EAPI 8, Section 7.2.10
eapi:value('RESTRICT', R://E, restrict(S)) -->
  !,
  eapi:restrict(R://E, S).

% PMS EAPI 8, Section 7.2.13
eapi:value('REQUIRED_USE', R://E, required_use(U)) -->
  !,
  eapi:required_use(R://E, U).

% PMS EAPI 8, Section 7.2.3
eapi:value('PDEPEND', R://E, pdepend(D)) -->
  !,
  eapi:cdepend(R://E, D).

% PMS EAPI 8, Section 7.2.3
eapi:value('IDEPEND', R://E, idepend(D)) -->
  !,
  eapi:depend(R://E, D).

% PMS EAPI 8, Section 7.2.3
eapi:value('BDEPEND', R://E, bdepend(D)) -->
  !,
  eapi:depend(R://E, D).

% Deprecated in PMS EAPI 8, Section 7.2.3
eapi:value('PROVIDE', R://E, provide(P)) -->
  !,
  eapi:provide(R://E, P).

% PMS EAPI 8, Section 7.2.14
eapi:value('PROPERTIES', R://E, properties(P)) -->
  !,
  eapi:properties(R://E, P).

% PMS EAPI 8, Section 12.1
eapi:value('_eclasses_', _, eclasses(C)) -->
  !,
  eapi:inherited(C).

% PMS EAPI 8, Section 12.1
eapi:value('_md5_', _, md5([R])) -->
  !,
  eapi:md5(R).

 % PMS EAPI 8, Section 12.2
eapi:value('EBUILD', _, manifest(ebuild, F, S, H)) -->
  !,
  eapi:manifest(F, S, H).

% PMS EAPI 8, Section 12.2
eapi:value('MISC', _, manifest(misc, F, S, H)) -->
  !,
  eapi:manifest(F, S, H).

 % PMS EAPI 8, Section 12.2
eapi:value('AUX', _, manifest(aux, F, S, H)) -->
  !,
  eapi:manifest(F, S, H).

% PMS EAPI 8, Section 12.2
eapi:value('DIST', _, manifest(dist, F, S, H)) -->
  !,
  eapi:manifest(F, S, H).

% PMS EAPI 8, Section 12.1
eapi:value(_, _, unused(U)) -->
  !,
  eapi:unused(U).


% -----------------------------------------------------------------------------
%  EAPI DCG value types
% -----------------------------------------------------------------------------
%
% Grammars invoked for parsing the different value types

%! DCG depend
%
% EAPI 8 - 8.2 defines a dependency as a dependency sequence.
% Elements of the dependency sequence are packages (PMS EAPI 8, Section 8.2).

eapi:depend(R://E, D) -->
  eapi:dependencies(package_d, R://E, D).


%! DCG rdepend
%
% EAPI 8 - 8.2 defines a runtime dependency as a dependency sequence.
% Elements of the dependency sequence are packages (PMS EAPI 8, Section 8.2).

eapi:rdepend(R://E, D) -->
  eapi:dependencies(package_r, R://E, D).


%! DCG src_uri
%
% EAPI 8 - 8.2.6 defines a src_uri as a dependency sequence.
% Elements of the dependency sequence are URIs (PMS EAPI 8, Section 7.2.12).

eapi:src_uri(R://E, S) -->
  eapi:dependencies(uri, R://E, S).


%! DCG restrict
%
% EAPI 8 - 8.2.5 defines a restrict as a dependency sequence.
% Elements of the dependency sequence are restrict strings
% (PMS EAPI 8, Section 7.2.10).

eapi:restrict(R://E, S) -->
  eapi:dependencies(restrict, R://E, S).


%! DCG homepage
%
% EAPI 8 - 7.2.6 defines a homepage as a list of URIs.
% Homepage URIs tend to include a wide range of non-standard
% characters, as opposed to src_uri. For this reason, parsing
% homepage is a simple operation, capturing the entire URI as a string
% (PMS EAPI 8, Section 7.2.6).

eapi:homepage([H]) -->
  eapi:chars_to_end(Hs),
  { atom_codes(H, Hs), ! }.


%! DCG license
%
% EAPI 8 - 7.2.9 defines a license as a dependency sequence.
% Elements of the dependency sequence are license strings
% (PMS EAPI 8, Section 7.2.9).

eapi:license(R://E, L) -->
  eapi:dependencies(license, R://E, L).


%! DCG description
%
% EAPI 8 - 7.2.4 defines a description as unparsed text
% (PMS EAPI 8, Section 7.2.4).

eapi:description([D]) -->
  eapi:chars_to_end(Ds),
  { string_codes(D, Ds), ! }.


%! DCG properties
%
% EAPI 8 - 7.2.14 defines properties as a dependency sequence.
% Elements of the dependency sequence are property strings
% (PMS EAPI 8, Section 7.2.14).

eapi:properties(R://E, P) -->
  eapi:dependencies(property, R://E, P).


%! DCG manifest
%
% A Manifest contains a filename, file size, and hashes
% (PMS EAPI 8, Section 12.2).

eapi:manifest(F, S, H) -->
  eapi:chars_to_space(Fs),
  eapi:chars_to_space(Ss),
  eapi:chars_to_end(Hs),
  { atom_codes(F, Fs),
    number_codes(S, Ss),
    string_codes(H, Hs), ! }.


%! DCG unused
%
% Some fields in a cache struct are currently unused.
% This grammar is used to parse those entries as a char sequence
% (PMS EAPI 8, Section 12.1).

eapi:unused([]) -->
  eapi:skip_to_end.


%! DCG cdepend
%
% EAPI 8 - 8.2 defines cdepend as a dependency sequence.
% Elements of the sequence are typically packages
% (PMS EAPI 8, Section 7.2.3).

eapi:cdepend(R://E, D) -->
  eapi:dependencies(package_c, R://E, D).


%! DCG provide
%
% EAPI 8 - 7.2.3 defines provide as a dependency sequence.
% Elements of the sequence must be virtuals. Deprecated in EAPI 8
% (PMS EAPI 8, Section 7.2.3).

eapi:provide(_, P) -->
  eapi:chars_to_end(Ps),
  { atom_codes(P, Ps), ! }.


%! DCG dependencies
%
% EAPI 8 - 8.2 Grammar for parsing DEPEND, RDEPEND, and PDEPEND
% (PMS EAPI 8, Section 8.2).
%
% Parses zero or more dependencies, separated by whitespace.

eapi:dependencies(T, R://E, [D|Rs]) -->
  eapi:whites,
  eapi:dependency(T, R://E, D), !,
  eapi:dependencies(T, R://E, Rs).

eapi:dependencies(_, _, []) -->
  [], !.


%! DCG dependency
%
% EAPI 8 - 8.2 defines multiple types of dependencies
% (PMS EAPI 8, Section 8.2).

eapi:dependency(T, R://E, D) -->
  eapi:use_conditional_group(T, R://E, D), !.

eapi:dependency(T, R://E, D) -->
  eapi:any_of_group(T, R://E, D), !.

eapi:dependency(T, R://E, D) -->
  eapi:all_of_group(T, R://E, D), !.

eapi:dependency(T, R://E, D) -->
  eapi:exactly_one_of_group(T, R://E, D), !.

eapi:dependency(T, R://E, D) -->
  eapi:at_most_one_of_group(T, R://E, D), !.

eapi:dependency(package_d, R://E, D) -->
  eapi:package_dependency(install, R://E, D).

eapi:dependency(package_r, R://E, D) -->
  eapi:package_dependency(run, R://E, D).

eapi:dependency(package_c, R://E, D) -->
  eapi:package_dependency(compile, R://E, D).

eapi:dependency(license, _, D) -->
  eapi:string(Ds),
  { atom_codes(D, Ds), ! }.

eapi:dependency(property, _, D) -->
  eapi:string(Ds),
  { atom_codes(D, Ds), ! }.

eapi:dependency(restrict, _, D) -->
  eapi:string(Ds),
  { atom_codes(D, Ds), ! }.

eapi:dependency(uri, _, D) -->
  eapi:uri(D), !.

eapi:dependency(use, _, D) -->
  eapi:required_use_flag(D), !.


% -----------------------------------------------------------------------------
%  DCG qualified_package
% -----------------------------------------------------------------------------

%! DCG qualified_package
%
% EAPI 8 - 8.2.6 defines a qualified package
% (PMS EAPI 8, Section 8.2.6).

eapi:qualified_package(C, P, V) -->
  eapi:category(C), eapi:separator, eapi:package(P), eapi:version(V), !.


% -----------------------------------------------------------------------------
%  DCG qualified_target
% -----------------------------------------------------------------------------

%! eapi:qualified_target(Query)
%
% Parses command line targets:
%
%  world
%  @set
%  /path/file.ebuild
%  ./path/file.ebuild
%  /path/file.tbz2
%  ./path/file.tbz2
%  Name
%  Category/Name
%  Category/Name-Version
%  Repository://Category/Name
%  Repository://Category/Name-Version
%  previous five with slot, operator and use deps
%
% Returns a knowledgebase query

eapi:qualified_target(world) -->
  [119, 111, 114, 108, 100],!.                           % world

eapi:qualified_target(S) -->                             % @set
  eapi:set(S),!.

eapi:qualified_target(path(Qa)) -->                      % relative path, either tbz or ebuild
  [46],!,
  uri_chars(Q),
  { atom_codes(Qa,[46|Q]),! }.

eapi:qualified_target(path(Qa)) -->                      % absolute path, either tbz or ebuild
  [47],!,
  uri_chars(Q),
  { atom_codes(Qa,[47|Q]),! }.

eapi:qualified_target(Q) -->
  eapi:operator(O),
  eapi:repository(R),                                    % required
  eapi:repositoryseparator,!,                            % required
  eapi:category(C),eapi:separator,eapi:package(P),       % required
  eapi:version0(V),                                      % optional
  eapi:slot_restriction(S),                              % optional
  eapi:use_dependencies(U),                              % optional
  { Q = qualified_target(O,R,C,P,V,[S,U]) }.

eapi:qualified_target(Q) -->
  eapi:operator(O),                                      % optional
  eapi:category(C),eapi:separator,!,                     % required
  eapi:package(P),!,                                     % required
  eapi:version0(V),                                      % optional
  eapi:slot_restriction(S),                              % optional
  eapi:use_dependencies(U),                              % optional
  { Q = qualified_target(O,_,C,P,V,[S,U]) }.

eapi:qualified_target(Q) -->
  eapi:operator(O),                                      % optional
  eapi:package(P),!,                                     % required
  eapi:version0(V),                                      % optional
  eapi:slot_restriction(S),                              % optional
  eapi:use_dependencies(U),                              % optional
  { Q = qualified_target(O,_,_,P,V,[S,U]) }.


% -----------------------------------------------------------------------------
%  DCG query
% -----------------------------------------------------------------------------

%! eapi:query(R)
%
% Turns a key=value command line query into a select(Key,Comparator,Value) query

eapi:query([select(Key,Comparator,Value)|R]) -->
  [Atom],
  { atom_codes(Atom,Codes), phrase(eapi:querypart(Key,Comparator,Value),Codes),! },
  eapi:query(R).

eapi:query([]) -->
  [].

eapi:querypart(Key,Comparator,Value) -->
  eapi:key(query,[Key,Comparator]),
  eapi:querypartcont(Key,Value).

eapi:querypartcont(version,V) -->
  !,
  eapi:version0(V).

eapi:querypartcont(eapi,V) -->
  !,
  eapi:version0(V).

eapi:querypartcont(keywords,V) -->
  !,
  eapi:keyword(V).

eapi:querypartcont(iuse,V) -->
  !,
  eapi:iuse(_,[V]).

eapi:querypartcont(_,Value) -->
  eapi:chars_to_end(Codes),
  { atom_codes(Value,Codes) }.


% -----------------------------------------------------------------------------
%  DCG dependency types
% -----------------------------------------------------------------------------

%! DCG package_dependency
%
% EAPI 8 - 8.2.6 defines package dependency
% (PMS EAPI 8, Section 8.2.6).

eapi:package_dependency(T, _R://_E, package_dependency(T, B, C, P, O, V, S, U)) -->
  eapi:blocking(B),                                      % optional
  eapi:operator(O),                                      % optional
  eapi:category(C), eapi:separator, !, eapi:package(P),  % required
  eapi:version0(V),                                      % optional
  eapi:slot_restriction(S),                              % optional
  eapi:use_dependencies(U).                              % optional


%! DCG use_conditional_group
%
% EAPI 8 - 8.2.3 defines a use conditional dependency
% (PMS EAPI 8, Section 8.2.3).

eapi:use_conditional_group(T, R://E, use_conditional_group(P, U, R://E, D)) -->
  eapi:use_exclamation(P),                               % optional
  eapi:use_flag(U),                                      % required
  [63], !,                                               % required char: ?
  eapi:whites,                                           % optional
  [40],                                                  % required char: (
  eapi:dependencies(T, R://E, D),                        % optional
  eapi:whites,                                           % optional
  [41].                                                  % required char: )


%! DCG any_of_group
%
% EAPI 8 - 8.2.2 defines an any-of-group dependency
% (PMS EAPI 8, Section 8.2.2).

eapi:any_of_group(T, R://E, any_of_group(D)) -->
  eapi:choice, !,                                        % required
  eapi:whites,                                           % optional
  [40],                                                  % required char: (
  eapi:dependencies(T, R://E, D),                        % optional
  eapi:whites,                                           % optional
  [41].                                                  % required char: )


%! DCG all_of_group
%
% EAPI 8 - 8.2.1 defines an all-of-group dependency
% (PMS EAPI 8, Section 8.2.1).

eapi:all_of_group(T, R://E, all_of_group(D)) -->
  [40], !,                                               % required char: (
  eapi:dependencies(T, R://E, D),                        % optional
  eapi:whites,                                           % optional
  [41].                                                  % required char: )


%! DCG exactly_one_of_group
%
% EAPI 8 - 8.2.4 defines an exactly_one_of dependency
% (PMS EAPI 8, Section 8.2.4).

eapi:exactly_one_of_group(T, R://E, exactly_one_of_group(D)) -->
  eapi:one_of, !,
  eapi:whites,
  [40], !,                                               % required char: (
  eapi:dependencies(T, R://E, D),                        % optional
  eapi:whites,                                           % optional
  [41].                                                  % required char: )


%! DCG at_most_one_of_group
%
% EAPI 8 - 8.2.5 defines an at_most_one_of dependency
% (PMS EAPI 8, Section 8.2.5).

eapi:at_most_one_of_group(T, R://E, at_most_one_of_group(D)) -->
  eapi:at_most_one, !,
  eapi:whites,
  [40], !,                                               % required char: (
  eapi:dependencies(T, R://E, D),                        % optional
  eapi:whites,                                           % optional
  [41].                                                  % required char: )


% -----------------------------------------------------------------------------
%  DCG blocking types
% -----------------------------------------------------------------------------

%! DCG blocking
%
% EAPI 8 - 8.2.6 defines the block operator for package dependencies
% (PMS EAPI 8, Section 8.2.6).

eapi:blocking(strong) -->
  [33,33], !.                                            % char: !!

eapi:blocking(weak) -->
  [33], !.                                               % char: !

eapi:blocking(no) -->
  [], !.


% -----------------------------------------------------------------------------
%  DCG operator types
% -----------------------------------------------------------------------------

%! DCG operator
%
% EAPI 8 - 8.2.6 defines the operators for package dependencies
% (PMS EAPI 8, Section 8.2.6).

eapi:operator(greaterequal) -->
  [62,61], !.                                            % char: >=

eapi:operator(greaterequal) -->
  [61,62], !.                                            % char: =>

eapi:operator(smallerequal) -->
  [60,61], !.                                            % char: <=

eapi:operator(smallerequal) -->
  [61,60], !.                                            % char: =<

eapi:operator(greater) -->
  [62], !.                                               % char: >

eapi:operator(smaller) -->
  [60], !.                                               % char: <

eapi:operator(tilde) -->
  [126], !.                                              % char: ~

eapi:operator(tilde) -->
  [58,61], !.                                            % char: :=

eapi:operator(equal) -->
  [61], !.                                               % char: =

eapi:operator(none) -->
  [], !.


% -----------------------------------------------------------------------------
%  DCG subtypes
% -----------------------------------------------------------------------------

%! DCG repository
%
% Repository Names (PMS EAPI 8, Section 8.2.6).

eapi:repository(Ra) -->
  eapi:chars1(c, R),
  { atom_codes(Ra, R), ! }.


%! DCG set
%
% Set Names (PMS EAPI 8, Section 8.2.6).

eapi:set([64|Sa]) -->
  [64], !,
  eapi:chars1(c, S),
  { atom_codes(Sa, S), ! }.


%! DCG category
%
% EAPI 8 - 3.1.1 Category Names (PMS EAPI 8, Section 3.1.1).

eapi:category(Ca) -->
  eapi:chars1(c, C),
  { atom_codes(Ca, C), ! }.


%! DCG separator
%
% EAPI 8 - 8.2.6 Package dependency specification (PMS EAPI 8, Section 8.2.6).

eapi:separator -->
  [47].                                                   % char: /


%! DCG repositoryseparator
%
% Repository separator (PMS EAPI 8, Section 8.2.6).

eapi:repositoryseparator -->
  [58,47,47].                                            % char: ://


%! DCG package
%
% EAPI 8 - 3.1.2 Package Names (PMS EAPI 8, Section 3.1.2).

eapi:package(P) -->
  eapi:pchars(L),
  { eapi:check_package(L),
    eapi:convert_package(L, P), ! }.


%! eapi:check_package(+L)
%
% Case: don't do any checks if package is just one chunk

eapi:check_package(L) :-
  length(L, 1), !.


%! eapi:check_package(+L)
%
% Case: check if package is valid, if there are more than one chunk

eapi:check_package(L) :-
  lists:reverse(L, [E, B|_]),
  \+(eapi:invalid_package_ending(E, B)).


%! eapi:convert_package(+L, -P)
%
% Converts a list of chunks to string

eapi:convert_package(L, P) :-
  maplist(atom_codes, R, L),
  atomic_list_concat(R, '-', P).


%! eapi:invalid_package_ending(+E, +B)
%
% Case: last chunk is a version

eapi:invalid_package_ending(E, _) :-
  phrase(eapi:version2(_), E, []), !.

%! eapi:invalid_package_ending(+E, +B)
%
% Case: last chunk is a revision AND the chunk before is a version

eapi:invalid_package_ending(E, B) :-
  phrase(eapi:versionrevision(_), E, []),
  phrase(eapi:version2(_), B, []), !.


%! DCG version
%
% EAPI 8 - 3.2 defines version specification (PMS EAPI 8, Section 3.2).

eapi:version(V) -->
  eapi:version2([N, W, A, S]),
  { eapi:version2atom(N, W, A, S, V) }.


%! DCG version0
%
% eapi:version0 starts with '-', and can be empty

eapi:version0(V) -->
  eapi:version2([N, W, A, S]),
  { eapi:version2atom(N, W, A, S, V) }.

eapi:version0([[], '', '', '', '']) -->
  [].


%! DCG version2
%
% eapi:version2 reads a version following EAPI 8 spec

eapi:version2([N, W, A, S]) -->
  eapi:versionnumberpart(N, W),
  eapi:versionalphapart(A),
  eapi:versionsuffixpart(S).

eapi:version2([[], '', '', '']) -->
  [], !.


%! DCG versionsuffixpart
%
% eapi: versionsuffixpart following EAPI 8 specs

eapi:versionsuffixpart([S|R]) -->
  eapi:versionsuffix(S),
  eapi:versionsuffixpart(R).

eapi:versionsuffixpart([]) -->
  [].


%! DCG versionnumberpart
%
% eapi: versionnumberpart following EAPI 8 specs

eapi:versionnumberpart([C|V], W) -->
  eapi:versioninteger(C, _),
  [46], !,
  eapi:versionnumberpart0(V, W).

eapi:versionnumberpart([C], W) -->
  eapi:versioninteger(C, W), !.


%! DCG versionnumberpart0
%
% eapi: versionnumberpart0 following EAPI 8 specs

eapi:versionnumberpart0([C|V], W) -->
  eapi:versioninteger(C, _),
  [46], !,
  eapi:versionnumberpart0(V, W).

eapi:versionnumberpart0([C], W) -->
  eapi:versioninteger(C, W), !.

eapi:versionnumberpart0([], _) -->
  [], !.


%! DCG versionalphapart
%
% eapi: versionalphapart following EAPI 8 specs

eapi:versionalphapart([C]) -->
  eapi:versionalpha(C), !.

eapi:versionalphapart([]) -->
  [], !.


%! DCG versionsuffix
%
% eapi: versionsuffix following EAPI 8 specs

eapi:versionsuffix([95,97,108,112,104,97|V]) -->
  [95,97,108,112,104,97],                               % _alpha
  !,
  eapi:versioninteger2(V, _).

eapi:versionsuffix([95,98,101,116,97|V]) -->
  [95,98,101,116,97],                                   % _beta
  !,
  eapi:versioninteger2(V, _).

eapi:versionsuffix([95,112,114,101|V]) -->
  [95,112,114,101],                                     % _pre
  !,
  eapi:versioninteger2(V, _).

eapi:versionsuffix([95,114,99|V]) -->
  [95,114,99],                                          % _rc
  !,
  eapi:versioninteger2(V, _).

eapi:versionsuffix([95,112|V]) -->
  [95,112],                                             % _p
  !,
  eapi:versioninteger2(V, _).

eapi:versionsuffix([45,114|V]) -->                      % -r
  [45,114],
  !,
  eapi:versioninteger(V, _).

eapi:versionrevision([114|V]) -->                       % (-)r
  [114],
  !,
  eapi:versioninteger(V, _).


%! DCG versioninteger
%
% eapi:versioninteger - reads integers (and detect integer wildcard)

eapi:versioninteger([], '*') -->
  [42], !.

eapi:versioninteger([C|V], W) -->
  [C],
  { code_type(C, digit), ! },
  eapi:versioninteger2(V, W).


%! DCG versioninteger2
%
% eapi:versioninteger2 - continuation of versioninteger

eapi:versioninteger2([], '*') -->
  [42], !.

eapi:versioninteger2([C|V], W) -->
  [C],
  { code_type(C, digit), ! },
  eapi:versioninteger2(V, W).

eapi:versioninteger2([], '') -->
  [].


%! DCG versionalpha
%
% eapi:versionalpha reads alpha

eapi:versionalpha([C]) -->
  [C],
  { code_type(C, alpha), ! }.


%! DCG md5
%
% EAPI 8 - 12.1 defines _md5_ metadata (PMS EAPI 8, Section 12.1).

eapi:md5(M) -->
  eapi:chars1(m, Ms),
  { atom_codes(M, Ms) }.


%! DCG slot_restriction
%
% EAPI 8 - 8.2.6 defines slot restriction (PMS EAPI 8, Section 8.2.6).

eapi:slot_restriction([any_different_slot]) -->
  [58,42], !.                                            % char: :*

eapi:slot_restriction([any_same_slot]) -->
  [58,61], !.                                            % char: :=

eapi:slot_restriction(S) -->
  [58], !,                                               % char: :
  eapi:slot(S).

eapi:slot_restriction([]) -->
  [], !.


%! DCG use_dependencies
%
% EAPI 8 - 8.2.6 defines use dependencies (PMS EAPI 8, Section 8.2.6).

eapi:use_dependencies(U) -->
  [91], !,                                               % char: [
  eapi:whites,
  eapi:use_dependency_list(U),
  eapi:whites,
  [93].                                                  % char: ]

eapi:use_dependencies([]) -->
  [], !.


%! DCG use_dependency_list
%
% EAPI 8 - 8.2.6 defines use dependency list as comma-separated
% list of use flags (PMS EAPI 8, Section 8.2.6).

eapi:use_dependency_list([use(U, D)|R]) -->
  eapi:use_dependency(U, D),
  eapi:whites,
  eapi:comma, !,
  eapi:whites,
  eapi:use_dependency_list(R).

eapi:use_dependency_list([use(U, D)]) -->
  eapi:use_dependency(U, D), !,
  eapi:whites.

eapi:use_dependency_list([]) -->
  [], !.


%! DCG use_dependency
%
% EAPI 8 - 8.2.6 defines use dependency syntax
% (PMS EAPI 8, Section 8.2.6).

eapi:use_dependency(inverse(U), D) -->
  [33],                                                  % char: !
  eapi:use_flag(U),
  eapi:use_default(D),
  [61].                                                  % char: =

eapi:use_dependency(equal(U), D) -->
  eapi:use_flag(U),
  eapi:use_default(D),
  [61].                                                  % char: =

eapi:use_dependency(optdisable(U), D) -->
  [33], !,                                               % char: !
  eapi:use_flag(U),
  eapi:use_default(D),
  [63].                                                  % char: ?

eapi:use_dependency(optenable(U), D) -->
  eapi:use_flag(U),
  eapi:use_default(D),
  [63], !.                                               % char: ?

eapi:use_dependency(disable(U), D) -->
  [45], !,                                               % char: -
  eapi:use_flag(U),
  eapi:use_default(D).

eapi:use_dependency(enable(U), D) -->
  eapi:use_flag(U),
  eapi:use_default(D).


%! DCG use_default
%
% EAPI 8 - 8.2.6 defines use default syntax
% (PMS EAPI 8, Section 8.2.6).

eapi:use_default(positive) -->
  [40,43,41], !.                                         % chars: (+)

eapi:use_default(negative) -->
  [40,45,41], !.                                         % chars: (-)

eapi:use_default(none) -->
  [], !.


%! DCG use_exclamation
%
% EAPI 8 - 8.2.3 defines use_exclamation (PMS EAPI 8, Section 8.2.3).

eapi:use_exclamation(negative) -->
  [33], !.                                               % char: !

eapi:use_exclamation(positive) -->
  [], !.


%! DCG required_use
%
% EAPI 8 - 7.2.13 defines required use as a list of use flags, with
% conditional, XOR, and OR relationships (PMS EAPI 8, Section 7.2.13).

eapi:required_use(Hash, U) -->
  eapi:dependencies(use, Hash, U).


%! DCG required_use_flag
%
% Required use flag syntax (PMS EAPI 8, Section 7.2.13).

eapi:required_use_flag(blocking(U)) -->
  [33], !,
  eapi:use_flag(U).

eapi:required_use_flag(required(U)) -->
  eapi:use_flag(U).


%! DCG iuse
%
% EAPI 8 - 7.2.7 defines iuse as a list of use flags, each possibly
% prefixed with a '+' or a '-' to indicate status
% (PMS EAPI 8, Section 7.2.7).

eapi:iuse(R://E, [plus(U)|Rs]) -->
  [43], !,                                               % char: +
  eapi:use_flag(U),
  eapi:whites,
  eapi:iuse(R://E, Rs).

eapi:iuse(R://E, [minus(U)|Rs]) -->
  [45], !,                                               % char: -
  eapi:use_flag(U),
  eapi:whites,
  eapi:iuse(R://E, Rs).

eapi:iuse(R://E, [U|Rs]) -->
  eapi:use_flag(U), !,
  eapi:whites,
  eapi:iuse(R://E, Rs).

eapi:iuse(_, []) -->
  [], !.


%! DCG keywords
%
% EAPI 8 - 7.2.8 defines keywords as a list of individual keywords,
% each possibly prefixed with a '~' or a '-' char to indicate status
% (PMS EAPI 8, Section 7.2.8).

eapi:keywords([K|R]) -->
  eapi:keyword(K), !,
  eapi:whites,
  eapi:keywords(R).

eapi:keywords([]) -->
  [], !.


%! DCG keyword
%
% EAPI 8 - 7.2.8 defines a keyword as a sequence of chars, each
% possibly prefixed with a '~' or a '-' char to indicate status
% (PMS EAPI 8, Section 7.2.8).

eapi:keyword(unstable(Ka)) -->
  [126], !,                                              % char: ~
  eapi:kchars(K),
  { atom_codes(Ka, K) }.

eapi:keyword(broken(Ka)) -->
  [45], !,                                               % char: -
  eapi:kchars(K),
  { atom_codes(Ka, K) }.

eapi:keyword(stable(Ka)) -->
  eapi:kchars(K), !,
  { atom_codes(Ka, K) }.


%! DCG inherited
%
% Identical to functions (PMS EAPI 8, Section 12.1).

eapi:inherited([[eclass(F), md5(M)]|R]) -->
  eapi:function(F), !,
  eapi:whites,
  eapi:md5(M), !,
  eapi:whites,
  eapi:inherited(R).

eapi:inherited([]) -->
  [], !.


%! DCG functionslist
%
% A line of functions (PMS EAPI 8, Section 7.2.2).

eapi:functions([F|R]) -->
  eapi:function(F), !,
  eapi:whites,
  eapi:functions(R).

eapi:functions([]) -->
  [], !.


%! DCG function
%
% Some cache entries have '-' as functions list (PMS EAPI 8, Section 7.2.2).

eapi:function('-') -->
  [45], !.                                               % char: -

eapi:function(F) -->
  eapi:chars1(f, FL),
  { atom_codes(F, FL), ! }.


%! DCG string
%
% Strings are defined as sequences of generic chars,
% separated by whites (PMS EAPI 8, Sections 7.2.9, 7.2.10, 7.2.14).

eapi:string(S) -->
  eapi:chars1(s, S).


%! DCG stringlist
%
% A list of strings (PMS EAPI 8, Sections 7.2.9, 7.2.10, 7.2.14).

eapi:stringlist([S|R]) -->
  eapi:string(S), !,
  eapi:whites,
  eapi:stringlist(R).

eapi:stringlist([]) -->
  [], !.


%! DCG use_flag
%
% Use flags are defined in EAPI 8 - 7.2.7 and 8.2.6
% (PMS EAPI 8, Sections 7.2.7, 8.2.6).

eapi:use_flag(Ua) -->
  eapi:chars1(u, U),
  { atom_codes(Ua, U), ! }.


%! DCG choice
%
% EAPI 8 - 8.2.2 Used for identifying an any_of_group
% (PMS EAPI 8, Section 8.2.2).

eapi:choice -->
  [124,124].                                             % char: ||


%! DCG one_of
%
% EAPI 8 - 8.2.4 Used for identifying a one_of group
% (PMS EAPI 8, Section 8.2.4).

eapi:one_of -->
  [94,94].                                              % char: ^^


%! DCG at_most_one
%
% EAPI 8 - 8.2.5 Used for identifying an at_most group
% (PMS EAPI 8, Section 8.2.5).

eapi:at_most_one -->
  [63,63].                                               % char: ??


%! DCG comma
%
% EAPI 8 - 8.2.6 Used for use_dependencies_list
% (PMS EAPI 8, Section 8.2.6).

eapi:comma -->
  [44].                                                  % char: ,


%! DCG virtual
%
% EAPI 8 - 3.1.2 defines a virtual (PMS EAPI 8, Section 3.1.2).
% Deprecated in EAPI 8 (PMS EAPI 8, Section 7.2.3).

eapi:virtual([virtual(A)]) -->
  [118, 105, 114, 116, 117, 97, 108], !,                % virtual
  eapi:separator,
  eapi:package(A).


%! DCG slot
%
% EAPI 8 - 7.2.11 defines subslot names (PMS EAPI 8, Section 7.2.11).

eapi:slot([slot(V)|Cont]) -->
  eapi:slot_version(V),
  eapi:slot_cont(Cont).

eapi:slot_cont([equal]) -->
  [61], {!}.                                             % char: =

eapi:slot_cont([subslot(V)|Cont]) -->
  [47], {!},                                             % char: /
  eapi:slot_version(V),
  eapi:slot_cont(Cont).

eapi:slot_cont([]) -->
  {!}.


%! DCG slot_version
%
% EAPI 8 - 7.2.11 defines a slot version (PMS EAPI 8, Section 7.2.11).

eapi:slot_version(Va) -->
  eapi:chars1(v, V),
  { atom_codes(Va, V) }.


%! DCG subslot
%
% EAPI 8 - 7.2.11 defines subslot names (PMS EAPI 8, Section 7.2.11).

eapi:subslot(S) -->
  [47],                                                  % char: /
  eapi:version0(S).


%! DCG eapi
%
% EAPI 8 - 7.2.5 defines the EAPI as a version. The EAPI is used to
% indicate syntax version level (PMS EAPI 8, Section 7.2.5).

eapi:eapi([V]) -->
  eapi:version2([N, W, A, S]),
  { eapi:version2atom(N, W, A, S, V) }.


%! DCG uri
%
% EAPI 8 - 7.2.12 defines URI (PMS EAPI 8, Section 7.2.12).


% DCG uri CASE: a prototyped URI

eapi:uri(uri(P, B, L)) -->
  eapi:proto(Ps),                                        % required
  [58,47,47], !,                                         % required ://
  eapi:uri_chars(Bs),                                    % required
  eapi:arrow(Ls),                                        % optional
  { atom_codes(P, Ps),
    atom_codes(B, Bs),
    Ls = [] -> file_base_name(B, L) ; atom_codes(L, Ls), ! }.


% DCG uriCASE: a non-prototyped URI

eapi:uri(uri('', '', P)) -->
  eapi:uri_chars1(Ps),
  { atom_codes(P, Ps), ! }.


%! DCG protocol
%
% EAPI 8 - 7.2.12 defines proto as part of a URI (PMS EAPI 8, Section 7.2.12).

eapi:proto(P) -->
  eapi:chars1(p, P).


%! DCG arrow
%
% EAPI 8 - 7.2.12 defines '->' followed by a string
% as an allowed URI construct (PMS EAPI 8, Section 7.2.12).

eapi:arrow(L) -->
  eapi:whites,
  [45,62], !,                                            % chars: ->
  eapi:whites,
  eapi:local(L).

eapi:arrow([]) -->
  [], !.


%! DCG local
%
% EAPI 8 - 7.2.12 defines '->' followed by a string
% as an allowed URI construct (PMS EAPI 8, Section 7.2.12).

eapi:local(L) -->
  eapi:uri_chars(L).


%! DCG timestamp
%
% metadata/timestamp.x contains a float, followed
% by human-readable datetime (PMS EAPI 8, Section 12.1).

eapi:timestamp(T) -->
  eapi:chars1(t, C),
  { number_codes(T, C) }.


% -----------------------------------------------------------------------------
%  REGULAR CHAR SEQUENCES
% -----------------------------------------------------------------------------

%! DCG uri_chars
%
% This reads all chars until a URI stopchar is encountered
% EAPI 8 allows for ( and ) in src_uri (PMS EAPI 8, Section 7.2.12).

eapi:uri_chars([]) -->
  [41,32], { !, fail }.                                  % char: )

eapi:uri_chars([]) -->
  [40,32], { !, fail }.                                  % char: (

eapi:uri_chars([C|R]) -->
  [C], { \+(code_type(C, white)), ! },
  eapi:uri_chars(R).

eapi:uri_chars([]) -->
  [], !.


%! DCG uri_chars1
%
% This reads all chars until a URI-specific stopchar is encountered
% EAPI 8 allows for ( and ) in src URI (PMS EAPI 8, Section 7.2.12).
% Needs at least 1 char

eapi:uri_chars1([C|R]) -->
  [C], { \+(code_type(C, white)), \+(C = 41), ! },
  eapi:uri_chars(R).


%! DCG chars1
%
% Reads one or more chars of the specified type (PMS EAPI 8, Sections 3.1, 7, 8).

eapi:chars1(Type, [C|T]) -->
  eapi:char(Type, C), !,
  eapi:chars0(Type, T).


%! DCG chars0
%
% Reads none or more chars of the specified type (PMS EAPI 8, Sections 3.1, 7, 8).

eapi:chars0(Type, C) -->
  eapi:chars1(Type, C), !.

eapi:chars0(_, []) -->
  [], !.


%! DCG char
%
% Reads a char of a specified type (PMS EAPI 8, Sections 3.1, 7, 8).

eapi:char(T, C) -->
  [C],
  { jumprule(T, C), ! }.


%! DCG jumprule
%
% CHAR jumptable

% EAPI 8 - 3.1.1: A category name may contain '-','_','+','.' and alphanumeric chars
% (PMS EAPI 8, Section 3.1.1)

eapi:jumprule(c, 45) :- !.                               % char: '-'
eapi:jumprule(c, 95) :- !.                               % char: '_'
eapi:jumprule(c, 43) :- !.                               % char: '+'
eapi:jumprule(c, 46) :- !.                               % char: '.'
eapi:jumprule(c, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.7: A use flag name may contain '-','_','+','@','.', and alphanumeric chars
% (PMS EAPI 8, Section 7.2.7)

eapi:jumprule(u, 45) :- !.                               % char: '-'
eapi:jumprule(u, 95) :- !.                               % char: '_'
eapi:jumprule(u, 43) :- !.                               % char: '+'
eapi:jumprule(u, 64) :- !.                               % char: '@'
eapi:jumprule(u, 46) :- !.                               % char: '.'
eapi:jumprule(u, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.11: A slot name may contain '-','_','+','.', and alphanumeric chars
% (PMS EAPI 8, Section 7.2.11)

eapi:jumprule(s, 45) :- !.                               % char: '-'
eapi:jumprule(s, 95) :- !.                               % char: '_'
eapi:jumprule(s, 43) :- !.                               % char: '+'
eapi:jumprule(s, 46) :- !.                               % char: '.'
eapi:jumprule(s, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.8: A keyword name may contain '-','_','+','@','.', and alphanumeric chars
% (PMS EAPI 8, Section 7.2.8)

eapi:jumprule(k, 45) :- !.                               % char: '-'
eapi:jumprule(k, 95) :- !.                               % char: '_'
eapi:jumprule(k, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 3.2: A version may contain '-','_','*','.', and alphanumeric chars
% (PMS EAPI 8, Section 3.2)

eapi:jumprule(v, 45) :- !.                               % char: '-'
eapi:jumprule(v, 95) :- !.                               % char: '_'
eapi:jumprule(v, 42) :- !.                               % char: '*'
eapi:jumprule(v, 46) :- !.                               % char: '.'
eapi:jumprule(v, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 8.2.6: A slot restriction may contain '-','_','*','.', and alphanumeric chars
% (PMS EAPI 8, Section 8.2.6)

eapi:jumprule(r, 45) :- !.                               % char: '-'
eapi:jumprule(r, 95) :- !.                               % char: '_'
eapi:jumprule(r, 42) :- !.                               % char: '*'
eapi:jumprule(r, 46) :- !.                               % char: '.'
eapi:jumprule(r, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.2: A function name may contain '-','_','+','.', and alphanumeric chars
% (PMS EAPI 8, Section 7.2.2)

eapi:jumprule(f, 45) :- !.                               % char: '-'
eapi:jumprule(f, 95) :- !.                               % char: '_'
eapi:jumprule(f, 43) :- !.                               % char: '+'
eapi:jumprule(f, 46) :- !.                               % char: '.'
eapi:jumprule(f, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.9, 7.2.10, 7.2.14: A string name may contain '-','_','+','.', and alphanumeric chars
% (PMS EAPI 8, Sections 7.2.9, 7.2.10, 7.2.14)

eapi:jumprule(s, 45) :- !.                               % char: '-'
eapi:jumprule(s, 95) :- !.                               % char: '_'
eapi:jumprule(s, 43) :- !.                               % char: '+'
eapi:jumprule(s, 46) :- !.                               % char: '.'
eapi:jumprule(s, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 7.2.12: A URI protocol name may contain '-','_','+','@','.', and alphanumeric chars
% (PMS EAPI 8, Section 7.2.12)

eapi:jumprule(p, 45) :- !.                               % char: '-'
eapi:jumprule(p, 95) :- !.                               % char: '_'
eapi:jumprule(p, 43) :- !.                               % char: '+'
eapi:jumprule(p, 46) :- !.                               % char: '.'
eapi:jumprule(p, 64) :- !.                               % char: '@'
eapi:jumprule(p, C) :- code_type(C, alnum), !.           % char: alphanumeric


% EAPI 8 - 12.1: A timestamp may contain '.' and digits
% (PMS EAPI 8, Section 12.1)

eapi:jumprule(t, 46) :- !.                               % char: '.'
eapi:jumprule(t, C) :- code_type(C, digit), !.           % char: digit


% EAPI 8 - 12.1: An md5 may contain hexadecimal chars
% (PMS EAPI 8, Section 12.1)

eapi:jumprule(m, C) :- code_type(C, alnum), !.           % char: hexadecimal


% -----------------------------------------------------------------------------
%  SPECIAL CHAR SEQS
% -----------------------------------------------------------------------------

%! DCG pchars
%
% EAPI 8 - 3.1.2 Reads a package name (PMS EAPI 8, Section 3.1.2).

% EAPI 2.1.2:  A package name may contain alphanumeric chars

eapi:pchar(C) -->
  [C],
  { code_type(C,alnum), ! }.

% EAPI 2.1.2-strict: A package name may not contain ':'

eapi:pchar(58) -->
  [58], { fail }.

% EAPI 2.1.2: A package name may contain '_'

eapi:pchar(95) -->
  [95],!.

% EAPI 4 - 2.1.2: A package name may contain '+'

eapi:pchar(43) -->
  [43],!.


%! DCG pchars
%
% A package contains one or more pchars

eapi:pchars([H|T]) -->
  eapi:pcharschunk(H),
  eapi:pchars2(T).

eapi:pchars2([H|T]) -->
  eapi:pcharschunk(H),
  eapi:pchars2(T).

eapi:pchars2([]) -->
  [],!.

eapi:pcharschunk([C|R]) -->
  eapi:pchar(C),!,
  eapi:pcharschunk2(R).

eapi:pcharschunk2([]) -->                                % a chunck ends when '-' is encountered
  [45],!.

eapi:pcharschunk2([]) -->                                % a chunck can never contain a '.'
  [46],!, { fail }.

eapi:pcharschunk2([C|R]) -->
  eapi:pchar(C),!,
  eapi:pcharschunk2(R).

eapi:pcharschunk2([]) -->
  [],!.


%! DCG uchars
%
% A use flag contains one or more uchars and must begin
% with an alphanumeric char, according to EAPI 2.1.4

eapi:uchars([C|T]) -->
  eapi:char(u,C),{ code_type(C,alnum) },!,
  eapi:uchars2(T).

eapi:uchars2([C|T]) -->
  eapi:char(u,C),!,
  eapi:uchars2(T).

eapi:uchars2([]) -->
  [],!.


%! DCG kchars
%
% EAPI 8 - 7.2.8 Reads a keyword name (PMS EAPI 8, Section 7.2.8).

% A keyword consists out of multiple kchars, the first char must be
% an alphanumeric char

eapi:kchars([42]) -->
  [42],!.                                                % char: *

eapi:kchars([C|T]) -->
  eapi:char(k,C),{ code_type(C,alnum) },!,
  eapi:uchars2(T).

eapi:kchars2(C) -->
  eapi:uchars(C).

eapi:kchars2([]) -->
  [],!.


%! DCG whites
%
% Reads none or more whitespace chars (PMS EAPI 8, Sections 7, 8).

eapi:whites -->
  [C], { code_type(C, white), ! },
  eapi:whites.

eapi:whites -->
  [], !.


%! DCG chars_to_space
%
% Reads chars until a space is found (PMS EAPI 8, Sections 12.1, 12.2).

eapi:chars_to_space([]) -->
  [32], !.

eapi:chars_to_space([C|R]) -->
  [C], !, %{ C \= 32, ! },
  eapi:chars_to_space(R).

eapi:chars_to_space([]) -->
  [], !.


%! DCG chars_to_dash
%
% collect all chars to '-'

eapi:chars_to_dash([45]) -->
  [45],!.                                                % chars: '-'

eapi:chars_to_dash([C|R]) -->
  [C],
  eapi:chars_to_dash(R).


%! DCG chars_to_comparator
%
% Reads chars until a comparator is found (PMS EAPI 8, Section 8.2.6).

eapi:chars_to_comparator([],smallerequal) -->
  [61],[60],!.                                           % chars: '=<'

eapi:chars_to_comparator([],greaterequal) -->
  [61],[62],!.                                          % chars: '=<'

eapi:chars_to_comparator([],smallerequal) -->
  [60],[61],!.                                           % chars: '<='

eapi:chars_to_comparator([],greaterequal) -->
  [62],[61],!.                                           % chars: '>='

eapi:chars_to_comparator([],smaller) -->
  [60],!.                                                % chars: '<'

eapi:chars_to_comparator([],greater) -->
  [62],!.                                                % chars: '>'

eapi:chars_to_comparator([],tilde) -->
  [126],!.                                               % chars: '~'

eapi:chars_to_comparator([],wildcard) -->
  [58,61],!.                                             % chars: ':='

eapi:chars_to_comparator([],notequal) -->
  [33],[61],!.                                           % chars: '!='

eapi:chars_to_comparator([],equal) -->
  [61],!.                                                % chars: '='

eapi:chars_to_comparator([C|T],M) -->
  [C],!,
  eapi:chars_to_comparator(T,M).


%! DCG chars_to_equal
%
% Reads chars until an equal is found (PMS EAPI 8, Section 12.1).

eapi:chars_to_equal([]) -->
  [61], !.

eapi:chars_to_equal([C|R]) -->
  [C], !, %{ C \= 61, ! },
  eapi:chars_to_equal(R).


%! DCG chars_to_end
%
% Reads chars until the end (PMS EAPI 8, Sections 7.2.4, 7.2.6).

eapi:chars_to_end([C|R]) -->
  [C], !,
  eapi:chars_to_end(R).

eapi:chars_to_end([]) -->
  [], !.


%! DCG skip_to_end
%
% Skips chars until the end (PMS EAPI 8, Section 12.1).

eapi:skip_to_end -->
  [_], !,
  eapi:skip_to_end.

eapi:skip_to_end -->
  [], !.


% -----------------------------------------------------------------------------
%  EAPI USE expand declarations
% -----------------------------------------------------------------------------

%! eapi:use_expand(Keys)
%
% Within the USE flags, some metadata is hidden that we want parsed out

eapi:use_expand('abi_mips').
eapi:use_expand('abi_ppc').
eapi:use_expand('abi_riscv').
eapi:use_expand('abi_s390').
eapi:use_expand('abi_x86').
eapi:use_expand('ada_target').
eapi:use_expand('alsa_cards').
eapi:use_expand('apache2_modules').
eapi:use_expand('apache2_mpms').
eapi:use_expand('calligra_features').
eapi:use_expand('cameras').
eapi:use_expand('collectd_plugins').
eapi:use_expand('cpu_flags_arm').
eapi:use_expand('cpu_flags_ppc').
eapi:use_expand('cpu_flags_x86').
eapi:use_expand('curl_ssl').
eapi:use_expand('elibc').
eapi:use_expand('enlightenment_modules').
eapi:use_expand('fftools').
eapi:use_expand('gpsd_protocols').
eapi:use_expand('grub_platforms').
eapi:use_expand('input_devices').
eapi:use_expand('kernel').
eapi:use_expand('l10n').
eapi:use_expand('lcd_devices').
eapi:use_expand('libreoffice_extensions').
eapi:use_expand('lirc_devices').
eapi:use_expand('llvm_targets').
eapi:use_expand('monkeyd_plugins').
eapi:use_expand('mpi_fabrics').
eapi:use_expand('netbeans_modules').
eapi:use_expand('nginx_modules_http').
eapi:use_expand('nginx_modules_mail').
eapi:use_expand('nginx_modules_stream').
eapi:use_expand('ofed_drivers').
eapi:use_expand('office_implementation').
eapi:use_expand('openmpi_ofed_features').
eapi:use_expand('openmpi_rm').
eapi:use_expand('php_targets').
eapi:use_expand('postgres_targets').
eapi:use_expand('python_single_target').
eapi:use_expand('python_targets').
eapi:use_expand('qemu_softmmu_targets').
eapi:use_expand('qemu_user_targets').
eapi:use_expand('ros_messages').
eapi:use_expand('sane_backend').
eapi:use_expand('userland').
eapi:use_expand('uwsgi_plugins').
eapi:use_expand('video_cards').
eapi:use_expand('voicemail_storage').
eapi:use_expand('xfce_plugins').
eapi:use_expand('xtables_addons').


% -----------------------------------------------------------------------------
%  Various helper predicates
% -----------------------------------------------------------------------------

%! DCG file:line
%
% From a given char list, reads one line

file:line([])    --> [10],!.
file:line([C|R]) --> [C],!,file:line(R).


%! DCG file:lines
%
% From a given char list, reads all lines

file:lines([L|R]) --> file:line(L),!, file:lines(R).
file:lines([])    --> [],!.


%! VERSION packageversion
%
% Produces version from a packagename.

packageversion(Name,Package,Version) :-
  atom_codes(Name,N),
  phrase(eapi:package(Package),N,V),
  phrase(eapi:version(Version),V,[]),!.

packageversion(_,_,_) :-
  config:failsilenton(version),!,
  fail.

packageversion(Name,_,_) :-
  message:failure(Name).


%! eapi:check_prefix_atom(+Prefix,+Atom)
%
% Predicate that checks whether an atom begins with a given Prefix

eapi:check_prefix_atom(_,Atom) :- \+(atom(Atom)), !, fail.
eapi:check_prefix_atom(Prefix,Atom) :- atom_prefix(Atom,Prefix),!.

%! eapi:strip_prefix_atom(+Prefix,+Atom,-Result)
%
% Predicate that strips a given prefix from an atom that begins with a given Prefix
% Fails otherwise

eapi:strip_prefix_atom(Prefix,Atom,Result) :-
  sub_atom(Atom,0,A,_,Prefix),
  B is A+1,
  sub_atom(Atom,B,_,0,Result).


%! eapi:strip_use_default(+Use,-NewUse)
%
% Strip plus(..) and minus(..) use default information from a use flag

eapi:strip_use_default(plus(Use),Use) :- !.
eapi:strip_use_default(minus(Use),Use) :- !.
eapi:strip_use_default(Use,Use) :- !.


%! eapi:check_use_expand_atom(+Atom)
%
% Predicate that checks whether an atom is a use_expand atom

eapi:check_use_expand_atom(Atom) :- eapi:use_expand(Key), eapi:check_prefix_atom(Key,Atom),!.


%! eapi:categorize_use(+Use,?State,?Reason))
%
% Categorize a given use flag

eapi:categorize_use(plus(Use),positive,preference) :-
  preference:use(Use),!.

eapi:categorize_use(plus(Use),negative,preference) :-
  preference:use(minus(Use)),!.

eapi:categorize_use(plus(Use),positive,ebuild) :-
  \+(preference:use(Use)),
  \+(preference:use(minus(Use))),
  !.

eapi:categorize_use(minus(Use),positive,preference) :-
  preference:use(Use),!.

eapi:categorize_use(minus(Use),negative,preference) :-
  preference:use(minus(Use)),!.

eapi:categorize_use(minus(Use),negative,ebuild) :-
  \+(preference:use(Use)),
  \+(preference:use(minus(Use))),
  !.

eapi:categorize_use(Use,positive,preference) :-
  preference:use(Use),!.

eapi:categorize_use(Use,negative,preference) :-
  preference:use(minus(Use)),!.

eapi:categorize_use(Use,negative,default) :-
  \+(preference:use(Use)),
  \+(preference:use(minus(Use))),
  \+(printer:unify(plus(_),Use)),
  \+(printer:unify(minus(_),Use)),!.


% -----------------------------------------------------------------------------
%  Helper predicates
% -----------------------------------------------------------------------------

%! eapi:version2atom(+N, +W, +A, +S, -V)
%
% eapi:version2atom converts version format to atom

eapi:version2atom(N, W, A, S, [Nn, Alphapart, Suffixpart, Fullversion]) :-
  maplist(atom_codes, Na, N),
  maplist(atom_codes, Aa, A),
  maplist(atom_codes, Sa, S),
  maplist(atom_number, Na, Nn),
  atomic_list_concat(Na, '.', Numberpart),
  atomic_list_concat(Aa, Alphapart),
  atomic_list_concat(Sa, Suffixpart),
  atomic_list_concat([Numberpart, W, Alphapart, Suffixpart], Fullversion).

eapi:version2numberlist('', []) :- !.

eapi:version2numberlist(NumberAtom, NumberList) :-
  atomic_list_concat(SplitAtoms, '.', NumberAtom),
  maplist(atom_number, SplitAtoms, NumberList).



%! eapi:substitute_sets(Query,Result)
%
% Replace world and set references in query with their content.

eapi:substitute_sets([],[]) :- !.

eapi:substitute_sets([world|Tail],Result) :-
  findall(E,world::entry(E),Targets),
  append(Targets,NewResult,Result),
  eapi:substitute_sets(Tail,NewResult).

eapi:substitute_sets([Set|Tail],Result) :-
  preference:set(Set,Targets),!,
  append(Targets,NewResult,Result),
  eapi:substitute_sets(Tail,NewResult).

eapi:substitute_sets([Query|Tail],[Query|Rest]) :-
  !,
  eapi:substitute_sets(Tail,Rest).


% -----------------------------------------------------------------------------
%  EAPI keys
% -----------------------------------------------------------------------------

%! eapi:keys(-Keys)
%
% Returns the list of metadata keys (PMS EAPI 8, Section 7).

% CASE: PMS cache version (deprecated)

% eapi:keys(['depend',
%           'rdepend',
%           'slot',
%           'src_uri',
%           'restrict',
%           'homepage',
%           'license',
%           'description',
%           'keywords',
%           'inherited',
%           'iuse',
%           'required_use',    % EAPI 4: REQUIRED_USE
%           'cdepend',         % EAPI 4: PDEPEND
%           'provide',
%           'eapi',
%           'unused',          % EAPI 4: PROPERTIES
%           'functions',       % EAPI 4: DEFINED_PHASES
%           'unused',
%           'unused',
%           'unused',
%           'unused',
%           'unused']).

%! eapi:elem(+Key,+Entry,-Content)
%
% Given a key and a pms cache entry, retrieves the element
% corresponding to the given key.
%
% Key:     The cache key
%
% Entry:   The pms cache entry
%
% Content: The content of the pms cache entry

% eapi:elem(K,E,C) :-
%   eapi:keys(S),
%   system:nth1(N,S,K),
%   system:nth1(N,E,C).


% CASE: MD5 version

eapi:elem(K,[E|_],C) :-
  E =.. [K,C],
  !.

eapi:elem(K,[_|R],C) :-
  !,
  eapi:elem(K,R,C).
