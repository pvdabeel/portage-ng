/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EAPI
This file contains a DCG grammar for Gentoo Portage cache files and manifests.
This grammar is compatible with EAPI version 7 and earlier.

Cache files:
------------
The portage cache is a directory inside the portage repository
that normally has a file for each ebuild in the portage tree.
In this file, metadata regarding the ebuild can be found.

The metadata inside this file is represented as KEY=VALUE pairs.
Each line has one KEY=VALUE pair.

Manifest files:
---------------
The DCG grammar also parses Manifest files.
Manifest files are found in the portage repository in each category/package
directory. For a given category and package combination, the manifest
contains hash information for all files referenced by the ebuilds in this 
category/package. 

The metadata inside this file is representated as KEY VALUE pairs.
Each line has one KEY VALUE pair. 

The specifications of the grammar can be found in the documentation
directory of this project.
*/

:- module(eapi, []).

% ----------
% EAPI parse
% ----------

%! eapi:parse(+Type,+Codes,-Metadata)
%
% Predicate used to invoke the parser on a list of metadata codes
%
% Type:     Manifest or Metadata
%
% Codes:    A list of codes, representing a line in a cache file
%           A line contains a key=value pair.
%
% Metadata: A prolog predicate, i.e. key(value)

eapi:parse(Type,Codes,Metadata) :-
  phrase(eapi:keyvalue(Type,Metadata),Codes).


% -----------------------
% EAPI keyvalue structure
% -----------------------

%! DCG eapi:keyvalue/1
%
% Predicate used to turn eapi 'key=value' and 'key value' pairs into prolog
% key(value) pairs

eapi:keyvalue(Type,Metadata) -->
  eapi:key(Type,Key),!,
  eapi:value(Key,Metadata).


% ---------------------------
% EAPI metadata key structure
% ---------------------------

%! DCG eapi:metadata_key/1
%
% Predicate used to retrieve the key from an eapi 'key=value' pair or 'key value' manifest.
%
% private predicate

eapi:key(metadata,Key) -->
  eapi:chars_to_equal(Cs),
  { string_codes(Key,Cs),! }.

eapi:key(manifest,Key) -->
  eapi:chars_to_space(Cs),
  { string_codes(Key,Cs),! }.


% --------------------
% EAPI value structure
% --------------------

%! DCG eapi:value/3
%
% Predicate used to retrieve the value corresponding to a given key.
% Also returns corresponding prolog declaration
%
% private predicates

eapi:value("DEFINED_PHASES",defined_phases(R)) -->
  !,
  eapi:functions(R).

eapi:value("DEPEND",depend(R)) -->
  !,
  eapi:depend(R).

eapi:value("DESCRIPTION",description(R)) -->
  !,
  eapi:description(R).

eapi:value("EAPI",eapi(R)) -->
  !,
  eapi:eapi(R).

eapi:value("HOMEPAGE",homepage(R)) -->
  !,
  eapi:homepage(R).

eapi:value("IUSE",iuse(R)) -->
  !,
  eapi:iuse(R).

eapi:value("KEYWORDS",keywords(R)) -->
  !,
  eapi:keywords(R).

eapi:value("LICENSE",license(R)) -->
  !,
  eapi:license(R).

eapi:value("RDEPEND",rdepend(R)) -->
  !,
  eapi:rdepend(R).

eapi:value("SLOT",slot(R)) -->
  !,
  eapi:slot(R).

eapi:value("SRC_URI",src_uri(R)) -->
  !,
  eapi:src_uri(R).

eapi:value("RESTRICT",restrict(R)) -->
  !,
  eapi:restrict(R).

eapi:value("REQUIRED_USE",required_use(R)) -->
  !,
  eapi:required_use(R).

eapi:value("PDEPEND",pdepend(R)) -->
  !,
  eapi:cdepend(R).

eapi:value("PROVIDE",provide(R)) -->
  !,
  eapi:provide(R).

eapi:value("PROPERTIES",properties(R)) -->
  !,
  eapi:properties(R).

eapi:value("_eclasses_",eclasses(R)) -->
  !,
  eapi:inherited(R).

eapi:value("_md5_",md5(R)) -->
  !,
  eapi:md5(R).

eapi:value("EBUILD",manifest(ebuild,F,S,H)) -->
  !,
  eapi:manifest(F,S,H).

eapi:value("MISC",manifest(misc,F,S,H)) -->
  !,
  eapi:manifest(F,S,H).

eapi:value("AUX",manifest(aux,F,S,H)) -->
  !,
  eapi:manifest(F,S,H).

eapi:value("DIST",manifest(dist,F,S,H)) -->
  !,
  eapi:manifest(F,S,H).

eapi:value(_,unused(R)) -->
  !,
  eapi:unused(R).


% --------------------
% EAPI DCG value types
% --------------------
%
% Grammars invoked for parsing the different value types
%
% private predicates


%! DCG depend
%
% EAPI 4 - 9.2 defines a dependency as a dependency sequence.
% Elements of the dependency sequence are packages.

eapi:depend(D) -->
  eapi:dependencies(package_d,D).


%! DCG rdepend
%
% EAPI 4 - 9.2 defines a runtime dependency as a dependency sequence.
% Elements of the dependency sequence are packages.

eapi:rdepend(D) -->
  eapi:dependencies(package_r,D).


