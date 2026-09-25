/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DOWNLOAD
Distfile fetching from a local HTTP mirror.

Downloads distfiles for a given ebuild entry by looking up Manifest DIST
entries, constructing mirror URLs using the GLEP 75 layout, and fetching
via curl. Already-present files in the local distdir are skipped.

After download, files are verified against Manifest checksums (BLAKE2B,
SHA512) using mirror:verify_hashes/4.

The mirror layout (flat or filename-hash) is fetched once from the HTTP
mirror's layout.conf and cached for the session.

Upstream SRC_URI fallback supports mirror:// URIs by resolving them
through the portage tree's profiles/thirdpartymirrors file.

This module is pure execution logic -- no display calls. Progress
rendering is handled by the builder and build printer.
*/

:- module(download, []).

% =============================================================================
%  DOWNLOAD declarations
% =============================================================================

:- dynamic download:cached_mirror_layout/1.
:- dynamic download:cached_thirdpartymirror/2.

% -----------------------------------------------------------------------------
%  Mirror layout (fetched from HTTP)
% -----------------------------------------------------------------------------

%! download:mirror_layout(-Layout) is det.
%
% Get the GLEP 75 layout of the HTTP mirror. Three-level cache:
%   1. In-memory cached_mirror_layout/1 (per-process, lock-free fast path).
%   2. On-disk cache under the active distdir, see disk_cache_path/1
%      (cross-process, TTL via config:mirror_layout_cache_ttl/1).
%   3. Network fetch via mirror_layout_from_any/2 (one curl per mirror
%      until one returns a parseable layout.conf).
%
% Only successful network fetches populate the disk cache; the legacy
% `flat` fallback used when every mirror is unreachable is cached
% in-memory only, so a transient outage does not pin every future
% session to flat for the full TTL.
%
% Concurrency note: the in-memory check happens lock-free on the fast
% path; only the (rare) cache-miss branch enters the mutex. Without the
% mutex, when many parallel download jobs race their first call
% (typical with --jobs 16 and 30+ distfiles in the same wave), every
% worker would issue its own curl. The wasted work was at best harmless,
% but combined with concurrent SWI tmp_file_stream/4 calls it surfaced
% as `existence_error(temporary_file, '')` from `$tmp_file_stream`/4
% under high load (libX11/libXdmcp/libXt class A failures observed in
% an external 1000-package compare matrix). Single-shot mutex eliminates
% the pile-up; the layout fetch itself no longer uses tmp_file_stream
% (see fetch_layout_conf below).

download:mirror_layout(Layout) :-
  download:cached_mirror_layout(Layout), !.

download:mirror_layout(Layout) :-
  with_mutex(download_mirror_layout,
    (   download:cached_mirror_layout(Layout)
    ->  true
    ;   download:read_disk_cache(Layout0)
    ->  Layout = Layout0,
        assertz(download:cached_mirror_layout(Layout))
    ;   download:mirror_layout_from_any(Layout1, Status),
        Layout = Layout1,
        assertz(download:cached_mirror_layout(Layout)),
        ( Status == fetched
        -> download:write_disk_cache(Layout)
        ;  true
        )
    )).


%! download:mirror_layout_from_any(-Layout, -Status) is det.
%
% Tries every configured mirror_url in order, returning the layout from
% the first one that serves a parseable layout.conf. Falls through to
% Layout=flat (the legacy Portage default) when no mirror responds.
% Status is `fetched` on a real success and `fallback` when every
% mirror failed; only `fetched` results are eligible for disk caching.

download:mirror_layout_from_any(Layout, Status) :-
  findall(M, config:mirror_url(M), Mirrors),
  download:mirror_layout_walk(Mirrors, Layout, Status).

download:mirror_layout_walk([], flat, fallback).
download:mirror_layout_walk([MirrorUrl|Rest], Layout, Status) :-
  atomic_list_concat([MirrorUrl, '/layout.conf'], LayoutUrl),
  ( download:fetch_layout_conf(LayoutUrl, Contents),
    mirror:parse_layout_conf(Contents, Layout0)
  -> Layout = Layout0, Status = fetched
  ;  download:mirror_layout_walk(Rest, Layout, Status)
  ).


%! download:disk_cache_path(-Path) is semidet.
%
% Path of the on-disk layout cache. Lives next to distfiles so that
% external matrix harnesses / pengines workflows share it via the
% existing distdir bind mount, with no extra config knob to wire up. Fails when
% the distfiles location is not configured (rare; keeps callers
% defensive).

download:disk_cache_path(Path) :-
  catch(distfiles:get_location(Distdir), _, fail),
  Distdir \== '',
  atomic_list_concat([Distdir, '/.mirror-layout.cache'], Path).


%! download:disk_cache_ttl(-Seconds) is det.
%
% TTL for the disk cache, sourced from config:mirror_layout_cache_ttl/1
% with a 24h hardcoded default if the config knob is absent (older
% deployments that have not picked up the new fact).

