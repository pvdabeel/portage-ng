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
%  Binary package consumption ($PKGDIR/Packages, gpkg multi-instance)
% -----------------------------------------------------------------------------
%
% These knobs control whether the builder consumes matching binpkgs from a
% locally-registered binpkg repository (instead of building from source).
% The check is gated on `cache:repository(binpkg)` being present, so all
% knobs are effectively no-ops on hosts that haven't registered a binpkg
% repository in their Source/Config/<host>.local.pl.

%! config:use_binpkg(?Bool)
%
% Master switch for binpkg consumption. When `true`, the builder asks
% `binpkg_exec:available_for/4` for a USE-matching variant before falling
% back to the source-build phase sequence in `ebuild_exec`. Default: true.

config:use_binpkg(true).


%! config:binpkg_respect_use(?Mode)
%
% Mirrors emerge's `--binpkg-respect-use=y|n`. When `strict`, only binpkgs
% whose stored `USE:` exactly matches the resolver's resolved USE (after
% IUSE_EFFECTIVE projection) are eligible. When `relaxed`, USE-mismatched
% binpkgs may still be selected (a warning is logged). Default: strict.

config:binpkg_respect_use(strict).


%! config:binpkg_respect_user_patches(?Bool)
%
% Mirrors emerge's `--binpkg-respect-user-patches=y|n`. When `true` (the
% default), a binpkg is not selected if `/etc/portage/patches` would
% apply to the corresponding ebuild (`${PN}`, `${P}`, `${PF}` or
% `${P}-${PR}`, each optionally `:${SLOT}`). This prevents a binary from
% silently reverting user patches. `--usepkg-include` does not override
% it. Set `false` or pass `--binpkg-respect-user-patches n` to accept
% the binpkg anyway.

config:binpkg_respect_user_patches(true).


%! config:binpkg_changed_deps(?Mode)
%
% Mirrors emerge's `--binpkg-changed-deps=y|n`. When `skip`, binpkgs whose
% recorded RDEPEND differs from the current ebuild's RDEPEND are excluded
% from the candidate set. When `warn`, they are still eligible (a warning
% is logged). Default: warn (less restrictive; binpkg-multi-instance
% already isolates USE drift).

config:binpkg_changed_deps(warn).


%! config:binpkg_refresh(?Policy)
%
% Controls when the in-memory binpkg index is refreshed against the
% on-disk `Packages` file:
%
%   manual : never auto-refresh; the index reflects the last `kb:sync(binpkg)`
%            run. Cheapest, fully predictable.
%   mtime  : on each `binpkg_exec:available_for/4` call, stat the index
%            file and re-run sync(kb) if its mtime is newer than the last
%            load. Useful when external producers are adding binpkgs
%            concurrently with portage-ng builds.
%
% Default: mtime so concurrent binpkg producers (tinderbox-ng shared
% cache) are visible without restarting portage-ng.

config:binpkg_refresh(mtime).


%! config:binpkg_self_inject(?Bool)
%
% Controls whether portage-ng incrementally registers the binary
% packages it produces itself (a source build with `--buildpkg` /
% `--buildpkgonly`, i.e. the `package` phase) directly into the
% in-memory binpkg cache, instead of waiting for the next mtime-driven
% full re-parse of `Packages` to discover them.
%
% When `true`, a successful source build asserts a single
% `cache:ordered_entry/5` (+ minimal metadata) for the freshly produced
% gpkg via `binpkg_exec:inject_built_binpkg/3`, and advances the
% `mtime` baseline so the resident process does NOT re-parse the whole
% ~27 MB index just to pick up its own output (portage-ng#80). This is
% the analogue of emerge's in-memory `bintree.inject()` and is most
% valuable in daemon mode, where the cache is resident across requests.
%
% The `mtime` refresh policy still applies to EXTERNAL producers
% (concurrent emerge / sibling matrix workers): a `Packages` mtime that
% advances past the baseline AFTER an inject still triggers a refresh,
% so cross-process visibility is preserved. Default: true.

config:binpkg_self_inject(true).


%! config:binpkg_debug(?Bool)
%
% When `true`, `binpkg_exec:available_for/4` logs (to `user_error`) the
% reason every binpkg variant of a scheduled package was rejected by the
% acceptance filters whenever NO usable binpkg was found and the build
% therefore falls through to a source compile. The first failing filter
% per variant is reported (gpkg-on-disk / slot / keywords / USE / subslot
% `:=` pin / RDEPEND drift), with the resolved gpkg path for the on-disk
% case so an in-chroot vs host PKGDIR mismatch is visible at a glance.
%
% This is a pure diagnostic: it never changes which binpkgs are accepted.
% Default `false` (zero overhead on the hot path). Intended for pinpointing
% why a closure that emerge satisfies from `[binary]` is rebuilt from
% source instead (e.g. the OCaml stack, portage-ng#81).

config:binpkg_debug(false).


%! config:choice_log(?Bool)
%
% When `true`, the resolver arms the structured choice-event log
% (`choicelog`) at runtime. Hot-path emit/wrap sites are only present
% when loaded with `-Dchoice_log=true` (set by `portage-ng-dev` for
% `--choice-log`); otherwise they are compiled out. Default `false`.

:- dynamic config:choice_log/1.

config:choice_log(false).


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

config:profile_loading(standalone, cached).
config:profile_loading(daemon,     cached).
config:profile_loading(worker,     cached).
config:profile_loading(client,     live).
config:profile_loading(server,     cached).

% Materialized preference state (Knowledge/preference.qlf).  Requires kb:load
% before preference:init.  Stamp covers kb.qlf, profile.qlf, /etc/portage,
% world/set files, use.desc, and USE/ACCEPT_* environment variables.

config:preference_cache(standalone, cached).
config:preference_cache(daemon,     cached).
config:preference_cache(worker,     cached).
config:preference_cache(client,     live).
config:preference_cache(server,     cached).

% -----------------------------------------------------------------------------
%  /etc/portage configuration directory
% -----------------------------------------------------------------------------
%
% Path to the Gentoo /etc/portage configuration directory.  userconfig:load/0
% reads make.conf, package.use, package.mask, package.unmask,
% package.accept_keywords, and package.license from this directory.
%
% On a Gentoo system, set this to '/etc/portage'.
% For development, use the bundled templates in Source/Domain/Gentoo/Preference/UserConfig.
% Comment out to disable file-based configuration entirely (falls back to the
% fallback:env/2 and fallback:package_*/1-2 facts in Preference/fallback.pl).

% config:portage_confdir('/etc/portage').

% Fallback environment defaults, package masks, and per-package USE overrides
% are in Source/Domain/Gentoo/Preference/fallback.pl.  They are only consulted
% when config:portage_confdir/1 is not set (no real /etc/portage configured).


% -----------------------------------------------------------------------------
%  Pkg directory
% -----------------------------------------------------------------------------

%! config:pkg_directory(?FullPath)
%
% Declaration of the pkg db directory on a system. This holds metadata
% for all packages installed on a system (`/var/db/pkg` on a standard
% Gentoo system).
%
% Host-specific: defined in Source/Config/<host>.local.pl (the file loaded
% via config:systemconfig/1), NOT here. Callers guard with
% current_predicate/1 so hosts without a clause fail cleanly.


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
  os:compose_path([Dir,'Source/Knowledge/Sets/world',Hostname],Filename).


%! config:set_dir(-Dir)
%
% Directory containing named set files (one entry per line).
% Each file @Name becomes a preference:local_set('@Name', Entries) fact.

config:set_dir(Dir) :-
  config:installation_dir(Base),
  os:compose_path([Base, 'Source/Knowledge/Sets'], Dir).


% -----------------------------------------------------------------------------
%  GLSA (Gentoo Linux Security Advisories)
% -----------------------------------------------------------------------------

%! config:glsa_dir(?Dir)
%
% Optional override for the on-disk GLSA directory. When unset, GLSA loading
% uses `$PORTDIR/metadata/glsa` from the registered portage repository.
% Declare a host-specific clause in Source/Config/<host>.local.pl if needed.

% config:glsa_dir('/path/to/metadata/glsa').


%! config:glsa_remote(-Url)
%
% Git remote used by `--sync` when `$PORTDIR/metadata/glsa` is missing
% (raw `github.com/gentoo/gentoo` trees omit GLSAs; rsync / gentoo-mirror
% trees already ship them). Official low-volume data repo.

config:glsa_remote('https://anongit.gentoo.org/git/data/glsa.git').


%! config:glsa_injected_file(-File)
%
% Path of the glsa_injected applied-ID file (Portage PRIVATE_PATH equivalent).
% Defaults to a host-local Knowledge path.

config:glsa_injected_file(File) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir, 'Source/Knowledge/Sets/glsa_injected', Hostname], File).