%! DCG src_uri
%
% EAPI 4 - 9.2.6 defines a src_uri as a dependency sequence.
% Elements of the dependency sequence are uri's.

eapi:src_uri(S) -->
  eapi:dependencies(uri,S).


%! DCG restrict
%
% EAPI 4 - 9.2.5 defines a restrict as a dependency sequence.
% Elements of the dependency sequence are restrict strings.

eapi:restrict(R) -->
  eapi:dependencies(restrict,R).


%! DCG homepage
%
% EAPI 4 - 9.2 defines a homepage as a dependency sequence.
% Elements of the dependency sequence are uri's.
%
% Homepage uri's tend to include a wide range of non-standard
% characters, as opposed to src_uri. For this reason parsing
% homepage is an expensive operation. In the current revision
% of this eapi parser, homepages are not parsed, unless needed.

eapi:homepage(H) -->
  eapi:chars_to_end(Hs),
  { string_codes(H,Hs),! }.


%! DCG license
%
% EAPI 4 - 9.2 defines a license as a dependency sequence.
% Elements of the dependency sequence are license strings.

eapi:license(L) -->
  eapi:dependencies(license,L).


%! DCG description
%
% EAPI 2.0 defines a description as an unparsed element. This
% is basically pure text information.

eapi:description(D) -->
  eapi:chars_to_end(Ds),
  { string_codes(D,Ds),! }.


%! DCG properties
%
% EAPI defines properties as a dependency sequence
% Elements of the dependency sequence are property strings.

eapi:properties(P) --> 
  eapi:dependencies(property,P).


%! DCG manifest
%
% A Manifest contains a filename, file size, and hashes

eapi:manifest(F,S,H) -->
  eapi:chars_to_space(Fs),
  eapi:chars_to_space(Ss),
  eapi:chars_to_end(Hs),
  { string_codes(F,Fs),
    string_codes(S,Ss),
    string_codes(H,Hs),! }.


%! DCG unused
%
% Some of the fields in a cache struct are currently unused.
% This grammar is used to parse those entries. Basically they
% are treated as a char sequence.

eapi:unused([]) -->
  eapi:skip_to_end.


%! DCG cdepend
%
% EAPI 4 - 9.2 defines cdepend as a dependency sequence. Elements
% of the sequence are typically packages.

eapi:cdepend(D) -->
  eapi:dependencies(package_c,D).


%! DCG provide
%
% EAPI 4 - 9.2 defines provide as a dependency sequence. Elements
% of the sequence must be virtuals.

eapi:provide(P) -->
  eapi:chars_to_end(Ps),
  { string_codes(P,Ps),! }.
  %eapi:dependencies(virtual,P).


%! DCG dependencies
%
% EAPI 4 - 9.1 Grammar for parsing DEPEND, RDEPEND and PDEPEND
%
% Parses zero or more dependencies, separated by whites

eapi:dependencies(T,[D|R]) -->
  eapi:whites,
  eapi:dependency(T,D), !,
  eapi:dependencies(T,R).

eapi:dependencies(_,[]) -->
  [],!.


%! DCG dependency
%
% EAPI 4 - 9.2 defines 4 types of dependencies

eapi:dependency(T,D) -->
  eapi:use_conditional_group(T,D),!.

eapi:dependency(T,D) -->
  eapi:any_of_group(T,D),!.

eapi:dependency(T,D) -->
  eapi:all_of_group(T,D),!.

eapi:dependency(T,D) -->
  eapi:exactly_one_of_group(T,D),!.

eapi:dependency(T,D) -->
  eapi:at_most_one_of_group(T,D),!.

eapi:dependency(package_d,D) -->
  eapi:package_dependency(install,D). %!

eapi:dependency(package_r,D) -->
  eapi:package_dependency(run,D). %!

eapi:dependency(package_c,D) -->
  eapi:package_dependency(compile,D). %!


% eapi:dependency(virtual,D) -->   % Virtuals can now also have versions, and are treated via package_dependency
%  eapi:virtual(D),!.

eapi:dependency(license,D) -->
  eapi:string(Ds),
  { atom_codes(D,Ds),! }.

eapi:dependency(property,D) -->
  eapi:string(Ds),
  { atom_codes(D,Ds),! }.

eapi:dependency(restrict,D) -->
  eapi:string(D),!.

eapi:dependency(uri,D) -->
  eapi:uri(D),!.


%! DCG qualified_package
%
% EAPI 4 - 9.2 defines a qualified package

eapi:qualified_package(C,P,V) -->
  eapi:category(C),eapi:separator,eapi:package(P),eapi:version(V),!.


%! DCG package_dependency
%
% EAPI 4 - 9.2.4 defines package dependency

eapi:package_dependency(T,package_dependency(T,B,C,P,O,V,S,U)) -->
  eapi:blocking(B),                                   % optional
  eapi:operator(O),                                   % optional
  eapi:category(C),eapi:separator,!,eapi:package(P),  % required
  eapi:version0(V),                                   % optional
  eapi:slot_restriction(S),                           % optional
  eapi:use_dependencies(U).                           % optional


%! DCG use_conditional_group
%
% EAPI 4 - 9.2.2 defines a use conditional dependency

eapi:use_conditional_group(T,use_conditional_group(P,U,D)) -->
  eapi:use_exclamation(P),                            % optional
  eapi:use_flag(U),                                   % required
  [63],!,                                             % required char: ?
  eapi:whites,                                        % optional
  [40],                                               % required char: (
  eapi:dependencies(T,D),                             % optional
  eapi:whites,                                        % optional
  [41].                                               % required char: )


