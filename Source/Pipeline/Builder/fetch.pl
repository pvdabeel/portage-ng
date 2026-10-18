/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> FETCH
Download orchestration for build jobs.

Runs the download/fetchonly side of a build step from inside a
jobserver worker: parallel curl downloads with per-file progress,
git clone/fetch for live ebuilds, RESTRICT=fetch handling, upstream
SRC_URI fallback, and binpkg rescue of failed source fetches.

Low-level primitives (curl spawning, checksum verification, mirror
layout, race-safe staging) live in Builder/download.pl; this module
orchestrates them and renders progress via the build printer.
*/

:- module(fetch, []).

% =============================================================================
%  FETCH declarations
% =============================================================================

:- dynamic fetch:dl_prev_snapshot/3.

% -----------------------------------------------------------------------------
%  Live (git) downloads
% -----------------------------------------------------------------------------

%! fetch:run_git_download(+Repo, +Entry, +LiveStartLine, +TotalLines, +LineOff, +PlanStep, +NumSteps, +ActionIdx, +Action, -Outcome) is det.
%
% Clones or fetches a live ebuild's git repository with progress tracking.
% Extracts EGIT_REPO_URI from the ebuild, uses the distdir/git3-src cache
% (matching Portage's git-r3.eclass convention), and polls for progress.

fetch:run_git_download(Repo, Entry, LiveStartLine, TotalLines,
                       LineOff, PlanStep, NumSteps, ActionIdx, Action, Outcome) :-
  ( download:extract_git_uri(Repo, Entry, URI)
  -> distfiles:get_location(Distdir),
     download:git_cache_dir(Distdir, GitCacheDir),
     ( \+ exists_directory(GitCacheDir) -> make_directory_path(GitCacheDir) ; true ),
     download:git_repo_cache_path(GitCacheDir, URI, RepoPath),
     ebuild_exec:build_log_path(Entry, LogPath),
     ebuild_exec:ensure_log_dir,
     Callback = fetch:git_progress_callback(LiveStartLine, TotalLines),
     download:start_git_clone_async(URI, RepoPath, LogPath, Pid),
     download:poll_git_progress(Pid, LogPath, Callback, ExitCode),
     ( ExitCode =:= 0
     -> with_mutex(build_display,
          build:update_live_subslot(0, LiveStartLine, TotalLines, done)),
        with_mutex(build_display,
          build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
        Outcome = done
     ;  with_mutex(build_display,
          build:update_live_subslot(0, LiveStartLine, TotalLines, failed)),
        with_mutex(build_display,
          build:update_slot(LineOff, TotalLines, failed(git), PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
        Outcome = failed(git)
     )
  ;  with_mutex(build_display,
       build:update_live_subslot(0, LiveStartLine, TotalLines, done)),
     with_mutex(build_display,
       build:update_slot(LineOff, TotalLines, done, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)),
     Outcome = done
  ).


%! fetch:git_progress_callback(+LiveStartLine, +TotalLines, +Phase, +Status) is det.
%
% Updates the live sub-slot display with git clone/fetch progress.

fetch:git_progress_callback(LiveStartLine, TotalLines, _Phase, progress(Pct)) :-
  with_mutex(build_display,
    build:update_live_subslot(0, LiveStartLine, TotalLines, progress(Pct))).

fetch:git_progress_callback(_, _, _, _).


% -----------------------------------------------------------------------------
%  Parallel distfile downloads
% -----------------------------------------------------------------------------

%! fetch:run_download_parallel(+Repo, +Entry, +Ctx, +LineOff, +TotalLines, +PlanStep, +NumSteps, +ActionIdx, +Action, +FileStartLine, +DistFiles, +Distdir, -Outcome) is det.
%
% Parallel download with per-file progress using pre-allocated layout.
% File sub-lines are already printed by print_job_slots; this predicate
% only starts async curls, polls progress in-place, and updates the
% header slot on completion.
%
% Binpkg rescue (portage-ng#28): when the source fetch fails (manual
% fetch required, dead URL, mirror outage) but a USE-compatible binpkg
% exists for this entry, the failure is downgraded to `done` so the
% plan proceeds to the install step, where the binpkg fast path merges
% the gpkg without needing the distfiles. The source fetch is still
% always attempted first -- binpkgs accelerate the source pipeline,
% they never replace it pre-emptively.

fetch:run_download_parallel(Repo, Entry, Ctx, LineOff, TotalLines, PlanStep, NumSteps, ActionIdx, Action,
                            FileStartLine, DistFiles, Distdir, Outcome) :-
  ( \+ exists_directory(Distdir) -> make_directory_path(Distdir) ; true ),
  maplist(download:validate_distfile_spec, DistFiles),
  ( download:is_fetch_restricted(Repo, Entry)
  -> fetch:handle_restricted_files(DistFiles, 0, TotalLines, FileStartLine, Distdir, MissingCount),
     ( MissingCount =:= 0
     -> FinalStatus = done, Outcome = done
     ;  fetch:binpkg_rescues_download(Action, Repo, Entry, Ctx)
     -> FinalStatus = done, Outcome = done
     ;  FinalStatus = failed('manual fetch required'), Outcome = failed('manual fetch required')
     )
  ;  fetch:safe_mirror_layout(Layout),
     fetch:prepare_download_jobs(Layout, Distdir, DistFiles, 0, Repo, Entry, DlJobs),
     get_time(T0),
     fetch:init_speed_tracking(DlJobs, T0, FileStartLine),
     fetch:poll_download_loop(DlJobs, TotalLines, FileStartLine, Distdir, FailCount),
     ( FailCount =:= 0
     -> FinalStatus = done, Outcome = done
     ;  fetch:binpkg_rescues_download(Action, Repo, Entry, Ctx)
     -> FinalStatus = done, Outcome = done
     ;  FinalStatus = failed('download errors'), Outcome = failed('download errors')
     )
  ),
  with_mutex(build_display,
    build:update_slot(LineOff, TotalLines, FinalStatus, PlanStep, NumSteps, ActionIdx, Action, Repo://Entry)).


%! fetch:binpkg_rescues_download(+Action, +Repo, +Entry, +Ctx) is semidet.
%
% Succeeds when a failed source fetch for Repo://Entry can be tolerated
% because a USE-compatible binpkg exists: the later install step will
% short-circuit through `binpkg_exec:execute/6` (qmerge) and never read
% the distfiles. Probes `binpkg_exec:available_for/4` with the same
% proof context the install dispatch will use, so the rescue decision
% mirrors the actual binpkg selection (USE / SLOT / KEYWORDS / subslot
% pins).
%
% Only plain `download` actions qualify: `fetchonly` exists precisely
% to obtain the sources, so a binpkg can never substitute for it. Any
% exception from the probe (unregistered repo, missing index) degrades
% to failure, preserving the original download error.

fetch:binpkg_rescues_download(download, Repo, Entry, Ctx) :-
  catch(binpkg_exec:available_for(Repo, Entry, Ctx, _BinpkgEntryId), _, fail).


%! fetch:safe_mirror_layout(-Layout) is det.
%
% Defense-in-depth wrapper around download:mirror_layout/1. The
% downstream layout fetch is now thread-safe and tmp_file_stream-free,
% but this catch ensures that any *future* unrelated failure (DNS hiccup,
% mirror down at process start, parse error in layout.conf) degrades
% gracefully to the legacy `flat` layout instead of aborting the whole
% download job (which would propagate to a [jobserver worker error]
% and SKIP every dependent install/run/register in the plan).
%
% The legacy `flat` layout is the safe fallback: it's what Portage used
% before GLEP 75, our local mirror has always served files from the
% flat layout, and the upstream Gentoo mirrors still expose flat-named
% paths. So this fallback strictly preserves correctness for any
% mirror that doesn't actively reject flat lookups.

fetch:safe_mirror_layout(Layout) :-
  catch(
    download:mirror_layout(Layout),
    E,
    ( print_message(warning,
        format("mirror_layout failed (~q); falling back to flat layout", [E])),
      Layout = flat,
      ( download:cached_mirror_layout(_)
      -> true
      ;  catch(assertz(download:cached_mirror_layout(flat)), _, true)
      )
    )).


%! fetch:prepare_download_jobs(+Layout, +Distdir, +DistFiles, +Idx, +Repo, +Entry, -DlJobs) is det.
%
% Start async curl processes for files not already present and verified.
% Returns dl_job/10 terms carrying the private staging directory/path.
% Each curl walks
% every configured mirror_url in declaration order, exiting at the first
% successful download. Upstream SRC_URI fallback is handled later by
% fetch:try_upstream_fallback/11 when the file still fails verification.
%
% Race-safety: curl writes into an unpredictable mode-0700 staging
% directory, never directly into the shared DestPath.
% fetch:finalize_download/13 verifies the temp path and atomic-renames
% to DestPath only after a successful checksum match, then falls
% through to a race-recovery check on DestPath when our own download
% failed (so a concurrent writer that produced a valid file is honoured
% instead of triggering a redundant retry). See `download.pl` --
% "Race-safe distfile staging" for the full rationale.

fetch:prepare_download_jobs(_, _, [], _, _, _, []).

fetch:prepare_download_jobs(Layout, Distdir, [dist(Filename, Size, Pairs)|Rest], Idx, Repo, Entry, Jobs) :-
  Idx1 is Idx + 1,
  download:distfile_destination(Distdir, Filename, DestPath),
  ( download:verified_distfile(DestPath, Size, Pairs)
  -> fetch:prepare_download_jobs(Layout, Distdir, Rest, Idx1, Repo, Entry, Jobs)
  ;  fetch:mirror_urls_for_file(Layout, Filename, URLs),
     fetch:start_download_job(URLs, DestPath, StageDir, TmpPath, Pid),
     Jobs = [dl_job(Pid, Idx, Filename, Size, Pairs, DestPath,
                    StageDir, TmpPath, Repo, Entry)|MoreJobs],
     fetch:prepare_download_jobs(Layout, Distdir, Rest, Idx1, Repo, Entry, MoreJobs)
  ).


%! fetch:start_download_job(+URLs, +DestPath, -StageDir, -TmpPath, -Pid) is det.
%
% Create private staging and start curl, cleaning the directory if spawn fails.

fetch:start_download_job(URLs, DestPath, StageDir, TmpPath, Pid) :-
  download:create_distfile_stage(DestPath, StageDir, TmpPath),
  catch(download:start_curl_async(URLs, TmpPath, Pid),
        Error,
        ( download:cleanup_distfile_stage(StageDir),
          throw(Error)
        )).


%! fetch:mirror_urls_for_file(+Layout, +Filename, -URLs) is det.
%
% Build the ordered list of HTTP mirror URLs to try for Filename. One URL
% per configured config:mirror_url/1 fact, expanded through the same GLEP
% 75 layout. Empty list never returned: caller is only invoked when a
% mirror_url is configured (which the rest of the build pipeline already
% requires).

fetch:mirror_urls_for_file(Layout, Filename, URLs) :-
  findall(URL,
          ( config:mirror_url(MirrorUrl),
            download:mirror_download_url(MirrorUrl, Layout, Filename, URL)
          ),
          URLs0),
  list_to_set(URLs0, URLs).


% -----------------------------------------------------------------------------
%  Speed tracking (dynamic state for per-file speed calculation)
% -----------------------------------------------------------------------------

%! fetch:init_speed_tracking(+DlJobs, +T0, +FileStartLine) is det.

fetch:init_speed_tracking([], _, _).

fetch:init_speed_tracking([dl_job(_, Idx, _, _, _, _, _, _, _, _)|Rest], T0, FileStartLine) :-
  Key is FileStartLine + Idx,
  retractall(fetch:dl_prev_snapshot(Key, _, _)),
  assertz(fetch:dl_prev_snapshot(Key, 0, T0)),
  fetch:init_speed_tracking(Rest, T0, FileStartLine).


%! fetch:clear_speed_tracking is det.
%
% Drop all per-file speed snapshots. Called by the builder when a plan
% step's display state is torn down.

fetch:clear_speed_tracking :-
  retractall(fetch:dl_prev_snapshot(_, _, _)).


%! fetch:compute_speed(+Key, +CurrentSize, -Speed) is det.
%
% Compute download speed in bytes/sec using delta from last snapshot.
% Key is FileStartLine + FileIdx (unique across concurrent downloads).

fetch:compute_speed(Key, CurrentSize, Speed) :-
  get_time(Now),
  ( fetch:dl_prev_snapshot(Key, PrevSize, PrevTime)
  -> Delta is CurrentSize - PrevSize,
     Dt is Now - PrevTime,
     ( Dt > 0.1, Delta > 0
     -> Speed is round(Delta / Dt),
        retractall(fetch:dl_prev_snapshot(Key, _, _)),
        assertz(fetch:dl_prev_snapshot(Key, CurrentSize, Now))
     ;  Speed = 0
     )
  ;  Speed = 0,
     assertz(fetch:dl_prev_snapshot(Key, CurrentSize, Now))
  ).


% -----------------------------------------------------------------------------
%  Poll loop
% -----------------------------------------------------------------------------

%! fetch:poll_download_loop(+DlJobs, +TotalLines, +FileStartLine, +Distdir, -FailCount) is det.
%
% Poll all active downloads until none remain. Returns the total
% number of failed downloads. Updates file sub-slot display with
% percentage and speed on each iteration.

fetch:poll_download_loop([], _, _, _, 0) :- !.

fetch:poll_download_loop(ActiveJobs, TotalLines, FileStartLine, Distdir, TotalFails) :-
  fetch:poll_all_jobs(ActiveJobs, TotalLines, FileStartLine, Distdir, StillActive, BatchFails),
  ( StillActive == []
  -> TotalFails = BatchFails
  ;  sleep(0.25),
     fetch:poll_download_loop(StillActive, TotalLines, FileStartLine, Distdir, MoreFails),
     TotalFails is BatchFails + MoreFails
  ).


%! fetch:poll_all_jobs(+Jobs, +TotalLines, +FileStartLine, +Distdir, -StillActive, -Fails) is det.

fetch:poll_all_jobs([], _, _, _, [], 0).

fetch:poll_all_jobs([Job|Rest], TotalLines, FileStartLine, Distdir, StillActive, Fails) :-
  Job = dl_job(Pid, FileIdx, Filename, ExpSize, Pairs, DestPath,
               StageDir, TmpPath, Repo, Entry),
  ( subprocess:poll_exit(Pid, ExitCode)
  -> setup_call_cleanup(
       true,
       fetch:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs,
                               DestPath, TmpPath, Repo, Entry,
                               TotalLines, FileStartLine, Distdir, OK),
       download:cleanup_distfile_stage(StageDir)),
     fetch:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, StillActive, RestFails),
     ( OK == true -> Fails = RestFails ; Fails is RestFails + 1 )
  ;  fetch:update_download_progress(FileIdx, Filename, ExpSize, DestPath, TmpPath,
                                    TotalLines, FileStartLine, Distdir),
     StillActive = [Job|MoreActive],
     fetch:poll_all_jobs(Rest, TotalLines, FileStartLine, Distdir, MoreActive, Fails)
  ).


%! fetch:finalize_download(+ExitCode, +FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +TmpPath, +Repo, +Entry, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Called when a curl process exits. Verifies the per-process temp
% download (see prepare_download_jobs) and atomic-renames it onto
% DestPath when verification succeeds. On any failure the temp path
% is deleted but DestPath is left intact -- a parallel writer (sibling
% external build harness session, host emerge in compare matrices,
% etc.) may have landed a valid copy there in the meantime, in which case
% race_recover/3 short-circuits success without retrying. If neither
% our temp nor a peer-supplied DestPath verifies, falls through to
% the upstream SRC_URI fallback chain.

fetch:finalize_download(ExitCode, FileIdx, Filename, ExpSize, Pairs,
                        DestPath, TmpPath, Repo, Entry,
                        TotalLines, FileStartLine, Distdir, OK) :-
  ( ExitCode =:= 0
  -> download:finalize_temp_download(TmpPath, DestPath, ExpSize, Pairs, MirrorOK)
  ;  ( download:race_recover(DestPath, ExpSize, Pairs)
     -> MirrorOK = true
     ;  MirrorOK = false
     )
  ),
  ( MirrorOK == true
  -> OK = true,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, done, Filename, ExpSize, Distdir))
  ;  fetch:try_upstream_fallback(FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                                 TotalLines, FileStartLine, Distdir, OK)
  ).


%! fetch:try_upstream_fallback(+FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +Repo, +Entry, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Attempts to download a distfile from its upstream SRC_URI peers when
% the Gentoo distfiles mirror has failed. Walks every URL yielded by
% download:upstream_url/4 (canonical mirror:// expansions first, then
% direct URIs) and stops at the first success that also passes size +
% checksum verification. This matches Portage's behaviour: when the
% Gentoo mirror prunes a distfile, the original upstream and its
% thirdpartymirror peers usually still serve it.

fetch:try_upstream_fallback(FileIdx, Filename, ExpSize, Pairs, DestPath, Repo, Entry,
                            TotalLines, FileStartLine, Distdir, OK) :-
  findall(U, download:upstream_url(Repo, Entry, Filename, U), URLs0),
  list_to_set(URLs0, URLs),
  ( URLs == []
  -> OK = false,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, failed, Filename, ExpSize, Distdir))
  ;  with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, progress(0, 0), Filename, ExpSize, Distdir)),
     fetch:try_url_chain(URLs, FileIdx, Filename, ExpSize, Pairs, DestPath,
                         TotalLines, FileStartLine, Distdir, OK)
  ).


