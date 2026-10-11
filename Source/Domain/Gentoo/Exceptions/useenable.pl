/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> USEENABLE
Learn HARD USE enables from build failures (portage-ng#110).

When a build dies at configure/compile because a provider was built with
the wrong USE set -- e.g. `KX11Extras: No such file or directory` because
`kde-frameworks/kwindowsystem` was merged `-X` -- the gap is not an
undeclared package (#102) and not a plan-time use_dep_unsat (#109). The
provider CN is already in the plan/VDB; what is missing is a HARD
`[flag]` usedep.

Like missing_provider (#102) and kernelconfig (#105), this mechanism
never repairs in place and threads the phase's exit code through
unchanged. It records a `feedback:discovered_usedep/4` and lets the
builder re-derive a plan that forces the provider USE and rebuilds it.

Resolution is curated only (no guessing): a small seed table maps
compile/configure symbols to `Provider + HARD usedeps`. Unmapped
symbols go to the unresolved backlog.

Log scanning strips GCC/CMake ANSI CSI sequences before matching: colored
`fatal error: <CSI>KX11Extras:` lines otherwise extract a garbage token and
silently miss the seed (Cluster A false negatives on tinderbox-ng). CMake
`Could NOT find Foo` is recognized in addition to `fatal error` / `*_LIB
NOTFOUND`, so seeds like `KPim6PimCommonActivities` fire on real KF6 logs.

Registered with the generic fixup registry
(Source/Domain/Gentoo/Exceptions/fixup.pl).
*/

:- module(useenable, []).

% =============================================================================
%  USEENABLE declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.
:- multifile fixup:phase_retry_hook/10.

:- multifile useenable:detector/3.
:- multifile useenable:provides_usedep/4.

fixup:mechanism(useenable).


% -----------------------------------------------------------------------------
%  Gate
% -----------------------------------------------------------------------------

%! useenable:enabled is semidet.
%
% True when `useenable` is listed in config:build_learned/1.
% A missing list leaves the strategy enabled.

useenable:enabled :-
  ( catch(config:build_learned(Strategies), _, fail), is_list(Strategies)
  -> memberchk(useenable, Strategies)
  ;  true
  ).


%! useenable:retry_phase(+Phase) is semidet.
%
% Phases where a wrong-USE provider typically surfaces.

useenable:retry_phase(configure).
useenable:retry_phase(compile).
useenable:retry_phase(prepare).


% -----------------------------------------------------------------------------
%  Per-phase retry hook (diagnose, never repair)
% -----------------------------------------------------------------------------

%! fixup:phase_retry_hook(+useenable, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.
%
% On a non-zero exit, scans the phase log for USE-enable signatures and
% records discovered_usedep facts. Always passes ExitCode0 through; the
% builder replan loop re-derives the plan with HARD usedeps on the
% provider.

fixup:phase_retry_hook(useenable, _EbuildPath, Entry, Phase, LogPath, _UseString, _Callback, SizeBefore, ExitCode0, ExitCode0) :-
  ( useenable:enabled,
    ExitCode0 =\= 0,
    useenable:retry_phase(Phase),
    fixup:tree_entry(Entry, Repo, _C, _N),
    useenable:scan_log(LogPath, SizeBefore, Lines),
    Lines \== []
  -> once(useenable:process_detections(Lines, Repo, Entry, Phase, ExitCode0))
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Log scanning
% -----------------------------------------------------------------------------

%! useenable:scan_log(+LogPath, +SizeBefore, -Lines) is det.
%
% fixup:scan_log/3 with each line ANSI-stripped so GCC colorized
% diagnostics still match the header detectors.

useenable:scan_log(LogPath, SizeBefore, Lines) :-
  fixup:scan_log(LogPath, SizeBefore, RawLines),
  maplist(useenable:strip_ansi, RawLines, Lines).


%! useenable:strip_ansi(+In, -Out) is det.
%
% Remove ECMA-48 CSI sequences (`ESC [ … final`) from a log line. GCC's
% colored `fatal error:` diagnostics wrap the header token in SGR/`EL`
% sequences; without stripping, extract_bare_header/2 keeps the ESC bytes
% inside the token and kf_header_name/1 never matches.

useenable:strip_ansi(In, Out) :-
  ( string(In) -> Str = In
  ; atom(In)   -> atom_string(In, Str)
  ;               format(string(Str), '~w', [In])
  ),
  string_codes(Str, Codes),
  useenable:strip_ansi_codes(Codes, Clean),
  string_codes(Out, Clean).

useenable:strip_ansi_codes([], []).
useenable:strip_ansi_codes([0x1B, 0x5B|Rest], Out) :- !,
  useenable:drop_csi(Rest, Rest2),
  useenable:strip_ansi_codes(Rest2, Out).
useenable:strip_ansi_codes([0x1B|Rest], Out) :- !,
  useenable:drop_esc_residue(Rest, Rest2),
  useenable:strip_ansi_codes(Rest2, Out).
useenable:strip_ansi_codes([C|Rest], [C|Out]) :-
  useenable:strip_ansi_codes(Rest, Out).

% CSI parameter (0x30-3F) + intermediate (0x20-2F) bytes, then a final (0x40-7E).
useenable:drop_csi([C|Rest], Rest2) :-
  C >= 0x20, C =< 0x3F, !,
  useenable:drop_csi(Rest, Rest2).
useenable:drop_csi([C|Rest], Rest) :-
  C >= 0x40, C =< 0x7E, !.
useenable:drop_csi([], []).

useenable:drop_esc_residue([], []).
useenable:drop_esc_residue([C|Rest], Rest) :-
  C >= 0x40, C =< 0x7E, !.
useenable:drop_esc_residue([_|Rest], Rest2) :-
  useenable:drop_esc_residue(Rest, Rest2).


% -----------------------------------------------------------------------------
%  Detection dispatch
% -----------------------------------------------------------------------------

%! useenable:process_detections(+Lines, +Repo, +Entry, +Phase, +ExitCode) is det.
%
% Runs detectors, deduplicates symbols, records usedep discoveries.

useenable:process_detections(Lines, Repo, Entry, Phase, ExitCode) :-
  findall(Symbol-Line,
          useenable:detector(Lines, Symbol, Line),
          Pairs0),
  fixup:dedup_first(Pairs0, Pairs),
  forall(member(Symbol-Line, Pairs),
         useenable:handle_symbol(Symbol, Line, Repo, Entry, Phase, ExitCode)).


%! useenable:handle_symbol(+Symbol, +Line, +Repo, +Entry, +Phase, +ExitCode) is det.
%
% Resolve symbol via curated seed; record discovered_usedep when the
% target does not already declare the provider with those HARD usedeps.

useenable:handle_symbol(symbol(Kind, Name), Line, Repo, Entry, Phase, ExitCode) :-
  ( useenable:provides_usedep(Kind, Name, Provider, UseDeps),
    useenable:package_in_tree(Provider)
  -> ( useenable:already_has_usedep(Repo, Entry, Provider, UseDeps)
     -> useenable:log_already_declared(Entry, Provider, UseDeps, symbol(Kind, Name))
     ;  Evidence = evidence(symbol(Kind, Name),
                            phase(Phase),
                            exit(ExitCode),
                            resolver(curated_seed),
                            log(Line)),
        ( UseDeps == []
        -> feedback:record_discovery(Repo://Entry, Provider, bdepend, Evidence)
        ;  feedback:record_usedep(Repo://Entry, Provider, UseDeps, Evidence)
        ),
        fixup:record(useenable, Entry, discovered_usedep(Provider, UseDeps)),
        useenable:log_discovery(Entry, Provider, UseDeps, symbol(Kind, Name))
     )
  ;  feedback:record_unresolved(symbol(Kind, Name),
                                evidence(symbol(Kind, Name), phase(Phase), exit(ExitCode), log(Line)))
  ).


%! useenable:package_in_tree(+Package) is semidet.

useenable:package_in_tree(Package) :-
  atom(Package),
  atomic_list_concat([C, N], '/', Package),
  cache:ordered_entry(Repo, _Id, C, N, _),
  Repo \== pkg,
  !.


%! useenable:already_has_usedep(+Repo, +Entry, +Provider, +UseDeps) is semidet.
%
% True when Target already declares Provider with every HARD enable in
% UseDeps. A bare `cat/name` declaration (empty brackets) does NOT
% suppress a usedep discovery — that is the #110 no-op this mechanism
% exists to fix.

useenable:already_has_usedep(Repo, Entry, Provider, UseDeps) :-
  UseDeps \== [],
  atomic_list_concat([C, N], '/', Provider),
  member(Key, [bdepend, depend, cdepend, idepend, rdepend]),
  cache:entry_metadata(Repo, Entry, Key, Dep),
  useenable:dep_has_hard_usedeps(Dep, C, N, UseDeps),
  !.


%! useenable:dep_has_hard_usedeps(+Dep, +C, +N, +UseDeps) is semidet.

useenable:dep_has_hard_usedeps(package_dependency(_, _, C, N, _, _, _, U), C, N, UseDeps) :-
  !,
  forall(member(use(enable(Flag), _), UseDeps),
         memberchk(use(enable(Flag), _), U)).
useenable:dep_has_hard_usedeps(use_conditional_group(_, _, _, Deps), C, N, UseDeps) :- !,
  member(D, Deps), useenable:dep_has_hard_usedeps(D, C, N, UseDeps).
useenable:dep_has_hard_usedeps(any_of_group(Deps), C, N, UseDeps) :- !,
  member(D, Deps), useenable:dep_has_hard_usedeps(D, C, N, UseDeps).
useenable:dep_has_hard_usedeps(all_of_group(Deps), C, N, UseDeps) :- !,
  member(D, Deps), useenable:dep_has_hard_usedeps(D, C, N, UseDeps).
useenable:dep_has_hard_usedeps(exactly_one_of_group(Deps), C, N, UseDeps) :- !,
  member(D, Deps), useenable:dep_has_hard_usedeps(D, C, N, UseDeps).
useenable:dep_has_hard_usedeps(at_most_one_of_group(Deps), C, N, UseDeps) :- !,
  member(D, Deps), useenable:dep_has_hard_usedeps(D, C, N, UseDeps).
useenable:dep_has_hard_usedeps(List, C, N, UseDeps) :-
  is_list(List),
  member(D, List),
  useenable:dep_has_hard_usedeps(D, C, N, UseDeps).


% -----------------------------------------------------------------------------
%  Logging
% -----------------------------------------------------------------------------

%! useenable:log_discovery(+Entry, +Provider, +UseDeps, +Symbol) is det.

useenable:log_discovery(Entry, Provider, UseDeps, symbol(Kind, Name)) :-
  message:color(yellow),
  format('>>> useenable: ~w needs ~w~w (~w ~w); recorded as learned USEDEP, re-deriving plan (#110)~n',
         [Entry, Provider, UseDeps, Kind, Name]),
  message:color(normal).


%! useenable:log_already_declared(+Entry, +Provider, +UseDeps, +Symbol) is det.

useenable:log_already_declared(Entry, Provider, UseDeps, symbol(Kind, Name)) :-
  message:color(red),
  format('!!! ~w failed on ~w ~w, but ~w~w IS already declared -- resolver USE forcing gap (#110)~n',
         [Entry, Kind, Name, Provider, UseDeps]),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Detector registry
% -----------------------------------------------------------------------------

%! useenable:detector(+Lines, -Symbol, -Line) is nondet.
%
% Normalizes a failed phase log into symbol(Kind, Name) + evidence line.
% Input lines may still contain ANSI (unit tests / alternate callers); each
% candidate is stripped before matching. Evidence Line is the cleaned text.

useenable:detector(Lines, Symbol, Line) :-
  member(Raw, Lines),
  useenable:strip_ansi(Raw, Line),
  useenable:detect_line(Line, Symbol).


%! useenable:detect_line(+Line, -Symbol) is nondet.
%
% Match a single already-stripped log line.

% KF6/Qt class header missing because provider USE is off:
%   fatal error: KX11Extras: No such file or directory
useenable:detect_line(Line, symbol(kf_header, Name)) :-
  sub_string(Line, _, _, _, "No such file"),
  useenable:extract_bare_header(Line, Name),
  useenable:kf_header_name(Name).

% CMake find_package style (KF6 config packages):
%   -- Could NOT find KPim6PimCommonActivities (missing: …_DIR)
useenable:detect_line(Line, symbol(kf_header, Name)) :-
  sub_string(Line, _, _, _, "Could NOT find"),
  useenable:extract_could_not_find(Line, Name),
  useenable:kf_header_name(Name).

% CMake find_library style:
%   X11_Xdamage_LIB NOTFOUND
useenable:detect_line(Line, symbol(cmake_lib, Name)) :-
  sub_string(Line, _, _, _, "NOTFOUND"),
  useenable:extract_cmake_lib(Line, Name).


%! useenable:extract_bare_header(+Line, -Name) is semidet.
%
% Pulls a header/class token that is NOT a path ending in .h/.hpp/.hh
% (those are handled by missing_provider).

useenable:extract_bare_header(Line, Name) :-
  ( useenable:extract_between(Line, "fatal error: ", ":", Tok)
  ; useenable:extract_between(Line, "error: ", ": No such file", Tok)
  ),
  atom_string(Name0, Tok),
  normalize_space(atom(Name), Name0),
  Name \== '',
  \+ sub_atom(Name, _, _, 0, '.h'),
  \+ sub_atom(Name, _, _, 0, '.hpp'),
  \+ sub_atom(Name, _, _, 0, '.hh'),
  \+ sub_atom(Name, _, _, _, '/').


%! useenable:extract_could_not_find(+Line, -Name) is semidet.
%
% Pulls the package/component token from a CMake
% `Could NOT find <Name> (missing: …)` diagnostic.

useenable:extract_could_not_find(Line, Name) :-
  ( useenable:extract_between(Line, "Could NOT find ", " (", Tok)
  ; useenable:extract_between(Line, "Could NOT find ", " ", Tok)
  ),
  atom_string(Name0, Tok),
  normalize_space(atom(Name), Name0),
  Name \== '',
  \+ sub_atom(Name, _, _, _, '/').


%! useenable:extract_cmake_lib(+Line, -Name) is semidet.

useenable:extract_cmake_lib(Line, Name) :-
  split_string(Line, " \t", " \t", Parts),
  member(Part, Parts),
  atom_string(Atom, Part),
  atom_concat(Name, '_LIB', Atom),
  Name \== ''.


%! useenable:extract_between(+Line, +Open, +Close, -Inner) is semidet.

useenable:extract_between(Line, Open, Close, Inner) :-
  sub_string(Line, _, _, After, Open),
  sub_string(Line, _, After, 0, Rest),
  sub_string(Rest, B, _, _, Close),
  sub_string(Rest, 0, B, _, Inner),
  Inner \== "".


%! useenable:kf_header_name(+Name) is semidet.
%
% Restricts bare-header detectors to the curated KDE/Qt names we seed.

useenable:kf_header_name('KX11Extras').
useenable:kf_header_name('KStartupInfo').
useenable:kf_header_name('KPim6PimCommonActivities').


% -----------------------------------------------------------------------------
%  Curated seed: symbol -> Provider + HARD usedeps
% -----------------------------------------------------------------------------

%! useenable:provides_usedep(+Kind, +Name, -Provider, -UseDeps) is semidet.
%
% Curated mapping only. UseDeps is a list of use(enable(Flag), none)
% terms matching eapi bracket parse of `[flag]`.

useenable:provides_usedep(kf_header, 'KX11Extras',
                          'kde-frameworks/kwindowsystem',
                          [use(enable('X'), none)]).
useenable:provides_usedep(kf_header, 'KStartupInfo',
                          'kde-frameworks/kwindowsystem',
                          [use(enable('X'), none)]).
useenable:provides_usedep(kf_header, 'KPim6PimCommonActivities',
                          'kde-apps/pimcommon',
                          [use(enable(activities), none)]).
useenable:provides_usedep(cmake_lib, 'X11_Xdamage',
                          'x11-libs/libXdamage',
                          []).


% -----------------------------------------------------------------------------
%  Build-summary note
% -----------------------------------------------------------------------------

%! fixup:mechanism_note(+useenable, +Count, -Lines) is semidet.

fixup:mechanism_note(useenable, N, [Line1, Line2]) :-
  fixup:packages_word(N, Word),
  format(atom(Line1), 'USE-enable feedback: ~d ~w needed a provider rebuilt with additional', [N, Word]),
  Line2 = '                    USE flags learned at build time (portage-ng#110):'.
