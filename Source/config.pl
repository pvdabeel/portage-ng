/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CONFIG
Configuration for portage-ng
*/

:- module(config, []).

% =============================================================================
%  CONFIG declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  General
% -----------------------------------------------------------------------------

%! config:name(?Name)
%
% Declares the name of this program.

config:name('portage-ng-dev').


%! config:hostname(?Hostname)
%
% Declares the hostname this program is running on.

config:hostname(Hostname) :- socket:gethostname(Hostname).


%! config:installation_dir(?FullPath)
%
% Declaration of the installation directory of the application source code.
% Needs to be a full path. We serialise some Prolog code to this directory.
% Needs to be passed to prolog as a system flag (See portage-ng.pl)

config:installation_dir(Dir) :-
  file_search_path(portage,Dir),!.


%! config:working_dir(+FullPath)
%
% Declares the current working directory

config:working_dir(Dir) :-
  config:installation_dir(Dir).


% -----------------------------------------------------------------------------
%  Repository
% -----------------------------------------------------------------------------

%! config:trust_metadata(?Bool)
%
% When set to false, we regenerate locally the cache entries
% after syncing with the remote repository. This is expensive,
% so by default we trust and regenerate only for locally changed
% ebuilds or ebuilds with missing cache.

config:trust_metadata(true).


%! config:write_metadata(?Bool)
%
% When ebuilds are changed locally or new ebuilds are created locally
% this will be detected during syncing, and portage will parse the
% ebuild metadata after running it through ebuild.sh.
%
% Prolog facts are updated with the updated metadata.
% If this variable is set to true, we will also create an on-disk
% cache entry for these ebuilds. This cache entry may be overwritten
% by a sync later on by remotely generated cache.

config:write_metadata(true).

% -----------------------------------------------------------------------------
%  Gentoo profile (for Portage parity)
% -----------------------------------------------------------------------------
%
% This is the Gentoo profile path *relative to the Portage tree profiles dir*.
% Example: /usr/portage/profiles/<profile>.
%
% Used by `profile.pl` to generate `preference:profile_use/1` terms.
%
% NOTE: This is intentionally in config (host/system configuration), not in
% preference (user/package preferences).

config:gentoo_profile('default/linux/amd64/23.0/split-usr/no-multilib').

% -----------------------------------------------------------------------------
%  Profile loading strategy
% -----------------------------------------------------------------------------
%
% Controls whether profile data (USE, masks, package.use, license groups)
% is parsed live from the Portage tree at startup, or loaded from a
% pre-serialized cache file (Knowledge/profile.qlf) generated during --sync.
%
% config:profile_loading(+Mode, +Strategy)
%   Mode:     standalone | daemon | worker | client | server
%   Strategy: cached     — load from Knowledge/profile.qlf (fast; requires --sync first)
%             live       — parse profile tree on every preference:init (slower)
%
% When strategy is 'cached' but Knowledge/profile.qlf is missing, falls back to 'live'.
% Default: live for all modes (backward compatible).

config:profile_loading(standalone, live).
config:profile_loading(daemon,     cached).
config:profile_loading(worker,     cached).
config:profile_loading(client,     live).
config:profile_loading(server,     cached).

% -----------------------------------------------------------------------------
%  /etc/portage configuration directory
% -----------------------------------------------------------------------------
%
% Path to the Gentoo /etc/portage configuration directory.  gentoo:load/0
% reads make.conf, package.use, package.mask, package.unmask,
% package.accept_keywords, and package.license from this directory.
%
% On a Gentoo system, set this to '/etc/portage'.
% For development, use the bundled templates in Source/Config/Config/Gentoo.
% Comment out to disable file-based configuration entirely (falls back to the
% config:gentoo_env/2 and config:gentoo_package_*/1-2 facts below).

% config:portage_confdir('/etc/portage').

% Optional: model selected Portage /etc/portage settings without exporting envvars.
% If set, `preference:getenv/2` will consult these when the real environment
% variable is absent.  When config:portage_confdir/1 is set, make.conf values
% take precedence over these facts (but both are consulted).
%
% Example:
%   config:gentoo_env('USE', 'X alsa dbus truetype -systemd -introspection -launcher').
%
% Leave unset (or empty) if you prefer to drive this via real envvars or make.conf.