%! DCG any_of_group
%
% EAPI 4 - 9.2.3 defines an any-of-group dependency

eapi:any_of_group(T,any_of_group(D)) -->
  eapi:choice,!,                                      % required
  eapi:whites,                                        % optional
  [40],                                               % required char: (
  eapi:dependencies(T,D),                             % optional
  eapi:whites,                                        % optional
  [41].                                               % required char: )


%! DCG all_of_group
%
% EAPI 9.2.1 defines an all-of-group dependency

eapi:all_of_group(T,all_of_group(D)) -->
  [40],!,                                             % required char: (
  eapi:dependencies(T,D),                             % optional
  eapi:whites,                                        % optional
  [41].                                               % required char: )


%! DCG exactly_one_of_group
%
% EAPI 5 - 8.2.0 defines an exactly_one_of dependency

eapi:exactly_one_of_group(T,exactly_one_of_group(D)) -->
  eapi:one_of,!,
  eapi:whites,
  [40],!,                                             % required char: (
  eapi:dependencies(T,D),                             % optional
  eapi:whites,                                        % optional
  [41].                                               % required char: )


%! DCG at_most_one_of_group
%
% EAPI 5 - 8.2.0 defines an at_most_one_of dependency

eapi:at_most_one_of_group(T,exactly_one_of_group(D)) -->
  eapi:at_most_one,!,
  eapi:whites,
  [40],!,                                             % required char: (
  eapi:dependencies(T,D),                             % optional
  eapi:whites,                                        % optional
  [41].                                               % required char: )


%! DCG blocking
%
% EAPI 4 - 9.2.4 defines the block operator for package dependencies

eapi:blocking(strong) -->
  [33,33],!.                                          % char: !!

eapi:blocking(weak) -->
  [33],!.                                             % char: !

eapi:blocking(no) -->
  [],!.


%! DCG operator
%
% EAPI 4 - 9.2.4 defines the operators for package dependencies

eapi:operator(greaterequal) -->
  [62,61], !.                                         % char: >=

eapi:operator(greaterequal) -->
  [61,62], !.                                         % char: =>

eapi:operator(smallerequal) -->
  [60,61], !.                                         % char: <=

eapi:operator(smallerequal) -->
  [61,60], !.                                         % char: =<

eapi:operator(greater) -->
  [62], !.                                            % char: >

eapi:operator(smaller) -->
  [60], !.                                            % char: <

eapi:operator(tilde) -->
  [126], !.                                           % char: ~

eapi:operator(equal) -->
  [61], !.                                            % char: =

eapi:operator(none) -->
  [], !.


%! DCG: category
%
% EAPI 4 - 2.1.1 Category Names

eapi:category(Ca) -->
  eapi:chars1(c,C),
  { atom_codes(Ca,C),! }.


% DCG: separator
%
% EAPI 4 - 9.2.4 Package dependency specification

eapi:separator -->
  [47].                                               % char: /


%! DCG: package
%
% EAPI 4 - 2.1.1 Package Names

eapi:package(P) -->
  eapi:pchars(L),
  { eapi:check_package(L),
    eapi:convert_package(L,P),! }.



% Case: don't do any checks if package is just one chunck

eapi:check_package(L) :-
  length(L,1),!.

% Case: check if package is valid, if there are more than one chunck

eapi:check_package(L) :-
  reverse(L,[E,B|_]),
  not(eapi:invalid_package_ending(E,B)).


% Converts a list of chuncks to atom

eapi:convert_package(L,P) :-
  maplist(atom_codes,R,L),
  atomic_list_concat(R,'-',P).


% Case: last chunk is a version

eapi:invalid_package_ending(E,_) :-
  phrase(eapi:version2(_),E,[]),!.

% Case: last chunk is a revision AND the chunk before is a version

eapi:invalid_package_ending(E,B) :-
  phrase(eapi:versionrevision(_),E,[]),
  phrase(eapi:version2(_),B,[]),!.



%! DCG: version
%
% EAPI 5 - 3.2 defines version specification


% eapi:version starts with '-', and cannot be empty

eapi:version(V) -->
%  [45],!,                                            % char: -
  eapi:version2([N,S]),
  { eapi:version2atom(N,S,V) }.

%eapi:version('') -->
%  [],!.



% eapi:version0 starts with '-', and can be empty

eapi:version0(V) -->
%  [45],
  eapi:version2([N,S]),
  { eapi:version2atom(N,S,V) }.

eapi:version0('') -->
  [].



% eapi:version2 reads a version following EAPI 5 spec

eapi:version2([C,S]) -->
  eapi:versionnumberpart(C),
  eapi:versionsuffixpart(S).

eapi:version2([]) -->
  [],!.


% eapi: versionsuffixpart following eapi 5 specs

eapi:versionsuffixpart([S|R]) -->
  eapi:versionsuffix(S),
  eapi:versionsuffixpart(R).

eapi:versionsuffixpart([]) -->
  [].


% eapi: versionnumberpart following eapi 5 specs

eapi:versionnumberpart([C,[46]|V]) -->
  eapi:versioninteger(C),
  [46],!,
  eapi:versionnumberpart(V).

eapi:versionnumberpart([C|V]) -->
  eapi:versioninteger(C),
  eapi:versionalphapart(V),!.

