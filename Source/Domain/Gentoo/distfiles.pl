/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DISTFILES
Manages the local distfiles directory where downloaded source tarballs are
stored. Registered as a repository instance per machine (like pkg/vdb),
providing predicates to query, verify and clean the distfiles store.
*/

:- module(distfiles, []).

% =============================================================================
%  DISTFILES declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Distfiles presence
% -----------------------------------------------------------------------------

%! distfiles:present(+Filename) is semidet.
%
% True if Filename exists in the local distfiles directory.

distfiles:present(Filename) :-
  sanitize:safe_filename(Filename),
  distfiles:get_location(Dir),
  atomic_list_concat([Dir, '/', Filename], Path),
  exists_file(Path).


%! distfiles:path(+Filename, -Path) is det.
%
% Computes the full filesystem path for a distfile in the local store.

distfiles:path(Filename, Path) :-
  ( sanitize:safe_filename(Filename) -> true
  ; throw(error(permission_error(access, distfile, Filename),
                context(distfiles:path/2, 'Invalid distfile name')))
  ),
  distfiles:get_location(Dir),
  atomic_list_concat([Dir, '/', Filename], Path).


% -----------------------------------------------------------------------------
%  Distfiles listing
% -----------------------------------------------------------------------------

%! distfiles:list(-Files) is det.
%
% Returns a sorted list of all filenames present in the distfiles directory.

distfiles:list(Files) :-
  distfiles:get_location(Dir),
  ( exists_directory(Dir)
  -> directory_files(Dir, All),
     include(distfiles:is_regular_file(Dir), All, Files0),
     sort(Files0, Files)
  ;  Files = []
  ).

%! distfiles:is_regular_file(+Dir, +Name) is semidet.
%
% Filter predicate: true if Name is a regular file (not . or ..).

distfiles:is_regular_file(Dir, Name) :-
  \+ member(Name, ['.', '..']),
  atomic_list_concat([Dir, '/', Name], Path),
  exists_file(Path).


% -----------------------------------------------------------------------------
%  Distfiles size
% -----------------------------------------------------------------------------

%! distfiles:file_size(+Filename, -Size) is semidet.
%
% Size in bytes of a distfile, if present.

distfiles:file_size(Filename, Size) :-
  distfiles:path(Filename, Path),
  exists_file(Path),
  size_file(Path, Size).


%! distfiles:total_size(-TotalBytes) is det.
%
% Total size in bytes of all files in the distfiles directory.

distfiles:total_size(TotalBytes) :-
  distfiles:list(Files),
  distfiles:get_location(Dir),
  aggregate_all(sum(S),
    ( member(F, Files),
      atomic_list_concat([Dir, '/', F], P),
      size_file(P, S)
    ),
    TotalBytes).


% -----------------------------------------------------------------------------
%  Distfiles cleanup
% -----------------------------------------------------------------------------

%! distfiles:orphans(+RepositoryAtom, -Orphans) is det.
%
% Returns a sorted list of filenames in the distfiles directory that are
% not referenced by any Manifest DIST entry in the given repository.

distfiles:orphans(RepositoryAtom, Orphans) :-
  distfiles:list(Present),
  findall(F, kb:query(manifest(all, dist, F, _), RepositoryAtom://_), Needed0),
  sort(Needed0, Needed),
  ord_subtract(Present, Needed, Orphans).


%! distfiles:clean(+RepositoryAtom) is det.
%
% Removes orphaned distfiles not referenced by any Manifest in the repository.

distfiles:clean(RepositoryAtom) :-
  distfiles:orphans(RepositoryAtom, Orphans),
  distfiles:get_location(Dir),
  forall(member(F, Orphans),
    ( atomic_list_concat([Dir, '/', F], Path),
      catch(delete_file(Path), _, true)
    )).
