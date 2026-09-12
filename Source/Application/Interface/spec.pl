/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SPEC
The optparse command-line flag specification (included into the INTERFACE
module via interface.pl).
*/

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

       [opt(ask),               type(boolean),   default(false),       shortflags(['a']), longflags(['ask']),                  help('Ask for confirmation before proceeding')],
       [opt(alert),             type(boolean),   default(false),       shortflags(['A']), longflags(['alert']),                help('Ring terminal bell when action needs attention')],
       [opt(verbose),           type(boolean),   default(false),       shortflags(['v']), longflags(['verbose']),              help('Turn on verbose mode')],
       [opt(pretend),           type(boolean),   default(false),       shortflags(['p']), longflags(['pretend']),              help('Turn on pretend mode')],
       [opt(fetchonly),         type(boolean),   default(false),       shortflags(['f']), longflags(['fetchonly']),            help('Turn on fetchonly mode')],
       [opt(fetchall),          type(boolean),   default(false),       shortflags(['F']), longflags(['fetch-all-uri']),        help('Fetch all SRC_URI files regardless of USE flags')],
       [opt(merge),             type(boolean),   default(true),        shortflags(['m']), longflags(['merge']),                help('Merge target package')],
       [opt(update),            type(boolean),   default(false),       shortflags(['u']), longflags(['update']),               help('Update target package')],
       [opt(upgrade),           type(boolean),   default(false),                          longflags(['upgrade']),              help('Upgrade set (default: @world): first compute a fresh plan under --emptytree, then run depclean')],
       [opt(deep),              type(boolean),   default(false),       shortflags(['d']), longflags(['deep']),                 help('Also consider dependencies')],
       [opt(emptytree),         type(boolean),   default(false),       shortflags(['e']), longflags(['emptytree']),            help('Pretend no other packages are installed')],
       [opt(buildpkg),          type(boolean),   default(false),       shortflags(['b']), longflags(['buildpkg']),             help('Create binary packages after building from source')],
       [opt(buildpkgonly),      type(boolean),   default(false),       shortflags(['B']), longflags(['buildpkgonly']),         help('Build binary packages but do not merge to live filesystem')],
       [opt(build),             type(boolean),   default(false),                          longflags(['build']),                help('Build target (print plan then execute with live progress)')],
       [opt(resume),            type(boolean),   default(false),       shortflags(['r']), longflags(['resume']),               help('Resume previous command')],
       [opt(newuse),            type(boolean),   default(false),       shortflags(['N']), longflags(['newuse']),               help('Rebuild if USE or IUSE changed since install')],
       [opt(changeduse),        type(boolean),   default(false),       shortflags(['U']), longflags(['changed-use']),          help('Rebuild only if effective USE flags changed')],
       [opt(changeddeps),       type(boolean),   default(false),                          longflags(['changed-deps']),         help('Rebuild if runtime dependencies changed since install')],
       [opt(changedslot),       type(boolean),   default(false),                          longflags(['changed-slot']),         help('Rebuild if SLOT changed since install')],
       [opt(selective),         type(boolean),   default(false),                          longflags(['selective']),            help('Do not reinstall already-installed packages')],
       [opt(select),            type(boolean),   default(true),                           longflags(['select']),               help('Add targets to world set (inverse of --oneshot)')],
       [opt(deselect),          type(boolean),   default(false),                          longflags(['deselect']),             help('Remove targets from world set without unmerging')],
       [opt(noreplace),         type(boolean),   default(false),       shortflags(['n']), longflags(['noreplace']),            help('Skip already-installed packages')],
       [opt(nodeps),            type(boolean),   default(false),       shortflags(['O']), longflags(['nodeps']),               help('Merge without resolving dependencies')],
       [opt(onlydeps),          type(boolean),   default(false),       shortflags(['o']), longflags(['onlydeps']),             help('Only merge dependencies, not the target itself')],
       [opt(withbdeps),         type(atom),      default(y),                              longflags(['with-bdeps']),           help('Include build-time dependencies (y or n)')],
       [opt(withtestdeps),      type(atom),      default(n),                              longflags(['with-test-deps']),       help('Include test dependencies (y or n)')],
       [opt(dynamicdeps),       type(boolean),   default(true),                           longflags(['dynamic-deps']),         help('Use repo dependency info instead of installed VDB')],
       [opt(rebuildnewrev),     type(boolean),   default(false),                          longflags(['rebuild-if-new-rev']),   help('Rebuild packages with new revision')],
       [opt(rebuildnewver),     type(boolean),   default(false),                          longflags(['rebuild-if-new-ver']),   help('Rebuild packages with new version available')],
       [opt(rebuildnewslot),    type(boolean),   default(false),                          longflags(['rebuild-if-new-slot']),  help('Rebuild packages when slot operator deps change')],
       [opt(rebuildunbuilt),    type(boolean),   default(false),                          longflags(['rebuild-if-unbuilt']),   help('Rebuild deps that have been rebuilt from source')],
       [opt(updateifinstalled), type(boolean),   default(false),                          longflags(['update-if-installed']),  help('Like --update but only for already-installed packages')],
       [opt(exclude),           type(atom),      default(''),                             longflags(['exclude']),              help('Exclude atoms from merge (repeatable)')],
       [opt(skip),              type(atom),      default(''),                             longflags(['skip']),                 help('Skip packages during --resume (repeatable)')],
       [opt(oneshot),           type(boolean),   default(false),       shortflags(['1']), longflags(['oneshot']),              help('Do not add package to world')],
       [opt(prefix),            type(atom),      default('/'),                            longflags(['prefix']),               help('Set the prefix directory')],
       [opt(style),             type(atom),      default('fancy'),                        longflags(['style']),                help('Set the printing style: fancy, column or short')],
       [opt(sync),              type(boolean),   default(false),                          longflags(['sync']),                 help('Sync repository. Optional args: repository names (e.g. portage, pkg, overlay)')],
       [opt(clear),             type(boolean),   default(false),                          longflags(['clear']),                help('Clear knowledge base')],
       [opt(regen),             type(boolean),   default(false),                          longflags(['regen']),                help('Regenerate the ebuild metadata cache (no network sync)')],
       [opt(metadata),          type(boolean),   default(false),                          longflags(['metadata']),             help('Regenerate the ebuild metadata cache (alias for --regen)')],
       [opt(listsets),          type(boolean),   default(false),                          longflags(['list-sets']),            help('List available package sets')],
       [opt(graph),             type(boolean),   default(false),                          longflags(['graph']),                help('Create graph. Args: "modified"|"full"|"emerge"|"emerge modified"|"emerge full".')],
       [opt(checknews),         type(boolean),   default(false),                          longflags(['check-news']),           help('Check for and display unread news items')],
       [opt(readnews),          type(boolean),   default(false),                          longflags(['read-news']),            help('Display news items when using --ask')],
       [opt(depclean),          type(boolean),   default(false),       shortflags(['c']), longflags(['depclean']),             help('Clean dependencies')],
       [opt(info),              type(boolean),   default(false),       shortflags(['i']), longflags(['info']),                 help('Show package version')],
       [opt(bugs),              type(boolean),   default(false),                          longflags(['bugs']),                 help('Print bug report drafts (Gentoo Bugzilla) for the given target, without printing a plan')],
       [opt(search),            type(boolean),   default(false),       shortflags(['s']), longflags(['search']),               help('Search for a target')],
       [opt(unmerge),           type(boolean),   default(false),       shortflags(['C']), longflags(['unmerge']),              help('Unmerge target')],
       [opt(usepkg),            type(boolean),   default(false),       shortflags(['k']), longflags(['usepkg']),               help('Use binary packages when available, fall back to source')],
       [opt(usepkgonly),        type(boolean),   default(false),       shortflags(['K']), longflags(['usepkg-only']),          help('Use only binary packages, fail if unavailable')],
       [opt(getbinpkg),         type(boolean),   default(false),       shortflags(['g']), longflags(['getbinpkg']),            help('Download binary packages from BINHOST')],
       [opt(getbinpkgonly),     type(boolean),   default(false),       shortflags(['G']), longflags(['getbinpkg-only']),       help('Use only remote binary packages from BINHOST')],
       [opt(usepkgexclude),     type(atom),      default(''),                             longflags(['usepkg-exclude']),       help('Exclude atoms from binary package usage (repeatable)')],
       [opt(usepkginclude),     type(atom),      default(''),                             longflags(['usepkg-include']),       help('Force binary package usage for specific atoms (repeatable)')],
       [opt(usepkgexcludelive), type(boolean),   default(false),                          longflags(['usepkg-exclude-live']),  help('Do not use binary packages for live (9999) ebuilds')],
       [opt(binpkgchangeddeps), type(boolean),   default(false),                          longflags(['binpkg-changed-deps']),  help('Ignore binpkgs whose deps have changed since build')],
       [opt(binpkgrespectuse),  type(boolean),   default(false),                          longflags(['binpkg-respect-use']),   help('Ignore binpkgs whose USE flags do not match')],
       [opt(rebuiltbinaries),   type(boolean),   default(false),                          longflags(['rebuilt-binaries']),     help('Replace installed packages with rebuilt binary packages')],
       [opt(failclean),         type(boolean),   default(false),                          longflags(['fail-clean']),           help('Clean build directory on failure')],
       [opt(quiet),             type(boolean),   default(false),       shortflags(['q']), longflags(['quiet']),                help('Reduced output')],
       [opt(jobs),              type(integer),   default(0),           shortflags(['j']), longflags(['jobs']),                 help('Number of parallel build jobs (0 = auto-detect)')],
       [opt(optimize),          type(atom),      default(parallelism),                    longflags(['optimize']),             help('Plan ordering strategy: parallelism (default) or soft-requirements')],
       [opt(loadavg),           type(float),     default(0.0),                            longflags(['load-average']),         help('Do not start new jobs if load average exceeds N (0 = no limit)')],
       [opt(color),             type(atom),      default(y),                              longflags(['color']),                help('Enable or disable color output (y or n)')],
       [opt(timeout),           type(integer),   default(0),                              longflags(['timeout']),              help('Abort proving/planning after N seconds (0 = no limit)')],
       [opt(variants),          type(atom),      default(none),                           longflags(['variants']),             help('Show alternative plans (none, auto, all, or comma-separated USE flags)')],
       [opt(host),              type(atom),      default(Hostname),                       longflags(['host']),                 help('Set server hostname (client mode)')],
       [opt(port),              type(integer),   default(4000),                           longflags(['port']),                 help('Set Server port (client or server mode)')],
       [opt(shell),             type(boolean),   default(false),                          longflags(['shell']),                help('Go to shell')],
       [opt(save),              type(boolean),   default(false),                          longflags(['save']),                 help('Save knowledgebase (only relevant in client mode')],
       [opt(load),              type(boolean),   default(false),                          longflags(['load']),                 help('Load knowledgebase (only relevant in client mode)')],
       [opt(version),           type(boolean),   default(false),       shortflags(['V']), longflags(['version']),              help('Show version')],

       % snapshot and rollback

       [opt(snapshot),          type(atom),      default(none),                           longflags(['snapshot']),             help('Create snapshot before merge (optional ID, auto-generated if omitted)')],
       [opt(rollback),          type(atom),      default(none),                           longflags(['rollback']),             help('Rollback to a named snapshot')],
       [opt(snapshots),         type(boolean),   default(false),                          longflags(['snapshots']),            help('List available snapshots')],

       % LLM interaction (requires LLM modules)

       [opt(explain),           type(atom),      default(none),                           longflags(['explain']),              help('Explain the build plan via LLM (optionally pass a question)')],
       [opt(llm),               type(atom),      default(none),                           longflags(['llm']),                  help('Start interactive chat with an LLM (optionally specify service name)')],
       [opt(diagnose),          type(boolean),   default(false),                          longflags(['diagnose']),             help('Metacircular LLM diagnose of a failed build (propose feedback; confirm to apply)')],
       [opt(diagnoselog),       type(atom),      default(none),                           longflags(['log']),                  help('Build log path for --diagnose (default: log dir for the package)')],
       [opt(trainmodel),        type(boolean),   default(false),                          longflags(['train-model']),          help('Build the semantic search embedding index (requires Ollama)')],
       [opt(similar),           type(boolean),   default(false),                          longflags(['similar']),              help('Find semantically similar packages (uses pre-built embedding index)')],
       [opt(estimate),          type(boolean),   default(false),                          longflags(['estimate']),             help('Show estimated build time for given packages or a plan')],

       % upstream version checking

       [opt(upstream),          type(boolean),   default(false),                          longflags(['upstream']),             help('Check upstream for newer package versions')],

       % bug search (Bugzilla quicksearch)

       [opt(searchbugs),        type(boolean),   default(false),                          longflags(['search-bugs']),          help('Search Bugzilla for bugs matching the given term')],

       % VDB queries (Paludis cave-style)

       [opt(contents),          type(boolean),   default(false),                          longflags(['contents']),             help('List files installed by a package')],
       [opt(owner),             type(boolean),   default(false),                          longflags(['owner']),                help('Find which package owns a file')],
       [opt(pkgsize),           type(boolean),   default(false),                          longflags(['size']),                 help('Show disk space used by an installed package')],
       [opt(verify),            type(boolean),   default(false),                          longflags(['verify']),               help('Verify installed package files against recorded checksums')],
       [opt(executables),       type(boolean),   default(false),                          longflags(['executables']),          help('Show executables provided by a package')],

       % maintenance

       [opt(fixlinkage),        type(boolean),   default(false),                          longflags(['fix-linkage']),          help('Rebuild packages with broken shared library linkage')],
       [opt(report),            type(boolean),   default(false),                          longflags(['report']),               help('Report problems with installed packages')],
       [opt(rdeps),             type(boolean),   default(false),                          longflags(['rdeps']),                help('Show reverse dependencies of a package')],
       [opt(unuseddistfiles),   type(boolean),   default(false),                          longflags(['unused-distfiles']),     help('List distfiles not used by any installed package')],
       [opt(import),            type(boolean),   default(false),                          longflags(['import']),               help('Track manually installed software in VDB')],
       [opt(importvdb),         type(boolean),   default(false),                          longflags(['import-vdb']),           help('Client mode: parse the local VDB and ship installed-package facts to the server')],
       [opt(unmanagedfiles),    type(boolean),   default(false),                          longflags(['unmanaged-files']),      help('Find files not owned by any installed package')],

       % resolver hints

       [opt(continuefailure),   type(atom),      default(never),                          longflags(['continue-on-failure']),  help('Continue after build failure: never, if-satisfied, if-independent, always')],
       [opt(favour),            type(atom),      default(''),                             longflags(['favour']),               help('Favour package in || dep choices (repeatable)')],
       [opt(avoid),             type(atom),      default(''),                             longflags(['avoid']),                help('Avoid package in || dep choices (repeatable)')],
       [opt(showdescriptions),  type(atom),      default(none),                           longflags(['show-descriptions']),    help('Show USE flag descriptions: none, new, all')],
       [opt(permitdowngrade),   type(boolean),   default(false),                          longflags(['permit-downgrade']),     help('Allow the resolver to pick older package versions')],
       [opt(presetpkg),         type(atom),      default(''),                             longflags(['preset']),               help('Pin a specific version: --preset =cat/pkg-ver (repeatable)')],
       [opt(hidepkg),           type(atom),      default(''),                             longflags(['hide']),                 help('Exclude packages/repos from resolution (repeatable)')],
       [opt(earlypkg),          type(atom),      default(''),                             longflags(['early']),                help('Order matching packages earlier in the plan (repeatable)')],
       [opt(latepkg),           type(atom),      default(''),                             longflags(['late']),                 help('Order matching packages later in the plan (repeatable)')],

       % convenience presets

       [opt(lazy),              type(boolean),   default(false),                          longflags(['lazy']),                 help('Minimal work: skip installed, no deep deps')],
       [opt(complete),          type(boolean),   default(false),                          longflags(['complete']),             help('Full update: deep, newuse, follow build deps')],
       [opt(everything),        type(boolean),   default(false),                          longflags(['everything']),           help('Reinstall everything: emptytree + deep')],

       % lifecycle management

       [opt(background),        type(boolean),   default(false),                          longflags(['background']),           help('Fork to background (daemon and server modes)')],
       [opt(status),            type(boolean),   default(false),                          longflags(['status']),               help('Check if daemon/server is running (ipc and client modes)')],
       [opt(cmd),               type(atom),      default(none),                           longflags(['cmd']),                  help('Send command to daemon/server: halt or relaunch (ipc and client modes)')],

       % build options

       [opt(logs),              type(boolean),   default(false),       shortflags(['l']), longflags(['logs']),                 help('Show build log paths in --build output')],

       % debugging purposes

       [opt(ci),                type(boolean),   default(false),                          longflags(['ci']),                   help('CI mode: non-interactive, fail with nonzero exit code on assumptions')],
       [opt(choicelog),         type(boolean),   default(false),                          longflags(['choice-log']),           help('Log structured resolver choice events to stderr after prove. Use the wrapper (sets -Dchoice_log=true) so emit/wrap sites are compiled in; without it they are compiled out')],
       [opt(profile),           type(boolean),   default(false),                          longflags(['profile']),              help('Enable instrumentation (sampler, debug hooks). Use wrapper or pass -Dinstrumentation=true to swipl.')]
      ].