eapi:versionnumberpart([C]) -->
  eapi:versioninteger(C),!.

eapi:versionnumberpart([]) -->
  [],!.


% eapi: versionalphapart following eapi 5 specs

eapi:versionalphapart([C]) -->
  eapi:versionalpha(C).


% eapi: versionsuffix following eapi 5 specs

eapi:versionsuffix([95,97,108,112,104,97|V]) -->
  [95,97,108,112,104,97],			      % _alpha
  !,
  eapi:versioninteger2(V).

eapi:versionsuffix([95,98,101,116,97|V]) -->
  [95,98,101,116,97],				      % _beta
  !,
  eapi:versioninteger2(V).

eapi:versionsuffix([95,112,114,101|V]) -->
  [95,112,114,101],				      % _pre
  !,
  eapi:versioninteger2(V).

eapi:versionsuffix([95,114,99|V]) -->
  [95,114,99],					      % _rc
  !,
  eapi:versioninteger2(V).

eapi:versionsuffix([95,112|V]) -->
  [95,112],					      % _p
  !,
  eapi:versioninteger2(V).

eapi:versionsuffix([45,114|V]) -->		      % -r
  [45,114],
  !,
  eapi:versioninteger(V).

% eapi:versionsuffix([]) -->
%   [],!.



eapi:versionrevision([114|V]) -->		      % (-)r
  [114],
  !,
  eapi:versioninteger(V).


% eapi:versioninteger - reads integers

eapi:versioninteger([42|V]) -->
  [42],
  eapi:versioninteger2(V).


eapi:versioninteger([C|V]) -->
  [C],
  { code_type(C,digit),! },
  eapi:versioninteger2(V).


eapi:versioninteger2([42|V]) -->
  [42],
  eapi:versioninteger(V).

eapi:versioninteger2(V) -->
  eapi:versioninteger(V),!.

eapi:versioninteger2([]) -->
  [].


% eapi:versionalpha reads alpha

eapi:versionalpha([C]) -->
  [C],
  { code_type(C,alpha), !}.


% eapi:version2atom converts version format to atom

eapi:version2atom(N,S,A) :-
  maplist(atom_codes,Na,N),
  maplist(atom_codes,Sa,S),
  atomic_list_concat(Na,Naa),
  atomic_list_concat(Sa,Saa),
  atomic_list_concat([Naa,Saa],A).


%! DCG: md5
%
% EAPI 5 - defines _md5_ metadata

eapi:md5(M) -->
  eapi:pchars(Ms),
  { convlist(codes_string,Ms,M) }.

codes_string(A,B) :- string_codes(B,A),!.


%! DCG: slot_restriction
%
% EAPI 4 - 9.2.4 defines slot restriction

eapi:slot_restriction(any_different_slot) -->
  [58,42],!.                                          % char:  :*

eapi:slot_restriction(any_same_slot) -->
  [58,61],!.                                          % char:  :=

eapi:slot_restriction(S) -->
  [58],!,                                             % char:  :
  eapi:slot(S).

eapi:slot_restriction([]) -->
  [],!.


%! DCG: use_dependencies
%
% EAPI 4 - 9.2.4 defines 2-style use dependencies

eapi:use_dependencies(U) -->
  [91],!,                                             % char: [
  eapi:whites,
  eapi:use_dependency_list(U),
  eapi:whites,
  [93].                                               % char: ]

eapi:use_dependencies([]) -->
  [],!.


%! DCG: use_dependency_list
%
% EAPI 4 - 9.2.4 defines use dependency list as comma separated
% list of use flags

eapi:use_dependency_list([use(U,D)|R]) -->
  eapi:use_dependency(U,D),
  eapi:whites,
  eapi:comma,!,
  eapi:whites,
  eapi:use_dependency_list(R).

eapi:use_dependency_list([use(U,D)]) -->
  eapi:use_dependency(U,D),!,
  eapi:whites.

eapi:use_dependency_list([]) -->
  [],!.


%! DCG: use_dependency
%
% EAPI 4 - 9.2.4 defines 2-style use dependency syntax

eapi:use_dependency(inverse(U),D) -->
  [33],                                               % char: !
  eapi:use_flag(U),
  eapi:use_default(D),
  [61].                                               % char: =

eapi:use_dependency(equal(U),D) -->
  eapi:use_flag(U),
  eapi:use_default(D),
  [61].                                               % char: =

eapi:use_dependency(optdisable(U),D) -->
  [33],!,                                             % char: !
  eapi:use_flag(U),
  eapi:use_default(D),
  [63].                                               % char: ?

eapi:use_dependency(optenable(U),D) -->
  eapi:use_flag(U),
  eapi:use_default(D),
  [63],!.                                             % char: ?

eapi:use_dependency(disable(U),D) -->
  [45],!,                                             % char: -
  eapi:use_flag(U),
  eapi:use_default(D).

eapi:use_dependency(enable(U),D) -->
  eapi:use_flag(U),
  eapi:use_default(D).


%! DCG use_default
%
% EAPI 4 - 9.2.5.4 defines 4-style use default syntax

eapi:use_default(positive) -->
  [40,43,41],!.                                       % chars: (+)

eapi:use_default(negative) -->
  [40,45,41],!.                                       % chars: (-)

eapi:use_default(none) -->
  [],!.


%! DCG use_exclamation
%
% EAPI 4 - 9.2.2 defines use_exclamation

