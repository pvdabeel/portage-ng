/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> ROUTES
HTTP paths shared by the server handlers and the knowledge-base proxy.

A name is the stable identifier. The server registers one handler per
endpoint, and the client asks for that path instead of a literal copied
into the caller.
*/

:- module(routes, []).

% =============================================================================
% ROUTES declarations
% =============================================================================

%! routes:endpoint(?Name, ?Path, ?Method) is nondet.
%
% Method is get or post. sync_named is the prefix under which a single
% repository is synced (/sync/<name>).

routes:endpoint(root, '/', get).
routes:endpoint(sync, '/sync', post).
routes:endpoint(sync_named, '/sync/', post).
routes:endpoint(save, '/save', post).
routes:endpoint(load, '/load', post).
routes:endpoint(clear, '/clear', post).
routes:endpoint(graph, '/graph', post).
routes:endpoint(graph_emerge, '/graph_emerge', post).
routes:endpoint(graph_pmerge, '/graph_pmerge', post).
routes:endpoint(prove, '/prove', post).
routes:endpoint(import_vdb, '/import-vdb', post).
routes:endpoint(vdb_status, '/vdb-status', get).
routes:endpoint(info, '/info', get).


%! routes:handler_options(+Name, -Options) is det.
%
% Extra http_handler/3 options for Name. sync_named is a prefix so
% /sync/<repository> reaches the same dispatcher.

routes:handler_options(Name, Options) :-
  routes:handler_option(Name, Options),
  !.
routes:handler_options(_, []).

routes:handler_option(sync, [time_limit(infinite)]).
routes:handler_option(sync_named, [prefix, time_limit(infinite)]).
routes:handler_option(graph, [time_limit(infinite)]).
routes:handler_option(graph_emerge, [time_limit(infinite)]).
routes:handler_option(graph_pmerge, [time_limit(infinite)]).
routes:handler_option(prove, [time_limit(infinite)]).
routes:handler_option(import_vdb, [time_limit(300)]).
