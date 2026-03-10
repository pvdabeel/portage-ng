/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INTERFACE
The interface interprets command line arguments passed to portage-ng and
dispatches them to the appropriate actions (merge, sync, graph, search, etc.).
It maps CLI flags declared in interface:spec/1 onto predicates that implement
each action.
*/

:- module(interface, []).

% =============================================================================
%  INTERFACE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Interface version
% -----------------------------------------------------------------------------

%! interface:version(-Version) is det.
%
% Unifies Version with the current portage-ng version string, obtained by
% executing the `version` script.

interface:version(V) :-
  script:exec('version',V).


%! interface:repo_git_version(+Dir, -Version) is det.
%
% Git date+hash for Dir, or 'unknown' when git is unavailable.

interface:repo_git_version(Dir, Version) :-
  catch(
    ( process_create(path(git),
                     ['--no-pager', log, '-1',
                      '--date=format:%Y.%m.%d', '--pretty=%cd (%h)'],
                     [stdout(pipe(Out)), stderr(null), cwd(Dir), process(Pid)]),
      call_cleanup(
        ( read_string(Out, _, Raw),
          split_string(Raw, "\n", "\n \t", [VerStr|_]),
          atom_string(Version, VerStr)
        ),
        ( close(Out), process_wait(Pid, _) )
      )
    ),
    _, Version = unknown
  ).


%! interface:print_version_repos is det.
%
% Prints registered repositories with name, git version, and path
% in aligned columns.

interface:print_version_repos :-
  findall(Name-Loc-Ver,
    ( context:instances(repository, Name),
      Name:get_location(Loc),
      interface:repo_git_version(Loc, Ver)
    ),
    Repos),
  ( Repos == []
  -> true
  ;  aggregate_all(max(L), (member(N-_-_, Repos), atom_length(N, L)), MaxN),
     aggregate_all(max(L), (member(_-_-V, Repos), atom_length(V, L)), MaxV),
     Col1 is MaxN + 4,
     Col2 is Col1 + MaxV + 2,
     forall(member(N-Loc-V, Repos),
       format('  ~w~t~*|~w~t~*|~w~n', [N, Col1, V, Col2, Loc])
     )
  ).


%! interface:print_system_info is det.
%
% Prints system information when --info is called without arguments,
% similar to emerge --info: profile, repositories, key system
% packages, and USE flags.

interface:print_system_info :-
  interface:version(Version),
  current_prolog_flag(version, PrologVer),
  format(atom(PrologVerAtom), '~w', [PrologVer]),
  ( catch(config:hostname(Hostname), _, Hostname = unknown) -> true ; Hostname = unknown ),
  ( catch(config:gentoo_profile(Profile), _, Profile = unknown) -> true ; Profile = unknown ),
  nl,
  format('portage-ng ~w (SWI-Prolog ~w, ~w)~n', [Version, PrologVerAtom, Profile]),
  format('================================================================~n'),
  format('System hostname: ~w~n', [Hostname]),
  ( catch(config:installation_dir(Dir), _, fail)
  -> format('Install dir:     ~w~n', [Dir])
  ;  true
  ),
  ( catch(config:printing_tty_size(H, W), _, fail)
  -> format('Terminal size:   ~wx~w~n', [W, H])
  ;  format('Terminal size:   (not a TTY)~n')
  ),
  nl,
  format('Repositories:~n'),
  forall(
    ( context:instances(repository, Name),
      Name:get_location(Loc)
    ),
    format('  ~w~t~30|~w~n', [Name, Loc])
  ),
  nl,
  format('World set:~n'),
  ( catch(forall(world::entry(E), format('  ~w~n', [E])), _, true)
  -> true
  ;  format('  (not loaded)~n')
  ).


%! interface:status(-Status) is det.
%
% Unifies Status with the current release stage
% (one of alpha, beta, testing, development, release).

interface:status(S) :-
  S = 'development'.


% -----------------------------------------------------------------------------
%  Interface specifications
% -----------------------------------------------------------------------------

%! interface:spec(-Specification) is det.
%
% Unifies Specification with the optparse specification list that declares
% all supported command-line flags, their types, defaults, and help texts.

