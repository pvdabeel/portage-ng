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
%
% A command line that cannot be parsed ends the program with an
% explanation; see interface:argv_handle_parse_error/1.

:- dynamic interface:argv_/2.

interface:argv(Options,Args) :-
  interface:argv_(Options,Args),!.

interface:argv(Options,Args) :-
  current_prolog_flag(argv, RawArgs),
  catch(
    interface:load_argv(RawArgs),
    E,
    interface:argv_handle_parse_error(E)
  ),
  interface:argv_(Options,Args),
  !.


%! interface:load_argv(+RawArgs) is det.
%
% Parses the command-line words RawArgs and stores the result as the
% command line that interface:argv/2 answers with, replacing what was
% stored before. Throws the errors of interface:parse_argv/3 and stores
% nothing in that case. The daemon calls this once per request with the
% words its client sent.

interface:load_argv(RawArgs) :-
  interface:parse_argv(RawArgs, Options, Args0),
  interface:drop_end_of_options(Args0, Args),
  retractall(interface:argv_(_,_)),
  assertz(interface:argv_(Options,Args)).


%! interface:parse_argv(+RawArgs, -Options, -PosArgs) is det.
%
% Parses the list of command-line words RawArgs against interface:spec/1.
% Options holds one opt(Value) term for every option in the spec: first
% the options that were not given, with their default value and in spec
% order, then the options that were given, in the order of the command
% line. An option given more than once keeps its last value. PosArgs
% holds the remaining words in their original order.
%
% The accepted forms are `--flag value`, `--flag=value`, `-f value` and
% `-fvalue`. A boolean option needs no value: `--flag` means true and
% `--no-flag` means false, and a following word `true` or `false` is
% taken as its value. A lone `-` or `--` is a positional word. Any other
% word that starts with a dash and is not an option of the spec is an
% error, as is a missing value or a value of the wrong type. Errors are
% thrown; interface:argv_error_text/3 describes them.
%
% This parser replaces library(optparse), which checked the whole spec
% again on every call. In a daemon that is once per request, and it took
% about 40 ms for a spec of this size. The differences in behaviour are
% few. `-1` is now read as the short form of --oneshot (optparse took it
% for a negative number and left it among the positional words), a whole
% number is accepted where a float is expected (`--load-average 2`), a
% short option written with two dashes (`--p`) is no longer accepted,
% and an option that needs a value but is the last word is an error
% instead of silently getting an empty value.

interface:parse_argv(RawArgs, Options, PosArgs) :-
  interface:ensure_opt_index,
  interface:scan_argv(RawArgs, Overrides0, PosArgs),
  interface:dedup_keeplast(Overrides0, Overrides),
  interface:opt_defaults_(Defaults),
  interface:merge_defaults(Defaults, Overrides, Options).


%! interface:ensure_opt_index is det.
%
% Builds the lookup tables of the parser from interface:spec/1 the first
% time it is called, and does nothing after that. opt_flag_/3 maps each
% flag as it is written on the command line (`-j`, `--jobs`) to the name
% and type of its option, opt_neg_flag_/2 maps the `--no-` form of each
% boolean option to its name, and opt_defaults_/1 holds the default value
% of every option in spec order. The spec is static, so the tables are
% never rebuilt.

:- dynamic interface:opt_index_ready_/0.
:- dynamic interface:opt_flag_/3.
:- dynamic interface:opt_neg_flag_/2.
:- dynamic interface:opt_defaults_/1.

interface:ensure_opt_index :-
  interface:opt_index_ready_,
  !.
interface:ensure_opt_index :-
  interface:spec(Spec),
  interface:register_spec_entries(Spec, Defaults),
  assertz(interface:opt_defaults_(Defaults)),
  assertz(interface:opt_index_ready_).


%! interface:register_spec_entries(+Spec, -Defaults) is det.
%
% Stores the flags of every spec entry in the lookup tables and collects
% the Name-Default pair of each entry in Defaults.

