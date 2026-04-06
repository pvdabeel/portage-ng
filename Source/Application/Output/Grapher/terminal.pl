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
% merge|fetchonly|emerge started|ended|wall_time_ms are stripped from the
main &lt;pre&gt; (including when prefixed by ANSI). Only wall_time_ms is
shown below as seconds; emerge pages may add vs. portage-ng merge time
from the sibling .merge file.
*/

:- module(terminal, []).

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
    split_timing_body(Type, RawContent, BodyContent, timing_display(Wall, _)),
    (   Type = emerge
    ->  merge_wall_seconds_from_graph(Repository, Entry, NgSec),
        Stats = timing_display(Wall, NgSec)
    ;   Stats = timing_display(Wall, none)
    ),
    ansi_to_html(BodyContent, HtmlContent),
    emit_html(Type, Repository://Entry, HtmlContent, Stats).


% -----------------------------------------------------------------------------
%  Content capture
% -----------------------------------------------------------------------------

%! terminal:capture_content(+Type, +Target, -Content)
%
% Obtain the raw ANSI text content for the given type.

terminal:capture_content(merge, Repository://Entry, Content) :-
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

terminal:capture_content(fetchonly, Repository://Entry, Content) :-
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

terminal:capture_content(info, Repository://Entry, Content) :-
    (   catch(
            capture_output(info:print_entry(Repository://Entry), Content),
            _,
            Content = "Failed to retrieve package info."
        )
    ->  true
    ;   Content = "Failed to retrieve package info."
    ).

terminal:capture_content(emerge, Repository://Entry, Content) :-
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

terminal:capture_output(Goal, String) :-
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
            true
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

terminal:resolve_graph_dir(Repository, Dir) :-
    gethostname(Host),
    config:graph_directory(Host, BaseDir),
    !,
    atomic_list_concat([BaseDir, '/', Repository], Dir).
terminal:resolve_graph_dir(_, '/tmp').


%! terminal:merge_wall_seconds_from_graph(+Repository, +Entry, -Seconds)
%
% If graph output contains Entry.merge with a % merge wall_time_ms line, return
% seconds as a float; otherwise none. Used on emerge HTML pages for comparison.

terminal:merge_wall_seconds_from_graph(Repository, Entry, Sec) :-
    resolve_graph_dir(Repository, Dir),
    atomic_list_concat([Dir, '/', Entry, '.merge'], File),
    exists_file(File),
    read_file_to_string(File, MergeText, [encoding(utf8)]),
    partition_timing_content(MergeText, _Kept, Infos),
    member(wall(merge, Ms), Infos),
    !,
    Sec is Ms / 1000.0.
terminal:merge_wall_seconds_from_graph(_, _, none).


% -----------------------------------------------------------------------------
%  Timing metadata (merge / fetchonly / emerge)
% -----------------------------------------------------------------------------

%! terminal:split_timing_body(+Type, +Raw, -Body, -timing_display(WallSec, CompareSlot))
%
% For merge, fetchonly, and emerge, strip "% <label> started|ended|wall_time_ms" lines
% from Raw and return the remainder as Body. CompareSlot in the result is always
% none here; terminal:graph/2 may replace it for emerge with portage-ng merge seconds.
% For info, Body = Raw and timing_display(none, none).

terminal:split_timing_body(info, Raw, Raw, timing_display(none, none)) :-
    !.
terminal:split_timing_body(_, Raw, Body, Stats) :-
    partition_timing_content(Raw, KeptLines, Infos),
    (   Infos = []
    ->  Body = Raw,
        Stats = timing_display(none, none)
    ;   (   KeptLines = []
        ->  Body = ""
        ;   atomics_to_string(KeptLines, '\n', Body)
        ),
        aggregate_timing_infos(Infos, Stats)
    ).


%! terminal:partition_timing_content(+Raw, -KeptLines, -InfoList)
%
% Split Raw into lines; lines matching timing metadata go to InfoList, others to KeptLines.

terminal:partition_timing_content(Raw, KeptLines, InfoList) :-
    split_string(Raw, "\n", "\r", Lines),
    partition_timing_lines(Lines, KeptLines, InfoList).


terminal:partition_timing_lines([], [], []).
terminal:partition_timing_lines([Line|Rest], Kept, Infos) :-
    timing_line_plain_for_meta(Line, Plain),
    (   parse_timing_meta(Plain, Info)
    ->  Kept = Krest,
        Infos = [Info|Irest]
    ;   Kept = [Line|Krest],
        Infos = Irest
    ),
    partition_timing_lines(Rest, Krest, Irest).


%! terminal:timing_line_plain_for_meta(+Line, -Plain)
%
% Strip leading ANSI CSI/OSC so "% emerge started: ..." matches even when
% Portage colors the timing lines.

terminal:timing_line_plain_for_meta(Line, Plain) :-
    (atom(Line) -> atom_string(Line, S0) ; S0 = Line),
    string_codes(S0, Cs0),
    strip_timing_line_esc_prefix(Cs0, Cs),
    string_codes(Plain, Cs).


terminal:strip_timing_line_esc_prefix([27, 91 | Rest], Out) :-
    !,
    collect_csi(Rest, _, _Term, After),
    strip_timing_line_esc_prefix(After, Out).
terminal:strip_timing_line_esc_prefix([27, 93 | Rest], Out) :-
    !,
    skip_osc(Rest, After),
    strip_timing_line_esc_prefix(After, Out).
terminal:strip_timing_line_esc_prefix([27, _ | Rest], Out) :-
    !,
    strip_timing_line_esc_prefix(Rest, Out).
terminal:strip_timing_line_esc_prefix(Cs, Cs).


terminal:parse_timing_meta(Line, Meta) :-
    parse_timing_started(Line, Meta),
    !.
terminal:parse_timing_meta(Line, Meta) :-
    parse_timing_ended(Line, Meta),
    !.
terminal:parse_timing_meta(Line, Meta) :-
    parse_timing_wall(Line, Meta),
    !.


terminal:parse_timing_started(Line, started(_Label, EpochStr, Human)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w started: ', [Label]),
    string_concat(Pfx, Rest, T),
    parse_epoch_human_paren(Rest, EpochStr, Human).


terminal:parse_timing_ended(Line, ended(_Label, EpochStr, Human)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w ended: ', [Label]),
    string_concat(Pfx, Rest, T),
    parse_epoch_human_paren(Rest, EpochStr, Human).


terminal:parse_timing_wall(Line, wall(_Label, Ms)) :-
    normalize_space(string(T), Line),
    member(Label, [merge, emerge, fetchonly]),
    format(string(Pfx), '% ~w wall_time_ms: ', [Label]),
    string_concat(Pfx, Rest, T),
    normalize_space(string(MsStr), Rest),
    number_string(Ms, MsStr).


terminal:parse_epoch_human_paren(Rest, EpochStr, Human) :-
    sub_string(Rest, EpLen, 2, _, " ("),
    !,
    sub_string(Rest, 0, EpLen, _, EpochStr),
    string_length(Rest, Tot),
    StartHum is EpLen + 2,
    HumEnd is Tot - 1,
    HumLen is HumEnd - StartHum,
    HumLen >= 0,
    sub_string(Rest, StartHum, HumLen, _, Human).


%! terminal:aggregate_timing_infos(+Infos, -timing_display(WallSec, none))
%
% WallSec is float seconds from any wall_time_ms line, or none. Second slot is
% always none here (filled for emerge in terminal:graph/2).

terminal:aggregate_timing_infos(Infos, timing_display(WallSec, none)) :-
    timing_wall_seconds(Infos, WallSec).


terminal:timing_wall_seconds(Infos, Sec) :-
    member(wall(_, Ms), Infos),
    !,
    Sec is Ms / 1000.0.
terminal:timing_wall_seconds(_, none).


%! terminal:format_wall_seconds(+Seconds, -String)
%
% Format wall-clock seconds for display (integer if whole, else up to 3 decimals).

terminal:format_wall_seconds(Sec, Str) :-
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

terminal:ansi_to_html(Input, Output) :-
    (atom(Input) -> atom_codes(Input, Codes) ; string_codes(Input, Codes)),
    ansi_walk(Codes, [], [], RevParts),
    reverse(RevParts, Parts),
    atomic_list_concat(Parts, Output).


%! terminal:ansi_walk(+Codes, +Classes, +Acc, -Result)
%
% Walk character codes, accumulating HTML output atoms in reverse order.

terminal:ansi_walk([], Classes, Acc, Result) :-
    (Classes \= [] -> Result = ['</span>' | Acc] ; Result = Acc).

terminal:ansi_walk([27, 91 | Rest], Classes, Acc, Result) :-
    !,
    collect_csi(Rest, ParamCodes, Term, After),
    (   Term == 109
    ->  parse_sgr_params(ParamCodes, Params),
        apply_sgr_params(Params, Classes, NewClasses),
        sgr_transition(Classes, NewClasses, Acc, Acc2),
        ansi_walk(After, NewClasses, Acc2, Result)
    ;   ansi_walk(After, Classes, Acc, Result)
    ).

terminal:ansi_walk([27, 93 | Rest], Classes, Acc, Result) :-
    !,
    skip_osc(Rest, After),
    ansi_walk(After, Classes, Acc, Result).

terminal:ansi_walk([27, _ | Rest], Classes, Acc, Result) :-
    !,
    ansi_walk(Rest, Classes, Acc, Result).

terminal:ansi_walk(Codes, Classes, Acc, Result) :-
    collect_plain(Codes, Plain, Rest),
    Plain \= [],
    !,
    html_escape_codes(Plain, Escaped),
    atom_codes(Atom, Escaped),
    ansi_walk(Rest, Classes, [Atom | Acc], Result).

terminal:ansi_walk([_ | Rest], Classes, Acc, Result) :-
    ansi_walk(Rest, Classes, Acc, Result).


% -----------------------------------------------------------------------------
%  ANSI parser helpers
% -----------------------------------------------------------------------------

terminal:collect_csi([C | Rest], [], C, Rest) :-
    C >= 64, C =< 126, !.
terminal:collect_csi([C | Rest], [C | Params], Term, After) :-
    collect_csi(Rest, Params, Term, After).
terminal:collect_csi([], [], 0, []).


terminal:parse_sgr_params([], [0]) :- !.
terminal:parse_sgr_params(Codes, Params) :-
    split_semicolon(Codes, Groups),
    maplist(param_number, Groups, Params).

terminal:split_semicolon([], [[]]).
terminal:split_semicolon([59 | Rest], [[] | Groups]) :- !,
    split_semicolon(Rest, Groups).
terminal:split_semicolon([C | Rest], [[C | G] | Gs]) :-
    split_semicolon(Rest, [G | Gs]).

terminal:param_number([], 0).
terminal:param_number(Codes, N) :- Codes \= [], catch(number_codes(N, Codes), _, N = 0).


terminal:skip_osc([], []).
terminal:skip_osc([7 | Rest], Rest) :- !.
terminal:skip_osc([27, 92 | Rest], Rest) :- !.
terminal:skip_osc([_ | Rest], After) :- skip_osc(Rest, After).


terminal:collect_plain([], [], []).
terminal:collect_plain([27 | Rest], [], [27 | Rest]) :- !.
terminal:collect_plain([C | Rest], [C | Plain], After) :-
    collect_plain(Rest, Plain, After).


terminal:html_escape_codes([], []).
terminal:html_escape_codes([38 | R], [0'&, 0'a, 0'm, 0'p, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
terminal:html_escape_codes([60 | R], [0'&, 0'l, 0't, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
terminal:html_escape_codes([62 | R], [0'&, 0'g, 0't, 0'; | Out]) :- !,
    html_escape_codes(R, Out).
terminal:html_escape_codes([C | R], Out) :-
    C >= 0xE000, C =< 0xF8FF, !,
    atom_codes('<span class="pua">', Open),
    atom_codes('</span>', Close),
    append(Open, [C | Mid], Out),
    append(Close, Tail, Mid),
    html_escape_codes(R, Tail).
terminal:html_escape_codes([C | R], [C | Out]) :- html_escape_codes(R, Out).


% -----------------------------------------------------------------------------
%  SGR state management
% -----------------------------------------------------------------------------

terminal:apply_sgr_params([], C, C).
terminal:apply_sgr_params([P | Rest], C, Final) :-
    apply_one_sgr(P, C, Mid),
    apply_sgr_params(Rest, Mid, Final).

terminal:apply_one_sgr(0, _, []) :- !.
terminal:apply_one_sgr(1, C, R) :- !, add_class(C, 'ansi-bold', R).
terminal:apply_one_sgr(2, C, R) :- !, add_class(C, 'ansi-dim', R).
terminal:apply_one_sgr(3, C, R) :- !, add_class(C, 'ansi-italic', R).
terminal:apply_one_sgr(4, C, R) :- !, add_class(C, 'ansi-underline', R).
terminal:apply_one_sgr(22, C, R) :- !, delete(C, 'ansi-bold', C1), delete(C1, 'ansi-dim', R).
terminal:apply_one_sgr(23, C, R) :- !, delete(C, 'ansi-italic', R).
terminal:apply_one_sgr(24, C, R) :- !, delete(C, 'ansi-underline', R).
terminal:apply_one_sgr(N, C, R) :- N >= 30, N =< 37, !, fg_class(N, Cls), set_fg(C, Cls, R).
terminal:apply_one_sgr(39, C, R) :- !, remove_fg(C, R).
terminal:apply_one_sgr(N, C, R) :- N >= 40, N =< 47, !, bg_class(N, Cls), set_bg(C, Cls, R).
terminal:apply_one_sgr(49, C, R) :- !, remove_bg(C, R).
terminal:apply_one_sgr(N, C, R) :- N >= 90, N =< 97, !, bfg_class(N, Cls), set_fg(C, Cls, R).
terminal:apply_one_sgr(N, C, R) :- N >= 100, N =< 107, !, bbg_class(N, Cls), set_bg(C, Cls, R).
terminal:apply_one_sgr(_, C, C).

terminal:fg_class(30,'fg-black').   terminal:fg_class(31,'fg-red').      terminal:fg_class(32,'fg-green').
terminal:fg_class(33,'fg-yellow').  terminal:fg_class(34,'fg-blue').     terminal:fg_class(35,'fg-magenta').
terminal:fg_class(36,'fg-cyan').    terminal:fg_class(37,'fg-white').

terminal:bg_class(40,'bg-black').   terminal:bg_class(41,'bg-red').      terminal:bg_class(42,'bg-green').
terminal:bg_class(43,'bg-yellow').  terminal:bg_class(44,'bg-blue').     terminal:bg_class(45,'bg-magenta').
terminal:bg_class(46,'bg-cyan').    terminal:bg_class(47,'bg-white').

terminal:bfg_class(90,'fg-bright-black').  terminal:bfg_class(91,'fg-bright-red').
terminal:bfg_class(92,'fg-bright-green').  terminal:bfg_class(93,'fg-bright-yellow').
terminal:bfg_class(94,'fg-bright-blue').   terminal:bfg_class(95,'fg-bright-magenta').
terminal:bfg_class(96,'fg-bright-cyan').   terminal:bfg_class(97,'fg-bright-white').

terminal:bbg_class(100,'bg-bright-black'). terminal:bbg_class(101,'bg-bright-red').
terminal:bbg_class(102,'bg-bright-green'). terminal:bbg_class(103,'bg-bright-yellow').
terminal:bbg_class(104,'bg-bright-blue').  terminal:bbg_class(105,'bg-bright-magenta').
terminal:bbg_class(106,'bg-bright-cyan').  terminal:bbg_class(107,'bg-bright-white').

terminal:set_fg(Classes, New, [New | Rest]) :- exclude(is_fg, Classes, Rest).
terminal:set_bg(Classes, New, [New | Rest]) :- exclude(is_bg, Classes, Rest).
terminal:remove_fg(Classes, Rest) :- exclude(is_fg, Classes, Rest).
terminal:remove_bg(Classes, Rest) :- exclude(is_bg, Classes, Rest).
terminal:add_class(C, Cls, C) :- memberchk(Cls, C), !.
terminal:add_class(C, Cls, [Cls | C]).
terminal:is_fg(C) :- atom_concat('fg-', _, C).
terminal:is_bg(C) :- atom_concat('bg-', _, C).

terminal:sgr_transition(Old, New, Acc, Result) :-
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
% timing_display(WallSec, CompareNgSec): CompareNgSec is merge seconds for emerge
% pages only (none otherwise).

terminal:emit_html(Type, Target, HtmlContent, TimingStats) :-
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
    emit_content(Type, HtmlContent, TimingStats),
    emit_body_close.

terminal:type_label(merge, 'Merge Plan').
terminal:type_label(fetchonly, 'Fetch Plan').
terminal:type_label(info, 'Package Info').
terminal:type_label(emerge, 'Emerge Output').


% -----------------------------------------------------------------------------
%  HTML emission - document structure
% -----------------------------------------------------------------------------

terminal:emit_doctype :-
    write('<!DOCTYPE html>'), nl.

terminal:emit_head_open(Cat, Name, Ver, Label) :-
    write('<html lang="en" data-theme="dark">'), nl,
    write('<head>'), nl,
    write('<meta charset="UTF-8">'), nl,
    write('<meta name="viewport" content="width=device-width, initial-scale=1.0">'), nl,
    format('<title>~w/~w-~w &mdash; ~w</title>~n', [Cat, Name, Ver, Label]),
    navtheme:emit_css_link('../').

terminal:emit_head_close :-
    write('</head>'), nl.

terminal:emit_body_open :-
    write('<body class="page-terminal">'), nl.

terminal:emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - body elements
% -----------------------------------------------------------------------------

terminal:emit_title_row(Cat, Name, Ver, Label) :-
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w/~w-~w &mdash; ~w</h1>~n', [Cat, Name, Ver, Label]),
    navtheme:emit_theme_btn,
    write('</div>'), nl.


terminal:emit_content(Type, HtmlContent, TimingStats) :-
    write('<div class="content">'), nl,
    write('<pre class="terminal">'),
    write(HtmlContent),
    write('</pre>'), nl,
    emit_terminal_stats(Type, TimingStats),
    write('</div>'), nl,
    navtheme:emit_theme_script('terminal-theme').


%! terminal:emit_terminal_stats(+Type, +timing_display(WallSec, CompareNgSec))
%
% Emit wall time only. On emerge pages, append portage-ng merge time when
% terminal:merge_wall_seconds_from_graph/3 found a .merge wall_time_ms.

terminal:emit_terminal_stats(_, timing_display(none, _)) :-
    !.
terminal:emit_terminal_stats(_, timing_display(W, _)) :-
    W == none,
    !.
terminal:emit_terminal_stats(Type, timing_display(WallSec, CompareNg)) :-
    write('<div class="terminal-stats" role="status">'), nl,
    write('  <dl>'), nl,
    format_wall_seconds(WallSec, WStr),
    (   CompareNg \== none,
        Type = emerge
    ->  format_wall_seconds(CompareNg, NgStr),
        format(string(Dd), '~w s <span class="vs-portage-ng">vs. <span class="wall-time-sec">~w s</span> for portage-ng</span>', [WStr, NgStr])
    ;   format(string(Dd), '~w s', [WStr])
    ),
    emit_stat_row_dd('Wall time', Dd),
    write('  </dl>'), nl,
    write('</div>'), nl.


%! terminal:emit_stat_row_dd(+Label, +DdString)
%
% Emit one &lt;dt&gt;/&lt;dd&gt; pair; DdString may contain inline HTML spans.

terminal:emit_stat_row_dd(Label, Dd) :-
    write('    <dt>'),
    write(Label),
    write('</dt><dd>'),
    write(Dd),
    write('</dd>'), nl.