% Proposed baseline USE to match the parity diffs we observed:
% - Fixes major missing deps driven by disabled flags in portage-ng plans:
%     X       -> xprop/xset/libXtst/... (e.g. xdg-utils, conky)
%     alsa    -> alsa-lib/alsa-ucm-conf/... (e.g. flite)
%     dbus    -> pulls dbus-related deps where emerge has dbus enabled
%     truetype-> matches emerge defaults seen in conky
% - Prevents the known large "extra in merge" chains:
%     -launcher (dbus-broker) and -introspection (glib stack)
%     -systemd  (OpenRC profile expectations)
%
% Mirror Gentoo /etc/portage/make.conf (vm-linux) USE, normalized (last occurrence wins).
% NOTE: The USE string is incremental; "last occurrence wins".
% Keep `introspection` enabled for GNOME/KDE stacks (many deps require glib[introspection]).

config:gentoo_env('USE', 'berkdb harfbuzz lto dnet resolutionkms o-flag-munging pgo graphite optimizations aio npm http split-usr -elogind policykit json -systemd -llvm -lua -berkdb -gdbm -introspection -vala -xen -hcache -ruby python gdbm fbcondecor messages smp qemu sqlite mmxext -svg avahi mmx sse sse2 sse3 ssse3 sse4 sse4_2 gmp cvs git x86emu gpg imap pop sidebar smime smtp dbus truetype X -xvmc xa xkb libkms cairo glitz png jpeg tiff gif mp3 opengl xcb xlib-xcb alsa aac aacplus jpeg2k fontconfig openssl ssh threads x264 x265 xvid dts md5sum a52 aalib zeroconf pkcs11 apng xattr nova account container object proxy directfb pcre16 -mdnsresponder-compat gpm').
config:gentoo_env('VIDEO_CARDS', 'vmware vesa vga').
config:gentoo_env('INPUT_DEVICES', 'evdev keyboard mouse vmmouse').
config:gentoo_env('ALSA_CARDS', 'ens1371').
config:gentoo_env('CPU_FLAGS_X86', 'aes avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3').
config:gentoo_env('PERL_FEATURES', 'ithreads').
config:gentoo_env('ACCEPT_KEYWORDS', '~amd64').
config:gentoo_env('ACCEPT_LICENSE', '-* @FREE').

% -----------------------------------------------------------------------------
%  Gentoo /etc/portage overrides (subset)
% -----------------------------------------------------------------------------
%
% These mirror simple /etc/portage files from your Gentoo system.
% Current scope:
% - package.mask: simple cat/pkg atoms (all versions masked)
% - package.use : per-package USE toggles (plus/minus)
%
% This is intentionally a small, explicit subset to improve parity without
% pulling in the full Portage config stack.

% /etc/portage/package.mask
config:gentoo_package_mask('sys-apps/systemd').

% /etc/portage/package.use
config:gentoo_package_use('app-emulation/open-vm-tools', '-dnet -X -multimon resolutionkms').
config:gentoo_package_use('app-editors/vim',             '-X').
config:gentoo_package_use('dev-lang/swi-prolog',         '-X').
config:gentoo_package_use('www-client/links',            '-X -jpeg -png -tiff').
config:gentoo_package_use('>=sys-libs/gdbm-1.26',        'berkdb').
config:gentoo_package_use('x11-wm/compiz-fusion',         'unsupported emerald').
config:gentoo_package_use('sys-kernel/gentoo-sources',    'symlink build').

% Note: we intentionally do not mirror extra /etc/portage tweaks here unless they
% exist on the Gentoo system (this keeps comparisons honest).


% -----------------------------------------------------------------------------
%  Pkg directory
% -----------------------------------------------------------------------------

%! config:pkg_directory(?Hostname,?FullPath)
%
% Declaration of the pkg db directory on a system. This holds metadata
% for all packages installed on a system

config:pkg_directory('imac-pro.local',    '/Volumes/Disk 1/Repository/pkg')  :- !.
config:pkg_directory('mac-pro.local',     '/Volumes/Storage/Repository/pkg') :- !.
config:pkg_directory('macbook-pro.local', '/Users/pvdabeel/Repository/pkg')  :- !.
config:pkg_directory('vm-linux.local',    '/var/db/pkg')                     :- !.


% -----------------------------------------------------------------------------
%  World file
% -----------------------------------------------------------------------------

%! config:world_file(Path)
%
% Declaration of the world file path. The world file holds the requirements
% for installed packages.