%! config:preserved_libs_registry_override(?File)
%
% Optional host-specific override for the preserve-libs registry path.
% Declare in Source/Config/<host>.local.pl when the default derivation
% (from `config:pkg_directory/1`) does not apply.

:- multifile config:preserved_libs_registry_override/1.
:- dynamic config:preserved_libs_registry_override/1.


%! config:preserved_libs_registry(?File)
%
% Path of Portage's `preserved_libs_registry` JSON (FEATURES=preserve-libs).
% Used by the `@preserved-rebuild` computed set. Prefers
% `config:preserved_libs_registry_override/1` when declared; otherwise
% derives from `config:pkg_directory/1` by mapping `.../db/pkg` →
% `.../lib/portage/preserved_libs_registry` (standard Gentoo layout).

config:preserved_libs_registry(File) :-
  config:preserved_libs_registry_override(File),
  !.

config:preserved_libs_registry(File) :-
  current_predicate(config:pkg_directory/1),
  config:pkg_directory(PkgDir),
  atom_concat(Prefix, '/db/pkg', PkgDir),
  atom_concat(Prefix, '/lib/portage/preserved_libs_registry', File).


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


%! config:verbosity(?Level)
%
% Different verbosity levels may be configured for printing runtime information

config:verbosity(debug).


% -----------------------------------------------------------------------------
%  Passwords
% -----------------------------------------------------------------------------

% The private passwords file is optional for standalone builds. Client
% and server modes call interface:require_digest_password/0 and refuse
% an empty digest password (do not pair empty defaults with a real
% Certificates/passwordfile). Copy template_passwords.pl → passwords.pl,
% set a secret, then `make passwordfile`.

:- if(exists_source(portage('Source/Config/Private/passwords'))).
:- include(portage('Source/Config/Private/passwords')).
:- else.

%! config:certificate_password(?Key,?Pass)
%
% Default (empty) passwords for unencrypted SSL client/server keys.
% Override by creating Source/Config/Private/passwords.pl from the template.

config:certificate_password(server,'').
config:certificate_password(client,'').


%! config:digest_password(?User,?Pass)
%
% Placeholder only when Private/passwords.pl is absent. Empty Pass is
% rejected by interface:require_digest_password/0 before any digest auth.

config:digest_password('portage-ng','').


%! config:digest_realm(?Realm)
%
% Default realm for digest user authentication.

config:digest_realm('portage-ng').

:- endif.


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
% Declares the server hostname the client/worker connects to. This can be
% overridden using the --host option in the interface. Workers that use
% Bonjour discovery only accept a discovered host that matches this pin
% (hostile LAN advertisements are ignored).

config:server_host('mac-pro.local').


%! config:server_bind(?Address)
%
% Interface the HTTPS Pengine server binds to. Default `localhost` keeps
% mutating POSTs (/sync, /clear, /load, …) off the public network; mTLS
% + digest still apply, but binding all interfaces would expose those
% endpoints to any peer that holds a CA-signed client cert and the digest
% password. Override with `*` / `0.0.0.0` only on a trusted VPN/LAN.

config:server_bind(localhost).


%! config:server_port(?Number)
%
% Declares the port on which the server needs to be launched (HTTPS/SSL).
% Combined with config:server_bind/1 (default localhost). Override with
% the --port option in the interface.

config:server_port(4000).


%! config:server_workers(?Count)
%
% Number of HTTP worker threads the server spawns to handle requests.

config:server_workers(32).


%! config:server_keep_alive_timeout(?Seconds)
%
% How long an idle keep-alive HTTP connection is kept open before the
% server closes it.

config:server_keep_alive_timeout(2).


%! config:cluster_result_timeout(?Seconds)
%
% How long a single result poll blocks while collecting distributed
% proving results. On expiry the collector checks for stale in-flight
% jobs (and re-queues them) before polling again.

config:cluster_result_timeout(60).


%! config:cluster_global_deadline(?Seconds)
%
% Overall deadline for collecting all results of a distributed proving
% batch. When reached, cluster:wait/1 returns the results collected so
% far and warns about missing ones instead of waiting forever.

config:cluster_global_deadline(3600).


%! config:cluster_worker_timeout(?Seconds)
%
% A worker is presumed dead when it has not contacted the server for
% this many seconds; its in-flight jobs are then re-queued for other
% workers. Should exceed the longest expected single prove job, since a
% busy single-threaded worker only heartbeats between jobs.

config:cluster_worker_timeout(900).


%! config:server_chunk(?Chunksize)
%
% When set to false, when working in client-server mode, one RPC call is
% performed per solution. When generating large number of solutions, such as
% backtracking over a goal, it is best to transfer multiple solutions in one
% chunk over one rpc call.

% Setting this to a higher value speeds up searching in client-server mode.
% Shouldn't be higher than the total number of entries in your repositories.

config:server_chunk(50000).


%! config:client_auto_import_vdb(?Bool)
%
% When true, client mode automatically (re-)imports the local VDB into the
% server before executing a command (--pretend, --merge, --search, ...):
% the import runs when no import record exists for the target server, or
% when the local VDB changed since the last import (cheap mtime check over
% the VDB root and its category directories). When false, the VDB is only
% shipped explicitly via --import-vdb. See knowledgebase:vdb_repository/1.

config:client_auto_import_vdb(true).


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
  os:compose_path([Dir,'Certificates',Certificate],Fullpath).


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
  os:compose_path([Dir,'Certificates/passwordfile'],Filename).


% -----------------------------------------------------------------------------
%  Graphing
% -----------------------------------------------------------------------------

% Interface can dynamically override graphing behavior for a single run
% (set by action:graph/1 for `--graph modified` and `--graph full`).

:- dynamic config:interface_graph_modified_only/1.

