/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> TERMINAL
Terminal output to HTML renderer for portage-ng. Converts ANSI-escaped text
(merge plans, fetchonly plans, package info, emerge output) into styled
self-contained HTML pages with day/night theme toggle. Lines of the form
% merge|fetchonly|emerge started|ended|wall_time_ms are removed from the
main &lt;pre&gt; and summarized below it (wall time in seconds).
*/

:- module(terminal, []).

:- use_module('../Printer/Plan/timing.pl', []).

% =============================================================================
%  TERMINAL declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! terminal:graph(+Type, +Target)
%
% Generate a terminal-output HTML page for the given graph type.
% Type is one of merge, fetchonly, info, emerge.

terminal:graph(Type, Repository://Entry) :-
    capture_content(Type, Repository://Entry, RawContent),
    split_timing_body(Type, RawContent, BodyContent, TimingStats),
    ansi_to_html(BodyContent, HtmlContent),
    emit_html(Type, Repository://Entry, HtmlContent, TimingStats).


% -----------------------------------------------------------------------------
%  Content capture
% -----------------------------------------------------------------------------

%! terminal:capture_content(+Type, +Target, -Content)
%
% Obtain the raw ANSI text content for the given type.

capture_content(merge, Repository://Entry, Content) :-
    Goals = [Repository://Entry:run?{[]}],
    get_time(T0),
    (   catch(
            (   pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers),
                capture_output(
                    (   timing:print_timing_header('merge', T0),
                        printer:print(Goals, Model, Proof, Plan, Triggers),
                        timing:print_timing_footer('merge', T0)
                    ),
                    Content)
            ),
            _,
            Content = "Failed to compute merge plan."
        )
    ->  true
    ;   Content = "Failed to compute merge plan."
    ).

capture_content(fetchonly, Repository://Entry, Content) :-
    Goals = [Repository://Entry:fetchonly?{[]}],
    get_time(T0),
    (   catch(
            (   pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers),
                capture_output(
                    (   timing:print_timing_header('fetchonly', T0),
                        printer:print(Goals, Model, Proof, Plan, Triggers),
                        timing:print_timing_footer('fetchonly', T0)
                    ),
                    Content)
            ),
            _,
            Content = "Failed to compute fetchonly plan."
        )
    ->  true
    ;   Content = "Failed to compute fetchonly plan."
    ).

capture_content(info, Repository://Entry, Content) :-
    (   catch(
            capture_output(info:print_entry(Repository://Entry), Content),
            _,
            Content = "Failed to retrieve package info."
        )
    ->  true
    ;   Content = "Failed to retrieve package info."
    ).

capture_content(emerge, Repository://Entry, Content) :-
    resolve_graph_dir(Repository, Dir),
    atomic_list_concat([Dir, '/', Entry, '.emerge'], File),
    (   exists_file(File)
    ->  read_file_to_string(File, Content, [encoding(utf8)])
    ;   Content = "No emerge output available."
    ).


%! terminal:capture_output(+Goal, -String)
%
% Run Goal with output redirected to a temp file (TTY mode enabled for ANSI),
% then read the file content back as a string.

capture_output(Goal, String) :-
    tmp_file_stream(utf8, TmpFile, TmpStream),
    close(TmpStream),
    (   catch(
            setup_call_cleanup(
                tell(TmpFile),
                ( set_stream(current_output, tty(true)),
                  Goal
                ),
                told
            ),
            _,
            told
        )
    ->  true
    ;   true
    ),
    (   exists_file(TmpFile)
    ->  read_file_to_string(TmpFile, String, [encoding(utf8)]),
        catch(delete_file(TmpFile), _, true)
    ;   String = ""
    ).


%! terminal:resolve_graph_dir(+Repository, -Dir)
%
% Resolve the graph output directory for a repository.

resolve_graph_dir(Repository, Dir) :-
    gethostname(Host),
    config:graph_directory(Host, BaseDir),
    !,
    atomic_list_concat([BaseDir, '/', Repository], Dir).
resolve_graph_dir(_, '/tmp').


% -----------------------------------------------------------------------------
%  Timing metadata (merge / fetchonly / emerge)
% -----------------------------------------------------------------------------

%! terminal:split_timing_body(+Type, +Raw, -Body, -timing_display(WallSec, StartedH, EndedH))
%
% For merge, fetchonly, and emerge, strip "% <label> started|ended|wall_time_ms" lines
% from Raw and return the remainder as Body. Aggregates human-readable started/ended
% timestamps and wall clock seconds from wall_time_ms. For info, Body = Raw and
% timing_display(none, '', '').

split_timing_body(info, Raw, Raw, timing_display(none, '', '')) :-
    !.
split_timing_body(_, Raw, Body, Stats) :-
    partition_timing_content(Raw, KeptLines, Infos),
    (   Infos = []
    ->  Body = Raw,
        Stats = timing_display(none, '', '')
    ;   (   KeptLines = []
        ->  Body = ""
        ;   atomics_to_string(KeptLines, '\n', Body)
        ),
        aggregate_timing_infos(Infos, Stats)
    ).


%! terminal:partition_timing_content(+Raw, -KeptLines, -InfoList)
%
% Split Raw into lines; lines matching timing metadata go to InfoList, others to KeptLines.

partition_timing_content(Raw, KeptLines, InfoList) :-
    split_string(Raw, "\n", "\r", Lines),
    partition_timing_lines(Lines, KeptLines, InfoList).


partition_timing_lines([], [], []).
partition_timing_lines([Line|Rest], Kept, Infos) :-
    (   parse_timing_meta(Line, Info)
    ->  Kept = Krest,
        Infos = [Info|Irest]
    ;   Kept = [Line|Krest],
        Infos = Irest
    ),
    partition_timing_lines(Rest, Krest, Irest).


parse_timing_meta(Line, Meta) :-
    parse_timing_started(Line, Meta),
    !.
parse_timing_meta(Line, Meta) :-
    parse_timing_ended(Line, Meta),
    !.
parse_timing_meta(Line, Meta) :-
    parse_timing_wall(Line, Meta),
    !.


parse_timing_started(Line, started(_Label, EpochStr, Human)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w started: ', [Label]),
    string_concat(Pfx, Rest, T),
    parse_epoch_human_paren(Rest, EpochStr, Human).


parse_timing_ended(Line, ended(_Label, EpochStr, Human)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w ended: ', [Label]),
    string_concat(Pfx, Rest, T),
    parse_epoch_human_paren(Rest, EpochStr, Human).


parse_timing_wall(Line, wall(_Label, Ms)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w wall_time_ms: ', [Label]),
    string_concat(Pfx, Rest, T),
    normalize_space(string(MsStr), Rest),
    number_string(Ms, MsStr).


parse_epoch_human_paren(Rest, EpochStr, Human) :-
    sub_string(Rest, EpLen, 3, _, " ("),
    !,
    sub_string(Rest, 0, EpLen, _, EpochStr),
    string_length(Rest, Tot),
    StartHum is EpLen + 3,
    HumEnd is Tot - 1,
    HumLen is HumEnd - StartHum,
    HumLen >= 0,
    sub_string(Rest, StartHum, HumLen, _, Human).


%! terminal:aggregate_timing_infos(+Infos, -timing_display(WallSec, StartedH, EndedH))
%
% WallSec is a float seconds from wall_time_ms, or the atom none. StartedH and EndedH
% are human timestamp strings from the parentheses in started/ended lines.

aggregate_timing_infos(Infos, timing_display(WallSec, Sh, Eh)) :-
    timing_started_human(Infos, Sh),
    timing_ended_human(Infos, Eh),
    timing_wall_seconds(Infos, WallSec).


timing_started_human(Infos, H) :-
    member(started(_, _, H), Infos),
    !.
timing_started_human(_, '').


timing_ended_human(Infos, H) :-
    member(ended(_, _, H), Infos),
    !.
timing_ended_human(_, '').


timing_wall_seconds(Infos, Sec) :-
    member(wall(_, Ms), Infos),
    !,
    Sec is Ms / 1000.0.
timing_wall_seconds(_, none).


%! terminal:format_wall_seconds(+Seconds, -String)
%
% Format wall-clock seconds for display (integer if whole, else up to 3 decimals).

format_wall_seconds(Sec, Str) :-
    Ms is round(Sec * 1000),
    (   Ms mod 1000 =:= 0
    ->  S0 is Ms // 1000,
        format(string(Str), '~d', [S0])
    ;   format(string(Str), '~3f', [Sec])
    ).


% -----------------------------------------------------------------------------
%  ANSI-to-HTML conversion
% -----------------------------------------------------------------------------

%! terminal:ansi_to_html(+Input, -Output)
%
% Convert a string containing ANSI escape sequences into HTML with span
% elements using CSS classes for styling. Handles SGR codes for colors,
% bold, dim, italic, underline, and resets.

ansi_to_html(Input, Output) :-
    (atom(Input) -> atom_codes(Input, Codes) ; string_codes(Input, Codes)),
    ansi_walk(Codes, [], [], RevParts),
    reverse(RevParts, Parts),
    atomic_list_concat(Parts, Output).


%! terminal:ansi_walk(+Codes, +Classes, +Acc, -Result)
%
% Walk character codes, accumulating HTML output atoms in reverse order.

ansi_walk([], Classes, Acc, Result) :-
    (Classes \= [] -> Result = ['</span>' | Acc] ; Result = Acc).

ansi_walk([27, 91 | Rest], Classes, Acc, Result) :-
    !,
    collect_csi(Rest, ParamCodes, Term, After),
    (   Term == 109
    ->  parse_sgr_params(ParamCodes, Params),
        apply_sgr_params(Params, Classes, NewClasses),
        sgr_transition(Classes, NewClasses, Acc, Acc2),
        ansi_walk(After, NewClasses, Acc2, Result)
    ;   ansi_walk(After, Classes, Acc, Result)
    ).

ansi_walk([27, 93 | Rest], Classes, Acc, Result) :-
    !,
    skip_osc(Rest, After),
    ansi_walk(After, Classes, Acc, Result).

ansi_walk([27, _ | Rest], Classes, Acc, Result) :-
    !,
    ansi_walk(Rest, Classes, Acc, Result).

ansi_walk(Codes, Classes, Acc, Result) :-
    collect_plain(Codes, Plain, Rest),
    Plain \= [],
    !,
    html_escape_codes(Plain, Escaped),
    atom_codes(Atom, Escaped),
    ansi_walk(Rest, Classes, [Atom | Acc], Result).

ansi_walk([_ | Rest], Classes, Acc, Result) :-
    ansi_walk(Rest, Classes, Acc, Result).


% -----------------------------------------------------------------------------
%  ANSI parser helpers
% -----------------------------------------------------------------------------

collect_csi([C | Rest], [], C, Rest) :-
    C >= 64, C =< 126, !.
collect_csi([C | Rest], [C | Params], Term, After) :-
    collect_csi(Rest, Params, Term, After).
collect_csi([], [], 0, []).


parse_sgr_params([], [0]) :- !.
parse_sgr_params(Codes, Params) :-
    split_semicolon(Codes, Groups),
    maplist(param_number, Groups, Params).

split_semicolon([], [[]]).
split_semicolon([59 | Rest], [[] | Groups]) :- !,
    split_semicolon(Rest, Groups).
split_semicolon([C | Rest], [[C | G] | Gs]) :-
    split_semicolon(Rest, [G | Gs]).

param_number([], 0).
param_number(Codes, N) :- Codes \= [], catch(number_codes(N, Codes), _, N = 0).


skip_osc([], []).
skip_osc([7 | Rest], Rest) :- !.
skip_osc([27, 92 | Rest], Rest) :- !.
skip_osc([_ | Rest], After) :- skip_osc(Rest, After).


collect_plain([], [], []).
collect_plain([27 | Rest], [], [27 | Rest]) :- !.
collect_plain([C | Rest], [C | Plain], After) :-
    collect_plain(Rest, Plain, After).


html_escape_codes([], []).
html_escape_codes([38 | R], [0'&, 0'a, 0'm, 0'p, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
html_escape_codes([60 | R], [0'&, 0'l, 0't, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
html_escape_codes([62 | R], [0'&, 0'g, 0't, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
html_escape_codes([C | R], Out) :-
    C >= 0xE000, C =< 0xF8FF, !,
    atom_codes('<span class="pua">', Open),
    atom_codes('</span>', Close),
    append(Open, [C | Mid], Out),
    append(Close, Tail, Mid),
    html_escape_codes(R, Tail).
html_escape_codes([C | R], [C | Out]) :- html_escape_codes(R, Out).


% -----------------------------------------------------------------------------
%  SGR state management
% -----------------------------------------------------------------------------

apply_sgr_params([], C, C).
apply_sgr_params([P | Rest], C, Final) :-
    apply_one_sgr(P, C, Mid),
    apply_sgr_params(Rest, Mid, Final).

apply_one_sgr(0, _, []) :- !.
apply_one_sgr(1, C, R) :- !, add_class(C, 'ansi-bold', R).
apply_one_sgr(2, C, R) :- !, add_class(C, 'ansi-dim', R).
apply_one_sgr(3, C, R) :- !, add_class(C, 'ansi-italic', R).
apply_one_sgr(4, C, R) :- !, add_class(C, 'ansi-underline', R).
apply_one_sgr(22, C, R) :- !, delete(C, 'ansi-bold', C1), delete(C1, 'ansi-dim', R).
apply_one_sgr(23, C, R) :- !, delete(C, 'ansi-italic', R).
apply_one_sgr(24, C, R) :- !, delete(C, 'ansi-underline', R).
apply_one_sgr(N, C, R) :- N >= 30, N =< 37, !, fg_class(N, Cls), set_fg(C, Cls, R).
apply_one_sgr(39, C, R) :- !, remove_fg(C, R).
apply_one_sgr(N, C, R) :- N >= 40, N =< 47, !, bg_class(N, Cls), set_bg(C, Cls, R).
apply_one_sgr(49, C, R) :- !, remove_bg(C, R).
apply_one_sgr(N, C, R) :- N >= 90, N =< 97, !, bfg_class(N, Cls), set_fg(C, Cls, R).
apply_one_sgr(N, C, R) :- N >= 100, N =< 107, !, bbg_class(N, Cls), set_bg(C, Cls, R).
apply_one_sgr(_, C, C).

fg_class(30,'fg-black').   fg_class(31,'fg-red').      fg_class(32,'fg-green').
fg_class(33,'fg-yellow').  fg_class(34,'fg-blue').     fg_class(35,'fg-magenta').
fg_class(36,'fg-cyan').    fg_class(37,'fg-white').

bg_class(40,'bg-black').   bg_class(41,'bg-red').      bg_class(42,'bg-green').
bg_class(43,'bg-yellow').  bg_class(44,'bg-blue').     bg_class(45,'bg-magenta').
bg_class(46,'bg-cyan').    bg_class(47,'bg-white').

bfg_class(90,'fg-bright-black').  bfg_class(91,'fg-bright-red').
bfg_class(92,'fg-bright-green').  bfg_class(93,'fg-bright-yellow').
bfg_class(94,'fg-bright-blue').   bfg_class(95,'fg-bright-magenta').
bfg_class(96,'fg-bright-cyan').   bfg_class(97,'fg-bright-white').

bbg_class(100,'bg-bright-black'). bbg_class(101,'bg-bright-red').
bbg_class(102,'bg-bright-green'). bbg_class(103,'bg-bright-yellow').
bbg_class(104,'bg-bright-blue').  bbg_class(105,'bg-bright-magenta').
bbg_class(106,'bg-bright-cyan').  bbg_class(107,'bg-bright-white').

set_fg(Classes, New, [New | Rest]) :- exclude(is_fg, Classes, Rest).
set_bg(Classes, New, [New | Rest]) :- exclude(is_bg, Classes, Rest).
remove_fg(Classes, Rest) :- exclude(is_fg, Classes, Rest).
remove_bg(Classes, Rest) :- exclude(is_bg, Classes, Rest).
add_class(C, Cls, C) :- memberchk(Cls, C), !.
add_class(C, Cls, [Cls | C]).
is_fg(C) :- atom_concat('fg-', _, C).
is_bg(C) :- atom_concat('bg-', _, C).

sgr_transition(Old, New, Acc, Result) :-
    (Old \= [] -> A1 = ['</span>' | Acc] ; A1 = Acc),
    (   New \= []
    ->  atomic_list_concat(New, ' ', Str),
        atomic_list_concat(['<span class="', Str, '">'], Tag),
        Result = [Tag | A1]
    ;   Result = A1
    ).


% -----------------------------------------------------------------------------
%  HTML emission - main
% -----------------------------------------------------------------------------

%! terminal:emit_html(+Type, +Target, +HtmlContent, +TimingStats)
%
% Emit a complete styled HTML document wrapping terminal output. TimingStats is
% timing_display/3 for optional stats below the &lt;pre&gt;.

emit_html(Type, Target, HtmlContent, TimingStats) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    gantt:version_str(Version, Ver),
    type_label(Type, Label),
    emit_doctype,
    emit_head_open(Cat, Name, Ver, Label),
    emit_head_close,
    emit_body_open,
    emit_title_row(Cat, Name, Ver, Label),
    deptree:version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    navtheme:emit_nav_bar(Repo, Entry, Cat, Name, Type, Newer, Newest, Older, Oldest),
    write('</div>'), nl,
    emit_content(HtmlContent, TimingStats),
    emit_body_close.

type_label(merge, 'Merge Plan').
type_label(fetchonly, 'Fetch Plan').
type_label(info, 'Package Info').
type_label(emerge, 'Emerge Output').


% -----------------------------------------------------------------------------
%  HTML emission - document structure
% -----------------------------------------------------------------------------

emit_doctype :-
    write('<!DOCTYPE html>'), nl.

emit_head_open(Cat, Name, Ver, Label) :-
    write('<html lang="en" data-theme="dark">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    format('<title>~w/~w-~w &mdash; ~w</title>~n', [Cat, Name, Ver, Label]),
    navtheme:emit_css_link('../').

emit_head_close :-
    write('</head>'), nl.

emit_body_open :-
    write('<body class="page-terminal">'), nl.

emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - body elements
% -----------------------------------------------------------------------------

emit_title_row(Cat, Name, Ver, Label) :-
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w/~w-~w &mdash; ~w</h1>~n', [Cat, Name, Ver, Label]),
    navtheme:emit_theme_btn,
    write('</div>'), nl.


emit_content(HtmlContent, TimingStats) :-
    write('<div class="content">'), nl,
    write('<pre class="terminal">'),
    write(HtmlContent),
    write('</pre>'), nl,
    emit_terminal_stats(TimingStats),
    write('</div>'), nl,
    navtheme:emit_theme_script('terminal-theme').


%! terminal:emit_terminal_stats(+timing_display(WallSec, StartedH, EndedH))
%
% Emit a definition list below the terminal block when any timing field is present.

emit_terminal_stats(timing_display(none, '', '')) :-
    !.
emit_terminal_stats(timing_display(W, Sh, Eh)) :-
    W == none,
    Sh == '',
    Eh == '',
    !.
emit_terminal_stats(timing_display(WallSec, Sh, Eh)) :-
    write('<div class="terminal-stats" role="status">'), nl,
    write('  <dl>'), nl,
    (   WallSec \== none
    ->  format_wall_seconds(WallSec, WStr),
        format(atom(Dd), '~w s', [WStr]),
        emit_stat_row('Wall time', Dd)
    ;   true
    ),
    (   Sh \== ''
    ->  emit_stat_row('Started', Sh)
    ;   true
    ),
    (   Eh \== ''
    ->  emit_stat_row('Ended', Eh)
    ;   true
    ),
    write('  </dl>'), nl,
    write('</div>'), nl.


%! terminal:emit_stat_row(+Label, +Value)
%
% Emit one &lt;dt&gt;/&lt;dd&gt; pair. Label and Value are atoms (safe literals / formatted times).

emit_stat_row(Label, Value) :-
    write('    <dt>'),
    write(Label),
    write('</dt><dd>'),
    write(Value),
    write('</dd>'), nl.
