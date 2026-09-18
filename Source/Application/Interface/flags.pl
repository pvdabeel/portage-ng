/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> FLAGS
Option handling: translating parsed CLI flags into runtime preferences and
config overrides, plus derived accessors (mode, port, server, tty and
working-directory init)
(included into the INTERFACE module via interface.pl).
*/

% -----------------------------------------------------------------------------
%  Option handling
% -----------------------------------------------------------------------------

%! interface:process_flags is det.
%
% Translates boolean CLI flags into runtime preference assertions
% (e.g. --deep asserts preference:local_flag(deep)) and sets
% config overrides for verbose mode and printing style.
%
% Every flag asserted here has a reader (preference:flag/1 lookups unless
% noted); the table is the contract, keep it current when adding a flag:
%
% | local_flag / config fact  | read by                                            |
% |---------------------------|----------------------------------------------------|
% | deep                      | target:deep_update_goals/3 (candidate:resolve :update) |
% | emptytree                 | resolving rules (install/run/reinstall), abirebuild:active |
% | depclean                  | depclean / unmerging rule set                       |
% | newuse, changeduse        | candidate keep-installed check + grouped_dep_update_reason |
% | changeddeps               | candidate (sets:entry_deps_outdated/1)              |
% | changedslot               | candidate (sets:entry_slot_changed/1)               |
% | rebuiltbinaries           | candidate (sets:entry_has_rebuilt_binary/1)         |
% | selective, noreplace      | rule(target(_,_):run): installed target -> world registration only |
% | updateifinstalled         | rule(target(_,_):run): not-installed target -> skipped |
% | nodeps, onlydeps          | rule(target(_,_):run), rule(_:install)              |
% | nodynamicdeps             | depclean:direct_deps_installed/2 (VDB-recorded deps) |
% | rebuildnewrev, rebuildnewver | target:rebuild_if_newer_available/1              |
% | rebuildnewslot            | abirebuild:enabled (forces sub-slot rebuilds on)    |
% | rebuildunbuilt            | abirebuild:build_consumers/3                        |
% | nobdeps (--with-bdeps=n)  | target:bdepend_only_dep/1 (--deep skips BDEPEND-only deps) |
% | withtestdeps              | target:target_context/2 -> candidate:eligible `test?` groups |
% | oneshot                   | rule(target(_,_):run / :uninstall), upgrade action  |
% | pretend                   | action:process_action/3 reads pretend(true) from Options |
% | buildpkg, buildpkgonly    | ebuild_exec:action_phases/3, maybe_inject_built/5   |
% | usepkg, getbinpkg         | binpkg_exec:consumption_enabled/0                   |
% | usepkgonly, getbinpkgonly | binpkg_exec:consumption_enabled/0, binary_only/0    |
% | usepkgexcludelive         | binpkg_exec:entry_allowed/2                         |
% | binpkgchangeddeps         | binpkg_exec:changed_deps_policy/1                   |
% | binpkgrespectuse          | binpkg_exec:respect_use_policy/1                    |
% | nobinpkgrespectuserpatches | binpkg_exec:respect_user_patches_policy/1          |
% | fetchonly                 | printer + builder (hide/skip merge actions; keep downloads) |
% | fetchall                  | fetchonly + ebuild:distfile_scope/1 (all SRC_URI) |
% | failclean                 | ebuild_exec:maybe_fail_clean/4                      |
% | readnews, ask, alert      | builder (pre-build prompt / bell)                   |
% | quiet                     | message:scroll expansion                            |
% | permitdowngrade           | ranking:dep_no_downgrade_value/3 (neutralises downgrade demotion) |
% | optimize_soft_requirements (--optimize soft-requirements) | ordering:prefers/2 (hand cyclic preferences to the projection) |
% | config:cli_prefix/1       | ebuild_exec:prefix_env/1 (EPREFIX for the ebuild run) |
% | config:usepkg_{in,ex}clude_atom/1 | binpkg_exec:entry_allowed/2                 |

