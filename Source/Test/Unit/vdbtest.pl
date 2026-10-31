/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> VDBTEST
Unit tests for the --import-vdb wire format and server registration.

The server-mode module is loaded on demand; the units skip when the
environment cannot be set up.
*/

:- module(vdbtest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  VDBTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
% VDB import round-trip tests (--import-vdb wire format + server registration)
% -----------------------------------------------------------------------------

%! vdb_import_env_ready is semidet.
%
% Load the server-mode module (and the libraries it needs) on demand so the
% /import-vdb handler logic can be exercised in a standalone test session.
% Fails (skipping the dependent tests) when the environment cannot be set up.

vdb_import_env_ready :-
  catch(
    ( load_files([library(pengines),
                  library('http/http_client'),
                  library('http/http_digest'),
                  library(streams)], [if(not_loaded)]),
      load_files(portage('Source/Application/Mode/server'), [if(not_loaded)])
    ),
    _, fail).


%! vdb_emit(+Term) is det.
%
% Emit one canonical wire term (mirrors client:emit_vdb_term/1).

vdb_emit(T) :-
  write_canonical(T),
  write('.\n').


%! vdb_test_payload(+Hostname, +Entries, +Metadata, -Payload) is det.
%
% Build a well-formed /import-vdb payload string from oe/4 and md/3 fact
% lists, mirroring the client-side serializer (client:vdb_payload/3).

vdb_test_payload(Hostname, Entries, Metadata, Payload) :-
  length(Entries, EC),
  length(Metadata, MC),
  variant_sha1(Entries-Metadata, Sha),
  with_output_to(string(Payload),
    ( vdb_emit(vdb_import_v1),
      vdb_emit(hostname(Hostname)),
      vdb_emit(stamp(stamp(EC, Sha))),
      forall(member(E, Entries), vdb_emit(E)),
      forall(member(M, Metadata), vdb_emit(M)),
      vdb_emit(end_of_vdb_import(EC, MC))
    )).


%! vdb_import_cleanup(+Repo) is det.
%
% Retract every fact registered for a test import repository.

vdb_import_cleanup(Repo) :-
  retractall(cache:repository(Repo)),
  retractall(cache:category(Repo, _)),
  retractall(cache:package(Repo, _, _)),
  retractall(cache:ordered_entry(Repo, _, _, _, _)),
  retractall(cache:entry_metadata(Repo, _, _, _)),
  retractall(knowledgebase:client_vdb_import(_, Repo, _, _, _, _, _)).


:- begin_tests(vdb_import_roundtrip).

test(synthetic_roundtrip,
     [condition(vdb_import_env_ready),
      cleanup(vdb_import_cleanup('pkg@unittest.local')),
      nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,1], '', 4, 0, [], 1, '2.1-r1'),
  Entries = [oe('test-cat/foo-2.1-r1', 'test-cat', foo, V2),
             oe('test-cat/foo-1.0',    'test-cat', foo, V1),
             oe('other-cat/bar-1.0',   'other-cat', bar, V1)],
  Metadata = [md('test-cat/foo-2.1-r1', installed, true),
              md('test-cat/foo-1.0',    installed, true),
              md('test-cat/foo-1.0',    slot, slot('0')),
              md('other-cat/bar-1.0',   installed, true)],
  vdb_test_payload('unittest.local', Entries, Metadata, Payload),
  with_output_to(string(Out), server:import_vdb(Payload)),
  term_string(vdb_import_ok('pkg@unittest.local', _, 3, 4), Out),
  Repo = 'pkg@unittest.local',
  % Repository registered with derived category/package facts.
  cache:repository(Repo),
  findall(C, cache:category(Repo, C), Cats0),
  msort(Cats0, Cats),
  Cats == ['other-cat', 'test-cat'],
  cache:package(Repo, 'test-cat', foo),
  cache:package(Repo, 'other-cat', bar),
  % Ordered entries preserved in wire order (version-descending).
  findall(oe(Id, C2, N2, Vv), cache:ordered_entry(Repo, Id, C2, N2, Vv), Got),
  Got == Entries,
  % Metadata facts round-trip exactly.
  findall(md(Id2, K, Val), cache:entry_metadata(Repo, Id2, K, Val), GotMd),
  msort(GotMd, GotMdS),
  msort(Metadata, MdS),
  GotMdS == MdS,
  % Import stamp registered for staleness checks.
  knowledgebase:client_vdb_import(tenant(legacy, 'unittest.local'),
                                  Repo, stamp(3, _), _, 3, 4, _).

test(real_vdb_parity,
     [condition((vdb_import_env_ready, cache:repository(pkg))),
      cleanup(vdb_import_cleanup('pkg@unittest-parity.local')),
      nondet]) :-
  % Serialize the real (already loaded) pkg repository and re-import it as
  % a per-client repo; the imported fact set must match the original
  % exactly, including ordered_entry order.
  findall(oe(Id, C, N, V), cache:ordered_entry(pkg, Id, C, N, V), Entries),
  Entries \== [],
  findall(md(Id, K, V), cache:entry_metadata(pkg, Id, K, V), Metadata),
  vdb_test_payload('unittest-parity.local', Entries, Metadata, Payload),
  with_output_to(string(_), server:import_vdb(Payload)),
  Repo = 'pkg@unittest-parity.local',
  findall(oe(Id, C, N, V), cache:ordered_entry(Repo, Id, C, N, V), Got),
  Got == Entries,
  findall(md(Id, K, V), cache:entry_metadata(Repo, Id, K, V), GotMd),
  msort(GotMd, GotMdS),
  msort(Metadata, MdS),
  GotMdS == MdS,
  % installed(true) parity between the original and imported repo.
  findall(E1, cache:entry_metadata(pkg,  E1, installed, true), I1),
  findall(E2, cache:entry_metadata(Repo, E2, installed, true), I2),
  msort(I1, S1),
  msort(I2, S2),
  S1 == S2.

test(reject_bad_hostname,
     [condition(vdb_import_env_ready),
      throws(error(permission_error(import, hostname, _), _))]) :-
  V = version([1,0], '', 4, 0, [], 0, '1.0'),
  vdb_test_payload('../etc', [oe('c/p-1.0', c, p, V)], [], Payload),
  with_output_to(string(_), server:import_vdb(Payload)).

test(reject_bad_fact_shape,
     [condition(vdb_import_env_ready),
      throws(error(type_error(vdb_import_fact, _), _))]) :-
  with_output_to(string(Payload),
    ( vdb_emit(vdb_import_v1),
      vdb_emit(hostname('unittest.local')),
      vdb_emit(stamp(stamp(1, '0000000000000000000000000000000000000000'))),
      vdb_emit(evil_fact(1)),
      vdb_emit(end_of_vdb_import(1, 0))
    )),
  with_output_to(string(_), server:import_vdb(Payload)).

test(reject_truncated_payload,
     [condition(vdb_import_env_ready),
      throws(error(type_error(vdb_import_term, end_of_file), _))]) :-
  with_output_to(string(Payload),
    ( vdb_emit(vdb_import_v1),
      vdb_emit(hostname('unittest.local')),
      vdb_emit(stamp(stamp(1, '0000000000000000000000000000000000000000')))
    )),
  with_output_to(string(_), server:import_vdb(Payload)).

test(reject_oversized_term, [condition(vdb_import_env_ready)]) :-
  % A single md/3 value longer than the per-term cap must be rejected
  % while reading, before the fact-count caps could ever fire.
  server:vdb_import_max_term_length(Max),
  BigLen is Max + 1000,
  length(BigCodes, BigLen),
  maplist(=(0'a), BigCodes),
  atom_codes(BigAtom, BigCodes),
  term_string(md('c/p-1.0', big, BigAtom), BigLine),
  format(string(Payload), 'vdb_import_v1.~nhostname(~q).~nstamp(stamp(1, ''0000000000000000000000000000000000000000'')).~n~w.~nend_of_vdb_import(1, 1).~n',
         ['unittest.local', BigLine]),
  ( catch(with_output_to(string(_), server:import_vdb(Payload)), E, Caught = E)
  -> nonvar(Caught)
  ;  fail
  ).

test(payload_size_cap) :-
  server:check_vdb_payload_size("small", 100),
  \+ catch(server:check_vdb_payload_size("this payload is too large", 4), _, fail).


test(request_stream_roundtrip,
     [condition(vdb_import_env_ready),
      cleanup(vdb_import_cleanup('pkg@unittest-stream.local')),
      nondet]) :-
  V = version([1,0], '', 4, 0, [], 0, '1.0'),
  Entries = [oe('test-cat/foo-1.0', 'test-cat', foo, V)],
  Metadata = [md('test-cat/foo-1.0', installed, true)],
  vdb_test_payload('unittest-stream.local', Entries, Metadata, Payload),
  string_codes(Payload, BytesList),
  length(BytesList, Bytes),
  setup_call_cleanup(
    open_string(Payload, In),
    server:import_vdb_request(
      [user(tenant(test, 'unittest-stream.local')),
       content_length(Bytes), input(In)],
      Result),
    close(In)),
  Result = vdb_import_ok('pkg@unittest-stream.local', _, 1, 1).

test(request_rejects_certificate_hostname_mismatch,
     [condition(vdb_import_env_ready),
      throws(error(permission_error(import, hostname, _), _))]) :-
  V = version([1,0], '', 4, 0, [], 0, '1.0'),
  vdb_test_payload('claimed.local',
                   [oe('test-cat/foo-1.0', 'test-cat', foo, V)], [], Payload),
  string_codes(Payload, BytesList),
  length(BytesList, Bytes),
  setup_call_cleanup(
    open_string(Payload, In),
    server:import_vdb_request(
      [user(tenant(test, 'certificate.local')),
       content_length(Bytes), input(In)],
      _),
    close(In)).

test(oversized_content_length_rejected_before_read,
     [condition(vdb_import_env_ready)]) :-
  server:vdb_import_max_payload_bytes(Max),
  TooLarge is Max + 1,
  setup_call_cleanup(
    open_string("unread", In),
    ( catch(server:import_vdb_request(
              [user(tenant(test, 'unittest.local')),
               content_length(TooLarge), input(In)], _),
            http_reply(payload_too_large), Caught = true),
      Caught == true,
      byte_count(In, 0)
    ),
    close(In)).

test(transaction_rollback_preserves_old_import,
     [condition(vdb_import_env_ready),
      cleanup(vdb_import_cleanup('pkg@rollback.local')),
      nondet]) :-
  V = version([1,0], '', 4, 0, [], 0, '1.0'),
  OldEntries = [oe('test-cat/old-1.0', 'test-cat', old, V)],
  OldMetadata = [md('test-cat/old-1.0', installed, true)],
  vdb_test_payload('rollback.local', OldEntries, OldMetadata, GoodPayload),
  with_output_to(string(_), server:import_vdb(GoodPayload)),
  with_output_to(string(BadPayload),
    ( vdb_emit(vdb_import_v1),
      vdb_emit(hostname('rollback.local')),
      vdb_emit(stamp(stamp(1, '0000000000000000000000000000000000000000'))),
      vdb_emit(oe('test-cat/new-1.0', 'test-cat', new, V)),
      vdb_emit(evil_fact),
      vdb_emit(end_of_vdb_import(1, 0))
    )),
  catch(with_output_to(string(_), server:import_vdb(BadPayload)), _, true),
  cache:ordered_entry('pkg@rollback.local', 'test-cat/old-1.0',
                      'test-cat', old, V),
  \+ cache:ordered_entry('pkg@rollback.local', 'test-cat/new-1.0', _, _, _).

test(certificate_identity_from_fixture,
     [condition((vdb_import_env_ready,
                 config:certificate('mac-pro.local', 'client-cert.pem', CertPath),
                 exists_file(CertPath))),
      nondet]) :-
  config:certificate('mac-pro.local', 'client-cert.pem', CertPath),
  setup_call_cleanup(
    open(CertPath, read, In, [type(binary)]),
    ssl:load_certificate(In, Certificate),
    close(In)),
  server:certificate_identity(Certificate, 'mac-pro.local', _).

:- end_tests(vdb_import_roundtrip).


% -----------------------------------------------------------------------------
%  Full coverage for Domain/Gentoo/vdb.pl and Domain/Gentoo/upstream.pl
% -----------------------------------------------------------------------------

vdbtest_mktemp(Prefix, Dir) :-
  tmp_file_stream(text, Base, Stream),
  close(Stream),
  delete_file(Base),
  atomic_list_concat([Base, '_', Prefix], Dir),
  make_directory(Dir).

vdbtest_rm_rf(Path) :-
  exists_directory(Path), !,
  directory_files(Path, Entries),
  forall((member(E, Entries), E \== '.', E \== '..'),
         ( os:compose_path(Path, E, Child),
           vdbtest_rm_rf(Child) )),
  catch(delete_directory(Path), _, true).
vdbtest_rm_rf(Path) :-
  exists_file(Path), !,
  catch(delete_file(Path), _, true).
vdbtest_rm_rf(_).

vdb_mock_repo:category('vcat').

:- begin_tests(vdb_and_upstream_full_coverage).

test(vdb_module_full_coverage, [nondet]) :-
  vdbtest_mktemp(vdb_cov, TmpDir),
  os:compose_path(TmpDir, 'pkg', PkgDir),
  os:compose_path(TmpDir, 'root', RootDir),
  os:compose_path(RootDir, 'sub', SubDir),
  make_directory_path(SubDir),
  os:compose_path(RootDir, 'owned.bin', OwnedFile),
  setup_call_cleanup(open(OwnedFile, write, SO), write(SO, 'hello'), close(SO)),
  crypto_file_hash(OwnedFile, OwnedMd5, [algorithm(md5), encoding(octet)]),
  os:compose_path(SubDir, 'unmanaged.txt', UnmanagedFile),
  setup_call_cleanup(open(UnmanagedFile, write, SU), write(SU, 'extra'), close(SU)),
  os:compose_path(PkgDir, 'vcat/vpkg-1.0', EntryDir),
  make_directory_path(EntryDir),
  os:compose_path(EntryDir, 'CONTENTS', ContentsFile),
  setup_call_cleanup(
    open(ContentsFile, write, SC),
    ( format(SC, 'obj ~w ~w 12345~n', [OwnedFile, OwnedMd5]),
      format(SC, 'obj /usr/bin/vpkg-missing 00000000000000000000000000000000 12345~n', []),
      format(SC, 'dir ~w~n', [SubDir]),
      format(SC, 'sym /usr/bin/vpkg-link -> /usr/bin/vpkg-target 12345~n', []),
      format(SC, 'sym /usr/sbin/vpkg-short -> targetonly~n', []),
      format(SC, 'sym /bin/vpkg-malformed~n', [])
    ),
    close(SC)),
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  setup_call_cleanup(
    ( unittest:accept_stable_amd64,
      asserta(config:pkg_directory(PkgDir)),
      assertz(cache:ordered_entry(pkg, 'vcat/vpkg-1.0', vcat, vpkg, V1)),
      assertz(cache:ordered_entry(portage, 'vcat/vpkg-2.0', vcat, vpkg, V2)),
      assertz(cache:entry_metadata(portage, 'vcat/vpkg-2.0', keywords, stable(amd64))),
      assertz(cache:entry_metadata(portage, 'vcat/vpkg-2.0', rdepend,
        all_of_group([
          any_of_group([
            use_conditional_group(positive, u, portage://'vcat/vpkg-2.0',
              [package_dependency(run, no, vcat, vpkg, none, version_none, [], [])])
          ])
        ])))
    ),
    with_output_to(string(_),
      ( os:compose_path(TmpDir, 'scaff1', Scaff1),
        vdb:make_repository_dirs(vdb_mock_repo, Scaff1),
        vdb:create_repository_dirs(vdb_mock_repo, Scaff1),
        vdb:outdated(vcat, vpkg, pkg://'vcat/vpkg-1.0', portage://'vcat/vpkg-2.0'),
        vdb:print_contents('vcat/vpkg-1.0'),
        vdb:print_contents('vcat/nonexistent-1.0'),
        vdb:print_owner(OwnedFile),
        vdb:print_owner('owned.bin'),
        vdb:print_owner('/no/such/file'),
        vdb:format_size(2000000000, _),
        vdb:format_size(2000000, _),
        vdb:format_size(2000, _),
        vdb:format_size(20, _),
        vdb:print_size('vcat/vpkg-1.0'),
        vdb:verify_package('vcat/vpkg-1.0'),
        vdb:verify_package('vcat/nonexistent-1.0'),
        vdb:print_executables('vcat/vpkg-1.0'),
        vdb:print_executables('vcat/nonexistent-1.0'),
        vdb:resolve_vdb_entries('vcat/vpkg-1.0', ['vcat/vpkg-1.0']),
        vdb:resolve_vdb_entries('vcat/vpkg', ['vcat/vpkg-1.0']),
        vdb:resolve_vdb_entries('vpkg', ['vcat/vpkg-1.0']),
        vdb:reverse_deps(vcat, vpkg, [portage://'vcat/vpkg-2.0']),
        vdb:import_package(vcat, imported, '1.0'),
        vdb:import_package(vcat, imported, '1.0'),
        vdb:read_metadata_file('vcat/imported-1.0', 'SLOT', '0'),
        vdb:split_pv("my-pkg-1.2.3", 'my-pkg', '1.2.3'),
        vdb:split_pv("noversion", noversion, '0'),
        vdb:build_contents_index(OwnedSet),
        vdb:find_unmanaged(RootDir, OwnedSet, Unmanaged),
        memberchk(UnmanagedFile, Unmanaged),
        vdb:find_unmanaged(RootDir, OwnedSet, 0, [])
      )),
    ( retractall(config:pkg_directory(PkgDir)),
      retractall(cache:ordered_entry(pkg, 'vcat/vpkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(pkg, 'vcat/imported-1.0', _, _, _)),
      retractall(cache:ordered_entry(portage, 'vcat/vpkg-2.0', _, _, _)),
      retractall(cache:entry_metadata(portage, 'vcat/vpkg-2.0', _, _)),
      vdbtest_rm_rf(TmpDir)
    )).

test(upstream_module_full_coverage, [nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V9 = version([9999], '', 4, 0, [], 0, '9999'),
  setup_call_cleanup(
    ( assertz(cache:ordered_entry(portage, 'ucat/upkg-9999', ucat, upkg, V9)),
      assertz(cache:ordered_entry(portage, 'ucat/upkg-1.0',  ucat, upkg, V1)),
      assertz(cache:ordered_entry(portage, 'ucat/liveonly-9999', ucat, liveonly, V9)),
      assertz(config:repology_address('1.2.3.4'))
    ),
    with_output_to(string(_),
      ( upstream:repology_user_agent(_),
        upstream:normalize_project_name('gtk+', 'gtk'),
        upstream:repology_url('gtk+', URL),
        upstream:curl_resolve_opts(URL, ['--resolve', _]),
        retractall(config:repology_address(_)),
        upstream:curl_resolve_opts(URL, []),
        upstream:curl_exit_text(28, timeout),
        upstream:error_text(err, 'err'),
        % local_version (non-9999 and 9999-only fallback)
        upstream:local_version(ucat, upkg, '1.0'),
        upstream:local_version(ucat, liveonly, '9999'),
        % newest_version, gentoo_version, gentoo_status
        Pkgs = [json{repo: "gentoo", status: "outdated", version: "1.0"},
                json{repo: "arch",   status: "newest",   version: "2.0"}],
        upstream:newest_version(Pkgs, "2.0"),
        upstream:gentoo_version(Pkgs, "1.0"),
        upstream:gentoo_status(Pkgs, outdated),
        % print_result branches: equal, outdated, other
        upstream:print_result(ucat, upkg, '1.0', "1.0", newest),
        upstream:print_result(ucat, upkg, '1.0', "2.0", outdated),
        upstream:print_result(ucat, upkg, '1.0', "2.0", devel),
        % fetch_project & check_package branches via mocked httpfetch
        assertz(httpfetch:mock_response(curl, any, ok(Pkgs))),
        upstream:check_package(ucat, upkg),
        retractall(httpfetch:mock_response(_, _, _)),
        assertz(httpfetch:mock_response(curl, any, ok([]))),
        upstream:check_package(ucat, upkg),
        retractall(httpfetch:mock_response(_, _, _)),
        assertz(httpfetch:mock_response(curl, any, ok([json{repo: "other", status: "devel", version: "1.0"}]))),
        upstream:check_package(ucat, upkg),
        retractall(httpfetch:mock_response(_, _, _)),
        assertz(httpfetch:mock_response(curl, any, no_curl)),
        assertz(httpfetch:mock_response(http_open, any, ok(Pkgs))),
        upstream:fetch_project(upkg, packages(Pkgs)),
        retractall(httpfetch:mock_response(http_open, _, _)),
        assertz(httpfetch:mock_response(http_open, any, throw(error(http_status(u, 404), _)))),
        upstream:fetch_project(upkg, packages([])),
        retractall(httpfetch:mock_response(http_open, _, _)),
        assertz(httpfetch:mock_response(http_open, any, throw(net_err))),
        upstream:fetch_project(upkg, error(_)),
        retractall(httpfetch:mock_response(_, _, _)),
        assertz(httpfetch:mock_response(curl, any, throw(boom))),
        upstream:fetch_project(upkg, error(_)),
        retractall(httpfetch:mock_response(_, _, _)),
        assertz(httpfetch:mock_response(curl, any, error('unreachable'))),
        upstream:check(['ucat/upkg', 'nonexistent/pkg']),
        upstream:check_packages([])
      )),
    ( retractall(httpfetch:mock_response(_, _, _)),
      retractall(config:repology_address(_)),
      retractall(cache:ordered_entry(portage, 'ucat/upkg-9999', _, _, _)),
      retractall(cache:ordered_entry(portage, 'ucat/upkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(portage, 'ucat/liveonly-9999', _, _, _))
    )).

:- end_tests(vdb_and_upstream_full_coverage).