download:disk_cache_ttl(Seconds) :-
  ( current_predicate(config:mirror_layout_cache_ttl/1),
    config:mirror_layout_cache_ttl(Seconds)
  -> true
  ;  Seconds = 86400
  ).


%! download:read_disk_cache(-Layout) is semidet.
%
% Reads a still-fresh layout from the on-disk cache. Fails if the
% cache file is missing, malformed, expired, or unreadable -- callers
% must fall through to the network path on failure.

download:read_disk_cache(Layout) :-
  download:disk_cache_path(Path),
  exists_file(Path),
  catch(
    setup_call_cleanup(
      open(Path, read, S),
      read(S, Term),
      close(S)),
    _, fail),
  Term = cached_layout(Layout, FetchEpoch),
  ground(Layout),
  integer(FetchEpoch),
  download:disk_cache_ttl(TTL),
  get_time(NowF),
  Now is integer(NowF),
  Now - FetchEpoch < TTL.


%! download:write_disk_cache(+Layout) is det.
%
% Writes Layout to the on-disk cache atomically (write to .tmp, then
% rename). All errors are swallowed: the cache is best-effort and
% must never break a working download path.

download:write_disk_cache(Layout) :-
  catch(download:write_disk_cache_(Layout), _, true).

download:write_disk_cache_(Layout) :-
  download:disk_cache_path(Path),
  file_directory_name(Path, Dir),
  ( exists_directory(Dir) -> true ; make_directory_path(Dir) ),
  atom_concat(Path, '.tmp', TmpPath),
  get_time(NowF),
  Now is integer(NowF),
  setup_call_cleanup(
    open(TmpPath, write, S),
    format(S, '% Auto-generated by download:write_disk_cache/1. Safe to delete.~n~q.~n',
              [cached_layout(Layout, Now)]),
    close(S)),
  rename_file(TmpPath, Path).


%! download:fetch_layout_conf(+URL, -Contents) is semidet.
%
% Fetch layout.conf from the mirror via curl. Fails if the fetch fails.
%
% Implementation note: we deliberately do NOT use tmp_file_stream/4
% (or any other temp-file-then-curl-then-read-then-delete dance) here.
% Under high-concurrency load (16+ workers calling layout fetch
% before the result is cached, plus other ebuild driver threads),
% SWI's `$tmp_file_stream`/4 was observed to throw
% `existence_error(temporary_file, '')` with context "Not a directory"
% on the call to canonicaliseDir for the tmp_dir. This surfaced as
% the class-A "download cascade SKIP" failures in an external
% 1000-package comparison matrix (12 of 22 portage-ng-only failures).
% Piping curl directly to a Prolog string sidesteps the bug entirely
% and is also a touch faster (no tmp file lifecycle, no extra read).

download:fetch_layout_conf(URL, Contents) :-
  download:url_allowed(URL),
  download:curl_proto_flag(Proto),
  process_create(
    path(curl),
    ['-L', '-s', '-f', '--proto', Proto,
     '--max-time', '30', '--max-filesize', '1048576', URL],
    [stdout(pipe(Out)), stderr(null), process(Pid)]),
  set_stream(Out, encoding(utf8)),
  call_cleanup(
    read_string(Out, _Len, Contents),
    close(Out)),
  process_wait(Pid, exit(ExitCode)),
  ExitCode =:= 0.


