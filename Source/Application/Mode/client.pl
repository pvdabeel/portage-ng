/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLIENT
Lightweight client for the portage-ng Pengine server. Delegates query
evaluation and dependency resolution to a remote server, avoiding the
need to load the full knowledge base locally. The server keeps its cache
indexed for fast queries and supports concurrent plan computation across
multiple threads.

Communication uses SSL-encrypted HTTP with digest authentication,
enabling secure remote administration of one or more servers.

The client supplies local state (installed packages, USE flags, keywords,
etc.) while the server provides the repository knowledge base. The server
returns a dependency plan that the client can print or execute.
*/

:- module(client, []).

% =============================================================================
%  CLIENT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Declare remote predicates
% -----------------------------------------------------------------------------

%! client:remote_predicate_template(?Predicate)
%
% Predicates whose full clause set is shipped to the remote Pengines sandbox.
% This is a list of predicates that are declared as remote in the server.
% The client will ship these predicates to the server and the server will
% evaluate them in its Pengines sandbox.

% Global USE, keywords, flags
client:remote_predicate_template(preference:local_use(_)).
client:remote_predicate_template(preference:local_env_use(_)).
client:remote_predicate_template(preference:local_accept_keywords(_)).
client:remote_predicate_template(preference:local_flag(_)).

% Per-package USE overrides (/etc/portage/package.use + profile)
client:remote_predicate_template(preference:local_userconfig_use(_,_,_,_)).
client:remote_predicate_template(preference:local_userconfig_use_versioned(_,_,_)).
client:remote_predicate_template(preference:local_profile_use_soft(_,_,_)).
client:remote_predicate_template(preference:local_profile_use_masked(_,_)).
client:remote_predicate_template(preference:local_profile_use_forced(_,_)).

% Package masking (profiles + /etc/portage/package.mask)
% Stored as local_masked(Id, Repo) — entry id first for indexing.
client:remote_predicate_template(preference:local_masked(_,_)).

% License acceptance
client:remote_predicate_template(preference:local_accepted_license(_)).
client:remote_predicate_template(preference:local_denied_license(_)).
client:remote_predicate_template(preference:local_license_group_raw(_,_)).

% Profile USE display markers
client:remote_predicate_template(preference:local_profile_masked_use_flag(_)).
client:remote_predicate_template(preference:local_profile_forced_use_flag(_)).

% World entries and named sets (file-backed, loaded during preference:init)
client:remote_predicate_template(preference:local_world_entry(_)).
client:remote_predicate_template(preference:local_set(_,_)).

% Installed state is NOT shipped per-RPC: the client uploads its VDB once
% via --import-vdb (see client:import_vdb/2 below); the server registers it
% as a per-client repository (pkg@<clienthost>) and the prover selects it
% through knowledgebase:vdb_repository/1. Only the repository name and the
% import stamp travel with each RPC (remote_predicate_instance below).


%! client:remote_predicate_instance(?Predicate)
%
% Predicates whose ground instances (matching facts) are shipped individually.

client:remote_predicate_instance(console:printing_style(_)).
client:remote_predicate_instance(console:printing_tty_size(_,_)).
client:remote_predicate_instance(preference:local_accept_license_wildcard).
client:remote_predicate_instance(preference:use_expand_env(_,_)).
client:remote_predicate_instance(config:use_expand_hidden(_)).
client:remote_predicate_instance(preference:keyword_selection_mode(_)).

% Per-client VDB import state (set after a successful --import-vdb; see
% client:ensure_vdb_state/1). The server-side accessor
% knowledgebase:vdb_repository/1 consults these in the Pengines sandbox.
client:remote_predicate_instance(client:vdb_repository(_)).
client:remote_predicate_instance(client:vdb_import_stamp(_)).


% -----------------------------------------------------------------------------
%  RPC execution
% -----------------------------------------------------------------------------

%! client:rpc_execute(Host,Port,Cmd)
%
% Use pengine_rpc to remotely call a sandboxed predicate in a Pengines sandbox.
% Use to run computationally expensive procedures on a server but retrieve the
% result in Prolog Term locally.
%
% Predicates declared as remote_predicate/1 will be injected in the remote
% remote Pengines sandbox

