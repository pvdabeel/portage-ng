/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SERVER
Server sets up a portage-ng pengine server.

Client is very lightweight applicaton that processes interface requests and
calls the server for processing. This way we avoid having to load the entire
knowledge base into memory for every request. With secure authentication, this
also allows for remote administration of one or more servers.

The server maintains an accurate view on the knowledge base. The client can
provide predicates describing local state (e.g. the installed packages on
this operating system.

Client requires very little resources, server is multi-threaded and will
enable us to calculate plans very easily. Essentially the server returns a
plan to the client, which the client can then execute. (Think of the plan
as a Makefile).

*/

:- module(server, []).

% *******************
% SERVER declarations
% *******************


%! server:start_server
%
% Start a http server on the given port and listens for commands

server:start_server  :-
  config:server_port(Port),
  config:hostname(Hostname),
  config:certificate('cacert.pem',CaCert),
  config:certificate(Hostname,'server-cert.pem',ServerCert),
  config:certificate(Hostname,'server-key.pem',ServerKey),
  config:password(server,Pass),
  http:http_server( %(http_handler,% server:reply,
                   [ port(Port) ,
                     workers(120) ,
		     keep_alive_timeout(1),
                     ssl([ certificate_file(ServerCert),
                           key_file(ServerKey),
                           password(Pass),
                           peer_cert(true),
                           cacerts([file(CaCert)])
                         ])
                   ]).



%! server:reply(+Request)
%
% Root: Show available locations

server:reply(Request) :-
    memberchk(path('/'), Request),
    !,
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    format('<h1>Portage-ng remote interface</h1>', []),
    format('<ul>~n', []),
    format('  <li><a href="prove">Prove all latest ebuilds in knowledge base.</a>'),
    format('  <li><a href="sync">Sync server knowledge base.</a>'),
    format('  <li><a href="info">Returns server info.</a>'),
    format('  <li><a href="upload">Upload some data</a>'),
    format('  <li><a href="quit">Say bye bye</a>'),
    format('  <li><a href="otherwise">Otherwise, print request</a>'),
    format('</ul>~n', []),
    format('</html>~n', []).


%! server:reply(+Request)
%
% Quit: Explicitely close the connection

server:reply(Request) :-
    member(path('/quit'), Request),
    !,
    format('Connection: close~n', []),
    format('Content-type: text/html~n~n', []),
    format('Bye Bye~n').


%! server:upload(+Request)
%! serverupload_reply(+Request)
%
% Provide a form for uploading a KB QLF file, and deal with the resulting
% upload.

server:reply(Request) :-
    member(path('/upload'), Request),
    !,
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    format('<form action="/upload_reply" enctype="multipart/form-data" method="post">~n', []),
    format('<input type="file" name="datafile">'),
    format('<input type="submit" name="sent">'),
    format('</body>~n', []),
    format('</html>~n', []).

server:reply(Request) :-
    member(path('/upload_reply'), Request),
    !,
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    format('<pre>~n', []),
    write( req(Request) ), nl,
    http_read_data(Request, Data, []),
    write( data(Data) ), nl,
    format('</pre>'),
    format('</body>~n', []),
    format('</html>~n', []).


%! server:reply(+Request)
%
% Run a test prove run

server:reply(Request) :-
    member(path('/prove'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    current_output(S),
    set_stream(S,buffer(false)),
    %format('Content-type: text/html~n~n', []),
    %format('<html>~n', []),
    prover:test_latest(portage,parallel_verbose),
    %format('</html>~n', []).
    format('~n', []).


%! server:reply(+Request)
%
% Sync server repositories. Warning: needs locking

server:reply(Request) :-
    member(path('/sync'), Request),
    !,
    format('Transfer-encoding: chunked~n~n', []),
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    kb:sync,kb:save,
    format('</html>~n', []).


%! server:reply(+Request)
%
% Sync server repositories. Warning: needs locking

server:reply(Request) :-
    member(path('/info'), Request),
    !,
    config:hostname(Hostname),
    config:number_of_cpus(Cpu),
    format('Transfer-encoding: chunked~n~n', []),
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    format('Host ~w has ~w cpu cores available.~n', [Hostname, Cpu]),
    format('</html>~n', []).


server:reply(Request) :-
  http_handler(Request).

%! server:reply(+Request)
%
% Every other case: print the request.

server:reply(Request) :-
    format('Transfer-encoding: chunked~n~n', []),
    format('Content-type: text/html~n~n', []),
    format('<html>~n', []),
    format('<table border=1>~n'),
    server:print_request(Request),
    format('~n</table>~n'),
    format('</html>~n', []).



%! server:print_request(+Request)
%
% Print the request

server:print_request([]).
server:print_request([H|T]) :-
    H =.. [Name, Value],
    format('<tr><td>~w<td>~w~n', [Name, Value]),
    server:print_request(T).




