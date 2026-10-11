/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> OCAMLABI
OCaml/findlib ABI repair exception (portage-ng#99).

OCaml has the same problem GHC has (portage-ng#93): package identity lives
in the compiled interface digests (.cmi CRCs) checked by the compiler and
in findlib's registry, NOT in the ebuild sub-slot. When an OCaml library
(or dev-lang/ocaml itself) is rebuilt, installed consumers keep carrying
compiled units referencing the old digests, and the next OCaml consumer's
configure/compile fails. Unlike Haskell there is no single eclass-driven
die line enumerating the broken packages; the failure surfaces as
heterogeneous compiler/ocamlfind messages:

  Error: The files /usr/lib64/ocaml/site-lib/res/res.cmi
         and /usr/lib64/ocaml/stdlib.cmi
         make inconsistent assumptions over interface Stdlib
  Error: Unbound module Camlp5
  ocamlfind: Package `camlp5' not found
  /usr/lib64/ocaml/site-lib/foo/foo.cmi is not a compiled interface

The sub-slot rebuild pass (portage-ng#89) cannot see this breakage (no
sub-slot delta), and traditional emerge simply fails the build. When
`ocamlabi` is listed in config:build_fixup/1, this mechanism recovers the failure
in-transaction: it extracts the stale compiled-unit file paths and findlib
package names from the failed phase's log segment, maps them to their
installed VDB owners through the CONTENTS records (the active enumerator
this domain lacks an eclass check for), rebuilds each owner from source at
its installed version, and re-runs the failed phase. Cascading breakage is
handled by one additional bounded round. Each package is rebuilt at most
once per session (ocamlabi:repair_applied_/2) so the mechanism can never
loop; repairs are serialized under a dedicated mutex; the package being
built and dev-lang/ocaml itself are never rebuild candidates.

Registered with the generic fixup registry (Source/Domain/Gentoo/
Exceptions/fixup.pl); the builder and printer have no knowledge of this
mechanism.
*/

:- module(ocamlabi, []).

% =============================================================================
%  OCAMLABI declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.
:- multifile fixup:phase_retry_hook/10.

:- dynamic ocamlabi:repair_applied_/2.

:- mutex_create(ocaml_abi_repair).

fixup:mechanism(ocamlabi).


% -----------------------------------------------------------------------------
%  Gate
% -----------------------------------------------------------------------------

%! ocamlabi:repair_enabled is semidet.

ocamlabi:repair_enabled :-
  ( catch(config:build_fixup(Strategies), _, fail), is_list(Strategies)
  -> memberchk(ocamlabi, Strategies)
  ;  true
  ).


%! ocamlabi:retry_phase(+Phase) is semidet.
%
% Phases in which stale OCaml compiled units surface: ocamlfind package
% checks run at configure time, digest mismatches abort the compile.

ocamlabi:retry_phase(configure).
ocamlabi:retry_phase(compile).


% -----------------------------------------------------------------------------
%  Failure signature
% -----------------------------------------------------------------------------

%! ocamlabi:phase_error(+LogPath, +SizeBefore, -Tail) is semidet.
%
% True when the log segment the failed phase wrote (fixup:log_tail/3)
% carries an OCaml stale-ABI signature. Tail is the examined log segment,
% kept for stale-unit extraction. All four signatures are OCaml-specific
% compiler/ocamlfind output, so a non-OCaml build can never match.

ocamlabi:phase_error(LogPath, SizeBefore, Tail) :-
  fixup:log_tail(LogPath, SizeBefore, Tail),
  ( sub_string(Tail, _, _, _, "make inconsistent assumptions over inter")
  ; sub_string(Tail, _, _, _, "is not a compiled interface")
  ; sub_string(Tail, _, _, _, "Error: Unbound module")
  ; sub_string(Tail, _, _, _, "ocamlfind: Package")
  ),
  !.


% -----------------------------------------------------------------------------
%  Stale-unit extraction
% -----------------------------------------------------------------------------

%! ocamlabi:stale_units(+Tail, -Paths, -Names) is det.
%
% Extracts the stale-unit evidence from the failed phase's log segment:
% Paths are absolute compiled-unit file paths (.cmi/.cmo/.cma/.cmx/.cmxa/
% .cmxs) taken from the error lines of digest-mismatch and broken-interface
% messages; Names are findlib package names from ocamlfind not-found
% errors plus lowercased module names from Unbound-module errors (the
% conventional findlib layout maps module Foo to site-lib/foo). Both lists
% are deduplicated.

ocamlabi:stale_units(Tail, Paths, Names) :-
  split_string(Tail, "\n", "\r", Lines),
  findall(P,
    ( member(Line, Lines),
      ocamlabi:error_context_line(Line),
      ocamlabi:line_cm_path(Line, P)
    ),
    Paths0),
  sort(Paths0, Paths),
  findall(N,
    ( member(Line, Lines),
      ocamlabi:line_findlib_name(Line, N)
    ),
    Names0),
  sort(Names0, Names).


%! ocamlabi:error_context_line(+Line) is semidet.
%
% True when Line belongs to an OCaml error message that carries stale
% compiled-unit paths. The inconsistent-assumptions message spans lines
% ("Error: The files X / and Y / make inconsistent assumptions..."), so
% both the Error: header lines and the "and"-continuation are matched;
% ordinary compile command lines (which may also mention .cm* files)
% never are.

ocamlabi:error_context_line(Line) :-
  ( sub_string(Line, _, _, _, "Error: The files")
  ; sub_string(Line, _, _, _, "Error: Files")
  ; sub_string(Line, _, _, _, "make inconsistent assumptions")
  ; sub_string(Line, _, _, _, "is not a compiled interface")
  ; ( split_string(Line, " \t", " \t", [First|_]),
      memberchk(First, ["and"]) )
  ),
  !.


%! ocamlabi:line_cm_path(+Line, -Path) is nondet.
%
% Yields each absolute compiled-unit path mentioned on Line, stripped of
% surrounding quote/backtick/comma decorations.

ocamlabi:line_cm_path(Line, Path) :-
  split_string(Line, " \t", " \t", Tokens),
  member(Token0, Tokens),
  ocamlabi:strip_decorations(Token0, Token),
  string_concat("/", _, Token),
  ocamlabi:cm_extension(Ext),
  string_concat(_, Ext, Token),
  atom_string(Path, Token).


%! ocamlabi:cm_extension(-Ext) is nondet.

ocamlabi:cm_extension(".cmi").
ocamlabi:cm_extension(".cmo").
ocamlabi:cm_extension(".cma").
ocamlabi:cm_extension(".cmx").
ocamlabi:cm_extension(".cmxa").
ocamlabi:cm_extension(".cmxs").


%! ocamlabi:line_findlib_name(+Line, -Name) is nondet.
%
% Yields the findlib package name from an ocamlfind not-found error, or
% the lowercased module name from an Unbound-module error.

ocamlabi:line_findlib_name(Line, Name) :-
  sub_string(Line, B, _, _, "ocamlfind: Package `"),
  Skip is B + 20,
  sub_string(Line, Skip, _, 0, Rest),
  sub_string(Rest, NB, 1, _, "'"),
  sub_string(Rest, 0, NB, _, NameS),
  NameS \== "",
  atom_string(Name, NameS),
  !.

ocamlabi:line_findlib_name(Line, Name) :-
  sub_string(Line, B, _, _, "Error: Unbound module "),
  Skip is B + 22,
  sub_string(Line, Skip, _, 0, Rest),
  split_string(Rest, " \t", " \t.,", [ModS|_]),
  ModS \== "",
  string_lower(ModS, LowS),
  atom_string(Name, LowS),
  !.


%! ocamlabi:strip_decorations(+Token0, -Token) is det.
%
% Strips quote, backtick, comma and parenthesis decorations the compiler
% wraps around file names in its error output.

ocamlabi:strip_decorations(Token0, Token) :-
  split_string(Token0, "", "\"'`,()", [Token]).


% -----------------------------------------------------------------------------
%  Stale-unit to installed-owner mapping
% -----------------------------------------------------------------------------

%! ocamlabi:stale_owners(+Paths, +Names, +SelfEntry, -Owners) is det.
%
% Maps the stale-unit evidence to installed VDB owners in a single pass
% over the CONTENTS records: an installed entry is an owner when it
% records one of the stale file Paths, or a directory ending in
% `site-lib/<Name>` for one of the findlib Names. The package being
% built (SelfEntry -- its own fresh units also appear in the error
% message) and dev-lang/ocaml (the compiler is never the stale side worth
% a repair rebuild) are excluded.

ocamlabi:stale_owners(Paths, Names, SelfEntry, Owners) :-
  findall(Suffix,
    ( member(N, Names),
      format(atom(Suffix), '/site-lib/~w', [N])
    ),
    Suffixes),
  findall(Entry,
    ( vdb:installed_entry(Entry),
      Entry \== SelfEntry,
      \+ ocamlabi:compiler_entry(Entry),
      once(( vdb:read_contents(Entry, Contents),
             member(Item, Contents),
             vdb:contents_item_path(Item, P),
             ocamlabi:path_is_stale(P, Paths, Suffixes) ))
    ),
    Owners0),
  sort(Owners0, Owners).


%! ocamlabi:compiler_entry(+Entry) is semidet.

ocamlabi:compiler_entry(Entry) :-
  cache:ordered_entry(pkg, Entry, 'dev-lang', ocaml, _),
  !.


%! ocamlabi:path_is_stale(+Path, +Paths, +Suffixes) is semidet.

ocamlabi:path_is_stale(Path, Paths, _) :-
  memberchk(Path, Paths),
  !.

ocamlabi:path_is_stale(Path, _, Suffixes) :-
  member(Suffix, Suffixes),
  sub_atom(Path, _, _, 0, Suffix),
  !.


% -----------------------------------------------------------------------------
%  Repair rebuild
% -----------------------------------------------------------------------------

%! ocamlabi:repair_owners(+Owners, -RepairedCount) is det.
%
% Rebuilds every stale owner not already repaired this session, under the
% ocaml_abi_repair mutex. Owners whose rebuild fails on the first pass get
% one more attempt after the others (the extraction yields registry order,
% not dependency order, so an inter-stale dependency can make the first
% pass fail). RepairedCount is the number of successful rebuilds in this
% call; already-repaired owners count as progress (another worker fixed
% them after our phase failed), owners gone from the tree do not.

ocamlabi:repair_owners(Owners, RepairedCount) :-
  with_mutex(ocaml_abi_repair,
    ocamlabi:repair_owners_locked(Owners, RepairedCount)).

ocamlabi:repair_owners_locked(Owners, RepairedCount) :-
  partition([E]>>(ocamlabi:repair_applied_(E, _)), Owners, Done, Todo),
  ocamlabi:repair_pass(Todo, Failed1),
  ocamlabi:repair_pass(Failed1, Failed2),
  length(Todo, NTodo),
  length(Failed2, NFailed),
  length(Done, NDone),
  RepairedCount is NTodo - NFailed + NDone.

ocamlabi:repair_pass([], []).
ocamlabi:repair_pass([Entry|Rest], Failed) :-
  ( ocamlabi:repair_applied_(Entry, _)
  -> Failed = MoreFailed
  ;  fixup:installed_tree_entry(Entry, TreeRepo)
  -> fixup:repair_rebuild(TreeRepo, Entry, 'ocaml-abi repair rebuild (portage-ng#99)', EC),
     ( EC =:= 0
     -> assertz(ocamlabi:repair_applied_(Entry, TreeRepo)),
        fixup:record(ocamlabi, Entry, stale_ocaml_abi),
        Failed = MoreFailed
     ;  Failed = [Entry|MoreFailed]
     )
  ;  Failed = [Entry|MoreFailed]
  ),
  ocamlabi:repair_pass(Rest, MoreFailed).


% -----------------------------------------------------------------------------
%  Per-phase retry hook
% -----------------------------------------------------------------------------

%! fixup:phase_retry_hook(+ocamlabi, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.
%
% On a non-zero exit of a configure/compile phase whose log segment
% matches an OCaml stale-ABI signature, rebuilds the installed owners of
% the stale compiled units and re-runs the failed phase; a second bounded
% round handles cascading breakage exposed by the repair itself.
% Otherwise passes ExitCode0 through unchanged.

fixup:phase_retry_hook(ocamlabi, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode) :-
  ( ocamlabi:repair_enabled,
    ocamlabi:retry_phase(Phase)
  -> ocamlabi:retry_loop(2, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode)
  ;  ExitCode = ExitCode0
  ).


%! ocamlabi:retry_loop(+RoundsLeft, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.

:- meta_predicate ocamlabi:retry_loop(+, +, +, +, +, +, 2, +, +, -).

ocamlabi:retry_loop(0, _, _, _, _, _, _, _, ExitCode, ExitCode) :- !.

ocamlabi:retry_loop(RoundsLeft, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode) :-
  ( ocamlabi:phase_error(LogPath, SizeBefore, Tail),
    ocamlabi:stale_units(Tail, Paths, Names),
    ( Paths \== [] ; Names \== [] ),
    ocamlabi:stale_owners(Paths, Names, Entry, Owners),
    Owners \== [],
    ocamlabi:repair_owners(Owners, Repaired),
    Repaired > 0
  -> fixup:log_marker(LogPath,
       '~w failed (exit ~w) with stale OCaml compiled units owned by ~w; rebuilding and retrying (portage-ng#99 ocaml-abi repair)',
       [Phase, ExitCode0, Owners]),
     ebuild_exec:log_file_size(LogPath, SizeBefore1),
     ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, UseString, Pid),
     ebuild_exec:poll_phase_spinning(Pid, Phase, Callback, ExitCode1),
     ( ExitCode1 =:= 0
     -> ExitCode = 0
     ;  RoundsLeft1 is RoundsLeft - 1,
        ocamlabi:retry_loop(RoundsLeft1, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore1, ExitCode1, ExitCode)
     )
  ;  ExitCode = ExitCode0
  ).


% -----------------------------------------------------------------------------
%  Build summary note
% -----------------------------------------------------------------------------

%! fixup:mechanism_note(+ocamlabi, +Count, -Lines) is semidet.

fixup:mechanism_note(ocamlabi, N, [Line1, Line2]) :-
  fixup:packages_word(N, Word),
  format(atom(Line1), 'OCaml ABI repair: ~d stale ~w rebuilt in-transaction after a', [N, Word]),
  Line2 = '                  compiler/findlib ABI change (portage-ng#99):'.
