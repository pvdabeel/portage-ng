/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> UPSTREAM
Checks upstream repositories for newer package versions via the Repology API.

Queries <config:repology_url>/api/v1/project/<name> for each package and
compares the "newest" version across all tracked distributions against the
version available in the local portage tree. The official host remains
https://repology.org; `config:repology_address/1` can pin that host while
public DNS is on registrar hold.
*/

:- module(upstream, []).

:- use_module(library(uri)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module(library(process)).

% =============================================================================
%  UPSTREAM declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Repology API interaction
% -----------------------------------------------------------------------------

%! upstream:repology_user_agent(-UA) is det.
%
% User-Agent string for Repology API requests (required by their TOS).

upstream:repology_user_agent(UA) :-
  config:repology_user_agent(UA).


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
  config:repology_url(Base),
  upstream:normalize_project_name(Name, ProjectName),
  format(atom(URL), '~w/api/v1/project/~w', [Base, ProjectName]).


%! upstream:fetch_project(+Name, -Result) is det.
%
% Fetches the Repology project data for Name. Result is
% `packages(List)` on an HTTP 200 (List may be empty when Repology
% has no such project) or `error(Why)` on transport failure. Curl is
% the primary transport so `config:repology_address/1` can pin the
% host via `--resolve` while `repology.org` DNS is on registrar hold;
% `http_open/3` is the fallback when curl is missing (and cannot pin).

upstream:fetch_project(Name, Result) :-
  upstream:repology_url(Name, URL),
  upstream:repology_user_agent(UA),
  catch(upstream:fetch_json_curl(URL, UA, Packages, Status), E,
        ( upstream:error_text(E, Text),
          Status = error(Text) )),
  ( Status == ok
  -> Result = packages(Packages)
  ; Status == no_curl
  -> upstream:fetch_json_http_open(URL, UA, Result)
  ; Status = error(Why)
  -> Result = error(Why)
  ).


%! upstream:fetch_json_curl(+URL, +UA, -Packages, -Status) is det.
%
% Status is `ok` (Packages bound), `no_curl` (binary missing) or
% `error(Why)` (curl exit / unparsable body).

upstream:fetch_json_curl(URL, UA, Packages, Status) :-
  format(atom(UAHeader), 'User-Agent: ~w', [UA]),
  upstream:curl_resolve_opts(URL, ResolveOpts),
  append([['-s', '-f', '-L', '--proto', '=https',
           '--max-time', '60',
           '-H', UAHeader, '-H', 'Accept: application/json'],
          ResolveOpts,
          [URL]],
         Args),
  catch(process_create(path(curl),
                       Args,
                       [stdout(pipe(Out)), stderr(null), process(Pid)]),
        error(existence_error(_, _), _),
        Status = no_curl),
  ( Status == no_curl
  -> true
  ;  set_stream(Out, encoding(utf8)),
     catch(call_cleanup(json_read_dict(Out, Dict0, [default_tag(json)]), close(Out)),
           _, Dict0 = none),
     process_wait(Pid, exit(Code)),
     ( Code =:= 0, Dict0 \== none
     -> Packages = Dict0, Status = ok
     ;  upstream:curl_exit_text(Code, Why),
        Status = error(Why) )
  ).


%! upstream:curl_resolve_opts(+URL, -Opts) is det.
%
% Extra curl arguments that pin the API host when
% `config:repology_address/1` is set.

upstream:curl_resolve_opts(URL, ['--resolve', Spec]) :-
  config:repology_address(IP),
  atom(IP),
  IP \== '',
  uri_components(URL, uri_components(_, Auth, _, _, _)),
  nonvar(Auth),
  ( atomic_list_concat([Host|_], :, Auth)
  -> true
  ;  Host = Auth
  ),
  format(atom(Spec), '~w:443:~w', [Host, IP]),
  !.
upstream:curl_resolve_opts(_, []).


%! upstream:curl_exit_text(+Code, -Text) is det.
%
% Human-readable reason for a curl exit code.

upstream:curl_exit_text(0,  'unparsable JSON') :- !.
upstream:curl_exit_text(22, 'HTTP error reply') :- !.
upstream:curl_exit_text(28, 'timeout') :- !.
upstream:curl_exit_text(6,  'could not resolve host') :- !.
upstream:curl_exit_text(7,  'connection refused') :- !.
upstream:curl_exit_text(Code, Text) :-
  format(atom(Text), 'curl exit ~w', [Code]).


%! upstream:fetch_json_http_open(+URL, +UA, -Result) is det.
%
% Fallback transport through SWI-Prolog's HTTP client. Cannot honour
% `config:repology_address/1`.

upstream:fetch_json_http_open(URL, UA, Result) :-
  catch(
    setup_call_cleanup(
      http_open(URL, In, [
        request_header('User-Agent' = UA),
        request_header('Accept' = 'application/json'),
        status_code(Code),
        timeout(60)
      ]),
      ( Code == 200
      -> set_stream(In, encoding(utf8)),
         json_read_dict(In, Packages, [default_tag(json)]),
         Result = packages(Packages)
      ;  Result = packages([])
      ),
      close(In)
    ),
    E,
    ( upstream:error_text(E, Text),
      Result = error(Text) )
  ).


%! upstream:error_text(+Error, -Text) is det.
%
% Render an exception term as a single atom.

upstream:error_text(E, Text) :-
  format(atom(Text), '~w', [E]).


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
  upstream:check_package(Category, Name, _).


%! upstream:check_package(+Category, +Name, -Status) is det.
%
% Like check_package/2, but binds Status to `ok` or `unreachable`.

upstream:check_package(Category, Name, Status) :-
  upstream:fetch_project(Name, Result),
  ( Result = error(Why)
  -> message:color(darkgray),
     format('  ~w/~w', [Category, Name]),
     message:color(normal),
     format(' — Repology unreachable (~w)~n', [Why]),
     Status = unreachable
  ; Result = packages([])
  -> message:color(darkgray),
     format('  ~w/~w', [Category, Name]),
     message:color(normal),
     format(' — not found on Repology~n', []),
     Status = ok
  ; Result = packages(Packages)
  -> ( upstream:local_version(Category, Name, LocalVer)
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
     ),
     Status = ok
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
% Checks a list of Category-Name pairs against upstream. A transport
% failure aborts the rest of the list so a DNS/registrar outage is not
% reported as hundreds of "not found" lines.

upstream:check_packages([]) :- !.
upstream:check_packages([Category-Name|Rest]) :-
  upstream:check_package(Category, Name, Status),
  ( Status == unreachable
  -> message:warning(['Repology lookup aborted. Official API host is still https://repology.org; public DNS has returned 127.0.0.1 since 2026-09-13 (registrar hold). See https://github.com/repology/repology-rs/issues/560. Temporary workaround: config:repology_address/1.'])
  ;  sleep(1),
     upstream:check_packages(Rest)
  ).


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
    \+ knowledgebase:is_vdb_repository(R),
    cache:ordered_entry(R, E, C, N, _)
  -> Packages = [C-N|RestPkgs]
  ; atom_codes(Arg, Codes2),
    phrase(eapi:qualified_target(Q2), Codes2),
    once((kb:query(Q2, R2://E2), \+ knowledgebase:is_vdb_repository(R2))),
    query:search([category(C2), name(N2)], R2://E2)
  -> Packages = [C2-N2|RestPkgs]
  ; message:warning(['Cannot resolve: ', Arg]),
    Packages = RestPkgs
  ),
  upstream:resolve_args(Rest, RestPkgs).