eapi:use_exclamation(negative) -->
  [33],!.                                             % char: !

eapi:use_exclamation(positive) -->
  [],!.


%! DCG iuse
%
% EAPI 4 - 2.1.4 defines iuse as a list of use flags, each possibly
% prefixed with a '+' or a '-' to indicate status.

eapi:iuse([plus(U)|R]) -->
  [43],!,                                             % char: +
  eapi:use_flag(U),
  eapi:whites,
  eapi:iuse(R).

eapi:iuse([minus(U)|R]) -->
  [45],!,                                             % char: -
  eapi:use_flag(U),
  eapi:whites,
  eapi:iuse(R).

eapi:iuse([U|R]) -->
  eapi:use_flag(U),!,
  eapi:whites,
  eapi:iuse(R).

eapi:iuse([]) -->
  [],!.


%! DCG required_use
%
% EAPI 4 defines required use as a list of use flags, with
% conditional, xor and or relationship.

eapi:required_use(Ua) -->
  eapi:chars_to_end(U),
  { atom_codes(Ua,U),! }.


%! DCG keywords
%
% EAPI 4 - 2.1.6 defines keywords as a list of individual keywords,
% each possibly prefixed with a '~' or a '-' char to indicate status.

eapi:keywords([K|R]) -->
  eapi:keyword(K),!,
  eapi:whites,
  eapi:keywords(R).

eapi:keywords([]) -->
  [],!.


%! DCG keyword
%
% EAPI 4 - 2.1.6 defines a keyword as a sequence of chars, each
% possibly prefixed with a '~' or a '-' char to indicate status.

eapi:keyword(unstable(Ka)) -->
  [126],!,                                            % char: ~
  eapi:kchars(K),
  { atom_codes(Ka,K) }.

eapi:keyword(broken(Ka)) -->
  [45],!,                                             % char: -
  eapi:kchars(K),
  { atom_codes(Ka,K) }.

eapi:keyword(stable(Ka)) -->
  eapi:kchars(K),!,
  { atom_codes(Ka,K) }.


%! DCG inherited
%
% Identical to functions

eapi:inherited([[eclass(F),md5(M)]|R]) -->
  eapi:function(F),!,
  eapi:whites,
  eapi:md5(M),!,
  eapi:whites,
  eapi:inherited(R).

eapi:inherited([]) -->
  [],!.


%! DCG functionslist
%
% A line of functions

eapi:functions([F|R]) -->
  eapi:function(F),!,
  eapi:whites,
  eapi:functions(R).

eapi:functions([]) -->
  [],!.


%! DCG function
%
% Some cache entries have '-' as functions list

eapi:function('-') -->
  [45],!.                                             % char: -

eapi:function(F) -->
  eapi:chars1(f,FL),
  { atom_codes(F,FL),! }.


%! DCG string
%
% Strings are defined as sequences of generic chars,
% separated by whites.

eapi:string(S) -->
  eapi:chars1(s,S).


%! DCG stringlist
%
% A list of strings

eapi:stringlist([S|R]) -->
  eapi:string(S),!,
  eapi:whites,
  eapi:stringlist(R).

eapi:stringlist([]) -->
  [],!.


%! DCG use_flag
%
% Use flags are defined in EAPI 4 - 9.2.2 and 4 - 9.2.4

eapi:use_flag(Ua) -->
  eapi:chars1(u,U),
  { atom_codes(Ua,U),! }.


%! DCG choice
%
% EAPI 4 - 9.2 Used for identifying an any_of_group

eapi:choice -->
  [124,124].                                          % char: ||.


%! DCG ane_of
%
% EAPI 5 - 8.2.0 Used for identifying a one_of group

eapi:one_of -->
  [94,94].                                            % char: ^^


%! DCG at_most_one
%
% EAPI 5 - 8.2.0 Used for identifying an at_most group

eapi:at_most_one -->
  [63,63].                                            % char: ??


%! DCG comma
%
% EAPI 4 - 9.2.4 Used for use_dependencies_list

eapi:comma -->
  [44].                                               % char: ,


%! DCG virtual
%
% EAPI 4 - 2.1.1 defines a virtual

eapi:virtual([virtual(A)]) -->
  [118, 105, 114, 116, 117, 97, 108],!,               % virtual
  eapi:separator,
  eapi:package(A).



%! DCG slot
%
% EAPI 5 - 8.2.6.3 defines subslot names

eapi:slot([slot(V),subslot(SV)]) -->
  eapi:slot_version(V),
  [47],                                               % char: /
  eapi:slot_version(SV).

eapi:slot([slot(V),equal]) -->
  eapi:slot_version(V),
  [61].                                               % char: =

eapi:slot([slot(V)]) -->
  eapi:slot_version(V).


%! DCG slot_version
%
% EAPI 5 - defines a slot version

eapi:slot_version(Va) -->
%  eapi:version0(V).
  eapi:chars1(v,V),
  {
    atom_codes(Va,V)
  }.



%! DCG subslot
%
% EAPI 5 - 8.2.6.4 defines subslot names

eapi:subslot(S) -->
  [47],                                               % char: /
  eapi:version0(S).


%! DCG eapi
%
% EAPI 2.0 defines the eapi as a version. The eapi is used to
% indicate syntax version level.

eapi:eapi(E) -->
  eapi:version2(E).



