/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> MISSING_PROVIDER
Missing-provider diagnosis exception (portage-ng#102).

When a build phase dies because a required provider is missing -- a
command that is not on PATH, a header/library/pkg-config module that is
not installed -- the fault is almost always an *undeclared* build
dependency in the ebuild/eclass (e.g. selinux-policy-2.eclass never lists
sys-apps/semodule-utils in BDEPEND, so `semodule_package: command not
found` aborts the compile). Unlike the ABI-repair mechanisms (ghcabi #93,
ocamlabi #99, collision #90) this one never repairs in place: it does NOT
call fixup:repair_rebuild/4 and it threads the phase's exit code through
unchanged (the phase legitimately still failed). Instead it turns the
failure into learned knowledge and lets the pipeline re-derive a plan.

The diagnosis is split into two pluggable layers so new failure shapes and
resolution strategies are added as clauses, never by editing the
dispatcher:

  - detector registry (missing_provider:detector/3): normalizes a failed
    phase's log tail into a symbol(Kind, Name) plus the evidence line.
    Ships command / header / library / pkg-config / python / perl
    detectors.
  - resolver chain (missing_provider:provider_of/4): maps a symbol to a
    concrete Category/Name package. Tries the authoritative VDB CONTENTS
    reverse-owner index first (installed packages), then a small curated
    seed table (for providers that are not installed -- the common case,
    since a missing provider was by definition never pulled in). No
    concrete, in-tree match => the symbol is recorded to an unresolved
    backlog and the target fails cleanly (no guessing).

A concrete discovery is recorded via feedback:record_discovery/4 (durable,
unioned into BDEPEND on the next proof) and fixup:record/3 (so it surfaces
in the build summary). Declared-but-unbuilt providers (a real resolver/
ordering bug) are logged loudly and never minted as a discovery.

Registered with the generic fixup registry (Source/Domain/Gentoo/
Exceptions/fixup.pl); the builder and printer stay generic.
*/

:- module(missing_provider, []).

% =============================================================================
%  MISSING_PROVIDER declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.
:- multifile fixup:phase_retry_hook/10.

:- multifile missing_provider:detector/3.
:- multifile missing_provider:provider_of/4.
:- multifile missing_provider:provides/3.

fixup:mechanism(missing_provider).


% -----------------------------------------------------------------------------
%  Gate
% -----------------------------------------------------------------------------

%! missing_provider:enabled is semidet.
%
% True when `missing_provider` is listed in config:build_learned/1.
% A missing list leaves the strategy enabled.

missing_provider:enabled :-
  ( catch(config:build_learned(Strategies), _, fail), is_list(Strategies)
  -> memberchk(missing_provider, Strategies)
  ;  true
  ).


%! missing_provider:retry_phase(+Phase) is semidet.
%
% Build phases in which a missing provider can surface. The mechanism
% never re-runs the phase; this only limits log scanning to the phases
% where a command/header/library is actually invoked.

missing_provider:retry_phase(prepare).
missing_provider:retry_phase(configure).
missing_provider:retry_phase(compile).
missing_provider:retry_phase(install).
missing_provider:retry_phase(test).


% -----------------------------------------------------------------------------
%  Per-phase retry hook (diagnose, never repair)
% -----------------------------------------------------------------------------

%! fixup:phase_retry_hook(+missing_provider, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.
%
% On a non-zero exit of a build phase, scans the log segment the phase
% appended for a missing-provider signature and records a discovery (or an
% unresolved diagnostic). Always passes ExitCode0 through unchanged -- the
% phase is never re-run here; the builder's replan loop re-derives the plan
% with the discovered provider ordered before the target.

fixup:phase_retry_hook(missing_provider, _EbuildPath, Entry, Phase, LogPath, _UseString, _Callback, SizeBefore, ExitCode0, ExitCode0) :-
  ( missing_provider:enabled,
    ExitCode0 =\= 0,
    missing_provider:retry_phase(Phase),
    fixup:tree_entry(Entry, Repo, _C, _N),
    fixup:scan_log(LogPath, SizeBefore, Lines),
    Lines \== []
  -> once(missing_provider:process_detections(Lines, Repo, Entry, Phase, ExitCode0))
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Detection dispatch
% -----------------------------------------------------------------------------

%! missing_provider:process_detections(+Lines, +Repo, +Entry, +Phase, +ExitCode) is det.
%
% Runs every registered detector over the log lines, deduplicates the
% resulting symbols, and handles each (resolve+record or backlog).

missing_provider:process_detections(Lines, Repo, Entry, Phase, ExitCode) :-
  findall(Symbol-Line,
          missing_provider:detector(Lines, Symbol, Line),
          Pairs0),
  fixup:dedup_first(Pairs0, Pairs),
  forall(member(Symbol-Line, Pairs),
         missing_provider:handle_symbol(Symbol, Line, Repo, Entry, Phase, ExitCode)).


%! missing_provider:handle_symbol(+Symbol, +Line, +Repo, +Entry, +Phase, +ExitCode) is det.
%
% Resolves a symbol to a concrete in-tree package and records a discovery,
% distinguishing an undeclared dep (mint discovery) from a declared-but-
% unbuilt one (log loudly, no discovery). Unresolvable symbols are added
% to the backlog.

missing_provider:handle_symbol(symbol(Kind, Name), Line, Repo, Entry, Phase, ExitCode) :-
  ( missing_provider:provider_of(Kind, Name, Package, Confidence),
    missing_provider:package_in_tree(Package)
  -> ( missing_provider:already_declared(Repo, Entry, Package)
     -> missing_provider:log_declared_but_unbuilt(Entry, Package, symbol(Kind, Name))
     ;  Evidence = evidence(symbol(Kind, Name),
                            phase(Phase),
                            exit(ExitCode),
                            resolver(Confidence),
                            log(Line)),
        feedback:record_discovery(Repo://Entry, Package, bdepend, Evidence),
        fixup:record(missing_provider, Entry, discovered(Package)),
        missing_provider:log_discovery(Entry, Package, symbol(Kind, Name))
     )
  ;  feedback:record_unresolved(symbol(Kind, Name),
                                evidence(symbol(Kind, Name), phase(Phase), exit(ExitCode), log(Line)))
  ).


%! missing_provider:package_in_tree(+Package) is semidet.
%
% True when the Category/Name atom names a package present in a tree
% repository (concrete mapping only -- never records a phantom provider).

missing_provider:package_in_tree(Package) :-
  atom(Package),
  atomic_list_concat([C, N], '/', Package),
  cache:ordered_entry(Repo, _Id, C, N, _),
  Repo \== pkg,
  !.


%! missing_provider:already_declared(+Repo, +Entry, +Package) is semidet.
%
% True when Package (Category/Name) already appears in the target's
% declared dependency metadata -- meaning the provider WAS declared but
% not built (a resolver/ordering bug), not an undeclared upstream gap.

missing_provider:already_declared(Repo, Entry, Package) :-
  atomic_list_concat([C, N], '/', Package),
  member(Key, [bdepend, depend, cdepend, idepend, rdepend]),
  cache:entry_metadata(Repo, Entry, Key, Dep),
  missing_provider:dep_mentions(Dep, C, N),
  !.


%! missing_provider:dep_mentions(+Dep, +C, +N) is semidet.
%
% True when a parsed dependency term (possibly a nested group) contains a
% package_dependency on Category C / Name N.

missing_provider:dep_mentions(package_dependency(_, _, C, N, _, _, _, _), C, N) :- !.
missing_provider:dep_mentions(use_conditional_group(_, _, _, Deps), C, N) :- !,
  member(D, Deps), missing_provider:dep_mentions(D, C, N).
missing_provider:dep_mentions(any_of_group(Deps), C, N) :- !,
  member(D, Deps), missing_provider:dep_mentions(D, C, N).
missing_provider:dep_mentions(all_of_group(Deps), C, N) :- !,
  member(D, Deps), missing_provider:dep_mentions(D, C, N).
missing_provider:dep_mentions(exactly_one_of_group(Deps), C, N) :- !,
  member(D, Deps), missing_provider:dep_mentions(D, C, N).
missing_provider:dep_mentions(at_most_one_of_group(Deps), C, N) :- !,
  member(D, Deps), missing_provider:dep_mentions(D, C, N).
missing_provider:dep_mentions(List, C, N) :-
  is_list(List),
  member(D, List),
  missing_provider:dep_mentions(D, C, N).


% -----------------------------------------------------------------------------
%  Logging (build log markers)
% -----------------------------------------------------------------------------

%! missing_provider:log_discovery(+Entry, +Package, +Symbol) is det.

missing_provider:log_discovery(Entry, Package, symbol(Kind, Name)) :-
  message:color(yellow),
  format('>>> missing provider: ~w needs ~w (~w ~w); recorded as learned BDEPEND, re-deriving plan (#102)~n',
         [Entry, Package, Kind, Name]),
  message:color(normal).


%! missing_provider:log_declared_but_unbuilt(+Entry, +Package, +Symbol) is det.

missing_provider:log_declared_but_unbuilt(Entry, Package, symbol(Kind, Name)) :-
  message:color(red),
  format('!!! ~w failed on missing ~w ~w, but ~w IS a declared dependency -- resolver ordering bug, not an undeclared dep (#102)~n',
         [Entry, Kind, Name, Package]),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Detector registry
% -----------------------------------------------------------------------------
%
% Each detector is nondet: missing_provider:detector(+Lines, -Symbol,
% -EvidenceLine). Add a clause (or a whole file) to teach a new failure
% signature; the dispatcher never changes.

%! missing_provider:detector(+Lines, -Symbol, -Line) is nondet.

% Command not found -- bash: "cmd: command not found".
missing_provider:detector(Lines, symbol(command, Cmd), Line) :-
  member(Line, Lines),
  missing_provider:extract_before(Line, ": command not found", CmdS),
  missing_provider:command_token(CmdS, Cmd).

% Command not found -- dash/busybox: "sh: 1: cmd: not found".
missing_provider:detector(Lines, symbol(command, Cmd), Line) :-
  member(Line, Lines),
  \+ sub_string(Line, _, _, _, "command not found"),
  missing_provider:extract_before(Line, ": not found", CmdS),
  missing_provider:command_token(CmdS, Cmd).

% Command not found -- env exec: "env: 'cmd': No such file or directory".
missing_provider:detector(Lines, symbol(command, Cmd), Line) :-
  member(Line, Lines),
  missing_provider:extract_between(Line, "env: '", "'", CmdS),
  missing_provider:command_token(CmdS, Cmd).

% Missing header -- gcc/clang: "fatal error: foo/bar.h: No such file or directory".
missing_provider:detector(Lines, symbol(header, Header), Line) :-
  member(Line, Lines),
  ( missing_provider:extract_between(Line, "fatal error: ", ":", HdrS)
  ; missing_provider:extract_between(Line, "error: ", ": No such file", HdrS)
  ),
  missing_provider:header_token(HdrS, Header).

% Missing library at link -- ld: "cannot find -lfoo".
missing_provider:detector(Lines, symbol(lib, Lib), Line) :-
  member(Line, Lines),
  missing_provider:extract_after(Line, "cannot find -l", Rest),
  missing_provider:word_token(Rest, Lib).

% Missing shared object -- "libfoo.so: cannot open shared object file".
missing_provider:detector(Lines, symbol(soname, SoName), Line) :-
  member(Line, Lines),
  missing_provider:extract_before(Line, ": cannot open shared object", SoS),
  missing_provider:basename_token(SoS, SoName),
  sub_atom(SoName, _, _, _, '.so').

% Missing pkg-config module -- "Package foo was not found in the pkg-config search path".
missing_provider:detector(Lines, symbol(pkgconfig, Pkg), Line) :-
  member(Line, Lines),
  missing_provider:extract_between(Line, "Package ", " was not found in the pkg-config", PkgS),
  missing_provider:word_token(PkgS, Pkg).

% Missing pkg-config module -- "No package 'foo' found".
missing_provider:detector(Lines, symbol(pkgconfig, Pkg), Line) :-
  member(Line, Lines),
  missing_provider:extract_between(Line, "No package '", "' found", PkgS),
  missing_provider:word_token(PkgS, Pkg).

% Missing python module -- "ModuleNotFoundError: No module named 'foo'".
missing_provider:detector(Lines, symbol(python_module, Mod), Line) :-
  member(Line, Lines),
  missing_provider:extract_between(Line, "No module named '", "'", ModS),
  missing_provider:word_token(ModS, Mod).

% Missing perl module -- "Can't locate Foo/Bar.pm in @INC".
missing_provider:detector(Lines, symbol(perl_module, Mod), Line) :-
  member(Line, Lines),
  missing_provider:extract_between(Line, "Can't locate ", " in @INC", ModS),
  missing_provider:word_token(ModS, Mod).


% -----------------------------------------------------------------------------
%  Token extraction helpers
% -----------------------------------------------------------------------------

%! missing_provider:extract_before(+Line, +Marker, -Field) is semidet.
%
% Field is the last colon-separated, space-trimmed field of the text
% preceding Marker in Line.

missing_provider:extract_before(Line, Marker, Field) :-
  sub_string(Line, Before, _, _, Marker),
  sub_string(Line, 0, Before, _, Prefix),
  split_string(Prefix, ":", " \t", Fields),
  exclude(==(""), Fields, NonEmpty),
  NonEmpty \== [],
  last(NonEmpty, Field),
  Field \== "".


%! missing_provider:extract_after(+Line, +Marker, -Rest) is semidet.
%
% Rest is the text immediately following Marker in Line.

missing_provider:extract_after(Line, Marker, Rest) :-
  sub_string(Line, _, _, After, Marker),
  sub_string(Line, _, After, 0, Rest).


%! missing_provider:extract_between(+Line, +Open, +Close, -Inner) is semidet.
%
% Inner is the text between the first Open and the next Close after it.

missing_provider:extract_between(Line, Open, Close, Inner) :-
  sub_string(Line, _, _, After, Open),
  sub_string(Line, _, After, 0, Rest),
  sub_string(Rest, B, _, _, Close),
  sub_string(Rest, 0, B, _, Inner),
  Inner \== "".


%! missing_provider:command_token(+Str, -Cmd) is semidet.
%
% Accepts a plausible command name: a single token (no spaces, no slash)
% of length > 1 made of command-name characters. Rejects sentences and
% absolute paths so ordinary log prose never mints a command symbol.

missing_provider:command_token(Str, Cmd) :-
  string_length(Str, L),
  L > 1,
  \+ sub_string(Str, _, _, _, " "),
  \+ sub_string(Str, _, _, _, "/"),
  missing_provider:name_string(Str),
  atom_string(Cmd, Str).


%! missing_provider:word_token(+Str, -Word) is semidet.
%
% Accepts a single space-free token (module/lib/pkg-config name).

missing_provider:word_token(Str0, Word) :-
  split_string(Str0, " \t", " \t", [Str|_]),
  string_length(Str, L),
  L > 0,
  \+ sub_string(Str, _, _, _, " "),
  atom_string(Word, Str).


%! missing_provider:header_token(+Str, -Header) is semidet.
%
% Accepts a header path ending in .h / .hpp / .hh.

missing_provider:header_token(Str0, Header) :-
  split_string(Str0, " \t", " \t", [Str|_]),
  ( sub_string(Str, _, _, 0, ".h")
  ; sub_string(Str, _, _, 0, ".hpp")
  ; sub_string(Str, _, _, 0, ".hh")
  ),
  atom_string(Header, Str).


%! missing_provider:basename_token(+Str, -Base) is semidet.
%
% Last whitespace-and-slash-delimited token of Str (a file basename).

missing_provider:basename_token(Str0, Base) :-
  split_string(Str0, " \t", " \t", Toks),
  exclude(==(""), Toks, NonEmpty),
  NonEmpty \== [],
  last(NonEmpty, Tok),
  ( sub_string(Tok, _, _, _, "/")
  -> file_base_name(Tok, BaseS)
  ;  BaseS = Tok
  ),
  atom_string(Base, BaseS).


%! missing_provider:name_string(+Str) is semidet.
%
% True when every character of Str is a command-name character
% (alphanumeric, or one of _ - . +).

missing_provider:name_string(Str) :-
  string_chars(Str, Chars),
  forall(member(Ch, Chars), missing_provider:name_char(Ch)).

missing_provider:name_char(Ch) :- char_type(Ch, alnum), !.
missing_provider:name_char('_').
missing_provider:name_char('-').
missing_provider:name_char('.').
missing_provider:name_char('+').


% -----------------------------------------------------------------------------
%  Resolver chain (symbol -> concrete package)
% -----------------------------------------------------------------------------
%
% missing_provider:provider_of(+Kind, +Name, -Package, -Confidence). Tried
% in clause order: the VDB CONTENTS reverse-owner index first (authoritative
% for installed providers), then the curated seed table (for providers not
% installed -- the common missing-provider case).

%! missing_provider:provider_of(+Kind, +Name, -Package, -Confidence) is nondet.

% Command owned by an installed package (qfile / equery-belongs equivalent).
missing_provider:provider_of(command, Name, Package, vdb_index) :-
  missing_provider:vdb_owner_package(Name, Package).

% Header / pkg-config module / soname owned by an installed package.
missing_provider:provider_of(header, Header, Package, vdb_index) :-
  file_base_name(Header, Base),
  missing_provider:vdb_owner_package(Base, Package).
missing_provider:provider_of(pkgconfig, Name, Package, vdb_index) :-
  atom_concat(Name, '.pc', Pc),
  missing_provider:vdb_owner_package(Pc, Package).
missing_provider:provider_of(soname, SoName, Package, vdb_index) :-
  missing_provider:vdb_owner_package(SoName, Package).
missing_provider:provider_of(lib, Lib, Package, vdb_index) :-
  atom_concat('lib', Lib, LibBase),
  ( atom_concat(LibBase, '.so', SoName)
  ; atom_concat(LibBase, '.a', SoName)
  ),
  missing_provider:vdb_owner_package(SoName, Package).

% Curated seed table (human-vetted; covers not-yet-installed providers).
missing_provider:provider_of(Kind, Name, Package, curated_seed) :-
  missing_provider:provides(Kind, Name, Package).


%! missing_provider:vdb_owner_package(+FileName, -Package) is semidet.
%
% Maps a file basename to the Category/Name of the installed package whose
% VDB CONTENTS records it. Deterministic: first owner wins.

missing_provider:vdb_owner_package(FileName, Package) :-
  vdb:find_owner(FileName, Owners),
  member(Entry-_Path, Owners),
  cache:ordered_entry(pkg, Entry, C, N, _),
  atomic_list_concat([C, N], '/', Package),
  !.


% -----------------------------------------------------------------------------
%  Curated seed table
% -----------------------------------------------------------------------------
%
% missing_provider:provides(+Kind, +Name, -Package). Multifile so hosts /
% future files can extend it. Kept small and conservative: each entry is a
% known-hard command whose provider is typically NOT installed when it is
% first needed (so the VDB index cannot find it).

%! missing_provider:provides(?Kind, ?Name, ?Package) is nondet.

missing_provider:provides(command, semodule_package, 'sys-apps/semodule-utils').
missing_provider:provides(command, semodule,         'sys-apps/policycoreutils').
missing_provider:provides(command, checkmodule,      'sys-apps/checkpolicy').
missing_provider:provides(command, msgfmt,           'sys-devel/gettext').
missing_provider:provides(command, msgmerge,         'sys-devel/gettext').
missing_provider:provides(command, xmlto,            'app-text/xmlto').
missing_provider:provides(command, gperf,            'dev-util/gperf').


% -----------------------------------------------------------------------------
%  Build summary note
% -----------------------------------------------------------------------------

%! fixup:mechanism_note(+missing_provider, +Count, -Lines) is semidet.

fixup:mechanism_note(missing_provider, N, [Line1, Line2]) :-
  fixup:packages_word(N, Word),
  format(atom(Line1), 'Missing provider: ~d ~w had an undeclared build dependency discovered at', [N, Word]),
  Line2 = '                  build time and learned as BDEPEND (portage-ng#102):'.
