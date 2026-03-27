% -----------------------------------------------------------------------------
%  Action: LIST-SETS
% -----------------------------------------------------------------------------

%! action:process_list_sets is det.
%
% Lists all available package sets (@world, @system, user-defined sets).

process_list_sets :-
  message:topheader(['Available package sets']),
  nl,
  message:color(green), format(' * '), message:color(normal),
  format('world~n'),
  message:color(green), format(' * '), message:color(normal),
  format('system~n'),
  forall(preference:set(Name, _),
    ( message:color(green), format(' * '), message:color(normal),
      format('~w~n', [Name])
    )).


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

process_sync(Mode, []) :-
  !,
  kb:sync,
  message:header(['Syncing profile']), nl,
  catch(profile:cache_save, _, true),
  ( Mode == standalone -> kb:save ; true ).

process_sync(Mode, RepoNames) :-
  forall(member(Name, RepoNames),
         kb:sync(Name)),
  message:header(['Syncing profile']), nl,
  catch(profile:cache_save, _, true),
  ( Mode == standalone -> kb:save ; true ).


% -----------------------------------------------------------------------------
%  Action: REGEN (regenerate metadata cache, no network sync)
% -----------------------------------------------------------------------------

%! action:process_regen(+Mode, +RepoNames) is det.
%
% Regenerates the ebuild metadata cache (md5-cache on disk) without
% performing a network sync (no git pull) or reloading into the
% knowledge base. This is the equivalent of running egencache.
% The knowledge base is updated on the next --sync or restart.

process_regen(_Mode, []) :-
  !,
  aggregate_all(count, kb:repository(_), Count),
  ( Count == 1 ->
    message:topheader(['Regenerating metadata for ',Count,' registered repository'])
  ; message:topheader(['Regenerating metadata for ',Count,' registered repositories'])
  ),
  forall(kb:repository(Repository),
    ( message:header(['Regenerating metadata for \"',Repository,'\"']), nl,
      ( catch(Repository:sync(metadata), _, true) -> true ; true )
    )).

process_regen(_Mode, RepoNames) :-
  forall(member(Name, RepoNames),
    ( kb:repository(Name) ->
      ( message:header(['Regenerating metadata for \"',Name,'\"']), nl,
        ( catch(Name:sync(metadata), _, true) -> true ; true )
      )
    ; message:failure(['Unknown repository: ', Name]),
      fail
    )).