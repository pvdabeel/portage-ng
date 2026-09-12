/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> BUGS
Bugzilla bug tracker knowledge store and search.

Two roles, one module (the `eapi` analogue for the `bugzilla` repository
type declared in `Source/Knowledge/repository.pl`):

  1. Repository backend. A repository instance of type `bugzilla`
     (e.g. `bugzilla` in the host config, remote `https://bugs.gentoo.org`)
     is synced through the paginated Bugzilla REST API. `sync(repository)`
     calls `bugs:sync_pages/2`, which writes raw JSON pages plus a resume
     state file under the repository location; `sync(kb)` calls
     `bugs:build_cache/3`, which folds the pending pages (newest wins)
     onto the hot store and serialises it to `Knowledge/bugs.raw` +
     `bugs.qlf` (GLSA-style, separate from `kb.qlf`). The first crawl walks
     the whole public bug space by bug-id keyset; later syncs fetch only
     bugs whose `last_change_time` moved. Network use is bounded by the
     generic per-repository daily sync cap (`config:repository_sync_limit/2`)
     enforced in `repository:sync/0`.

  2. Consumers. `--search-bugs` (`bugs:check/1`) searches the local
     store first and falls back to the live REST quicksearch (or goes
     straight to REST) per `config:bugzilla_search/1`. The `--graph` bugs
     page (`Source/Application/Output/Grapher/tracker.pl`) and the plan
     printer's domain-assumption annotation use `bugs:package_bugs/3` and
     `bugs:entry_bugs/2`, which join the `bug_atom/4` index (package atoms
     extracted from bug summaries and `cf_stabilisation_atoms`) against
     tree entries.

Hot store (module `bugsdata`, dynamic, populated from bugs.qlf):

  - `bug(Id, Product, Component, Status, Resolution, Severity, Priority,
         Assignee, Created, Changed, Keywords, Summary)`
  - `bug_atom(Id, Category, Name, Version)` — Version is a `version/7`
    term or `version_none`
*/

:- module(bugs, []).

:- use_module(library(uri)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).

% =============================================================================
%  BUGS declarations
% =============================================================================

:- dynamic bugs:loaded/0.
:- dynamic bugs:cache_file_override/1.
:- dynamic bugs:location_override/1.

:- dynamic bugsdata:bug/12.
:- dynamic bugsdata:bug_atom/4.


% -----------------------------------------------------------------------------
%  Configuration and paths
% -----------------------------------------------------------------------------

%! bugs:base_url(-Base) is det.
%
% Base URL of the Bugzilla instance (`config:bugzilla_url/1`).

bugs:base_url(Base) :-
  config:bugzilla_url(Base).


%! bugs:rest_fields(-Fields) is det.
%
% Bugzilla REST `include_fields` requested for every bug.

bugs:rest_fields([id, product, component, status, resolution, severity,
                  priority, assigned_to, creation_time, last_change_time,
                  keywords, cf_stabilisation_atoms, summary]).


%! bugs:page_size(-N) is det.
%
% Bugs per REST page (`config:bugzilla_page_size/1`, default 1000).

bugs:page_size(N) :-
  ( current_predicate(config:bugzilla_page_size/1),
    config:bugzilla_page_size(N0), integer(N0), N0 > 0
  -> N = N0
  ;  N = 1000 ).


%! bugs:request_delay(-Seconds) is det.
%
% Politeness pause between consecutive REST pages
% (`config:bugzilla_request_delay/1`, default 2).

bugs:request_delay(S) :-
  ( current_predicate(config:bugzilla_request_delay/1),
    config:bugzilla_request_delay(S0), number(S0), S0 >= 0
  -> S = S0
  ;  S = 2 ).


%! bugs:scope(-Scope) is det.
%
% Bug population kept in the store: `all` public bugs or `open` only
% (`config:bugzilla_scope/1`, default all).

bugs:scope(Scope) :-
  ( current_predicate(config:bugzilla_scope/1),
    config:bugzilla_scope(S0), memberchk(S0, [all, open])
  -> Scope = S0
  ;  Scope = all ).


%! bugs:location(-Dir) is semidet.
%
% Repository location of the registered `bugzilla` instance (raw JSON
% pages + resume state). Tests may override it.

bugs:location(Dir) :-
  bugs:location_override(Dir), !.
bugs:location(Dir) :-
  catch(bugzilla:get_location(Dir), _, fail),
  atom(Dir), Dir \== ''.


%! bugs:cache_file(-File) is det.
%
% Path of the qcompiled bug store. Prefers the `bugzilla` instance cache
% slot, else `Knowledge/bugs.qlf` under the working directory.

bugs:cache_file(File) :-
  bugs:cache_file_override(File), !.
bugs:cache_file(File) :-
  catch(bugzilla:get_cache(File0), _, fail),
  atom(File0), File0 \== '',
  !,
  File = File0.
bugs:cache_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/bugs.qlf', File).


%! bugs:raw_file(+QlfFile, -RawFile) is det.
%
% Textual source next to the qlf (`bugs.raw` for `bugs.qlf`).

bugs:raw_file(Qlf, Raw) :-
  file_name_extension(Base, _, Qlf),
  file_name_extension(Base, raw, Raw).


%! bugs:bug_url(+Id, -URL) is det.
%
% URL to view bug Id on the configured Bugzilla.

bugs:bug_url(Id, URL) :-
  bugs:base_url(Base),
  bugs:bug_url(Base, Id, URL).


%! bugs:bug_url(+Base, +Id, -URL) is det.
%
% Constructs the URL to view a bug.

