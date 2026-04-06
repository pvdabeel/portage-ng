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

:- include('Interface/target.pl').

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
       [opt(fetchall),  type(boolean),   default(false),       shortflags(['F']), longflags(['fetch-all-uri']), help('Fetch all SRC_URI files regardless of USE flags')],
       [opt(merge),     type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),     help('Merge target package')],
       [opt(update),    type(boolean),   default(false),       shortflags(['u']), longflags(['update']),    help('Update target package')],
       [opt(upgrade),   type(boolean),   default(false),                          longflags(['upgrade']),   help('Upgrade set (default: @world): first compute a fresh plan under --emptytree, then run depclean')],
       [opt(deep),      type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),      help('Also consider dependencies')],
       [opt(emptytree), type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']), help('Pretend no other packages are installed')],
       [opt(buildpkg),  type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),  help('Create binary packages after building from source')],
       [opt(buildpkgonly), type(boolean), default(false),       shortflags(['B']), longflags(['buildpkgonly']), help('Build binary packages but do not merge to live filesystem')],
       [opt(build),     type(boolean),   default(false),                          longflags(['build']),     help('Build target (print plan then execute with live progress)')],
       [opt(resume),    type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),    help('Resume previous command')],
       [opt(newuse),    type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),    help('Rebuild if USE or IUSE changed since install')],
       [opt(changeduse), type(boolean),   default(false),       shortflags(['U']), longflags(['changed-use']), help('Rebuild only if effective USE flags changed')],
       [opt(changeddeps), type(boolean),  default(false),                          longflags(['changed-deps']), help('Rebuild if runtime dependencies changed since install')],
       [opt(changedslot), type(boolean),  default(false),                          longflags(['changed-slot']), help('Rebuild if SLOT changed since install')],
       [opt(selective), type(boolean),   default(false),                          longflags(['selective']), help('Do not reinstall already-installed packages')],
       [opt(select),    type(boolean),   default(true),                           longflags(['select']),    help('Add targets to world set (inverse of --oneshot)')],
       [opt(deselect),  type(boolean),   default(false),                          longflags(['deselect']),  help('Remove targets from world set without unmerging')],
       [opt(noreplace), type(boolean),   default(false),       shortflags(['n']), longflags(['noreplace']), help('Skip already-installed packages')],
       [opt(nodeps),    type(boolean),   default(false),       shortflags(['O']), longflags(['nodeps']),    help('Merge without resolving dependencies')],
       [opt(onlydeps),  type(boolean),   default(false),       shortflags(['o']), longflags(['onlydeps']),  help('Only merge dependencies, not the target itself')],
       [opt(withbdeps), type(atom),      default(y),                              longflags(['with-bdeps']), help('Include build-time dependencies (y or n)')],
       [opt(withtestdeps), type(atom),    default(n),                              longflags(['with-test-deps']), help('Include test dependencies (y or n)')],
       [opt(dynamicdeps), type(boolean),  default(true),                           longflags(['dynamic-deps']), help('Use repo dependency info instead of installed VDB')],
       [opt(rebuildnewrev), type(boolean), default(false),                          longflags(['rebuild-if-new-rev']), help('Rebuild packages with new revision')],
       [opt(rebuildnewver), type(boolean), default(false),                          longflags(['rebuild-if-new-ver']), help('Rebuild packages with new version available')],
       [opt(rebuildnewslot), type(boolean), default(false),                         longflags(['rebuild-if-new-slot']), help('Rebuild packages when slot operator deps change')],
       [opt(rebuildunbuilt), type(boolean), default(false),                         longflags(['rebuild-if-unbuilt']), help('Rebuild deps that have been rebuilt from source')],
       [opt(updateifinstalled), type(boolean), default(false),                      longflags(['update-if-installed']), help('Like --update but only for already-installed packages')],
       [opt(exclude),   type(atom),      default(''),                             longflags(['exclude']),   help('Exclude atoms from merge (repeatable)')],
       [opt(skip),      type(atom),      default(''),                             longflags(['skip']),     help('Skip packages during --resume (repeatable)')],
       [opt(oneshot),   type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),   help('Do not add package to world')],
       [opt(prefix),    type(atom),      default('/'),                            longflags(['prefix']),    help('Set the prefix directory')],
       [opt(style),     type(atom),      default('fancy'),                        longflags(['style']),     help('Set the printing style: fancy, column or short')],
       [opt(sync),      type(boolean),   default(false),                          longflags(['sync']),      help('Sync repository. Optional args: repository names (e.g. portage, pkg, overlay)')],
       [opt(clear),     type(boolean),   default(false),                          longflags(['clear']),     help('Clear knowledge base')],
       [opt(regen),     type(boolean),   default(false),                          longflags(['regen']),     help('Regenerate the ebuild metadata cache (no network sync)')],
       [opt(metadata),  type(boolean),   default(false),                          longflags(['metadata']), help('Regenerate the ebuild metadata cache (alias for --regen)')],
       [opt(listsets),  type(boolean),   default(false),                          longflags(['list-sets']), help('List available package sets')],
       [opt(graph),     type(boolean),   default(false),                          longflags(['graph']),     help('Create graph. Args: "modified"|"full"|"build"|"build modified"|"build full".')],
       [opt(checknews), type(boolean),   default(false),                          longflags(['check-news']), help('Check for and display unread news items')],
       [opt(readnews),  type(boolean),   default(false),                          longflags(['read-news']), help('Display news items when using --ask')],
       [opt(depclean),  type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),  help('Clean dependencies')],
       [opt(info),      type(boolean),   default(false),       shortflags(['i']), longflags(['info']),      help('Show package version')],
       [opt(bugs),      type(boolean),   default(false),                          longflags(['bugs']),      help('Print bug report drafts (Gentoo Bugzilla) for the given target, without printing a plan')],
       [opt(search),    type(boolean),   default(false),       shortflags(['s']), longflags(['search']),    help('Search for a target')],
       [opt(unmerge),   type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),   help('Unmerge target')],
       [opt(usepkg),    type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),    help('Use binary packages when available, fall back to source')],
       [opt(usepkgonly), type(boolean),  default(false),       shortflags(['K']), longflags(['usepkg-only']), help('Use only binary packages, fail if unavailable')],
       [opt(getbinpkg), type(boolean),  default(false),       shortflags(['g']), longflags(['getbinpkg']), help('Download binary packages from BINHOST')],
       [opt(getbinpkgonly), type(boolean), default(false),      shortflags(['G']), longflags(['getbinpkg-only']), help('Use only remote binary packages from BINHOST')],
       [opt(usepkgexclude), type(atom),  default(''),                             longflags(['usepkg-exclude']), help('Exclude atoms from binary package usage (repeatable)')],
       [opt(usepkginclude), type(atom),  default(''),                             longflags(['usepkg-include']), help('Force binary package usage for specific atoms (repeatable)')],
       [opt(usepkgexcludelive), type(boolean), default(false),                     longflags(['usepkg-exclude-live']), help('Do not use binary packages for live (9999) ebuilds')],
       [opt(binpkgchangeddeps), type(boolean), default(false),                     longflags(['binpkg-changed-deps']), help('Ignore binpkgs whose deps have changed since build')],
       [opt(binpkgrespectuse), type(boolean), default(false),                      longflags(['binpkg-respect-use']), help('Ignore binpkgs whose USE flags do not match')],
       [opt(rebuiltbinaries), type(boolean), default(false),                       longflags(['rebuilt-binaries']), help('Replace installed packages with rebuilt binary packages')],
       [opt(failclean), type(boolean),   default(false),                          longflags(['fail-clean']), help('Clean build directory on failure')],
       [opt(quiet),     type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),     help('Reduced output')],
       [opt(jobs),      type(integer),   default(0),           shortflags(['j']), longflags(['jobs']),      help('Number of parallel build jobs (0 = auto-detect)')],
       [opt(loadavg),   type(float),     default(0.0),                            longflags(['load-average']), help('Do not start new jobs if load average exceeds N (0 = no limit)')],
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
       [opt(trainmodel), type(boolean),   default(false),                          longflags(['train-model']), help('Build the semantic search embedding index (requires Ollama)')],
       [opt(similar),   type(boolean),   default(false),                          longflags(['similar']),   help('Find semantically similar packages (uses pre-built embedding index)')],
       [opt(estimate),  type(boolean),   default(false),                          longflags(['estimate']),  help('Show estimated build time for given packages or a plan')],

       % upstream version checking

       [opt(upstream),  type(boolean),   default(false),                          longflags(['upstream']),  help('Check upstream for newer package versions')],

       % bug search (Bugzilla quicksearch)

       [opt(searchbugs), type(boolean),   default(false),                          longflags(['search-bugs']), help('Search Bugzilla for bugs matching the given term')],

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
       [opt(import),      type(boolean), default(false),                          longflags(['import']),       help('Track manually installed software in VDB')],
       [opt(unmanagedfiles), type(boolean), default(false),                       longflags(['unmanaged-files']), help('Find files not owned by any installed package')],

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

       [opt(background), type(boolean),   default(false),                          longflags(['background']), help('Fork to background (daemon and server modes)')],
       [opt(status),    type(boolean),   default(false),                          longflags(['status']),    help('Check if daemon/server is running (ipc and client modes)')],
       [opt(cmd),       type(atom),      default(none),                           longflags(['cmd']),       help('Send command to daemon/server: halt or relaunch (ipc and client modes)')],

       % build options

       [opt(logs),      type(boolean),   default(false),       shortflags(['l']), longflags(['logs']),      help('Show build log paths in --build output')],

       % debugging purposes

       [opt(ci),        type(boolean),   default(false),                          longflags(['ci']),        help('CI mode: non-interactive, fail with nonzero exit code on assumptions')],
       [opt(profile),   type(boolean),   default(false),                          longflags(['profile']),   help('Enable instrumentation (sampler, debug hooks). Use wrapper or pass -Dinstrumentation=true to swipl.')]
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

