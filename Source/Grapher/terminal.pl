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
self-contained HTML pages with day/night theme toggle.
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
    ansi_to_html(RawContent, HtmlContent),
    emit_html(Type, Repository://Entry, HtmlContent).


% -----------------------------------------------------------------------------
%  Content capture
% -----------------------------------------------------------------------------

%! terminal:capture_content(+Type, +Target, -Content)
%
% Obtain the raw ANSI text content for the given type.

capture_content(merge, Repository://Entry, Content) :-
    Goals = [Repository://Entry:run?{[]}],
    (   catch(
            (   pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers),
                capture_output(printer:print(Goals, Model, Proof, Plan, Triggers), Content)
            ),
            _,
            Content = "Failed to compute merge plan."
        )
    ->  true
    ;   Content = "Failed to compute merge plan."
    ).

capture_content(fetchonly, Repository://Entry, Content) :-
    Goals = [Repository://Entry:fetchonly?{[]}],
    (   catch(
            (   pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers),
                capture_output(printer:print(Goals, Model, Proof, Plan, Triggers), Content)
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
    html_escape_codes(R, Out).
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

%! terminal:emit_html(+Type, +Target, +HtmlContent)
%
% Emit a complete styled HTML document wrapping terminal output.

emit_html(Type, Target, HtmlContent) :-
    Target = Repo://Entry,
    cache:ordered_entry(Repo, Entry, Cat, Name, Version),
    gantt:version_str(Version, Ver),
    type_label(Type, Label),
    emit_doctype,
    emit_head_open(Cat, Name, Ver, Label),
    emit_css,
    emit_head_close,
    emit_body_open,
    emit_title_row(Cat, Name, Ver, Label),
    deptree:version_neighbours(Repo, Entry, Newer, Newest, Older, Oldest),
    emit_nav_bar(Repo, Entry, Cat, Name, Type, Newer, Newest, Older, Oldest),
    emit_content(HtmlContent),
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
    format('<title>~w/~w-~w &mdash; ~w</title>~n', [Cat, Name, Ver, Label]).

emit_head_close :-
    write('</head>'), nl.

emit_body_open :-
    write('<body>'), nl.

emit_body_close :-
    write('</body>'), nl,
    write('</html>'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - CSS with day/night theming and ANSI colors
% -----------------------------------------------------------------------------

emit_css :-
    write('<style>'), nl,
    emit_css_variables,
    emit_css_base,
    emit_css_ansi,
    write('</style>'), nl.

emit_css_variables :-
    write('  :root {'), nl,
    write('    --bg: #1e1e2e; --surface: #282840; --surface2: #313150;'), nl,
    write('    --border: #444466; --text: #e0e0f0; --text2: #a0a0c0; --text3: #777799;'), nl,
    write('    --accent: #7aa2f7; --link: #7aa2f7;'), nl,
    write('    --pre-bg: #1a1a2a;'), nl,
    write('    --ansi-black: #555; --ansi-red: #f7768e; --ansi-green: #9ece6a;'), nl,
    write('    --ansi-yellow: #e0af68; --ansi-blue: #7aa2f7; --ansi-magenta: #bb9af7;'), nl,
    write('    --ansi-cyan: #7dcfff; --ansi-white: #c0c0d0;'), nl,
    write('    --ansi-bright-black: #888; --ansi-bright-red: #ff9e9e;'), nl,
    write('    --ansi-bright-green: #b5e890; --ansi-bright-yellow: #f0c890;'), nl,
    write('    --ansi-bright-blue: #9ec5ff; --ansi-bright-magenta: #d0b0ff;'), nl,
    write('    --ansi-bright-cyan: #a0e0ff; --ansi-bright-white: #e0e0f0;'), nl,
    write('    --ansi-bg-red: #a13050; --ansi-bg-green: #4a7a30; --ansi-bg-yellow: #8a6a20;'), nl,
    write('    --ansi-bg-blue: #3060a0; --ansi-bg-magenta: #6a3090; --ansi-bg-cyan: #207080;'), nl,
    write('    --ansi-bg-black: #505060; --ansi-bg-white: #707080;'), nl,
    write('    --bubble-text: #f0f0f0;'), nl,
    write('  }'), nl,
    write('  [data-theme="light"] {'), nl,
    write('    --bg: #fdfdfd; --surface: #f5f5f5; --surface2: #fafbfc;'), nl,
    write('    --border: #e0e0e0; --text: #333; --text2: #888; --text3: #bbb;'), nl,
    write('    --accent: #1565c0; --link: #1565c0;'), nl,
    write('    --pre-bg: #fafafa;'), nl,
    write('    --ansi-black: #333; --ansi-red: #c62828; --ansi-green: #2e7d32;'), nl,
    write('    --ansi-yellow: #e65100; --ansi-blue: #1565c0; --ansi-magenta: #6a1b9a;'), nl,
    write('    --ansi-cyan: #0277bd; --ansi-white: #888;'), nl,
    write('    --ansi-bright-black: #666; --ansi-bright-red: #e53935;'), nl,
    write('    --ansi-bright-green: #43a047; --ansi-bright-yellow: #ef6c00;'), nl,
    write('    --ansi-bright-blue: #1e88e5; --ansi-bright-magenta: #8e24aa;'), nl,
    write('    --ansi-bright-cyan: #00acc1; --ansi-bright-white: #333;'), nl,
    write('    --bubble-text: #333;'), nl,
    write('    --ansi-bg-red: #ffe0e0; --ansi-bg-green: #e0f0e0; --ansi-bg-yellow: #fff0d0;'), nl,
    write('    --ansi-bg-blue: #e0e8ff; --ansi-bg-magenta: #f0e0ff; --ansi-bg-cyan: #e0f0f8;'), nl,
    write('    --ansi-bg-black: #e0e0e0; --ansi-bg-white: #f0f0f0;'), nl,
    write('  }'), nl.

emit_css_base :-
    write('  * { box-sizing: border-box; margin: 0; padding: 0; }'), nl,
    write('  body { font-family: "Helvetica Neue", Helvetica, Arial, sans-serif;'), nl,
    write('         background: var(--bg); color: var(--text); padding: 24px 32px; }'), nl,
    write('  .header { padding-bottom: 10px; border-bottom: 1px solid var(--border); margin-bottom: 12px; }'), nl,
    write('  .title-row { display: flex; align-items: center; justify-content: space-between; }'), nl,
    write('  h1 { font-size: 18px; font-weight: 600; }'), nl,
    write('  .theme-btn { background: var(--surface); border: 1px solid var(--border);'), nl,
    write('               border-radius: 6px; padding: 4px 10px; cursor: pointer;'), nl,
    write('               font-size: 14px; color: var(--text2); }'), nl,
    write('  .theme-btn:hover { background: var(--surface2); color: var(--text); }'), nl,
    write('  .nav-rows { display: flex; flex-direction: column; gap: 6px; margin-top: 10px; }'), nl,
    write('  .nav-bar { display: flex; gap: 8px; font-size: 10px; width: fit-content; }'), nl,
    write('  .nav-group { display: flex; gap: 0; border: 1px solid var(--border);'), nl,
    write('               border-radius: 4px; overflow: hidden; }'), nl,
    write('  .nav-group-label { font-size: 8px; font-weight: 600; color: var(--text2);'), nl,
    write('                     text-transform: uppercase; letter-spacing: 0.5px;'), nl,
    write('                     padding: 3px 8px; background: var(--surface); display: flex;'), nl,
    write('                     align-items: center; border-right: 1px solid var(--border); }'), nl,
    write('  .nav-link { padding: 4px 8px; color: var(--text); text-decoration: none;'), nl,
    write('              border-right: 1px solid var(--border); cursor: pointer; }'), nl,
    write('  .nav-link:last-child { border-right: none; }'), nl,
    write('  .nav-link:hover { background: var(--surface2); color: var(--accent); }'), nl,
    write('  .nav-link.active { font-weight: 700; color: var(--accent);'), nl,
    write('                     background: var(--surface2); border-bottom: 2px solid var(--accent); }'), nl,
    write('  .nav-link.disabled { color: var(--text3); cursor: default; }'), nl,
    write('  .nav-link.disabled:hover { background: transparent; color: var(--text3); }'), nl,
    write('  .content { margin-top: 12px; }'), nl,
    write('  pre.terminal { background: var(--pre-bg); border: 1px solid var(--border);'), nl,
    write('                 border-radius: 6px; padding: 16px 20px; overflow-x: auto;'), nl,
    write('                 font-family: "SF Mono", "Cascadia Code", "Fira Code", Menlo, monospace;'), nl,
    write('                 font-size: 12px; line-height: 1.5; color: var(--text);'), nl,
    write('                 white-space: pre-wrap; word-wrap: break-word;'), nl,
    write('                 max-height: calc(100vh - 200px); overflow-y: auto; }'), nl,
    write('  ::-webkit-scrollbar { width: 8px; height: 8px; }'), nl,
    write('  ::-webkit-scrollbar-track { background: var(--bg); }'), nl,
    write('  ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }'), nl.

emit_css_ansi :-
    write('  .fg-black { color: var(--ansi-black); }'), nl,
    write('  .fg-red { color: var(--ansi-red); }'), nl,
    write('  .fg-green { color: var(--ansi-green); }'), nl,
    write('  .fg-yellow { color: var(--ansi-yellow); }'), nl,
    write('  .fg-blue { color: var(--ansi-blue); }'), nl,
    write('  .fg-magenta { color: var(--ansi-magenta); }'), nl,
    write('  .fg-cyan { color: var(--ansi-cyan); }'), nl,
    write('  .fg-white { color: var(--ansi-white); }'), nl,
    write('  .fg-bright-black { color: var(--ansi-bright-black); }'), nl,
    write('  .fg-bright-red { color: var(--ansi-bright-red); }'), nl,
    write('  .fg-bright-green { color: var(--ansi-bright-green); }'), nl,
    write('  .fg-bright-yellow { color: var(--ansi-bright-yellow); }'), nl,
    write('  .fg-bright-blue { color: var(--ansi-bright-blue); }'), nl,
    write('  .fg-bright-magenta { color: var(--ansi-bright-magenta); }'), nl,
    write('  .fg-bright-cyan { color: var(--ansi-bright-cyan); }'), nl,
    write('  .fg-bright-white { color: var(--ansi-bright-white); }'), nl,
    write('  .bg-black { background: var(--ansi-bg-black); }'), nl,
    write('  .bg-red { background: var(--ansi-bg-red); }'), nl,
    write('  .bg-green { background: var(--ansi-bg-green); }'), nl,
    write('  .bg-yellow { background: var(--ansi-bg-yellow); }'), nl,
    write('  .bg-blue { background: var(--ansi-bg-blue); }'), nl,
    write('  .bg-magenta { background: var(--ansi-bg-magenta); }'), nl,
    write('  .bg-cyan { background: var(--ansi-bg-cyan); }'), nl,
    write('  .bg-white { background: var(--ansi-bg-white); }'), nl,
    write('  .bg-bright-black { background: var(--ansi-bg-black); }'), nl,
    write('  .bg-bright-red { background: var(--ansi-bg-red); }'), nl,
    write('  .bg-bright-green { background: var(--ansi-bg-green); }'), nl,
    write('  .bg-bright-yellow { background: var(--ansi-bg-yellow); }'), nl,
    write('  .bg-bright-blue { background: var(--ansi-bg-blue); }'), nl,
    write('  .bg-bright-magenta { background: var(--ansi-bg-magenta); }'), nl,
    write('  .bg-bright-cyan { background: var(--ansi-bg-cyan); }'), nl,
    write('  .bg-bright-white { background: var(--ansi-bg-white); }'), nl,
    write('  .ansi-bold { font-weight: 700; }'), nl,
    write('  .ansi-dim { opacity: 0.6; }'), nl,
    write('  .ansi-italic { font-style: italic; }'), nl,
    write('  .ansi-underline { text-decoration: underline; }'), nl,
    write('  span[class*="bg-"] { border-radius: 4px; padding: 1px 6px; color: var(--bubble-text); }'), nl.


% -----------------------------------------------------------------------------
%  HTML emission - body elements
% -----------------------------------------------------------------------------

emit_title_row(Cat, Name, Ver, Label) :-
    write('<div class="header">'), nl,
    write('<div class="title-row">'), nl,
    format('<h1>~w/~w-~w &mdash; ~w</h1>~n', [Cat, Name, Ver, Label]),
    write('<button class="theme-btn" id="theme-btn" onclick="toggleTheme()">&#9790;</button>'), nl,
    write('</div>'), nl.


emit_nav_bar(Repo, Entry, _Cat, Name, ActiveType, Newer, Newest, Older, Oldest) :-
    write('<div class="nav-rows">'), nl,
    write('<div class="nav-bar">'), nl,
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">nav</span>'), nl,
    format('    <a class="nav-link" href="../index.html">~w</a>~n', [Repo]),
    format('    <a class="nav-link" href="./~w.html">~w</a>~n', [Name, Name]),
    write('  </div>'), nl,
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">version</span>'), nl,
    emit_version_link(Newest, '&laquo;', ActiveType),
    emit_version_link(Newer,  '&lsaquo;',  ActiveType),
    emit_version_link(Older,  '&rsaquo;',   ActiveType),
    emit_version_link(Oldest, '&raquo;',   ActiveType),
    write('  </div>'), nl,
    write('</div>'), nl,
    write('<div class="nav-bar">'), nl,
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">graphs</span>'), nl,
    emit_graph_link(Entry, detail, ActiveType),
    emit_graph_link(Entry, deptree, ActiveType),
    emit_graph_link(Entry, gantt, ActiveType),
    write('  </div>'), nl,
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">cli</span>'), nl,
    emit_cli_link(Entry, merge, ActiveType),
    emit_cli_link(Entry, fetchonly, ActiveType),
    emit_cli_link(Entry, info, ActiveType),
    write('  </div>'), nl,
    write('  <div class="nav-group">'), nl,
    write('    <span class="nav-group-label">legacy</span>'), nl,
    emit_cli_link(Entry, emerge, ActiveType),
    write('  </div>'), nl,
    write('</div>'), nl,
    write('</div>'), nl,
    write('</div>'), nl.


emit_graph_link(Entry, Type, _Active) :-
    format('    <a class="nav-link" href="../~w-~w.html">~w</a>~n', [Entry, Type, Type]).

emit_cli_link(Entry, Type, Active) :-
    cli_flag(Type, Flag),
    (   Type == Active
    ->  format('    <a class="nav-link active">~w</a>~n', [Flag])
    ;   format('    <a class="nav-link" href="../~w-~w.html">~w</a>~n', [Entry, Type, Flag])
    ).

cli_flag(merge, '--merge').
cli_flag(fetchonly, '--fetchonly').
cli_flag(info, '--info').
cli_flag(emerge, 'emerge').


emit_version_link('', Label, _) :-
    !,
    format('    <a class="nav-link disabled">~w</a>~n', [Label]).
emit_version_link(Entry, Label, Type) :-
    format('    <a class="nav-link" href="../~w-~w.html" title="~w">~w</a>~n',
           [Entry, Type, Entry, Label]).


emit_content(HtmlContent) :-
    write('<div class="content">'), nl,
    write('<pre class="terminal">'),
    write(HtmlContent),
    write('</pre>'), nl,
    write('</div>'), nl,
    emit_theme_script.


emit_theme_script :-
    write('<script>'), nl,
    write('function toggleTheme() {'), nl,
    write('  const html = document.documentElement;'), nl,
    write('  const cur = html.getAttribute("data-theme") || "dark";'), nl,
    write('  const next = cur === "dark" ? "light" : "dark";'), nl,
    write('  html.setAttribute("data-theme", next);'), nl,
    write('  document.getElementById("theme-btn").innerHTML = next === "light" ? "&#9788;" : "&#9790;";'), nl,
    write('  localStorage.setItem("terminal-theme", next);'), nl,
    write('}'), nl,
    write('(function() {'), nl,
    write('  const saved = localStorage.getItem("terminal-theme");'), nl,
    write('  if (saved) {'), nl,
    write('    document.documentElement.setAttribute("data-theme", saved);'), nl,
    write('    document.getElementById("theme-btn").innerHTML = saved === "light" ? "&#9788;" : "&#9790;";'), nl,
    write('  }'), nl,
    write('})();'), nl,
    write('</script>'), nl.
