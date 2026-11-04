/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> ARGV
Command-line reading: parsing argv against interface:spec/1, parse-error
handling, unknown-flag suggestions, and environment lookups (included into the
INTERFACE module via interface.pl).
*/

% -----------------------------------------------------------------------------
%  Command line reading
% -----------------------------------------------------------------------------

%! interface:argv(-Options, -Args) is det.
%
% Parses and caches the command-line arguments. Options is a list of
% opt(Value) terms matching the spec; Args is the list of positional
% (non-option) arguments. Results are memoised in interface:argv_/2.

:- dynamic interface:argv_/2.

interface:argv(Options,Args) :-
  interface:argv_(Options,Args),!.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(
    opt_arguments(S,Options,Args0),
    E,
    interface:argv_handle_parse_error(E)
  ),
  interface:drop_end_of_options(Args0, Args),
  assertz(interface:argv_(Options,Args)).


%! interface:drop_end_of_options(+Args0, -Args) is det.
%
% Drops a leading GNU `--` end-of-options marker. tinderbox-ng (and
% other wrappers) pass `--` before atoms such as `=cat/pkg-9999`.

interface:drop_end_of_options(['--'|Rest], Rest) :- !.
interface:drop_end_of_options(Args, Args).


%! interface:argv_handle_parse_error(+Exception) is det.
%
% Handles optparse exceptions. For unknown options, prints a clear message
% and halts. Other exceptions are rethrown.

interface:argv_handle_parse_error(E) :-
  E = error(ExType, _),
  ExType = existence_error(commandline_option, Flag),
  !,
  format(user_error, 'Error: Unknown option ~w.~n', [Flag]),
  ( interface:suggest_similar_flag(Flag, Suggestion) ->
      format(user_error, 'Did you mean: ~w?~n', [Suggestion])
  ; true
  ),
  format(user_error, 'Use --help for available options.~n', []),
  halt(1).

interface:argv_handle_parse_error(E) :-
  throw(E).


% -----------------------------------------------------------------------------
%  Help text
% -----------------------------------------------------------------------------

%! interface:print_help is det.
%
% Writes a usage line and the option summary synthesised from
% interface:spec/1. The --help early-exit calls this before the
% knowledge base is loaded.

interface:print_help :-
  interface:spec(Spec),
  opt_help(Spec, Help),
  format('Usage: portage-ng [--mode MODE] [OPTIONS] [TARGETS...]~n~n~w', [Help]).



%! interface:suggest_similar_flag(+Unknown, -Suggestion) is semidet.
%
% Suggests the closest known flag to an unknown flag using prefix matching
% and edit distance heuristics.

interface:suggest_similar_flag(Unknown, Suggestion) :-
  atom_string(Unknown, UnkStr),
  interface:spec(Spec),
  findall(Score-Flag,
    ( member(OptSpec, Spec),
      memberchk(longflags(Flags), OptSpec),
      member(F, Flags),
      atom_concat('--', F, Flag),
      atom_string(Flag, FlagStr),
      interface:flag_similarity(UnkStr, FlagStr, Score),
      Score > 0.4
    ),
    Matches0),
  Matches0 \== [],
  sort(0, @>=, Matches0, [_-Suggestion|_]).


%! interface:flag_similarity(+A, +B, -Score) is det.
%
% Computes a similarity score (0.0-1.0) between two flag strings
% using longest common prefix ratio.

interface:flag_similarity(A, B, Score) :-
  string_codes(A, CA),
  string_codes(B, CB),
  interface:common_prefix_length(CA, CB, 0, PLen),
  string_length(A, LA),
  string_length(B, LB),
  MaxLen is max(LA, LB),
  ( MaxLen =:= 0 -> Score = 0.0
  ; Score is PLen / MaxLen
  ).


%! interface:common_prefix_length(+CodesA, +CodesB, +Acc, -Len) is det.
%
% Counts the length of the common prefix between two code lists.

interface:common_prefix_length([C|As], [C|Bs], Acc, Len) :-
  !,
  Acc1 is Acc + 1,
  interface:common_prefix_length(As, Bs, Acc1, Len).
interface:common_prefix_length(_, _, Len, Len).


%! interface:getenv(+Name, -Value) is semidet.
%
% Retrieves the value of the environment variable Name.
% In IPC mode, client-forwarded overrides take precedence over
% the daemon's own process environment.

interface:getenv(Name, Value) :-
  ( daemon:client_env(Name, Value) ->
    true
  ; system:getenv(Name, Value)
  ).
