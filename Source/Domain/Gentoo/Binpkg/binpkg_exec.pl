/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BINPKG_EXEC
USE-aware selection and qmerge invocation for Portage binary packages.

This is the binpkg-side counterpart to `ebuild_exec`. It is the *only*
module that knows how to drive Portage's `ebuild qmerge` from a
pre-extracted gpkg, and the only place that decides whether a binpkg is
acceptable in lieu of a source build.

# Public surface

  - `binpkg_exec:available_for(+SrcRepo, +SrcEntry, +Ctx, -BinpkgEntryId)`
    is the dispatch probe. Given the resolver's resolved (SrcRepo,
    SrcEntry, Ctx), find a binpkg variant whose stored USE / SLOT /
    KEYWORDS are compatible with what the resolver asked for. Fails (no
    side-effects) if no candidate fits or if the binpkg repo is not
    registered. When multiple candidates pass the filters, the highest
    BUILD_ID wins (mirrors emerge's "newer wins" tie-breaker). The
    probe also honors `config:binpkg_refresh/1` to optionally re-read
    the on-disk `Packages` index when an external producer has updated
    it since the last load.

  - `binpkg_exec:execute(+Action, +SrcRepo, +SrcEntry, +BinpkgEntryId, +Ctx, -Outcome)`
    performs the binary merge:
      1. Resolve gpkg path from the binpkg repo's location + the
         entry's `path` metadata.
      2. Resolve the source ebuild path from SrcRepo (qmerge's `ebuild`
         CLI insists on a path inside a real portage tree).
      3. Compose the build dir under `config:build_root/1`.
      4. Delegate extraction to `binpkg_extract:prepare_builddir/3`.
      5. Spawn `ebuild --skip-manifest <SRC_EBUILD> qmerge` with
         `MERGE_TYPE=binary`, `PORTAGE_BINPKG_FILE=<gpkg>`,
         `PORTAGE_BUILDDIR=<builddir>`, and the resolver's USE.
      6. Bind Outcome to `done` on success, `failed(qmerge_exit(N))` on
         non-zero exit, or `failed(Reason)` for setup errors.

# Configuration knobs (all in `Source/config.pl`) and their CLI overrides

  - `config:use_binpkg(true|false)`         -- master switch; any of
    `--usepkg` / `--usepkg-only` / `--getbinpkg` / `--getbinpkg-only`
    turns consumption on for the run (`consumption_enabled/0`)
  - `--usepkg-only` / `--getbinpkg-only`   -- no source fallback
    (`binary_only/0`, honoured by ebuild_exec's dispatch)
  - `--usepkg-include` / `--usepkg-exclude` / `--usepkg-exclude-live`
    -- per-package allow / deny lists (`entry_allowed/2`)
  - `config:binpkg_respect_use(strict|relaxed)` -- USE matching mode;
    `--binpkg-respect-use` forces strict (`respect_use_policy/1`)
  - `config:binpkg_respect_user_patches(true|false)` -- skip binpkgs when
    `/etc/portage/patches` would apply; `--binpkg-respect-user-patches n`
    disables (`respect_user_patches_policy/1`). `--usepkg-include` does
    not override this (same as emerge).
  - `config:binpkg_changed_deps(skip|warn)`     -- RDEPEND-drift policy;
    `--binpkg-changed-deps` forces skip (`changed_deps_policy/1`)
  - `config:binpkg_refresh(manual|mtime)`       -- index refresh policy

  The binpkg repository is a local `Packages` index: there is no BINHOST
  to download from, so `--getbinpkg` / `--getbinpkg-only` behave as
  `--usepkg` / `--usepkg-only`.

# What this module does NOT do

  - Implement preinst/install/postinst/VDB-write itself. That logic
    (~6700 lines of Python) is delegated to `ebuild qmerge`, which calls
    `portage/dbapi/vartree.py:merge()` internally.
  - Re-fetch / verify the gpkg. We trust the `Packages` index hash
    fields. (qmerge does its own MD5 verification anyway.)
  - Mutate the binpkg repository. Production of binpkgs is owned by
    `ebuild_exec` (when `--buildpkg` is active) or external producers
    such as concurrent build-harness matrix sessions.

The end-to-end recipe was validated empirically against
`app-misc/jq-1.8.1` BUILD_IDs 8 (oniguruma=on) and 10 (oniguruma=off);
both produced the expected USE-distinct VDB entries and runtime library
linkages.
*/

:- module(binpkg_exec, []).

% =============================================================================
%  BINPKG_EXEC declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Run-time policy: CLI flags over config defaults
% -----------------------------------------------------------------------------

%! binpkg_exec:consumption_enabled is semidet.
%
% Binary packages may be consumed in this run: `config:use_binpkg(true)`
% is the host default, and any of `--usepkg`, `--usepkg-only`,
% `--getbinpkg`, `--getbinpkg-only` turns consumption on for the run.

binpkg_exec:consumption_enabled :-
  ( preference:flag(usepkg)
  ; preference:flag(usepkgonly)
  ; preference:flag(getbinpkg)
  ; preference:flag(getbinpkgonly)
  ; config:use_binpkg(true)
  ),
  !.


%! binpkg_exec:binary_only is semidet.
%
% `--usepkg-only` / `--getbinpkg-only`: a merge step without a usable
% binpkg fails instead of falling back to a source build.

binpkg_exec:binary_only :-
  ( preference:flag(usepkgonly)
  ; preference:flag(getbinpkgonly)
  ),
  !.


%! binpkg_exec:entry_allowed(+SrcRepo, +SrcEntry) is semidet.
%
% Binary packages may be used for this source entry: a `--usepkg-include`
% atom forces consumption for its packages; otherwise consumption must be
% enabled and the package must not match a `--usepkg-exclude` atom nor, under
% `--usepkg-exclude-live`, carry PROPERTIES=live. Atoms are `cat/name` or
% `name` (the same shapes as `--exclude`). User patches under
% `config:portage_confdir/1/patches` still skip the binpkg unless
% `--binpkg-respect-user-patches n` (or `config:binpkg_respect_user_patches(false)`).

binpkg_exec:entry_allowed(SrcRepo, SrcEntry) :-
  cache:ordered_entry(SrcRepo, SrcEntry, C, N, Version),
  ( config:usepkg_include_atom(Pattern),
    binpkg_exec:cn_matches_atom(C, N, Pattern)
  -> true
  ;  binpkg_exec:consumption_enabled,
     \+ ( config:usepkg_exclude_atom(Pattern),
          binpkg_exec:cn_matches_atom(C, N, Pattern) ),
     \+ ( preference:flag(usepkgexcludelive),
          ebuild:is_live(SrcRepo://SrcEntry) )
  ),
  binpkg_exec:user_patches_allow(SrcRepo, SrcEntry, C, N, Version).


%! binpkg_exec:cn_matches_atom(+C, +N, +Pattern) is semidet.

binpkg_exec:cn_matches_atom(C, N, Pattern) :-
  ( N == Pattern
  ; atomic_list_concat([C, N], '/', Pattern)
  ),
  !.


%! binpkg_exec:respect_use_policy(-Mode) is det.
%
% USE matching mode for use_compatible/4: `--binpkg-respect-use` forces
% `strict`, otherwise `config:binpkg_respect_use/1` (default strict).

binpkg_exec:respect_use_policy(Mode) :-
  ( preference:flag(binpkgrespectuse) -> Mode = strict
  ; config:binpkg_respect_use(Mode0)  -> Mode = Mode0
  ; Mode = strict
  ).


%! binpkg_exec:changed_deps_policy(-Mode) is det.
%
% RDEPEND-drift policy for rdepend_acceptable/3: `--binpkg-changed-deps`
% forces `skip`, otherwise `config:binpkg_changed_deps/1` (default warn).

binpkg_exec:changed_deps_policy(Mode) :-
  ( preference:flag(binpkgchangeddeps) -> Mode = skip
  ; config:binpkg_changed_deps(Mode0)  -> Mode = Mode0
  ; Mode = warn
  ).


%! binpkg_exec:respect_user_patches_policy(-Mode) is det.
%
% `respect` (default) skips a binpkg when `/etc/portage/patches` would
% apply to the source ebuild. `ignore` accepts the binpkg anyway
% (`--binpkg-respect-user-patches n` or `config:binpkg_respect_user_patches(false)`).

binpkg_exec:respect_user_patches_policy(Mode) :-
  ( preference:flag(nobinpkgrespectuserpatches) -> Mode = ignore
  ; config:binpkg_respect_user_patches(false)   -> Mode = ignore
  ; Mode = respect
  ).


% -----------------------------------------------------------------------------
%  User patches (/etc/portage/patches) vs binpkg consumption
% -----------------------------------------------------------------------------

:- dynamic binpkg_exec:user_patches_warned/2.


%! binpkg_exec:user_patches_allow(+SrcRepo, +SrcEntry, +C, +N, +Version) is semidet.
%
% Succeeds when a binpkg may still be used for this source entry under
% the user-patch policy. Fails (and warns once per CN) when `respect`
% is on and a matching `*.patch` / `*.diff` exists.

binpkg_exec:user_patches_allow(SrcRepo, SrcEntry, C, N, Version) :-
  ( binpkg_exec:respect_user_patches_policy(ignore)
  -> true
  ;  binpkg_exec:src_slot(SrcRepo, SrcEntry, Slot),
     binpkg_exec:user_patches_apply(C, N, Version, Slot, PatchDir)
  -> binpkg_exec:warn_user_patches(C, N, PatchDir),
     fail
  ;  true
  ).


%! binpkg_exec:warn_user_patches(+C, +N, +PatchDir) is det.

binpkg_exec:warn_user_patches(C, N, PatchDir) :-
  ( binpkg_exec:user_patches_warned(C, N)
  -> true
  ;  assertz(binpkg_exec:user_patches_warned(C, N)),
     message:warning(['binpkg: skipping binary for ', C, '/', N,
                      ' because user patches apply (', PatchDir, ')'])
  ).


%! binpkg_exec:src_slot(+SrcRepo, +SrcEntry, -Slot) is det.
%
% Source SLOT, or `0` when the ebuild does not declare one.

binpkg_exec:src_slot(SrcRepo, SrcEntry, Slot) :-
  ( cache:entry_metadata(SrcRepo, SrcEntry, slot, slot(Slot0))
  -> Slot = Slot0
  ; cache:entry_metadata(SrcRepo, SrcEntry, slot, Slot0),
    atomic(Slot0),
    Slot0 \== ''
  -> Slot = Slot0
  ; Slot = '0'
  ).


%! binpkg_exec:user_patches_apply(+C, +N, +Version, +Slot, -PatchDir) is semidet.
%
% First `/etc/portage/patches` directory that matches this CN/version/slot
% and contains a `*.patch` or `*.diff` file. Fails when `portage_confdir`
% is unset, `patches/` is absent, or no matching directory has patch files.
% Directory names follow portage(5): `${P}-${PR}[:${SLOT}]`, `${P}[:${SLOT}]`,
% `${PN}[:${SLOT}]` (PF is `${PN}-${PVR}` and is also checked).

binpkg_exec:user_patches_apply(C, N, Version, Slot, PatchDir) :-
  current_predicate(config:portage_confdir/1),
  config:portage_confdir(ConfDir),
  os:compose_path([ConfDir, 'patches'], PatchesRoot),
  exists_directory(PatchesRoot),
  binpkg_exec:user_patch_leafs(N, Version, Slot, Leafs),
  member(Leaf, Leafs),
  os:compose_path([PatchesRoot, C, Leaf], Candidate),
  binpkg_exec:directory_has_patch_files(Candidate),
  !,
  PatchDir = Candidate.


%! binpkg_exec:user_patch_leafs(+Name, +Version, +Slot, -Leafs) is det.

binpkg_exec:user_patch_leafs(Name, Version, Slot, Leafs) :-
  binpkg_exec:version_pvr(Version, PV, PVR, Rev),
  atomic_list_concat([Name, PV], '-', P),
  atomic_list_concat([Name, PVR], '-', PF),
  format(atom(PPR), '~w-~w-r~w', [Name, PV, Rev]),
  format(atom(SlotS), '~w', [Slot]),
  atomic_list_concat([PF, SlotS], ':', PFSlot),
  atomic_list_concat([P, SlotS], ':', PSlot),
  atomic_list_concat([PPR, SlotS], ':', PPRSlot),
  atomic_list_concat([Name, SlotS], ':', PNSlot),
  Leafs = [PF, PFSlot, PPR, PPRSlot, P, PSlot, Name, PNSlot].


%! binpkg_exec:version_pvr(+Version, -PV, -PVR, -Rev) is det.
%
% Splits a `version/7` term or display atom into PV (no revision), PVR
% (display string) and numeric revision (0 when absent).

binpkg_exec:version_pvr(version(_,_,_,_,_,Rev,Full), PV, Full, Rev) :-
  !,
  atom_string(Full, FullS),
  eapi:split_revision(FullS, PVS, _),
  atom_string(PV, PVS).
binpkg_exec:version_pvr(version_none, none, none, 0) :- !.
binpkg_exec:version_pvr(Version, PV, PVR, Rev) :-
  version_domain:display_atom(Version, PVR),
  atom_string(PVR, PVRStr),
  eapi:split_revision(PVRStr, PVS, Rev),
  atom_string(PV, PVS).


%! binpkg_exec:directory_has_patch_files(+Dir) is semidet.
%
% True when Dir exists and contains a non-hidden regular file whose name
% ends in `.patch` or `.diff`.

binpkg_exec:directory_has_patch_files(Dir) :-
  exists_directory(Dir),
  directory_files(Dir, Names),
  member(Name, Names),
  \+ sub_atom(Name, 0, 1, _, '.'),
  ( sub_atom(Name, _, _, 0, '.patch')
  ; sub_atom(Name, _, _, 0, '.diff')
  ),
  os:compose_path([Dir, Name], File),
  exists_file(File),
  !.

%! binpkg_exec:available_for(+SrcRepo, +SrcEntry, +Ctx, -BinpkgEntryId) is semidet.
%
% Master entry point used by `ebuild_exec:execute/5`'s dispatch hook to
% decide whether to short-circuit a source build with a binary merge.
% Fails silently and cheaply if any of the following holds:
%   - binpkg consumption is off for this entry (entry_allowed/2)
%   - the `binpkg` repository isn't registered (`cache:repository(binpkg)` absent)
%   - the source entry's category/name/version can't be derived
%   - no binpkg variant of the same (cat, name, version) exists
%   - none of the candidates pass the USE / SLOT / keywords filters
%
% On success, BinpkgEntryId is the chosen variant's cache entry id
% (e.g. `'app-misc/jq-1.8.1-9'`). The decision policy when multiple
% candidates pass is "highest BUILD_ID wins".

binpkg_exec:available_for(SrcRepo, SrcEntry, Ctx, BinpkgEntryId) :-
  binpkg_exec:entry_allowed(SrcRepo, SrcEntry),
  cache:repository(binpkg),
  % Hold the binpkg index lock across BOTH the (possibly index-rewriting)
  % refresh AND the candidate scan. A concurrent `sync(kb)` swap takes the
  % same lock for its retract+assert, so this probe can never observe a
  % half-swapped index -- it sees either the full old snapshot or the full
  % new one, never an empty/partial one (portage-ng#80, item D).
  with_mutex(binpkg_index_lock,
    binpkg_exec:refresh_and_collect_candidates(SrcRepo, SrcEntry, Ctx, Candidates)),
  Candidates \== [],
  binpkg_exec:pick_best_candidate(Candidates, BinpkgEntryId).


%! binpkg_exec:refresh_and_collect_candidates(+SrcRepo, +SrcEntry, +Ctx, -Candidates) is det.
%
% Runs the configured index-refresh policy and then collects all binpkg
% variants of the source entry's (cat, name, version) that pass the
% eligibility filters. Always succeeds (binding Candidates to `[]` when
% the source entry is unknown or no variant qualifies). Must be called
% with `binpkg_index_lock` held.

binpkg_exec:refresh_and_collect_candidates(SrcRepo, SrcEntry, Ctx, Candidates) :-
  binpkg_exec:maybe_refresh_index,
  ( binpkg_exec:src_entry_cnv(SrcRepo, SrcEntry, Cat, Name, Version)
  -> findall(Bid-Eid,
             ( cache:ordered_entry(binpkg, Eid, Cat, Name, Version),
               cache:entry_metadata(binpkg, Eid, build_id, Bid),
               binpkg_exec:candidate_passes_filters(SrcRepo, SrcEntry, Eid, Ctx)
             ),
             Candidates),
     ( Candidates == []
     -> binpkg_exec:maybe_diagnose_rejection(SrcRepo, SrcEntry, Ctx, Cat, Name, Version)
     ;  true
     )
  ;  Candidates = []
  ).


% -----------------------------------------------------------------------------
%  Rejection diagnostics (config:binpkg_debug/1, default off)
% -----------------------------------------------------------------------------

%! binpkg_exec:maybe_diagnose_rejection(+SrcRepo, +SrcEntry, +Ctx, +Cat, +Name, +Version) is det.
%
% When `config:binpkg_debug(true)` and no usable binpkg was found for a
% scheduled (Cat, Name, Version), report -- to `user_error` -- why each
% binpkg variant was rejected (or that no variant exists). Pure diagnostic;
% never affects acceptance. No-op (cheap fact check) when debug is off.

binpkg_exec:maybe_diagnose_rejection(SrcRepo, SrcEntry, Ctx, Cat, Name, Version) :-
  ( config:binpkg_debug(true)
  -> findall(Eid, cache:ordered_entry(binpkg, Eid, Cat, Name, Version), Variants),
     ( Variants == []
     -> binpkg_exec:log_binpkg_debug("no binpkg variant indexed for ~w/~w-~w (source build)",
                                     [Cat, Name, Version])
     ;  forall(member(Eid, Variants),
               binpkg_exec:diagnose_candidate(SrcRepo, SrcEntry, Eid, Ctx))
     )
  ;  true
  ).


%! binpkg_exec:diagnose_candidate(+SrcRepo, +SrcEntry, +BinpkgEid, +Ctx) is det.
%
% Report the first acceptance filter that rejects this binpkg variant.
% Mirrors the conjunction order in candidate_passes_filters/4 so the
% reported reason is the one that actually blocked selection.

binpkg_exec:diagnose_candidate(SrcRepo, SrcEntry, Eid, Ctx) :-
  ( \+ binpkg_exec:gpkg_on_disk(Eid)
  -> ( binpkg_exec:gpkg_path(Eid, GpkgPath) -> true ; GpkgPath = '<unresolved>' ),
     binpkg_exec:log_binpkg_debug("reject ~w: gpkg not on disk (resolved path: ~w)",
                                  [Eid, GpkgPath])
  ; \+ binpkg_exec:slot_compatible(SrcRepo, SrcEntry, Eid)
  -> binpkg_exec:log_binpkg_debug("reject ~w: slot/subslot incompatible with source", [Eid])
  ; \+ binpkg_exec:keywords_acceptable(Eid)
  -> binpkg_exec:log_binpkg_debug("reject ~w: KEYWORDS unacceptable for host arch", [Eid])
  ; \+ binpkg_exec:use_compatible(SrcRepo, SrcEntry, Eid, Ctx)
  -> binpkg_exec:respect_use_policy(Mode),
     binpkg_exec:log_binpkg_debug("reject ~w: USE incompatible (binpkg_respect_use=~w)",
                                  [Eid, Mode])
  ; \+ binpkg_exec:subslot_pins_compatible(Eid)
  -> binpkg_exec:log_binpkg_debug("reject ~w: subslot := pin mismatch vs live VDB (ABI cascade)",
                                  [Eid])
  ; \+ binpkg_exec:rdepend_acceptable(SrcRepo, SrcEntry, Eid)
  -> binpkg_exec:log_binpkg_debug("reject ~w: RDEPEND drift", [Eid])
  ;  binpkg_exec:log_binpkg_debug("~w: passes all filters (not the rejection cause)", [Eid])
  ).


%! binpkg_exec:log_binpkg_debug(+Fmt, +Args) is det.
%
% Emit a single `binpkg-debug:` prefixed line to `user_error`.

binpkg_exec:log_binpkg_debug(Fmt, Args) :-
  format(user_error, "binpkg-debug: ", []),
  format(user_error, Fmt, Args),
  nl(user_error).


% -----------------------------------------------------------------------------
%  Index refresh policy (config:binpkg_refresh/1)
% -----------------------------------------------------------------------------

%! binpkg_exec:last_index_mtime(?Repository, ?Mtime) is nondet.
%
% Per-repository baseline: the on-disk mtime of the `Packages` index as
% it was when we last loaded it into the in-memory cache. Used by the
% `mtime` refresh policy to detect external changes (new binpkgs dropped
% by a concurrent producer) without paying for a full re-parse on every
% probe. Mtime is a SWI-Prolog float (seconds since the epoch, as
% returned by `time_file/2`).

:- dynamic binpkg_exec:last_index_mtime/2.


%! binpkg_exec:maybe_refresh_index is det.
%
% Honors `config:binpkg_refresh/1` at the start of `available_for/4`:
%
%   - manual : never auto-refresh (default; cheapest, fully predictable).
%   - mtime  : stat the index file and, if its mtime is newer than the
%              recorded baseline, re-run `binpkg:sync(kb)` before answering.
%
% Always succeeds. Missing config or unknown policy degrades to `manual`
% so an operator typo never silently disables binpkg dispatch.

binpkg_exec:maybe_refresh_index :-
  ( config:binpkg_refresh(Policy) -> true ; Policy = manual ),
  binpkg_exec:apply_refresh_policy(Policy).


%! binpkg_exec:apply_refresh_policy(+Policy) is det.
%
% Dispatch on the policy atom. The `mtime` branch is serialized via the
% shared `binpkg_index_lock` so it can neither race another probe nor
% interleave with the retract+assert swap in `repository:sync(kb)`
% (both hold the same lock). The lock is recursive, so it is safe to
% call this from a context that already holds it (e.g. `available_for/4`,
% `ensure_index_fresh/0`).

binpkg_exec:apply_refresh_policy(manual) :- !.

binpkg_exec:apply_refresh_policy(mtime) :- !,
  with_mutex(binpkg_index_lock,
             binpkg_exec:refresh_if_stale(binpkg)).

binpkg_exec:apply_refresh_policy(_).


%! binpkg_exec:ensure_index_fresh is det.
%
% Mtime-gated, atomic (re)load of the on-disk binpkg index into the
% in-memory cache. This is the single entry point callers use to make
% sure the binpkg cache is current before they need it:
%
%   - `builder:prepare_binpkg_index/0` at build start, and
%   - the local daemon before each request (so a long-lived daemon acts
%     as a shared, always-fresh binpkg index service; portage-ng#80,
%     item D).
%
% Behaviour:
%   - no-op when binpkg consumption is off or the repo isn't registered;
%   - on the FIRST observation in a process, always syncs (the resident
%     cache may be an empty register or a stale `kb.qlf` snapshot --
%     portage-ng#24);
%   - thereafter syncs ONLY when the `Packages` mtime advanced past the
%     recorded baseline (portage-ng#80, item A: a back-to-back build on
%     an unchanged index pays one stat, not a full 27 MB re-parse).
%
% The work runs under `binpkg_index_lock`, so it is atomic with respect
% to concurrent `available_for/4` probes and never leaves the cache
% empty (a failed/partial parse keeps the previous snapshot intact).
% Always succeeds.

binpkg_exec:ensure_index_fresh :-
  ( binpkg_exec:consumption_enabled,
    cache:repository(binpkg)
  -> with_mutex(binpkg_index_lock,
                binpkg_exec:refresh_if_stale(binpkg))
  ;  true
  ).


%! binpkg_exec:refresh_if_stale(+Repository) is det.
%
% Compare the index file's current mtime against the recorded baseline:
%
%   - First observation: record the baseline AND re-sync. We cannot
%     assume the in-memory cache matches the on-disk index here:
%     `kb:register/1` does not parse `Packages`, and a `Knowledge/kb.qlf`
%     generated at the last `--sync` may carry a stale binpkg snapshot
%     (portage-ng#24). Build flows reach this first-observation sync via
%     `binpkg_exec:ensure_index_fresh` (called from
%     `builder:prepare_binpkg_index` and the daemon); a probe arriving
%     outside a prepared build pays the same one-time parse cost here.
%   - Newer mtime than baseline: update the baseline and call
%     `Repository:sync(kb)` to re-load the in-memory cache from disk.
%   - Same or older mtime: no-op.
%
% Exceptions during stat or sync are caught so a transient failure
% (e.g. the index file disappearing mid-probe) degrades to "use the
% cache we have" rather than breaking dispatch. Always succeeds.

binpkg_exec:refresh_if_stale(Repository) :-
  catch(binpkg_exec:probe_index_mtime(Repository, Disk), _, fail), !,
  ( binpkg_exec:last_index_mtime(Repository, Prev)
  -> ( Disk > Prev
     -> retractall(binpkg_exec:last_index_mtime(Repository, _)),
        assertz(binpkg_exec:last_index_mtime(Repository, Disk)),
        catch(Repository:sync(kb), _, true)
     ;  true
     )
  ;  assertz(binpkg_exec:last_index_mtime(Repository, Disk)),
     catch(Repository:sync(kb), _, true)
  ).

binpkg_exec:refresh_if_stale(_).


% -----------------------------------------------------------------------------
%  Incremental self-inject of just-built binpkgs (portage-ng#80)
% -----------------------------------------------------------------------------

%! binpkg_exec:inject_built_binpkg(+SrcRepo, +SrcEntry, +Ctx) is det.
%
% Register a binary package that THIS process just produced (a source
% build with `--buildpkg` / `--buildpkgonly`) directly into the
% in-memory binpkg cache, without re-parsing the on-disk `Packages`
% index. This is the analogue of emerge's `bintree.inject()`: the
% builder already holds every fact a later `available_for/4` probe needs
% (category, name, version, resolved USE, slot), and the only
% binpkg-specific fields -- the BUILD_ID and the gpkg path -- are read
% straight off the freshly written archive in `$PKGDIR`.
%
% The row is asserted under `binpkg_index_lock`, so it is atomic with
% respect to a concurrent `available_for/4` / `sync(kb)` and never
% leaves the index in a partial state. The `mtime` baseline is then
% advanced to the current `Packages` mtime so the resident process does
% not turn around and re-parse the whole index just to rediscover its
% own output; an EXTERNAL producer that bumps the mtime AFTER this still
% triggers a normal refresh (see `refresh_if_stale/1`).
%
% Always succeeds (no-op when self-inject is disabled, binpkg
% consumption is off, the repo is not registered, or the produced gpkg
% cannot be located). Any error is swallowed: a failed inject must never
% fail an otherwise successful build -- worst case the binpkg is simply
% rediscovered by the next mtime refresh.

binpkg_exec:inject_built_binpkg(SrcRepo, SrcEntry, Ctx) :-
  ( config:binpkg_self_inject(true),
    binpkg_exec:consumption_enabled,
    cache:repository(binpkg)
  -> catch(binpkg_exec:do_inject_built_binpkg(SrcRepo, SrcEntry, Ctx), _, true)
  ;  true
  ).


%! binpkg_exec:do_inject_built_binpkg(+SrcRepo, +SrcEntry, +Ctx) is semidet.
%
% The body of `inject_built_binpkg/3`: resolve the produced gpkg, build
% the cache row, and swap it in under the index lock. Fails (caught by
% the wrapper) when the source entry is unknown or no matching gpkg is
% on disk.

binpkg_exec:do_inject_built_binpkg(SrcRepo, SrcEntry, Ctx) :-
  cache:ordered_entry(SrcRepo, SrcEntry, Cat, Name, Version),
  binpkg_exec:built_gpkg(Cat, Name, Version, RelPath, BuildId),
  eapi:version_full(Version, VFull),
  atomic_list_concat([Cat, '/', Name, '-', VFull, '-', BuildId], EntryId),
  binpkg_exec:built_binpkg_metadata(SrcRepo, SrcEntry, Ctx, BuildId, RelPath, Meta),
  with_mutex(binpkg_index_lock,
    ( retractall(cache:ordered_entry(binpkg, EntryId, _, _, _)),
      retractall(cache:entry_metadata(binpkg, EntryId, _, _)),
      assertz(cache:ordered_entry(binpkg, EntryId, Cat, Name, Version)),
      forall(member(Key-Value, Meta),
             assertz(cache:entry_metadata(binpkg, EntryId, Key, Value))),
      ( cache:category(binpkg, Cat)     -> true ; assertz(cache:category(binpkg, Cat)) ),
      ( cache:package(binpkg, Cat, Name) -> true ; assertz(cache:package(binpkg, Cat, Name)) ),
      ( cache:repository(binpkg)        -> true ; assertz(cache:repository(binpkg)) ),
      % Absorb our own `Packages` write into the baseline so the next
      % probe does not re-parse the full index to rediscover this row.
      % ONLY when a baseline already exists: a missing baseline means no
      % first-observation sync has happened yet, and creating one here
      % would suppress that initial full resync (which guards against a
      % stale kb.qlf snapshot -- portage-ng#24). In the normal build flow
      % `prepare_binpkg_index` has already anchored the baseline before
      % any inject runs.
      ( binpkg_exec:last_index_mtime(binpkg, _),
        catch(binpkg_exec:probe_index_mtime(binpkg, NewMtime), _, fail)
      -> retractall(binpkg_exec:last_index_mtime(binpkg, _)),
         assertz(binpkg_exec:last_index_mtime(binpkg, NewMtime))
      ;  true
      )
    )).


%! binpkg_exec:built_gpkg(+Cat, +Name, +Version, -RelPath, -BuildId) is semidet.
%
% Locate the gpkg this process just produced for (Cat, Name, Version) by
% globbing `<PKGDIR>/<Cat>/<Name>/<Name>-<VFull>-*.gpkg.tar` and picking
% the highest BUILD_ID (the most recent build wins -- mirrors
% `pick_best_candidate/2`). RelPath is the gpkg path relative to the
% binpkg repo root, in the same shape `cache:entry_metadata(.., path, ..)`
% carries (`<Cat>/<Name>/<basename>`). Fails when the repo root is
% unknown or no matching archive exists.

binpkg_exec:built_gpkg(Cat, Name, Version, RelPath, BuildId) :-
  binpkg:get_location(Root),
  eapi:version_full(Version, VFull),
  atomic_list_concat([Name, '-', VFull], Pf),
  atomic_list_concat([Root, '/', Cat, '/', Name, '/', Pf, '-*.gpkg.tar'], Pattern),
  expand_file_name(Pattern, Files),
  findall(Bid-Rel,
          ( member(File, Files),
            file_base_name(File, Base),
            atomic_list_concat([Cat, '/', Name, '/', Base], Rel),
            binpkg_index:path_build_id(Rel, Bid)
          ),
          Pairs),
  Pairs \== [],
  binpkg_exec:pick_best_candidate(Pairs, RelPath),
  memberchk(BuildId-RelPath, Pairs).


%! binpkg_exec:built_binpkg_metadata(+SrcRepo, +SrcEntry, +Ctx, +BuildId, +RelPath, -Meta) is det.
%
% Assemble the minimal `Key-Value` metadata an `available_for/4` probe
% needs to accept this freshly-built binpkg:
%
%   - build_id / path : binpkg-specific identity (qmerge needs `path`).
%   - use             : the resolver's resolved positive USE -- by
%                       construction identical to what a later probe
%                       recomputes, so the strict USE filter matches.
%   - slot            : the source entry's SLOT (`slot/subslot` when a
%                       subslot is present), so the SLOT filter matches.
%
% KEYWORDS and the DEPEND-family fields are deliberately omitted: their
% absence makes the corresponding filters accept-by-default, which is
% exactly right for a binpkg just built against the live system (its
% `:=` subslot pins necessarily match the current VDB, and it was built
% for this host's arch).

binpkg_exec:built_binpkg_metadata(SrcRepo, SrcEntry, Ctx, BuildId, RelPath, Meta) :-
  binpkg_exec:resolver_positive_use(SrcRepo, SrcEntry, Ctx, UseToks),
  atomic_list_concat(UseToks, ' ', UseAtom),
  ( binpkg_exec:src_slot_combined(SrcRepo, SrcEntry, SlotComb)
  -> SlotPairs = [slot-SlotComb]
  ;  SlotPairs = []
  ),
  append([build_id-BuildId, path-RelPath, use-UseAtom], SlotPairs, Meta).


%! binpkg_exec:src_slot_combined(+SrcRepo, +SrcEntry, -Combined) is semidet.
%
% Resolve the source entry's SLOT as the combined `slot/subslot` atom
% (or the bare slot when no subslot is recorded), matching the shape the
% binpkg `Packages` index stores. Fails when the source has no slot
% info, in which case the caller omits the slot field entirely.

binpkg_exec:src_slot_combined(SrcRepo, SrcEntry, Combined) :-
  query:search(slot(Slot), SrcRepo://SrcEntry),
  ( query:search(subslot(Sub), SrcRepo://SrcEntry), Sub \== ''
  -> atomic_list_concat([Slot, '/', Sub], Combined)
  ;  Combined = Slot
  ).


%! binpkg_exec:record_index_baseline(+Repository, +Mtime) is det.
%
% Anchor the `mtime` refresh policy after an externally-performed sync.
% Mtime is the index file's mtime probed BEFORE that sync (or the atom
% `none` when the index was missing); recording the pre-sync value
% guarantees that an index update racing the sync is still picked up by
% the next probe. Retained as a utility; the in-tree sync paths now flow
% through `binpkg_exec:ensure_index_fresh/0`, which anchors the baseline
% itself via `refresh_if_stale/1`.

binpkg_exec:record_index_baseline(Repository, none) :- !,
  retractall(binpkg_exec:last_index_mtime(Repository, _)).

binpkg_exec:record_index_baseline(Repository, Mtime) :-
  retractall(binpkg_exec:last_index_mtime(Repository, _)),
  assertz(binpkg_exec:last_index_mtime(Repository, Mtime)).


%! binpkg_exec:probe_index_mtime(+Repository, -Mtime) is semidet.
%
% Resolve the repository's `Packages` index path via its OO `get_cache/1`
% accessor, confirm the file exists, and return its current mtime.
% Fails if the binpkg instance is uninitialized or the index is missing.

binpkg_exec:probe_index_mtime(Repository, Mtime) :-
  Repository:get_cache(IndexFile),
  exists_file(IndexFile),
  time_file(IndexFile, Mtime).


%! binpkg_exec:src_entry_cnv(+SrcRepo, +SrcEntry, -Cat, -Name, -Version) is semidet.
%
% Derives (Category, Name, Version) for a source entry id, in the same
% form used by `cache:ordered_entry/5`. Looks up the entry's existing
% cache row (cheap, indexed) instead of re-parsing the atom.

binpkg_exec:src_entry_cnv(SrcRepo, SrcEntry, Cat, Name, Version) :-
  cache:ordered_entry(SrcRepo, SrcEntry, Cat, Name, Version), !.


%! binpkg_exec:pick_best_candidate(+Candidates, -BestEid) is det.
%
% Candidates is a non-empty list of `BuildId-Eid` pairs; BestEid is the
% Eid with the highest BuildId (the most recent build). The standard
% order of terms compares the integer keys numerically; BuildId is unique
% per binpkg, so there are no ties to break.

binpkg_exec:pick_best_candidate(Candidates, BestEid) :-
  max_member(_-BestEid, Candidates).


% -----------------------------------------------------------------------------
%  Candidate filters
% -----------------------------------------------------------------------------

%! binpkg_exec:candidate_passes_filters(+SrcRepo, +SrcEntry, +BinpkgEid, +Ctx) is semidet.
%
% Conjunction of all eligibility checks for a candidate binpkg:
%   1. On-disk gpkg archive present (index entry may be stale)
%   2. SLOT compatibility
%   3. KEYWORDS acceptability for the host ARCH
%   4. USE compatibility (modulated by respect_use_policy/1)
%   5. Subslot-pin (`:slot/subslot=`) compatibility against the live VDB
%   6. RDEPEND drift (modulated by changed_deps_policy/1)
%
% Each check is a separate predicate so individual policies stay
% testable in isolation.

binpkg_exec:candidate_passes_filters(SrcRepo, SrcEntry, BinpkgEid, Ctx) :-
  binpkg_exec:gpkg_on_disk(BinpkgEid),
  binpkg_exec:slot_compatible(SrcRepo, SrcEntry, BinpkgEid),
  binpkg_exec:keywords_acceptable(BinpkgEid),
  binpkg_exec:use_compatible(SrcRepo, SrcEntry, BinpkgEid, Ctx),
  binpkg_exec:subslot_pins_compatible(BinpkgEid),
  binpkg_exec:rdepend_acceptable(SrcRepo, SrcEntry, BinpkgEid).


%! binpkg_exec:gpkg_on_disk(+BinpkgEntryId) is semidet.
%
% Succeeds when the on-disk gpkg archive for this index entry exists.
% The Packages index can list variants whose files were removed or never
% synced into this session (common on tinderbox-ng shared binpkg caches).

binpkg_exec:gpkg_on_disk(BinpkgEntryId) :-
  binpkg_exec:gpkg_path(BinpkgEntryId, GpkgPath),
  exists_file(GpkgPath).


%! binpkg_exec:slot_compatible(+SrcRepo, +SrcEntry, +BinpkgEid) is semidet.
%
% Both SLOT and (when present) SUBSLOT must match. Storage shapes differ
% per repo type:
%   - binpkg cache: a single `slot` field with combined value (e.g. `'0/1'`).
%                   Crucially, Portage *omits* the SLOT line entirely from
%                   the Packages index when SLOT="0" (the default), as a
%                   space optimization. We treat a missing field as if the
%                   binpkg recorded `SLOT="0"`.
%   - eapi  cache: split into `slot/1` + `subslot/1` rows (e.g. `slot('0')`,
%                  `subslot('1')`).
%
% We split the binpkg's combined value on `/`, then compare the slot
% halves first (always required) and the subslot halves only if both
% sides supply one.

binpkg_exec:slot_compatible(SrcRepo, SrcEntry, BinpkgEid) :-
  ( cache:entry_metadata(binpkg, BinpkgEid, slot, BinpkgSlotFull)
  -> binpkg_exec:split_slot(BinpkgSlotFull, BinpkgSlot, BinpkgSubSlot)
  ;  BinpkgSlot = '0', BinpkgSubSlot = ''     % Portage convention
  ),
  ( query:search(slot(SrcSlot), SrcRepo://SrcEntry)
  -> BinpkgSlot == SrcSlot,
     ( query:search(subslot(SrcSubSlot), SrcRepo://SrcEntry),
       BinpkgSubSlot \== ''
     -> BinpkgSubSlot == SrcSubSlot
     ;  true
     )
  ;  true   % source repo missing slot info -> don't block
  ).


%! binpkg_exec:split_slot(+Combined, -Slot, -SubSlot) is det.
%
% Splits `'0/1'` into `'0'` and `'1'`. If there is no `/`, SubSlot is
% bound to the empty atom.

binpkg_exec:split_slot(Combined, Slot, SubSlot) :-
  ( atomic_list_concat([Slot, SubSlot], '/', Combined) -> true
  ; Slot = Combined, SubSlot = ''
  ).


%! binpkg_exec:keywords_acceptable(+BinpkgEid) is semidet.
%
% Check the binpkg's stored KEYWORDS list contains at least one entry
% acceptable to the host. We approximate by requiring the host ARCH (or
% `~ARCH`) to appear; full ACCEPT_KEYWORDS handling is a follow-up.
% Defensive: if KEYWORDS metadata is missing, accept (assume the
% producer knew what it was doing).

binpkg_exec:keywords_acceptable(BinpkgEid) :-
  ( cache:entry_metadata(binpkg, BinpkgEid, keywords, KwAtom)
  -> binpkg_exec:any_arch_match(KwAtom)
  ;  true
  ).


%! binpkg_exec:any_arch_match(+KwAtom) is semidet.
%
% Splits a `'~alpha amd64 ~arm arm64'` style KEYWORDS atom and succeeds
% iff at least one entry matches the host ARCH (with or without a
% `~` prefix). Host ARCH is resolved via `preference:arch/1` if
% available; falls back to `amd64` for sandboxed test contexts.

binpkg_exec:any_arch_match(KwAtom) :-
  binpkg_exec:host_arch(Arch),
  atomic_list_concat(Tokens, ' ', KwAtom),
  ( memberchk(Arch, Tokens) ; atom_concat('~', Arch, Unstable), memberchk(Unstable, Tokens) ),
  !.


%! binpkg_exec:host_arch(-Arch) is det.
%
% Best-effort host arch lookup. `preference:arch/1` is the canonical
% source on production hosts; we fall back to `amd64` when running in
% standalone test harnesses that don't load the preference module.

binpkg_exec:host_arch(Arch) :-
  ( catch(preference:arch(Arch), _, fail)
  -> true
  ;  Arch = amd64
  ).


%! binpkg_exec:use_compatible(+SrcRepo, +SrcEntry, +BinpkgEid, +Ctx) is semidet.
%
% Compares the resolver's resolved USE flag set against the binpkg's
% stored USE, restricted to the ebuild's IUSE so that profile-level
% flags (abi_x86_64, elibc_glibc, kernel_linux, ...) don't pollute the
% comparison.
%
% Modes (see respect_use_policy/1):
%   strict  : sets must be exactly equal (intersected with IUSE)
%   relaxed : binpkg's positive set must be a superset of the resolver's
%             positive set (i.e. the binpkg has at least all flags the
%             resolver wants enabled; extras are tolerated)
%
% Defensive: if the binpkg has no `use` metadata, accept; if the source
% has no IUSE, accept (degenerate ebuild with no USE flags).

binpkg_exec:use_compatible(SrcRepo, SrcEntry, BinpkgEid, Ctx) :-
  ( cache:entry_metadata(binpkg, BinpkgEid, use, BinpkgUseAtom)
  -> binpkg_exec:tokenize_use(BinpkgUseAtom, BinpkgUseSet)
  ;  BinpkgUseSet = []
  ),
  binpkg_exec:resolver_positive_use(SrcRepo, SrcEntry, Ctx, ResolverSet),
  binpkg_exec:ebuild_iuse(SrcRepo, SrcEntry, IuseSet),
  ( IuseSet == []
  -> true
  ;  intersection(BinpkgUseSet, IuseSet, BinpkgIuse),
     intersection(ResolverSet,   IuseSet, ResolverIuse),
     binpkg_exec:respect_use_policy(Mode),
     binpkg_exec:use_sets_match(Mode, BinpkgIuse, ResolverIuse)
  ).


%! binpkg_exec:use_sets_match(+Mode, +BinpkgIuse, +ResolverIuse) is semidet.

binpkg_exec:use_sets_match(strict, A, B)  :- !, msort(A, S), msort(B, S).
binpkg_exec:use_sets_match(relaxed, A, B) :- subtract(B, A, []).


%! binpkg_exec:tokenize_use(+UseAtom, -Tokens) is det.
%
% Splits a space-separated USE atom (as stored in the index) into a
% sorted list of atoms with `-` prefixes stripped (binpkg USE only
% records *positive* flags; absence implies negative).

binpkg_exec:tokenize_use(UseAtom, Tokens) :-
  atomic_list_concat(Raw, ' ', UseAtom),
  exclude(==(''), Raw, NonEmpty),
  sort(NonEmpty, Tokens).


%! binpkg_exec:resolver_positive_use(+SrcRepo, +SrcEntry, +Ctx, -Tokens) is det.
%
% Reuses `ebuild_exec:collect_use_string/4` (the same logic that builds
% the USE env var for a source build), then keeps only the positive
% tokens (those without a `-` prefix). This guarantees the binpkg
% comparison uses the *exact* USE the resolver would have shipped to
% `ebuild merge`.

binpkg_exec:resolver_positive_use(SrcRepo, SrcEntry, Ctx, Tokens) :-
  ebuild_exec:collect_use_string(SrcRepo, SrcEntry, Ctx, UseAtom),
  atomic_list_concat(Raw, ' ', UseAtom),
  include(binpkg_exec:is_positive_token, Raw, Positive),
  sort(Positive, Tokens).


%! binpkg_exec:is_positive_token(+Tok) is semidet.

binpkg_exec:is_positive_token(Tok) :-
  Tok \== '',
  \+ atom_concat('-', _, Tok).


%! binpkg_exec:ebuild_iuse(+SrcRepo, +SrcEntry, -IuseSet) is det.
%
% Returns the set of USE flags declared by the ebuild's IUSE. The eapi
% cache stores `+default` flags as the compound term `plus(F)` and plain
% flags as bare atoms; we normalize to a sorted set of atoms.

binpkg_exec:ebuild_iuse(SrcRepo, SrcEntry, IuseSet) :-
  findall(F,
          ( cache:entry_metadata(SrcRepo, SrcEntry, iuse, IuseRaw),
            binpkg_exec:iuse_flag_name(IuseRaw, F)
          ),
          Raw),
  sort(Raw, IuseSet).


%! binpkg_exec:iuse_flag_name(+Raw, -Name) is det.
%
% Normalizes one cache row to its bare flag name. Handles:
%   - `plus(F)`    -> F   (the `+default` form)
%   - `minus(F)`   -> F   (defensive; eapi storage allows this for
%                          profile-stripped flags)
%   - `F` (atom)   -> F   (plain flag)

binpkg_exec:iuse_flag_name(plus(F),  F) :- !.
binpkg_exec:iuse_flag_name(minus(F), F) :- !.
binpkg_exec:iuse_flag_name(F,        F).


% -----------------------------------------------------------------------------
%  Subslot-pin (`:slot/subslot=`) validation against the live VDB
% -----------------------------------------------------------------------------

%! binpkg_exec:subslot_pins_compatible(+BinpkgEid) is semidet.
%
% Mirrors emerge's binpkg-acceptance rule for slot-operator (`:=`)
% dependencies (PMS 8.2 / EAPI 7): when a binpkg was produced its
% recorded DEPEND-family fields embed the resolved
% `<category>/<name>:<slot>/<subslot>=` of every dep that carried a
% `:=` operator. The binpkg is only acceptable if every such pin
% still matches the live VDB record of the depended-on package; a
% subslot mismatch indicates the producer of the binpkg linked
% against an ABI that no longer exists on the consuming host (e.g.
% an OCaml `.cmi` baked against `dev-lang/ocaml:0/5.3.0` is unreadable
% by the live `dev-lang/ocaml:0/5.4.0` compiler).
%
% We walk DEPEND, RDEPEND, PDEPEND, BDEPEND and IDEPEND so any pin in
% any dep field is honoured. Within each field we recurse through
% group constructors (`all_of_group`, `any_of_group`,
% `use_conditional_group`, `exactly_one_of_group`,
% `at_most_one_of_group`) so conditional / nested deps are not
% silently skipped. Per-atom rejection rule is conservative: we only
% reject when we can positively confirm a mismatch (recorded subslot
% present, live install for the dep at the same slot exists, and
% their canonicalised subslots differ). Missing live install, missing
% live subslot or parse failure all degrade to "accept" so this check
% only ever causes regressions when emerge would also reject.

binpkg_exec:subslot_pins_compatible(BinpkgEid) :-
  forall(
    member(Key, [depend, rdepend, pdepend, bdepend, idepend]),
    binpkg_exec:dep_field_subslot_compatible(BinpkgEid, Key)).


%! binpkg_exec:dep_field_subslot_compatible(+BinpkgEid, +Key) is semidet.
%
% Reads one dep field (lowercased atom: `depend`, `rdepend`, ...) from
% the binpkg cache, parses it with the EAPI dependency grammar, and
% requires every embedded `:slot/subslot=` pin to be satisfied. A
% missing field accepts. A parse failure also accepts (defensive: the
% binpkg may be in a slightly newer format than our grammar handles,
% and we would rather defer to emerge's logic than over-reject).

binpkg_exec:dep_field_subslot_compatible(BinpkgEid, Key) :-
  ( cache:entry_metadata(binpkg, BinpkgEid, Key, ValueAtom),
    ValueAtom \== ''
  -> ( binpkg_exec:parse_dep_value(ValueAtom, Deps)
     -> binpkg_exec:walk_deps_subslot(Deps)
     ;  true
     )
  ;  true
  ).


%! binpkg_exec:parse_dep_value(+ValueAtom, -Deps) is semidet.
%
% Parses a verbatim DEPEND-family atom (as stored in the binpkg
% `Packages` index) into a list of EAPI dependency terms. The
% pseudo `R://E` context expected by `eapi:depend//2` is filled with
% anonymous variables -- it is only used by the grammar to thread
% provenance back into error messages and is not consulted by the
% structural shape we walk here.

binpkg_exec:parse_dep_value(ValueAtom, Deps) :-
  ( atom(ValueAtom)   -> atom_codes(ValueAtom, Codes)
  ; string(ValueAtom) -> string_codes(ValueAtom, Codes)
  ),
  catch(phrase(eapi:depend(_://_, Deps), Codes), _, fail).


%! binpkg_exec:walk_deps_subslot(+Deps) is semidet.
%
% Walks a parsed dependency list, descending into group constructors
% and validating any atom-level `:slot/subslot=` pin against the live
% VDB. Succeeds iff every confirmed pin matches.

binpkg_exec:walk_deps_subslot([]).
binpkg_exec:walk_deps_subslot([D|Ds]) :-
  binpkg_exec:walk_dep_subslot(D),
  binpkg_exec:walk_deps_subslot(Ds).


%! binpkg_exec:walk_dep_subslot(+Dep) is semidet.
%
% Per-node visitor. Group constructors recurse into their child list;
% `package_dependency/8` atoms are validated against the live VDB;
% anything else (blocker-only atoms, virtuals already lowered, etc.)
% passes through.

binpkg_exec:walk_dep_subslot(package_dependency(_, _, C, P, _, _, Slot, _)) :- !,
  binpkg_exec:check_atom_subslot_pin(C, P, Slot).

binpkg_exec:walk_dep_subslot(all_of_group(D)) :- !,
  binpkg_exec:walk_deps_subslot(D).

binpkg_exec:walk_dep_subslot(any_of_group(D)) :- !,
  binpkg_exec:walk_deps_subslot(D).

binpkg_exec:walk_dep_subslot(use_conditional_group(_, _, _, D)) :- !,
  binpkg_exec:walk_deps_subslot(D).

binpkg_exec:walk_dep_subslot(exactly_one_of_group(D)) :- !,
  binpkg_exec:walk_deps_subslot(D).

binpkg_exec:walk_dep_subslot(at_most_one_of_group(D)) :- !,
  binpkg_exec:walk_deps_subslot(D).

binpkg_exec:walk_dep_subslot(_).


%! binpkg_exec:check_atom_subslot_pin(+Category, +Name, +Slot) is semidet.
%
% Validates one dependency atom's slot list. The grammar emits Slot
% as a list that, for a resolved `:N/M=` pin, contains both
% `subslot(M)` and the `equal` marker. Anything else (plain `:N`,
% bare `:=`, `:*`, missing slot list) carries no concrete subslot
% pin and is accepted unconditionally. When a pin IS present, we
% require either no live install of (Category, Name) at the recorded
% slot, no recorded live subslot, or live-vs-recorded subslot
% equality (after `canon_slot` normalisation).

binpkg_exec:check_atom_subslot_pin(Cat, Name, Slot) :-
  ( is_list(Slot),
    memberchk(equal, Slot),
    memberchk(subslot(RecSubRaw), Slot)
  -> ( memberchk(slot(RecSlotRaw), Slot)
     -> slotmeta:canon_slot(RecSlotRaw, RecSlot)
     ;  RecSlot = (-)
     ),
     slotmeta:canon_slot(RecSubRaw, RecSub),
     binpkg_exec:live_subslot_matches(Cat, Name, RecSlot, RecSub)
  ;  true
  ).


%! binpkg_exec:live_subslot_matches(+Category, +Name, +RecSlot, +RecSub) is semidet.
%
% Looks up the live (VDB) install of (Category, Name). If RecSlot is
% bound to a concrete atom we restrict to installs in that slot;
% otherwise the first installed (Category, Name) is considered.
% Succeeds (accept) when there is no install or the install records
% no subslot; otherwise requires `RecSub` to equal the live subslot.
%
% The lookup consults the on-disk VDB first (portage-ng#24): the
% in-memory `pkg://` cache is a snapshot loaded at startup, so it does
% NOT see packages merged earlier in the *current* plan. In issue #24
% the plan merged dev-libs/protobuf-34.2 in an early wave; the startup
% snapshot (taken from a baseline without protobuf) made this check
% accept a stale sci-ml/onnx binpkg pinned to `protobuf:0/33.1.0=`,
% and sci-ml/caffe2 then failed compiling against the mismatched
% gencode. Reading `<vdb>/<cat>/<pf>/SLOT` from disk sees the freshly
% merged install and rejects such candidates -- matching emerge, which
% validates binpkg `:=` pins against the live vartree. The snapshot
% path remains as a fallback for hosts without a stat'able VDB.
%
% When proving for a remote client (knowledgebase:vdb_repository/1
% resolves to a per-client `pkg@<host>` repo, see --import-vdb) the
% server's on-disk VDB is irrelevant: we skip the disk consult and use
% the imported in-memory snapshot instead.

binpkg_exec:live_subslot_matches(Cat, Name, RecSlot, RecSub) :-
  ( binpkg_exec:live_install_subslot(Cat, Name, RecSlot, LiveSub)
  -> LiveSub == RecSub
  ;  true
  ).


%! binpkg_exec:live_install_subslot(+Category, +Name, +RecSlot, -LiveSub) is semidet.
%
% Resolves the canonicalised subslot of the live install of
% (Category, Name) in slot RecSlot (`(-)` means any slot). Fails when
% there is no such install or it records no concrete subslot -- the
% caller treats failure as "nothing confirmable, accept". On-disk VDB
% wins; the in-memory `pkg://` snapshot is only consulted when no VDB
% root is available on this host.

binpkg_exec:live_install_subslot(Cat, Name, RecSlot, LiveSub) :-
  knowledgebase:vdb_repository(pkg),
  binpkg_exec:vdb_disk_root(Root), !,
  binpkg_exec:vdb_disk_install_subslot(Root, Cat, Name, RecSlot, LiveSub).

binpkg_exec:live_install_subslot(Cat, Name, RecSlot, LiveSub) :-
  binpkg_exec:find_live_install_for_slot(Cat, Name, RecSlot, LiveRepo://LiveEntry),
  query:search(subslot(LiveSubRaw), LiveRepo://LiveEntry),
  slotmeta:canon_slot(LiveSubRaw, LiveSub).


%! binpkg_exec:vdb_disk_root(-Root) is semidet.
%
% The on-disk VDB root (`/var/db/pkg` layout) of the registered `pkg`
% repository, when it exists as a directory.

binpkg_exec:vdb_disk_root(Root) :-
  current_predicate(pkg:get_location/1),
  catch(pkg:get_location(Root), _, fail),
  exists_directory(Root).


%! binpkg_exec:vdb_disk_install_subslot(+Root, +Category, +Name, +RecSlot, -Sub) is semidet.
%
% Reads `<Root>/<Category>/<pf>/SLOT` for the installed (Category, Name)
% whose canonicalised slot matches RecSlot (`(-)` = any), and returns
% its canonicalised subslot. Fails when no matching install exists or
% the SLOT file carries no `/subslot` part. `eapi:packageversion/3`
% guards against name-prefix collisions (e.g. `protobuf-java-*` dirs
% while looking for `protobuf`) and skips transient `-MERGING-*` dirs.

binpkg_exec:vdb_disk_install_subslot(Root, Cat, Name, RecSlot, Sub) :-
  os:compose_path(Root, Cat, CatDir),
  exists_directory(CatDir),
  os:directory_content(CatDir, PF),
  % Parse with a fresh variable and compare afterwards: calling
  % packageversion/3 with the name pre-bound makes a unification miss
  % fall through to its message:failure/1 clause for every unrelated
  % sibling dir.
  catch(eapi:packageversion(PF, PkgName, _Version), _, fail),
  PkgName == Name,
  os:compose_path([CatDir, PF, 'SLOT'], SlotFile),
  exists_file(SlotFile),
  catch(read_file_to_string(SlotFile, SlotStr0, []), _, fail),
  split_string(SlotStr0, "", " \t\r\n", [SlotStr]),
  SlotStr \== "",
  atom_string(SlotAtom, SlotStr),
  binpkg_exec:split_slot(SlotAtom, LiveSlotRaw, LiveSubRaw),
  LiveSubRaw \== '',
  slotmeta:canon_slot(LiveSlotRaw, LiveSlot),
  ( RecSlot == (-) -> true ; LiveSlot == RecSlot ),
  slotmeta:canon_slot(LiveSubRaw, Sub),
  !.


%! binpkg_exec:find_live_install_for_slot(+Cat, +Name, +RecSlot, -RepoEntry) is semidet.
%
% Resolves the live VDB entry (in the active VDB repository, see
% knowledgebase:vdb_repository/1) that matches the recorded slot. When
% `RecSlot == (-)` (no slot constraint recorded) the first installed
% entry wins. Otherwise we backtrack through every installed entry
% of (Cat, Name) and pick the first whose canonicalised slot equals
% RecSlot.

binpkg_exec:find_live_install_for_slot(Cat, Name, (-), VdbRepo://Entry) :- !,
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(Name), category(Cat), installed(true)], VdbRepo://Entry).

binpkg_exec:find_live_install_for_slot(Cat, Name, RecSlot, VdbRepo://Entry) :-
  knowledgebase:vdb_repository(VdbRepo),
  query:search([name(Name), category(Cat), installed(true)], VdbRepo://Entry),
  ( query:search(slot(LiveSlotRaw), VdbRepo://Entry)
  -> slotmeta:canon_slot(LiveSlotRaw, LiveSlot),
     LiveSlot == RecSlot
  ;  true
  ),
  !.


%! binpkg_exec:rdepend_acceptable(+SrcRepo, +SrcEntry, +BinpkgEid) is semidet.
%
% Checks whether the binpkg's recorded RDEPEND+PDEPEND (index fields,
% use-reduced under the binpkg's own USE) still match the current
% ebuild's. Mirrors emerge's `--binpkg-changed-deps`; the mode comes from
% changed_deps_policy/1:
%   skip : refuse the binpkg on drift
%   warn : accept the binpkg and warn

binpkg_exec:rdepend_acceptable(SrcRepo, SrcEntry, BinpkgEid) :-
  ( binpkg_exec:rdepend_drift(SrcRepo, SrcEntry, BinpkgEid)
  -> binpkg_exec:changed_deps_policy(Mode),
     Mode \== skip,
     message:warning(['binpkg ', BinpkgEid,
                      ': runtime dependencies changed since it was built (using it anyway)'])
  ;  true
  ).


%! binpkg_exec:rdepend_drift(+SrcRepo, +SrcEntry, +BinpkgEid) is semidet.
%
% The binpkg's recorded runtime dependencies differ from the source
% ebuild's (sets:runtime_deps_differ/3). A binpkg without `rdepend` /
% `pdepend` index fields recorded none.

binpkg_exec:rdepend_drift(SrcRepo, SrcEntry, BinpkgEid) :-
  binpkg_exec:index_dep_terms(BinpkgEid, rdepend, Rd),
  binpkg_exec:index_dep_terms(BinpkgEid, pdepend, Pd),
  append(Rd, Pd, Recorded),
  ( cache:entry_metadata(binpkg, BinpkgEid, use, UseAtom)
  -> binpkg_exec:tokenize_use(UseAtom, Use)
  ;  Use = []
  ),
  sets:runtime_deps_differ(Recorded, Use, SrcRepo://SrcEntry).


%! binpkg_exec:index_dep_terms(+BinpkgEid, +Key, -Deps) is det.
%
% The parsed EAPI dependency terms of a binpkg index field ([] when the
% field is absent, which Portage does for empty values).

binpkg_exec:index_dep_terms(BinpkgEid, Key, Deps) :-
  ( cache:entry_metadata(binpkg, BinpkgEid, Key, Raw)
  -> sets:parse_rdepend_string(Raw, Deps)
  ;  Deps = []
  ).


% -----------------------------------------------------------------------------
%  Execution: drive `ebuild qmerge`
% -----------------------------------------------------------------------------

%! binpkg_exec:execute(+Action, +SrcRepo, +SrcEntry, +BinpkgEntryId, +Ctx, -Outcome) is det.
%
% Performs the actual binary merge for a chosen binpkg. Outcome is one
% of:
%   done                     -- qmerge exited 0; package is installed
%   failed(qmerge_exit(N))   -- qmerge exited non-zero
%   failed(Reason)           -- setup step failed (missing gpkg, extract
%                               error, etc.); Reason is a printable atom
%
% The Action argument is accepted but not currently used for branching:
% install/reinstall/update/downgrade all map to the same qmerge call
% (qmerge handles the unmerge-old / merge-new sequence internally via
% `dblink.merge`).

binpkg_exec:execute(_Action, SrcRepo, SrcEntry, BinpkgEntryId, Ctx, Outcome) :-
  catch(
    ( binpkg_exec:execute_inner(SrcRepo, SrcEntry, BinpkgEntryId, Ctx, Outcome)
    -> true
    ;  Outcome = failed(inner_aborted)
    ),
    Err,
    ( format(user_error, 'binpkg_exec:execute exception: ~q~n', [Err]),
      Outcome = failed(exception(Err))
    )
  ).


%! binpkg_exec:execute_inner(+SrcRepo, +SrcEntry, +BinpkgEntryId, +Ctx, -Outcome) is det.
%
% The non-catch'd body of `execute/6`. Splits resolution from execution
% so unit tests can stub one half without touching the other.

binpkg_exec:execute_inner(SrcRepo, SrcEntry, BinpkgEntryId, Ctx, Outcome) :-
  % --- resolve all paths ---------------------------------------------------
  binpkg_exec:gpkg_path(BinpkgEntryId, GpkgPath),
  binpkg_exec:source_ebuild_path(SrcRepo, SrcEntry, EbuildPath),
  binpkg_exec:builddir_for(SrcRepo, SrcEntry, BuildDir),
  binpkg_exec:inner_name_for(BinpkgEntryId, InnerName),

  % --- preconditions + qmerge (single branch tree; never fall through) -----
  ( \+ exists_file(GpkgPath)
  -> Outcome = failed(missing_gpkg(GpkgPath))
  ; \+ exists_file(EbuildPath)
  -> Outcome = failed(missing_ebuild(EbuildPath))
  ; binpkg_extract:prepare_builddir(GpkgPath, InnerName, BuildDir)
  -> ebuild_exec:collect_use_string(SrcRepo, SrcEntry, Ctx, UseString),
     binpkg_exec:run_qmerge(BinpkgEntryId, EbuildPath, GpkgPath, BuildDir, UseString, ExitCode),
     ( ExitCode =:= 0
     -> Outcome = done
     ;  Outcome = failed(qmerge_exit(ExitCode))
     )
  ;  Outcome = failed(extract_failed(GpkgPath))
  ).


% -----------------------------------------------------------------------------
%  Path resolution
% -----------------------------------------------------------------------------

%! binpkg_exec:gpkg_path(+BinpkgEntryId, -GpkgPath) is semidet.
%
% Composes the absolute path to the gpkg file from the binpkg repo's
% location and the entry's `path` metadata field (relative path inside
% the cache, e.g. `'app-misc/jq/jq-1.8.1-9.gpkg.tar'`).

binpkg_exec:gpkg_path(BinpkgEntryId, GpkgPath) :-
  cache:entry_metadata(binpkg, BinpkgEntryId, path, RelPathAtom),
  binpkg:get_location(Root),
  os:compose_path(Root, RelPathAtom, GpkgPath).


%! binpkg_exec:source_ebuild_path(+SrcRepo, +SrcEntry, -EbuildPath) is semidet.
%
% Defers to the source repository's `get_ebuild_file/2` method to obtain
% the absolute path of the source ebuild. The `ebuild` CLI requires this
% path to live inside a recognized portage tree, so we cannot simply
% point at a copy in build-info/.

binpkg_exec:source_ebuild_path(SrcRepo, SrcEntry, EbuildPath) :-
  SrcRepo:get_ebuild_file(SrcEntry, EbuildPath).


%! binpkg_exec:builddir_for(+SrcRepo, +SrcEntry, -BuildDir) is det.
%
% Computes `<config:build_root>/<category>/<pf>`, the canonical
% PORTAGE_BUILDDIR layout. Uses the source entry (not the binpkg entry)
% for cat/pf so concurrent binpkg merges of different BUILD_IDs share a
% builddir -- they would race anyway, since they merge to the same VDB.

binpkg_exec:builddir_for(SrcRepo, SrcEntry, BuildDir) :-
  cache:ordered_entry(SrcRepo, SrcEntry, Cat, Name, Version),
  eapi:version_full(Version, Pv),
  atomic_list_concat([Name, '-', Pv], Pf),
  config:build_root(Root),
  os:compose_path([Root, Cat, Pf], BuildDir).


%! binpkg_exec:inner_name_for(+BinpkgEntryId, -InnerName) is det.
%
% Strips the leading `<category>/` from a binpkg entry id to recover the
% inner directory name embedded in the gpkg (e.g.
% `'app-misc/jq-1.8.1-9'` -> `'jq-1.8.1-9'`).

binpkg_exec:inner_name_for(BinpkgEntryId, InnerName) :-
  atomic_list_concat([_Cat, Inner], '/', BinpkgEntryId),
  InnerName = Inner.


% -----------------------------------------------------------------------------
%  qmerge invocation
% -----------------------------------------------------------------------------

%! binpkg_exec:run_qmerge(+Id, +EbuildPath, +GpkgPath, +BuildDir, +UseString, -ExitCode) is det.
%
% Spawns `ebuild --skip-manifest <EbuildPath> qmerge` (under the
% portage_pkg_merge lock) with the canonical binpkg env var set:
%   MERGE_TYPE=binary           tells ebuild.sh this is a binary merge
%   PORTAGE_BINPKG_FILE=<gpkg>  binpkg path (used for VDB BINPKGMD5)
%   PORTAGE_BUILDDIR=<dir>      where image/, build-info/, temp/ live
%   USE=<resolver USE>          resolver's resolved USE (matches binpkg's)
%
% Id is the binpkg entry id (used for the deconfliction record). Under
% config:deconflict_collisions=override the qmerge is recovered from a
% collision-protect abort (see run_qmerge_deconflict/6); otherwise stdout/
% stderr inherit the parent's terminal so qmerge's progress messages flow
% through. PATH and HOME are passed through but other environment is NOT
% sanitized -- if the user has portage-related env vars set we honor them,
% mirroring how `ebuild ... merge` already behaves under `ebuild_exec`.

binpkg_exec:run_qmerge(Id, EbuildPath, GpkgPath, BuildDir, UseString, ExitCode) :-
  ebuild_exec:with_portage_pkg_merge_lock(qmerge,
    binpkg_exec:run_qmerge_deconflict(Id, EbuildPath, GpkgPath, BuildDir, UseString, ExitCode)).


%! binpkg_exec:run_qmerge_deconflict(+Id, +EbuildPath, +GpkgPath, +BuildDir, +UseString, -ExitCode) is det.
%
% Runs qmerge with collision deconfliction (portage-ng#90). When
% config:deconflict_collisions/1 is `override` the qmerge output is captured
% to a temp log and, if the merge aborts with Portage's collision-protect
% signature, the qmerge is retried once with FEATURES=-collision-protect
% -protect-owned so the binary package overwrites the conflicting file(s).
% In any other mode the qmerge runs once with no override.

binpkg_exec:run_qmerge_deconflict(Id, EbuildPath, GpkgPath, BuildDir, UseString, ExitCode) :-
  collision:deconflict_mode(override),
  !,
  setup_call_cleanup(
    tmp_file_stream(text, LogPath, S0),
    ( close(S0),
      binpkg_exec:run_qmerge_unlocked(EbuildPath, GpkgPath, BuildDir, UseString, [], LogPath, ExitCode0),
      ( ExitCode0 =\= 0,
        collision:phase_error(LogPath, 0)
      -> binpkg_exec:log_qmerge_collision_retry(Id, ExitCode0),
         fixup:record(collision, Id, collision_protect),
         binpkg_exec:run_qmerge_unlocked(EbuildPath, GpkgPath, BuildDir, UseString,
                                         ['FEATURES'='-collision-protect -protect-owned'], LogPath, ExitCode)
      ;  ExitCode = ExitCode0
      )
    ),
    catch(delete_file(LogPath), _, true)).

binpkg_exec:run_qmerge_deconflict(_Id, EbuildPath, GpkgPath, BuildDir, UseString, ExitCode) :-
  binpkg_exec:run_qmerge_unlocked(EbuildPath, GpkgPath, BuildDir, UseString, [], inherit, ExitCode).


%! binpkg_exec:log_qmerge_collision_retry(+Id, +ExitCode) is det.
%
% Prints a visible marker line when a qmerge is retried with collision
% protection disabled (mirrors collision:log_retry/3, which writes to the
% source-merge build log; qmerge has no per-build log so the marker goes
% to the terminal).

binpkg_exec:log_qmerge_collision_retry(Id, ExitCode) :-
  catch(
    format('~n=== qmerge ~w failed (exit ~w) with file-collision signature; retrying with FEATURES=-collision-protect -protect-owned (portage-ng#90 deconfliction) ===~n',
           [Id, ExitCode]),
    _, true).


%! binpkg_exec:run_qmerge_unlocked(+EbuildPath, +GpkgPath, +BuildDir, +UseString, +ExtraEnv, +LogPath, -ExitCode) is det.
%
% Spawns `ebuild --skip-manifest <EbuildPath> qmerge`. When LogPath is the
% atom `inherit` the child's stdout/stderr flow straight to the terminal
% (live progress). Otherwise output is redirected to LogPath and then echoed
% to the terminal, preserving the real exit code, so the log can be scanned
% for the collision-protect signature. ExtraEnv (Name=Value pairs) extends
% the binpkg env -- used by the deconfliction retry to inject FEATURES.

binpkg_exec:run_qmerge_unlocked(EbuildPath, GpkgPath, BuildDir, UseString, ExtraEnv, inherit, ExitCode) :-
  !,
  config:ebuild_command(EbuildCmd),
  process_create(
    path(EbuildCmd),
    ['--skip-manifest', EbuildPath, 'qmerge'],
    [process(Pid),
     environment(['MERGE_TYPE'='binary',
                  'PORTAGE_BINPKG_FILE'=GpkgPath,
                  'PORTAGE_BUILDDIR'=BuildDir,
                  'USE'=UseString|ExtraEnv])]),
  process_wait(Pid, exit(ExitCode)).

binpkg_exec:run_qmerge_unlocked(EbuildPath, GpkgPath, BuildDir, UseString, ExtraEnv, LogPath, ExitCode) :-
  config:ebuild_command(EbuildCmd),
  % Fixed -c script; paths via $1..$3 (sanitize argv contract).
  process_create(
    path(sh),
    ['-c', '"$1" --skip-manifest "$2" qmerge >"$3" 2>&1; rc=$?; cat "$3"; exit $rc',
     '_', EbuildCmd, EbuildPath, LogPath],
    [process(Pid),
     environment(['MERGE_TYPE'='binary',
                  'PORTAGE_BINPKG_FILE'=GpkgPath,
                  'PORTAGE_BUILDDIR'=BuildDir,
                  'USE'=UseString|ExtraEnv])]),
  process_wait(Pid, exit(ExitCode)).