bugs:bug_url(Base, Id, URL) :-
  format(atom(URL), '~w/show_bug.cgi?id=~w', [Base, Id]).


% -----------------------------------------------------------------------------
%  REST transport
% -----------------------------------------------------------------------------

%! bugs:fetch_json(+URL, -Dict) is semidet.
%
% GET URL as JSON with the configured User-Agent. Fails (after a notice)
% on network errors and on non-2xx replies, so callers can stop a crawl
% and resume on the next sync.
%
% Transport is curl piped straight into the JSON reader — the same
% choice as download.pl. SWI's own http_open/3 was observed to block
% indefinitely in the TLS handshake on one macOS host (imac-pro) while
% curl on the same host answered in under a second; curl is also what
% every other network fetch in portage-ng already relies on. http_open/3
% remains as the fallback when no curl binary is installed.

bugs:fetch_json(URL, Dict) :-
  config:bugzilla_user_agent(UA),
  catch(bugs:fetch_json_curl(URL, UA, Dict, Status), E,
        ( bugs:error_text(E, Text),
          message:warning(['Bugzilla request failed: ', Text]),
          Status = error )),
  ( Status == ok
  -> true
  ;  Status == no_curl
  -> bugs:fetch_json_http_open(URL, UA, Dict)
  ;  fail ).


%! bugs:fetch_json_curl(+URL, +UA, -Dict, -Status) is det.
%
% Status is `ok` (Dict bound), `no_curl` (binary missing) or `failed`
% (curl exit code / unparsable body, already reported).

bugs:fetch_json_curl(URL, UA, Dict, Status) :-
  format(atom(UAHeader), 'User-Agent: ~w', [UA]),
  catch(process_create(path(curl),
                       ['-s', '-f', '-L', '--proto', '=http,https',
                        '--max-time', '180',
                        '-H', UAHeader, '-H', 'Accept: application/json',
                        URL],
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
     -> Dict = Dict0, Status = ok
     ;  bugs:curl_exit_text(Code, Why),
        message:warning(['Bugzilla request failed (', Why, '): ', URL]),
        Status = failed )
  ).


%! bugs:curl_exit_text(+Code, -Text) is det.
%
% Human-readable reason for a curl exit code.

bugs:curl_exit_text(0,  'unparsable JSON') :- !.
bugs:curl_exit_text(22, 'HTTP error reply') :- !.
bugs:curl_exit_text(28, 'timeout') :- !.
bugs:curl_exit_text(6,  'could not resolve host') :- !.
bugs:curl_exit_text(7,  'connection refused') :- !.
bugs:curl_exit_text(Code, Text) :-
  format(atom(Text), 'curl exit ~w', [Code]).


%! bugs:fetch_json_http_open(+URL, +UA, -Dict) is semidet.
%
% Fallback transport through SWI-Prolog's HTTP client.

bugs:fetch_json_http_open(URL, UA, Dict) :-
  catch(
    setup_call_cleanup(
      http_open(URL, In, [
        request_header('User-Agent' = UA),
        request_header('Accept' = 'application/json'),
        status_code(Code),
        timeout(180)
      ]),
      ( Code == 200
      -> set_stream(In, encoding(utf8)),
         json_read_dict(In, Dict, [default_tag(json)])
      ;  message:warning(['Bugzilla replied HTTP ', Code, ' for ', URL]),
         fail
      ),
      close(In)
    ),
    E,
    ( bugs:error_text(E, Text),
      message:warning(['Bugzilla request failed: ', Text]), fail )
  ).


%! bugs:search_url(+Term, -URL) is det.
%
% Constructs the Bugzilla REST API URL for a quicksearch.

bugs:search_url(Term, URL) :-
  bugs:base_url(Base),
  ( atom(Term) -> atom_string(Term, TermStr) ; TermStr = Term ),
  uri_encoded(query_value, TermStr, Encoded),
  format(atom(URL), '~w/rest/bug?quicksearch=~w&limit=20&include_fields=id,summary,status,resolution,component,creation_time', [Base, Encoded]).


%! bugs:fetch_bugs(+Term, -Bugs) is det.
%
% Fetches bugs matching Term from the Bugzilla REST API (live
% quicksearch). Returns a list of bug dicts; [] on any failure.

bugs:fetch_bugs(Term, Bugs) :-
  bugs:search_url(Term, URL),
  ( bugs:fetch_json(URL, Response),
    get_dict(bugs, Response, Bugs0)
  -> Bugs = Bugs0
  ;  Bugs = [] ).


%! bugs:page_url(+Params, -URL) is det.
%
% `/rest/bug` search URL for one page. Params is a list of Key=Value
% pairs appended verbatim (values must already be URL-safe); the field
% list and page size are added here.

bugs:page_url(Params, URL) :-
  bugs:base_url(Base),
  bugs:rest_fields(Fields),
  atomic_list_concat(Fields, ',', FieldsAtom),
  bugs:page_size(Limit),
  findall(P, ( member(K=V, Params), format(atom(P), '~w=~w', [K, V]) ), Ps0),
  format(atom(F), 'include_fields=~w', [FieldsAtom]),
  format(atom(L), 'limit=~w', [Limit]),
  append(Ps0, [F, L], Ps),
  atomic_list_concat(Ps, '&', Query),
  format(atom(URL), '~w/rest/bug?~w', [Base, Query]).


%! bugs:scope_params(-Params) is det.
%
% Extra search parameters restricting the full crawl to the configured
% scope (`open` adds the three open statuses; `all` adds nothing).

