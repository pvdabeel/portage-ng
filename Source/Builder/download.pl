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
% Get the GLEP 75 layout of the HTTP mirror. Fetches layout.conf from
% the mirror URL on first call, then caches the result.

download:mirror_layout(Layout) :-
  download:cached_mirror_layout(Layout), !.

download:mirror_layout(Layout) :-
  config:mirror_url(MirrorUrl),
  atomic_list_concat([MirrorUrl, '/layout.conf'], LayoutUrl),
  ( download:fetch_layout_conf(LayoutUrl, Contents)
  -> ( mirror:parse_layout_conf(Contents, Layout0)
     -> Layout = Layout0
     ;  Layout = flat
     )
  ;  Layout = flat
  ),
  assertz(download:cached_mirror_layout(Layout)).


%! download:fetch_layout_conf(+URL, -Contents) is semidet.
%
% Fetch layout.conf from the mirror via curl. Fails if the fetch fails.

download:fetch_layout_conf(URL, Contents) :-
  tmp_file_stream(text, TmpPath, Stream),
  close(Stream),
  process_create(
    path(curl),
    ['-L', '-s', '-f', '--proto', '=https,http,ftp',
     '--max-time', '30', '--max-filesize', '1048576', '-o', TmpPath, URL],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)),
  ExitCode =:= 0,
  read_file_to_string(TmpPath, Contents, []),
  delete_file(TmpPath).


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
%  Distfile fetching
% -----------------------------------------------------------------------------

%! download:fetch_distfiles(+Repository, +Entry, +Context, -Failures) is det.
%
% Download all distfiles for a given ebuild entry. Returns a list of
% filenames that failed to download. Each file is verified against both
% size and Manifest checksums after download.

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
% preference-scoped manifest query so only distfiles reachable under
% the current USE flag settings are included (matching the plan display).