% -----------------------------------------------------------------------------
%  Thirdpartymirrors (mirror:// URI resolution)
% -----------------------------------------------------------------------------

%! download:load_thirdpartymirrors is det.
%
% Loads and caches profiles/thirdpartymirrors from the portage tree.
% Each line maps a mirror name to a space-separated list of base URLs.
% Skips comment lines and blank lines. Only loads once per session.

download:load_thirdpartymirrors :-
  download:cached_thirdpartymirror(_, _), !.

download:load_thirdpartymirrors :-
  ( catch(portage:get_location(Root), _, fail),
    os:compose_path(Root, 'profiles/thirdpartymirrors', Path),
    exists_file(Path)
  -> setup_call_cleanup(
       open(Path, read, S),
       download:read_thirdpartymirror_lines(S),
       close(S))
  ;  true
  ).


%! download:read_thirdpartymirror_lines(+Stream) is det.
%
% Reads and asserts all mirror entries from the thirdpartymirrors file.

download:read_thirdpartymirror_lines(S) :-
  read_line_to_string(S, Line),
  ( Line == end_of_file
  -> true
  ;  download:parse_thirdpartymirror_line(Line),
     download:read_thirdpartymirror_lines(S)
  ).


%! download:parse_thirdpartymirror_line(+Line) is det.
%
% Parses a single thirdpartymirrors line. Format is tab-separated:
% mirror_name\tURL1 URL2 URL3 ...

download:parse_thirdpartymirror_line(Line) :-
  ( sub_string(Line, 0, 1, _, "#") -> true
  ; string_length(Line, 0) -> true
  ; split_string(Line, "\t", "", [NameStr|URLParts]),
    URLParts \= []
  -> atom_string(Name, NameStr),
     atomic_list_concat(URLParts, '\t', URLsJoined),
     atom_string(URLsJoined, URLsStr),
     split_string(URLsStr, " ", " ", URLStrs),
     exclude(=(""), URLStrs, URLStrsClean),
     maplist([US, UA]>>atom_string(UA, US), URLStrsClean, URLs),
     assertz(download:cached_thirdpartymirror(Name, URLs))
  ;  true
  ).


%! download:resolve_mirror_uri(+Base, +Filename, -URL) is nondet.
%
% Resolves a mirror:// URI to concrete download URLs. Base is the
% path after mirror:// (e.g. 'gnu/emacs/emacs-29.4.tar.xz'), where
% the first path segment is the mirror name and the rest is the
% relative path. Tries each mirror URL in order on backtracking.

download:resolve_mirror_uri(Base, _Filename, URL) :-
  % Defense-in-depth: if upstream metadata leaked through with an
  % unbound Base (historically: the eapi:uri/3 DCG operator-precedence
  % bug that left P and B unbound on `->`-renamed distfiles), fail
  % cleanly rather than throwing `instantiation_error` from
  % atom_string/2 -- the surrounding findall/3 in
  % fetch:try_upstream_fallback/11 will then simply move on to the
  % next candidate URL, which is the right behaviour even when the
  % parser is misbehaving.
  nonvar(Base),
  download:load_thirdpartymirrors,
  atom_string(Base, BaseStr),
  split_string(BaseStr, "/", "", [MirrorStr|PathParts]),
  PathParts \= [],
  atom_string(MirrorName, MirrorStr),
  atomic_list_concat(PathParts, '/', RelPath),
  download:cached_thirdpartymirror(MirrorName, URLs),
  member(MirrorBase, URLs),
  download:join_mirror_url(MirrorBase, RelPath, URL).


%! download:join_mirror_url(+MirrorBase, +RelPath, -URL) is det.
%
% Joins a mirror base URL with a relative path, ensuring exactly
% one '/' separator between them.

download:join_mirror_url(MirrorBase, RelPath, URL) :-
  ( sub_atom(MirrorBase, _, 1, 0, '/')
  -> atomic_list_concat([MirrorBase, RelPath], URL)
  ;  atomic_list_concat([MirrorBase, '/', RelPath], URL)
  ).


% -----------------------------------------------------------------------------
%  Race-safe distfile staging
% -----------------------------------------------------------------------------
%
% The distdir is bind-mounted into every external build-harness
% session (and into the host emerge sessions running in parallel during
% compare matrices), so multiple writers can race for the same
% `Distdir/Filename`. Two
% concrete failure modes were observed in the 1000-package matrix:
%
%   1. Two processes curl into the same DestPath simultaneously and
%      truncate / interleave each other's writes (verify_size/hashes
%      then fail for both).
%   2. Worker A's curl fails fast (e.g. a 404 from the Gentoo mirror
%      for a RESTRICT=mirror distfile such as dev-libs/cusparselt),
%      A calls delete_file(DestPath), and that delete blows away a
%      perfectly good file that worker B just finished writing.
%
% The helpers below stage every download into a process-private
% `<DestPath>.<Pid>.<Tid>.partial` temp path, atomic-rename on success,
% and -- on failure -- check whether some other writer happened to
% land a valid copy at DestPath in the meantime. We only ever delete
% the temp path; the shared DestPath is treated as immutable from
% outside our own successful rename.

%! download:tmp_dest_path(+DestPath, -TmpPath) is det.
%
% Per-process, per-thread staging path for a distfile download.
% Including both PID and TID makes it safe even when multiple
% threads inside one portage-ng-dev process race for the same
% distfile (e.g. parallel `--jobs N` with the same distfile shared
% between two packages in the same wave).

download:tmp_dest_path(DestPath, TmpPath) :-
  current_prolog_flag(pid, Pid),
  ( catch(thread_self(TidRaw), _, fail) -> Tid = TidRaw ; Tid = main ),
  format(atom(TmpPath), '~w.~w.~w.partial', [DestPath, Pid, Tid]).


%! download:finalize_temp_download(+TmpPath, +DestPath, +ExpectedSize, +Pairs, -OK) is det.
%
% Verify TmpPath against expected size + Manifest hashes, then atomic-
% rename to DestPath on success. On failure, delete only TmpPath and
% then try a race-recovery: if another writer landed a valid file at
% DestPath while we were busy, treat the download as successful (no
% need to retry, no wasted bandwidth on the next URL in the chain).
%
% OK is unified with `true` on success and `false` on failure. We never
% delete DestPath here -- shared distfiles are treated as immutable
% from outside our own successful rename.

download:finalize_temp_download(TmpPath, DestPath, ExpectedSize, Pairs, OK) :-
  ( exists_file(TmpPath),
    download:verify_size(TmpPath, ExpectedSize),
    download:verify_hashes(TmpPath, Pairs)
  -> catch(rename_file(TmpPath, DestPath), _, true),
     OK = true
  ;  catch(delete_file(TmpPath), _, true),
     ( download:race_recover(DestPath, ExpectedSize, Pairs)
     -> OK = true
     ;  OK = false
     )
  ).