bugs:scope_params(Params) :-
  bugs:scope(Scope),
  ( Scope == open
  -> Params = [status='UNCONFIRMED', status='CONFIRMED', status='IN_PROGRESS']
  ;  Params = [] ).


% -----------------------------------------------------------------------------
%  Sync state (resume file under the repository location)
% -----------------------------------------------------------------------------

%! bugs:state_file(+Location, -File) is det.
%
% `<Location>/state.pl`: Prolog terms `last_id/1`, `since/1`,
% `complete/1`, `last_sync/1`.

bugs:state_file(Location, File) :-
  os:compose_path(Location, 'state.pl', File).


%! bugs:pages_dir(+Location, -Dir) is det.
%
% `<Location>/pages`: pending JSON pages not yet folded into the store.

bugs:pages_dir(Location, Dir) :-
  os:compose_path(Location, 'pages', Dir).


%! bugs:read_state(+Location, -State) is det.
%
% State is a list of the terms in the state file ([] when absent or
% unreadable).

bugs:read_state(Location, State) :-
  bugs:state_file(Location, File),
  ( exists_file(File)
  -> catch(
       setup_call_cleanup(
         open(File, read, In, [encoding(utf8)]),
         bugs:read_terms(In, State),
         close(In)),
       _, State = [])
  ;  State = [] ).


%! bugs:read_terms(+In, -Terms) is det.
%
% All terms on stream In.

bugs:read_terms(In, Terms) :-
  read_term(In, T, []),
  ( T == end_of_file
  -> Terms = []
  ;  Terms = [T|Rest],
     bugs:read_terms(In, Rest) ).


%! bugs:write_state(+Location, +State) is det.
%
% Atomically replace the state file with the given terms.

bugs:write_state(Location, State) :-
  bugs:state_file(Location, File),
  atom_concat(File, '.tmp', Tmp),
  setup_call_cleanup(
    open(Tmp, write, Out, [encoding(utf8)]),
    forall(member(T, State), format(Out, '~q.~n', [T])),
    close(Out)),
  rename_file(Tmp, File).


%! bugs:state_get(+State, +Key, -Value, +Default) is det.
%
% Value of the unary term Key(Value) in State, or Default.

bugs:state_get(State, Key, Value, Default) :-
  Term =.. [Key, V],
  ( memberchk(Term, State) -> Value = V ; Value = Default ).


%! bugs:state_put(+State0, +Term, -State) is det.
%
% Replace the unary term with the same functor as Term.

bugs:state_put(State0, Term, State) :-
  functor(Term, F, 1),
  functor(Old, F, 1),
  exclude(=(Old), State0, State1),
  append(State1, [Term], State).


%! bugs:sync_time(-Iso) is semidet.
%
% ISO timestamp of the last completed network sync of the bug store.

bugs:sync_time(Iso) :-
  bugs:location(Location),
  bugs:read_state(Location, State),
  memberchk(last_sync(Iso), State).


%! bugs:now_iso(-Iso) is det.
%
% Current UTC time as Bugzilla-style `YYYY-MM-DDTHH:MM:SSZ`.

bugs:now_iso(Iso) :-
  get_time(Now),
  bugs:stamp_iso(Now, Iso).


%! bugs:stamp_iso(+Stamp, -Iso) is det.
%
% Format a POSIX time stamp as UTC ISO 8601 with `Z` suffix.

bugs:stamp_iso(Stamp, Iso) :-
  stamp_date_time(Stamp, DT, 'UTC'),
  format_time(atom(Iso), '%FT%TZ', DT).


% -----------------------------------------------------------------------------
%  Network sync: paginated crawl into JSON pages
% -----------------------------------------------------------------------------

%! bugs:sync_pages(+Location, +Remote) is det.
%
% Repository-level sync for a `bugzilla` repository. First run (or a
% resumed, incomplete run): keyset crawl over `bug_id` from the last id
% seen, in the configured scope. Later runs: fetch bugs whose
% `last_change_time` is at or after the previous run's start (minus a
% small overlap), again by bug-id keyset. Every page is written to
% `<Location>/pages/` and the state file advances after each page, so a
% network failure simply resumes on the next sync. Always succeeds; the
% caller decides whether the pending pages get folded (sync(kb)).

bugs:sync_pages(Location, Remote) :-
  message:scroll(['Bugzilla: syncing from ', Remote]), nl,
  bugs:pages_dir(Location, Pages),
  os:ensure_directory_path(Pages),
  bugs:read_state(Location, State0),
  bugs:state_get(State0, complete, Complete, false),
  bugs:now_iso(StartIso),
  ( Complete == true
  -> bugs:state_get(State0, since, Since, StartIso),
     message:scroll(['Bugzilla: fetching bugs changed since ', Since]), nl,
     bugs:crawl(Location, [last_change_time=Since], 0, 0, State0, State1, 0, Fetched)
  ;  bugs:state_get(State0, last_id, LastId, 0),
     bugs:scope_params(ScopeParams),
     message:scroll(['Bugzilla: looking up the highest bug id ...']),
     bugs:highest_bug_id(MaxId),
     message:scroll(['Bugzilla: full crawl from bug id ', LastId, ' to ', MaxId]), nl,
     bugs:crawl(Location, ScopeParams, LastId, MaxId, State0, State1, 0, Fetched)
  ),
  bugs:state_get(State1, complete, Complete1, false),
  ( Complete1 == true
  -> % The next incremental run picks up everything changed since this
     % run started, minus 10 minutes of overlap for clock skew and
     % in-flight edits; newest-wins folding makes the overlap harmless.
     get_time(Now), Overlap is Now - 600, bugs:stamp_iso(Overlap, SinceNext),
     bugs:state_put(State1, since(SinceNext), State2),
     bugs:state_put(State2, last_sync(StartIso), State3),
     bugs:write_state(Location, State3),
     message:scroll(['Bugzilla: fetched ', Fetched, ' bugs.']), nl
  ;  message:warning(['Bugzilla: crawl interrupted after ', Fetched,
                      ' bugs; it resumes on the next sync.'])
  ).