interface:register_spec_entries([], []).
interface:register_spec_entries([Entry|Rest], [Id-Def|More]) :-
  memberchk(opt(Id), Entry),
  ( memberchk(type(Type), Entry) -> true ; Type = term ),
  ( memberchk(default(Def), Entry) -> true ; Def = '_' ),
  ( memberchk(shortflags(Shorts), Entry) -> true ; Shorts = [] ),
  ( memberchk(longflags(Longs), Entry) -> true ; Longs = [] ),
  forall(member(S, Shorts),
         ( atom_concat('-', S, SF),
           assertz(interface:opt_flag_(SF, Id, Type)) )),
  forall(member(L, Longs),
         ( atom_concat('--', L, LF),
           assertz(interface:opt_flag_(LF, Id, Type)),
           ( Type == boolean
           -> atom_concat('--no-', L, NF),
              assertz(interface:opt_neg_flag_(NF, Id))
           ;  true
           ) )),
  interface:register_spec_entries(Rest, More).


%! interface:scan_argv(+Words, -Overrides, -PosArgs) is det.
%
% Walks the command-line words from left to right. Overrides receives a
% Name-Value pair for every option met, PosArgs every other word. The
% clauses try, in this order: a `--no-` flag, a flag that is a word of
% its own, `--flag=value`, a short flag with its value attached, an
% unknown word that starts with a dash, and finally a positional word.

interface:scan_argv([], [], []) :- !.
interface:scan_argv([Tok|Rest], [Id-false|More], Pos) :-
  interface:opt_neg_flag_(Tok, Id),
  !,
  interface:scan_argv(Rest, More, Pos).
interface:scan_argv([Tok|Rest], [Id-Val|More], Pos) :-
  interface:opt_flag_(Tok, Id, Type),
  !,
  interface:consume_flag_value(Type, Tok, Rest, Val, Rest1),
  interface:scan_argv(Rest1, More, Pos).
interface:scan_argv([Tok|Rest], [Id-Val|More], Pos) :-
  sub_atom(Tok, 0, 2, _, '--'),
  sub_atom(Tok, EqPos, 1, _, '='),
  EqPos > 2,
  !,
  sub_atom(Tok, 0, EqPos, _, FlagAtom),
  AfterEq is EqPos + 1,
  sub_atom(Tok, AfterEq, _, 0, ValAtom),
  ( interface:opt_flag_(FlagAtom, Id, Type)
  -> interface:parse_opt_value(Type, FlagAtom, ValAtom, Val),
     interface:scan_argv(Rest, More, Pos)
  ;  throw(error(existence_error(commandline_option, FlagAtom), _))
  ).
interface:scan_argv([Tok|Rest], [Id-Val|More], Pos) :-
  sub_atom(Tok, 0, 1, _, '-'),
  \+ sub_atom(Tok, 0, 2, _, '--'),
  atom_length(Tok, Len),
  Len > 2,
  sub_atom(Tok, 0, 2, _, ShortFlag),
  interface:opt_flag_(ShortFlag, Id, Type),
  !,
  sub_atom(Tok, 2, _, 0, ValAtom),
  ( sub_atom(ValAtom, 0, 1, _, '=')
  -> throw(error(syntax_error(commandline_option_value),
                 commandline_option(Tok)))
  ;  interface:parse_opt_value(Type, ShortFlag, ValAtom, Val),
     interface:scan_argv(Rest, More, Pos)
  ).
interface:scan_argv([Tok|_], _, _) :-
  Tok \== '-',
  Tok \== '--',
  sub_atom(Tok, 0, 1, _, '-'),
  !,
  throw(error(existence_error(commandline_option, Tok), _)).
interface:scan_argv([Tok|Rest], Overrides, [Tok|Pos]) :-
  interface:scan_argv(Rest, Overrides, Pos).


%! interface:consume_flag_value(+Type, +Flag, +Rest, -Val, -RestOut) is det.
%
% Gives the value of a flag that was a word of its own. Rest holds the
% words after the flag and RestOut the words left once the value is
% taken. A boolean flag takes the next word only when that word is
% `true` or `false`; otherwise it is true and takes nothing. A flag of
% any other type takes the next word and it is an error if there is none.

interface:consume_flag_value(boolean, _Flag, [Next|Rest], Bool, Rest) :-
  ( Next == true -> Bool = true ; Next == false -> Bool = false ),
  !.
interface:consume_flag_value(boolean, _Flag, Rest, true, Rest) :- !.
interface:consume_flag_value(Type, Flag, [ValAtom|Rest], Val, Rest) :-
  !,
  interface:parse_opt_value(Type, Flag, ValAtom, Val).
