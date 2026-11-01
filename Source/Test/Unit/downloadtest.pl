/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> DOWNLOADTEST
Security tests for distfile validation, verification and staging,
and git clone progress parsing.
*/

:- module(downloadtest, []).

:- use_module(library(plunit)).

% =============================================================================
% DOWNLOADTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Fixtures
% -----------------------------------------------------------------------------

downloadtest:with_temp_dir(Goal) :-
  tmp_file(downloadtest, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  setup_call_cleanup(true, call(Goal, Tmp),
                     catch(delete_directory_and_contents(Tmp), _, true)).


downloadtest:write_fixture(Dir, Name, Path, Size, Pairs) :-
  os:compose_path(Dir, Name, Path),
  setup_call_cleanup(
    open(Path, write, Out, [type(binary)]),
    format(Out, 'verified fixture~n', []),
    close(Out)),
  size_file(Path, Size),
  mirror:openssl_file_hash(Path, '-sha512', Sha512),
  Pairs = [alg_hash(sha512, Sha512)].


% -----------------------------------------------------------------------------
% Filename and cached-file policy
% -----------------------------------------------------------------------------

:- begin_tests(download_security).

test(reject_traversal_spec,
     [throws(error(permission_error(write, distfile, '../escape'), _))]) :-
  download:validate_distfile_spec(
    dist('../escape', 1, [alg_hash(sha512, deadbeef)])).

test(reject_absolute_spec,
     [throws(error(permission_error(write, distfile, '/tmp/escape'), _))]) :-
  download:validate_distfile_spec(
    dist('/tmp/escape', 1, [alg_hash(sha512, deadbeef)])).

test(reject_unsupported_only,
     [throws(error(domain_error(strong_manifest_hashes, _), _))]) :-
  download:validate_distfile_spec(
    dist('source.tar', 1, [alg_hash(unknown, deadbeef)])).

test(verified_existing_file, [nondet]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Path, Size, Pairs),
      download:verified_distfile(Path, Size, Pairs)
    )).

test(reject_wrong_size, [fail]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Path, Size, Pairs),
      Wrong is Size + 1,
      download:verified_distfile(Path, Wrong, Pairs)
    )).

test(reject_wrong_digest, [fail]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Path, Size, _),
      download:verified_distfile(Path, Size, [alg_hash(sha512, deadbeef)])
    )).

test(reject_weak_only, [fail]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Path, Size, _),
      mirror:openssl_file_hash(Path, '-sha1', Sha1),
      download:verified_distfile(Path, Size, [alg_hash(sha1, Sha1)])
    )).

test(reject_symlink, [condition(current_predicate(link_file/3)), fail]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Path, Size, Pairs),
      os:compose_path(Dir, link, Link),
      link_file(Path, Link, symbolic),
      download:verified_distfile(Link, Size, Pairs)
    )).


% -----------------------------------------------------------------------------
% Private staging and final publication
% -----------------------------------------------------------------------------

test(private_stage_is_sibling_directory) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, distfile, Dest),
      setup_call_cleanup(
        download:create_distfile_stage(Dest, Stage, Tmp),
        ( exists_directory(Stage),
          file_directory_name(Stage, Dir),
          file_directory_name(Tmp, Stage),
          sanitize:not_symlink(Stage)
        ),
        download:cleanup_distfile_stage(Stage))
    )).

test(rename_failure_is_not_success, [nondet]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, source, Tmp, Size, Pairs),
      os:compose_path([Dir, missing, dest], Dest),
      download:finalize_temp_download(Tmp, Dest, Size, Pairs, OK),
      assertion(OK == false)
    )).

test(race_recovery_keeps_valid_peer, [nondet]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      downloadtest:write_fixture(Dir, peer, Dest, Size, Pairs),
      os:compose_path(Dir, invalid, Tmp),
      setup_call_cleanup(open(Tmp, write, Out), write(Out, invalid), close(Out)),
      download:finalize_temp_download(Tmp, Dest, Size, Pairs, OK),
      assertion(OK == true),
      download:verified_distfile(Dest, Size, Pairs)
    )).

:- end_tests(download_security).


% -----------------------------------------------------------------------------
% Git clone progress tail
% -----------------------------------------------------------------------------

:- begin_tests(download_git_progress).

test(missing_log_is_zero) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'absent.log', Path),
      download:read_git_progress(Path, Pct),
      assertion(Pct == 0)
    )).