config:world_file(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Sets/world',Hostname],Filename).


% -----------------------------------------------------------------------------
%  Snapshots
% -----------------------------------------------------------------------------

%! config:snapshot_dir(-Dir)
%
% Returns the base directory for snapshots on the current host.

config:snapshot_dir(Dir) :-
  config:installation_dir(Base),
  config:hostname(Hostname),
  os:compose_path([Base, 'Source/Snapshots', Hostname], Dir).


%! config:snapshot_enabled
%
% When asserted, --snapshot is automatically active for every merge.
% Disabled by default. Enable in per-machine config files.

:- dynamic config:snapshot_enabled/0.


% -----------------------------------------------------------------------------
%  System
% -----------------------------------------------------------------------------

%! config:systemconfig(?Filename)
%
% Declares the systemconfig for the host this program is running. This file
% contains system specific configuration settings. The standard setting
% looks whether <hostname>.pl exists in the Source/Config directory. If not
% then Source/Config/default.pl is used. Typically this is used to define the
% different repositories / overlays per hostname.

config:systemconfig(Filename) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir,'Source/Config','default'],Default),
  os:compose_path([Dir,'Source/Config',Hostname],Configuration),
  system:file_name_extension(Configuration,'pl',ConfigFile),
  ( system:exists_file(ConfigFile)
    -> Filename = ConfigFile
    ;  Filename = Default ).


%! config:number_of_cpus(?Count)
%
% This application parallellizes parsing, proving, planning and building.
% SWI prolog is automatically able to determine the maximum cpu count, but
% sometimes we may want to change this to a value of our choice.

config:number_of_cpus(C) :- current_prolog_flag(cpu_count,C).


%! config:number_of_cpus(?Count)
%
% Different verbosity levels may be configured for printing runtime information

config:verbosity(debug).


% -----------------------------------------------------------------------------
%  Passwords
% -----------------------------------------------------------------------------

:- include(portage('Source/Config/Private/passwords')).


% -----------------------------------------------------------------------------
%  Network
% -----------------------------------------------------------------------------

%! config:bonjour_service(?Service)
%
% The mDNS service used to advertise and discover the server on the network.

config:bonjour_service('_portage-ng._tcp.').

%! config:bonjour_worker_service(?Service)
%
% The mDNS service used by workers to advertise compute capacity.

config:bonjour_worker_service('_portage-ng-worker._tcp.').


%! config:server_host(?Url)
%
% Declares the server url, including protocol (https) and port the client needs
% to connect on. This can be overridden using the --host option in the interface.

config:server_host('mac-pro.local').


%! config:server_port(?Number)
%
% Declares the port on which the server needs to be launched.
% Always launches on localhost, using https/ssl. This can be overridden
% using the --port option in the interface.

config:server_port(4000).


%! config:server_chunck(?Chunksize)
%
% When set to false, when working in client-server mode, one % RPC call is
% performed per solution. When generating large number of solutions, such as
% backtracking over a goal, it is best to transfer multiple solutions in one
% chunck over one rpc call.

% Setting this to a higher value speeds up searching in client-server mode.
% Shouldn't be higher than the total number of entries in your repositories.

config:server_chunk(50000).


% -----------------------------------------------------------------------------
%  Certificates
% -----------------------------------------------------------------------------

%! config:initialize_cacert
%
% Initializes the certificate authority. We use certificates in our
% client-server communication.

config:initialize_cacert :-
  config:certificate('cacert.pem',Fullpath),
  create_prolog_flag(system_cacert_filename,Fullpath,[access(read_only)]).


%! config:certificate(+Certificate,-Fullpath)
%
% Returns an absolute path for a given certificate name

config:certificate(Certificate,Fullpath) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates',Certificate],Fullpath).


%! config:certificate(+Hostname,+Certificate,-Fullpath)
%
% Return an absolute path for a given hostname certificate name

config:certificate(Hostname,Certificate,FullPath) :-
  atomic_list_concat([Hostname,Certificate],'.',HostCertificate),
  config:certificate(HostCertificate,FullPath).


%! config:digest_passwordfile(?File)
%
% Declares the password file for http(s) digest user authentication

config:digest_passwordfile(Filename) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Source/Certificates/passwordfile'],Filename).


% -----------------------------------------------------------------------------
%  Graphing
% -----------------------------------------------------------------------------

% Interface can dynamically override graphing behavior for a single run.
% (Used by CLI flags like --graph-modified / --graph-full.)

:- dynamic config:interface_graph_modified_only/1.