interface:process_flags :-
  interface:argv(Options, _),
  (lists:memberchk(deep(true),              Options) -> asserta(preference:local_flag(deep)) ; true),
  (lists:memberchk(emptytree(true),         Options) -> asserta(preference:local_flag(emptytree)) ; true),
  (lists:memberchk(depclean(true),          Options) -> asserta(preference:local_flag(depclean)) ; true),
  (lists:memberchk(newuse(true),            Options) -> asserta(preference:local_flag(newuse)) ; true),
  (lists:memberchk(changeduse(true),        Options) -> asserta(preference:local_flag(changeduse)) ; true),
  (lists:memberchk(changeddeps(true),       Options) -> asserta(preference:local_flag(changeddeps)) ; true),
  (lists:memberchk(changedslot(true),       Options) -> asserta(preference:local_flag(changedslot)) ; true),
  (lists:memberchk(selective(true),         Options) -> asserta(preference:local_flag(selective)) ; true),
  (lists:memberchk(noreplace(true),         Options) -> asserta(preference:local_flag(noreplace)) ; true),
  (lists:memberchk(nodeps(true),            Options) -> asserta(preference:local_flag(nodeps)) ; true),
  (lists:memberchk(onlydeps(true),          Options) -> asserta(preference:local_flag(onlydeps)) ; true),
  (lists:memberchk(dynamicdeps(false),      Options) -> asserta(preference:local_flag(nodynamicdeps)) ; true),
  (lists:memberchk(rebuildnewrev(true),     Options) -> asserta(preference:local_flag(rebuildnewrev)) ; true),
  (lists:memberchk(rebuildnewver(true),     Options) -> asserta(preference:local_flag(rebuildnewver)) ; true),
  (lists:memberchk(rebuildnewslot(true),    Options) -> asserta(preference:local_flag(rebuildnewslot)) ; true),
  (lists:memberchk(rebuildunbuilt(true),    Options) -> asserta(preference:local_flag(rebuildunbuilt)) ; true),
  (lists:memberchk(updateifinstalled(true), Options) -> asserta(preference:local_flag(updateifinstalled)) ; true),
  (lists:memberchk(readnews(true),          Options) -> asserta(preference:local_flag(readnews)) ; true),
  (lists:memberchk(withbdeps(n),            Options) -> asserta(preference:local_flag(nobdeps)) ; true),
  (lists:memberchk(withtestdeps(y),         Options) -> asserta(preference:local_flag(withtestdeps)) ; true),
  (lists:memberchk(pretend(true),           Options) -> asserta(preference:local_flag(pretend)) ; true),
  (lists:memberchk(oneshot(true),           Options) -> asserta(preference:local_flag(oneshot)) ; true),
  (lists:memberchk(select(false),           Options) -> asserta(preference:local_flag(oneshot)) ; true),
  (lists:memberchk(buildpkg(true),          Options) -> asserta(preference:local_flag(buildpkg)) ; true),
  (lists:memberchk(buildpkgonly(true),      Options) -> asserta(preference:local_flag(buildpkgonly)) ; true),
  (lists:memberchk(usepkg(true),            Options) -> asserta(preference:local_flag(usepkg)) ; true),
  (lists:memberchk(usepkgonly(true),        Options) -> asserta(preference:local_flag(usepkgonly)) ; true),
  (lists:memberchk(getbinpkg(true),         Options) -> asserta(preference:local_flag(getbinpkg)) ; true),
  (lists:memberchk(getbinpkgonly(true),     Options) -> asserta(preference:local_flag(getbinpkgonly)) ; true),
  (lists:memberchk(fetchonly(true),         Options) -> asserta(preference:local_flag(fetchonly)) ; true),
  (lists:memberchk(fetchall(true),          Options)
    -> asserta(preference:local_flag(fetchall)),
       asserta(preference:local_flag(fetchonly)) ; true),
  (lists:memberchk(failclean(true),         Options) -> asserta(preference:local_flag(failclean)) ; true),
  (lists:memberchk(usepkgexcludelive(true), Options) -> asserta(preference:local_flag(usepkgexcludelive)) ; true),
  (lists:memberchk(binpkgchangeddeps(true), Options) -> asserta(preference:local_flag(binpkgchangeddeps)) ; true),
  (lists:memberchk(binpkgrespectuse(true),  Options) -> asserta(preference:local_flag(binpkgrespectuse)) ; true),
  ( interface:binpkg_respect_user_patches_off(Options)
  -> asserta(preference:local_flag(nobinpkgrespectuserpatches)) ; true),
  (lists:memberchk(rebuiltbinaries(true),   Options) -> asserta(preference:local_flag(rebuiltbinaries)) ; true),
  (lists:memberchk(ask(true),               Options) -> asserta(preference:local_flag(ask)) ; true),
  (lists:memberchk(alert(true),             Options) -> asserta(preference:local_flag(alert)) ; true),
  (lists:memberchk(quiet(true),             Options) -> asserta(preference:local_flag(quiet)) ; true),
  (lists:memberchk(verbose(true),           Options) -> asserta(config:verbose(true)) ; true),
  (lists:memberchk(choicelog(true),         Options)
    -> ( asserta(config:choice_log(true)),
         choicelog:arm,
         choicelog:reset
       )
    ; true),
  (lists:memberchk(profile(true),           Options) -> set_prolog_flag(instrumentation, true) ; true),
  (lists:memberchk(logs(true),              Options) -> asserta(config:show_build_logs(true)) ; true),
  (lists:memberchk(ci(true),                Options) -> asserta(config:cli_ci(true)) ; true),
  (lists:memberchk(style(Style),            Options) -> interface:assert_valid_style(Style) ; true),
  (lists:memberchk(optimize(Strategy),      Options) -> interface:assert_valid_optimize(Strategy) ; true),
  ((lists:memberchk(jobs(J),                Options), J > 0) -> asserta(config:cli_jobs(J)) ; true),
  ((lists:memberchk(loadavg(L),             Options), L > 0.0) -> asserta(config:cli_load_average(L)) ; true),
  (lists:memberchk(permitdowngrade(true),   Options) -> asserta(preference:local_flag(permitdowngrade)) ; true),
  ((lists:memberchk(prefix(P),              Options), P \== '/') -> asserta(config:cli_prefix(P)) ; true),
  (lists:memberchk(color(n),                Options) -> retractall(config:color_output) ; true),
  (lists:memberchk(showdescriptions(SD),    Options), SD \== none
                                                     -> asserta(config:show_use_descriptions(SD)) ; true),
  (lists:memberchk(continuefailure(CF),     Options), CF \== never
                                                     -> asserta(config:continue_on_failure(CF)) ; true),
  % convenience presets
  (lists:memberchk(lazy(true), Options) ->
    asserta(preference:local_flag(noreplace)),
    asserta(preference:local_flag(nodeps)) ; true),
  (lists:memberchk(complete(true), Options) ->
    asserta(preference:local_flag(deep)),
    asserta(preference:local_flag(newuse)),
    retractall(preference:local_flag(nobdeps)) ; true),
  (lists:memberchk(everything(true), Options) ->
    asserta(preference:local_flag(emptytree)),
    asserta(preference:local_flag(deep)) ; true),
  interface:process_repeated_flags,
  interface:process_snapshot_flag.