interface:spec(S) :-
  config:hostname(Hostname),
  S = [[opt(mode),      type(atom),      default('standalone'),                   longflags(['mode'] ),
        help([ '  standalone: start standalone (all in memory, no server required)'
             , '  ipc:        thin IPC client, requires running daemon'
             , '  daemon:     persistent daemon, serves ipc clients via Unix socket'
             , '  client:     TCP/IP client, requires running server'
             , '  server:     start as server'
             , '  worker:     start distributed prover worker'])],
       [opt(ask),       type(boolean),   default(false),       shortflags(['a']), longflags(['ask']),       help('Ask for confirmation before proceeding')],
       [opt(alert),     type(boolean),   default(false),       shortflags(['A']), longflags(['alert']),     help('Ring terminal bell when action needs attention')],
       [opt(verbose),   type(boolean),   default(false),       shortflags(['v']), longflags(['verbose']),   help('Turn on verbose mode')],
       [opt(pretend),   type(boolean),   default(false),       shortflags(['p']), longflags(['pretend']),   help('Turn on pretend mode')],
       [opt(fetchonly), type(boolean),   default(false),       shortflags(['f']), longflags(['fetchonly']), help('Turn on fetchonly mode')],
       [opt(fetchall),  type(boolean),   default(false),       shortflags(['F']), longflags(['fetch-all-uri']),help('Fetch all SRC_URI files regardless of USE flags')],
       [opt(merge),     type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),    type(boolean),   default(false),       shortflags(['u']), longflags(['update']),    help('Update target package')],
       [opt(upgrade),   type(boolean),   default(false),                          longflags(['upgrade']),   help('Upgrade set (default: @world): first compute a fresh plan under --emptytree, then run depclean')],
       [opt(deep),      type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(emptytree), type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg),  type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),  help('Create binary packages after building from source')],
       [opt(buildpkgonly),type(boolean), default(false),       shortflags(['B']), longflags(['buildpkgonly']),help('Build binary packages but do not merge to live filesystem')],
       [opt(build),     type(boolean),   default(false),                          longflags(['build']),     help('Build target (print plan then execute with live progress)')],
       [opt(resume),    type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),    type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),    help('Rebuild if USE or IUSE changed since install')],
       [opt(changeduse),type(boolean),   default(false),       shortflags(['U']), longflags(['changed-use']),help('Rebuild only if effective USE flags changed')],
       [opt(changeddeps),type(boolean),  default(false),                          longflags(['changed-deps']),help('Rebuild if runtime dependencies changed since install')],
       [opt(changedslot),type(boolean),  default(false),                          longflags(['changed-slot']),help('Rebuild if SLOT changed since install')],
       [opt(selective), type(boolean),   default(false),                          longflags(['selective']), help('Do not reinstall already-installed packages')],
       [opt(select),    type(boolean),   default(true),                           longflags(['select']),    help('Add targets to world set (inverse of --oneshot)')],
       [opt(deselect),  type(boolean),   default(false),                          longflags(['deselect']),  help('Remove targets from world set without unmerging')],
       [opt(noreplace), type(boolean),   default(false),       shortflags(['n']), longflags(['noreplace']), help('Skip already-installed packages')],
       [opt(nodeps),    type(boolean),   default(false),       shortflags(['O']), longflags(['nodeps']),    help('Merge without resolving dependencies')],
       [opt(onlydeps),  type(boolean),   default(false),       shortflags(['o']), longflags(['onlydeps']),  help('Only merge dependencies, not the target itself')],
       [opt(withbdeps), type(atom),      default(y),                              longflags(['with-bdeps']),help('Include build-time dependencies (y or n)')],
       [opt(withtestdeps),type(atom),    default(n),                              longflags(['with-test-deps']),help('Include test dependencies (y or n)')],
       [opt(dynamicdeps),type(boolean),  default(true),                           longflags(['dynamic-deps']),help('Use repo dependency info instead of installed VDB')],
       [opt(rebuildnewrev),type(boolean),default(false),                          longflags(['rebuild-if-new-rev']),help('Rebuild packages with new revision')],
       [opt(rebuildnewver),type(boolean),default(false),                          longflags(['rebuild-if-new-ver']),help('Rebuild packages with new version available')],
       [opt(rebuildnewslot),type(boolean),default(false),                         longflags(['rebuild-if-new-slot']),help('Rebuild packages when slot operator deps change')],
       [opt(rebuildunbuilt),type(boolean),default(false),                         longflags(['rebuild-if-unbuilt']),help('Rebuild deps that have been rebuilt from source')],
       [opt(updateifinstalled),type(boolean),default(false),                      longflags(['update-if-installed']),help('Like --update but only for already-installed packages')],
       [opt(exclude),   type(atom),      default(''),                             longflags(['exclude']),   help('Exclude atoms from merge (repeatable)')],
       [opt(skip),      type(atom),      default(''),                             longflags(['skip']),     help('Skip packages during --resume (repeatable)')],
       [opt(oneshot),   type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),    type(atom),      default('/'),                            longflags(['prefix']),    help('Set the prefix directory')],
       [opt(style),     type(atom),      default('fancy'),                        longflags(['style']),     help('Set the printing style: fancy, column or short')],
       [opt(sync),      type(boolean),   default(false),                          longflags(['sync']),      help('Sync repository. Optional args: repository names (e.g. portage, pkg, overlay)')],
       [opt(clear),     type(boolean),   default(false),                          longflags(['clear']),     help('Clear knowledge base')],
       [opt(regen),     type(boolean),   default(false),                          longflags(['regen']),     help('Regenerate the ebuild metadata cache (no network sync)')],
       [opt(metadata),  type(boolean),   default(false),                          longflags(['metadata']), help('Regenerate the ebuild metadata cache (alias for --regen)')],
       [opt(listsets),  type(boolean),   default(false),                          longflags(['list-sets']),help('List available package sets')],
       [opt(graph),     type(boolean),   default(false),                          longflags(['graph']),     help('Create graph. Args: "modified"|"full"|"build"|"build modified"|"build full".')],
       [opt(checknews), type(boolean),   default(false),                          longflags(['check-news']),help('Check for and display unread news items')],
       [opt(readnews),  type(boolean),   default(false),                          longflags(['read-news']),help('Display news items when using --ask')],
       [opt(depclean),  type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),      type(boolean),   default(false),       shortflags(['i']), longflags(['info']),      help('Show package version')],
       [opt(bugs),      type(boolean),   default(false),                          longflags(['bugs']),      help('Print bug report drafts (Gentoo Bugzilla) for the given target, without printing a plan')],
       [opt(search),    type(boolean),   default(false),       shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),   type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),    type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),    help('Use binary packages when available, fall back to source')],
       [opt(usepkgonly),type(boolean),  default(false),       shortflags(['K']), longflags(['usepkg-only']),help('Use only binary packages, fail if unavailable')],
       [opt(getbinpkg), type(boolean),  default(false),       shortflags(['g']), longflags(['getbinpkg']), help('Download binary packages from BINHOST')],
       [opt(getbinpkgonly),type(boolean),default(false),      shortflags(['G']), longflags(['getbinpkg-only']),help('Use only remote binary packages from BINHOST')],
       [opt(usepkgexclude),type(atom),  default(''),                             longflags(['usepkg-exclude']),help('Exclude atoms from binary package usage (repeatable)')],
       [opt(usepkginclude),type(atom),  default(''),                             longflags(['usepkg-include']),help('Force binary package usage for specific atoms (repeatable)')],
       [opt(usepkgexcludelive),type(boolean),default(false),                     longflags(['usepkg-exclude-live']),help('Do not use binary packages for live (9999) ebuilds')],
       [opt(binpkgchangeddeps),type(boolean),default(false),                     longflags(['binpkg-changed-deps']),help('Ignore binpkgs whose deps have changed since build')],
       [opt(binpkgrespectuse),type(boolean),default(false),                      longflags(['binpkg-respect-use']),help('Ignore binpkgs whose USE flags do not match')],
       [opt(rebuiltbinaries),type(boolean),default(false),                       longflags(['rebuilt-binaries']),help('Replace installed packages with rebuilt binary packages')],
       [opt(failclean), type(boolean),   default(false),                          longflags(['fail-clean']),help('Clean build directory on failure')],
       [opt(quiet),     type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(jobs),      type(integer),   default(0),           shortflags(['j']), longflags(['jobs']),      help('Number of parallel build jobs (0 = auto-detect)')],
       [opt(loadavg),   type(float),     default(0.0),                            longflags(['load-average']),help('Do not start new jobs if load average exceeds N (0 = no limit)')],
       [opt(color),     type(atom),      default(y),                              longflags(['color']),     help('Enable or disable color output (y or n)')],
       [opt(timeout),   type(integer),   default(0),                              longflags(['timeout']),   help('Abort proving/planning after N seconds (0 = no limit)')],
       [opt(variants),  type(atom),      default(none),                           longflags(['variants']),  help('Show alternative plans (none, auto, all, or comma-separated USE flags)')],
       [opt(host),      type(atom),      default(Hostname),                       longflags(['host']),      help('Set server hostname (client mode)')],
       [opt(port),      type(integer),   default(4000),                           longflags(['port']),      help('Set Server port (client or server mode)')],
       [opt(shell),     type(boolean),   default(false),                          longflags(['shell']),     help('Go to shell')],
       [opt(save),      type(boolean),   default(false),                          longflags(['save']),      help('Save knowledgebase (only relevant in client mode')],
       [opt(load),      type(boolean),   default(false),                          longflags(['load']),      help('Load knowledgebase (only relevant in client mode)')],
       [opt(version),   type(boolean),   default(false),       shortflags(['V']), longflags(['version']),   help('Show version')],

       % snapshot and rollback

       [opt(snapshot),  type(atom),      default(none),                           longflags(['snapshot']),  help('Create snapshot before merge (optional ID, auto-generated if omitted)')],
       [opt(rollback),  type(atom),      default(none),                           longflags(['rollback']),  help('Rollback to a named snapshot')],
       [opt(snapshots), type(boolean),   default(false),                          longflags(['snapshots']), help('List available snapshots')],

       % LLM interaction (requires LLM modules)

       [opt(explain),   type(atom),      default(none),                           longflags(['explain']),   help('Explain the build plan via LLM (optionally pass a question)')],
       [opt(llm),       type(atom),      default(none),                           longflags(['llm']),       help('Start interactive chat with an LLM (optionally specify service name)')],

       % upstream version checking

       [opt(upstream),  type(boolean),   default(false),                          longflags(['upstream']),  help('Check upstream for newer package versions')],

       % VDB queries (Paludis cave-style)

       [opt(contents),    type(boolean), default(false),                          longflags(['contents']),    help('List files installed by a package')],
       [opt(owner),       type(boolean), default(false),                          longflags(['owner']),       help('Find which package owns a file')],
       [opt(pkgsize),     type(boolean), default(false),                          longflags(['size']),        help('Show disk space used by an installed package')],
       [opt(verify),      type(boolean), default(false),                          longflags(['verify']),      help('Verify installed package files against recorded checksums')],
       [opt(executables), type(boolean), default(false),                          longflags(['executables']), help('Show executables provided by a package')],

       % maintenance

       [opt(fixlinkage),  type(boolean), default(false),                          longflags(['fix-linkage']), help('Rebuild packages with broken shared library linkage')],
       [opt(report),      type(boolean), default(false),                          longflags(['report']),      help('Report problems with installed packages')],
       [opt(rdeps),       type(boolean), default(false),                          longflags(['rdeps']),       help('Show reverse dependencies of a package')],
       [opt(unuseddistfiles), type(boolean), default(false),                      longflags(['unused-distfiles']), help('List distfiles not used by any installed package')],

       % resolver hints

       [opt(continuefailure), type(atom), default(never),                         longflags(['continue-on-failure']), help('Continue after build failure: never, if-satisfied, if-independent, always')],
       [opt(favour),      type(atom),    default(''),                             longflags(['favour']),      help('Favour package in || dep choices (repeatable)')],
       [opt(avoid),       type(atom),    default(''),                             longflags(['avoid']),       help('Avoid package in || dep choices (repeatable)')],
       [opt(showdescriptions), type(atom), default(none),                         longflags(['show-descriptions']), help('Show USE flag descriptions: none, new, all')],
       [opt(permitdowngrade), type(boolean), default(false),                      longflags(['permit-downgrade']), help('Allow the resolver to pick older package versions')],
       [opt(presetpkg),   type(atom),    default(''),                             longflags(['preset']),      help('Pin a specific version: --preset =cat/pkg-ver (repeatable)')],
       [opt(hidepkg),     type(atom),    default(''),                             longflags(['hide']),        help('Exclude packages/repos from resolution (repeatable)')],
       [opt(earlypkg),    type(atom),    default(''),                             longflags(['early']),       help('Order matching packages earlier in the plan (repeatable)')],
       [opt(latepkg),     type(atom),    default(''),                             longflags(['late']),        help('Order matching packages later in the plan (repeatable)')],

       % convenience presets

       [opt(lazy),        type(boolean), default(false),                          longflags(['lazy']),        help('Minimal work: skip installed, no deep deps')],
       [opt(complete),    type(boolean), default(false),                          longflags(['complete']),    help('Full update: deep, newuse, follow build deps')],
       [opt(everything),  type(boolean), default(false),                          longflags(['everything']),  help('Reinstall everything: emptytree + deep')],

       % lifecycle management

       [opt(background),type(boolean),   default(false),                          longflags(['background']),help('Fork to background (daemon and server modes)')],
       [opt(status),    type(boolean),   default(false),                          longflags(['status']),    help('Check if daemon/server is running (ipc and client modes)')],
       [opt(cmd),       type(atom),      default(none),                           longflags(['cmd']),       help('Send command to daemon/server: halt or relaunch (ipc and client modes)')],

       % build options

       [opt(logs),      type(boolean),   default(false),       shortflags(['l']), longflags(['logs']),      help('Show build log paths in --build output')],

       % debugging purposes

       [opt(ci),        type(boolean),   default(false),                          longflags(['ci']),        help('CI mode: non-interactive, fail with nonzero exit code on assumptions')]
      ].