%! bugs:highest_bug_id(-MaxId) is det.
%
% Highest public bug id (one request); 0 when the lookup fails. Only used
% as the denominator of the full-crawl progress line.

bugs:highest_bug_id(MaxId) :-
  bugs:base_url(Base),
  format(atom(URL), '~w/rest/bug?f1=bug_id&o1=greaterthan&v1=0&order=bug_id%20DESC&limit=1&include_fields=id', [Base]),
  ( bugs:fetch_json(URL, Response),
    get_dict(bugs, Response, [Top|_]),
    get_dict(id, Top, Id), integer(Id)
  -> MaxId = Id
  ;  MaxId = 0 ).


%! bugs:progress(+Verb, +Fetched, +Id, +MaxId) is det.
%
% One scroll line: `Bugzilla: <Verb> ... <Fetched> bugs, id <Id>/<MaxId>
% (<pct>%)`; the id ratio is omitted when MaxId is unknown (0).

bugs:progress(Verb, Fetched, Id, MaxId) :-
  ( MaxId > 0
  -> Pct is min(100.0, 100 * Id / MaxId),
     format(atom(Ratio), ', id ~d/~d (~1f%)', [Id, MaxId, Pct])
  ;  Ratio = '' ),
  message:scroll(['Bugzilla: ', Verb, ' ', Fetched, ' bugs fetched', Ratio]).


%! bugs:crawl(+Location, +Params, +AfterId, +MaxId, +State0, -State, +Acc, -Fetched)
%
% Keyset pagination: each page asks for bugs with id > AfterId ordered by
% id; the page's maximum id seeds the next request. A short page ends the
% crawl and marks the state complete. `last_id` is only tracked for the
% initial full crawl (Params without last_change_time); incremental runs
% keep their own cursor in the recursion. MaxId (0 = unknown) drives the
% progress percentage.

bugs:crawl(Location, Params, AfterId, MaxId0, State0, State, Acc, Fetched) :-
  bugs:progress('requesting page,', Acc, AfterId, MaxId0),
  bugs:page_url([f1=bug_id, o1=greaterthan, v1=AfterId, order=bug_id|Params], URL),
  ( bugs:fetch_json(URL, Response),
    get_dict(bugs, Response, Page),
    is_list(Page)
  -> length(Page, N),
     Acc1 is Acc + N,
     ( N > 0
     -> bugs:write_page(Location, Page, MaxId),
        bugs:progress('page stored,', Acc1, MaxId, MaxId0)
     ;  MaxId = AfterId ),
     ( memberchk(last_change_time=_, Params)
     -> State1 = State0
     ;  bugs:state_put(State0, last_id(MaxId), State1) ),
     bugs:page_size(Limit),
     ( N < Limit
     -> bugs:state_put(State1, complete(true), State),
        bugs:write_state(Location, State),
        Fetched = Acc1
     ;  bugs:state_put(State1, complete(false), State2),
        bugs:write_state(Location, State2),
        bugs:request_delay(Delay),
        ( Delay > 0 -> sleep(Delay) ; true ),
        bugs:crawl(Location, Params, MaxId, MaxId0, State2, State, Acc1, Fetched) )
  ;  % transport failure: keep what we have, stay incomplete
     bugs:state_put(State0, complete(false), State),
     bugs:write_state(Location, State),
     Fetched = Acc
  ).


%! bugs:write_page(+Location, +Page, -MaxId) is det.
%
% Persist one REST page as `<Location>/pages/<stamp>-<maxid>.json`.
% Files sort chronologically by name, which is the fold order.

bugs:write_page(Location, Page, MaxId) :-
  bugs:pages_dir(Location, Dir),
  aggregate_all(max(Id), ( member(B, Page), get_dict(id, B, Id) ), MaxId),
  get_time(Now),
  Stamp is truncate(Now * 1000),
  format(atom(Name), '~d-~d.json', [Stamp, MaxId]),
  os:compose_path(Dir, Name, File),
  atom_concat(File, '.tmp', Tmp),
  setup_call_cleanup(
    open(Tmp, write, Out, [encoding(utf8)]),
    json_write_dict(Out, Page, [width(0)]),
    close(Out)),
  rename_file(Tmp, File).


%! bugs:pending_pages(+Location, -Files) is det.
%
% Pending page files, oldest first.

bugs:pending_pages(Location, Files) :-
  bugs:pages_dir(Location, Dir),
  ( exists_directory(Dir)
  -> directory_files(Dir, Names0),
     include([N]>>file_name_extension(_, json, N), Names0, Names1),
     msort(Names1, Names),
     findall(F, ( member(N, Names), os:compose_path(Dir, N, F) ), Files)
  ;  Files = [] ).


%! bugs:read_page(+File, -Bugs) is det.
%
% Bug dicts in one page file ([] when unreadable).

bugs:read_page(File, Bugs) :-
  catch(
    setup_call_cleanup(
      open(File, read, In, [encoding(utf8)]),
      json_read_dict(In, Bugs0, [default_tag(json)]),
      close(In)),
    _, Bugs0 = []),
  ( is_list(Bugs0) -> Bugs = Bugs0 ; Bugs = [] ).