interface:argv(Options,Args) :-
  interface:argv_(Options,Args),!.

interface:argv(Options,Args) :-
  interface:spec(S),
  catch(
    opt_arguments(S,Options,Args),
    E,
    interface:argv_handle_parse_error(E)
  ),
  assertz(interface:argv_(Options,Args)).

%! interface:argv_handle_parse_error(+Exception) is det.
%
% Handles optparse exceptions. For unknown options, prints a clear message
% and halts. Other exceptions are rethrown.

interface:argv_handle_parse_error(E) :-
  E = error(ExType, _),
  ExType = existence_error(commandline_option, Flag),
  !,
  format(user_error, 'Error: Unknown option ~w.~n', [Flag]),
  ( interface:suggest_similar_flag(Flag, Suggestion) ->
      format(user_error, 'Did you mean: ~w?~n', [Suggestion])
  ; true
  ),
  format(user_error, 'Use --help for available options.~n', []),
  halt(1).
interface:argv_handle_parse_error(E) :-
  throw(E).


%! interface:suggest_similar_flag(+Unknown, -Suggestion) is semidet.
%
% Suggests the closest known flag to an unknown flag using prefix matching
% and edit distance heuristics.

interface:suggest_similar_flag(Unknown, Suggestion) :-
  atom_string(Unknown, UnkStr),
  interface:spec(Spec),
  findall(Score-Flag,
    ( member(OptSpec, Spec),
      memberchk(longflags(Flags), OptSpec),
      member(F, Flags),
      atom_concat('--', F, Flag),
      atom_string(Flag, FlagStr),
      interface:flag_similarity(UnkStr, FlagStr, Score),
      Score > 0.4
    ),
    Matches0),
  Matches0 \== [],
  sort(0, @>=, Matches0, [_-Suggestion|_]).