% -----------------------------------------------------------------------------
%  Command line reading
% -----------------------------------------------------------------------------

%! interface:argv(-Options, -Args) is det.
%
% Parses and caches the command-line arguments. Options is a list of
% opt(Value) terms matching the spec; Args is the list of positional
% (non-option) arguments. Results are memoised in interface:argv_/2.

:- dynamic interface:argv_/2.

intarface:argv(Options,Args) :-
  interface:argv_(Options,Args),!.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(opt_arguments(S,Options,Args),_,true),
  assertz(interface:argv_(Options,Args)).


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


% -----------------------------------------------------------------------------
%  Option handling
% -----------------------------------------------------------------------------

%! interface:process_flags is det.
%
% Translates boolean CLI flags into runtime preference assertions
% (e.g. --deep asserts preference:local_flag(deep)) and sets
% config overrides for verbose mode and printing style.

interface:process_flags:-
  interface:argv(Options,_),
  (lists:memberchk(deep(true),      Options) -> asserta(preference:local_flag(deep))            ; true),
  (lists:memberchk(emptytree(true), Options) -> asserta(preference:local_flag(emptytree))       ; true),
  (lists:memberchk(depclean(true),  Options) -> asserta(preference:local_flag(depclean))        ; true),
  (lists:memberchk(newuse(true),    Options) -> asserta(preference:local_flag(newuse))          ; true),
  (lists:memberchk(changeduse(true),Options) -> asserta(preference:local_flag(changeduse))      ; true),
  (lists:memberchk(changeddeps(true),Options)-> asserta(preference:local_flag(changeddeps))     ; true),
  (lists:memberchk(changedslot(true),Options)-> asserta(preference:local_flag(changedslot))     ; true),
  (lists:memberchk(selective(true),Options) -> asserta(preference:local_flag(selective))        ; true),
  (lists:memberchk(noreplace(true),Options) -> asserta(preference:local_flag(noreplace))       ; true),
  (lists:memberchk(nodeps(true),   Options) -> asserta(preference:local_flag(nodeps))           ; true),
  (lists:memberchk(onlydeps(true), Options) -> asserta(preference:local_flag(onlydeps))        ; true),
  (lists:memberchk(dynamicdeps(false),Options)-> asserta(preference:local_flag(nodynamicdeps)) ; true),
  (lists:memberchk(rebuildnewrev(true),Options)-> asserta(preference:local_flag(rebuildnewrev)); true),
  (lists:memberchk(rebuildnewver(true),Options)-> asserta(preference:local_flag(rebuildnewver)); true),
  (lists:memberchk(rebuildnewslot(true),Options)->asserta(preference:local_flag(rebuildnewslot));true),
  (lists:memberchk(rebuildunbuilt(true),Options)->asserta(preference:local_flag(rebuildunbuilt));true),
  (lists:memberchk(updateifinstalled(true),Options)->asserta(preference:local_flag(updateifinstalled));true),
  (lists:memberchk(readnews(true), Options) -> asserta(preference:local_flag(readnews))        ; true),
  (lists:memberchk(withbdeps(n),   Options) -> asserta(preference:local_flag(nobdeps))          ; true),
  (lists:memberchk(withtestdeps(y),Options) -> asserta(preference:local_flag(withtestdeps))    ; true),
  (lists:memberchk(pretend(true),   Options) -> asserta(preference:local_flag(pretend))         ; true),
  (lists:memberchk(oneshot(true),   Options) -> asserta(preference:local_flag(oneshot))         ; true),
  (lists:memberchk(select(false),   Options) -> asserta(preference:local_flag(oneshot))         ; true),
  (lists:memberchk(buildpkg(true), Options) -> asserta(preference:local_flag(buildpkg))        ; true),
  (lists:memberchk(buildpkgonly(true),Options)->asserta(preference:local_flag(buildpkgonly))  ; true),
  (lists:memberchk(usepkg(true),    Options) -> asserta(preference:local_flag(usepkg))        ; true),
  (lists:memberchk(usepkgonly(true),Options) -> asserta(preference:local_flag(usepkgonly))    ; true),
  (lists:memberchk(getbinpkg(true), Options) -> asserta(preference:local_flag(getbinpkg))     ; true),
  (lists:memberchk(getbinpkgonly(true),Options)->asserta(preference:local_flag(getbinpkgonly)); true),
  (lists:memberchk(fetchall(true),  Options) -> asserta(preference:local_flag(fetchall))      ; true),
  (lists:memberchk(failclean(true), Options) -> asserta(preference:local_flag(failclean))     ; true),
  (lists:memberchk(usepkgexcludelive(true),Options)->asserta(preference:local_flag(usepkgexcludelive));true),
  (lists:memberchk(binpkgchangeddeps(true),Options)->asserta(preference:local_flag(binpkgchangeddeps));true),
  (lists:memberchk(binpkgrespectuse(true),Options)->asserta(preference:local_flag(binpkgrespectuse));true),
  (lists:memberchk(rebuiltbinaries(true),Options)->asserta(preference:local_flag(rebuiltbinaries));true),
  (lists:memberchk(ask(true),      Options) -> asserta(preference:local_flag(ask))              ; true),
  (lists:memberchk(alert(true),    Options) -> asserta(preference:local_flag(alert))            ; true),
  (lists:memberchk(verbose(true),   Options) -> asserta(config:verbose(true))                   ; true),
  (lists:memberchk(logs(true),     Options) -> asserta(config:show_build_logs(true))            ; true),
  (lists:memberchk(style(Style),    Options) -> asserta(config:interface_printing_style(Style)) ; true),
  ((lists:memberchk(jobs(J),       Options), J > 0) -> asserta(config:cli_jobs(J))              ; true),
  ((lists:memberchk(loadavg(L),    Options), L > 0.0) -> asserta(config:cli_load_average(L))    ; true),
  (lists:memberchk(permitdowngrade(true),Options)->asserta(preference:local_flag(permitdowngrade));true),
  (lists:memberchk(color(n),       Options) -> retractall(config:color_output)                  ; true),
  (lists:memberchk(showdescriptions(SD),Options), SD \== none
                                           -> asserta(config:show_use_descriptions(SD))         ; true),
  (lists:memberchk(continuefailure(CF),Options), CF \== never
                                           -> asserta(config:continue_on_failure(CF))            ; true),
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