%! fetch:try_url_chain(+URLs, +FileIdx, +Filename, +ExpSize, +Pairs, +DestPath, +TotalLines, +FileStartLine, +Distdir, -OK) is det.
%
% Walk a list of candidate download URLs in order. Each curl writes
% into a new private same-filesystem staging directory; on success the temp is atomic-
% renamed onto DestPath. Stops at the first URL whose curl exits 0
% AND whose temp passes size + checksum verification, OR at the
% first race_recover/3 success (peer writer landed a valid file at
% DestPath while we were trying). If every URL fails, the file is
% marked as failed -- DestPath itself is never deleted.

fetch:try_url_chain([], FileIdx, Filename, ExpSize, _Pairs, _DestPath,
                    TotalLines, FileStartLine, Distdir, false) :-
  with_mutex(build_display,
    build:update_file_subslot(FileIdx, FileStartLine, TotalLines, failed, Filename, ExpSize, Distdir)).

fetch:try_url_chain([URL|Rest], FileIdx, Filename, ExpSize, Pairs, DestPath,
                    TotalLines, FileStartLine, Distdir, OK) :-
  setup_call_cleanup(
    download:create_distfile_stage(DestPath, StageDir, TmpPath),
    ( download:curl_download(URL, TmpPath, ExitCode),
      ( ExitCode =:= 0
      -> download:finalize_temp_download(TmpPath, DestPath, ExpSize, Pairs, AttemptOK)
      ;  ( download:race_recover(DestPath, ExpSize, Pairs)
         -> AttemptOK = true
         ;  AttemptOK = false
         )
      )
    ),
    download:cleanup_distfile_stage(StageDir)),
  ( AttemptOK == true
  -> OK = true,
     with_mutex(build_display,
       build:update_file_subslot(FileIdx, FileStartLine, TotalLines, done, Filename, ExpSize, Distdir))
  ;  fetch:try_url_chain(Rest, FileIdx, Filename, ExpSize, Pairs, DestPath,
                         TotalLines, FileStartLine, Distdir, OK)
  ).


