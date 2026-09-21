/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> GHCABI
GHC ABI-hash repair exception, the native haskell-updater (portage-ng#93),
GHC boot-lib package-DB readiness (portage-ng#108), and prove-time
CABAL_CORE_LIB_GHC_PV filtering against the selected GHC (portage-ng#112).

Gentoo encodes a Haskell package's identity in ghc-pkg's ABI hash (the
`-<hash>` suffix, e.g. bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ), NOT in the
ebuild sub-slot. When a dev-haskell library is rebuilt (new hash) its
installed reverse-dependencies keep referencing the old hash, and the next
Haskell consumer's pkg_setup/configure aborts with haskell-cabal.eclass's
check:

  installed package semigroupoids-5.3.7 is broken due to missing package
  bifunctors-5.6.3-9AmA3NO9963FDwV9BBcxcZ
  * Detected broken packages: semigroupoids-5.3.7 semialign-1.3
  * //==-- Please, run 'haskell-updater' to fix broken packages --==//

The sub-slot rebuild pass (portage-ng#89) cannot see this: there is no
sub-slot delta to observe (the hash lives only in ghc-pkg's registry). The
real fix is at the ebuild/eclass level (encoding the ABI identity where
the resolver can see it); until then, traditional emerge fails the same
way and defers to a manual haskell-updater run. We do better: gated by
config:ghc_abi_repair/1, the failure is recovered in-transaction by
parsing the broken package list from the log segment of the failed phase,
rebuilding each broken package from source at its installed version
(re-registering it with a hash consistent with the just-rebuilt
dependency), and re-running the failed phase. Cascading breakage (a repair
rebuild bumping another consumer's hash) is handled by one additional
bounded round. Each package is rebuilt at most once per session
(ghcabi:repair_applied_/2), so the mechanism can never loop; repairs are
serialized under a dedicated mutex so parallel workers hitting the same
breakage don't rebuild twice.

A distinct failure class (portage-ng#108) is Cabal dying on GHC boot
libraries that are not Portage packages at all:

  Error: setup: Encountered missing or private dependencies:
  bytestring >=0.10.4 && <0.12, deepseq ..., ghc-prim ..., template-haskell ...

Those names have no ebuilds to `repair_rebuild`. Recovery is
`ghc-pkg recache` (same post-merge hook as ebuild_exec:maybe_register_ghc_pkg/4)
then retry the failed phase.

Registered with the generic fixup registry (Source/Domain/Gentoo/
Exceptions/fixup.pl); the builder and printer have no knowledge of this
mechanism.
*/

:- module(ghcabi, []).

% =============================================================================
%  GHCABI declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.
:- multifile fixup:phase_retry_hook/10.

:- dynamic ghcabi:repair_applied_/2.

:- mutex_create(ghc_abi_repair).

fixup:mechanism(ghcabi).


% -----------------------------------------------------------------------------
%  Gate
% -----------------------------------------------------------------------------

%! ghcabi:repair_enabled is semidet.

ghcabi:repair_enabled :-
  ( catch(config:ghc_abi_repair(V), _, fail), ground(V)
  -> V == true
  ;  true
  ).


%! ghcabi:retry_phase(+Phase) is semidet.
%
% Phases in which haskell-cabal.eclass runs its broken-package check
% (ghc-package.eclass `checks`): pkg_setup and the configure path. A
% compile failure can also surface it via a late `ghc-pkg` invocation.

ghcabi:retry_phase(setup).
ghcabi:retry_phase(configure).
ghcabi:retry_phase(compile).


% -----------------------------------------------------------------------------
%  Failure signature
% -----------------------------------------------------------------------------

%! ghcabi:phase_error(+LogPath, +SizeBefore, -Tokens) is semidet.
%
% True when the log segment the failed phase wrote (fixup:log_tail/3)
% carries the haskell-updater broken-package signature. Tokens is the
% parsed, deduplicated list of broken `name-ver` atoms from the "Detected
% broken packages:" line(s).

ghcabi:phase_error(LogPath, SizeBefore, Tokens) :-
  fixup:log_tail(LogPath, SizeBefore, Tail),
  sub_string(Tail, _, _, _, "haskell-updater"),
  ghcabi:broken_tokens(Tail, Tokens),
  Tokens \== [],
  !.


%! ghcabi:broken_tokens(+Tail, -Tokens) is det.
%
% Parses every "Detected broken packages:" line in Tail and returns the
% union of the `name-ver` tokens listed after the colon. The eclass
% output is colorized (einfo/eerror ANSI prefixes) but the token area
% itself is plain text; tokens are validated by shape (must contain a
% `-<digit>` version separator) so stray decorations never map to a
% package.

ghcabi:broken_tokens(Tail, Tokens) :-
  split_string(Tail, "\n", "\r", Lines),
  findall(Token,
    ( member(Line, Lines),
      sub_string(Line, B, _, _, "Detected broken packages:"),
      Skip is B + 25,
      sub_string(Line, Skip, _, 0, Rest),
      split_string(Rest, " \t", " \t", Parts),
      member(P0, Parts),
      ghcabi:strip_ansi(P0, P),
      P \== "",
      atom_string(Token, P),
      ghcabi:pv_token(Token)
    ),
    Tokens0),
  sort(Tokens0, Tokens).


%! ghcabi:strip_ansi(+Str, -Clean) is det.
%
% Truncates Str at the first ESC character, dropping any trailing ANSI
% color/reset sequence the eclass output may have attached to a token.

ghcabi:strip_ansi(Str, Clean) :-
  ( sub_string(Str, B, 1, _, "\u001b")
  -> sub_string(Str, 0, B, _, Clean)
  ;  Clean = Str
  ).


%! ghcabi:pv_token(+Token) is semidet.
%
% Token looks like a `name-version` atom: it contains a `-` immediately
% followed by a digit (the Gentoo name/version separator).

ghcabi:pv_token(Token) :-
  sub_atom(Token, B, 1, _, '-'),
  D is B + 1,
  sub_atom(Token, D, 1, _, Ch),
  char_type(Ch, digit),
  !.


% -----------------------------------------------------------------------------
%  Broken-token to entry mapping
% -----------------------------------------------------------------------------

%! ghcabi:token_entry(+Token, -TreeRepo, -Entry) is semidet.
%
% Maps a broken `name-ver` token to the installed VDB entry
% (Category/Name-Version) and a tree repository that still carries the
% same version, so the package can be rebuilt as-is. Fails when the
% installed version is gone from the tree (then the repair skips it and
% the phase failure keeps its original semantics).

ghcabi:token_entry(Token, TreeRepo, Entry) :-
  cache:ordered_entry(pkg, Entry, C, _N, _V),
  atomic_list_concat([C, Token], '/', Entry),
  fixup:installed_tree_entry(Entry, TreeRepo),
  !.


%! ghcabi:repair_tokens(+Tokens, -RepairedCount) is det.
%
% Rebuilds every broken token not already repaired this session, under
% the ghc_abi_repair mutex. Tokens whose rebuild fails on the first pass
% get one more attempt after the others (ghc-pkg lists broken packages in
% registry order, not dependency order, so an inter-broken dependency can
% make the first pass fail). RepairedCount is the number of successful
% rebuilds in this call; already-repaired tokens count as progress
% (another worker fixed them after our phase failed), unmappable tokens
% do not.

ghcabi:repair_tokens(Tokens, RepairedCount) :-
  with_mutex(ghc_abi_repair,
    ghcabi:repair_tokens_locked(Tokens, RepairedCount)).

ghcabi:repair_tokens_locked(Tokens, RepairedCount) :-
  partition([T]>>(ghcabi:repair_applied_(T, _)), Tokens, Done, Todo),
  ghcabi:repair_pass(Todo, Failed1),
  ghcabi:repair_pass(Failed1, Failed2),
  length(Todo, NTodo),
  length(Failed2, NFailed),
  length(Done, NDone),
  RepairedCount is NTodo - NFailed + NDone.

ghcabi:repair_pass([], []).
ghcabi:repair_pass([Token|Rest], Failed) :-
  ( ghcabi:repair_applied_(Token, _)
  -> Failed = MoreFailed
  ;  ghcabi:token_entry(Token, TreeRepo, Entry)
  -> fixup:repair_rebuild(TreeRepo, Entry, 'ghc-abi repair rebuild (portage-ng#93)', EC),
     ( EC =:= 0
     -> assertz(ghcabi:repair_applied_(Token, Entry)),
        fixup:record(ghcabi, Entry, broken_abi(Token)),
        Failed = MoreFailed
     ;  Failed = [Token|MoreFailed]
     )
  ;  Failed = [Token|MoreFailed]
  ),
  ghcabi:repair_pass(Rest, MoreFailed).


% -----------------------------------------------------------------------------
%  Per-phase retry hook
% -----------------------------------------------------------------------------

%! fixup:phase_retry_hook(+ghcabi, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.
%
% On a non-zero exit of a setup/configure/compile phase whose log segment
% matches the haskell-updater broken-package signature, rebuilds the
% broken packages and re-runs the failed phase; a second bounded round
% handles cascading breakage exposed by the repair itself. Otherwise
% passes ExitCode0 through unchanged.

fixup:phase_retry_hook(ghcabi, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode) :-
  ( ghcabi:repair_enabled,
    ghcabi:retry_phase(Phase)
  -> ghcabi:retry_loop(2, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode)
  ;  ExitCode = ExitCode0
  ).


%! ghcabi:retry_loop(+RoundsLeft, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.

:- meta_predicate ghcabi:retry_loop(+, +, +, +, +, +, 2, +, +, -).

ghcabi:retry_loop(0, _, _, _, _, _, _, _, ExitCode, ExitCode) :- !.

ghcabi:retry_loop(RoundsLeft, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore, ExitCode0, ExitCode) :-
  ( ghcabi:phase_error(LogPath, SizeBefore, Tokens),
    ghcabi:repair_tokens(Tokens, Repaired),
    Repaired > 0
  -> fixup:log_marker(LogPath,
       '~w failed (exit ~w) with broken GHC packages ~w; rebuilding and retrying (portage-ng#93 ghc-abi repair)',
       [Phase, ExitCode0, Tokens]),
     ghcabi:rerun_phase(RoundsLeft, EbuildPath, Entry, Phase, LogPath, UseString, Callback, ExitCode)
  ; ghcabi:boot_dep_error(LogPath, SizeBefore, BootLibs),
    ghcabi:recache_ghc_pkg(BootLibs)
  -> ghcabi:log_boot_recache(LogPath, Phase, ExitCode0, BootLibs),
     fixup:record(ghcabi, Entry, boot_dep_recache(BootLibs)),
     ghcabi:rerun_phase(RoundsLeft, EbuildPath, Entry, Phase, LogPath, UseString, Callback, ExitCode)
  ; ghcabi:boot_dep_error(LogPath, SizeBefore, BootLibs),
    % Recache already tried this session; the ebuild version is incompatible
    % with the live GHC boot libs (e.g. text-1.2.5.0 vs ghc-9.8 bytestring).
    % Exclude this version and let the builder re-derive (portage-ng#108).
    ghcabi:exclude_failing_version(Entry, BootLibs, Phase, ExitCode0)
  -> ExitCode = ExitCode0
  ;  ExitCode = ExitCode0
  ).


%! ghcabi:exclude_failing_version(+Entry, +BootLibs, +Phase, +ExitCode) is semidet.
%
% Records feedback:excluded_version/4 for the failing tree entry so the
% next prove skips it. Fails when the entry is not a tree package or the
% exclusion was already known (no replan growth).

ghcabi:exclude_failing_version(Entry, BootLibs, Phase, ExitCode) :-
  cache:ordered_entry(Repo, Entry, C, N, Ver),
  Repo \== pkg,
  \+ feedback:excluded_version(C, N, Ver, _),
  Evidence = evidence(boot_dep(BootLibs), phase(Phase), exit(ExitCode), entry(Entry)),
  feedback:record_excluded_version(C, N, Ver, Evidence),
  fixup:record(ghcabi, Entry, excluded_version(Ver)),
  message:color(yellow),
  format('>>> ghcabi: excluding ~w/~w-~w after GHC boot-lib mismatch; re-deriving plan (#108)~n',
         [C, N, Ver]),
  message:color(normal),
  !.


%! ghcabi:rerun_phase(+RoundsLeft, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, -ExitCode) is det.
%
% Re-runs the failed phase after a successful repair/recache step.

:- meta_predicate ghcabi:rerun_phase(+, +, +, +, +, +, 2, -).

ghcabi:rerun_phase(RoundsLeft, EbuildPath, Entry, Phase, LogPath, UseString, Callback, ExitCode) :-
  ebuild_exec:log_file_size(LogPath, SizeBefore1),
  ebuild_exec:start_phase_async(EbuildPath, Phase, LogPath, UseString, Pid),
  ebuild_exec:poll_phase_spinning(Pid, Phase, Callback, ExitCode1),
  ( ExitCode1 =:= 0
  -> ExitCode = 0
  ;  RoundsLeft1 is RoundsLeft - 1,
     ghcabi:retry_loop(RoundsLeft1, EbuildPath, Entry, Phase, LogPath, UseString, Callback, SizeBefore1, ExitCode1, ExitCode)
  ).


%! ghcabi:boot_dep_error(+LogPath, +SizeBefore, -BootLibs) is semidet.
%
% True when the failed phase log carries Cabal's "Encountered missing or
% private dependencies" signature naming at least one GHC boot library
% (portage-ng#108). BootLibs is the list of matching boot-lib names.

ghcabi:boot_dep_error(LogPath, SizeBefore, BootLibs) :-
  fixup:log_tail(LogPath, SizeBefore, Tail),
  sub_string(Tail, _, _, _, "Encountered missing or private dependencies"),
  findall(Lib,
          ( ghcabi:boot_lib(Lib),
            atom_string(Lib, LibS),
            sub_string(Tail, _, _, _, LibS)
          ),
          BootLibs0),
  sort(BootLibs0, BootLibs),
  BootLibs \== [],
  !.


%! ghcabi:boot_lib(?Name) is nondet.
%
% GHC boot libraries that ship with the compiler (no Portage ebuild).

ghcabi:boot_lib(bytestring).
ghcabi:boot_lib(deepseq).
ghcabi:boot_lib('ghc-prim').
ghcabi:boot_lib('template-haskell').
ghcabi:boot_lib(array).
ghcabi:boot_lib(containers).
ghcabi:boot_lib(directory).
ghcabi:boot_lib(filepath).
ghcabi:boot_lib(pretty).
ghcabi:boot_lib(process).
ghcabi:boot_lib(time).
ghcabi:boot_lib(unix).
ghcabi:boot_lib(binary).


% -----------------------------------------------------------------------------
%  Prove-time CABAL_CORE_LIB_GHC_PV filter (portage-ng#112)
% -----------------------------------------------------------------------------

:- dynamic ghcabi:cabal_core_cache_/2.


%! ghcabi:version_incompatible_with_selected_ghc(+C, +N, +Domain, +RepoEntry) is semidet.
%
% True when RepoEntry declares a non-empty CABAL_CORE_LIB_GHC_PV that does
% not cover the already-selected GHC, and another (C,N) candidate does
% cover it AND is admitted by Domain. Mirrors haskell-cabal.eclass
% `cabal-is-dummy-lib`: the matching sibling is the known-good (dummy)
% install for that GHC; the mismatched older core-lib ebuild would attempt
% a real Cabal build against incompatible boot libraries (text-1.2.5 vs
% ghc-9.8 → portage-ng#108/#112).
%
% The domain guard is the other direction (portage-ng#123). An exact old
% atom such as `=dev-haskell/adjunctions-4.4` requires `mtl < 2.3`, and the
% only in-domain mtl is the GHC-9.2 core lib. The GHC-9.8 sibling matches
% the selected compiler but sits outside that bound, so it is not a real
% alternative: rejecting the in-domain core lib here made the dep
% unsatisfiable and left GHC 9.8 locked. Keeping the in-domain lib lets its
% own `<dev-lang/ghc-9.5` constraint re-select the compiler.
%
% Inactive when no GHC is selected yet, or when the entry has no
% CABAL_CORE_LIB_GHC_PV (regular Haskell packages).

ghcabi:version_incompatible_with_selected_ghc(C, N, Domain, Repo://Entry) :-
  ghcabi:selected_ghc_numeric_version(GhcNumeric),
  % A learned ghc domain from an earlier pass can already have ruled the
  % selected compiler out (portage-ng#123: ghc < 9.5 while 9.8 is still
  % the snapshot). Filtering core libs against that stale compiler would
  % reject the lib that matches the domain's compiler.
  ghcabi:selected_ghc_inside_learned_domain,
  ghcabi:cabal_core_ghc_pvs(Repo://Entry, PVs),
  PVs \== [],
  \+ ghcabi:cabal_core_matches(PVs, GhcNumeric),
  cache:ordered_entry(OtherRepo, OtherEntry, C, N, _),
  OtherEntry \== Entry,
  ghcabi:cabal_core_ghc_pvs(OtherRepo://OtherEntry, OtherPVs),
  OtherPVs \== [],
  ghcabi:cabal_core_matches(OtherPVs, GhcNumeric),
  version_domain:domain_allows_candidate(Domain, OtherRepo://OtherEntry),
  !.


%! ghcabi:selected_ghc_numeric_version(-Numeric) is semidet.
%
% Numeric GHC version atom (e.g. `9.8.4`) from the selected_cn snapshot.

ghcabi:selected_ghc_numeric_version(Numeric) :-
  cnselect:snapshot_selected_cn_candidates('dev-lang', ghc, [GhcRepo://GhcEntry|_]),
  cache:ordered_entry(GhcRepo, GhcEntry, _, _, Ver),
  ghcabi:version_numeric_atom(Ver, Numeric),
  !.


%! ghcabi:selected_ghc_inside_learned_domain is semidet.
%
% True when no learned ghc domain exists, or the selected GHC is inside
% it. A selected compiler outside the learned domain is stale.

ghcabi:selected_ghc_inside_learned_domain :-
  ( prover:learned(cn_domain('dev-lang', ghc, any), Domain) ->
      cnselect:snapshot_selected_cn_candidates('dev-lang', ghc, [Repo://Entry|_]),
      version_domain:domain_allows_candidate(Domain, Repo://Entry)
  ; true
  ),
  !.


%! ghcabi:version_numeric_atom(+Version, -Numeric) is semidet.

ghcabi:version_numeric_atom(version(Nums, _, _, _, _, _, _), Numeric) :-
  is_list(Nums),
  Nums \== [],
  atomic_list_concat(Nums, '.', Numeric).


%! ghcabi:cabal_core_ghc_pvs(+RepoEntry, -PVs) is det.
%
% Reads CABAL_CORE_LIB_GHC_PV from the on-disk ebuild (not in md5-cache).
% Memoized per entry. Returns [] when absent or unreadable.

ghcabi:cabal_core_ghc_pvs(Repo://Entry, PVs) :-
  ( ghcabi:cabal_core_cache_(Repo://Entry, Cached)
  -> PVs = Cached
  ;  ( catch(ghcabi:read_cabal_core_from_ebuild(Repo://Entry, Read), _, Read = [])
     -> true
     ;  Read = []
     ),
     assertz(ghcabi:cabal_core_cache_(Repo://Entry, Read)),
     PVs = Read
  ).


%! ghcabi:read_cabal_core_from_ebuild(+RepoEntry, -PVs) is det.

ghcabi:read_cabal_core_from_ebuild(Repo://Entry, PVs) :-
  ebuild_exec:ebuild_path(Repo, Entry, Path),
  exists_file(Path),
  !,
  setup_call_cleanup(
    open(Path, read, S, [encoding(utf8)]),
    ghcabi:scan_cabal_core_stream(S, PVs),
    close(S)).
ghcabi:read_cabal_core_from_ebuild(_, []).


%! ghcabi:scan_cabal_core_stream(+Stream, -PVs) is det.

ghcabi:scan_cabal_core_stream(S, PVs) :-
  ( at_end_of_stream(S)
  -> PVs = []
  ;  read_line_to_string(S, Line),
     ( ghcabi:parse_cabal_core_line(Line, PVs)
     -> true
     ;  ghcabi:scan_cabal_core_stream(S, PVs)
     )
  ).


%! ghcabi:parse_cabal_core_line(+Line, -PVs) is semidet.
%
% Accepts `CABAL_CORE_LIB_GHC_PV="a b c"` (double or single quotes).

ghcabi:parse_cabal_core_line(Line0, PVs) :-
  ( string(Line0) -> Line = Line0 ; atom_string(Line0, Line) ),
  split_string(Line, "", " \t", [Trimmed]),
  sub_string(Trimmed, 0, _, _, "CABAL_CORE_LIB_GHC_PV"),
  sub_string(Trimmed, EqFrom, 1, _, "="),
  !,
  AfterEq is EqFrom + 1,
  sub_string(Trimmed, AfterEq, _, 0, Rhs0),
  split_string(Rhs0, "", " \t", [Rhs1]),
  string_length(Rhs1, Len),
  Len >= 2,
  sub_string(Rhs1, 0, 1, _, Q),
  ( Q == "\"" ; Q == "'" ),
  End is Len - 1,
  sub_string(Rhs1, End, 1, 0, Q),
  InnerLen is Len - 2,
  sub_string(Rhs1, 1, InnerLen, _, Inner),
  split_string(Inner, " \t", " \t", Parts),
  exclude(ghcabi:empty_string, Parts, NonEmpty),
  maplist(atom_string, PVs, NonEmpty),
  !.


ghcabi:empty_string("").


%! ghcabi:cabal_core_matches(+PVs, +GhcNumeric) is semidet.
%
% True when GhcNumeric (e.g. `9.8.4`) matches a CABAL_CORE pattern using
% the same glob semantics as haskell-cabal.eclass (`[[ a == pat ]]`).

ghcabi:cabal_core_matches(PVs, GhcNumeric) :-
  member(Pat0, PVs),
  ( atom_concat('PM:', _, Pat0)
  -> fail  % PM: patterns need the package-manager PV; numeric path is enough here
  ;  Pat = Pat0
  ),
  wildcard_match(Pat, GhcNumeric),
  !.


%! ghcabi:recache_ghc_pkg(+BootLibs) is semidet.
%
% Runs ghc-pkg recache once under the ghc_abi_repair mutex. Succeeds when
% the command was attempted (even if ghc-pkg is absent — then the retry
% will fail with the original exit and we stop). Deduplicated per session
% via repair_applied_(ghc_pkg_recache, _).

ghcabi:recache_ghc_pkg(BootLibs) :-
  with_mutex(ghc_abi_repair,
    ( ghcabi:repair_applied_(ghc_pkg_recache, _)
    -> fail
    ;  ebuild_exec:register_ghc_pkg(boot_dep(BootLibs)),
       assertz(ghcabi:repair_applied_(ghc_pkg_recache, BootLibs))
    )).


%! ghcabi:log_boot_recache(+LogPath, +Phase, +ExitCode, +BootLibs) is det.

ghcabi:log_boot_recache(LogPath, Phase, ExitCode, BootLibs) :-
  fixup:log_marker(LogPath,
    '~w failed (exit ~w) with missing GHC boot deps ~w; ghc-pkg recache and retry (portage-ng#108)',
    [Phase, ExitCode, BootLibs]).


% -----------------------------------------------------------------------------
%  Build summary note
% -----------------------------------------------------------------------------

%! fixup:mechanism_note(+ghcabi, +Count, -Lines) is semidet.

fixup:mechanism_note(ghcabi, N, [Line1, Line2]) :-
  fixup:packages_word(N, Word),
  format(atom(Line1), 'GHC ABI repair: ~d broken ~w rebuilt in-transaction after a', [N, Word]),
  Line2 = '                dependency ABI-hash change (portage-ng#93, haskell-updater equivalent):'.
