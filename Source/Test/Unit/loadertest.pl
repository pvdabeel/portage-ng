/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> LOADERTEST
Unit tests for the compiled module cache (Source/loader.pl).

The cache is only sound when every file whose goal expansions are compiled
into other files is declared as a compile-time source. These tests hold the
declarations against what is actually loaded.
*/

:- module(loadertest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  LOADERTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Fixture: project files that define expansions
% -----------------------------------------------------------------------------

%! loadertest:source_root(-Root) is det.
%
% Root is the Source directory of the project, with a trailing slash.

source_root(Root) :-
  absolute_file_name(portage('Source'), Dir, [file_type(directory)]),
  atom_concat(Dir, '/', Root).


%! loadertest:expansion_file(-File) is nondet.
%
% File is a project source, outside Source/Test, with a clause for a goal
% expansion in any module or for a term expansion in user or system. A
% term expansion in another module only rewrites that module's own file.

expansion_file(File) :-
  source_root(Root),
  atom_concat(Root, 'Test/', TestRoot),
  expansion_head(Module, Head),
  \+ predicate_property(Module:Head, imported_from(_)),
  catch(clause(Module:Head, _, Ref), error(_, _), fail),
  clause_property(Ref, file(File)),
  sub_atom(File, 0, _, _, Root),
  \+ sub_atom(File, 0, _, _, TestRoot).

expansion_head(Module, Head) :-
  member(Head, [goal_expansion(_, _), goal_expansion(_, _, _, _)]),
  functor(Head, Name, Arity),
  current_predicate(Module:Name/Arity).
expansion_head(Module, Head) :-
  member(Module, [user, system]),
  member(Head, [term_expansion(_, _), term_expansion(_, _, _, _)]),
  functor(Head, Name, Arity),
  current_predicate(Module:Name/Arity).


%! loadertest:declared_file(-File) is nondet.
%
% File is a declared compile-time source.

declared_file(File) :-
  loader:compile_time_source(Spec),
  absolute_file_name(Spec, File, [file_type(prolog), access(read)]).


%! loadertest:with_cache_directory(+Directory, :Goal) is semidet.
%
% Runs Goal with Directory as the selected cache directory.

:- meta_predicate with_cache_directory(+, 0).

with_cache_directory(Directory, Goal) :-
  findall(D, loader:cache_directory(D), Saved),
  setup_call_cleanup(
      ( retractall(loader:cache_directory(_)),
        assertz(loader:cache_directory(Directory)) ),
      Goal,
      ( retractall(loader:cache_directory(_)),
        forall(member(D, Saved), assertz(loader:cache_directory(D))) )).


% -----------------------------------------------------------------------------
%  Declarations
% -----------------------------------------------------------------------------

:- begin_tests(loader).

test(compile_time_sources_exist) :-
  forall(loader:compile_time_source(Spec),
         absolute_file_name(Spec, _, [file_type(prolog), access(read)])).

test(source_only_files_exist) :-
  forall(loader:source_only(Spec),
         absolute_file_name(Spec, _, [file_type(prolog), access(read)])).

test(expansion_files_found) :-
  % Guards the scan itself: it must see the files known to define expansions.
  findall(F, expansion_file(F), Files),
  forall(member(Name, ['message.pl', 'query.pl', 'version.pl', 'prover.pl']),
         ( member(F, Files), file_base_name(F, Name) )).

test(expansion_files_are_compile_time_sources) :-
  findall(F, expansion_file(F), Files0),
  sort(Files0, Files),
  findall(F, declared_file(F), Declared),
  findall(F, ( member(F, Files), \+ memberchk(F, Declared) ), Missing),
  assertion(Missing == []).


% -----------------------------------------------------------------------------
%  Cache paths
% -----------------------------------------------------------------------------

test(cached_file_mirrors_source_path) :-
  with_cache_directory('/cache/standalone',
      loader:cached_source(portage('Source/Pipeline/prover.pl'), Source, Qlf)),
  file_base_name(Source, 'prover.pl'),
  Qlf == '/cache/standalone/Source/Pipeline/prover.qlf'.

test(spec_without_extension) :-
  with_cache_directory('/cache/standalone',
      loader:cached_source(portage('Source/Domain/Gentoo/preference'), _, Qlf)),
  Qlf == '/cache/standalone/Source/Domain/Gentoo/preference.qlf'.

test(source_only_file_is_not_cached) :-
  with_cache_directory('/cache/standalone',
      ( \+ loader:cached_source(portage('Source/config'), _, _),
        \+ loader:cached_source(portage('Source/config.pl'), _, _) )).

test(library_is_not_cached) :-
  with_cache_directory('/cache/standalone',
      \+ loader:cached_source(library(lists), _, _)).

test(no_cache_directory_no_cached_file) :-
  findall(D, loader:cache_directory(D), Saved),
  setup_call_cleanup(
      retractall(loader:cache_directory(_)),
      \+ loader:cached_source(portage('Source/Pipeline/prover.pl'), _, _),
      forall(member(D, Saved), assertz(loader:cache_directory(D)))).

:- end_tests(loader).