% -----------------------------------------------------------------------------
%  RESTRICT=fetch handling
% -----------------------------------------------------------------------------

%! fetch:handle_restricted_files(+DistFiles, +Idx, +TotalLines, +FileStartLine, +Distdir, -MissingCount) is det.
%
% For fetch-restricted ebuilds, checks each distfile: present files get
% a green checkmark, missing files get a yellow "manual fetch required" marker.

fetch:handle_restricted_files([], _, _, _, _, 0).

fetch:handle_restricted_files([dist(Filename, Size, Pairs)|Rest], Idx, TotalLines, FileStartLine, Distdir, MissingCount) :-
  Idx1 is Idx + 1,
  download:distfile_destination(Distdir, Filename, DestPath),
  ( download:verified_distfile(DestPath, Size, Pairs)
  -> with_mutex(build_display,
       build:update_file_subslot(Idx, FileStartLine, TotalLines, done, Filename, Size, Distdir)),
     fetch:handle_restricted_files(Rest, Idx1, TotalLines, FileStartLine, Distdir, MissingCount)
  ;  with_mutex(build_display,
       build:update_file_subslot(Idx, FileStartLine, TotalLines, restricted, Filename, Size, Distdir)),
     fetch:handle_restricted_files(Rest, Idx1, TotalLines, FileStartLine, Distdir, RestMissing),
     MissingCount is RestMissing + 1
  ).


