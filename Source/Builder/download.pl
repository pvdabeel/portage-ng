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

This module is pure execution logic -- no display calls. Progress
rendering is handled by the builder and build printer.
*/

:- module(download, []).

% =============================================================================
%  DOWNLOAD declarations
% =============================================================================

:- dynamic download:cached_mirror_layout/1.

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
    ['-L', '-s', '-f', '-o', TmpPath, URL],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)),
  ExitCode =:= 0,
  read_file_to_string(TmpPath, Contents, []),
  delete_file(TmpPath).


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
% SRC_URI-scoped manifest query to get only the distfiles needed for
% this specific entry, then looks up checksums from manifest_metadata.

download:collect_distfile_specs(Repository, Entry, Specs) :-
  findall(dist(Filename, Size, Pairs),
    ( kb:query(manifest(all, dist, Filename, Size), Repository://Entry),
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
    ['-L', '-s', '-f', '-o', DestPath, URL],
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(ExitCode)).


%! download:start_curl_async(+URL, +DestPath, -Pid) is det.
%
% Start a curl download without blocking. Returns the process Pid
% for later polling via check_process_done/2.

download:start_curl_async(URL, DestPath, Pid) :-
  process_create(
    path(curl),
    ['-L', '-s', '-f', '-o', DestPath, URL],
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