test(empty_log_is_zero) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'empty.log', Path),
      setup_call_cleanup(open(Path, write, Out), true, close(Out)),
      download:read_git_progress(Path, Pct),
      assertion(Pct == 0)
    )).

test(carriage_return_keeps_latest) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'git.log', Path),
      setup_call_cleanup(
        open(Path, write, Out),
        format(Out, 'Receiving objects: 10%\rReceiving objects: 73%\r', []),
        close(Out)),
      download:read_git_progress(Path, Pct),
      assertion(Pct == 73)
    )).

test(tail_ignores_prefix_beyond_window) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'git.log', Path),
      download:git_progress_window(Window),
      Padding is Window + 64,
      setup_call_cleanup(
        open(Path, write, Out),
        ( format(Out, 'Receiving objects:  1%\n', []),
          forall(between(1, Padding, _), put_char(Out, x)),
          format(Out, '\nReceiving objects: 87% (1/2)\n', [])
        ),
        close(Out)),
      download:read_git_progress(Path, Pct),
      assertion(Pct == 87)
    )).

test(complete_percentage_caps_at_99) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'git.log', Path),
      setup_call_cleanup(
        open(Path, write, Out),
        format(Out, 'Receiving objects: 100% (2/2), done.\n', []),
        close(Out)),
      download:read_git_progress(Path, Pct),
      assertion(Pct == 99)
    )).

:- end_tests(download_git_progress).


% -----------------------------------------------------------------------------
% Full coverage for Domain/Gentoo/mirror.pl
% -----------------------------------------------------------------------------

:- begin_tests(mirror_full_coverage).

test(mirror_layout_paths_diffs_and_verification, [nondet]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'mirror', MirrorRoot),
      os:compose_path(Dir, 'distdir', Distdir),
      make_directory_path(MirrorRoot),
      make_directory_path(Distdir),
      % Write layout.conf with filename-hash BLAKE2B 8
      os:compose_path(MirrorRoot, 'layout.conf', LayoutConf),
      setup_call_cleanup(
        open(LayoutConf, write, SL),
        format(SL, '# comment~n[structure]~n0 = filename-hash BLAKE2B 8~n1 = flat~n[other]~nx = y~n', []),
        close(SL)),
      mirror:layout(MirrorRoot, Layout),
      assertion(Layout == filename_hash(blake2b, [8])),
      mirror:parse_structure_spec("flat", flat),
      mirror:parse_structure_spec("filename-hash BLAKE2B 4:8 extra", filename_hash(blake2b, [4, 8])),
      mirror:pick_structure([structure(0, flat)], flat),
      mirror:pick_structure([structure(0, unknown), structure(1, flat)], flat),
      \+ mirror:filename_hash_hex(unknown_alg, 'foo.tar.gz', _),
      % Write a distfile into both MirrorRoot (under hashed path) and Distdir (flat)
      Filename = 'testdist.tar.gz',
      mirror:distfile_path(MirrorRoot, Layout, Filename, HashedPath),
      file_directory_name(HashedPath, HashedSubdir),
      make_directory_path(HashedSubdir),
      setup_call_cleanup(open(HashedPath, write, SM), write(SM, 'payload'), close(SM)),
      mirror:distfile_path(Distdir, flat, Filename, FlatPath),
      setup_call_cleanup(open(FlatPath, write, SD), write(SD, 'payload'), close(SD)),
      size_file(FlatPath, Size),
      mirror:openssl_file_hash(FlatPath, '-sha256', Sha256),
      format(string(CksumStr),
             'SHA256 ~w BLAKE2B 00 SHA512 00 SHA1 00 MD5 00 RMD160 00 CUSTOM 00 ODD',
             [Sha256]),
      mirror:mirror_present(MirrorRoot, Layout, Filename),
      mirror:flat_present(Distdir, Filename),
      % Register synthetic repository manifest metadata
      V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
      setup_call_cleanup(
        ( assertz(cache:ordered_entry(mtest, 'mcat/mpkg-1.0', mcat, mpkg, V1)),
          assertz(cache:entry_metadata(mtest, 'mcat/mpkg-1.0', src_uri,
                    uri('https', 'ex.org', Filename))),
          assertz(cache:manifest(mtest, '/m/Manifest', 100, mcat, mpkg)),
          assertz(cache:manifest_metadata(mtest, '/m/Manifest', dist, Filename, Size, CksumStr)),
          assertz(cache:manifest_metadata(mtest, '/m/Manifest', dist, Filename, 1, CksumStr)),
          assertz(cache:manifest_metadata(mtest, '/m/Manifest', dist, 'missing.tar.gz', 10, 'SHA256 00'))
        ),
        with_output_to(string(_),
          ( mirror:missing_on_mirror(mtest, MirrorRoot, _),
            mirror:extra_on_mirror(mtest, MirrorRoot, _),
            mirror:missing_on_distdir(mtest, Distdir, _),
            mirror:extra_on_distdir(mtest, Distdir, _),
            mirror:report(mtest, MirrorRoot, Distdir),
            mirror:getenv_default('PORTAGE_NG_NONEXISTENT_ENV_VAR', 'def', 'def'),
            mirror:supported_hash_algorithm(sha256),
            mirror:strong_hash_algorithm(blake2b512),
            mirror:strong_hash_algorithm(sha512),
            mirror:strong_hash_algorithm(sha256),
            mirror:select_for_hash_verification(none, [a,b], [], 0),
            mirror:select_for_hash_verification(all, [a,b], [a,b], 2),
            mirror:select_for_hash_verification(sample(1), [a,b], [a], 1),
            mirror:select_for_hash_verification(sample(5), [a,b], [a,b], 2),
            mirror:verify_size('/no/such/file', 10, false),
            mirror:verify_hashes(FlatPath, [], true, 0),
            mirror:test_stats(mtest, [mirror_root(MirrorRoot), distdir(Distdir), verify_hashes(all)]),
            setenv('PORTAGE_NG_MIRROR_ROOT', MirrorRoot),
            setenv('PORTAGE_NG_DISTDIR', Distdir),
            mirror:test_stats(mtest),
            unsetenv('PORTAGE_NG_MIRROR_ROOT'),
            unsetenv('PORTAGE_NG_DISTDIR')
          )),
        ( retractall(cache:ordered_entry(mtest, 'mcat/mpkg-1.0', _, _, _)),
          retractall(cache:entry_metadata(mtest, 'mcat/mpkg-1.0', _, _)),
          retractall(cache:manifest(mtest, '/m/Manifest', _, _, _)),
          retractall(cache:manifest_metadata(mtest, '/m/Manifest', _, _, _, _))
        ))
    )).