%! config:graph_directory(?FullPath)
%
% This application is capable of writing Graphviz dot files and will turn
% them into interactive scalable vector graphics (svg) to enable you to
% browse through a dependency graph.
%
% Directory doesn't need a trailing '/'.
%
% Host-specific: defined in Source/Config/<host>.local.pl (the file loaded
% via config:systemconfig/1), NOT here. Callers guard with
% current_predicate/1 so hosts without a clause fail cleanly.


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


%! config:graph_repository(?Repository)
%
% Name of the repository graphed by default when `--graph` / `kb:graph`
% (and `--graph emerge` / `kb:graph_emerge`) is invoked. Must match a
% registered repository instance name (typically `portage`).

config:graph_repository(portage).


% -----------------------------------------------------------------------------
%  Emerge file generation (--graph emerge)
% -----------------------------------------------------------------------------

% Interface can dynamically force full regeneration for a single run.
% (Used by `--graph emerge full`.)

:- dynamic config:force_emerge_regen/1.

%! config:emerge_vp_path(?Path)
%
% Per-host path to the `emerge-vp` wrapper used by `--graph emerge` to
% generate `.emerge` files alongside the `.merge` files in the graph
% directory. The wrapper invokes Gentoo's traditional `emerge -vp` so
% portage-ng can render side-by-side comparisons in HTML.
%
% Host-specific: defined in Source/Config/<host>.local.pl (the file loaded
% via config:systemconfig/1), NOT here. When the host config defines no
% clause, `--graph emerge` prints a clear warning instead of writing
% `.emerge` files.


%! config:emerge_vp_timeout(?Seconds)
%
% Per-ebuild timeout for emerge-vp invocations. Mirrors the legacy
% generate-emerge-files.sh default.

config:emerge_vp_timeout(120).


%! config:emerge_vp_concurrency(?N)
%
% Number of parallel emerge-vp workers spawned by `--graph emerge`.
% Defaults to 1 (matches the legacy shell). Increase cautiously: emerge-vp
% inside a gentoo-prefix is fork-heavy and concurrent runs can saturate I/O.

config:emerge_vp_concurrency(1).


%! config:graph_include_emerge(?Bool)
%
% When true, the default `--graph` run also generates `.emerge` files at
% the end of the pipeline (after writing proof files). False by default;
% use `--graph emerge` for explicit regeneration. Set to true on hosts
% where the gentoo-prefix emerge-vp wrapper is available and you want
% one-command refresh of the entire graph directory.

config:graph_include_emerge(false).


%! config:graph_html_type(?List)
%
% Defines all HTML graph types produced by --graph.  Each type maps to a
% self-contained interactive HTML file per ebuild.

config:graph_html_type([detail,deptree,gantt,merge,fetchonly,info,glsa,bugs,emerge]).


