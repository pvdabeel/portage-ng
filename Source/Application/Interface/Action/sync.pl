/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: LIST-SETS
% -----------------------------------------------------------------------------

%! action:process_list_sets is det.
%
% Lists all available package sets (@world, @system, user-defined sets,
% and computed sets such as @installed / @security).

action:process_list_sets :-
  message:topheader(['Available package sets']),
  nl,
  message:color(green), format(' * '), message:color(normal),
  format('world~n'),
  message:color(green), format(' * '), message:color(normal),
  format('system~n'),
  forall(preference:set(Name, _),
    ( message:color(green), format(' * '), message:color(normal),
      format('~w~n', [Name])
    )),
  ( current_predicate(sets:is_computed_set/1) ->
      forall(sets:is_computed_set(Name),
        ( message:color(green), format(' * '), message:color(normal),
          format('~w~n', [Name])
        ))
  ; true
  ).


% -----------------------------------------------------------------------------
%  Action: SYNC (optional repository selection)
% -----------------------------------------------------------------------------

%! action:process_sync(+Mode, +RepoNames) is det.
%
% Dispatches --sync with optional repository name arguments:
%   --sync                       sync all registered repositories + save kb
%   --sync portage               sync only the portage repository + save kb
%   --sync portage overlay       sync portage and overlay repositories + save kb
%
% In standalone mode the knowledge base is saved to disk after syncing.

action:process_sync(Mode, []) :-
  !,
  kb:sync,
  message:header(['Syncing profile']), nl,
  catch(profile:cache_save, _, true),
  catch(glsa:cache_save, _, true),
  catch(preference:cache_invalidate, _, true),
  action:apply_package_moves,
  action:persist_sync(Mode, []).

action:process_sync(Mode, RepoNames) :-
  forall(member(Name, RepoNames),
         kb:sync(Name)),
  message:header(['Syncing profile']), nl,
  catch(profile:cache_save, _, true),
  catch(glsa:cache_save, _, true),
  catch(preference:cache_invalidate, _, true),
  action:apply_package_moves,
  action:persist_sync(Mode, RepoNames).


%! action:persist_sync(+Mode, +RepoNames) is det.
%
% In standalone mode, saves the knowledge base. RepoNames [] is a sync
% of every repository. When that save includes pkg, the incremental
% installed-package file is dropped: kb.qlf now matches the VDB walk,
% and reapplying the file would undo packages installed since the
% builds that wrote it.

action:persist_sync(Mode, RepoNames) :-
  ( Mode == standalone ->
      kb:save,
      ( ( RepoNames == [] ; memberchk(pkg, RepoNames) ),
        current_predicate(pkgdelta:clear/0)
      -> pkgdelta:clear
      ;  true
      )
  ;  true
  ).


%! action:apply_package_moves is det.
%
% Post-sync application of profiles/updates package moves to the world
% file (see pkgmoves:apply_world_moves/0). Skipped silently when the
% pkgmoves module is not loaded (client mode).

action:apply_package_moves :-
  ( current_predicate(pkgmoves:apply_world_moves/0)
  -> catch(pkgmoves:apply_world_moves, _, true)
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Action: REGEN (regenerate metadata cache, no network sync)
% -----------------------------------------------------------------------------

%! action:process_regen(+Mode, +RepoNames) is det.
%
% Regenerates the ebuild metadata cache (md5-cache on disk) without
% performing a network sync (no git pull) or reloading into the
% knowledge base. This is the equivalent of running egencache.
% The knowledge base is updated on the next --sync or restart.
%
% Registered repositories are enumerated through the public cache
% (declared(cache(repository(Name)))), not kb:repository/1. That slot is
% private and its clause body is unconditionally true; membership lives
% only in the cache asserted by register/1. A direct call throws
% permission_error unless a public method is holding the access token.

%! action:registered_repository(?Name) is nondet.
%
% Name is a repository registered with the knowledge base.

action:registered_repository(Name) :-
  kb:declared(cache(repository(Name))).

action:process_regen(_Mode, []) :-
  !,
  aggregate_all(count, action:registered_repository(_), Count),
  ( Count == 1 ->
    message:topheader(['Regenerating metadata for ',Count,' registered repository'])
  ; message:topheader(['Regenerating metadata for ',Count,' registered repositories'])
  ),
  forall(action:registered_repository(Repository),
    ( message:header(['Regenerating metadata for \"',Repository,'\"']), nl,
      ( catch(Repository:sync(metadata), _, true) -> true ; true )
    )).

action:process_regen(_Mode, RepoNames) :-
  forall(member(Name, RepoNames),
    ( action:registered_repository(Name) ->
      ( message:header(['Regenerating metadata for \"',Name,'\"']), nl,
        ( catch(Name:sync(metadata), _, true) -> true ; true )
      )
    ; message:failure(['Unknown repository: ', Name]),
      fail
    )).