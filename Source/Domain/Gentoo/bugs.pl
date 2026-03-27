/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BUGS
Queries a Bugzilla instance for bugs matching a search term via the REST API.

Uses config:bugzilla_url/1 (default bugs.gentoo.org) and the quicksearch
parameter to find recent bugs. Displays id, status, summary, and link.
*/

:- module(bugs, []).

:- use_module(library(uri)).

% =============================================================================
%  BUGS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Bugzilla API interaction
% -----------------------------------------------------------------------------



%! bugs:search_url(+Term, -URL) is det.
%
% Constructs the Bugzilla REST API URL for a quicksearch.

bugs:search_url(Term, URL) :-
  config:bugzilla_url(Base),
  ( atom(Term) -> atom_string(Term, TermStr) ; TermStr = Term ),
  uri_encoded(query_value, TermStr, Encoded),
  format(atom(URL), '~w/rest/bug?quicksearch=~w&limit=20&include_fields=id,summary,status,resolution,component,creation_time', [Base, Encoded]).


%! bugs:fetch_bugs(+Term, -Bugs) is semidet.
%
% Fetches bugs matching Term from the Bugzilla REST API.
% Returns a list of bug dicts on success.

bugs:fetch_bugs(Term, Bugs) :-
  bugs:search_url(Term, URL),
  config:bugzilla_user_agent(UA),
  catch(
    setup_call_cleanup(
      http_open(URL, In, [
        request_header('User-Agent' = UA),
        request_header('Accept' = 'application/json'),
        status_code(Code)
      ]),
      ( Code == 200
      -> json_read_dict(In, Response, [default_tag(json)]),
         ( get_dict(bugs, Response, Bugs) -> true ; Bugs = [] )
      ;  Bugs = []
      ),
      close(In)
    ),
    _Error,
    Bugs = []
  ).


%! bugs:bug_url(+Base, +Id, -URL) is det.
%
% Constructs the URL to view a bug.

bugs:bug_url(Base, Id, URL) :-
  format(atom(URL), '~w/show_bug.cgi?id=~w', [Base, Id]).


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
  ( Res == ''
  -> StatusStr = Status
  ;  atom_string(Res, ResStr),
     format(string(StatusStr), '~w ~w', [Status, ResStr])
  ),
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
  config:bugzilla_url(Base),
  length(Bugs, Count),
  ( Count =:= 1 -> Suffix = '' ; Suffix = 's' ),
  format('  Found ~w bug~w for "~w":~n~n', [Count, Suffix, Term]),
  forall(member(Bug, Bugs), bugs:print_bug(Base, Bug)).


% -----------------------------------------------------------------------------
%  Main entry point
% -----------------------------------------------------------------------------

%! bugs:check(+Terms) is det.
%
% Searches Bugzilla for bugs matching the given terms.
% Terms are joined with spaces to form the search query.

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
  config:bugzilla_url(Config),
  nl,
  message:topheader(['Bug search']),
  nl,
  format('  Searching for "~w" on ~w...~n~n', [Term, Config]),
  bugs:fetch_bugs(Term, Bugs),
  bugs:print_bugs(Term, Bugs),
  nl.