% -----------------------------------------------------------------------------
%  Projection: JSON bug -> bug/12 + bug_atom/4
% -----------------------------------------------------------------------------

%! bugs:project_bug(+Dict, -Bug, -Atoms) is semidet.
%
% Project one REST bug dict onto the hot-store row and its package
% atoms. Fails when the dict has no integer id.

bugs:project_bug(Dict, bug(Id, Product, Component, Status, Resolution,
                           Severity, Priority, Assignee, Created, Changed,
                           Keywords, Summary),
                 Atoms) :-
  get_dict(id, Dict, Id), integer(Id),
  bugs:field(Dict, product, Product),
  bugs:field(Dict, component, Component),
  bugs:field(Dict, status, Status),
  bugs:field(Dict, resolution, Resolution),
  bugs:field(Dict, severity, Severity),
  bugs:field(Dict, priority, Priority),
  bugs:field(Dict, assigned_to, Assignee),
  bugs:field(Dict, creation_time, Created),
  bugs:field(Dict, last_change_time, Changed),
  bugs:field(Dict, summary, Summary),
  ( get_dict(keywords, Dict, Ks), is_list(Ks)
  -> maplist(bugs:to_atom, Ks, Keywords)
  ;  Keywords = [] ),
  bugs:field(Dict, cf_stabilisation_atoms, Stab),
  bugs:summary_atoms(Summary, Stab, Atoms0),
  findall(bug_atom(Id, C, N, V), member(atom(C, N, V), Atoms0), Atoms).


%! bugs:field(+Dict, +Key, -Atom) is det.
%
% String/atom/number field as an atom ('' when absent or null).

bugs:field(Dict, Key, Atom) :-
  ( get_dict(Key, Dict, V), V \== null
  -> bugs:to_atom(V, Atom)
  ;  Atom = '' ).


%! bugs:to_atom(+Value, -Atom) is det.

bugs:to_atom(V, A) :- atom(V), !, A = V.
bugs:to_atom(V, A) :- string(V), !, atom_string(A, V).
bugs:to_atom(V, A) :- number(V), !, atom_number(A, V).
bugs:to_atom(V, A) :- format(atom(A), '~w', [V]).


% -----------------------------------------------------------------------------
%  Package atom extraction
% -----------------------------------------------------------------------------

%! bugs:summary_atoms(+Summary, +StabilisationAtoms, -Atoms) is det.
%
% Package atoms named in a bug: every whitespace token of the summary and
% of `cf_stabilisation_atoms` that parses as `[op]category/name[-version]`
% (with optional `:slot`, `[use]`, `::repo` and trailing punctuation
% stripped). Atoms is a duplicate-free list of `atom(C, N, V)`; V is a
% `version/7` term or `version_none`. Categories are validated against the
% loaded tree (`cache:category/2`) when one is loaded, so prose such as
% `usr/bin` is not mistaken for a package.

bugs:summary_atoms(Summary, Stab, Atoms) :-
  bugs:tokens(Summary, T1),
  bugs:tokens(Stab, T2),
  append(T1, T2, Tokens),
  findall(atom(C, N, V),
          ( member(Tok, Tokens),
            bugs:token_atom(Tok, C, N, V) ),
          Atoms0),
  list_to_set(Atoms0, Atoms).


%! bugs:tokens(+Text, -Tokens) is det.
%
% Whitespace-separated tokens of an atom/string ('' gives []).

bugs:tokens('', []) :- !.
bugs:tokens(Text, Tokens) :-
  atom_string(Text, Str),
  split_string(Str, " \t\n\r,;()[]{}<>\"'", "", Parts0),
  exclude(==(""), Parts0, Parts),
  maplist([S, A]>>atom_string(A, S), Parts, Tokens).


%! bugs:token_atom(+Token, -C, -N, -V) is semidet.
%
% Parse one token as a package atom.

bugs:token_atom(Token, C, N, V) :-
  bugs:clean_token(Token, Clean),
  sub_atom(Clean, _, _, _, '/'),
  atom_codes(Clean, Codes),
  phrase(bugs:package_atom(C, N, V), Codes, []),
  bugs:known_category(C).


%! bugs:clean_token(+Token, -Clean) is det.
%
% Strip a leading dependency operator, anything from `:` (slot / `::repo`)
% or `[` (use deps) onward, and trailing sentence punctuation.

bugs:clean_token(Token, Clean) :-
  atom_codes(Token, Codes0),
  bugs:strip_leading(Codes0, Codes1),
  bugs:cut_at_slot(Codes1, Codes2),
  bugs:strip_trailing(Codes2, Codes3),
  atom_codes(Clean, Codes3).

bugs:strip_leading([C|T], R) :-
  memberchk(C, `=<>~!*`), !,
  bugs:strip_leading(T, R).
bugs:strip_leading(L, L).

bugs:cut_at_slot(Codes, Prefix) :-
  ( append(Prefix0, [C|_], Codes), memberchk(C, `:[`)
  -> Prefix = Prefix0
  ;  Prefix = Codes ).

bugs:strip_trailing(Codes, R) :-
  ( append(Init, [C], Codes), memberchk(C, `.,;:!?/-`)
  -> bugs:strip_trailing(Init, R)
  ;  R = Codes ).


%! DCG package_atom(-C, -N, -V)
%
% `category/name` optionally followed by `-version`.

bugs:package_atom(C, N, V) -->
  eapi:category(C), eapi:separator, eapi:package(N), eapi:version0(V).