client:rpc_execute(Hostname,Port,Cmd) :-
  format(atom(URL), 'https://~w:~d', [Hostname,Port]),
  config:certificate('cacert.pem',CaCert),
  % Client certificate is identified by the *local* hostname, not the remote
  % server host we are connecting to.
  config:hostname(LocalHostname),
  config:certificate(LocalHostname,'client-cert.pem',ClientCert),
  config:certificate(LocalHostname,'client-key.pem',ClientKey),
  config:certificate_password(client,Pass),
  config:digest_password(User,Digestpwd),
  interface:require_digest_password,
  config:server_chunk(ChunkSize),
  client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
  client:maybe_auto_import_vdb(Hostname, Port),
  client:ensure_vdb_state(Hostname),
  findall(Template,(remote_predicate_template(Template)),Templates),
  findall(Instance,
          (remote_predicate_instance(Local:Instance),
           call(Local:Instance)),
          Context),
  pengine_rpc(URL,Cmd,
              [ host(Hostname),
                authorization(digest(User,Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass),
                chunk(ChunkSize),
                src_predicates(Templates),
                src_list(Context)
              ]).


%! client:rpc_execute(Host,Port,Command,Output)
%
% Same as rpc_execute/3 but captures output to Terminal in in Output string.

client:rpc_execute(Hostname,Port,Cmd,Output) :-
  rpc_execute(Hostname,Port,
              streams:with_output_to(string(Output),
                                     Cmd,
                                    [capture([user_output,user_error]),
                                     color(true)])).


%! client:rpc_execute(Host,Port,Command,Output,Srclist)
%
% Same as rpc_execute/4 but pushes a list of predicates to remote server

client:rpc_execute(Hostname,Port,Cmd,Output,Srclist) :-
  rpc_execute(Hostname,Port,
              streams:with_output_to(string(Output),
                                     Cmd,
                                     [src_list(Srclist),
                                      capture([user_output,user_error]),
                                      color(true)])).


% -----------------------------------------------------------------------------
%  Streaming output of remote execution
% -----------------------------------------------------------------------------

%! client:execute_remotely(Host,Port,Page)
%
% Triggers a pre-defined action remotely. E.g. syncing a repository.
% Output is streamed over https in realtime. Actions are sent as POST
% requests: the server only accepts POST on its state-mutating and
% expensive endpoints (/sync, /save, /load, /clear, /graph, /prove).

client:execute_remotely(Hostname,Port,Page) :-
    format(atom(URL), 'https://~w:~d~w', [Hostname,Port, Page]),
    config:certificate('cacert.pem',CaCert),
    % Client certificate is identified by the *local* hostname, not the remote
    % server host we are connecting to.
    config:hostname(LocalHostname),
    config:certificate(LocalHostname,'client-cert.pem',ClientCert),
    config:certificate(LocalHostname,'client-key.pem',ClientKey),
    config:certificate_password(client,Pass),
    config:digest_password(User,Digestpwd),
    interface:require_digest_password,
    client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
    http:http_open(URL, In,
              [ host(Hostname),
		            authorization(digest(User,Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass),
                post(atom('')),
                chunked
              ]),
    set_stream(In, buffer(false)),
    call_cleanup(
        client:stream_flush_cr(In),
        close(In)
    ).

client:stream_flush_cr(Stream) :-
    catch(get_char(Stream, Char),
          error(io_error(read, _), _),
          Char = end_of_file),
    ( Char == end_of_file -> true
    ; put_char(Char),
      flush_output,
      client:stream_flush_cr(Stream)
    ).


% -----------------------------------------------------------------------------
% TLS helper predicates
% -----------------------------------------------------------------------------

% Fail with a clear message if TLS material is missing.
% We keep certificate generation out of runtime: use `make certs HOST=<hostname>`.
client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey) :-
  interface:require_tls_files(client, LocalHostname, CaCert, ClientCert, ClientKey).


% -----------------------------------------------------------------------------
% VDB import - client-side state
% -----------------------------------------------------------------------------

% Import state for the server we are talking to, loaded lazily from the
% stamp file (Knowledge/vdbimport.pl) by ensure_vdb_state/1. When set, the
% matching remote_predicate_instance declarations ship the repository name
% and stamp into the Pengines sandbox with every RPC.
:- dynamic client:vdb_state_loaded/1.
:- dynamic client:vdb_repository/1.
:- dynamic client:vdb_import_stamp/1.
% Per-process latch: the auto-import freshness check ran for this server.
:- dynamic client:vdb_auto_checked/1.


%! client:maybe_auto_import_vdb(+Server, +Port) is det.
%
% Automatic VDB import (config:client_auto_import_vdb/1): before the first
% RPC of this process to Server, (re-)import the local VDB when no import
% record exists or the local VDB changed since the last import. A failed
% auto-import degrades to a warning - the command proceeds and the server
% warns loudly that the plan reflects its own installed set.

client:maybe_auto_import_vdb(Server, Port) :-
  ( client:vdb_auto_checked(Server) ->
      true
  ;   assertz(client:vdb_auto_checked(Server)),
      ( config:client_auto_import_vdb(true),
        client:vdb_import_needed(Server, Port) ->
          ( catch(client:import_vdb(Server, Port), _, fail) ->
              true
          ;   message:warning(['Automatic VDB import failed - continuing; ',
                               'this plan may reflect the server\'s ',
                               'installed packages.'])
          )
      ;   true
      )
  ).


%! client:vdb_import_needed(+Server, +Port) is semidet.
%
% True when no matching import exists on the server, or the local VDB changed.

client:vdb_import_needed(Server, Port) :-
  ( catch(client:stored_vdb_import(Server, Repo, Stamp, Time), _, fail),
    catch(client:remote_vdb_status(Server, Port,
                                   vdb_status(current, Repo, Stamp)), _, fail)
  ->
      ( client:local_vdb_mtime(MTime) -> MTime > Time ; true )
  ;   true
  ).


%! client:local_vdb_mtime(-MTime) is semidet.
%
% Most recent modification time over the local VDB root and its
% (category) subdirectories.

client:local_vdb_mtime(MTime) :-
  client:local_pkg_directory(Root),
  exists_directory(Root),
  time_file(Root, RootT),
  findall(T,
          ( directory_files(Root, Entries),
            member(E, Entries),
            E \== '.',
            E \== '..',
            os:compose_path(Root, E, Path),
            exists_directory(Path),
            catch(time_file(Path, T), _, fail) ),
          Ts),
  max_list([RootT|Ts], MTime).


%! client:ensure_vdb_state(+Server) is det.
%
% Load the persisted VDB import record for Server (if any) into the
% dynamic vdb_repository/1 and vdb_import_stamp/1 facts. Memoized per
% server; a no-op when no import has been performed.

client:ensure_vdb_state(Server) :-
  ( client:vdb_state_loaded(Server) ->
      true
  ;   client:reset_vdb_state,
      ( catch(client:stored_vdb_import(Server, Repo, Stamp, _), _, fail) ->
          assertz(client:vdb_repository(Repo)),
          assertz(client:vdb_import_stamp(Stamp))
      ;   true
      ),
      assertz(client:vdb_state_loaded(Server))
  ).


%! client:reset_vdb_state is det.
%
% Clear the in-memory VDB import state (forces a reload from the stamp
% file on the next RPC).

client:reset_vdb_state :-
  retractall(client:vdb_state_loaded(_)),
  retractall(client:vdb_repository(_)),
  retractall(client:vdb_import_stamp(_)).


%! client:vdb_import_file(-File) is det.
%
% Path of the persisted VDB import stamp file.

client:vdb_import_file(File) :-
  config:state_dir(Dir),
  os:compose_path(Dir, 'Knowledge/vdbimport.pl', File).


%! client:stored_vdb_import(+Server, -Repo, -Stamp, -Time) is semidet.
%
% Read the persisted import record for Server from the stamp file.

client:stored_vdb_import(Server, Repo, Stamp, Time) :-
  client:vdb_import_file(File),
  exists_file(File),
  client:read_file_terms(File, Terms),
  memberchk(vdb_import(Server, Repo, Stamp, Time), Terms).


%! client:save_vdb_import_record(+Server, +Repo, +Stamp) is det.
%
% Persist the import record for Server, keeping records for other servers.

client:save_vdb_import_record(Server, Repo, Stamp) :-
  client:vdb_import_file(File),
  get_time(Now),
  findall(vdb_import(S, R, St, T),
          ( catch(client:stored_vdb_import(S, R, St, T), _, fail),
            S \== Server ),
          Others),
  setup_call_cleanup(
    open(File, write, Out),
    forall(member(Term, [vdb_import(Server, Repo, Stamp, Now)|Others]),
           format(Out, '~q.~n', [Term])),
    close(Out)),
  filesex:chmod(File, 0o600).


%! client:read_file_terms(+File, -Terms) is det.
%
% Read all Prolog terms from File.

client:read_file_terms(File, Terms) :-
  setup_call_cleanup(
    open(File, read, In),
    client:read_stream_terms(In, Terms),
    close(In)).

client:read_stream_terms(In, Terms) :-
  read_term(In, T, []),
  ( T == end_of_file ->
      Terms = []
  ;   Terms = [T|Rest],
      client:read_stream_terms(In, Rest)
  ).


% -----------------------------------------------------------------------------
% VDB import - parse local VDB and upload to the server
% -----------------------------------------------------------------------------

%! client:import_vdb(+Hostname, +Port) is det.
%
% Implements --import-vdb (issue #78): parse the local VDB into cache:
% facts using the standard repository sync path, serialize them as a
% Prolog term stream, and POST them to the server's /import-vdb endpoint.
% On success the server registers the facts as repository pkg@<localhost>
% and subsequent prove RPCs resolve installed state against it.

client:import_vdb(Hostname, Port) :-
  client:ensure_vdb_import_modules,
  client:local_pkg_directory(Location),
  message:header(['Importing local VDB (', Location, ') into server ', Hostname]),
  nl,
  client:sync_local_vdb(Location),
  config:hostname(LocalHostname),
  client:vdb_payload(LocalHostname, Stamp, Payload),
  client:post_remotely(Hostname, Port, '/import-vdb', Payload, Output),
  ( client:parse_vdb_import_response(Output,
                                     vdb_import_ok(Repo, Stamp, EntryCount, MdCount)) ->
      client:save_vdb_import_record(Hostname, Repo, Stamp),
      client:reset_vdb_state,
      message:inform(['Installed-state repository registered as ', Repo,
                      ' (', EntryCount, ' entries, ', MdCount,
                      ' metadata facts)'])
  ;   write(Output),
      message:failure(['VDB import failed - see server response above.'])
  ).


%! client:parse_vdb_import_response(+Text, -Term) is semidet.

client:parse_vdb_import_response(Text, Term) :-
  term_string(Term0, Text, [syntax_errors(error)]),
  Term0 = vdb_import_ok(Repo, Stamp, Entries, Metadata),
  atom(Repo),
  ground(Stamp),
  integer(Entries),
  integer(Metadata),
  Term = Term0.


%! client:ensure_vdb_import_modules is det.
%
% Client mode does not load the knowledge/pipeline module groups; load the
% lean set needed to parse a VDB into cache: facts on demand.

client:ensure_vdb_import_modules :-
  user:ensure_loaded(portage('Source/Knowledge/cache.pl')),
  user:ensure_loaded(portage('Source/Knowledge/repository.pl')),
  user:ensure_loaded(portage('Source/Pipeline/parser.pl')).


%! client:local_pkg_directory(-Location) is det.
%
% Determine the local VDB root. Client mode never consults the host config
% file (main(client) skips config:systemconfig/1 loading because the config
% registers repositories with the kb, which is a proxy in client mode), so
% read the config:pkg_directory/1 fact straight from the file. Falls back
% to /var/db/pkg.

client:local_pkg_directory(Location) :-
  ( current_predicate(config:pkg_directory/1),
    catch(config:pkg_directory(Location), _, fail) ->
      true
  ;   config:systemconfig(File),
      exists_file(File),
      catch(client:read_file_terms(File, Terms), _, fail),
      memberchk((config:pkg_directory(Location)), Terms) ->
      true
  ;   Location = '/var/db/pkg',
      exists_directory(Location) ->
      true
  ;   message:failure(['Cannot determine local VDB location: add ',
                       'config:pkg_directory/1 to your host config.'])
  ).


%! client:sync_local_vdb(+Location) is det.
%
% Create (once) a local `pkg` repository instance over the VDB directory
% and run the standard VDB kb sync, asserting cache: facts locally.

client:sync_local_vdb(Location) :-
  ( catch(pkg:get_type('vdb'), _, fail) ->
      true
  ;   pkg:newinstance(repository),
      pkg:init(Location, '', '', 'local', 'vdb')
  ),
  pkg:sync(kb).


%! client:vdb_payload(+LocalHostname, -Stamp, -Payload) is det.
%
% Serialize the locally synced `pkg` cache facts into the /import-vdb wire
% format: a header (version, hostname, stamp), one oe/4 term per ordered
% entry (order is significant: version-descending), one md/3 term per
% metadata fact, and a trailer carrying the fact counts.

client:vdb_payload(LocalHostname, Stamp, Payload) :-
  findall(oe(Id, C, N, V), cache:ordered_entry(pkg, Id, C, N, V), Entries),
  findall(md(Id, K, V), cache:entry_metadata(pkg, Id, K, V), Metadata),
  length(Entries, EntryCount),
  ( EntryCount > 0 ->
      true
  ;   message:failure(['Local VDB parse produced no entries - nothing to import.'])
  ),
  length(Metadata, MdCount),
  variant_sha1(Entries-Metadata, Sha),
  Stamp = stamp(EntryCount, Sha),
  with_output_to(string(Payload),
    ( client:emit_vdb_term(vdb_import_v1),
      client:emit_vdb_term(hostname(LocalHostname)),
      client:emit_vdb_term(stamp(Stamp)),
      forall(member(E, Entries), client:emit_vdb_term(E)),
      forall(member(M, Metadata), client:emit_vdb_term(M)),
      client:emit_vdb_term(end_of_vdb_import(EntryCount, MdCount))
    )).

client:emit_vdb_term(T) :-
  write_canonical(T),
  write('.\n').


%! client:post_remotely(+Hostname, +Port, +Page, +Payload, -Output) is det.
%
% Like execute_remotely/3 but POSTs Payload and captures the (chunked)
% response body into Output for inspection by the caller.

client:post_remotely(Hostname, Port, Page, Payload, Output) :-
  format(atom(URL), 'https://~w:~d~w', [Hostname, Port, Page]),
  config:certificate('cacert.pem', CaCert),
  config:hostname(LocalHostname),
  config:certificate(LocalHostname, 'client-cert.pem', ClientCert),
  config:certificate(LocalHostname, 'client-key.pem', ClientKey),
  config:certificate_password(client, Pass),
  config:digest_password(User, Digestpwd),
  interface:require_digest_password,
  client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
  setup_call_cleanup(
    http:http_open(URL, In,
              [ host(Hostname),
                authorization(digest(User, Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass),
                post(string(Payload))
              ]),
    read_string(In, _, Output),
    close(In)).


%! client:remote_vdb_status(+Hostname, +Port, -Status) is semidet.
%
% Query the authenticated server-side import state for this certificate.

client:remote_vdb_status(Hostname, Port, Status) :-
  format(atom(URL), 'https://~w:~d/vdb-status', [Hostname, Port]),
  config:certificate('cacert.pem', CaCert),
  config:hostname(LocalHostname),
  config:certificate(LocalHostname, 'client-cert.pem', ClientCert),
  config:certificate(LocalHostname, 'client-key.pem', ClientKey),
  config:certificate_password(client, Pass),
  config:digest_password(User, Digestpwd),
  interface:require_digest_password,
  client:require_tls_files(LocalHostname, CaCert, ClientCert, ClientKey),
  setup_call_cleanup(
    http:http_open(URL, In,
              [ host(Hostname),
                authorization(digest(User, Digestpwd)),
                cacerts([file(CaCert)]),
                certificate_file(ClientCert),
                key_file(ClientKey),
                password(Pass)
              ]),
    read_string(In, _, Text),
    close(In)),
  term_string(Status0, Text, [syntax_errors(error)]),
  ( Status0 = vdb_status(missing)
  ; Status0 = vdb_status(current, Repo, Stamp),
    atom(Repo),
    ground(Stamp)
  ),
  Status = Status0.