%! interface:process_mode(-Mode) is det.
%
% Unifies Mode with the --mode value from the command line
% (standalone, client, server, or worker).

interface:process_mode(Mode) :-
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
        -> message:logo(['::- portage-ng ',Version],Mode),
           Continue = prolog
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


%! interface:init_tty
%
% Initialize TTY-related features (editline, history). Safe to call when
% stdout is redirected; silently skips when not on a real terminal.

interface:init_tty :-
  ( stream_property(user_input, tty(true)),
    stream_property(user_output, tty(true))
  -> ensure_loaded(library('editline')),
     catch(prolog_history(enable), _, true)
  ; true
  ).


%! interface:process_requests(+Mode) is det.
%
% Main dispatch. Processes the parsed command-line options and maps each
% recognised flag (--sync, --graph, --merge, etc.) onto the corresponding
% action predicate. Falls through to halt(1) if no action matches.

interface:process_requests(server) :-
  !, prolog.

interface:process_requests(daemon) :-
  !, prolog.

interface:process_requests(worker) :-
  !, prolog.

interface:process_requests(Mode) :-
  interface:version(Version),

  interface:process_flags,
  interface:process_continue(Continue),
  interface:argv(Options,Args),

  message:log(['Args:      ',Args]),
  message:log(['Options:   ',Options]),

  set_prolog_flag(toplevel_prompt,'~m~d~l?- '),

  ( memberchk(snapshots(true),Options) -> (snapshot:list,                                           Continue) ;
    memberchk(rollback(RollbackId),Options), RollbackId \== none
                                       -> (interface:process_rollback(RollbackId, Options),          Continue) ;
    memberchk(version(true),Options)  -> (message:logo(['::- portage-ng ',Version]),
                                         interface:print_version_repos,             Continue) ;
    memberchk(info(true),Options)     -> (interface:process_action(info,Args,Options),              Continue) ;
    memberchk(bugs(true),Options)     -> (interface:process_bugs(Args,Options),                     Continue) ;
    memberchk(clear(true),Options)    -> (kb:clear, 						    Continue) ;
    memberchk(graph(true),Options)    -> (interface:process_graph(Args), nl, 				  	    Continue) ;
    memberchk(deselect(true),Options) -> (interface:process_deselect(Args),                       Continue) ;
    memberchk(unmerge(true),Options)  -> (interface:process_action(uninstall,Args,Options), 	    Continue) ;
    memberchk(depclean(true),Options) -> (interface:process_action(depclean,Args,Options),         Continue) ;
    memberchk(upgrade(true),Options)  -> (interface:process_upgrade(Args,Options),                 Continue) ;
    % For a single target, Portage-style update behaves like a normal merge:
    % resolve full runtime closure and perform a transactional replace if needed.
    % In portage-ng the "full closure" corresponds to proving :run.
    memberchk(update(true),Options)   -> (interface:process_action(run,Args,Options),               Continue) ;
    memberchk(search(true),Options)   -> (interface:process_action(search,Args,Options),            Continue) ;
    memberchk(listsets(true),Options) -> (interface:process_list_sets,                              Continue) ;
    memberchk(checknews(true),Options)-> (news:check,                                              Continue) ;
    memberchk(readnews(true),Options) -> (news:check,                                              Continue) ;
    memberchk(regen(true),Options)   -> (interface:process_regen(Mode, Args),!,                    Continue) ;
    memberchk(metadata(true),Options)-> (interface:process_regen(Mode, Args),!,                    Continue) ;
    memberchk(sync(true),Options)     -> (interface:process_sync(Mode, Args),!,                    Continue) ;
    memberchk(save(true),Options)     -> (kb:save,!, 						    Continue) ;
    memberchk(load(true),Options)     -> (kb:load,!, 						    Continue) ;
    memberchk(fetchonly(true),Options)-> (interface:process_action(fetchonly,Args,Options),         Continue) ;
    memberchk(resume(true),Options)  -> (interface:assert_resume_skip_args(Args),
                                         builder:build_resume,                                     Continue) ;
    memberchk(build(true),Options)   -> (interface:process_build(Args,Options),                    Continue) ;
    memberchk(contents(true),Options) -> (interface:process_vdb_query(contents,Args),              Continue) ;
    memberchk(owner(true),Options)   -> (interface:process_vdb_query(owner,Args),                 Continue) ;
    memberchk(pkgsize(true),Options) -> (interface:process_vdb_query(size,Args),                  Continue) ;
    memberchk(verify(true),Options)  -> (interface:process_vdb_query(verify,Args),                Continue) ;
    memberchk(executables(true),Options) -> (interface:process_vdb_query(executables,Args),       Continue) ;
    memberchk(fixlinkage(true),Options) -> (interface:process_fix_linkage(Args,Options),          Continue) ;
    memberchk(report(true),Options)  -> (interface:process_report(Options),                       Continue) ;
    memberchk(rdeps(true),Options)   -> (interface:process_rdeps(Args),                           Continue) ;
    memberchk(unuseddistfiles(true),Options) -> (interface:process_unused_distfiles(Options),     Continue) ;
    memberchk(upstream(true),Options) -> (interface:process_upstream(Args,Options),                 Continue) ;
    interface:extract_llm_opt(Options, LlmOpt)
                                      -> (interface:process_llm_chat(LlmOpt),                      Continue) ;
    memberchk(merge(true),Options)    -> (interface:process_action(run,Args,Options),               Continue) ;
    memberchk(shell(true),Options)    -> (message:logo(['::- portage-ng shell - ',Version]),	    prolog)),

  Continue.