%! bugs:known_category(+C) is semidet.
%
% Accept C when some loaded repository declares it, or when no tree is
% loaded at all (unit tests, bare hosts).

bugs:known_category(C) :-
  ( cache:category(_, _)
  -> once(cache:category(_, C))
  ;  true ).


% -----------------------------------------------------------------------------
%  Cache build: fold pending pages onto the store and serialise
% -----------------------------------------------------------------------------

%! bugs:build_cache(+Location, +Qlf, -Count) is det.
%
% kb-level sync for a `bugzilla` repository: load the existing store from
% Qlf (if any), apply every pending page in chronological order (a bug
% seen again replaces its earlier row and atoms), drop rows outside the
% configured scope, write `<Qlf-base>.raw`, qcompile it to Qlf and delete
% the consumed pages. Count is the number of bugs in the store.

bugs:build_cache(Location, Qlf, Count) :-
  with_mutex(bugs_store, bugs:build_cache_locked(Location, Qlf, Count)).

bugs:build_cache_locked(Location, Qlf, Count) :-
  bugs:load_store(Qlf),
  bugs:pending_pages(Location, Pages),
  length(Pages, NPages),
  ( NPages > 0
  -> message:scroll(['Bugzilla: folding ', NPages, ' pending pages']), nl
  ;  true ),
  forall(member(File, Pages), bugs:apply_page(File)),
  bugs:prune_scope,
  aggregate_all(count, bugsdata:bug(_,_,_,_,_,_,_,_,_,_,_,_), Count),
  ( NPages > 0 ; \+ exists_file(Qlf) ),
  !,
  bugs:write_store(Qlf),
  forall(member(File, Pages), catch(delete_file(File), _, true)),
  retractall(bugs:loaded),
  assertz(bugs:loaded).
bugs:build_cache_locked(_, _, Count) :-
  aggregate_all(count, bugsdata:bug(_,_,_,_,_,_,_,_,_,_,_,_), Count),
  retractall(bugs:loaded),
  assertz(bugs:loaded).


%! bugs:load_store(+Qlf) is det.
%
% Populate `bugsdata` from Qlf when the module is still empty.

bugs:load_store(Qlf) :-
  ( \+ bugsdata:bug(_,_,_,_,_,_,_,_,_,_,_,_),
    exists_file(Qlf)
  -> bugs:raw_file(Qlf, Raw),
     bugs:detach_store_file(Raw),
     catch(ensure_loaded(Qlf), E,
           ( bugs:error_text(E, Text),
             message:warning(['bugs: could not load ', Qlf, ': ', Text]) ))
  ;  true ).


%! bugs:apply_page(+File) is det.
%
% Fold one page: replace each bug's row and atom index entries.

bugs:apply_page(File) :-
  bugs:read_page(File, Dicts),
  forall(( member(D, Dicts), bugs:project_bug(D, Bug, Atoms) ),
         bugs:store_bug(Bug, Atoms)).


%! bugs:store_bug(+Bug, +Atoms) is det.
%
% Replace the row and atoms of one bug in the hot store.

bugs:store_bug(Bug, Atoms) :-
  arg(1, Bug, Id),
  retractall(bugsdata:bug(Id,_,_,_,_,_,_,_,_,_,_,_)),
  retractall(bugsdata:bug_atom(Id,_,_,_)),
  assertz(bugsdata:Bug),
  forall(member(A, Atoms), assertz(bugsdata:A)).


%! bugs:prune_scope is det.
%
% With `config:bugzilla_scope(open)`, incremental runs also deliver bugs
% that were closed since the last sync; drop every non-open row.

bugs:prune_scope :-
  bugs:scope(Scope),
  ( Scope == open
  -> forall(( bugsdata:bug(Id,_,_,Status,_,_,_,_,_,_,_,_),
              \+ bugs:open_status(Status) ),
            ( retractall(bugsdata:bug(Id,_,_,_,_,_,_,_,_,_,_,_)),
              retractall(bugsdata:bug_atom(Id,_,_,_)) ))
  ;  true ).


%! bugs:write_store(+Qlf) is det.
%
% Serialise `bugsdata` to the raw file and qcompile it to Qlf.

bugs:write_store(Qlf) :-
  bugs:raw_file(Qlf, Raw),
  file_directory_name(Raw, Dir),
  ( exists_directory(Dir) -> true ; make_directory_path(Dir) ),
  setup_call_cleanup(
    open(Raw, write, Out, [encoding(utf8)]),
    ( format(Out, ':- module(bugsdata, []).~n', []),
      format(Out, '% Auto-generated Bugzilla cache — do not edit.~n~n', []),
      format(Out, ':- dynamic bug/12.~n', []),
      format(Out, ':- dynamic bug_atom/4.~n~n', []),
      forall(bugsdata:bug(Id,P,Co,St,Re,Se,Pr,As,Cr,Ch,Kw,Su),
             ( write_canonical(Out, bug(Id,P,Co,St,Re,Se,Pr,As,Cr,Ch,Kw,Su)),
               format(Out, '.~n', []) )),
      forall(bugsdata:bug_atom(Id,C,N,V),
             ( write_canonical(Out, bug_atom(Id,C,N,V)),
               format(Out, '.~n', []) ))
    ),
    close(Out)),
  % qcompile/1 both compiles and (re)loads the source, so the in-memory
  % store is emptied first and repopulated from the file — otherwise every
  % row would end up twice (the asserted copy plus the loaded one).
  bugs:clear_facts,
  bugs:detach_store_file(Raw),
  catch(qcompile(Raw), E,
        ( bugs:error_text(E, Text),
          message:warning(['bugs: qcompile failed: ', Text]),
          catch(load_files(Raw, []), _, true) )).


