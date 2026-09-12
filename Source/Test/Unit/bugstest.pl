/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> BUGSTEST
Unit tests for the Bugzilla bug store (Source/Domain/Gentoo/bugs.pl): package
atom extraction, JSON page projection, newest-wins folding into the store,
local search, and the generic per-repository daily sync cap
(Source/Knowledge/repository.pl). No network access.
*/

:- module(bugstest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).
:- use_module(library(http/json)).

% =============================================================================
%  BUGSTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Package atom extraction
% -----------------------------------------------------------------------------

:- begin_tests(bugs_atoms).

test(stablereq_summary_and_stab_atoms) :-
  bugs:summary_atoms('app-emacs/transient-0.13.7: stablereq',
                     '=app-emacs/transient-0.13.7 amd64 arm64 x86', Atoms),
  Atoms = [atom('app-emacs', transient, version(_,_,_,_,_,_,'0.13.7'))].

test(operator_usedep_and_prose_paths) :-
  bugs:summary_atoms('>=dev-libs/glib-2.80.0[introspection] fails with sys-devel/gcc-14 (usr/bin/ld error)',
                     '', Atoms),
  memberchk(atom('dev-libs', glib, version(_,_,_,_,_,_,'2.80.0')), Atoms),
  memberchk(atom('sys-devel', gcc, version(_,_,_,_,_,_,'14')), Atoms),
  \+ memberchk(atom(usr, bin, _), Atoms).

test(unversioned_atom_and_slot_cut) :-
  bugs:summary_atoms('media-libs/mesa: crash with dev-lang/rust:1.80', '', Atoms),
  memberchk(atom('media-libs', mesa, version_none), Atoms),
  memberchk(atom('dev-lang', rust, version_none), Atoms).

test(revision_is_kept) :-
  bugs:summary_atoms('www-client/firefox-128.0.1-r1 hangs', '', Atoms),
  Atoms = [atom('www-client', firefox, version(_,_,_,_,_,Rev,'128.0.1-r1'))],
  Rev == 1.

test(no_atoms_in_tracker_summary) :-
  bugs:summary_atoms('[TRACKER] portage should validate ability to install', '', []).

test(duplicates_collapse) :-
  bugs:summary_atoms('dev-lang/rust-1.97.1: stablereq', '=dev-lang/rust-1.97.1 amd64', Atoms),
  length(Atoms, 1).

test(prose_version_does_not_throw) :-
  bugs:summary_atoms('media-libs/mesa-25.2.x fails; see >=media-libs/mesa-25.3.0', '', Atoms),
  Atoms = [atom('media-libs', mesa, version(_,_,_,_,_,_,'25.3.0'))].

:- end_tests(bugs_atoms).

:- begin_tests(bugs_tracker).

test(slug_lowercases_and_collapses_punctuation) :-
  tracker:slug('Current packages', 'current-packages'),
  tracker:slug('[OLD] Core system', 'old-core-system'),
  tracker:slug('TEST-REQUEST', 'test-request'),
  tracker:slug('', other).

test(severity_order_known_first) :-
  tracker:severity_order([normal, qa, blocker, minor], [blocker, normal, minor, qa]).

test(default_hidden_resolved_and_workflow_components) :-
  tracker:default_hidden(resolved, 'current-packages'),
  tracker:default_hidden(open, stabilization),
  tracker:default_hidden(open, keywording),
  \+ tracker:default_hidden(open, 'current-packages').

:- end_tests(bugs_tracker).


% -----------------------------------------------------------------------------
%  Projection, folding, search
% -----------------------------------------------------------------------------

:- begin_tests(bugs_store).

% Fixture: a fresh location with two pending pages. The second page
% re-delivers bug 900001 as RESOLVED FIXED with a changed summary, so the
% fold must replace the earlier row and its atoms.

bugs_fixture_page1([
  json{id:900001, product:"Gentoo Linux", component:"Current packages",
       status:"CONFIRMED", resolution:"", severity:"normal", priority:"Normal",
       assigned_to:"someone", creation_time:"2026-01-01T00:00:00Z",
       last_change_time:"2026-01-02T00:00:00Z", keywords:["PATCH"],
       cf_stabilisation_atoms:"",
       summary:"dev-libs/foo-1.2.3 fails to build against dev-libs/bar"},
  json{id:900002, product:"Gentoo Linux", component:"Stabilization",
       status:"IN_PROGRESS", resolution:"", severity:"enhancement", priority:"Normal",
       assigned_to:"arch", creation_time:"2026-01-03T00:00:00Z",
       last_change_time:"2026-01-03T00:00:00Z", keywords:[],
       cf_stabilisation_atoms:"=dev-libs/foo-1.2.3 amd64",
       summary:"dev-libs/foo-1.2.3: stablereq"}
]).

bugs_fixture_page2([
  json{id:900001, product:"Gentoo Linux", component:"Current packages",
       status:"RESOLVED", resolution:"FIXED", severity:"normal", priority:"Normal",
       assigned_to:"someone", creation_time:"2026-01-01T00:00:00Z",
       last_change_time:"2026-01-05T00:00:00Z", keywords:[],
       cf_stabilisation_atoms:"",
       summary:"dev-libs/foo-1.2.4 fails to build"}
]).

bugs_store_setup :-
  tmp_file(bugstest_repo, Dir),
  make_directory_path(Dir),
  bugs:pages_dir(Dir, Pages),
  make_directory_path(Pages),
  bugs_fixture_page1(P1),
  bugs_fixture_page2(P2),
  bugs:write_page(Dir, P1, _),
  sleep(0.01),
  bugs:write_page(Dir, P2, _),
  tmp_file(bugstest_store, Base),
  atom_concat(Base, '.qlf', Qlf),
  retractall(bugs:location_override(_)),
  retractall(bugs:cache_file_override(_)),
  assertz(bugs:location_override(Dir)),
  assertz(bugs:cache_file_override(Qlf)),
  bugs:clear_facts.