%! fetch:update_download_progress(+FileIdx, +Filename, +ExpSize, +DestPath, +TmpPath, +TotalLines, +FileStartLine, +Distdir) is det.
%
% Update a file sub-slot with current download progress (percentage + speed).
%
% Curl writes to the per-process temp path (see prepare_download_jobs);
% if the temp file exists we use its size for live progress and fall
% back to the final DestPath only after a successful atomic rename.

fetch:update_download_progress(FileIdx, Filename, ExpSize, DestPath, TmpPath,
                               TotalLines, FileStartLine, Distdir) :-
  SpeedKey is FileStartLine + FileIdx,
  ( exists_file(TmpPath) -> SizeSrc = TmpPath
  ; exists_file(DestPath) -> SizeSrc = DestPath
  ; SizeSrc = none
  ),
  ( SizeSrc \== none
  -> size_file(SizeSrc, CurrentSize),
     ( atom(ExpSize) -> atom_number(ExpSize, ES) ; ES = ExpSize ),
     ( ES > 0 -> Pct is min(99, (CurrentSize * 100) // ES) ; Pct = 0 ),
     fetch:compute_speed(SpeedKey, CurrentSize, Speed)
  ;  Pct = 0, Speed = 0
  ),
  with_mutex(build_display,
    build:update_file_subslot(FileIdx, FileStartLine, TotalLines, progress(Pct, Speed), Filename, ExpSize, Distdir)).
