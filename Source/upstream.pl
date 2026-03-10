/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> UPSTREAM
Checks upstream repositories for newer package versions via the Repology API.

Queries https://repology.org/api/v1/project/<name> for each package and
compares the "newest" version across all tracked distributions against the
version available in the local portage tree.
*/

:- module(upstream, []).

:- use_module(library(http/http_open)).
:- use_module(library(http/http_json)).

% =============================================================================
%  UPSTREAM declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Repology API interaction
% -----------------------------------------------------------------------------

%! upstream:repology_user_agent(-UA) is det.
%
% User-Agent string for Repology API requests (required by their TOS).

upstream:repology_user_agent('portage-ng/2026 (https://github.com/pvdabeel/prolog)').


%! upstream:normalize_project_name(+Name, -ProjectName) is det.
%
% Normalizes a Gentoo package name to a Repology project name by
% stripping trailing special characters like '+'.

upstream:normalize_project_name(Name, ProjectName) :-
  atom_string(Name, Str),
  string_codes(Str, Codes),
  include(upstream:is_project_char, Codes, CleanCodes),
  string_codes(CleanStr, CleanCodes),
  string_lower(CleanStr, Lower),
  atom_string(ProjectName, Lower).

upstream:is_project_char(C) :-
  ( code_type(C, alnum) -> true
  ; memberchk(C, [0'-, 0'_, 0'.])
  ).


%! upstream:repology_url(+Name, -URL) is det.
%
% Constructs the Repology API URL for a given project name.

upstream:repology_url(Name, URL) :-
  upstream:normalize_project_name(Name, ProjectName),
  format(atom(URL), 'https://repology.org/api/v1/project/~w', [ProjectName]).


%! upstream:fetch_project(+Name, -Packages) is semidet.
%
% Fetches the Repology project data for Name. Returns a list of
% package dicts on success.

upstream:fetch_project(Name, Packages) :-
  upstream:repology_url(Name, URL),
  upstream:repology_user_agent(UA),
  catch(
    setup_call_cleanup(
      http_open(URL, In, [
        request_header('User-Agent' = UA),
        request_header('Accept' = 'application/json'),
        status_code(Code)
      ]),
      ( Code == 200
      -> json_read_dict(In, Packages, [default_tag(json)])
      ;  Packages = []
      ),
      close(In)
    ),
    _Error,
    Packages = []
  ).


% -----------------------------------------------------------------------------
%  Version extraction from Repology data
% -----------------------------------------------------------------------------

%! upstream:newest_version(+Packages, -Version) is semidet.
%
% Extracts the newest version from a Repology project response.
% Looks for any package with status "newest" and returns its version.

upstream:newest_version(Packages, Version) :-
  member(Pkg, Packages),
  get_dict(status, Pkg, "newest"),
  get_dict(version, Pkg, Version),
  !.


%! upstream:gentoo_version(+Packages, -Version) is semidet.
%
% Extracts the Gentoo-specific version from a Repology project response.

upstream:gentoo_version(Packages, Version) :-
  member(Pkg, Packages),
  get_dict(repo, Pkg, "gentoo"),
  get_dict(status, Pkg, Status),
  Status \== "rolling",
  get_dict(version, Pkg, Version),
  !.


%! upstream:gentoo_status(+Packages, -Status) is semidet.
%
% Extracts the Gentoo package status from a Repology project response.

upstream:gentoo_status(Packages, Status) :-
  member(Pkg, Packages),
  get_dict(repo, Pkg, "gentoo"),
  get_dict(status, Pkg, StatusStr),
  StatusStr \== "rolling",
  atom_string(Status, StatusStr),
  !.


% -----------------------------------------------------------------------------
%  Local version lookup
% -----------------------------------------------------------------------------

%! upstream:local_version(+Category, +Name, -Version) is semidet.
%
% Finds the highest version of Category/Name in the local portage tree.

upstream:local_version(Category, Name, VersionStr) :-
  cache:ordered_entry(portage, _Entry, Category, Name, Version),
  Version = version(_, _, _, _, _, _, VersionStr),
  VersionStr \== '9999',
  \+ sub_atom(VersionStr, _, _, 0, '9999'),
  !.
upstream:local_version(Category, Name, VersionStr) :-
  cache:ordered_entry(portage, _Entry, Category, Name, Version),
  Version = version(_, _, _, _, _, _, VersionStr),
  !.


% -----------------------------------------------------------------------------
%  Check and display
% -----------------------------------------------------------------------------

%! upstream:check_package(+Category, +Name) is det.
%
% Checks a single package against the Repology API and prints the result.

upstream:check_package(Category, Name) :-
  upstream:fetch_project(Name, Packages),
  ( Packages == []
  -> message:color(darkgray),
     format('  ~w/~w', [Category, Name]),
     message:color(normal),
     format(' — not found on Repology~n', [])
  ; ( upstream:local_version(Category, Name, LocalVer)
    -> true
    ;  LocalVer = '?'
    ),
    ( upstream:newest_version(Packages, NewestVer)
    -> ( upstream:gentoo_status(Packages, GentooStatus)
       -> true
       ;  GentooStatus = unknown
       ),
       upstream:print_result(Category, Name, LocalVer, NewestVer, GentooStatus)
    ; message:color(darkgray),
      format('  ~w/~w-~w', [Category, Name, LocalVer]),
      message:color(normal),
      format(' — no upstream newest version found~n', [])
    )
  ).


%! upstream:print_result(+Cat, +Name, +Local, +Newest, +Status) is det.
%
% Prints a comparison line for a single package.

upstream:print_result(Category, Name, LocalVer, NewestVer, Status) :-
  atom_string(LocalAtom, LocalVer),
  atom_string(NewestAtom, NewestVer),
  ( LocalAtom == NewestAtom
  -> message:color(green),
     format('  ~w/~w-~w', [Category, Name, LocalVer]),
     message:color(darkgray),
     format(' — up to date~n', []),
     message:color(normal)
  ; Status == outdated
  -> message:color(yellow),
     format('  ~w/~w-~w', [Category, Name, LocalVer]),
     message:color(normal),
     format(' — upstream: ', []),
     message:color(green),
     format('~w', [NewestVer]),
     message:color(normal),
     format(' (update available)~n', [])
  ; message:color(lightgray),
    format('  ~w/~w-~w', [Category, Name, LocalVer]),
    message:color(normal),
    format(' — upstream: ~w (~w)~n', [NewestVer, Status])
  ).


%! upstream:check_packages(+Packages) is det.
%
% Checks a list of Category-Name pairs against upstream.

upstream:check_packages([]) :- !.
upstream:check_packages([Category-Name|Rest]) :-
  upstream:check_package(Category, Name),
  sleep(1),
  upstream:check_packages(Rest).


%! upstream:check(+Args) is det.
%
% Main entry point. Resolves positional arguments (including @world)
% to a list of packages and checks each against upstream.

upstream:check(Args) :-
  nl,
  message:topheader(['Upstream version check']),
  nl,
  eapi:substitute_sets(Args, Resolved),
  upstream:resolve_args(Resolved, Packages0),
  sort(Packages0, Packages),
  length(Packages, Count),
  ( Count =:= 1 -> Suffix = '' ; Suffix = 's' ),
  format('Checking ~w package~w against Repology...~n~n', [Count, Suffix]),
  upstream:check_packages(Packages),
  nl.


%! upstream:resolve_args(+Args, -Packages) is det.
%
% Resolves positional arguments to Category-Name pairs.

upstream:resolve_args([], []) :- !.
upstream:resolve_args([Arg|Rest], Packages) :-
  atom_codes(Arg, Codes),
  ( phrase(eapi:qualified_target(Q), Codes),
    once(kb:query(Q, R://E)),
    R \== pkg,
    cache:ordered_entry(R, E, C, N, _)
  -> Packages = [C-N|RestPkgs]
  ; atom_codes(Arg, Codes2),
    phrase(eapi:qualified_target(Q2), Codes2),
    once((kb:query(Q2, R2://E2), R2 \== pkg)),
    query:search([category(C2), name(N2)], R2://E2)
  -> Packages = [C2-N2|RestPkgs]
  ; message:warning(['Cannot resolve: ', Arg]),
    Packages = RestPkgs
  ),
  upstream:resolve_args(Rest, RestPkgs).