%! download:race_recover(+DestPath, +ExpectedSize, +Pairs) is semidet.
%
% Succeeds when DestPath already exists, has the expected size, and
% verifies against the supplied Manifest hash pairs. Used to short-
% circuit a failed/redundant download when another writer (parallel
% emerge, sibling external build-harness session, prior portage-ng job
% in the same wave) has already produced a valid copy.

download:race_recover(DestPath, ExpectedSize, Pairs) :-
  exists_file(DestPath),
  download:verify_size(DestPath, ExpectedSize),
  download:verify_hashes(DestPath, Pairs).


% -----------------------------------------------------------------------------
%  Distfile fetching
% -----------------------------------------------------------------------------

%! download:fetch_distfiles(+Repository, +Entry, +_Context, -Failures) is det.
%
% Download all distfiles for a given ebuild entry. Returns a list of
% filenames that failed to download. Each file is verified against both
% size and Manifest checksums after download. The ?{Context} list is
% currently unused but reserved for future use.

download:fetch_distfiles(Repository, Entry, _Context, Failures) :-
  distfiles:get_location(Distdir),
  ( \+ exists_directory(Distdir) -> make_directory_path(Distdir) ; true ),
  config:mirror_url(MirrorUrl),
  download:mirror_layout(Layout),
  download:collect_distfile_specs(Repository, Entry, DistFiles),
  download:fetch_all(MirrorUrl, Layout, Distdir, DistFiles, [], Failures).


%! download:collect_distfile_specs(+Repository, +Entry, -Specs) is det.
%
% Collect distfile specs with checksums for a given entry. Uses the
% manifest scope of ebuild:distfile_scope/1 -- the distfiles reachable
% under the current USE flags, or every SRC_URI under --fetch-all-uri --
% matching the plan display.