%! config:graph_directory(?Hostname,?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% Directory doesn't need a trailing '/'.
%
% We store the generated dot and svg files in the following directory.

config:graph_directory('imac-pro.local',    '/Volumes/Disk 1/Graph')  :- !.
config:graph_directory('mac-pro.local',     '/Volumes/Storage/Graph') :- !.
config:graph_directory('macbook-pro.local', '/Users/pvdabeel/Graph')  :- !.
config:graph_directory('vm-linux.local',    '/root/Graph')            :- !.


%! config:graph_modified_only(?Bool)
%
% Set when you want Graphviz dot file to be created for new ebuilds only

% Note: call sites often query this as `config:graph_modified_only(true)` in an
% if-then-else. Therefore this predicate must *not* have an unconditional
% `.../1` clause that makes `config:graph_modified_only(true)` succeed when the
% effective value is false.
%
% Resolution order:
% - CLI/runtime override (dynamic) via config:interface_graph_modified_only/1
% - Default (can be changed by editing config:graph_modified_only_default/1)

config:graph_modified_only(Bool) :-
  ( config:interface_graph_modified_only(Bool0) ->
      Bool = Bool0
  ; config:graph_modified_only_default(Bool)
  ).

% Default graphing behavior (when CLI didn't override):
% true = graph only modified/new ebuilds
% false = graph everything

config:graph_modified_only_default(true).


%! config:graph_html_type(?List)
%
% Defines all HTML graph types produced by --graph.  Each type maps to a
% self-contained interactive HTML file per ebuild.

config:graph_html_type([detail,deptree,gantt,merge,fetchonly,info,emerge]).


%! config:graph_dependency_type(?List)
%
% Legacy: dependency types for which DOT graphs can be produced.
% No longer part of the default --graph output (superseded by deptree + detail).

config:graph_dependency_type([detail,
                              bdepend,
                              cdepend,
                              depend,
                              idepend,
                              rdepend,
                              pdepend]).


%! config:graph_proof_type(?List)
%
% Legacy: proof types for which DOT graphs can be produced.
% No longer part of the default --graph output (superseded by terminal HTML).

config:graph_proof_type([merge,fetchonly,info]).


%! config:graph_legacy_type(?List)
%
% Legacy: legacy types for which DOT graphs can be produced.
% No longer part of the default --graph output (superseded by terminal HTML).

config:graph_legacy_type([emerge]).


% -----------------------------------------------------------------------------
%  Cycle / SCC printing
% -----------------------------------------------------------------------------

%! config:print_prover_cycles(?Bool)
%
% Whether to print cycle-break explanations (DFS/BFS cycle paths) for
% prover cycle-break assumptions in plan output.  These assumptions
% already appear in the plan as "(assumed running)" / "(assumed
% installed)" line items, so the tree visualisation is redundant.
% Expensive to compute and can produce very large output.

config:print_prover_cycles(false).


%! config:print_prover_cycles_style(?Style)
%
% Display style for the cycle breaks section:
%   - `off`      : do not print cycle breaks section (default)
%   - `flat`     : one cycle break per line, compact list
%   - `detailed` : each cycle break on two lines with "- Cycle break:" header

config:print_prover_cycles_style(off).


%! config:print_prover_cycles_max_total(?N)
%
% Maximum number of prover cycle-break assumptions for which a cycle
% explanation tree is printed.  Additional cycle breaks are summarised
% as "(… N more cycle breaks omitted)".

config:print_prover_cycles_max_total(10).


%! config:print_prover_cycles_max_depth(?N)
%
% Maximum DFS/BFS search depth when constructing prover cycle paths.
% Lower values produce shorter (but possibly incomplete) cycle trees;
% higher values find longer cycles at the cost of more search time.

config:print_prover_cycles_max_depth(25).


%! config:print_scc(?Bool)
%
% Whether to print the scheduler's SCC (strongly connected component)
% decomposition in plan output.  Shows which packages form cyclic
% merge-sets in the planner remainder and the linearization order
% chosen by the scheduler.

config:print_scc(false).


%! config:print_scc_max_members(?N)
%
% Maximum number of SCC members to display per component.
% Components larger than this show only the first N members with
% a summary count.

config:print_scc_max_members(50).


%! config:print_blockers(?Style)
%
% How to display blocker assumptions in plan output.
% Blockers are separated from other domain assumptions into their own
% section.
%
% Styles:
%   off    - no blocker section printed
%   gentoo - compact Portage-like dark-gray lines
%   fancy  - detailed multi-line assumption format with provenance

config:print_blockers(gentoo).


% -----------------------------------------------------------------------------
%  Graphing: static assets
% -----------------------------------------------------------------------------


% When generating HTML (index pages + proofs) we copy a few static assets into the
% repository graph directory (the dir created by repository:prepare_directory/1).
%
% Targets (fixed names in output directory):
%
% - .index.css   (used by writer:write_index_files/2 HTML)
% - .proof.css   (used by Scripts/*/print-aha to render proof output)
% - .meslo.ttf   (font used by proof rendering)
%
% Sources are configurable here (defaults are in Documentation/Assets/).


%! config:graph_asset_source(+Key, -SourcePath)
%
% Returns the source path for a given asset key

config:graph_asset_source(index_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/.index.css'], Source).

config:graph_asset_source(portage_ng_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/portage-ng.css'], Source).

config:graph_asset_source(proof_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/.proof.css'], Source).

config:graph_asset_source(meslo_ttf, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/.meslo.ttf'], Source).


% -----------------------------------------------------------------------------
%  Distfiles / mirrors (analysis + future downloader)
% -----------------------------------------------------------------------------


%! config:mirror_root(?Path)
%
% Default paths used by mirror:test_stats/1 and related tooling.
% These can be overridden at call-site (mirror:test_stats/2), but having a single
% source of truth here makes behavior consistent across CLI and scripts.
%
% - mirror_root/1: hashed distfiles mirror root (GLEP 75 layout.conf aware)
% - Local distfiles directory is configured per machine via distfiles repository

config:mirror_root('/Volumes/Storage/Distfiles/distfiles').

%! config:mirror_url(?URL)
%
% HTTP base URL of the local distfiles mirror. The mirror has the same
% GLEP 75 directory layout as mirror_root/1, served over HTTP.

config:mirror_url('http://mac-pro.local/distfiles').

%! config:mirror_verify_hashes_default(?Policy)
%
% Default hash verification policy for mirror:test_stats:
%
% - none: only check existence + size
% - sample(N): verify hashes for the first N unique distfiles (fast sanity)
% - all: verify hashes for all unique distfiles (expensive)

config:mirror_verify_hashes_default(none).


%! config:bugzilla_url(?URL)
%
% Base URL of the Bugzilla instance for --search-bugs (e.g. bugs.gentoo.org).
% Used to query the REST API at <URL>/rest/bug?quicksearch=<term>.

config:bugzilla_url('https://bugs.gentoo.org').


%! config:bugzilla_user_agent(?UA) is det.
%
% User-Agent string for Bugzilla API requests.

config:bugzilla_user_agent('portage-ng/2026 (https://github.com/pvdabeel/prolog)').


% -----------------------------------------------------------------------------
%  Proving
% -----------------------------------------------------------------------------

%! config:time_limit(?Limit)
%
% When parsing, proving or planning, use the specified time limit to
% automatically stop computation if it takes too long.
%In seconds.

config:time_limit(90).


%! config:proving_target(?Target)
%
% Fact which controls the test target for prover, planner, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).


%! config:reprove_max_retries(?Count)
%
% Maximum number of iterative reprove retries.
%
% This controls the bounded retry loop in prover:prove/9 that handles
% prover_reprove(Info) exceptions.
%
% Important distinction from normal Prolog backtracking:
%
% - Normal backtracking explores alternatives *within one proof attempt* and
%   does not persist learned conflict information once it unwinds.
% - Reprove retries are *iterative refinement*: each retry restarts
%   proving from the target, but keeps scoped no-goods learned from earlier
%   failed attempts (e.g. reject candidate X; then retry and potentially add Y,
%   yielding X+Y on the next attempt).
%
% In short: this is a bounded "learn + restart" loop, not plain in-branch
% backtracking.
%
% Tuning:
%
% - 0 disables iterative retries (single pass only).
% - Higher values allow more refinement but can increase runtime.
%
% Recommended default: 20 (Portage-like retry budget)

config:reprove_max_retries(20).


%! config:avoid_reinstall(?Bool)
%
% If a package is already installed, when this config item is set to true,
% we will verify installation, rather than reinstall the package.

config:avoid_reinstall(false).


% -----------------------------------------------------------------------------
%  Printing
% -----------------------------------------------------------------------------

% Interface can dynamically adjust the verbosity

:- dynamic config:verbose/1.

config:verbose(false).


% Color output is enabled by default. Retract to disable ANSI color/style.

:- dynamic config:color_output/0.
:- dynamic config:cli_jobs/1.
:- dynamic config:cli_load_average/1.
:- dynamic config:excluded_atom/1.
:- dynamic config:skip_atom/1.
:- dynamic config:usepkg_exclude_atom/1.
:- dynamic config:usepkg_include_atom/1.
:- dynamic config:dep_favour/1.
:- dynamic config:dep_avoid/1.
:- dynamic config:dep_preset/1.
:- dynamic config:dep_hide/1.
:- dynamic config:dep_early/1.
:- dynamic config:dep_late/1.
:- dynamic config:continue_on_failure/1.
:- dynamic config:show_use_descriptions/1.
:- dynamic config:show_build_logs/1.

config:color_output.


%! config:output_tty is semidet.
%
% Succeeds when the ultimate output destination is a real TTY.
% In daemon/IPC mode the daemon's user_output is a socket, but
% the client's stdout may be a TTY -- daemon:client_is_tty is
% asserted when the client reports a TTY.

:- dynamic config:output_tty_cached/1.

config:output_tty :-
  ( config:output_tty_cached(Val)
  -> Val == true
  ; ( ( stream_property(user_output, tty(true))
      ; catch(daemon:client_is_tty, _, fail)
      )
    -> asserta(config:output_tty_cached(true))
    ;  asserta(config:output_tty_cached(false)),
       fail
    )
  ).


% Interface can dynamically set the printing style

:- dynamic config:interface_printing_style/1.

% The default printing style

config:default_printing_style('fancy').


%! confg:printing_style(?Setting)
%
% Retrieves the printing style ('short', 'column' or 'fancy')
%
% 1. Running as a server, use client style

config:printing_style(Style) :-
  pengine_self(M),
  !,
  M:printing_style(Style).

% 2. Not running as a server, use interface style when specified,
%    otherwise default

config:printing_style(Style) :-
  config:interface_printing_style(Style),!.

config:printing_style(Style) :-
  \+(config:interface_printing_style(_)),
  config:default_printing_style(Style).


%! config:printing_tty_size(?H,?W)
%
% Retrieves the tty_size to use for printing
%
% 1. Running as a server, use client tty_size

config:printing_tty_size(H,W) :-
  pengine_self(M),
  !,
  M:printing_tty_size(H,W).

% 1b. Running as daemon, use client-provided tty_size

config:printing_tty_size(H,W) :-
  catch(daemon:client_tty_size(H,W), _, fail),
  !.

% 2. Otherwise use actual tty_size

config:printing_tty_size(H,W) :-
  catch(tty_size(H,W), _, fail),
  !.

% 3. Fallback in case actual tty_size cannot be retrieved

config:printing_tty_size(80,160).


%! config:print_expand_use(?Bool)
%
% Defines whether we print information that is normally not printed

config:print_expand_use(false).


%! config:printable_metadata(?List)
%
% Defines which elements in which order to print out when printing ebuild
% information. Use 'blank' to put blank lines in output. Use 'hl' to output
% a horizontal line.

config:printable_metadata([blank,
                           hl, % -------------
                           description,
                           homepage,
                           maintainer,
                           license,
                           eapi,
                           slot,
  		                     subslot,
                           hl, % -------------
                           iuse,
                           required_use,
                           keywords,
                           properties,
                           eclasses,
                           defined_phases,
                           installed,
                           hl, % -------------
                           src_uri,
                           hl, % -------------
                           bdepend,
                           blank,
                           depend,
                           blank,
                           idepend,
                           blank,
                           rdepend,
                           blank,
                           pdepend
                          ]).


% -----------------------------------------------------------------------------
%  Testing
% -----------------------------------------------------------------------------

%! config:test_style(?Style)
%
% Sets the default test style for executing tests. Can be either:
% - single_verbose
% - parallel_verbose
% - parallel_fast

config:test_style(parallel_verbose).


%! config:test_stats_top_n(?N)
%
% How many items to show in "Top cycle mentions" in test statistics output.
%
% Note: must be a non-negative integer.

config:test_stats_top_n(25).


%! config:test_stats_table_width(?Width)
%
% Total table width (characters) including the 2-space left indent.

config:test_stats_table_width(80).

%! config:test_stats_label_col_width(?Width)
%
% Width of the leftmost label/metric column.

config:test_stats_label_col_width(34).

%! config:test_stats_pct_col_width(?Width)
%
% Width of a percentage column.

config:test_stats_pct_col_width(10).

%! config:test_stats_rank_col_width(?Width)
%
% Width of the rank-number column in ranked tables.

config:test_stats_rank_col_width(4).

%! config:test_stats_count_col_width(?Width)
%
% Width of a count column (aligned with pct columns at 10 chars).

config:test_stats_count_col_width(10).


%! config:bugreport_drafts_enabled(?Bool)
%
% Whether to print "Bug report drafts (Gentoo Bugzilla)" in the warnings section
% when domain assumptions are present.
%
config:bugreport_drafts_enabled(true).


%! config:bugreport_drafts_max_assumptions(?N)
%
% Only print bug report drafts when the number of domain assumptions is small,
% to avoid overwhelming output for bulk runs.
%
% Note: must be a non-negative integer.
%
config:bugreport_drafts_max_assumptions(25).


%! config:failsilenton(?Key)
%
% Fails silently (i.e. without messaging failure on the termimal.
% Key can be:
% - version : fails silently when trying to parse versions from git repositories

config:failsilenton(version).


% -----------------------------------------------------------------------------
%  Building
% -----------------------------------------------------------------------------

%! config:build_live_phases(?Phases)
%
% List of ebuild phases that are actually executed during --build.
% Phases not in this list are stubbed (displayed but not run).
% An empty list means fully stubbed (equivalent to old dry_run_build(true)).
% The full sequence [clean,setup,unpack,prepare,configure,compile,test,install,merge]
% means fully live (equivalent to old dry_run_build(false)).
% When --buildpkg is active, the `package` phase appears between
% `install` and `merge` (added dynamically by ebuild_exec:build_phases/1).

config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test]).


%! config:dry_run_build(?Bool)
%
% Derived predicate for backward compatibility.
% Succeeds with true when build_live_phases is empty (fully stubbed).

config:dry_run_build(true) :-
  config:build_live_phases([]).


%! config:time_limit_build(?Limit)
%
% When executing a plan (i.e. building) use the specified time limit to
% automatically stop the build process if it takes too long. Note this limit
% applies to an entire step in a plan.
% In seconds.

config:time_limit_build(6000).


%! config:ebuild_command(?Command)
%
% Path or name of the `ebuild` CLI binary (from sys-apps/portage).
% Used by ebuild_exec:run_phases/3 to execute build phases.
% Override in per-machine config files if ebuild lives outside PATH
% (e.g. Gentoo Prefix installations).

:- dynamic config:ebuild_command/1.

config:ebuild_command(ebuild).


%! config:build_root(?Path)
%
% Root directory for build work (PORTAGE_TMPDIR equivalent).
% Portage defaults to /var/tmp/portage; override here or per-machine.

config:build_root('/var/tmp/portage').


%! config:build_log_dir(?Path)
%
% Directory where per-package build logs are stored. Each build action
% produces a log file that captures all phase stdout/stderr output.
% Override per-machine if desired.

config:build_log_dir('/var/tmp/portage-ng/logs').


% -----------------------------------------------------------------------------
%  Large Language Models
% -----------------------------------------------------------------------------

%! config:llm_api_key(?LLM,?Key)
%
% Declares the private API key for each large language model.

:- include(portage('Source/Config/Private/api_key')).


%! config:llm_capability(+Name,-Capability)
%
% Declares prompts to be passed to the LLM

config:llm_capability(context,Capability) :-
  Description="You are interacting with portage-ng, an alternative dependency resolver
               for Gentoo Linux written in SWI-Prolog. portage-ng reads the same Portage
               tree (metadata/md5-cache) and package database (var/db/pkg) as traditional
               Gentoo emerge, but it resolves dependencies using its own Prolog-based
               prover, planner, and scheduler. It is NOT the standard Portage emerge tool.
               When diagnosing issues, keep in mind: (1) the Portage tree, installed
               packages, USE flags, keywords, and profiles are identical to a real Gentoo
               system; (2) dependency resolution errors come from portage-ng's solver, not
               from emerge; (3) domain assumptions indicate deps that portage-ng could not
               satisfy (e.g. missing metadata, USE flag mismatches, keyword restrictions);
               (4) portage-ng uses terms like 'grouped_package_dependency', 'selected_cn',
               'cn_domain', and 'prover:learned' which are internal solver concepts, not
               standard Portage terminology. Do not suggest running emerge commands to fix
               portage-ng issues. Focus on the dependency metadata and constraints instead.",
  normalize_space(string(Capability),Description).

config:llm_capability(chat,Capability) :-
  Description="When formulating a response, you may optionally enclose a message
               (e.g., a question) in <call:chatgpt>, <call:gemini>, <call:ollama>,
               or <call:claude> tags to send it to the respective LLM. The response
               is automatically returned to you, with each LLM maintaining its own
               history of your queries.",
  normalize_space(string(Capability),Description).

config:llm_capability(code,Capability) :-
  Description="When asked to write SWI-Prolog code, you may optionally enclose the
               code in <call:swi_prolog> XML tags. Any code within these tags will
               be executed locally in a temporary module, with the output
               automatically returned to you. Do not mention the XML tags unless
               you include SWI-Prolog code between them. Write the code as if it
               were loaded from a separate source file, including triggering
               execution of your main function using a :- directive, such as
               :- main. The temporary module is destroyed after execution.",
  normalize_space(string(Capability),Description).


%! config:llm_support(-Prompt)
%
% Declares prompts to be passed to the LLM in case of merge failure

config:llm_support(Capability) :-
  Description="portage-ng (a Prolog-based alternative dependency resolver for Gentoo)
               failed to resolve the following target against a standard Portage tree.
               This is NOT the traditional emerge tool. The package may be missing from
               the Portage tree, renamed, moved to a different category, or have empty
               metadata cache entries. Please help identify the correct package atom or
               suggest what might be wrong. Give a short answer. Here is what was
               requested: ",
  normalize_space(string(Capability),Description).


%! config:llm_use_tools(?Bool)
%
% Declares whether or not to enable to code execution integration

config:llm_use_tools(true).


%! config:llm_max_tokens(?Max)
%
% Declares the maximum tokens returned by an LLM

config:llm_max_tokens(4096).


%! config:llm_temperature(?Temperature)
%
% Declares how creative or predictable the LLM should be

config:llm_temperature(0.7).


%! config:llm_sandboxed_execution(?Bool)
%
% Declares whether to turn on or turn off the LLM code execution sandbox

config:llm_sandboxed_execution(true).


%! config:llm_default(?Service)
%
% Declares the default LLM service used by explainer:explain/2.

config:llm_default(claude).


%! config:llm_model(?LLM,?Key)
%
% Declares which version of each large language model to use.

config:llm_model(grok,       'grok-4-1-fast-reasoning').
config:llm_model(chatgpt,    'gpt-4o').
config:llm_model(claude,     'claude-sonnet-4-5').
config:llm_model(gemini ,    'gemini-3-pro-preview').
config:llm_model(llama ,     'Llama-4-Maverick-17B-128E-Instruct-FP8').
config:llm_model(ollama ,    'llama3.2').


%! config:llm_endpoint(?LLM,?Endpoint)
%
% Declares the https endpoint url for each large language model.

config:llm_endpoint(grok,    'https://api.x.ai/v1/chat/completions').
config:llm_endpoint(chatgpt, 'https://api.openai.com/v1/chat/completions').
config:llm_endpoint(claude,  'https://api.anthropic.com/v1/messages').
config:llm_endpoint(gemini,  'https://generativelanguage.googleapis.com/v1beta/chat/completions').
config:llm_endpoint(llama,   'https://api.llama.com/v1/chat/completions').
config:llm_endpoint(ollama,  'http://localhost:11434/v1/chat/completions').


% -----------------------------------------------------------------------------
%  Semantic search (natural-language package search via embeddings)
% -----------------------------------------------------------------------------

%! config:semantic_search_enabled(?Bool) is det.
%
% Enable or disable natural-language semantic search. When false,
% --search falls back to structured queries only and --train-model
% is a no-op.

config:semantic_search_enabled(true).


%! config:semantic_model(?Model) is det.
%
% The Ollama model used for generating embeddings.

config:semantic_model('nomic-embed-text').


%! config:semantic_endpoint(?Endpoint) is det.
%
% The Ollama embeddings API endpoint.

config:semantic_endpoint('http://localhost:11434/api/embed').


%! config:semantic_top_n(?N) is det.
%
% Number of results returned by a semantic search query.

config:semantic_top_n(10).


% -----------------------------------------------------------------------------
%  Build time estimation
% -----------------------------------------------------------------------------

%! config:emerge_log_path(?Path) is semidet.
%
% Path to emerge.log for reading historical build durations.
% Comment out or remove to disable emerge.log parsing.

config:emerge_log_path('/var/log/emerge.log').


%! config:buildtime_enabled(?Bool) is det.
%
% Enable or disable build time estimation in plan output.

config:buildtime_enabled(true).


% -----------------------------------------------------------------------------
%  Daemon (ultralight mode)
% -----------------------------------------------------------------------------

%! config:daemon_socket_path(-Path) is det.
%
% Path to the Unix domain socket used by the ultralight daemon.
% Uses XDG_RUNTIME_DIR if available, otherwise /tmp.

config:daemon_socket_path(Path) :-
  ( getenv('XDG_RUNTIME_DIR', Dir)
  -> true
  ;  getenv('USER', User),
     atomic_list_concat(['/tmp/portage-ng-', User], Dir)
  ),
  ( \+ exists_directory(Dir) -> make_directory(Dir) ; true ),
  atomic_list_concat([Dir, '/portage-ng.sock'], Path).

%! config:daemon_pid_path(-Path) is det.
%
% Path to the PID file co-located with the daemon socket.

config:daemon_pid_path(Path) :-
  ( getenv('XDG_RUNTIME_DIR', Dir)
  -> true
  ;  getenv('USER', User),
     atomic_list_concat(['/tmp/portage-ng-', User], Dir)
  ),
  ( \+ exists_directory(Dir) -> make_directory(Dir) ; true ),
  atomic_list_concat([Dir, '/portage-ng.pid'], Path).

%! config:daemon_inactivity_timeout(?Seconds) is det.
%
% Seconds of inactivity after which the daemon auto-shuts down.
% 0 means never auto-shutdown.

config:daemon_inactivity_timeout(1800).

%! config:daemon_autostart(?Bool) is det.
%
% When true (default), --mode ipc auto-starts a background daemon if
% none is running. When false, prints an error instead.

config:daemon_autostart(true).