interface:process_requests(_) :-
  ( catch(daemon:running, _, fail)
  -> true
  ;  halt(1)
  ).

% -----------------------------------------------------------------------------
%  Action: GRAPH (optional mode argument)
% -----------------------------------------------------------------------------

%! interface:process_graph(+Args) is det.
%
% Dispatches --graph with optional positional arguments:
%   --graph                 uses config:graph_modified_only/1
%   --graph modified        overrides to modified-only for this run
%   --graph full            overrides to graph everything for this run
%   --graph build           graph + builder test (download + safe phases)
%   --graph build modified  graph modified + builder test
%   --graph build full      graph full + builder test

interface:process_graph([]) :-
  kb:graph,
  !.
interface:process_graph([modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
interface:process_graph([full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  !.
interface:process_graph([build]) :-
  kb:graph,
  builder:test_stats(portage),
  !.
interface:process_graph([build, modified]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(true)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  builder:test_stats(portage),
  !.
interface:process_graph([build, full]) :-
  setup_call_cleanup(
    asserta(config:interface_graph_modified_only(false)),
    kb:graph,
    retractall(config:interface_graph_modified_only(_))
  ),
  builder:test_stats(portage),
  !.
interface:process_graph(Args) :-
  message:warning(['--graph: ignoring unexpected args: ', Args]),
  kb:graph.


% -----------------------------------------------------------------------------
%  Action: LIST-SETS
% -----------------------------------------------------------------------------

%! interface:process_list_sets is det.
%
% Lists all available package sets (@world, @system, user-defined sets).

interface:process_list_sets :-
  message:topheader(['Available package sets']),
  nl,
  message:color(green), format(' * '), message:color(normal),
  format('world~n'),
  forall(preference:set(Name, _),
    ( message:color(green), format(' * '), message:color(normal),
      format('~w~n', [Name])
    )).


% -----------------------------------------------------------------------------
%  Action: SYNC (optional repository selection)
% -----------------------------------------------------------------------------

%! interface:process_sync(+Mode, +RepoNames) is det.
%
% Dispatches --sync with optional repository name arguments:
%   --sync                       sync all registered repositories + save kb
%   --sync portage               sync only the portage repository + save kb
%   --sync portage overlay       sync portage and overlay repositories + save kb
%
% In standalone mode the knowledge base is saved to disk after syncing.

interface:process_sync(Mode, []) :-
  !,
  kb:sync,
  catch(profile:cache_save, _, true),
  ( Mode == standalone -> kb:save ; true ).

interface:process_sync(Mode, RepoNames) :-
  forall(member(Name, RepoNames),
         kb:sync(Name)),
  catch(profile:cache_save, _, true),
  ( Mode == standalone -> kb:save ; true ).


% -----------------------------------------------------------------------------
%  Action: REGEN (regenerate metadata cache, no network sync)
% -----------------------------------------------------------------------------

%! interface:process_regen(+Mode, +RepoNames) is det.
%
% Regenerates the ebuild metadata cache (md5-cache on disk) without
% performing a network sync (no git pull) or reloading into the
% knowledge base. This is the equivalent of running egencache.
% The knowledge base is updated on the next --sync or restart.

interface:process_regen(_Mode, []) :-
  !,
  aggregate_all(count, kb:repository(_), Count),
  ( Count == 1 ->
    message:topheader(['Regenerating metadata for ',Count,' registered repository'])
  ; message:topheader(['Regenerating metadata for ',Count,' registered repositories'])
  ),
  forall(kb:repository(Repository),
    ( message:header(['Regenerating metadata for \"',Repository,'\"']), nl,
      ( catch(Repository:sync(metadata), _, true) -> true ; true )
    )).

interface:process_regen(_Mode, RepoNames) :-
  forall(member(Name, RepoNames),
    ( kb:repository(Name) ->
      ( message:header(['Regenerating metadata for \"',Name,'\"']), nl,
        ( catch(Name:sync(metadata), _, true) -> true ; true )
      )
    ; message:failure(['Unknown repository: ', Name]),
      fail
    )).


% -----------------------------------------------------------------------------
%  Action: UPGRADE (emptytree + depclean, two-phase)
% -----------------------------------------------------------------------------

%! interface:process_upgrade(+ArgsSets, +Options) is det.
%
% Two-phase Portage-like upgrade:
%   Phase A: compute a fresh plan under --emptytree (ignores installed shortcuts)
%   Phase B: run depclean on the real installed graph
%
% Defaults to @world when no positional arguments are given.
% Enforces --oneshot semantics so @world is not modified.

interface:process_upgrade(ArgsSets0, Options) :-
  % Default roots: @world when no args are provided (Portage-like)
  ( ArgsSets0 == [] -> ArgsSets = [world] ; ArgsSets = ArgsSets0 ),
  setup_call_cleanup(
    ( asserta(preference:local_flag(oneshot)),
      asserta(preference:local_flag(emptytree))
    ),
    interface:process_action(run, ArgsSets, Options),
    ( retractall(preference:local_flag(emptytree)),
      retractall(preference:local_flag(oneshot))
    )
  ),
  % Cleanup phase on the real VDB graph (depclean internally asserts local_flag(depclean))
  interface:process_action(depclean, ArgsSets, Options).


% -----------------------------------------------------------------------------
%  Action: BUG REPORT DRAFTS
% -----------------------------------------------------------------------------

%! interface:process_bugs(+ArgsSets, +Options) is det.
%
% Proves the given targets and prints only the domain-assumption bug report
% drafts (Gentoo Bugzilla style), without rendering the full plan.
%
% Example: Source/Scripts/Wrapper/portage-ng-dev --mode standalone --bugs ghc

interface:process_bugs([], _Options) :-
  !,
  message:inform('Need more arguments').

interface:process_bugs(ArgsSets, Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  eapi:substitute_sets(ArgsSets,Args),
  % Use Action=run to match normal merge planning semantics (install+run deps).
  findall(R://E:run?{[]}, ( member(Arg,Args),
                           atom_codes(Arg,Codes),
                           phrase(eapi:qualified_target(Q),Codes),
                           once(kb:query(Q,R://E))
                         ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  ( Proposal == [] ->
      message:inform('No matching target found'),
      !
  ; true
  ),
  ( Mode == 'client' ->
      client:rpc_execute(Host,Port,
        ( prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
          interface:print_bugreport_drafts_from_proof(ProofAVL)
        ),
        Output),
      writeln(Output)
  ; % standalone / server-side execution
    prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
    interface:print_bugreport_drafts_from_proof(ProofAVL),
    % In --bugs mode we do not sync and we do not touch world.
    ( memberchk(ci(true), Options) ->
        halt(0)
    ; true
    )
  ).

%! interface:print_bugreport_drafts_from_proof(+ProofAVL) is det.
%
% Extracts domain assumptions from the proof AVL and delegates to
% warning:print_bugreport_drafts/1. Prints "(none)" when clean.

interface:print_bugreport_drafts_from_proof(ProofAVL) :-
  findall(Content, assoc:gen_assoc(rule(assumed(Content)), ProofAVL, _), DomainAssumptions0),
  sort(DomainAssumptions0, DomainAssumptions),
  ( DomainAssumptions == [] ->
      message:header('Bug report drafts (Gentoo Bugzilla)'),
      nl,
      writeln('  (none)')
  ; warning:print_bugreport_drafts(DomainAssumptions)
  ).


% -----------------------------------------------------------------------------
%  Action processing
% -----------------------------------------------------------------------------

%! interface:process_action(+Action, +Args, +Options) is det.
%
% Dispatches a concrete CLI action. Action is one of info, search,
% depclean, uninstall, fetchonly, or run (merge). Args are the positional
% target arguments; Options is the full parsed option list.

% -----------------------------------------------------------------------------
%  Action: INFO
% -----------------------------------------------------------------------------

interface:process_action(info,[],_) :-
  !,
  interface:print_system_info.

interface:process_action(info,Args,_Options) :-
  !,
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( phrase(eapi:qualified_target(Q), Codes),
        once(kb:query(Q, R://E))
      -> info:print_entry(R://E)
      ; message:warning(['Package not found: ', Arg])
      )
    )).


% -----------------------------------------------------------------------------
%  Action: SEARCH
% -----------------------------------------------------------------------------

interface:process_action(search,[],_) :-
  !,
  message:failure('Usage: portage-ng --search key=value ... (e.g. name=gcc, category=sys-devel, description=*compiler*)').

interface:process_action(search,Args,_Options) :-
  !,
  ( phrase(eapi:query(Q), Args)
  -> message:log(['Query:   ',Q]),
     aggregate_all(count, kb:query(Q, _), Count),
     forall(kb:query(Q, R://E), writeln(R://E)),
     ( Count =:= 0
     -> message:inform('No matching packages found.')
     ;  true
     )
  ; message:warning(['Invalid search query: ', Args])
  ).

% -----------------------------------------------------------------------------
%  Action: DEPCLEAN
% -----------------------------------------------------------------------------

interface:process_action(depclean, ArgsSets, _Options) :-
  !,
  depclean:run(ArgsSets).


% -----------------------------------------------------------------------------
%  Action: MERGE
% -----------------------------------------------------------------------------

interface:process_action(_Action,[],_) :-
  !,
  message:failure('No targets specified.').

interface:process_action(Action,ArgsSets,Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  ( memberchk(pretend(true), Options) -> PretendMode = true ; PretendMode = false ),
  eapi:substitute_sets(ArgsSets,Args),
  interface:report_unresolvable_targets(Action, Args),
  findall(target(Q,Arg):Action?{[]},
          ( member(Arg,Args),
            atom_codes(Arg,Codes),
            phrase(eapi:qualified_target(Q),Codes),
            ( Action == uninstall
              -> once((kb:query(Q, R0://E0), kb:query(installed(true), R0://E0)))
              ;  once(kb:query(Q, _R://_E))
            )
          ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  (Proposal == []
   -> ( config:llm_support(Prompt),
        atomic_list_concat([Prompt|Args],Message),
        config:llm_default(Service),
        explainer:call_llm(Service, Message, _),
        fail )
   ;  true),
  (Mode == 'client' ->
    (client:rpc_execute(Host,Port,
     (pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers),
      printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
      ( PretendMode == false -> vdb:sync ; true )),
     Output),
     writeln(Output));
    ( ( memberchk(timeout(TimeLimitSec), Options) -> true ; TimeLimitSec = 0 ),
      ( memberchk(variants(VariantsOpt), Options) -> true ; VariantsOpt = none ),
      ( memberchk(explain(ExplainOpt), Options) -> true ; ExplainOpt = none ),
      ( TimeLimitSec =< 0 ->
          ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, FallbackUsed),
            printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
            ( VariantsOpt \== none, PretendMode == true
            -> interface:run_variants(VariantsOpt, Proposal, ProofAVL, Plan, Triggers)
            ;  true
            ),
            ( ExplainOpt \== none, PretendMode == true
            -> interface:run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, Triggers)
            ;  true
            )
          )
      ; catch(
          call_with_time_limit(TimeLimitSec,
            ( pipeline:prove_plan_with_fallback(Proposal, ProofAVL, ModelAVL, Plan, Triggers, FallbackUsed),
              printer:print(Proposal,ModelAVL,ProofAVL,Plan,Triggers),
              ( VariantsOpt \== none, PretendMode == true
              -> interface:run_variants(VariantsOpt, Proposal, ProofAVL, Plan, Triggers)
              ;  true
              ),
              ( ExplainOpt \== none, PretendMode == true
              -> interface:run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, Triggers)
              ;  true
              )
            )),
          time_limit_exceeded,
          ( message:bubble(red,'Error'),
            message:color(red),
            message:print(' Time limit exceeded while proving/planning. Try increasing --timeout or narrowing the target.'), nl,
            message:color(normal),
            flush_output,
            halt(1)
          )
        )
      ),
      ( memberchk(ci(true), Options) ->
          interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode),
          halt(ExitCode)
      ; FallbackUsed == false,
        PretendMode == false ->
          vdb:sync
      ; true
      ),
      ( FallbackUsed == false,
        PretendMode == false ->
            interface:execute_world_actions_from_plan(Plan),
            world:save
        ; true
        )
    )).


% -----------------------------------------------------------------------------
%  Target validation helper
% -----------------------------------------------------------------------------

%! interface:report_unresolvable_targets(+Action, +Args) is det.
%
% Prints a warning for each target argument that cannot be parsed
% or has no matching entry in the knowledge base.

interface:report_unresolvable_targets(Action, Args) :-
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( \+ phrase(eapi:qualified_target(_), Codes)
      -> message:warning(['Cannot parse target: ', Arg])
      ; phrase(eapi:qualified_target(Q), Codes),
        ( Action == uninstall
        -> ( once((kb:query(Q, R0://E0), kb:query(installed(true), R0://E0)))
           -> true
           ;  message:warning(['Not installed: ', Arg])
           )
        ; ( once(kb:query(Q, _R://_E))
          -> true
          ;  message:warning(['Package not found: ', Arg])
          )
        )
      )
    )).


% -----------------------------------------------------------------------------
%  Action: VARIANTS (multi-variant pretend)
% -----------------------------------------------------------------------------

%! interface:run_variants(+VariantsOpt, +Proposal, +BaseProof, +BasePlan, +BaseTriggers) is det.
%
% Detects pivot points and proves variant plans in parallel, then
% prints each variant sequentially with a diff summary.

interface:run_variants(VariantsOpt, Proposal, BaseProof, BasePlan, _BaseTriggers) :-
  variant:plan_entries(BasePlan, BaseEntries),
  interface:build_variant_specs(VariantsOpt, Proposal, BaseProof, Specs),
  ( Specs == []
  -> message:inform('No variant pivot points detected.')
  ;  length(Specs, N),
     nl,
     message:color(cyan),
     ( N > 1 -> Plural = 's' ; Plural = '' ),
     format('Proving ~w variant~w in parallel...', [N, Plural]),
     message:color(normal), nl,
     flush_output,
     pipeline:prove_variants_parallel(Proposal, Specs, Results),
     interface:print_variant_results(Results, BaseEntries, 1)
  ).


%! interface:build_variant_specs(+Opt, +Proposal, +ProofAVL, -Specs) is det.
%
% Builds variant specifications from the --variants option value.

interface:build_variant_specs(auto, Proposal, ProofAVL, Specs) :-
  !,
  variant:detect_pivots(ProofAVL, Proposal, 5, UsePivots, BranchPivots),
  variant:pivots_to_specs(UsePivots, BranchPivots, Specs).

interface:build_variant_specs(all, Proposal, ProofAVL, Specs) :-
  !,
  variant:detect_use_pivots(ProofAVL, Proposal, 20, UsePivots),
  variant:pivots_to_specs(UsePivots, [], Specs).

interface:build_variant_specs(FlagList, Proposal, ProofAVL, Specs) :-
  atomic_list_concat(Flags, ',', FlagList),
  variant:user_flags_to_specs(Flags, Proposal, ProofAVL, Specs).


%! interface:print_variant_results(+Results, +BaseEntries, +N) is det.

interface:print_variant_results([], _, _).

interface:print_variant_results([variant_result(Spec, failed)|Rest], BaseEntries, N) :-
  !,
  Spec = variant(_, _, _, _, Label),
  nl,
  message:color(cyan),
  format('--- Variant ~w: ~w ---', [N, Label]),
  message:color(normal), nl,
  message:warning(['Variant proof failed.']),
  N1 is N + 1,
  interface:print_variant_results(Rest, BaseEntries, N1).

interface:print_variant_results([variant_result(Spec, _Proof, _Model, Plan, _Triggers)|Rest], BaseEntries, N) :-
  Spec = variant(_, _, _, _, Label),
  nl,
  plan:print_variant_header(N, Label),
  variant:plan_entries(Plan, VarEntries),
  length(VarEntries, VarCount),
  variant:plan_diff(BaseEntries, VarEntries, Diff),
  format('  Plan size: ~w actions~n', [VarCount]),
  plan:print_variant_diff(Diff),
  N1 is N + 1,
  interface:print_variant_results(Rest, BaseEntries, N1).


% -----------------------------------------------------------------------------
%  Action: EXPLAIN (LLM-powered plan Q&A)
% -----------------------------------------------------------------------------

%! interface:run_explain(+ExplainOpt, +Proposal, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL) is det.
%
% Dispatches to the explain module. Requires LLM modules to be loaded.
% ExplainOpt is either 'true' (conversational mode) or a question atom
% (single-shot mode).

interface:run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  ( predicate_property(explain:explain_plan(_,_,_,_,_,_), defined)
  -> ( ExplainOpt == true
     -> explain:explain_plan_interactive(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL)
     ;  explain:explain_plan(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL)
     )
  ;  message:warning('--explain requires LLM support. LLM modules are not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: UPSTREAM (version checking)
% -----------------------------------------------------------------------------

%! interface:process_upstream(+Args, +Options) is det.
%
% Checks upstream for newer versions of the specified packages.
% Defaults to @world when no arguments are given.

interface:process_upstream(Args, _Options) :-
  ( Args == []
  -> upstream:check([world])
  ;  upstream:check(Args)
  ).


% -----------------------------------------------------------------------------
%  Action: LLM chat
% -----------------------------------------------------------------------------

%! interface:extract_llm_opt(+Options, -LlmOpt) is semidet.
%
% Succeeds when --llm was passed on the command line. Unifies LlmOpt
% with 'true' when no service name was given, or the service name atom.

interface:extract_llm_opt(Options, LlmOpt) :-
  memberchk(llm(Val), Options),
  Val \== none,
  ( Val == '' -> LlmOpt = true ; LlmOpt = Val ).


%! interface:process_llm_chat(+LlmOpt) is det.
%
% Starts an interactive chat session with the specified LLM service.
% LlmOpt is either 'true' (use default service) or a service name atom.

interface:process_llm_chat(LlmOpt) :-
  ( predicate_property(explainer:call_llm(_,_,_), defined)
  -> ( LlmOpt == true
     -> config:llm_default(Service)
     ;  Service = LlmOpt
     ),
     ( config:llm_model(Service, Model)
     -> nl,
        message:color(cyan),
        format('Chat session with ~w (~w). Type "quit" or "exit" to leave.~n', [Service, Model]),
        message:color(normal),
        nl,
        interface:llm_chat_loop(Service)
     ;  message:warning(['Unknown LLM service: ', Service,
                         '. Available: claude, grok, chatgpt, gemini, ollama.'])
     )
  ;  message:warning('--llm requires LLM support. LLM modules are not loaded.')
  ).


%! interface:llm_chat_loop(+Service) is det.
%
% Interactive read-eval-print loop for LLM chat. Reads user input,
% sends it to the LLM service, prints the streamed response, and
% recurses until the user types quit/exit/q or EOF.

interface:llm_chat_loop(Service) :-
  message:color(green),
  format('~w> ', [Service]),
  message:color(normal),
  flush_output,
  catch(
    read_line_to_string(user_input, Line),
    _,
    Line = end_of_file
  ),
  ( Line == end_of_file
  -> nl
  ; string_lower(Line, Lower),
    ( member(Lower, ["quit", "exit", "q"])
    -> true
    ; Line == ""
    -> interface:llm_chat_loop(Service)
    ; nl,
      explainer:call_llm(Service, Line, _Response),
      nl, nl,
      interface:llm_chat_loop(Service)
    )
  ).


% -----------------------------------------------------------------------------
%  Action: SNAPSHOT (flag processing + rollback dispatch)
% -----------------------------------------------------------------------------

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


%! interface:process_rollback(+Id, +Options) is det.
%
% Dispatches rollback: with --pretend shows diff, without executes
% the actual rollback.

interface:process_rollback(Id, Options) :-
  ( memberchk(pretend(true), Options)
  -> snapshot:diff(Id)
  ;  snapshot:diff(Id),
     nl,
     format('Proceeding with rollback...~n'),
     nl,
     snapshot:rollback(Id)
  ).


% -----------------------------------------------------------------------------
%  Action: RESUME (skip args helper)
% -----------------------------------------------------------------------------

%! interface:assert_resume_skip_args(+Args) is det.
%
% Asserts each positional argument as a config:skip_atom/1 fact.
% When --resume is active, positional args name packages to skip.

interface:assert_resume_skip_args([]).

interface:assert_resume_skip_args([A|Rest]) :-
  asserta(config:skip_atom(A)),
  interface:assert_resume_skip_args(Rest).


% -----------------------------------------------------------------------------
%  Action: BUILD
% -----------------------------------------------------------------------------

interface:process_build([], _Options) :-
  !,
  message:failure('No targets specified for --build.').

interface:process_build(ArgsSets, _Options) :-
  eapi:substitute_sets(ArgsSets, Args),
  interface:report_unresolvable_targets(run, Args),
  findall(target(Q,Arg):run?{[]},
          ( member(Arg, Args),
            atom_codes(Arg, Codes),
            phrase(eapi:qualified_target(Q), Codes),
            once(kb:query(Q, _R://_E))
          ),
          Proposal),
  !,
  ( Proposal == []
  -> message:failure('No valid targets found.')
  ;  builder:build(Proposal)
  ).


% -----------------------------------------------------------------------------
%  Action: DESELECT (remove from world)
% -----------------------------------------------------------------------------

%! interface:process_deselect(+Args) is det.
%
% Removes each positional argument from the world set file.
% The package remains installed but will no longer be tracked
% for @world updates.

interface:process_deselect(Args) :-
  ( Args == []
  -> message:failure('No targets specified for --deselect.')
  ;  forall(member(Arg, Args),
       ( world:unregister(Arg),
         message:inform(['Removed \'', Arg, '\' from world set.'])
       )),
     world:save,
     message:inform(['World set saved.'])
  ).


% -----------------------------------------------------------------------------
%  Side effects: execute planned world actions
% -----------------------------------------------------------------------------

%! interface:execute_world_actions_from_plan(+Plan) is det.
%
% Walks the plan (list of steps, each a list of rules) and executes any
% world_action/2 side effects (register/unregister packages in @world).

interface:execute_world_actions_from_plan([]) :- !.
interface:execute_world_actions_from_plan([Step|Rest]) :-
  interface:execute_world_actions_step(Step),
  interface:execute_world_actions_from_plan(Rest).

%! interface:execute_world_actions_step(+Step) is det.
%
% Processes a single plan step (list of rules), executing world_action
% side effects for any rule whose head is world_action(Op, Arg):world.

interface:execute_world_actions_step([]) :- !.
interface:execute_world_actions_step([Rule|Rest]) :-
  ( Rule = rule(Head,_Body),
    prover:canon_literal(Head, Core, _Ctx),
    Core = world_action(Op, Arg):world ->
      ( Op == register ->
          world:register(Arg)
      ; Op == unregister ->
          world:unregister(Arg)
      ; true
      )
  ; true
  ),
  interface:execute_world_actions_step(Rest).


% -----------------------------------------------------------------------------
%  Action: VDB queries (contents, owner, size, verify, executables)
% -----------------------------------------------------------------------------

%! interface:process_vdb_query(+QueryType, +Args) is det.
%
% Dispatches VDB query commands. For --owner, Args are file paths;
% for all others, Args are package targets.

interface:process_vdb_query(_, []) :-
  !, message:failure('No targets specified.').

interface:process_vdb_query(owner, Args) :-
  !,
  forall(member(Arg, Args),
    ( message:header(['Packages owning ', Arg]),
      nl,
      vdb:print_owner(Arg)
    )).

interface:process_vdb_query(QueryType, Args) :-
  forall(member(Arg, Args),
    ( vdb:resolve_vdb_entries(Arg, Entries),
      ( Entries == [] ->
        message:warning(['Not installed: ', Arg])
      ; forall(member(Entry, Entries),
          interface:run_vdb_query(QueryType, Entry))
      )
    )).


%! interface:run_vdb_query(+QueryType, +Entry) is det.

interface:run_vdb_query(contents, Entry) :-
  message:header(['Contents of ', Entry]),
  nl,
  vdb:print_contents(Entry).

interface:run_vdb_query(size, Entry) :-
  vdb:print_size(Entry).

interface:run_vdb_query(verify, Entry) :-
  vdb:verify_package(Entry).

interface:run_vdb_query(executables, Entry) :-
  message:header(['Executables from ', Entry]),
  nl,
  vdb:print_executables(Entry).


% -----------------------------------------------------------------------------
%  Action: FIX-LINKAGE
% -----------------------------------------------------------------------------

%! interface:process_fix_linkage(+Args, +Options) is det.
%
% Scans installed packages for broken shared library linkage and
% outputs packages that need rebuilding.

interface:process_fix_linkage(_Args, _Options) :-
  ( predicate_property(linkage:check(_), defined) ->
    linkage:check(Results),
    ( Results == [] ->
      message:inform('No broken linkage detected.')
    ; message:header(['Packages with broken linkage']),
      nl,
      forall(member(Entry-Libs, Results),
        ( format('  ~w~n', [Entry]),
          forall(member(Lib, Libs),
            format('    broken: ~w~n', [Lib]))
        )),
      nl,
      length(Results, N),
      format('~w package(s) need rebuilding.~n', [N])
    )
  ; message:warning('Linkage checking module not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: REPORT
% -----------------------------------------------------------------------------

%! interface:process_report(+Options) is det.
%
% Displays a summary of potential problems with installed packages.

interface:process_report(_Options) :-
  ( predicate_property(report:check(_), defined) ->
    report:check(Results),
    report:print_results(Results)
  ; message:warning('Report module not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: REVERSE DEPENDENCIES
% -----------------------------------------------------------------------------

%! interface:process_rdeps(+Args) is det.
%
% Shows which packages depend on the given targets.

interface:process_rdeps([]) :-
  !, message:failure('No targets specified.').

interface:process_rdeps(Args) :-
  forall(member(Arg, Args),
    ( atom_codes(Arg, Codes),
      ( phrase(eapi:qualified_target(Q), Codes),
        once(kb:query(Q, _Repo://Entry))
      -> query:search([category(Cat), name(Name)], _://Entry),
         message:header(['Reverse dependencies of ', Cat, '/', Name]),
         nl,
         vdb:reverse_deps(Cat, Name, RevDeps),
         ( RevDeps == [] ->
           format('  (none found)~n')
         ; length(RevDeps, Count),
           forall(member(RD, RevDeps), format('  ~w~n', [RD])),
           nl,
           format('~w reverse dependency(ies) found.~n', [Count])
         )
      ; message:warning(['Package not found: ', Arg])
      )
    )).


% -----------------------------------------------------------------------------
%  Action: UNUSED DISTFILES
% -----------------------------------------------------------------------------

%! interface:process_unused_distfiles(+Options) is det.
%
% Lists distfiles not referenced by any installed package.

interface:process_unused_distfiles(_Options) :-
  ( predicate_property(distfiles:orphans(_,_), defined) ->
    distfiles:get_location(DistDir),
    message:header(['Unused distfiles in ', DistDir]),
    nl,
    distfiles:orphans(portage, Orphans),
    ( Orphans == [] ->
      message:inform('No unused distfiles found.')
    ; length(Orphans, Count),
      forall(member(F, Orphans), format('  ~w~n', [F])),
      nl,
      format('~w unused distfile(s).~n', [Count])
    )
  ; message:warning('Distfiles module not available.')
  ).


% -----------------------------------------------------------------------------
%  CI helpers
% -----------------------------------------------------------------------------

%! interface:ci_exit_code(+ModelAVL, +ProofAVL, -ExitCode) is det.
%
% Computes the CI exit code from the proof artifacts:
%   0 = no assumptions (clean plan)
%   1 = only prover cycle-break assumptions
%   2 = domain assumptions present (missing/non-existent deps, etc.)

interface:ci_exit_code(ModelAVL, ProofAVL, ExitCode) :-
  ( interface:has_any_assumption(ModelAVL) ->
      ( interface:has_domain_assumptions(ProofAVL) -> ExitCode = 2
      ; interface:has_cycle_breaks(ProofAVL)       -> ExitCode = 1
      ; ExitCode = 1
      )
  ; ExitCode = 0
  ).

%! interface:has_any_assumption(+ModelAVL) is semidet.
%
% Succeeds if the model contains any assumed(_) key.

interface:has_any_assumption(ModelAVL) :-
  assoc:gen_assoc(Key, ModelAVL, _),
  Key = assumed(_),
  !.

%! interface:has_domain_assumptions(+ProofAVL) is semidet.
%
% Succeeds if the proof contains at least one domain assumption
% (proof key of the form rule(assumed(_))).

interface:has_domain_assumptions(ProofAVL) :-
  assoc:gen_assoc(rule(assumed(_)), ProofAVL, _),
  !.

%! interface:has_cycle_breaks(+ProofAVL) is semidet.
%
% Succeeds if the proof contains at least one prover cycle-break
% assumption (proof key of the form assumed(rule(_))).

interface:has_cycle_breaks(ProofAVL) :-
  assoc:gen_assoc(assumed(rule(_)), ProofAVL, _),
  !.