download:collect_distfile_specs(Repository, Entry, Specs) :-
  ebuild:distfile_scope(Scope),
  findall(dist(Filename, Size, Pairs),
    ( query:search(manifest(Scope, dist, Filename, Size), Repository://Entry),
      download:lookup_checksums(Repository, Entry, Filename, Pairs)
    ),
    Specs0),
  sort(1, @<, Specs0, Specs).


%! download:lookup_checksums(+Repository, +Entry, +Filename, -Pairs) is det.
%
% Look up Manifest checksums for a specific distfile. Falls back to
% an empty list if checksums cannot be found.

download:lookup_checksums(Repository, Entry, Filename, Pairs) :-
  cache:ordered_entry(Repository, Entry, Category, Name, _),
  cache:manifest(Repository, ManifestPath, _, Category, Name),
  cache:manifest_metadata(Repository, ManifestPath, dist, Filename, _, ChecksumsStr),
  mirror:parse_manifest_checksums(ChecksumsStr, Pairs),
  !.

download:lookup_checksums(_, _, _, []).


%! download:fetch_all(+MirrorUrl, +Layout, +Distdir, +DistFiles, +FailAcc, -Failures) is det.
%
% Fetch all distfiles sequentially, accumulating failures.

download:fetch_all(_MirrorUrl, _Layout, _Distdir, [], Failures, Failures).

download:fetch_all(MirrorUrl, Layout, Distdir, [dist(Filename, Size, Pairs)|Rest], Acc, Failures) :-
  ( download:fetch_one(MirrorUrl, Layout, Distdir, Filename, Size, Pairs)
  -> download:fetch_all(MirrorUrl, Layout, Distdir, Rest, Acc, Failures)
  ;  download:fetch_all(MirrorUrl, Layout, Distdir, Rest, [Filename|Acc], Failures)
  ).


%! download:fetch_one(+MirrorUrl, +Layout, +Distdir, +Filename, +ExpectedSize, +ChecksumPairs) is semidet.
%
% Fetch a single distfile if not already present in distdir.
% Verifies size and checksums after download. Fails if any check fails.
%
% Race-safety: stages curl into a per-process temp path, atomic-renames
% on success, and falls through to a race-recovery check if our curl
% (or verification) failed but another writer landed a valid copy at
% DestPath in the meantime. Never deletes DestPath -- shared distfiles
% are treated as immutable from outside our own atomic rename. See
% the "Race-safe distfile staging" section above for context.

download:fetch_one(_MirrorUrl, _Layout, Distdir, Filename, _ExpectedSize, _Pairs) :-
  mirror:flat_present(Distdir, Filename), !.

download:fetch_one(MirrorUrl, Layout, Distdir, Filename, ExpectedSize, Pairs) :-
  ( sanitize:safe_filename(Filename) -> true
  ; throw(error(permission_error(write, distfile, Filename),
                context(download:fetch_one/6, 'Invalid distfile name (path traversal rejected)')))
  ),
  download:mirror_download_url(MirrorUrl, Layout, Filename, URL),
  os:compose_path(Distdir, Filename, DestPath),
  download:tmp_dest_path(DestPath, TmpPath),
  download:curl_download(URL, TmpPath, ExitCode),
  ( ExitCode =:= 0
  -> download:finalize_temp_download(TmpPath, DestPath, ExpectedSize, Pairs, OK)
  ;  catch(delete_file(TmpPath), _, true),
     ( download:race_recover(DestPath, ExpectedSize, Pairs)
     -> OK = true
     ;  OK = false
     )
  ),
  OK == true.


%! download:mirror_download_url(+MirrorUrl, +Layout, +Filename, -URL) is det.
%
% Construct the HTTP download URL for a distfile. Uses mirror:distfile_path/4
% with the mirror URL as root to compute the full URL directly.

download:mirror_download_url(MirrorUrl, Layout, Filename, URL) :-
  mirror:distfile_path(MirrorUrl, Layout, Filename, URL).


% -----------------------------------------------------------------------------
%  Curl and verification
% -----------------------------------------------------------------------------

%! download:curl_args(-Args) is det.
%
% Common curl flags used everywhere we fetch a distfile. Mirrors emerge's
% robustness: follow redirects, fail on HTTP >= 400, restrict protocols,
% retry transient errors, resume partial downloads, hard cap per attempt.
% --connect-timeout bounds the initial connect (so a dead mirror does not
% eat the full --max-time before we move on to the next URL).

download:curl_args(Args) :-
  download:curl_proto_flag(Proto),
  Args = ['-L', '-s', '-f',
          '--proto', Proto,
          '--connect-timeout', '15',
          '--retry', '3',
          '--retry-delay', '2',
          '--retry-connrefused',
          '-C', '-',
          '--max-time', '600'].


%! download:curl_proto_flag(-Flag) is det.
%
% curl --proto allowlist. Default https-only; http added when
% config:curl_allow_http(true). ftp is never allowed.

download:curl_proto_flag(Flag) :-
  ( current_predicate(config:curl_allow_http/1),
    config:curl_allow_http(true)
  -> Flag = '=https,http'
  ;  Flag = '=https'
  ).


%! download:url_allowed(+URL) is semidet.
%
% True when URL's scheme is permitted by config:curl_allow_http/1.

download:url_allowed(URL) :-
  atom(URL),
  ( atom_concat('https://', _, URL)
  -> true
  ;  atom_concat('http://', _, URL),
     current_predicate(config:curl_allow_http/1),
     config:curl_allow_http(true)
  ).


%! download:curl_download(+URLOrList, +DestPath, -ExitCode) is det.
%
% Download a file to DestPath using curl (blocking). URLOrList is either
% a single URL atom or a list of URLs to try in order; first successful
% URL wins (curl exits 0). All curl invocations include the standard
% retry/resume flags from download:curl_args/1.

download:curl_download(URL, DestPath, ExitCode) :-
  ( is_list(URL) -> URLs = URL ; URLs = [URL] ),
  download:curl_args(BaseArgs),
  download:curl_walk(URLs, BaseArgs, DestPath, ExitCode).

download:curl_walk([], _, _, 22).
download:curl_walk([URL|Rest], BaseArgs, DestPath, ExitCode) :-
  ( download:url_allowed(URL)
  -> append(BaseArgs, ['-o', DestPath, URL], Args),
     process_create(path(curl), Args,
                    [stdout(null), stderr(null), process(Pid)]),
     process_wait(Pid, exit(EC)),
     ( EC =:= 0
     -> ExitCode = 0
     ;  ( Rest == [] -> ExitCode = EC
        ;  catch(delete_file(DestPath), _, true),
           download:curl_walk(Rest, BaseArgs, DestPath, ExitCode)
        )
     )
  ;  ( Rest == [] -> ExitCode = 22
     ;  download:curl_walk(Rest, BaseArgs, DestPath, ExitCode)
     )
  ).


%! download:start_curl_async(+URLOrList, +DestPath, -Pid) is det.
%
% Start a curl download without blocking. Returns the process Pid for
% later polling via subprocess:poll_exit/2. URLOrList is either a single
% URL atom or a list of URLs; for a list, a small bash trampoline is
% used to walk the URLs sequentially (curl exits 0 at first success).
% The same retry/resume flags as download:curl_args/1 are applied to
% every attempt.

download:start_curl_async(URL, DestPath, Pid) :-
  ( is_list(URL) -> URLs0 = URL ; URLs0 = [URL] ),
  include(download:url_allowed, URLs0, URLs),
  ( URLs == []
  -> process_create(path(false), [],
                    [stdout(null), stderr(null), process(Pid)])
  ;  URLs = [Single]
  -> download:curl_args(BaseArgs),
     append(BaseArgs, ['-o', DestPath, Single], Args),
     process_create(path(curl), Args,
                    [stdout(null), stderr(null), process(Pid)])
  ;  download:async_multi_url_curl(URLs, DestPath, Pid)
  ).


%! download:async_multi_url_curl(+URLs, +DestPath, -Pid) is det.
%
% Spawn bash with a *fixed* `-c` script; DestPath, proto flag, and URLs
% are passed as argv (`$1`, `$2`, `$@` after shift) — never interpolated
% into the script string (sanitize argv contract).

download:async_multi_url_curl(URLs, DestPath, Pid) :-
  download:curl_proto_flag(Proto),
  Script = 'dest="$1"; proto="$2"; shift 2; for u in "$@"; do curl -L -s -f --proto "$proto" --connect-timeout 15 --retry 3 --retry-delay 2 --retry-connrefused -C - --max-time 600 -o "$dest" "$u" && exit 0; rm -f "$dest"; done; exit 22',
  process_create(path(bash),
                 ['-c', Script, 'curlwalk', DestPath, Proto|URLs],
                 [stdout(null), stderr(null), process(Pid)]).


%! download:verify_size(+Path, +ExpectedSize) is semidet.
%
% Verify that the downloaded file matches the expected size from the Manifest.

download:verify_size(Path, ExpectedSize) :-
  ( atom(ExpectedSize)
  -> atom_number(ExpectedSize, Expected)
  ;  Expected = ExpectedSize
  ),
  size_file(Path, ActualSize),
  ActualSize =:= Expected.


%! download:verify_hashes(+Path, +ChecksumPairs) is semidet.
%
% Verify the downloaded file against Manifest checksums. Delegates to
% mirror:verify_hashes/4. Succeeds if all supported hashes match.
% Fails on an empty checksum list: size-only acceptance would let an
% MITM on http/ftp swap a same-sized payload.

download:verify_hashes(_Path, []) :-
  !,
  fail.

download:verify_hashes(Path, Pairs) :-
  mirror:verify_hashes(Path, Pairs, OK, _UnsupportedCount),
  OK == true.


% -----------------------------------------------------------------------------
%  Upstream SRC_URI resolution
% -----------------------------------------------------------------------------

%! download:upstream_url(+Repo, +Entry, +Filename, -URL) is nondet.
%
% Enumerates upstream download URLs for a distfile by looking up the
% original SRC_URI metadata. Handles mirror:// URIs by resolving them
% through profiles/thirdpartymirrors (each thirdpartymirror entry
% becomes a separate solution). For direct http/https/ftp URIs,
% constructs the URL from the stored protocol and path. Yields all
% mirror:// expansions before direct URIs (canonical-source first).
%
% This predicate intentionally has NO cut, so callers can enumerate
% every candidate URL via findall/3 or a backtracking retry loop --
% Gentoo's distfiles mirror prunes old files, but the original
% upstream and its thirdpartymirror peers usually still serve them.
%
% USE/ARCH conditional handling: SRC_URI entries are stored wrapped
% in `use_conditional_group(Sign, UseFlag, Self, Inner)` terms when
% the ebuild gates them on a USE flag (or a USE_EXPAND such as
% `amd64?` for ARCH-conditional binary distfiles, e.g. NVIDIA
% cusparselt). Going through `query:search(src_uri(uri(...)))` only
% binds against the wrapper, so we must traverse the SRC_URI model
% with `query:deep_member(preference, ...)` -- the same helper used
% by the manifest path -- to honour the active global USE flags and
% reach the inner uri/3 terms. Without this, packages like
% dev-libs/cusparselt yielded zero upstream URLs and fell straight
% to "FAIL (download errors)" the moment the Gentoo mirror returned
% 404 (which it always does for RESTRICT=mirror distfiles).

download:upstream_url(Repo, Entry, Filename, URL) :-
  query:search(all(src_uri(Model)), Repo://Entry),
  query:deep_member(preference, uri(Proto, Base, Filename), Model),
  % Guard against partially-bound URI terms (see eapi:uri/3 parser
  % regression). Without nonvar/1 here, an `uri(_,_,Filename)` term
  % would unify with `uri(mirror,...)` regardless of the actual stored
  % protocol, sending the call into resolve_mirror_uri/3 with an
  % unbound Base.
  nonvar(Proto), nonvar(Base),
  Proto == mirror,
  download:resolve_mirror_uri(Base, Filename, URL).

download:upstream_url(Repo, Entry, Filename, URL) :-
  query:search(all(src_uri(Model)), Repo://Entry),
  query:deep_member(preference, uri(Proto, Base, Filename), Model),
  nonvar(Proto), nonvar(Base),
  Proto \== '',
  Proto \== mirror,
  atomic_list_concat([Proto, '://', Base], URL).


% -----------------------------------------------------------------------------
%  RESTRICT=fetch detection
% -----------------------------------------------------------------------------

%! download:is_fetch_restricted(+Repo, +Entry) is semidet.
%
% Succeeds if the ebuild has RESTRICT="fetch", meaning distfiles
% must be manually obtained by the user.

download:is_fetch_restricted(Repo, Entry) :-
  query:search(restrict(fetch), Repo://Entry), !.


% -----------------------------------------------------------------------------
%  Git repository cloning for live ebuilds
% -----------------------------------------------------------------------------

%! download:extract_git_uri(+Repo, +Entry, -URI) is semidet.
%
% Extracts the EGIT_REPO_URI from the .ebuild file by grepping for
% the assignment. Handles the common case where the URI is directly
% assigned (e.g. EGIT_REPO_URI="https://...").

download:extract_git_uri(Repo, Entry, URI) :-
  Repo:get_ebuild_file(Entry, EbuildPath),
  exists_file(EbuildPath),
  download:entry_package_name(Repo, Entry, PN),
  setup_call_cleanup(
    open(EbuildPath, read, S),
    download:scan_for_git_uri(S, PN, URI),
    close(S)).


%! download:entry_package_name(+Repo, +Entry, -PN)
%
% Package name for expanding ${PN} in EGIT_REPO_URI.

download:entry_package_name(Repo, Entry, PN) :-
  cache:ordered_entry(Repo, Entry, _Category, PN, _),
  !.
download:entry_package_name(_Repo, Entry, PN) :-
  atomic_list_concat([_, PF], '/', Entry),
  eapi:packageversion(PF, PN, _),
  !.
download:entry_package_name(_Repo, _Entry, '').


download:scan_for_git_uri(S, PN, URI) :-
  read_line_to_string(S, Line),
  Line \== end_of_file,
  ( download:parse_git_uri_line(Line, PN, URI)
  -> true
  ;  download:scan_for_git_uri(S, PN, URI)
  ).


download:parse_git_uri_line(Line, PN, URI) :-
  sub_string(Line, _, _, _, "EGIT_REPO_URI="),
  split_string(Line, "=", " \t", [_|Parts]),
  Parts \= [],
  atomic_list_concat(Parts, '=', RawValue),
  atom_string(RawValue, RawStr),
  split_string(RawStr, "\"'", "\"'", ValueParts),
  member(VS, ValueParts),
  VS \= "",
  download:expand_git_uri_vars(VS, PN, Expanded),
  download:first_http_token(Expanded, Tok),
  \+ sub_string(Tok, _, _, _, "$"),
  \+ sub_string(Tok, _, _, _, "/api/"),
  \+ sub_string(Tok, _, _, _, " "),
  atom_string(URI, Tok),
  !.


%! download:expand_git_uri_vars(+Raw, +PN, -Expanded)
%
% Expand ${PN} / $PN so live ebuilds that write
% EGIT_REPO_URI="https://.../${PN}.git" are fetchable. Emerge's git-r3
% does this at unpack time; the download step must do it too or PN
% fails while emerge succeeds.

download:expand_git_uri_vars(Raw, '', Raw) :-
  !.
download:expand_git_uri_vars(Raw, PN, Expanded) :-
  atom_string(PN, PNs),
  re_replace('\\$\\{PN\\}'/g, PNs, Raw, Mid),
  re_replace('\\$PN'/g, PNs, Mid, Expanded).


%! download:first_http_token(+Value, -Token)
%
% Take the first http(s)/git URI when HOMEPAGE-style concatenation
% leaked into EGIT_REPO_URI.

download:first_http_token(Value, Token) :-
  split_string(Value, " \t", " \t", Parts),
  member(Token, Parts),
  ( sub_string(Token, 0, 8, _, "https://")
  ; sub_string(Token, 0, 7, _, "http://")
  ; sub_string(Token, 0, 6, _, "git://")
  ),
  !.


%! download:git_cache_dir(+Distdir, -GitCacheDir) is det.
%
% Computes the git3-src cache directory under the distdir, matching
% the Portage git-r3.eclass convention.

download:git_cache_dir(Distdir, GitCacheDir) :-
  atomic_list_concat([Distdir, '/git3-src'], GitCacheDir).


%! download:git_repo_cache_path(+GitCacheDir, +URI, -RepoPath) is det.
%
% Computes the bare repo cache path for a git URI. Converts the URI
% to a safe directory name by replacing '://' and '/' with underscores,
% then appending '.git'.

download:git_repo_cache_path(GitCacheDir, URI, RepoPath) :-
  atom_string(URI, URIStr),
  split_string(URIStr, "://", "", Parts),
  atomic_list_concat(Parts, '_', SafeName0),
  atom_string(SafeName0, S0),
  split_string(S0, "/", "", Segments),
  atomic_list_concat(Segments, '_', SafeName),
  ( sub_atom(SafeName, _, 4, 0, '.git')
  -> RepoName = SafeName
  ;  atom_concat(SafeName, '.git', RepoName)
  ),
  os:compose_path(GitCacheDir, RepoName, RepoPath).


%! download:start_git_clone_async(+URI, +RepoPath, +LogPath, -Pid) is det.
%
% Starts a git clone --bare (or fetch if already cloned) without blocking.
% Progress output is appended to LogPath for polling. The URI is refused
% when git would read it as an option, and passed after `--` on clone.

download:start_git_clone_async(URI, RepoPath, LogPath, Pid) :-
  download:require_git_uri_safe(URI),
  open(LogPath, append, LogStream),
  download:git_spawn_opts(Out, Err, Pid, Opts),
  download:git_no_cred_args(NoCred),
  ( exists_directory(RepoPath)
  -> append(NoCred, ['-C', RepoPath, 'fetch', '--progress', '--all'], Args)
  ;  append(NoCred, ['clone', '--bare', '--progress', '--', URI, RepoPath], Args)
  ),
  process_create(path(git), Args, Opts),
  thread_create(
    download:pipe_to_log(Out, Err, LogStream), _, [detached(true)]).


%! download:git_uri_safe(+URI) is semidet.
%
% True when URI would not be read as a git option. The `git+` prefix
% is stripped first so `git+--upload-pack=x` is rejected the same way
% as `--upload-pack=x` (pkgcore 9c6ae8d).

download:git_uri_safe(URI) :-
  ( atom(URI)
  -> atom_string(URI, S)
  ;  string(URI)
  -> S = URI
  ),
  download:git_uri_effective_(S, Effective),
  \+ sub_string(Effective, 0, 1, _, "-").


%! download:git_uri_effective_(+URI, -Effective) is det.
%
% Strip a leading `git+` transport prefix, if present.

download:git_uri_effective_(S, Effective) :-
  ( sub_string(S, 0, 4, _, "git+")
  -> sub_string(S, 4, _, 0, Effective)
  ;  Effective = S
  ).


%! download:require_git_uri_safe(+URI) is semidet.
%
% Fail (after a user-visible message) when URI is a git option.

download:require_git_uri_safe(URI) :-
  ( download:git_uri_safe(URI)
  -> true
  ;  message:failure(['Refusing git URI that git would read as an option: ', URI]),
     fail
  ).


%! download:git_no_cred_args(-Args) is det.
%
% Extra `git -c` flags that disable credential helpers so a public
% HTTPS clone stays anonymous and a 401 fails instead of prompting.

download:git_no_cred_args(['-c', 'credential.helper=',
                           '-c', 'credential.interactive=never']).


%! download:git_spawn_opts(-Out, -Err, -Pid, -Opts) is det.
%
% Common process_create/3 options for live-ebuild git clone/fetch.
% stdin is closed and credential prompts are disabled so a 401/404
% fails immediately instead of blocking on a username/password prompt.
% Public HTTPS clones are anonymous; /bin/false (not /bin/true) is the
% askpass so git does not treat an empty username as "answered".

download:git_spawn_opts(Out, Err, Pid, Opts) :-
  subprocess:noninteractive_git_env(Env),
  Opts = [stdin(null), stdout(pipe(Out)), stderr(pipe(Err)), process(Pid),
          environment(Env)].


%! download:pipe_to_log(+Out, +Err, +LogStream) is det.
%
% Copies stdout and stderr pipe data into the log stream, then closes
% all three streams. Runs in a detached thread for async git operations.

download:pipe_to_log(Out, Err, LogStream) :-
  catch(
    ( thread_create(
        (catch(copy_stream_data(Err, LogStream), _, true), close(Err)),
        ErrTid, []),
      catch(copy_stream_data(Out, LogStream), _, true),
      close(Out),
      thread_join(ErrTid, _)
    ), _, true),
  catch(close(LogStream), _, true).


%! download:poll_git_progress(+Pid, +LogPath, :Callback, -ExitCode) is det.
%
% Polls a running git process. Parses the last progress line from
% the log to extract a percentage, then calls Callback with the
% current progress. Polls every 0.5 seconds.

:- meta_predicate download:poll_git_progress(+, +, 2, -).

download:poll_git_progress(Pid, LogPath, Callback, ExitCode) :-
  ( subprocess:poll_exit(Pid, EC)
  -> ExitCode = EC
  ;  download:read_git_progress(LogPath, Pct),
     call(Callback, git, progress(Pct)),
     sleep(0.5),
     download:poll_git_progress(Pid, LogPath, Callback, ExitCode)
  ).


%! download:read_git_progress(+LogPath, -Pct) is det.
%
% Reads the last few lines of the git log file and extracts the most
% recent progress percentage. Returns 0 if no percentage is found.

download:read_git_progress(LogPath, Pct) :-
  ( exists_file(LogPath)
  -> catch(
       ( read_file_to_string(LogPath, Content, []),
         download:extract_last_pct(Content, Pct)
       ), _, Pct = 0)
  ;  Pct = 0
  ).

download:extract_last_pct(Content, Pct) :-
  split_string(Content, "\r\n", "", Lines),
  reverse(Lines, RevLines),
  ( member(Line, RevLines),
    Line \= "",
    download:parse_pct_from_line(Line, P)
  -> Pct = P
  ;  Pct = 0
  ).

download:parse_pct_from_line(Line, Pct) :-
  sub_string(Line, Before, 1, _, "%"),
  BeforeStart is max(0, Before - 3),
  Len is Before - BeforeStart,
  sub_string(Line, BeforeStart, Len, _, NumStr),
  split_string(NumStr, " (", " (", Parts),
  last(Parts, PctStr),
  PctStr \= "",
  number_string(Pct0, PctStr),
  Pct is min(99, max(0, Pct0)).