%! interface:flag_similarity(+A, +B, -Score) is det.
%
% Computes a similarity score (0.0-1.0) between two flag strings
% using longest common prefix ratio.

interface:flag_similarity(A, B, Score) :-
  string_codes(A, CA),
  string_codes(B, CB),
  interface:common_prefix_length(CA, CB, 0, PLen),
  string_length(A, LA),
  string_length(B, LB),
  MaxLen is max(LA, LB),
  ( MaxLen =:= 0 -> Score = 0.0
  ; Score is PLen / MaxLen
  ).


%! interface:common_prefix_length(+CodesA, +CodesB, +Acc, -Len) is det.
%
% Counts the length of the common prefix between two code lists.

interface:common_prefix_length([C|As], [C|Bs], Acc, Len) :-
  !,
  Acc1 is Acc + 1,
  interface:common_prefix_length(As, Bs, Acc1, Len).
interface:common_prefix_length(_, _, Len, Len).


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
  (lists:memberchk(fetchall(true),          Options) -> asserta(preference:local_flag(fetchall)) ; true),
  (lists:memberchk(failclean(true),         Options) -> asserta(preference:local_flag(failclean)) ; true),
  (lists:memberchk(usepkgexcludelive(true), Options) -> asserta(preference:local_flag(usepkgexcludelive)) ; true),
  (lists:memberchk(binpkgchangeddeps(true), Options) -> asserta(preference:local_flag(binpkgchangeddeps)) ; true),
  (lists:memberchk(binpkgrespectuse(true),  Options) -> asserta(preference:local_flag(binpkgrespectuse)) ; true),
  (lists:memberchk(rebuiltbinaries(true),   Options) -> asserta(preference:local_flag(rebuiltbinaries)) ; true),
  (lists:memberchk(ask(true),              Options) -> asserta(preference:local_flag(ask)) ; true),
  (lists:memberchk(alert(true),            Options) -> asserta(preference:local_flag(alert)) ; true),
  (lists:memberchk(quiet(true),             Options) -> asserta(preference:local_flag(quiet)) ; true),
  (lists:memberchk(verbose(true),           Options) -> asserta(config:verbose(true)) ; true),
  (lists:memberchk(profile(true),           Options) -> set_prolog_flag(instrumentation, true) ; true),
  (lists:memberchk(logs(true),              Options) -> asserta(config:show_build_logs(true)) ; true),
  (lists:memberchk(style(Style),            Options) -> interface:assert_valid_style(Style) ; true),
  ((lists:memberchk(jobs(J),                Options), J > 0) -> asserta(config:cli_jobs(J)) ; true),
  ((lists:memberchk(loadavg(L),             Options), L > 0.0) -> asserta(config:cli_load_average(L)) ; true),
  (lists:memberchk(permitdowngrade(true),   Options) -> asserta(preference:local_flag(permitdowngrade)) ; true),
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