:- end_tests(mirror_full_coverage).


% -----------------------------------------------------------------------------
% Full coverage for Pipeline/Builder/download.pl and Pipeline/Builder/fetch.pl
% -----------------------------------------------------------------------------

:- dynamic distfiles:get_location/1.
:- dynamic portage:get_location/1.
:- dynamic dltest_repo:get_ebuild_file/2.
:- dynamic dltest_repo:get_type/1.

:- begin_tests(download_and_fetch_full_coverage).

test(download_and_fetch_modules_full_coverage, [nondet]) :-
  downloadtest:with_temp_dir(
    [Dir]>>(
      os:compose_path(Dir, 'distdir', Distdir),
      os:compose_path(Dir, 'portage/profiles', ProfilesDir),
      os:compose_path(Dir, 'logs', LogDir),
      make_directory_path(Distdir),
      make_directory_path(ProfilesDir),
      make_directory_path(LogDir),
      % Write thirdpartymirrors
      os:compose_path(ProfilesDir, 'thirdpartymirrors', TpmFile),
      setup_call_cleanup(
        open(TpmFile, write, STPM),
        format(STPM, '# comment~n~ngnu\thttps://ftp.gnu.org/gnu/ https://mirror.gnu.org/gnu~nbadline~n', []),
        close(STPM)),
      % Write live ebuild with EGIT_REPO_URI
      os:compose_path(Dir, 'live-9999.ebuild', LiveEbuild),
      setup_call_cleanup(
        open(LiveEbuild, write, SLE),
        format(SLE, '# ebuild~nEGIT_REPO_URI="https://example.org/${PN}.git"~n', []),
        close(SLE)),
      % Write verified distfile in Distdir
      Filename = 'verified.tar.gz',
      os:compose_path(Distdir, Filename, DestPath),
      setup_call_cleanup(open(DestPath, write, SDF), write(SDF, 'payload'), close(SDF)),
      size_file(DestPath, Size),
      mirror:openssl_file_hash(DestPath, '-sha256', Sha256),
      Pairs = [alg_hash(sha256, Sha256)],
      format(string(CksumStr), 'SHA256 ~w', [Sha256]),
      V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
      % Create a fake curl & git in Dir/bin so curl/git calls are instant and local
      os:compose_path(Dir, 'bin', BinDir),
      make_directory_path(BinDir),
      os:compose_path(BinDir, 'curl', FakeCurl),
      setup_call_cleanup(
        open(FakeCurl, write, SFC),
        format(SFC, '#!/bin/sh~nfor arg in "$@"; do case "$arg" in *layout.conf) printf "[structure]\\n0 = flat\\n"; exit 0;; esac; done~nexit 22~n', []),
        close(SFC)),
      filesex:chmod(FakeCurl, 0o755),
      os:compose_path(BinDir, 'git', FakeGit),
      setup_call_cleanup(
        open(FakeGit, write, SFG),
        format(SFG, '#!/bin/sh~necho "Receiving objects: 50%%" >&2~nexit 0~n', []),
        close(SFG)),
      filesex:chmod(FakeGit, 0o755),
      getenv('PATH', OldPath),
      atomic_list_concat([BinDir, ':', OldPath], NewPath),
      os:compose_path(Dir, 'portage', PortageRoot),
      setup_call_cleanup(
        ( setenv('PATH', NewPath),
          retractall(distfiles:get_location(_)),
          asserta(distfiles:get_location(Distdir)),
          retractall(portage:get_location(_)),
          asserta(portage:get_location(PortageRoot)),
          retractall(config:build_log_dir(_)),
          asserta(config:build_log_dir(LogDir)),
          retractall(download:cached_mirror_layout(_)),
          retractall(download:cached_thirdpartymirror(_, _)),
          asserta(dltest_repo:get_ebuild_file('dcat/dpkg-1.0', LiveEbuild)),
          asserta(dltest_repo:get_ebuild_file('dcat/unindexed-1.0', LiveEbuild)),
          asserta(dltest_repo:get_type(eapi)),
          assertz(cache:ordered_entry(dltest_repo, 'dcat/dpkg-1.0', dcat, dpkg, V1)),
          assertz(cache:entry_metadata(dltest_repo, 'dcat/dpkg-1.0', src_uri,
                    uri('mirror', 'gnu/dpkg/verified.tar.gz', Filename))),
          assertz(cache:entry_metadata(dltest_repo, 'dcat/dpkg-1.0', src_uri,
                    uri('https', 'example.org/verified.tar.gz', Filename))),
          assertz(cache:manifest(dltest_repo, '/m/Manifest', 100, dcat, dpkg)),
          assertz(cache:manifest_metadata(dltest_repo, '/m/Manifest', dist, Filename, Size, CksumStr))
        ),
        with_output_to(string(_),
          ( % 1. Mirror layout disk cache + network fetch
            download:write_disk_cache(flat),
            download:read_disk_cache(flat),
            download:mirror_layout(flat),
            download:mirror_layout(flat),
            retractall(download:cached_mirror_layout(_)),
            download:disk_cache_path(CachePath),
            catch(delete_file(CachePath), _, true),
            download:mirror_layout(flat),
            download:mirror_layout_walk([], flat, fallback),
            % 2. Thirdpartymirrors & upstream_url
            download:load_thirdpartymirrors,
            download:load_thirdpartymirrors,
            findall(U, download:upstream_url(dltest_repo, 'dcat/dpkg-1.0', Filename, U), [_, _, _]),
            % 3. collect_distfile_specs, lookup_checksums, fetch_distfiles, fetch_one, curl_download, start_curl_async
            download:collect_distfile_specs(dltest_repo, 'dcat/dpkg-1.0', Specs),
            download:lookup_checksums(dltest_repo, 'dcat/none-1.0', 'none', []),
            download:fetch_distfiles(dltest_repo, 'dcat/dpkg-1.0', [], []),
            os:compose_path(Distdir, 'missing.tar.gz', MissingDest),
            \+ download:fetch_one('https://mirror.example.org', flat, Distdir, 'missing.tar.gz', Size, Pairs),
            asserta(config:curl_allow_http(true)),
            download:curl_proto_flag('=https,http'),
            download:url_allowed('http://example.org/a'),
            retractall(config:curl_allow_http(true)),
            download:curl_download([], MissingDest, 22),
            download:curl_download(['ftp://disallowed', 'https://example.org/a', 'https://example.org/b'], MissingDest, _),
            download:start_curl_async([], MissingDest, PidEmpty),
            process_wait(PidEmpty, _),
            download:start_curl_async(['https://example.org/a'], MissingDest, PidSingle),
            process_wait(PidSingle, _),
            download:start_curl_async(['https://example.org/a', 'https://example.org/b'], MissingDest, PidMulti),
            process_wait(PidMulti, _),
            % 4. Git URI extraction, repo cache path, start_git_clone_async, poll_git_progress
            download:extract_git_uri(dltest_repo, 'dcat/dpkg-1.0', 'https://example.org/dpkg.git'),
            download:extract_git_uri(dltest_repo, 'dcat/unindexed-1.0', 'https://example.org/unindexed.git'),
            download:entry_package_name(dltest_repo, 'not_a_cpv', ''),
            download:expand_git_uri_vars("https://example.org/a.git", '', "https://example.org/a.git"),
            download:git_cache_dir(Distdir, GitCacheDir),
            download:git_repo_cache_path(GitCacheDir, 'https://example.org/repo', _),
            download:git_repo_cache_path(GitCacheDir, 'https://example.org/repo.git', RepoPath),
            % 5. fetch.pl: run_git_download, run_download_parallel, speed tracking, poll_download_loop, try_upstream_fallback, handle_restricted_files
            fetch:run_git_download(dltest_repo, 'dcat/dpkg-1.0', 1, 2, 0, 1, 1, 0, download, done),
            make_directory_path(RepoPath),
            fetch:run_git_download(dltest_repo, 'dcat/dpkg-1.0', 1, 2, 0, 1, 1, 0, download, done),
            fetch:run_git_download(dltest_repo, 'dcat/no_ebuild', 1, 2, 0, 1, 1, 0, download, done),
            fetch:git_progress_callback(1, 2, git, progress(50)),
            fetch:git_progress_callback(1, 2, git, other),
            fetch:safe_mirror_layout(_),
            fetch:run_download_parallel(dltest_repo, 'dcat/dpkg-1.0', [], 0, 2, 1, 1, 0, download, 1, Specs, Distdir, done),
            % Restricted fetch (both present and missing)
            assertz(cache:entry_metadata(dltest_repo, 'dcat/dpkg-1.0', restrict, fetch)),
            fetch:run_download_parallel(dltest_repo, 'dcat/dpkg-1.0', [], 0, 2, 1, 1, 0, download, 1, Specs, Distdir, done),
            MissingSpec = [dist('missing_restr.tar.gz', Size, Pairs)],
            fetch:run_download_parallel(dltest_repo, 'dcat/dpkg-1.0', [], 0, 2, 1, 1, 0, download, 1, MissingSpec, Distdir, _),
            retractall(cache:entry_metadata(dltest_repo, 'dcat/dpkg-1.0', restrict, fetch)),
            % Failing download job + speed tracking + upstream fallback
            fetch:run_download_parallel(dltest_repo, 'dcat/dpkg-1.0', [], 0, 2, 1, 1, 0, download, 1, MissingSpec, Distdir, _),
            fetch:init_speed_tracking([dl_job(1, 0, 'f', 100, Pairs, DestPath, Dir, DestPath, dltest_repo, 'dcat/dpkg-1.0')], 0.0, 1),
            fetch:compute_speed(1, 50, _),
            fetch:compute_speed(999, 50, _),
            fetch:update_download_progress(0, Filename, Size, DestPath, DestPath, 2, 1, Distdir),
            fetch:update_download_progress(0, 'none', Size, '/no/file', '/no/tmp', 2, 1, Distdir),
            fetch:try_upstream_fallback(0, Filename, Size, Pairs, DestPath, dltest_repo, 'dcat/dpkg-1.0', 2, 1, Distdir, _),
            fetch:try_upstream_fallback(0, Filename, Size, Pairs, MissingDest, dltest_repo, 'dcat/dpkg-1.0', 2, 1, Distdir, false),
            fetch:clear_speed_tracking
          )),
        ( setenv('PATH', OldPath),
          retractall(distfiles:get_location(Distdir)),
          retractall(portage:get_location(PortageRoot)),
          retractall(config:build_log_dir(LogDir)),
          assertz(config:build_log_dir('/var/tmp/portage-ng/logs')),
          retractall(download:cached_mirror_layout(_)),
          retractall(download:cached_thirdpartymirror(_, _)),
          retractall(dltest_repo:get_ebuild_file(_, _)),
          retractall(dltest_repo:get_type(_)),
          retractall(cache:ordered_entry(dltest_repo, _, _, _, _)),
          retractall(cache:entry_metadata(dltest_repo, _, _, _)),
          retractall(cache:manifest(dltest_repo, _, _, _, _)),
          retractall(cache:manifest_metadata(dltest_repo, _, _, _, _, _))
        ))
    )).

:- end_tests(download_and_fetch_full_coverage).