interface:consume_flag_value(_Type, Flag, [], _, _) :-
  throw(error(existence_error(commandline_option_value, Flag),
              commandline_option(Flag))).


%! interface:parse_opt_value(+Type, +Flag, +Atom, -Val) is det.
%
% Converts the word Atom into a value of the Type that Flag expects. A
% whole number is accepted for a float. A word that does not fit throws
% a type error that names the flag.

interface:parse_opt_value(atom, _Flag, Atom, Atom) :- !.
interface:parse_opt_value(boolean, _Flag, Atom, Atom) :-
  ( Atom == true ; Atom == false ),
  !.
interface:parse_opt_value(integer, _Flag, Atom, Val) :-
  catch(atom_number(Atom, Val), _, fail),
  integer(Val),
  !.
interface:parse_opt_value(float, _Flag, Atom, Val) :-
  catch(atom_number(Atom, N), _, fail),
  number(N),
  !,
  Val is float(N).
interface:parse_opt_value(Type, Flag, Atom, _) :-
  throw(error(type_error(Type, Atom), commandline_option(Flag))).


%! interface:dedup_keeplast(+Pairs, -Unique) is det.
%
% Drops every Name-Value pair for which a later pair with the same name
% exists, so an option given more than once keeps its last value.

interface:dedup_keeplast([], []).
interface:dedup_keeplast([Id-Val|Rest], Result) :-
  ( memberchk(Id-_, Rest)
  -> interface:dedup_keeplast(Rest, Result)
  ;  Result = [Id-Val|More],
     interface:dedup_keeplast(Rest, More)
  ).


%! interface:merge_defaults(+Defaults, +Overrides, -Options) is det.
%
% Builds the final option list: the default of every option that was not
% given, followed by the options that were given.

interface:merge_defaults([], Overrides, Options) :-
  interface:pairs_to_opts(Overrides, Options).
interface:merge_defaults([Id-Def|Rest], Overrides, Options) :-
  ( memberchk(Id-_, Overrides)
  -> interface:merge_defaults(Rest, Overrides, Options)
  ;  Opt =.. [Id, Def],
     Options = [Opt|More],
     interface:merge_defaults(Rest, Overrides, More)
  ).


%! interface:pairs_to_opts(+Pairs, -Options) is det.
%
% Turns each Name-Value pair into the term Name(Value).

interface:pairs_to_opts([], []).
interface:pairs_to_opts([Id-Val|Rest], [Opt|More]) :-
  Opt =.. [Id, Val],
  interface:pairs_to_opts(Rest, More).


%! interface:drop_end_of_options(+Args0, -Args) is det.
%
% Drops a leading GNU `--` end-of-options marker. tinderbox-ng (and
% other wrappers) pass `--` before atoms such as `=cat/pkg-9999`.

interface:drop_end_of_options(['--'|Rest], Rest) :- !.
interface:drop_end_of_options(Args, Args).


%! interface:argv_handle_parse_error(+Exception) is det.
%
% Called when the command line of this process cannot be parsed. Explains
% the mistake on standard error and halts with the status given by
% interface:argv_error_text/3. Any other exception is passed on
% unchanged.
%
% The daemon does not come here for the command line of a request. A
% halt would stop the daemon itself, because SWI-Prolog does not let a
% halt be cancelled by catching it. The daemon calls interface:load_argv/1
% and writes the same explanation and status to its client instead; see
% daemon:handle_error/3.

interface:argv_handle_parse_error(E) :-
  interface:argv_error_text(E, Status, Lines),
  !,
  forall(member(Line, Lines),
         format(user_error, '~w~n', [Line])),
  halt(Status).

interface:argv_handle_parse_error(E) :-
  throw(E).


%! interface:argv_error_text(+Exception, -Status, -Lines) is semidet.
%
% True when Exception is one of the errors interface:parse_argv/3 throws.
% Lines is the explanation for the user and Status the exit status that
% goes with it: 1 for an option that does not exist, 2 for a value that
% is missing or of the wrong type. These are the statuses the program
% returned for the same mistakes when it still used library(optparse).