% -----------------------------------------------------------------------------
%  Mode flag verification
% -----------------------------------------------------------------------------

%! interface:verify(+Mode) is det.
%
% Verify CLI flags for the given mode. If an early-exit flag is set
% (--background, --status, --cmd, --shell), performs the requested
% action and halts. Succeeds silently when no early-exit flag matches,
% allowing main/1 to continue.

interface:verify(Mode) :-
  interface:argv(Options, _),
  interface:check_flags(Mode, Options).

interface:check_flags(Mode, Options) :-
  interface:early_exit(Mode, Options).
interface:check_flags(_, _).


%! interface:early_exit(+Mode, +Options) is semidet.
%
% Per-mode early-exit handlers. Each clause matches a specific flag,
% performs its action, and halts. Clauses are tried in definition order.

interface:early_exit(ipc, Options) :-
  memberchk(shell(true), Options), !,
  format(user_error,
    'Error: --shell is not supported in ipc mode. Use --mode standalone --shell instead.~n', []),
  halt(1).

interface:early_exit(ipc, Options) :-
  memberchk(status(true), Options), !,
  ( daemon:status -> halt(0) ; halt(1) ).

interface:early_exit(ipc, Options) :-
  memberchk(cmd(Cmd), Options), Cmd \= none, !,
  daemon:send_command(Cmd),
  halt(0).

interface:early_exit(daemon, Options) :-
  memberchk(background(true), Options), !,
  daemon:fork_background(daemon),
  halt(0).

interface:early_exit(client, Options) :-
  memberchk(status(true), Options), !,
  interface:process_server(Host, Port),
  ( interface:server_reachable(Host, Port)
  -> format('Server reachable at ~w:~w~n', [Host, Port]),
     halt(0)
  ;  format('Server not reachable at ~w:~w~n', [Host, Port]),
     halt(1)
  ).

interface:early_exit(client, Options) :-
  memberchk(cmd(Cmd), Options), Cmd \= none, !,
  format(user_error,
    'Error: --cmd is not yet supported for client mode.~n', []),
  halt(1).

interface:early_exit(server, Options) :-
  memberchk(background(true), Options), !,
  daemon:fork_background(server),
  halt(0).


