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