%! config:graph_site_url(?Url)
%
% Public origin of the generated graph site, with no trailing slash.
% `--graph` writes robots.txt and sitemap.xml against this host
% (default https://ebuild.portage-ng.ai). Override per host if needed.

config:graph_site_url('https://ebuild.portage-ng.ai').


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
%  Cycle printing
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
%   - `off`      : do not print cycle breaks section
%   - `flat`     : one cycle break per line, compact list (default)
%   - `detailed` : each cycle break on two lines with "- Cycle break:" header

config:print_prover_cycles_style(flat).


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


%! config:print_prover_cycles_max_inferences(?N)
%
% Inference budget for the search that reconstructs one prover cycle
% path (cycle:print_cycle_explanation/3). The depth-bounded searches are
% exponential in the branching factor in the worst case; the budget caps
% them deterministically, so the same plan prints the same explanation
% on every machine. When it is exhausted the explanation is omitted.

config:print_prover_cycles_max_inferences(10000000).


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
% - .portage-ng.css (shared CSS for all HTML graph pages)
% - .proof.css   (used by Scripts/*/print-aha to render proof output)
% - .meslo.ttf   (font used by proof rendering)
%
% Sources are configurable here (defaults are in Documentation/Assets/Graph/).


%! config:graph_asset_source(+Key, -SourcePath)
%
% Returns the source path for a given asset key

config:graph_asset_source(portage_ng_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/Graph/Stylesheets/portage-ng.css'], Source).

config:graph_asset_source(proof_css, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/Graph/Stylesheets/proof.css'], Source).

config:graph_asset_source(meslo_ttf, Source) :-
  config:installation_dir(Dir),
  os:compose_path([Dir,'Documentation/Assets/Graph/Fonts/meslo.ttf'], Source).


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


%! config:mirror_url(?URL) is multi.
%
% HTTPS base URL(s) of distfiles mirrors. The mirror has the same GLEP 75
% directory layout as mirror_root/1. Multiple facts may be present; the
% downloader tries them in declaration order, then falls back to the
% SRC_URI chain. Prefer https. Cleartext http mirrors require
% config:curl_allow_http(true) (see host configs).

:- multifile config:mirror_url/1.

config:mirror_url('https://distfiles.gentoo.org/distfiles').


%! config:curl_allow_http(?Bool)
%
% When false (default), curl is restricted to `--proto =https` and
% cleartext http/ftp URLs are skipped. Set true on a host that uses a
% trusted LAN mirror (e.g. http://mac-pro.local/distfiles). Integrity
% still depends on Manifest hashes (empty checksum lists are rejected).

:- dynamic config:curl_allow_http/1.
:- multifile config:curl_allow_http/1.

config:curl_allow_http(false).


%! config:file_integrity(?Mode)
%
% Integrity policy for Knowledge sidecars (kb.qlf, resume.pl, feedback.pl):
%   * prefer  — verify .sha256 when present; warn and load when absent
%   * require — refuse to load without a matching .sha256 sidecar
%   * off     — skip verification
% Sidecars are written on every save/append by the corresponding writers.

config:file_integrity(prefer).


%! config:mirror_verify_hashes_default(?Policy)
%
% Default hash verification policy for mirror:test_stats:
%
% - none: only check existence + size
% - sample(N): verify hashes for the first N unique distfiles (fast sanity)
% - all: verify hashes for all unique distfiles (expensive)

config:mirror_verify_hashes_default(none).


%! config:mirror_layout_cache_ttl(?Seconds)
%
% TTL (in seconds) for the on-disk cache of the GLEP 75 layout.conf
% reply, written under the active distdir (see download:disk_cache_path/1).
% Mirror layout almost never changes, but clusters of short-lived
% portage-ng processes (external compare matrices, server worker
% pool) would otherwise re-fetch layout.conf for every invocation,
% which both wastes a curl per session (~1s) and adds a real failure
% mode if the mirror flaps. Default 24h is conservative; bump it for
% offline / network-restricted runs.

config:mirror_layout_cache_ttl(86400).


%! config:bugzilla_url(?URL)
%
% Base URL of the Bugzilla instance for --search-bugs (e.g. bugs.gentoo.org).
% Used to query the REST API at <URL>/rest/bug?quicksearch=<term>.

config:bugzilla_url('https://bugs.gentoo.org').


%! config:bugzilla_user_agent(?UA) is det.
%
% User-Agent string for Bugzilla API requests.

config:bugzilla_user_agent('portage-ng/2026 (https://github.com/pvdabeel/portage-ng)').


%! config:bugzilla_scope(?Scope)
%
% Bug population kept by a `bugzilla`-type repository (see
% Source/Domain/Gentoo/bugs.pl): `all` public bugs, or `open` only
% (UNCONFIRMED / CONFIRMED / IN_PROGRESS). The initial crawl of `all`
% fetches roughly 600 pages of 1000 bugs; later syncs only fetch bugs
% whose last_change_time moved.
%
% The bugzilla_* knobs below are dynamic so a host config can override
% them with retractall/assertz (same pattern as config:curl_allow_http/1).

:- dynamic config:bugzilla_scope/1.
:- dynamic config:bugzilla_page_size/1.
:- dynamic config:bugzilla_request_delay/1.
:- dynamic config:bugzilla_search/1.
:- dynamic config:bugzilla_annotate/1.

config:bugzilla_scope(all).


%! config:bugzilla_page_size(?N)
%
% Bugs requested per REST page during a bugzilla repository sync.

config:bugzilla_page_size(1000).


%! config:bugzilla_request_delay(?Seconds)
%
% Politeness pause between consecutive REST pages of one sync.

config:bugzilla_request_delay(2).


%! config:bugzilla_search(?Policy)
%
% Where --search-bugs looks first: `cache_first` answers from the synced
% local bug store and only falls back to the live REST quicksearch when
% nothing matches locally (or no store exists); `rest` always queries the
% Bugzilla REST API directly.

config:bugzilla_search(cache_first).


%! config:bugzilla_annotate(?Bool)
%
% When true, the plan printer lists known open bugs (from the local bug
% store) under each domain assumption that names a package. Silent when
% no store has been synced.

config:bugzilla_annotate(true).


%! config:repository_sync_limit(?Repository, ?PerDay) is multi.
%
% Maximum number of network syncs (`sync(repository)`) of a registered
% repository in any rolling 24-hour window. Repositories without a clause
% are unlimited. Enforced in repository:sync/0; the metadata and kb steps
% still run from local data when the cap is reached. Stamps live in
% Knowledge/<Repository>.sync. Declared in the host config next to the
% repository instance, e.g. `config:repository_sync_limit(bugzilla, 1).`

:- multifile config:repository_sync_limit/2.
:- dynamic config:repository_sync_limit/2.


% -----------------------------------------------------------------------------
%  Repology (--upstream)
% -----------------------------------------------------------------------------

%! config:repology_url(?URL)
%
% Base URL of the Repology instance used by `--upstream`. The API path
% `/api/v1/project/<name>` is appended. The official host is still
% `https://repology.org`. Since 2026-09-13 that domain has been on
% registrar hold and public DNS returns `127.0.0.1` (see
% https://github.com/repology/repology-rs/issues/560). Do not point this
% at another hostname unless AMDmi3 publishes a replacement domain —
% pin the still-live address with `config:repology_address/1` instead.

:- dynamic config:repology_url/1.
:- multifile config:repology_url/1.

config:repology_url('https://repology.org').


%! config:repology_user_agent(?UA) is det.
%
% User-Agent string for Repology API requests (required by their TOS).

config:repology_user_agent('portage-ng/2026 (https://github.com/pvdabeel/prolog)').


%! config:repology_address(?IP)
%
% Optional IPv4 or IPv6 pin passed to curl as
% `--resolve <host>:443:<IP>` so `--upstream` can reach the still-live
% Repology host while public DNS is on hold. No default clause. AMDmi3
% published `92.63.176.157` / `2a03:6f01:1:2::f159` in
% https://github.com/repology/repology-rs/issues/560 — set one of those
% in a host config only as a temporary workaround, and retract it once
% DNS recovers. TLS still verifies the `repology.org` certificate.

:- dynamic config:repology_address/1.
:- multifile config:repology_address/1.


% -----------------------------------------------------------------------------
%  Proving
% -----------------------------------------------------------------------------

%! config:default_rules(?Module)
%
% The rule module the prover falls back to when no pass has scoped one
% explicitly (prover:rule_module/1). The prover itself is rule-set
% agnostic: the resolver stage passes `resolving`, the orderer stage
% passes `ordering`; this default serves query-side model construction
% running outside any pass (printer, builder, interactive queries).

config:default_rules(resolving).


%! config:time_limit(?Limit)
%
% When parsing, proving or planning, use the specified time limit to
% automatically stop computation if it takes too long.
%In seconds.

config:time_limit(300).


%! config:proving_target(?Target)
%
% Fact which controls the test target for prover, orderer, printer and builder
% Set to either:
%
%  - 'install' : Proof using compile-time dependencies only
%  - 'run': Proof using compile- and run-time dependencies

config:proving_target(run).


%! config:reprove_max_retries(?Count)
%
% Maximum number of iterative reprove retries.
%
% This controls the bounded retry loop in prover:prove/10 that handles
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


%! config:shared_dep_use_forcing(?Bool)
%
% When true, the resolver folds a consumer's HARD bracketed USE requirement
% (`dep[flag]`, an unconditional/forcing directive -- NOT a following `[flag=]`)
% onto an already-committed shared provider and reproves so the provider is
% rebuilt with that flag enabled, instead of degrading the consumer to a
% `unsatisfied_constraints` domain assumption (portage-ng#91 sub-mechanism B).
%
% The canonical case is the KDE-Frameworks stack: `dev-qt/qtbase` is committed
% (its `:install` proved) before `kde-frameworks/kcoreaddons` and ~21 siblings
% are resolved, and those need `>=dev-qt/qtbase-6.10.1:6 [ dbus? icu network ]`,
% i.e. `qtbase[icu]`. Because `icu` is not a profile/IUSE default and arrived
% after qtbase was committed `-icu`, the consumers degrade. With this flag the
% resolver learns a persistent `bwu_force(C,N)` for the missing HARD flag; the
% pass continues with the force applied in-place, and all forces learned
% during the pass are flushed as ONE batched reprove when the pass completes
% (portage-ng#94). On the re-proof qtbase's `:install` builds with `icu` and
% the cascade clears.
%
% Scope is deliberately narrow (and self-limiting): it fires only when the
% provider is *already* committed in the current proof pass (so its USE was
% frozen before the flag arrived), only for HARD (forcing) flags that are
% seedable (not profile-masked) and not already default-on, and at most once
% per (provider, flag-set) via the learned-store dedup. Set to `false` to
% disable.

config:shared_dep_use_forcing(true).


%! config:equality_use_follow(?Bool)
%
% When true, a `[flag=]` / `[!flag=]` dependency whose provider could not
% take the projected value is satisfied from the CONSUMER side instead: the
% resolver learns an `eq_follow(C,N)` for the consumer and flushes it through
% the same batched reprove as the shared-dep HARD forces (portage-ng#121).
%
% An equality bracket means "provider.flag == my flag", and the resolver
% projects the consumer's solved value onto the provider. That projection can
% fail to stick two ways: the provider's own REQUIRED_USE overturns it, or a
% hard bracket from another consumer outranks it in the cross-dependency
% merge. Either way the finished plan violates the equality with nothing
% reported. The canonical case is `app-emulation/virtualbox` with X off
% depending on `dev-qt/qtbase:6[X=]`: `gui? ( any-of ( X eglfs wayland ) )`
% puts X straight back on (it is the `+`-default arm), so the provider cannot
% follow and the consumer has to -- which is also the change emerge proposes.
%
% Narrow by construction: it fires only for a flag an equality edge
% projected, only when the provider's settled value contradicts it, only for
% a flag the consumer can flip (in IUSE, not USE_EXPAND, not profile-masked),
% and once per consumer flag-set via the learned-store dedup. Set to `false`
% to disable.

config:equality_use_follow(true).


%! config:dep_model_cache(?Bool)
%
% When true (default), model(dependency(...)):config?{Ctx} query results
% are cached per proof in memo:dep_model_cache_/5 under a hazard-encoded
% key: the full ground context, the prover:assuming flag bits, and a
% selected_cn snapshot signature over the entry's choice-group members
% (variant exploration bypasses the cache).  Because every mutable input
% is part of the key, entries stay valid across fallback tiers, reprove
% passes and partial restarts within one proof; memo:clear_caches drops
% the cache between proofs.  See the design comment at the top of
% Source/Knowledge/query.pl.  Set to `false` to recompute every model
% query (useful for A/B validation).

config:dep_model_cache(true).


%! config:reprove_partial_restart(?Bool)
%
% When true, a reprove retry triggered by a DEFERRED conflict (one
% reported by heuristic:reprove_pending/1 after a pass completed, e.g.
% the batched shared-dep USE-force flush of portage-ng#94) performs a
% conflict-driven PARTIAL restart instead of a full restart: the prover
% prunes only the literals affected by the conflict (the transitive
% dependents-closure of the forced providers over the Triggers index)
% from the completed pass's Proof/Model/Triggers/Constraints and
% resumes proving from that state. Unaffected literals hit the `proven`
% fast path, so deep KDE/GNOME-style stacks avoid re-deriving the
% ~95% of the closure a USE force does not touch.
%
% Conflicts THROWN mid-pass (e.g. cn_domain version conflicts) always
% use the classical full restart: their pass never completed, so there
% is no consistent state to resume from.
%
% Equivalence to a full restart: package actions, USE configurations,
% domain assumptions and cycle-breaks are identical. Cycle-break
% parity relies on the prior-proven witness
% (prover:restart_note_prior_proven/2): benign-cycle classification
% inspects the cycle-stack path, and a resumed pass reaches pruned
% literals through different stacks (kept literals short-circuit via
% the `proven` fast path), so a cycle re-detected on a literal the
% pre-restart pass proved cycle-free is classified benign from the
% witness instead of the path. Wave/step ORDERING may still differ
% slightly: a kept literal retains the body it derived at its
% pass-1 derivation time, while a full restart re-derives it after the
% pass's cross-dep USE accumulation has grown (e.g. a `glib` dep edge
% resolved to "installed glib satisfies" early in pass 1 vs "wait for
% glib update" on the re-pass). Both are valid topological orders of
% their own proofs; making them byte-identical would require
% re-deriving every literal whose resolution consulted mutable
% accumulation state - i.e. a full restart.
%
% Set to `false` to fall back to full restarts for deferred conflicts
% (useful for A/B validation).

config:reprove_partial_restart(true).


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
:- dynamic config:cli_prefix/1.
:- dynamic config:dep_favour/1.
:- dynamic config:dep_avoid/1.
:- dynamic config:dep_preset/1.
:- dynamic config:dep_hide/1.
:- dynamic config:dep_early/1.
:- dynamic config:dep_late/1.
:- dynamic config:continue_on_failure/1.
:- dynamic config:build_live_phases/1.
:- dynamic config:show_use_descriptions/1.
:- dynamic config:show_build_logs/1.

config:color_output.


% Color palette for USE flag display in plan output.
%
% easy (default) -- Classic Portage style:
%   Enabled flags:  red bold      (matches emerge -vp output)
%   Disabled flags: blue bold     (matches emerge -vp output)
%   Assumed flags:  orange
%   Forced/masked:  green bold ()
%
% full -- Detailed reason-based coloring:
%   Enabled  preference (env):     green bold + *
%   Enabled  preference (non-env): red bold
%   Enabled  profile forced:       green bold ()
%   Enabled  package_use:          red bold
%   Enabled  ebuild default:       red italic
%   Disabled preference (env):     green bold + *
%   Disabled preference (non-env): blue bold
%   Disabled profile masked:       green bold ()
%   Disabled package_use:          blue bold
%   Disabled ebuild default:       lightblue italic
%   Disabled default:              darkgray italic

:- dynamic config:color_palette/1.

config:color_palette(full).


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


%! config:powerline_bubbles is semidet.
%
% Succeeds when Powerline private-use bubble caps (U+E0B6/U+E0B4)
% are appropriate for the output terminal. Fails on the Linux console
% (TERM=linux), where angle-bracket bubbles are used instead.

:- dynamic config:powerline_bubbles_cached/1.

config:powerline_bubbles :-
  ( config:powerline_bubbles_cached(Val)
  -> Val == true
  ; ( config:powerline_bubbles_env_ok
    -> asserta(config:powerline_bubbles_cached(true))
    ;  asserta(config:powerline_bubbles_cached(false)),
       fail
    )
  ).


%! config:terminal_env_term(-Term) is semidet.
%
% TERM from the client-forwarded environment (daemon/IPC) or the
% local process environment.

config:terminal_env_term(Term) :-
  ( catch(daemon:client_env('TERM', Term), _, fail)
  -> true
  ;  catch(system:getenv('TERM', Term), _, fail)
  ).


config:powerline_bubbles_env_ok :-
  ( catch(config:terminal_env_term(Term), _, fail)
  -> Term \== linux
  ;  true
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
% Retrieves the tty_size to use for printing, applying client-server
% "context routing": in pengines (server) mode the connected client's
% terminal is used, in ipc mode the daemon uses the size forwarded by the
% ipc client, and otherwise the local terminal is used.
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

% 2. Otherwise use the local terminal size

config:printing_tty_size(H,W) :-
  config:local_tty_size(H,W).


%! config:local_tty_size(-H,-W) is det.
%
% The local process terminal size, falling back to a sane default when
% stdout is not a tty (tty_size/2 may throw outside a real terminal).
%
% This performs no client-server context routing, so it is safe for the
% lightweight ipc client to call without pulling in library(pengines). It
% also backs the local fallback clause of config:printing_tty_size/2.

config:local_tty_size(H,W) :-
  ( catch(tty_size(H,W), _, fail) -> true ; H = 80, W = 160 ).


%! config:print_expand_use(?Bool)
%
% Defines whether we print information that is normally not printed

config:print_expand_use(false).


%! config:use_expand_hidden(?Prefix) is nondet.
%
% USE_EXPAND prefixes hidden from printer output.

config:use_expand_hidden('abi_mips').
config:use_expand_hidden('abi_ppc').
config:use_expand_hidden('abi_riscv').
config:use_expand_hidden('abi_s390').
config:use_expand_hidden('abi_x86').
config:use_expand_hidden('cpu_flags_arm').
config:use_expand_hidden('cpu_flags_ppc').


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
%
% Default is fully live: `--build` behaves like `emerge` and actually
% installs each ebuild into the live filesystem and VDB. Without merge,
% downstream packages cannot find their build deps in /usr (e.g.
% apr-util's configure cannot locate apr-1-config). To dry-run a build
% without touching the live FS, use `--pretend` instead.
%
% Note: ebuild_exec:build_phases/1 is responsible for omitting the
% `test` phase based on FEATURES (see config:features_test_enabled).
% Compute_live_prefix stops at the first phase NOT in this list, so
% removing intermediate phases here would also stub install/merge.

config:build_live_phases([clean, setup, unpack, prepare, configure, compile, test, install, merge]).


%! config:build_serial_retry(?Bool)
%
% When true, a failed parallel-make-sensitive phase (compile, test,
% install) is retried once with MAKEOPTS=-j1 before the build is
% declared failed (portage-ng#25). Environment variables override
% make.conf in Portage's config stack, so the retry forces a serial
% make without touching the user's configuration. Make resumes
% incrementally, so the retry is cheap: it only changes the outcome
% when the original failure was a parallel-make scheduling race
% (e.g. net-analyzer/nsat's link step running before its objects are
% compiled). Deterministic failures fail again immediately.

config:build_serial_retry(true).


%! config:build_transient_retry(?Bool)
%
% When true, a failed phase whose log tail carries the bash PID-reuse
% signature ("wait: pid N is not a child of this shell") is retried
% once before the build is declared failed (portage-ng#76). The
% signature comes from Portage helpers (ecompress, ...) that `wait`
% on a process-substitution pid which bash has lost track of due to
% PID recycling under high fork rates (Gentoo bug #965423, fixed
% upstream in Nov 2025). The failure is environmental and transient,
% not a property of the ebuild, so a single retry of the same phase
% recovers it. Deterministic failures don't match the signature and
% fail immediately, keeping their original semantics.

config:build_transient_retry(true).


%! config:deconflict_collisions(?Mode)
%
% Policy for how the builder reacts when a `merge` phase aborts due to
% Portage's `pkg_preinst` collision-protect check (a file in the package's
% image is already owned by a *different* installed package -- e.g.
% `app-arch/hardlink` vs the installed `sys-apps/util-linux[hardlink]`
% providing `/usr/bin/hardlink`, or `dev-libs/libiconv` vs `sys-libs/glibc`).
% Traditional `emerge` refuses such a package at the resolver (blocker)
% stage; portage-ng instead attempts the build and decides what to do at
% merge time, which is what tinderbox-ng needs (it must exercise the build,
% not stop at the plan). Modes:
%
%   - `off`      : never override; a collision aborts the merge as usual.
%   - `report`   : do not override the merge, but record/surface the
%                  collision as a deconfliction *assumption* (safe default
%                  for real installs -- visible, non-destructive).
%   - `override` : re-run the merge with `FEATURES=-collision-protect
%                  -protect-owned` so the package overwrites the colliding
%                  file(s) and the merge succeeds. The overwritten path ends
%                  up listed in two packages' VDB CONTENTS (dual ownership) --
%                  harmless in an ephemeral tinderbox OverlayFS session, which
%                  is why this is the tinderbox default. The action is always
%                  logged (build log marker) and recorded (`fixup:record/3`,
%                  see Source/Domain/Gentoo/Exceptions/collision.pl) so it is
%                  never silent.
%
% Default is `override` (tinderbox-oriented). A production deployment that
% wants emerge-like safety should set this to `report` in its host config.

config:deconflict_collisions(override).


%! config:ghc_abi_repair(?Bool)
%
% When true, a setup/configure/compile phase failure carrying
% haskell-cabal.eclass's broken-package signature ("Detected broken
% packages: ...", "Please, run 'haskell-updater'") is recovered
% in-transaction (portage-ng#93): the listed packages are rebuilt from
% source at their installed version -- re-registering them in ghc-pkg's
% database with ABI hashes consistent with their just-rebuilt
% dependencies -- and the failed phase is re-run. This is the native
% equivalent of Gentoo's haskell-updater, which traditional emerge
% defers to a manual run (emerge fails the same configure and exits).
% The GHC ABI hash lives only in ghc-pkg's registry, so the sub-slot
% rebuild pass (config:subslot_rebuild/1, portage-ng#89) cannot observe
% this class of breakage.
%
% Bounded: each broken package is rebuilt at most once per session, the
% failed phase is retried at most twice, and repairs are serialized
% across build workers. Every repair leaves a marker in both the
% consumer's and the rebuilt package's build logs and is recorded via
% `fixup:record/3` (see Source/Domain/Gentoo/Exceptions/ghcabi.pl). Set
% to `false` to keep emerge-compatible behaviour (fail and defer to
% haskell-updater).

config:ghc_abi_repair(true).


%! config:ghc_pkg_register(?Bool)
%
% When true, a successful merge of `dev-lang/ghc` triggers
% `ghc-pkg recache` so GHC boot libraries are visible to subsequent
% `dev-haskell/*` configures (portage-ng#108). Complements the reactive
% ghcabi repair for Cabal "Encountered missing or private dependencies"
% (bytestring / deepseq / ghc-prim / template-haskell). Default true;
% silent no-op when `ghc-pkg` is not on PATH.

config:ghc_pkg_register(true).


%! config:ocaml_abi_repair(?Bool)
%
% When true, a configure/compile phase failure carrying an OCaml
% stale-ABI signature (the compiler's "make inconsistent assumptions
% over interface" / "is not a compiled interface" digest errors, an
% "Error: Unbound module" abort, or an ocamlfind package-not-found
% error) is recovered in-transaction (portage-ng#99): the stale
% compiled-unit paths and findlib package names are extracted from the
% failed phase's log, mapped to their installed owners through the VDB
% CONTENTS records, and those owners are rebuilt from source at their
% installed version before the failed phase is re-run. This is the
% OCaml analogue of the GHC ABI repair (config:ghc_abi_repair/1,
% portage-ng#93): OCaml package identity lives in the .cmi interface
% digests and findlib's registry, not in the ebuild sub-slot, so the
% sub-slot rebuild pass (config:subslot_rebuild/1, portage-ng#89)
% cannot observe this class of breakage and traditional emerge simply
% fails the build.
%
% Bounded: each stale owner is rebuilt at most once per session, the
% failed phase is retried at most twice, and repairs are serialized
% across build workers. Every repair leaves a marker in both the
% consumer's and the rebuilt package's build logs and is recorded via
% `fixup:record/3` (see Source/Domain/Gentoo/Exceptions/ocamlabi.pl).
% Set to `false` to keep emerge-compatible behaviour (fail the build).

config:ocaml_abi_repair(true).


%! config:missing_provider_feedback(?Bool)
%
% When true, a build phase that dies because a required command/file
% provider is missing (e.g. `semodule_package: command not found`,
% exit 127) is turned into learned knowledge rather than repaired in
% place (portage-ng#102). The `missing_provider` exception mechanism
% (Source/Domain/Gentoo/Exceptions/missing_provider.pl) scans the failed
% phase's log for a missing-provider signature, resolves it to a concrete
% package (via the VDB CONTENTS reverse-owner index and a small curated
% seed table), and records a `feedback:discovered_dep/4`. The phase still
% fails (the exit code is threaded through unchanged); the builder's
% bounded replan loop (config:missing_provider_max_replan/1) then
% re-derives a plan with the provider unioned into BDEPEND, so the
% provider is proved and ordered before the target on the retry pass.
%
% Unlike the ABI repair mechanisms (ghc/ocaml), this one never rebuilds a
% package in place: plans are derived, never patched. Set to `false` to
% keep emerge-compatible behaviour (fail the build with no discovery).

config:missing_provider_feedback(true).


%! config:missing_provider_max_replan(?N)
%
% Upper bound on the number of times builder:build_loop/2 will re-derive
% and re-run a plan after a build pass records new missing-provider
% discoveries (portage-ng#102). Combined with discovery deduplication in
% feedback:record_discovery/4, this guarantees the replan loop always
% terminates. Must be a non-negative integer.

config:missing_provider_max_replan(3).


%! config:use_enable_feedback(?Bool)
%
% When true, a build phase that dies because a provider was built with
% the wrong USE set (e.g. `KX11Extras: No such file` when
% `kwindowsystem` was merged `-X`) is turned into learned knowledge
% rather than repaired in place (portage-ng#110). The `useenable`
% exception mechanism records a `feedback:discovered_usedep/4` with HARD
% bracketed USE deps; the builder's bounded replan loop then re-derives
% a plan that forces those flags and rebuilds the provider. Plans are
% derived, never patched — no imperative package.use write from the
% hook. Set to `false` to disable.

config:use_enable_feedback(true).


%! config:kernel_config_repair(?Bool)
%
% When true, a build that dies in its `setup` phase because Gentoo's
% linux-info.eclass `CONFIG_CHECK` found the kernel source configuration
% missing (or carrying) a required option is turned into learned knowledge
% rather than repaired in place (portage-ng#105). The `kernelconfig`
% exception mechanism (Source/Domain/Gentoo/Exceptions/kernelconfig.pl)
% parses the required `CONFIG_*` options from the failed phase's log and
% records a `feedback:required_kernel_config/3`. The phase still fails (the
% exit code is threaded through unchanged); the builder's bounded replan
% loop (config:missing_provider_max_replan/1) then re-derives a plan
% carrying a kernel-config-change pre-action ordered before the target,
% and the builder applies the option to the kernel source .config
% (scripts/config + `make olddefconfig`/`modules_prepare`) before the
% packages build, so the CONFIG_CHECK passes.
%
% Like the missing-provider feedback (config:missing_provider_feedback/1),
% this never rebuilds a package in place: plans are derived, never patched.
% It unblocks userspace packages gated on a kernel option (apparmor, ...);
% kernel-module packages that need a full kernel rebuild are only partly
% helped (the option is set, but no kernel rebuild/reboot happens). Set to
% `false` to keep emerge-compatible behaviour (fail the build).

config:kernel_config_repair(true).


%! config:kernel_source_dir(?Dir)
%
% Kernel source directory whose `.config` the linux-info `CONFIG_CHECK`
% reads and the kernelconfig repair (config:kernel_config_repair/1,
% portage-ng#105) edits. Defaults to the eselect-managed /usr/src/linux
% symlink when unset; override per host if the active kernel tree lives
% elsewhere.

config:kernel_source_dir('/usr/src/linux').


%! config:toolchain_reactivation(?Bool)
%
% When true, the Gentoo build domain (`ebuild_exec:maybe_reactivate_toolchain/4`,
% a post-merge hook) re-activates the toolchain right after a toolchain
% package (gcc/clang/binutils/glibc) merges: it runs `gcc-config`
% (regenerating the gcc + ccache-masquerade wrappers) followed by
% `env-update` (regenerating `/etc/profile.env` and the `ld.so.cache`).
% This mirrors what `emerge` does between merges and is required so a
% freshly rebuilt compiler is actually active for the `pkg_setup` probes of
% later packages -- e.g. `gnustep-base/gnustep-make`'s Objective-C runtime
% probe after a `sys-devel/gcc[objc]` rebuild under `FEATURES=ccache`
% (portage-ng#86). The bare `ebuild` CLI, unlike `emerge`, never reactivates
% the toolchain on its own.
%
% The reactivation is serialized under the `portage_pkg_merge` mutex (so it
% never overlaps a concurrent merge) and is tolerant of missing host
% commands: on a non-Gentoo host (e.g. macOS standalone) `gcc-config` /
% `env-update` are simply absent and the hook is a silent no-op.

config:toolchain_reactivation(true).


%! config:subslot_rebuild(?Bool)
%
% When true, the resolver propagates sub-slot (`:=`) ABI changes to
% already-installed reverse-dependencies -- the native equivalent of
% Gentoo's `@preserved-rebuild` / `haskell-updater` pass. When pass 1
% proves a merge whose sub-slot changes versus the installed copy (e.g. a
% `dev-haskell/*` library rebuilt with a new GHC ABI hash, `dev-lang/ocaml`
% with a new ABI, or a `dev-lang/perl` major bump), the proof-obligation
% channel (heuristic:proof_obligation/4 -> abirebuild:obligations/3)
% contributes same-version `:update` rebuild goals (carrying
% `rebuild_reason(subslot_change(...))`) for the installed packages that
% bound to it through a `:=` / `:slot=` dependency. Each rebuild is proven
% in the same pass and ordered after the provider through its own
% dependency edges, keeping `ghc-pkg check` / OCaml's findlib registry
% consistent before the next consumer configures (portage-ng#89).
% Masked / keyword-filtered consumers degrade to domain assumptions
% instead of escalating the proof to the unmask tier (portage-ng#118).
%
% The obligation is transaction-driven: it only fires when a proven merge
% itself changes a `:=` provider's sub-slot, so for the common case it is
% a cheap per-merge-literal check that adds nothing. Set to `false` to
% disable.

config:subslot_rebuild(true).


%! config:features_test_enabled is semidet.
%
% True iff FEATURES (env > make.conf > fallback) contains 'test' with
% positive sense, applying Portage's incremental left-to-right semantics
% ('-test' removes, 'test' adds, last occurrence wins). Returns false if
% FEATURES is unset or preference:getenv is unavailable.

config:features_test_enabled :-
  catch(
    ( preference:getenv('FEATURES', Atom),
      Atom \== '',
      atomic_list_concat(Tokens, ' ', Atom),
      config:features_resolve_test(Tokens, false, true)
    ),
    _,
    fail
  ).

config:features_resolve_test([], State, State).
config:features_resolve_test([test | Rest], _, Out) :-
  !, config:features_resolve_test(Rest, true, Out).
config:features_resolve_test(['-test' | Rest], _, Out) :-
  !, config:features_resolve_test(Rest, false, Out).
config:features_resolve_test([_ | Rest], State, Out) :-
  config:features_resolve_test(Rest, State, Out).


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
%
% The private api_key file is optional. On a fresh checkout (where
% Source/Config/Private/template_api_key.pl has not been copied to
% api_key.pl yet) we fall back to empty keys; llm:check_api_key/2 then
% prints a clear instruction when an LLM service is actually used.

:- if(exists_source(portage('Source/Config/Private/api_key'))).
:- include(portage('Source/Config/Private/api_key')).
:- else.

config:llm_api_key(grok,     '').
config:llm_api_key(chatgpt,  '').
config:llm_api_key(claude,   '').
config:llm_api_key(gemini,   '').
config:llm_api_key(llama,    '').
config:llm_api_key(ollama,   '').

:- endif.


%! config:llm_capability(+Name,-Capability)
%
% Declares prompts to be passed to the LLM

config:llm_capability(context,Capability) :-
  Description="You are interacting with portage-ng, an alternative dependency resolver
               for Gentoo Linux written in SWI-Prolog. portage-ng reads the same Portage
               tree (metadata/md5-cache) and package database (var/db/pkg) as traditional
               Gentoo emerge, but it resolves dependencies using its own Prolog-based
               prover and ordering engine. It is NOT the standard Portage emerge tool.
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

config:llm_capability(architecture,Capability) :-
  Description="portage-ng mechanisms (ground yourself before answering code/design
               questions): pipeline is reader/parser -> prover (Proof/Model/Constraints/
               Triggers AVLs) -> orderer (second prover pass over planning laws,
               projects availability proofs to waves) -> printer -> builder. Domain
               assumptions are proof key rule(assumed(X));
               cycle-breaks are assumed(rule(X)). feedback:* learns build-time deps and
               re-derives plans; prover:learn only narrows version/USE domains. Before
               inventing APIs or file layouts, use sandboxed Prolog to call
               llmknowledge:list_topics, llmknowledge:print_topic(Name),
               llmknowledge:print_handbook(Chapter), or
               llmknowledge:print_source('Source/...', StartLine, NumLines). Topics
               include architecture, proof, assumptions, learning, code_map,
               context_words, howto_inspect. Handbook aliases include architecture,
               prover, assumptions, rules, planning, building, llm, policy.",
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
               :- main. The temporary module is destroyed after execution.
               To inspect portage-ng itself from sandbox, prefer:
               :- llmknowledge:print_topic(code_map).
               :- llmknowledge:print_handbook(architecture).
               :- llmknowledge:print_source('Source/Pipeline/prover.pl', 1, 80).
               Do not attempt filesystem writes, shell, or feedback:record_*/prover:learn
               from sandbox.",
  normalize_space(string(Capability),Description).

% Metacircular diagnose prompts only (excluded from ordinary chat via llm:prompt/1).
config:llm_capability(metacircular,Capability) :-
  Description="You are the metacircular repair advisor for portage-ng. You know how
               plans and proofs are produced: reader/parser builds cache facts; the
               prover builds ProofAVL/ModelAVL/Constraints/TriggersAVL; the orderer
               re-proves ordering laws over the proof and projects waves; the
               printer renders the plan. Domain assumptions use proof key
               rule(assumed(X)); prover cycle-breaks use assumed(rule(X)). Positive
               (actionable) domain assumptions: masked, keyword_filtered, license,
               blocker_assumption. Negative (blocking): non_existent_dependency,
               missing_dependency, required_use_violation, slot_conflict,
               version_no_candidate, version_conflict, unsatisfied_constraints,
               issue_with_model. Build-time learning uses feedback:* (discovered_dep,
               discovered_usedep, excluded_version, required_kernel_config) which
               re-derives the plan — NOT prover:learn (version/USE domains only).
               Deterministic fixups register via fixup:mechanism/1 and
               fixup:phase_retry_hook/10 under Source/Domain/Gentoo/Exceptions/.
               When diagnosing a failed build, respond with ONE Prolog term only,
               optionally fenced as ```prolog ... ```:
               repair_proposal([action(...), ...]) with at most 3 actions.
               Allowed actions:
               action(record_discovery, Repo://Entry, 'cat/pkg', bdepend, Evidence)
               action(record_usedep, Repo://Entry, 'cat/pkg', [use(enable(Flag),none)], Evidence)
               action(record_excluded_version, Cat, Name, Ver, Evidence)
               action(record_kernel_config, Repo://Entry, ['CONFIG_FOO'], Evidence)
               action(draft_fixup, MechanismName, Synopsis, SketchBody)
               Never invent out-of-tree packages. Prefer record_discovery when a
               missing command/header/lib maps to an in-tree Category/Name.
               Evidence should be a structured term citing phase/log lines.
               Do not propose edits to resolving.pl, prover, resolver, or orderer.",
  normalize_space(string(Capability),Description).


%! config:load_llm_modules(?Bool)
%
% When false, `load_modules/1` skips the LLM backends (no provider backends,
% explain, metacircular, or semantic search). Builder/CLI paths that
% need LLM support detect the absence and skip with a warning.
% The fact is consulted by load_modules(Mode), which runs before the
% host config (Source/Config/<host>.local.pl) is loaded, so it must be
% changed here or via retractall/1 + assertz/1 before load_modules/1.

:- dynamic config:load_llm_modules/1.

config:load_llm_modules(true).


%! config:llm_metacircular(?Bool)
%
% Kill-switch for LLM metacircular diagnose-after-build (propose + confirm).

config:llm_metacircular(true).


%! config:llm_server_calls(?Bool)
%
% When true, Pengines clients may call `explainer:call_llm/3` on the
% server (sandbox safelist). Default false: LLM stays host-local so
% authenticated clients cannot burn server API keys or exfiltrate
% prompts. Enable only on a trusted cluster where the server's
% `Source/Config/Private/api_key.pl` is intentionally shared.

:- dynamic config:llm_server_calls/1.

config:llm_server_calls(false).


%! config:llm_metacircular_log_tail(?Bytes)
%
% Maximum bytes of build-log tail included in a metacircular diagnose prompt.

config:llm_metacircular_log_tail(12000).


%! config:llm_metacircular_max_actions(?N)
%
% Cap on actions accepted from a single repair_proposal/1.

config:llm_metacircular_max_actions(3).


%! config:llm_knowledge_max_bytes(?Bytes)
%
% Cap for llmknowledge:handbook/2 and whole-file reads.

config:llm_knowledge_max_bytes(12000).


%! config:llm_knowledge_max_source_lines(?N)
%
% Cap for llmknowledge:source/4 line excerpts.

config:llm_knowledge_max_source_lines(120).


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
config:llm_model(claude,     'claude-sonnet-4-6').
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


%! config:llm_local(?LLM)
%
% Declares which large language models run locally and therefore need no API
% key. The chat driver (llm:check_api_key/2) skips the key requirement for
% these services.

config:llm_local(ollama).


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


%! config:semantic_batch_size(?Size) is det.
%
% Number of texts embedded per HTTP request when building the semantic
% index. Ollama's /api/embed accepts an array of inputs, so batching
% avoids one round-trip per package.

config:semantic_batch_size(64).


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


%! config:download_mbit(?Mbit) is det.
%
% Assumed download link rate in megabits per second (decimal, 1 Mbit =
% 1e6 bit). The Gantt time view and critical-path download bars convert
% Manifest sizes, live git3-src cache size, or the same-C/N Manifest
% average at this rate. Override in the host-local config
% (`retractall(config:download_mbit(_))` then assert) for a different
% link. Default is 100 Mbit/s.

config:download_mbit(100).


% -----------------------------------------------------------------------------
%  Daemon (ultralight mode)
% -----------------------------------------------------------------------------

%! config:daemon_runtime_dir(-Dir) is det.
%
% Directory holding the daemon socket and PID file. Uses XDG_RUNTIME_DIR
% if available, otherwise a per-user directory under /tmp. Pure accessor:
% creation, ownership verification, and permission enforcement (0700) are
% performed by daemon:ensure_runtime_dir/1 at daemon startup.

config:daemon_runtime_dir(Dir) :-
  ( getenv('XDG_RUNTIME_DIR', Dir)
  -> true
  ;  getenv('USER', User),
     atomic_list_concat(['/tmp/portage-ng-', User], Dir)
  ).


%! config:daemon_socket_path(-Path) is det.
%
% Path to the Unix domain socket used by the ultralight daemon.

config:daemon_socket_path(Path) :-
  config:daemon_runtime_dir(Dir),
  atomic_list_concat([Dir, '/portage-ng.sock'], Path).


%! config:daemon_pid_path(-Path) is det.
%
% Path to the PID file co-located with the daemon socket.

config:daemon_pid_path(Path) :-
  config:daemon_runtime_dir(Dir),
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