%! bugs:detach_store_file(+Raw) is det.
%
% The `bugsdata` module may only be (re)loaded from the file it was first
% loaded from. When the store is about to be loaded from another path
% (tests, a relocated Knowledge directory), unload the old file first.

bugs:detach_store_file(Raw) :-
  ( current_module(bugsdata),
    module_property(bugsdata, file(Old)),
    Old \== Raw
  -> unload_file(Old)
  ;  true ).


%! bugs:error_text(+Error, -Text) is det.
%
% Render an exception term as a single atom for message lists.

bugs:error_text(E, Text) :-
  format(atom(Text), '~w', [E]).


% -----------------------------------------------------------------------------
%  Cache availability and lazy loading
% -----------------------------------------------------------------------------

%! bugs:cache_available is semidet.
%
% Succeeds when the qcompiled bug store exists on disk.

bugs:cache_available :-
  bugs:cache_file(File),
  exists_file(File).


%! bugs:cache_load is semidet.
%
% Load the qcompiled store into `bugsdata`. Fails when absent.

bugs:cache_load :-
  bugs:cache_file(File),
  exists_file(File),
  bugs:clear_facts,
  bugs:raw_file(File, Raw),
  bugs:detach_store_file(Raw),
  % if(true): the facts were just retracted, so an "already loaded"
  % short-cut would leave the store empty.
  load_files(File, [if(true)]),
  retractall(bugs:loaded),
  assertz(bugs:loaded).


%! bugs:ensure_loaded is det.
%
% Idempotent, thread-safe lazy load of the bug store (the grapher renders
% pages in parallel). Without a cache file the store stays empty and is
% marked loaded, so consumers degrade to "no bugs".

bugs:ensure_loaded :-
  bugs:loaded, !.
bugs:ensure_loaded :-
  with_mutex(bugs_store, bugs:ensure_loaded_locked).

bugs:ensure_loaded_locked :-
  bugs:loaded, !.
bugs:ensure_loaded_locked :-
  ( bugs:cache_load -> true
  ; retractall(bugs:loaded),
    assertz(bugs:loaded) ).


%! bugs:clear_facts is det.
%
% Empty the hot store and the loaded flag.

bugs:clear_facts :-
  retractall(bugsdata:bug(_,_,_,_,_,_,_,_,_,_,_,_)),
  retractall(bugsdata:bug_atom(_,_,_,_)),
  retractall(bugs:loaded).


% -----------------------------------------------------------------------------
%  Queries
% -----------------------------------------------------------------------------

%! bugs:open_status(+Status) is semidet.
%
% Bugzilla open statuses.

bugs:open_status('UNCONFIRMED').
bugs:open_status('CONFIRMED').
bugs:open_status('IN_PROGRESS').


%! bugs:bug(?Id, -Status, -Resolution, -Severity, -Summary) is nondet.
%
% Compact view of a stored bug.

bugs:bug(Id, Status, Resolution, Severity, Summary) :-
  bugs:ensure_loaded,
  bugsdata:bug(Id,_,_,Status,Resolution,Severity,_,_,_,_,_,Summary).


%! bugs:bug_detail(+Id, -Detail) is semidet.
%
% Detail is a list of Key(Value) terms for every stored column.

bugs:bug_detail(Id, [product(P), component(Co), status(St), resolution(Re),
                     severity(Se), priority(Pr), assignee(As), created(Cr),
                     changed(Ch), keywords(Kw), summary(Su)]) :-
  bugs:ensure_loaded,
  bugsdata:bug(Id,P,Co,St,Re,Se,Pr,As,Cr,Ch,Kw,Su).


%! bugs:is_open(+Id) is semidet.
%
% True when bug Id has an open status.

bugs:is_open(Id) :-
  bugs:ensure_loaded,
  bugsdata:bug(Id,_,_,Status,_,_,_,_,_,_,_,_),
  bugs:open_status(Status).


%! bugs:package_bugs(+C, +N, -Ids) is det.
%
% Ids of bugs whose atom index names package C/N, newest (highest id)
% first.

bugs:package_bugs(C, N, Ids) :-
  bugs:ensure_loaded,
  findall(Id, bugsdata:bug_atom(Id, C, N, _), Ids0),
  sort(0, @>, Ids0, Ids).


%! bugs:open_package_bugs(+C, +N, -Ids) is det.
%
% As package_bugs/3, restricted to open bugs.

bugs:open_package_bugs(C, N, Ids) :-
  bugs:package_bugs(C, N, All),
  include(bugs:is_open, All, Ids).