interface:argv_error_text(error(existence_error(commandline_option, Flag), _),
                          1, Lines) :-
  !,
  format(atom(Line), 'Error: Unknown option ~w.', [Flag]),
  ( interface:suggest_similar_flag(Flag, Suggestion)
  -> format(atom(Hint), 'Did you mean: ~w?', [Suggestion]),
     Lines = [Line, Hint, 'Use --help for available options.']
  ;  Lines = [Line, 'Use --help for available options.']
  ).
interface:argv_error_text(error(existence_error(commandline_option_value, Flag), _),
                          2, [Line, 'Use --help for available options.']) :-
  !,
  format(atom(Line), 'Error: Option ~w needs a value.', [Flag]).
interface:argv_error_text(error(type_error(Type, Value), commandline_option(Flag)),
                          2, [Line, 'Use --help for available options.']) :-
  !,
  interface:opt_type_text(Type, Expected),
  format(atom(Line), 'Error: Option ~w expects ~w, got \'~w\'.',
         [Flag, Expected, Value]).
interface:argv_error_text(error(syntax_error(commandline_option_value),
                                commandline_option(Word)),
                          2, [Line, 'Write the value of a short option without \'=\', as in -j4 or -j 4.']) :-
  format(atom(Line), 'Error: Cannot read option ~w.', [Word]).


%! interface:opt_type_text(+Type, -Text) is det.
%
% Describes an option type in words for an error message.

interface:opt_type_text(integer, 'a whole number') :- !.
interface:opt_type_text(float,   'a number') :- !.
interface:opt_type_text(boolean, 'true or false') :- !.
interface:opt_type_text(Type,    Type).


% -----------------------------------------------------------------------------
%  Help text
% -----------------------------------------------------------------------------

%! interface:print_help is det.
%
% Writes a usage line and one aligned row per flag in interface:spec/1.
% The description column is fixed. A flag longer than that column puts
% its text on the following lines, so a missing short flag cannot pull
% the rest of the row left. The --help early-exit calls this before the
% knowledge base is loaded.

interface:print_help :-
  interface:spec(Spec),
  format('Usage: portage-ng [--mode MODE] [OPTIONS] [TARGETS...]~n~n', []),
  interface:help_rows(Spec, Rows),
  interface:help_flag_width(Rows, Width),
  interface:help_text_width(Width, TextWidth),
  forall(member(row(Flag, Lines), Rows),
         interface:print_help_row(Width, TextWidth, Flag, Lines)).



%! interface:help_rows(+Spec, -Rows) is det.
%
% One row(Flag, Lines) per option that has a short or long flag.
% Lines is either plain(Text) or block(Lines) for a preformatted list.

interface:help_rows(Spec, Rows) :-
  findall(row(Flag, Lines),
          ( member(Opt, Spec),
            interface:help_flag(Opt, Flag),
            interface:help_lines(Opt, Lines)
          ),
          Rows).



%! interface:help_flag(+Opt, -Flag) is semidet.
%
% Flag text such as `-h, --help` or `--jobs ARG`. Non-booleans take ARG
% so the row shows that a value is required.

interface:help_flag(Opt, Flag) :-
  ( memberchk(shortflags(Shorts), Opt) -> true ; Shorts = [] ),
  ( memberchk(longflags(Longs), Opt) -> true ; Longs = [] ),
  findall(S, ( member(C, Shorts), atom_concat('-', C, S) ), ShortAtoms),
  findall(L, ( member(N, Longs), atom_concat('--', N, L) ), LongAtoms),
  append(ShortAtoms, LongAtoms, Atoms),
  Atoms \== [],
  atomic_list_concat(Atoms, ', ', Joined),
  ( memberchk(type(boolean), Opt)
  -> Flag = Joined
  ;  atom_concat(Joined, ' ARG', Flag)
  ).



%! interface:help_lines(+Opt, -Lines) is det.
%
% plain(Text) for a single help atom. block(Lines) for a list, with the
% shared leading indent removed so the authored columns stay aligned.

interface:help_lines(Opt, Lines) :-
  ( memberchk(help(Help), Opt) -> true ; Help = '' ),
  ( is_list(Help)
  -> maplist(interface:help_strip, Help, Block),
     Lines = block(Block)
  ;  Lines = plain(Help)
  ).



