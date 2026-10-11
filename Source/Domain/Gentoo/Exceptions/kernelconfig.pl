/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> KERNELCONFIG
Kernel CONFIG_CHECK learning exception (portage-ng#105).

When a build dies in the `setup` phase because Gentoo's linux-info.eclass
`CONFIG_CHECK` found the running kernel source configuration missing (or
carrying) a required option -- e.g.

  CONFIG_SECURITY_APPARMOR:	 is not set when it should be.
  ERROR: sys-apps/apparmor-4.1.7::gentoo failed (setup phase):
    Incorrect kernel configuration options

the fault is not an ebuild bug and not a resolver gap: the kernel source
tree simply lacks an option the package needs. Like the missing-provider
mechanism (#102), this one never repairs in place and threads the phase's
exit code through unchanged; it turns the failure into learned knowledge
and lets the pipeline re-derive a plan that includes a kernel-config-change
action ordered before the failing package.

The learned requirement is recorded via feedback:record_kernel_config/3
(durable, surfaced as a plan pre-action on the next pass) and fixup:record/3
(so it shows in the build summary). On the re-derived plan the builder
applies the option to the kernel source .config (scripts/config +
`make olddefconfig`) before building, so the CONFIG_CHECK passes.

Scope: satisfying CONFIG_CHECK unblocks userspace packages (apparmor,
apparmor-utils, ...). Kernel-module packages that need a rebuilt kernel are
only partly helped (the option is set and `modules_prepare` is run, but no
kernel rebuild/reboot happens). Two other cluster-C sub-types are out of
scope by construction and correctly left to fail: a kernel that is newer
than a package's supported ceiling (a version bound, not an option) and an
unset PYTHON_SINGLE_TARGET (a profile choice, not a kernel option).

Registered with the generic fixup registry (Source/Domain/Gentoo/
Exceptions/fixup.pl); the builder and printer stay generic.
*/

:- module(kernelconfig, []).

% =============================================================================
%  KERNELCONFIG declarations
% =============================================================================

:- multifile fixup:mechanism/1.
:- multifile fixup:mechanism_note/3.
:- multifile fixup:phase_retry_hook/10.

fixup:mechanism(kernelconfig).


% -----------------------------------------------------------------------------
%  Gate
% -----------------------------------------------------------------------------

%! kernelconfig:enabled is semidet.
%
% True when `kernelconfig` is listed in config:build_learned/1.
% A missing list leaves the strategy enabled.

kernelconfig:enabled :-
  ( catch(config:build_learned(Strategies), _, fail), is_list(Strategies)
  -> memberchk(kernelconfig, Strategies)
  ;  true
  ).


%! kernelconfig:kernel_source_dir(-Dir) is det.
%
% Kernel source directory whose .config the CONFIG_CHECK reads. Overridable
% via config:kernel_source_dir/1; defaults to the eselect-managed
% /usr/src/linux symlink.

kernelconfig:kernel_source_dir(Dir) :-
  ( catch(config:kernel_source_dir(D), _, fail), atom(D), D \== ''
  -> Dir = D
  ;  Dir = '/usr/src/linux'
  ).


% -----------------------------------------------------------------------------
%  Per-phase retry hook (diagnose, never repair)
% -----------------------------------------------------------------------------

%! fixup:phase_retry_hook(+kernelconfig, +EbuildPath, +Entry, +Phase, +LogPath, +UseString, :Callback, +SizeBefore, +ExitCode0, -ExitCode) is det.
%
% On a non-zero exit of the setup phase, scans the log segment the phase
% appended for linux-info CONFIG_CHECK lines and records the required
% kernel options as learned knowledge. Always passes ExitCode0 through
% unchanged -- the phase is never re-run here; the builder's replan loop
% re-derives the plan with a kernel-config-change action ordered before the
% target.

fixup:phase_retry_hook(kernelconfig, _EbuildPath, Entry, Phase, LogPath, _UseString, _Callback, SizeBefore, ExitCode0, ExitCode0) :-
  ( kernelconfig:enabled,
    ExitCode0 =\= 0,
    Phase == setup,
    fixup:tree_entry(Entry, Repo, _C, _N),
    fixup:scan_log(LogPath, SizeBefore, Lines),
    Lines \== [],
    kernelconfig:detect_options(Lines, Options, EvidenceLines),
    Options \== []
  -> once(kernelconfig:record_requirement(Repo, Entry, Phase, ExitCode0, Options, EvidenceLines))
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Detection
% -----------------------------------------------------------------------------

%! kernelconfig:detect_options(+Lines, -Options, -EvidenceLines) is det.
%
% Runs the CONFIG_CHECK detectors over the log lines, deduplicating on the
% option name: the first CONFIG_CHECK verdict per option wins, so a later
% line asking for a different state of the same option is ignored.
% Options is a sorted list of config(Name, State) with State in {y, n}.

kernelconfig:detect_options(Lines, Options, EvidenceLines) :-
  findall(Name-(config(Name, State)-Line),
          kernelconfig:detector(Lines, config(Name, State), Line),
          Pairs0),
  fixup:dedup_first(Pairs0, Pairs),
  findall(Opt, member(_-(Opt-_), Pairs), Options0),
  sort(Options0, Options),
  findall(Line, member(_-(_-Line), Pairs), EvidenceLines0),
  sort(EvidenceLines0, EvidenceLines).


%! kernelconfig:detector(+Lines, -Option, -Line) is nondet.
%
% linux-info.eclass emits one line per unsatisfied option:
%   "CONFIG_FOO:\t is not set when it should be."  -> enable  (config(Name,y))
%   "CONFIG_FOO:\t is set when it should not be."  -> disable (config(Name,n))

kernelconfig:detector(Lines, config(Name, y), Line) :-
  member(Line, Lines),
  sub_string(Line, _, _, _, "is not set when it should be"),
  kernelconfig:config_token(Line, Name).

kernelconfig:detector(Lines, config(Name, n), Line) :-
  member(Line, Lines),
  sub_string(Line, _, _, _, "is set when it should not be"),
  \+ sub_string(Line, _, _, _, "is not set when it should be"),
  kernelconfig:config_token(Line, Name).


%! kernelconfig:config_token(+Line, -Name) is semidet.
%
% Extracts the CONFIG_<NAME> token (the text from the first "CONFIG_"
% occurrence up to the following colon) and validates it is a single
% config-option identifier.

kernelconfig:config_token(Line, Name) :-
  sub_string(Line, Before, _, 0, FromConfig0),
  sub_string(FromConfig0, 0, 7, _, "CONFIG_"),
  !,
  kernelconfig:config_token_at(Line, Before, Name).
kernelconfig:config_token(Line, Name) :-
  sub_string(Line, Before, _, _, "CONFIG_"),
  kernelconfig:config_token_at(Line, Before, Name).

kernelconfig:config_token_at(Line, Before, Name) :-
  sub_string(Line, Before, _, 0, FromConfig),
  split_string(FromConfig, ":", " \t", [Tok|_]),
  Tok \== "",
  \+ sub_string(Tok, _, _, _, " "),
  sub_string(Tok, 0, 7, _, "CONFIG_"),
  kernelconfig:name_string(Tok),
  atom_string(Name, Tok).


%! kernelconfig:name_string(+Str) is semidet.
%
% True when every character of Str is a config-option character
% (alphanumeric or underscore).

kernelconfig:name_string(Str) :-
  string_chars(Str, Chars),
  forall(member(Ch, Chars), kernelconfig:name_char(Ch)).

kernelconfig:name_char(Ch) :- char_type(Ch, alnum), !.
kernelconfig:name_char('_').


% -----------------------------------------------------------------------------
%  Recording
% -----------------------------------------------------------------------------

%! kernelconfig:record_requirement(+Repo, +Entry, +Phase, +ExitCode, +Options, +EvidenceLines) is det.
%
% Records the learned kernel-config requirement as durable feedback (so the
% next proof pass surfaces it as a pre-action and future runs plan it
% proactively) and as a fixup record (for the build summary).

kernelconfig:record_requirement(Repo, Entry, Phase, ExitCode, Options, EvidenceLines) :-
  Evidence = evidence(kernel_config(Options),
                      phase(Phase),
                      exit(ExitCode),
                      log(EvidenceLines)),
  feedback:record_kernel_config(Repo://Entry, Options, Evidence),
  fixup:record(kernelconfig, Entry, kernel_config(Options)),
  kernelconfig:log_requirement(Entry, Options).


%! kernelconfig:log_requirement(+Entry, +Options) is det.

kernelconfig:log_requirement(Entry, Options) :-
  kernelconfig:options_atom(Options, OptAtom),
  message:color(yellow),
  format('>>> kernel config: ~w needs ~w; recorded as learned requirement, re-deriving plan (#105)~n',
         [Entry, OptAtom]),
  message:color(normal).


%! kernelconfig:options_atom(+Options, -Atom) is det.
%
% Human-readable rendering of a config-option list, e.g.
% "CONFIG_SECURITY_APPARMOR=y CONFIG_FOO=n".

kernelconfig:options_atom(Options, Atom) :-
  findall(Tok,
          ( member(config(Name, State), Options),
            format(atom(Tok), '~w=~w', [Name, State]) ),
          Toks),
  atomic_list_concat(Toks, ' ', Atom).


% -----------------------------------------------------------------------------
%  Applying a kernel-config pre-action
% -----------------------------------------------------------------------------

%! kernelconfig:apply_planned(+PreActions) is det.
%
% Applies every kernel_config(Options, _Evidence) pre-action in PreActions
% to the kernel source .config, then normalizes the tree. Called by the
% builder before it executes the plan steps, so the CONFIG_CHECK of the
% package that learned the requirement now passes. Best-effort and
% defensive: a missing kernel tree, missing scripts/config, or a failing
% make never aborts the build (the package's own CONFIG_CHECK will just
% fail again with a clear message).

kernelconfig:apply_planned(PreActions) :-
  ( kernelconfig:enabled,
    findall(Opt,
            ( member(kernel_config(Options, _Evidence), PreActions),
              member(Opt, Options) ),
            Opts0),
    sort(Opts0, Opts),
    Opts \== []
  -> kernelconfig:apply_options(Opts)
  ;  true
  ).


%! kernelconfig:apply_options(+Options) is det.
%
% Enables/disables each config(Name, State) in the kernel source .config
% via scripts/config, then runs `make olddefconfig` (to resolve option
% dependencies) and `make modules_prepare` (so out-of-tree modules can
% still build against the tree). All best-effort. Uses process_create/3
% argv only — KDir/ConfigPath/option names are never interpolated into
% `sh -c`.

kernelconfig:apply_options(Options) :-
  kernelconfig:kernel_source_dir(KDir),
  atom_concat(KDir, '/.config', ConfigPath),
  ( exists_file(ConfigPath)
  -> kernelconfig:log_apply(KDir, Options),
     catch(
       ( kernelconfig:run_scripts_config(KDir, ConfigPath, Options),
         kernelconfig:run_make(KDir, olddefconfig),
         kernelconfig:run_make(KDir, modules_prepare)
       ),
       _Error,
       true)
  ;  message:color(red),
     format('!!! kernel config: ~w has no .config; cannot apply learned options (#105)~n', [ConfigPath]),
     message:color(normal)
  ).


%! kernelconfig:run_scripts_config(+KDir, +ConfigPath, +Options) is det.
%
% Run scripts/config --enable/--disable for each option via argv.
% Skips options whose bare suffix is not a safe CONFIG token.

kernelconfig:run_scripts_config(KDir, ConfigPath, Options) :-
  atomic_list_concat([KDir, '/scripts/config'], Script),
  ( exists_file(Script)
  -> forall(
       member(config(Name, State), Options),
       ( kernelconfig:strip_prefix(Name, Suffix),
         ( kernelconfig:safe_config_suffix(Suffix),
           ( State == y -> Op = '--enable' ; Op = '--disable' )
         -> catch(
              ( process_create(Script,
                               ['--file', ConfigPath, Op, Suffix],
                               [stdout(null), stderr(null), process(Pid)]),
                process_wait(Pid, _)
              ),
              _, true)
         ;  true
         )
       ))
  ;  true
  ).


%! kernelconfig:run_make(+KDir, +Target) is det.
%
% Best-effort `make -C KDir Target` via argv (stdout/stderr discarded).

kernelconfig:run_make(KDir, Target) :-
  catch(
    ( process_create(path(make), ['-C', KDir, Target],
                     [stdout(null), stderr(null), process(Pid)]),
      process_wait(Pid, _)
    ),
    _, true).


%! kernelconfig:safe_config_suffix(+Suffix) is semidet.
%
% True when Suffix is a bare Kconfig token safe as an argv element
% (uppercase letters, digits, underscore only).

kernelconfig:safe_config_suffix(Suffix) :-
  atom(Suffix),
  atom_string(Suffix, S),
  string_length(S, Len), Len > 0, Len =< 128,
  re_match('^[A-Z0-9_]+$', S).


%! kernelconfig:strip_prefix(+Name, -Suffix) is det.
%
% Drops a leading CONFIG_ from a config-option name (scripts/config wants
% the bare suffix).

kernelconfig:strip_prefix(Name, Suffix) :-
  ( atom_concat('CONFIG_', Suffix0, Name)
  -> Suffix = Suffix0
  ;  Suffix = Name
  ).


%! kernelconfig:log_apply(+KDir, +Options) is det.

kernelconfig:log_apply(KDir, Options) :-
  kernelconfig:options_atom(Options, OptAtom),
  message:color(green),
  format('>>> kernel config: applying ~w to ~w/.config (#105)~n', [OptAtom, KDir]),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Build summary note
% -----------------------------------------------------------------------------

%! fixup:mechanism_note(+kernelconfig, +Count, -Lines) is semidet.

fixup:mechanism_note(kernelconfig, N, [Line1, Line2]) :-
  fixup:packages_word(N, Word),
  format(atom(Line1), 'Kernel config: ~d ~w required kernel options that were learned at', [N, Word]),
  Line2 = '               setup time and applied to the kernel source .config (portage-ng#105):'.