%! bugs:entry_bugs(+Repo://+Entry, -Ids) is det.
%
% Ids of bugs whose atom index names Entry's exact version, newest first.

bugs:entry_bugs(Repo://Entry, Ids) :-
  bugs:ensure_loaded,
  ( cache:ordered_entry(Repo, Entry, C, N, Ver),
    Ver \== version_none
  -> findall(Id, bugsdata:bug_atom(Id, C, N, Ver), Ids0),
     sort(0, @>, Ids0, Ids)
  ;  Ids = [] ).


%! bugs:atom_version_bugs(+C, +N, +Ver, -Ids) is det.
%
% Ids of bugs naming C/N at exactly Ver (a version/7 term).

bugs:atom_version_bugs(C, N, Ver, Ids) :-
  bugs:ensure_loaded,
  findall(Id, bugsdata:bug_atom(Id, C, N, Ver), Ids0),
  sort(0, @>, Ids0, Ids).


%! bugs:search_local(+Term, -Bugs) is det.
%
% Search the local store. A `category/name` term uses the atom index;
% anything else is a case-insensitive substring match on summaries.
% Bugs is a list of dicts (id, summary, status, resolution) compatible
% with the live REST result, newest first, at most 20.

bugs:search_local(Term, Bugs) :-
  bugs:ensure_loaded,
  ( bugs:token_atom(Term, C, N, _)
  -> bugs:package_bugs(C, N, Ids0)
  ;  atom_string(Term, S0), string_lower(S0, Needle),
     findall(Id, ( bugsdata:bug(Id,_,_,_,_,_,_,_,_,_,_,Summary),
                   atom_string(Summary, SS), string_lower(SS, Low),
                   sub_string(Low, _, _, _, Needle) ),
             Ids1),
     sort(0, @>, Ids1, Ids0)
  ),
  bugs:take(20, Ids0, Ids),
  findall(json{id:Id, summary:Su, status:St, resolution:Re},
          ( member(Id, Ids),
            bugsdata:bug(Id,_,_,St,Re,_,_,_,_,_,_,Su) ),
          Bugs).


%! bugs:take(+N, +List, -Prefix) is det.

bugs:take(N, List, Prefix) :-
  length(List, Len),
  ( Len =< N -> Prefix = List ; length(Prefix, N), append(Prefix, _, List) ).


% -----------------------------------------------------------------------------
%  Display
% -----------------------------------------------------------------------------

%! bugs:print_bug(+Base, +Bug) is det.
%
% Prints a single bug line.

bugs:print_bug(Base, Bug) :-
  get_dict(id, Bug, Id),
  get_dict(summary, Bug, Summary),
  get_dict(status, Bug, Status),
  ( get_dict(resolution, Bug, Res) -> true ; Res = '' ),
  ( Res == '' ; Res == "" ),
  !,
  bugs:print_bug_line(Base, Id, Status, Summary).
bugs:print_bug(Base, Bug) :-
  get_dict(id, Bug, Id),
  get_dict(summary, Bug, Summary),
  get_dict(status, Bug, Status),
  get_dict(resolution, Bug, Res),
  format(string(StatusStr), '~w ~w', [Status, Res]),
  bugs:print_bug_line(Base, Id, StatusStr, Summary).


%! bugs:print_bug_line(+Base, +Id, +StatusText, +Summary) is det.

bugs:print_bug_line(Base, Id, StatusStr, Summary) :-
  bugs:bug_url(Base, Id, BugURL),
  message:color(cyan),
  format('  #~w', [Id]),
  message:color(normal),
  format(' [~w] ', [StatusStr]),
  message:color(lightgray),
  format('~w~n', [Summary]),
  message:color(normal),
  message:color(darkgray),
  format('      ~w~n', [BugURL]),
  message:color(normal).


%! bugs:print_bugs(+Term, +Bugs) is det.
%
% Prints the bug list or a not-found message.

bugs:print_bugs(_Term, []) :-
  message:color(darkgray),
  format('  No bugs found.~n', []),
  message:color(normal).

bugs:print_bugs(Term, Bugs) :-
  Bugs \= [],
  bugs:base_url(Base),
  length(Bugs, Count),
  ( Count =:= 1 -> Suffix = '' ; Suffix = 's' ),
  format('  Found ~w bug~w for "~w":~n~n', [Count, Suffix, Term]),
  forall(member(Bug, Bugs), bugs:print_bug(Base, Bug)).


% -----------------------------------------------------------------------------
%  Main entry point (--search-bugs)
% -----------------------------------------------------------------------------

%! bugs:search_policy(-Policy) is det.
%
% `cache_first` (default) or `rest` (`config:bugzilla_search/1`).

bugs:search_policy(Policy) :-
  ( current_predicate(config:bugzilla_search/1),
    config:bugzilla_search(P0), memberchk(P0, [cache_first, rest])
  -> Policy = P0
  ;  Policy = cache_first ).


%! bugs:check(+Terms) is det.
%
% Searches for bugs matching the given terms (joined with spaces). With
% policy `cache_first` and a synced store, the local store answers first
% and the live REST quicksearch is only used when it finds nothing; with
% policy `rest` (or no store) the REST API is queried directly.

bugs:check([]) :-
  nl,
  message:topheader(['Bug search']),
  nl,
  message:color(darkgray),
  format('  Usage: portage-ng-dev --search-bugs <search_term>~n', []),
  format('  Example: portage-ng-dev --search-bugs mesa~n', []),
  format('  Example: portage-ng-dev --search-bugs "x11-libs/mesa compile"~n', []),
  message:color(normal),
  nl.

bugs:check(Terms) :-
  Terms \= [],
  atomic_list_concat(Terms, ' ', Term),
  bugs:base_url(Base),
  nl,
  message:topheader(['Bug search']),
  nl,
  bugs:search_policy(Policy),
  ( Policy == cache_first,
    bugs:cache_available,
    bugs:search_local(Term, Local),
    Local \== []
  -> ( bugs:sync_time(Synced) -> true ; Synced = 'unknown' ),
     format('  Searching for "~w" in the local bug store (synced ~w)...~n~n', [Term, Synced]),
     Bugs = Local
  ;  ( Policy == cache_first, bugs:cache_available
     -> format('  No local match for "~w"; querying ~w...~n~n', [Term, Base])
     ;  format('  Searching for "~w" on ~w...~n~n', [Term, Base]) ),
     bugs:fetch_bugs(Term, Bugs)
  ),
  bugs:print_bugs(Term, Bugs),
  nl,
  !.