%! interface:process_repeated_flags is det.
%
% Scans the raw argv for repeated value-taking flags and asserts
% each value. This bypasses optparse's keeplast behaviour, allowing
% e.g. --skip pkg1 --skip pkg2 without shell quoting.

interface:process_repeated_flags :-
  current_prolog_flag(argv, RawArgs),
  interface:collect_flag_values(RawArgs, '--skip', Skips),
  forall(member(S, Skips), asserta(config:skip_atom(S))),
  interface:collect_flag_values(RawArgs, '--exclude', Excludes),
  forall(member(E, Excludes), asserta(config:excluded_atom(E))),
  interface:collect_flag_values(RawArgs, '--usepkg-exclude', UExcl),
  forall(member(U, UExcl), asserta(config:usepkg_exclude_atom(U))),
  interface:collect_flag_values(RawArgs, '--usepkg-include', UIncl),
  forall(member(I, UIncl), asserta(config:usepkg_include_atom(I))),
  interface:collect_flag_values(RawArgs, '--favour', Favours),
  forall(member(Fv, Favours), asserta(config:dep_favour(Fv))),
  interface:collect_flag_values(RawArgs, '--avoid', Avoids),
  forall(member(Av, Avoids), asserta(config:dep_avoid(Av))),
  interface:collect_flag_values(RawArgs, '--preset', Presets),
  forall(member(Pr, Presets), asserta(config:dep_preset(Pr))),
  interface:collect_flag_values(RawArgs, '--hide', Hides),
  forall(member(Hi, Hides), asserta(config:dep_hide(Hi))),
  interface:collect_flag_values(RawArgs, '--early', Earlys),
  forall(member(Ea, Earlys), asserta(config:dep_early(Ea))),
  interface:collect_flag_values(RawArgs, '--late', Lates),
  forall(member(La, Lates), asserta(config:dep_late(La))).