% -----------------------------------------------------------------------------
%  Request processing
% -----------------------------------------------------------------------------

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
                                       -> (action:process_rollback(RollbackId, Options),             Continue) ;
    memberchk(version(true),Options)  -> (message:logo(['::- portage-ng ',Version]),
                                         interface:print_version_repos,             Continue) ;
    memberchk(info(true),Options)     -> (action:process_action(info,Args,Options),                 Continue) ;
    memberchk(bugs(true),Options)     -> (action:process_bugs(Args,Options),                        Continue) ;
    memberchk(clear(true),Options)    -> (kb:clear,                                                 Continue) ;
    memberchk(graph(true),Options)    -> (action:process_graph(Args), nl,                           Continue) ;
    memberchk(deselect(true),Options) -> (action:process_deselect(Args),                            Continue) ;
    memberchk(unmerge(true),Options)  -> (action:process_action(uninstall,Args,Options),             Continue) ;
    memberchk(depclean(true),Options) -> (action:process_action(depclean,Args,Options),              Continue) ;
    memberchk(upgrade(true),Options)  -> (action:process_upgrade(Args,Options),                      Continue) ;
    % For a single target, Portage-style update behaves like a normal merge:
    % resolve full runtime closure and perform a transactional replace if needed.
    % In portage-ng the "full closure" corresponds to proving :run.
    memberchk(update(true),Options)   -> (action:process_action(run,Args,Options),                   Continue) ;
    memberchk(search(true),Options)   -> (action:process_action(search,Args,Options),                Continue) ;
    memberchk(listsets(true),Options) -> (action:process_list_sets,                                  Continue) ;
    memberchk(checknews(true),Options) -> (news:check,                                               Continue) ;
    memberchk(readnews(true),Options) -> (news:check,                                                Continue) ;
    memberchk(regen(true),Options)   -> (action:process_regen(Mode, Args),!,                         Continue) ;
    memberchk(metadata(true),Options) -> (action:process_regen(Mode, Args),!,                        Continue) ;
    memberchk(sync(true),Options)     -> (action:process_sync(Mode, Args),!,                         Continue) ;
    memberchk(save(true),Options)     -> (kb:save,!,                                                 Continue) ;
    memberchk(load(true),Options)     -> (kb:load,!,                                                 Continue) ;
    memberchk(fetchonly(true),Options) -> (action:process_action(fetchonly,Args,Options),            Continue) ;
    memberchk(resume(true),Options)  -> (action:assert_resume_skip_args(Args),
                                         builder:build_resume,                                       Continue) ;
    memberchk(build(true),Options)   -> (action:process_build(Args,Options),                         Continue) ;
    memberchk(contents(true),Options) -> (action:process_vdb_query(contents,Args),                   Continue) ;
    memberchk(owner(true),Options)   -> (action:process_vdb_query(owner,Args),                      Continue) ;
    memberchk(pkgsize(true),Options) -> (action:process_vdb_query(size,Args),                       Continue) ;
    memberchk(verify(true),Options)  -> (action:process_vdb_query(verify,Args),                     Continue) ;
    memberchk(executables(true),Options) -> (action:process_vdb_query(executables,Args),            Continue) ;
    memberchk(fixlinkage(true),Options) -> (action:process_fix_linkage(Args,Options),               Continue) ;
    memberchk(report(true),Options)  -> (action:process_report(Options),                            Continue) ;
    memberchk(rdeps(true),Options)   -> (action:process_rdeps(Args),                                Continue) ;
    memberchk(unuseddistfiles(true),Options) -> (action:process_unused_distfiles(Options),          Continue) ;
    memberchk(import(true),Options)  -> (action:process_import(Args,Options),                        Continue) ;
    memberchk(unmanagedfiles(true),Options) -> (action:process_unmanaged_files(Args),                Continue) ;
    memberchk(upstream(true),Options) -> (action:process_upstream(Args,Options),                     Continue) ;
    memberchk(searchbugs(true),Options) -> (action:process_search_bugs(Args,Options),                Continue) ;
    memberchk(trainmodel(true),Options) -> (action:process_train_model,                              Continue) ;
    memberchk(similar(true),Options)   -> (action:process_similar(Args),                             Continue) ;
    memberchk(estimate(true),Options)  -> (action:process_estimate(Args),                            Continue) ;
    action:extract_llm_opt(Options, LlmOpt)
                                      -> (action:process_llm_chat(LlmOpt),                          Continue) ;
    memberchk(shell(true),Options), Args \== []
                                      -> (action:process_action(run,Args,Options),                   Continue) ;
    memberchk(shell(true),Options)    -> Continue ;
    memberchk(merge(true),Options)    -> (action:process_action(run,Args,Options),                   Continue)),

  Continue.

interface:process_requests(_) :-
  ( catch(daemon:running, _, fail)
  -> true
  ;  halt(1)
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