download:collect_distfile_specs(Repository, Entry, Specs) :-
  findall(dist(Filename, Size, Pairs),
    ( kb:query(manifest(preference, dist, Filename, Size), Repository://Entry),
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

download:fetch_one(_MirrorUrl, _Layout, Distdir, Filename, _ExpectedSize, _Pairs) :-
  mirror:flat_present(Distdir, Filename), !.

download:fetch_one(MirrorUrl, Layout, Distdir, Filename, ExpectedSize, Pairs) :-
  ( sanitize:safe_filename(Filename) -> true
  ; throw(error(permission_error(write, distfile, Filename),
                context(download:fetch_one/6, 'Invalid distfile name (path traversal rejected)')))
  ),
  download:mirror_download_url(MirrorUrl, Layout, Filename, URL),
  atomic_list_concat([Distdir, '/', Filename], DestPath),
  download:curl_download(URL, DestPath, ExitCode),
  ExitCode =:= 0,
  download:verify_size(DestPath, ExpectedSize),
  ( download:verify_hashes(DestPath, Pairs)
  -> true
  ;  catch(delete_file(DestPath), _, true),
     fail
  ).


%! download:mirror_download_url(+MirrorUrl, +Layout, +Filename, -URL) is det.
%
% Construct the HTTP download URL for a distfile. Uses mirror:distfile_path/4
% with the mirror URL as root to compute the full URL directly.

download:mirror_download_url(MirrorUrl, Layout, Filename, URL) :-
  mirror:distfile_path(MirrorUrl, Layout, Filename, URL).


% -----------------------------------------------------------------------------
%  Curl and verification
% -----------------------------------------------------------------------------

%! download:curl_download(+URL, +DestPath, -ExitCode) is det.
%
% Download a file from URL to DestPath using curl (blocking).

download:curl_download(URL, DestPath, ExitCode) :-
  process_create(
    path(curl),
    ['-L', '-s', '-f', '--proto', '=https,http,ftp',
     '--max-time', '600', '-o', DestPath, URL],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)).


%! download:start_curl_async(+URL, +DestPath, -Pid) is det.
%
% Start a curl download without blocking. Returns the process Pid
% for later polling via check_process_done/2.

download:start_curl_async(URL, DestPath, Pid) :-
  process_create(
    path(curl),
    ['-L', '-s', '-f', '--proto', '=https,http,ftp',
     '--max-time', '600', '-o', DestPath, URL],
    [stdout(null), stderr(null), process(Pid)]).


%! download:check_process_done(+Pid, -ExitCode) is semidet.
%
% Non-blocking check whether a process has exited. Succeeds with the
% exit code if done, fails if still running.

download:check_process_done(Pid, ExitCode) :-
  catch(
    process_wait(Pid, exit(ExitCode), [timeout(0)]),
    _,
    fail
  ).


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

download:verify_hashes(_Path, []) :- !.

download:verify_hashes(Path, Pairs) :-
  mirror:verify_hashes(Path, Pairs, OK, _UnsupportedCount),
  OK == true.


% -----------------------------------------------------------------------------
%  Upstream SRC_URI resolution
% -----------------------------------------------------------------------------

%! download:upstream_url(+Repo, +Entry, +Filename, -URL) is semidet.
%
% Resolves the upstream download URL for a distfile by looking up the
% original SRC_URI metadata. Handles mirror:// URIs by resolving them
% through profiles/thirdpartymirrors. For direct http/https/ftp URIs,
% constructs the URL from the stored protocol and path. Tries mirror://
% URIs first (they are typically the canonical source), then falls back
% to direct URIs.

download:upstream_url(Repo, Entry, Filename, URL) :-
  kb:query(src_uri(uri(mirror, Base, Filename)), Repo://Entry),
  download:resolve_mirror_uri(Base, Filename, URL),
  !.

download:upstream_url(Repo, Entry, Filename, URL) :-
  kb:query(src_uri(uri(Proto, Base, Filename)), Repo://Entry),
  Proto \= '',
  Proto \= mirror,
  atomic_list_concat([Proto, '://', Base], URL),
  !.


% -----------------------------------------------------------------------------
%  RESTRICT=fetch detection
% -----------------------------------------------------------------------------

%! download:is_fetch_restricted(+Repo, +Entry) is semidet.
%
% Succeeds if the ebuild has RESTRICT="fetch", meaning distfiles
% must be manually obtained by the user.

download:is_fetch_restricted(Repo, Entry) :-
  kb:query(restrict(fetch), Repo://Entry), !.


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
  setup_call_cleanup(
    open(EbuildPath, read, S),
    download:scan_for_git_uri(S, URI),
    close(S)).

download:scan_for_git_uri(S, URI) :-
  read_line_to_string(S, Line),
  Line \== end_of_file,
  ( download:parse_git_uri_line(Line, URI)
  -> true
  ;  download:scan_for_git_uri(S, URI)
  ).

download:parse_git_uri_line(Line, URI) :-
  sub_string(Line, _, _, _, "EGIT_REPO_URI="),
  split_string(Line, "=", " \t", [_|Parts]),
  Parts \= [],
  atomic_list_concat(Parts, '=', RawValue),
  atom_string(RawValue, RawStr),
  split_string(RawStr, "\"'", "\"'", ValueParts),
  member(VS, ValueParts),
  VS \= "",
  atom_string(URI, VS),
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
  atomic_list_concat([GitCacheDir, '/', RepoName], RepoPath).


%! download:start_git_clone_async(+URI, +RepoPath, +LogPath, -Pid) is det.
%
% Starts a git clone --bare (or fetch if already cloned) without blocking.
% Progress output is appended to LogPath for polling.

download:start_git_clone_async(URI, RepoPath, LogPath, Pid) :-
  open(LogPath, append, LogStream),
  ( exists_directory(RepoPath)
  -> process_create(
       path(git),
       ['-C', RepoPath, 'fetch', '--progress', '--all'],
       [stdout(pipe(Out)), stderr(pipe(Err)),
        process(Pid)])
  ;  process_create(
       path(git),
       ['clone', '--bare', '--progress', URI, RepoPath],
       [stdout(pipe(Out)), stderr(pipe(Err)),
        process(Pid)])
  ),
  thread_create(
    download:pipe_to_log(Out, Err, LogStream), _, [detached(true)]).


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
  ( download:check_process_done(Pid, EC)
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