bugs_store_cleanup :-
  ( retract(bugs:cache_file_override(Qlf)) ->
      bugs:raw_file(Qlf, Raw),
      forall(member(F, [Qlf, Raw]), ( exists_file(F) -> delete_file(F) ; true ))
  ; true
  ),
  ( retract(bugs:location_override(Dir)) ->
      catch(delete_directory_and_contents(Dir), _, true)
  ; true
  ),
  bugs:clear_facts.

test(project_bug_row_and_atoms) :-
  bugs_fixture_page1([D|_]),
  bugs:project_bug(D, Bug, Atoms),
  Bug = bug(900001, 'Gentoo Linux', 'Current packages', 'CONFIRMED', '',
            normal, 'Normal', someone, '2026-01-01T00:00:00Z',
            '2026-01-02T00:00:00Z', ['PATCH'], _),
  memberchk(bug_atom(900001, 'dev-libs', foo, version(_,_,_,_,_,_,'1.2.3')), Atoms),
  memberchk(bug_atom(900001, 'dev-libs', bar, version_none), Atoms).

test(fold_newest_wins_and_consumes_pages,
     [setup(bugs_store_setup), cleanup(bugs_store_cleanup)]) :-
  bugs:location(Dir),
  bugs:cache_file(Qlf),
  bugs:build_cache(Dir, Qlf, Count),
  Count == 2,
  exists_file(Qlf),
  bugs:pending_pages(Dir, []),
  % bug 900001 was replaced by the second page
  bugs:bug(900001, 'RESOLVED', 'FIXED', _, Summary),
  sub_atom(Summary, 0, _, _, 'dev-libs/foo-1.2.4'),
  \+ bugsdata:bug_atom(900001, 'dev-libs', bar, _),
  bugsdata:bug_atom(900001, 'dev-libs', foo, version(_,_,_,_,_,_,'1.2.4')),
  % package view: both bugs, newest first; only 900002 still open
  bugs:package_bugs('dev-libs', foo, [900002, 900001]),
  bugs:open_package_bugs('dev-libs', foo, [900002]),
  bugs:atom_version_bugs('dev-libs', foo, version([1,2,3],'',4,0,[],0,'1.2.3'), [900002]),
  % rebuilding with no pending pages keeps the store as is
  bugs:build_cache(Dir, Qlf, Count2),
  Count2 == 2.

test(search_local_atom_and_substring,
     [setup(bugs_store_setup), cleanup(bugs_store_cleanup)]) :-
  bugs:location(Dir),
  bugs:cache_file(Qlf),
  bugs:build_cache(Dir, Qlf, _),
  bugs:search_local('dev-libs/foo', ByAtom),
  maplist([B, Id]>>get_dict(id, B, Id), ByAtom, [900002, 900001]),
  bugs:search_local('STABLEREQ', BySubstring),
  BySubstring = [B2],
  get_dict(id, B2, 900002),
  get_dict(status, B2, 'IN_PROGRESS'),
  bugs:search_local('no such thing', []).

test(state_roundtrip, [setup(bugs_store_setup), cleanup(bugs_store_cleanup)]) :-
  bugs:location(Dir),
  bugs:read_state(Dir, []),
  bugs:write_state(Dir, [last_id(42), complete(false)]),
  bugs:read_state(Dir, S1),
  bugs:state_get(S1, last_id, 42, 0),
  bugs:state_put(S1, complete(true), S2),
  memberchk(complete(true), S2),
  \+ memberchk(complete(false), S2),
  bugs:state_get(S2, since, Since, none),
  Since == none.

:- end_tests(bugs_store).


% -----------------------------------------------------------------------------
%  Per-repository daily sync cap
% -----------------------------------------------------------------------------

:- begin_tests(bugs_sync_cap).

cap_repo(bugstest_capped_repo).

cap_setup :-
  cap_repo(R),
  retractall(config:repository_sync_limit(R, _)),
  assertz(config:repository_sync_limit(R, 2)),
  repository:sync_stamp_file(R, File),
  ( exists_file(File) -> delete_file(File) ; true ).

cap_cleanup :-
  cap_repo(R),
  retractall(config:repository_sync_limit(R, _)),
  repository:sync_stamp_file(R, File),
  ( exists_file(File) -> delete_file(File) ; true ).

test(uncapped_repository_is_always_allowed) :-
  repository:network_sync_allowed(bugstest_uncapped_repo),
  repository:record_network_sync(bugstest_uncapped_repo),
  repository:sync_stamp_file(bugstest_uncapped_repo, File),
  \+ exists_file(File).

test(cap_counts_recent_syncs_only, [setup(cap_setup), cleanup(cap_cleanup)]) :-
  cap_repo(R),
  repository:network_sync_allowed(R),
  repository:record_network_sync(R),
  repository:network_sync_allowed(R),
  repository:record_network_sync(R),
  \+ repository:network_sync_allowed(R),
  % a stamp older than 24h does not count
  repository:sync_stamp_file(R, File),
  get_time(Now),
  Old is Now - 90000,
  setup_call_cleanup(
    open(File, write, Out),
    ( format(Out, '~q.~n', [Old]), format(Out, '~q.~n', [Now]) ),
    close(Out)),
  repository:network_sync_allowed(R),
  repository:recent_sync_stamps(R, Stamps),
  length(Stamps, 1).

:- end_tests(bugs_sync_cap).