%! interface:help_strip(+Line0, -Line) is det.
%
% Drop leading spaces from a preformatted help line.

interface:help_strip(Line0, Line) :-
  atom_codes(Line0, Codes0),
  interface:skip_spaces(Codes0, Codes),
  atom_codes(Line, Codes).



%! interface:skip_spaces(+Codes0, -Codes) is det.
%
% Codes is Codes0 without a leading run of spaces.

interface:skip_spaces([32|Rest], Codes) :-
  !,
  interface:skip_spaces(Rest, Codes).
interface:skip_spaces(Codes, Codes).



%! interface:help_flag_width(+Rows, -Width) is det.
%
% Width of the flag column. Flags longer than 32 characters do not
% stretch the column; their description goes on the next line.

interface:help_flag_width(Rows, Width) :-
  findall(N,
          ( member(row(Flag, _), Rows),
            atom_length(Flag, N),
            N =< 32
          ),
          Ns),
  max_list([12|Ns], Width).



%! interface:help_text_width(+FlagWidth, -TextWidth) is det.
%
% Characters available for wrapped help text after the flag column.

interface:help_text_width(FlagWidth, TextWidth) :-
  console:printing_tty_size(_, Cols),
  Room is Cols - (FlagWidth + 4),
  ( Room >= 24
  -> TextWidth = Room
  ;  TextWidth = 56
  ).



%! interface:print_help_row(+Width, +TextWidth, +Flag, +Lines) is det.
%
% Print one option. The description starts at column Width+4.

interface:print_help_row(Width, TextWidth, Flag, Lines) :-
  interface:help_body(Lines, TextWidth, Body),
  atom_length(Flag, FL),
  ( FL =< Width, Body = [First|Rest]
  -> Pad is Width - FL,
     format('  ~w', [Flag]),
     forall(between(1, Pad, _), put_char(' ')),
     format('  ~w~n', [First]),
     interface:print_help_cont(Width, Rest)
  ;  format('  ~w~n', [Flag]),
     interface:print_help_cont(Width, Body)
  ).



%! interface:print_help_cont(+Width, +Lines) is det.
%
% Print Lines at the description column.

interface:print_help_cont(Width, Lines) :-
  Indent is Width + 4,
  forall(member(Line, Lines),
         format('~*|~w~n', [Indent, Line])).



%! interface:help_body(+Lines, +TextWidth, -Body) is det.
%
% Body lines to print. A preformatted block is kept intact. A plain
% sentence is wrapped to TextWidth.

interface:help_body(block(Lines), _, Lines) :- !.
interface:help_body(plain(Text), TextWidth, Body) :-
  interface:wrap_line(Text, TextWidth, Body).



%! interface:wrap_line(+Text, +Width, -Lines) is det.
%
% Break Text into lines of at most Width characters, splitting on spaces.

interface:wrap_line(Text, Width, [Text]) :-
  atom_length(Text, N),
  N =< Width,
  !.
interface:wrap_line(Text, Width, Lines) :-
  atomic_list_concat(Words, ' ', Text),
  interface:wrap_words(Words, Width, [], Lines).



%! interface:wrap_words(+Words, +Width, +Acc, -Lines) is det.
%
% Greedy word wrap. Acc is the current line in reverse.

interface:wrap_words([], _, [], []) :- !.
interface:wrap_words([], _, Acc, [Line]) :-
  !,
  reverse(Acc, Words),
  atomic_list_concat(Words, ' ', Line).
interface:wrap_words([Word|Words], Width, [], Lines) :-
  !,
  atom_length(Word, WL),
  ( WL > Width
  -> Lines = [Word|Rest],
     interface:wrap_words(Words, Width, [], Rest)
  ;  interface:wrap_words(Words, Width, [Word], Lines)
  ).
interface:wrap_words([Word|Words], Width, Acc, Lines) :-
  reverse(Acc, Current),
  atomic_list_concat(Current, ' ', Cur),
  atom_length(Cur, CL),
  atom_length(Word, WL),
  Need is CL + 1 + WL,
  ( Need =< Width
  -> interface:wrap_words(Words, Width, [Word|Acc], Lines)
  ;  Lines = [Cur|Rest],
     interface:wrap_words([Word|Words], Width, [], Rest)
  ).


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