% DCG uri_chars
%
% This reads all chars until an uri stopchar stopchar is encountered
% EAPI 6 allows for ( and ) in src_uri !.

eapi:uri_chars([]) -->
  [41,32], { !,fail }.                                % char: )

eapi:uri_chars([]) -->
  [40,32], { !,fail }.                                % char: (

eapi:uri_chars([C|R]) -->
  [C], { not(code_type(C,white)),! },
  eapi:uri_chars(R).

eapi:uri_chars([]) -->
  [],!.


% DCG uri_chars1
%
% This reads all chars until an uri specific stopchar is encountered
% EAPI 6 allows for ( and ) in src uri !.
% Needs at least 1 char

eapi:uri_chars1([C|R]) -->
  [C], { not(code_type(C,white)),not(C = 41), !},
  eapi:uri_chars(R).


%! DCG uri
%
% EAPI 4 - 9.2 defines URI

% -------------------------
% CASE 1 : a prototyped uri
% -------------------------

eapi:uri(uri(P,B,L)) -->
  eapi:proto(Ps),          % required
  [58,47,47],!,            % required ://
  eapi:uri_chars(Bs),      % required
  eapi:arrow(Ls),          % optional
  { string_codes(P,Ps),
    string_codes(B,Bs),
    string_codes(L,Ls),! }.

% -----------------------------
% CASE 2 : a non-prototyped uri
% -----------------------------

eapi:uri(uri(P)) -->
  eapi:uri_chars1(Ps),
  { string_codes(P,Ps),! }.


% DCG protocol
%
% EAPI 4 - 9.2 defines proto as part of an URI

eapi:proto(P) -->
  eapi:chars1(p,P).


% DCG arrow
%
% EAPI 4 - 9.2. defines '->' followed by a string
% as an allowed URI construct.

eapi:arrow(L) -->
  eapi:whites,
  [45,62],!,               % chars: ->
  eapi:whites,
  eapi:local(L).

eapi:arrow([]) -->
  [],!.


% DCG local
%
% EAPI 4 - 9.2 defines '->' followed by a string
% as an allowed URI construct

eapi:local(L) -->
  eapi:uri_chars(L).


% DCG timestamp
%
% metadata/timestamp.x contains a float, followed
% by human readable datetime

eapi:timestamp(T) -->
  eapi:chars1(t,T).


% ----------------------
% REGULAR CHAR SEQUENCES
% ----------------------

% DCG chars1
%
% Reads one or more chars of the specified type

eapi:chars1(Type,[C|T]) -->
  eapi:char(Type,C),!,
  eapi:chars0(Type,T).


% DCG chars0
%
% Reads none or more chars of the specified type

eapi:chars0(Type,C) -->
  eapi:chars1(Type,C),!.

eapi:chars0(_,[]) -->
  [],!.


% DCG char
%
% Reads a char of a specified type

eapi:char(T,C) -->
  [C],
  { eapi:jumprule(T,[C]),! }.


% CHAR jumptable

eapi:jumprule(c,[45]) :- !.                      % EAPI 2.1.1: A category name may contain '-'
eapi:jumprule(c,[95]) :- !.                      % EAPI 2.1.1: A category name may contain '_'
eapi:jumprule(c,[43]) :- !.                      % EAPI 2.1.1: A category name may contain '+'
eapi:jumprule(c,[46]) :- !.                      % EAPI 2.1.1: A category name may contain '.'
eapi:jumprule(c,[C]) :- code_type(C,alnum), !.   % EAPI 2.1.1: A category name may contain alphanumeric chars
eapi:jumprule(u,[45]) :- !.                      % EAPI 2.1.4: A use flag name may contain '-'
eapi:jumprule(u,[95]) :- !.                      % EAPI 2.1.4: A use flag name may contain '_'
eapi:jumprule(u,[43]) :- !.                      % EAPI 2.1.4: A use flag name may contain '+'
eapi:jumprule(u,[64]) :- !.                      % EAPI 2.1.4: A use flag name may contain '@'
eapi:jumprule(u,[46]) :- !.                      % EAPI PROGRESS: A use flag name may contain '.'
eapi:jumprule(u,[C]) :- code_type(C,alnum), !.   % EAPI 2.1.4: A use flag name may contain alphanumeric chars
eapi:jumprule(s,[45]) :- !.                      % EAPI 2.1.3: A slot name may contain '-'
eapi:jumprule(s,[95]) :- !.                      % EAPI 2.1.3: A slot name may contain '_'
eapi:jumprule(s,[43]) :- !.                      % EAPI 2.1.3: A slot name may contain '+'
eapi:jumprule(s,[46]) :- !.                      % EAPI 2.1.3: A slot name may contain '.'
eapi:jumprule(s,[C]) :- code_type(C,alnum), !.   % EAPI 2.1.3: A slot name may contain alphanumeric chars
eapi:jumprule(k,[45]) :- !.                      % EAPI 2.1.6: A keyword name may contain '-'
eapi:jumprule(k,[95]) :- !.                      % EAPI 2.1.6: A keyword name may contain '_'
eapi:jumprule(k,[C]) :- code_type(C,alnum), !.   % EAPI 2.1.6: A keyword name may contain alphanumeric chars
eapi:jumprule(v,[45]) :- !.                      % EAPI 2.2: A version may contain '-'
eapi:jumprule(v,[95]) :- !.                      % EAPI 2.2: A version may contain '_'
eapi:jumprule(v,[42]) :- !.                      % EAPI 2.2: A version may contain '*'
eapi:jumprule(v,[46]) :- !.                      % EAPI 2.2: A version may contain '.'
eapi:jumprule(v,[C]) :- code_type(C,alnum), !.   % EAPI 2.2: A version may contain alphanumeric chars
eapi:jumprule(r,[45]) :- !.                      % EAPI 9.2.4: A slot restriction may contain '-'
eapi:jumprule(r,[95]) :- !.                      % EAPI 9.2.4: A slot restriction may contain '_'
eapi:jumprule(r,[46]) :- !.                      % EAPI 9.2.4: A slot restriction may contain '*'
eapi:jumprule(r,[46]) :- !.                      % EAPI 9.2.4: A slot restriction may contain '.'
eapi:jumprule(r,[C]) :- code_type(C,alnum), !.   % EAPI 9.2.4: A slot restriction may contain alphanumeric chars
eapi:jumprule(f,[45]) :- !.                      % EAPI 9.2.0: A function name may contain '-'
eapi:jumprule(f,[95]) :- !.                      % EAPI 9.2.0: A function name may contain '_'
eapi:jumprule(f,[43]) :- !.                      % EAPI 9.2.0: A function name may contain '+'
eapi:jumprule(f,[46]) :- !.                      % EAPI 9.2.0: A function name may contain '.'
eapi:jumprule(f,[C]) :- code_type(C,alnum), !.   % EAPI 9.2.0: A function name may contain alphanumeric chars
eapi:jumprule(s,[45]) :- !.                      % EAPI 2.1.4: A string name may contain '-'
eapi:jumprule(s,[95]) :- !.                      % EAPI 2.1.4: A string name may contain '_'
eapi:jumprule(s,[43]) :- !.                      % EAPI 2.1.4: A string name may contain '+'
eapi:jumprule(s,[46]) :- !.                      % EAPI 2.1.4: A string name may contain '@'
eapi:jumprule(s,[C]) :- code_type(C,alnum), !.   % EAPI 2.1.4: A string name may contain alphanumeric chars
eapi:jumprule(p,[45]) :- !.                      % EAPI 9.2.0: A uri protocol name may contain '-'
eapi:jumprule(p,[95]) :- !.                      % EAPI 9.2.0: A uri protocol name may contain '_'
eapi:jumprule(p,[43]) :- !.                      % EAPI 9.2.0: A uri protocol name may contain '+'
eapi:jumprule(p,[46]) :- !.                      % EAPI 9.2.0: A uri protocol name may contain '.'
eapi:jumprule(p,[46]) :- !.                      % EAPI 9.2.0: A uri protocol name may contain '@'
eapi:jumprule(p,[C]) :- code_type(C,alnum), !.   % EAPI 9.2.0: A uri protocol name may contain alphanumeric chars
eapi:jumprule(t,[46]) :- !.                      % A timestamp may contain a '.'
eapi:jumprule(t,[C]) :- code_type(C,digit), !.   % A timestamp may contain digit chars.

% ----------------------
% SPECIAL CHAR SEQUENCES
% ----------------------

% DCG pchar
%
% The individual characters allowed in a 'Package'

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

% EAPI 4 - 2.1.2-strict: A package name may contain '-', if the char
%                        following it is not a digit
% deprecated in EAPI 5


%eapi:pchar([45,D]) -->
%  [45,D],
%  { code_type(D,digit)  }. % digit -> fail

%eapi:pchar([45]) -->
%  [45],!.


% EAPI 4 - 2.1.2-strict: A package name may contain '-', if the char
%                        following it is an alphabetical char

%eapi:pchar([45,C]) -->
%  [45,C],
%  { code_type(C,alpha), ! }.

% EAPI 4 - 2.1.2-strict: A package name may not contain '.'

%eapi:pchar(46) -->
%  [46], { fail }.

% EAPI 4 - 2.1.2: A package name may contain '+'

eapi:pchar(43) -->
  [43],!.


% DCG pchars
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


eapi:pcharschunk2([]) -->		% a chunck ends when '-' is encountered
  [45],!.

eapi:pcharschunk2([]) --> 		% a chunck can never contain a '.'
  [46],!, { fail }.

eapi:pcharschunk2([C|R]) -->
  eapi:pchar(C),!,
  eapi:pcharschunk2(R).

eapi:pcharschunk2([]) -->
  [],!.


% DCG uchars
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


% DCG kchars
%
% A keyword consists out of multiple kchars, the first char must be
% an alphanumeric char

eapi:kchars([42]) -->
  [42],!.                                             % char: *

eapi:kchars([C|T]) -->
  eapi:char(k,C),{ code_type(C,alnum) },!,
  eapi:uchars2(T).

eapi:kchars2(C) -->
  eapi:uchars(C).

eapi:kchars2([]) -->
  [],!.


% DCG whites
%
% Whites is a sequence of zero or more white characters.

eapi:white -->
  [C],
  { code_type(C,white),! }.

eapi:whites -->
  eapi:white,!,
  eapi:whites.

eapi:whites -->
  [].


% ------------
% Generic DCGS
% ------------

% DCG chars_to_end
%
% collect all chars to end of stream

eapi:chars_to_end([C|T]) -->
  [C],!,
  eapi:chars_to_end(T).


eapi:chars_to_end([]) -->
  [],!.


% DCG chars_to_equal
%
% collect all chars to '='

eapi:chars_to_equal([]) -->
  [61],!.                                             % chars: '='

eapi:chars_to_equal([C|T]) -->
  [C],!,
  eapi:chars_to_equal(T).


% DCG chars_to_space
%
% collect all chars to ' '

eapi:chars_to_space([]) -->
  [32],!.                                             % chars: ' '

eapi:chars_to_space([C|T]) -->
  [C],!,
  eapi:chars_to_space(T).


% DCG chars_to_dash
%
% collect all chars to '-'

eapi:chars_to_dash([45]) -->
  [45],!.                                             % chars: '-'

eapi:chars_to_dash([C|R]) -->
  [C],
  eapi:chars_to_dash(R).


% DCG skip_to_end
%
% skip all chars to end of stream

eapi:skip_to_end -->
  [_],!,
  eapi:skip_to_end.

eapi:skip_to_end -->
  [],!.


% DCG file:line
%
% From a given char list, reads one line

file:line([])    --> [10],!.
file:line([C|R]) --> [C],!,file:line(R).


% DCG file:lines
%
% From a given char list, reads all lines

file:lines([L|R]) --> file:line(L),!, file:lines(R).
file:lines([])    --> [],!.


% *************************
% EAPI version declarations
% *************************

% VERSION sublist
%
% This function is used to split up a version into different subparts.
%
% Deprecated

version:sublist([], _,[],[]) :- !.
version:sublist([E|T],S,T,[]) :-
  system:member(E,S),!.
version:sublist([H|T],S,R,[H|RT]) :-
  version:sublist(T,S,R,RT).


% VERSION sublists
%
% Produces all sublists of a given list.
%
% Deprecated

version:sublists([],_,[]) :- !.

version:sublists(L,S,[E|T]) :-
  version:sublist(L,S,R,E),!,
  version:sublists(R,S,T).


% VERSION packageversion
%
% Produces version from a packagename.

packageversion(Name,Package,Version) :-
  atom_to_chars(Name,N),
  phrase(eapi:package(Package),N,V),
  phrase(eapi:version(Version),V,[]),!.

packageversion(Name,_,_) :-
  message:failure(Name).


% ***************************
% HISTORICAL - EAPI PMS cache
% ***************************

% Prior to the MD5 format where Metadata was represented as KEY=VALUE
% pairs inside a file, another format was used. This formwat was called
% the PMS format. In a pms cache file, the line number defines the key.
%
% The code is depcrecated but kept for historic reasons.


%! eapi:keys(-Keys)
%
% Predicate representing the key structure of a pms cache entry.
% In a pms cache entry, line number defined the key.

eapi:keys(['depend',
           'rdepend',
           'slot',
           'src_uri',
           'restrict',
           'homepage',
           'license',
           'description',
           'keywords',
           'inherited',
           'iuse',
           'required_use',    % EAPI 4: REQUIRED_USE
           'cdepend',         % EAPI 4: PDEPEND
           'provide',
           'eapi',
           'unused',          % EAPI 4: PROPERTIES
           'functions',       % EAPI 4: DEFINED_PHASES
           'unused',
           'unused',
           'unused',
           'unused',
           'unused']).


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


%! eapi:check_prefix_atom(+Prefix,+Atom)
%
% Predicate that checks whether an atom begins with a given Prefix

eapi:check_prefix_atom(_,Atom) :- not(atom(Atom)), !, fail.
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


%! eapi:get_use_expand(+Key,+Use,-Filtered)
%
% Retrieves use_expand meta information from the USE flags

eapi:get_use_expand(Key,Use,Filtered) :-
  include(eapi:check_prefix_atom(Key),Use,Filtered).


%! eapi:shorten_use_expand(+Key,+Long,-Short)
%
% Shortens use_expand meta information for a given prefix.

eapi:shorten_use_expand(Key,Long,Short) :-
  convlist(eapi:strip_prefix_atom(Key),Long,Short),!.


%! eapi:filter_use_defaults(+Use,-Filtered)
%
% Filterd use default information from the USE flags

eapi:filter_use_defaults(Use,Filtered) :-
  convlist(eapi:strip_use_default,Use,Filtered).


%! eapi:filter_use_expand(+Use,-Filtered)
%
% Filters use_expand meta information from the USE flags

eapi:filter_use_expand(Use,Filtered) :-
  exclude(eapi:check_use_expand_atom,Use,Filtered),!.


%! eapi:split_iuse_set(+Values,-Positive,-Negative)
%
% Splits the configuration values (USE or USE Expand flags) into a 
% positive and negative set

eapi:split_iuse_set(Iuse,PositiveUseSorted,NegativeUseSorted) :-
  preference:use(Use),
  subtract(Iuse,Use,NegativeUse),
  subtract(Iuse,NegativeUse,PositiveUse),
  sort(NegativeUse,NegativeUseSorted),
  sort(PositiveUse,PositiveUseSorted).


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

% PMS version

% eapi:elem(K,E,C) :-
%   eapi:keys(S),
%   system:nth1(N,S,K),
%   system:nth1(N,E,C).

% MD5 version

eapi:elem(K,[E|_],C) :-
  E =.. [K,C],
  !.

eapi:elem(K,[_|R],C) :-
  % not(E =.. [K,C]),
  !,
  eapi:elem(K,R,C).

% eapi:elem(_,[],[]) :-
%    !.
