/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> VDB
Tracks installed packages on the system by scanning the VDB (var/db/pkg)
directory tree. Provides predicates to synchronise the installed-package
metadata into the Prolog cache, to scaffold repository directory structures,
and to copy static graph assets.
*/

:- module(vdb, []).

% =============================================================================
%  PKG declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  VDB synchronisation
% -----------------------------------------------------------------------------

%! vdb:sync is det.
%
% Refreshes the in-memory installed-package metadata by scanning the VDB
% directory. Retracts all existing `installed` metadata for the portage
% repository and re-asserts a fact for every package found on disk.

vdb:sync :-
  retractall(cache:entry_metadata(portage,_,installed,_)),
  forall(vdb:find_installed_pkg(portage://Entry),
         (asserta(cache:entry_metadata(portage,Entry,installed,true)))).


%! vdb:find_installed_pkg(-RepoEntry) is nondet.
%
% Enumerates installed packages from the host-specific VDB directory
% (config:pkg_directory/2). On backtracking, unifies RepoEntry with
% each portage://Category/Package-Version found on disk.

vdb:find_installed_pkg(portage://Entry) :-
  config:hostname(Hostname),
  config:pkg_directory(Hostname,Directory),
  os:directory_content(Directory,Category),
  os:compose_path(Directory,Category,CategoryDir),
  os:directory_content(CategoryDir,Package),
  os:compose_path(Category,Package,Entry).


% -----------------------------------------------------------------------------
%  Repository directory scaffolding
% -----------------------------------------------------------------------------

%! vdb:create_repository_dirs(+Repository, +Directory) is det.
%
% Ensures that Directory contains a subdirectory for every category
% in Repository. Existing subdirectories are left untouched.

vdb:create_repository_dirs(Repository,Directory) :-
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     (system:exists_directory(Subdir);
      system:make_directory(Subdir)))).


%! vdb:make_repository_dirs(+Repository, +Directory) is det.
%
% Creates Directory and a subdirectory for every category in Repository.
% Unlike create_repository_dirs/2, this assumes Directory does not yet
% exist.

vdb:make_repository_dirs(Repository,Directory) :-
  system:make_directory(Directory),
  forall(Repository:category(C),
    (os:compose_path(Directory,C,Subdir),
     system:make_directory(Subdir))).


% -----------------------------------------------------------------------------
%  Graph directory helpers
% -----------------------------------------------------------------------------

%! vdb:copy_graph_assets(+Directory) is det.
%
% Copies all static assets (.index.css, .proof.css, .meslo.ttf) into
% the repository graph Directory. Sources are resolved via
% config:graph_asset_source/2.

vdb:copy_graph_assets(Directory) :-
  vdb:copy_graph_asset(index_css, '.index.css', Directory),
  vdb:copy_graph_asset(proof_css, '.proof.css', Directory),
  vdb:copy_graph_asset(meslo_ttf, '.meslo.ttf', Directory),
  !.

%! vdb:copy_graph_asset(+Key, +TargetName, +Directory) is det.
%
% Copies the asset identified by Key to Directory/TargetName,
% overwriting any existing file. Warns on missing sources or copy
% failures.

vdb:copy_graph_asset(Key, TargetName, Directory) :-
  ( current_predicate(config:graph_asset_source/2),
    config:graph_asset_source(Key, Source),
    exists_file(Source)
  ->
    atomic_list_concat([Directory,'/',TargetName], Target),
    ( exists_file(Target) -> catch(delete_file(Target), _, true) ; true ),
    catch(copy_file(Source, Target), E,
          message:warning(['Failed to copy graph asset ', Source, ' -> ', Target, ' (', E, ')']))
  ; message:warning(['Missing graph asset source for ', Key, ' (or file not found)'])
  ).


% -----------------------------------------------------------------------------
%  VDB helpers (diagnostics)
% -----------------------------------------------------------------------------

%! vdb:outdated(+Category, +Name, -Installed, -Latest) is nondet.
%
% Succeeds when the VDB (pkg) repository contains Category/Name at an
% older version than the newest acceptable candidate in the portage
% repository. Useful as a diagnostic for validating --deep behaviour.
%
% Example:
%   ?- vdb:outdated('dev-libs', openssl, Installed, Latest).
%   Installed = pkg://'dev-libs/openssl-3.5.0',
%   Latest    = portage://'dev-libs/openssl-3.5.4'.

vdb:outdated(Category, Name, pkg://InstalledEntry, portage://LatestEntry) :-
  cache:ordered_entry(pkg, InstalledEntry, Category, Name, InstalledVer),
  preference:accept_keywords(K),
  once(query:search([repository(portage),category(Category),name(Name),keywords(K),version(LatestVer)],
                    portage://LatestEntry)),
  compare(>, LatestVer, InstalledVer).