%! interface:collect_flag_values(+ArgList, +Flag, -Values) is det.
%
% Walks the argument list and collects the value following each
% occurrence of Flag.

interface:collect_flag_values([], _, []).

interface:collect_flag_values([Flag, Value|Rest], Flag, [Value|More]) :-
  !,
  interface:collect_flag_values(Rest, Flag, More).

interface:collect_flag_values([_|Rest], Flag, Values) :-
  interface:collect_flag_values(Rest, Flag, Values).


%! interface:binpkg_respect_user_patches_off(+Options) is semidet.
%
% True when `--binpkg-respect-user-patches` was passed as `n`, `no`, or
% `false` (emerge's `=n`). The spec default is `y`.

interface:binpkg_respect_user_patches_off(Options) :-
  memberchk(binpkgrespectuserpatches(Val), Options),
  memberchk(Val, [n, no, false, 'n', 'no', 'false']).


%! interface:assert_valid_style(+Style) is det.
%
% Asserts the given printing style if it is one of the known values
% (fancy, column, short). Falls back to 'fancy' with a warning otherwise.

interface:assert_valid_style(Style) :-
  memberchk(Style, ['fancy', 'column', 'short']), !,
  asserta(config:interface_printing_style(Style)).

interface:assert_valid_style(Style) :-
  format(atom(Msg), 'Unknown printing style "~w", falling back to "fancy"', [Style]),
  message:warning(Msg),
  asserta(config:interface_printing_style('fancy')).


%! interface:assert_valid_optimize(+Strategy) is det.
%
% Selects the plan ordering strategy (`--optimize`). `parallelism` is the
% default and asserts nothing; `soft-requirements` asserts
% preference:local_flag(optimize_soft_requirements), read by
% ordering:prefers/2. Unknown values warn and keep the default.

interface:assert_valid_optimize(parallelism) :- !.

interface:assert_valid_optimize('soft-requirements') :-
  !,
  asserta(preference:local_flag(optimize_soft_requirements)).

interface:assert_valid_optimize(Strategy) :-
  format(atom(Msg), 'Unknown --optimize strategy "~w", using "parallelism"', [Strategy]),
  message:warning(Msg).


%! interface:process_snapshot_flag is det.
%
% Activates snapshot mode if --snapshot was passed or config:snapshot_enabled
% is asserted. Generates an ID from timestamp if none provided.

interface:process_snapshot_flag :-
  interface:argv(Options, _),
  ( memberchk(snapshot(SnapVal), Options), SnapVal \== none
  -> ( SnapVal == true
     -> snapshot:generate_id(Id)
     ;  Id = SnapVal
     ),
     assertz(snapshot:active_id(Id))
  ;  config:snapshot_enabled
  -> snapshot:generate_id(Id),
     assertz(snapshot:active_id(Id))
  ;  true
  ).


%! interface:get_mode(-Mode) is det.
%
% Unifies Mode with the --mode value from the command line
% (standalone, client, server, or worker).

interface:get_mode(Mode) :-
  interface:argv(Options,_),
  lists:memberchk(mode(Mode),Options).


%! interface:process_continue(-Continue) is det.
%
% Determines the continuation after the dispatched action completes.
% Unifies Continue with `halt`, `prolog`, or `true` depending on mode
% and whether --shell was requested.

interface:process_continue(Continue) :-
  !,
  interface:argv(Options,_),
  interface:version(Version),
  lists:memberchk(mode(Mode),Options),

  (lists:memberchk(mode(server),Options)
   ->  message:logo(['::- portage-ng ',Version],Mode),
       Continue = true
   ;   (lists:memberchk(shell(true),Options)
        -> Continue = (message:logo(['::- portage-ng ',Version],Mode), prolog)
        ;  ( catch(daemon:running, _, fail)
           -> Continue = true
           ;  Continue = halt))).


%! interface:get_port(-Port) is det.
%
% Unifies Port with the --port value from the command line, falling back
% to config:server_port/1 if not specified.

interface:get_port(Port) :-
  interface:argv(Options,_),
  ( lists:memberchk(port(Port), Options) -> true
  ; config:server_port(Port)
  ),
  !.

%! interface:process_server(-Host, -Port) is det.
%
% Unifies Host and Port with the --host and --port values from the
% command line, falling back to config:server_host/1 and
% config:server_port/1 respectively.

interface:process_server(Host,Port) :-
  interface:argv(Options,_),
  (lists:memberchk(host(Host),  Options) ; config:server_host(Host)),
  interface:get_port(Port),
  !.


%! interface:server_reachable(+Host, +Port) is semidet.
%
% Succeeds if a TCP connection to Host:Port can be established.

interface:server_reachable(Host, Port) :-
  catch(
    ( tcp_socket(Socket),
      tcp_connect(Socket, Host:Port),
      tcp_close_socket(Socket) ),
    _, fail).


%! interface:require_tls_files(+Role, +Hostname, +CaCert, +Cert, +Key) is det.
%
% Fail with a clear message if TLS material is missing for the given Role
% (client or server). Certificate generation is kept out of runtime: use
% `make certs HOST=<hostname>`. Shared by client.pl and server.pl.

interface:require_tls_files(Role, Hostname, CaCert, Cert, Key) :-
  findall(File,
          ( member(File, [CaCert, Cert, Key]),
            \+ exists_file(File)
          ),
          Missing),
  ( Missing == []
  -> true
  ;  message:failure(['Missing TLS files for ', Role, ' mode: ', Missing, '\n',
                      'Expected CA cert:      ', CaCert, '\n',
                      'Expected ', Role, ' cert:  ', Cert, '\n',
                      'Expected ', Role, ' key:   ', Key, '\n\n',
                      'To generate them locally, run:\n',
                      '  make certs HOST=', Hostname, '\n',
                      'If your hostname includes a .local suffix, ensure HOST matches `config:hostname/1`.\n'
                     ])
  ).


%! interface:require_digest_password is det.
%
% Fail when config:digest_password/2 is missing or empty. Empty defaults
% (no Private/passwords.pl) must not be paired with a real
% Certificates/passwordfile — copy the template, set a secret, then
% `make passwordfile`.

interface:require_digest_password :-
  ( current_predicate(config:digest_password/2),
    config:digest_password(_User, Pass),
    atom(Pass), Pass \== ''
  -> true
  ;  message:failure(['Empty or missing config:digest_password/2.\n',
                      'Copy Source/Config/Private/template_passwords.pl to\n',
                      '  Source/Config/Private/passwords.pl\n',
                      'set a non-empty digest password, then run:\n',
                      '  make passwordfile\n'])
  ).


%! interface:init_tty
%
% Load a command-line editor when running on a TTY. Prefers
% library(editline) and falls back to library(readline), then
% enables persistent history. Does not call rl_wrap/el_wrap:
% GNU readline's wrap before prolog/0 leaves the toplevel blocked
% with no prompt on this SWI build.

interface:init_tty :-
  ( stream_property(user_input, tty(true)),
    stream_property(user_output, tty(true))
  -> interface:init_line_editor,
     catch(prolog_history(enable), _, true)
  ; true
  ).


%! interface:init_line_editor is det.
%
% Load library(editline) or library(readline). The library's own
% initialization wrap, when present in the QLF, is what attaches
% the editor; we do not wrap explicitly.

interface:init_line_editor :-
  catch(ensure_loaded(library('editline')), _, fail),
  !.
interface:init_line_editor :-
  catch(ensure_loaded(library('readline')), _, fail),
  !.
interface:init_line_editor.


%! interface:init_working_dir is det.
%
% Changes to the configured working directory so relative Knowledge/
% paths resolve.

interface:init_working_dir :-
  config:working_dir(Dir),
  cd(Dir).
