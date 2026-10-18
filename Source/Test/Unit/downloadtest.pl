/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> DOWNLOADTEST
Security tests for distfile validation, verification and staging.
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
