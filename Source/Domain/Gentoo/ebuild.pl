/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> EBUILD
This file currently contains some syntactic sugar for common knowledgebase
queries.
*/

:- module(ebuild, []).

% =============================================================================
%  EBUILD declarations
% =============================================================================

%! ebuild:invoke(cache,+Location,+Entry,-Stream)
%
% Sources the ebuild and its eclasses via ebuild-depend.sh and exports the
% metadata variables relevant to create a repository cache entry.

ebuild:invoke(cache,Location,Entry,Stream) :-
  split_string(Entry,"/","/",[Category,Package]),
  eapi:packageversion(Package,Name,version(_,_,_,_,_,_,_)),
  atomic_list_concat([Location,'/',Category,"/",Name,"/",Package,'.ebuild'],Ebuild),
  process_set_method(vfork),
  process_create(portage('Source/Domain/Gentoo/Ebuild/ebuild-depend.sh'),
    ['--single',Ebuild,Location],
    [stdout(pipe(Stream)),stderr(null)]),
  !.


% -----------------------------------------------------------------------------
%  Batch metadata extraction
% -----------------------------------------------------------------------------

%! ebuild:entry_fields(+Location, +Entry, -Fields)
%
% Eight protocol fields for one repository entry: Category, PN, PV, PR,
% PVR, PF, P, EBUILD. PR is empty at revision 0 and otherwise `-rN`.

ebuild:entry_fields(Location, Entry, Fields) :-
  split_string(Entry, "/", "/", [Category, Package]),
  eapi:packageversion(Package, Name, version(_,_,_,_,_,Rev,Version)),
  ( Rev =:= 0 -> Revision = '' ; format(atom(Revision), '-r~d', [Rev]) ),
  string_concat(UpstreamVersion, Revision, Version),
  string_concat(UpstreamPackage, Revision, Package),
  atomic_list_concat([Location,'/',Category,"/",Name,"/",Package,'.ebuild'], Ebuild),
  Fields = [Category, Name, UpstreamVersion, Revision, Version, Package,
            UpstreamPackage, Ebuild].


%! ebuild:nul_free_field(+Field) is semidet.
%
% A protocol field is text and contains no NUL byte.

ebuild:nul_free_field(Field) :-
  ( atom(Field)
  -> atom_codes(Field, Codes)
  ; string(Field)
  -> string_codes(Field, Codes)
  ),
  \+ memberchk(0, Codes).


%! ebuild:write_nul_record(+Stream, +Fields) is semidet.
%
% Write each field followed by a NUL delimiter. Every field is checked
% before the first byte, so a rejected record cannot split a frame.

ebuild:write_nul_record(Stream, Fields) :-
  maplist(ebuild:nul_free_field, Fields),
  ebuild:emit_nul_record(Stream, Fields).


%! ebuild:emit_nul_record(+Stream, +Fields) is det.
%
% Emit an already-validated NUL-delimited record.

ebuild:emit_nul_record(_, []).
ebuild:emit_nul_record(Stream, [Field|Rest]) :-
  format(Stream, '~w', [Field]),
  put_code(Stream, 0),
  ebuild:emit_nul_record(Stream, Rest).


%! ebuild:write_entry_frame(+Stream, +Fields) is semidet.
%
% Write one `entry` request. Fields is the eight-element list from
% ebuild:entry_fields/3, or the same layout built by md5cache.

ebuild:write_entry_frame(Stream, Fields) :-
  Fields = [_, _, _, _, _, _, _, _],
  ebuild:write_nul_record(Stream, [entry|Fields]).


%! ebuild:write_quit_frame(+Stream) is det.
%
% Write the coprocess shutdown request.

ebuild:write_quit_frame(Stream) :-
  ebuild:write_nul_record(Stream, [quit]).


%! ebuild:invoke_batch(+Location, +Entries, -Results)
%
% Process a list of Entries in a single ebuild-depend.sh --batch invocation.
% Returns a list of Entry-Contents pairs, where Contents is a list of
% KEY=VALUE strings (same format as reader:invoke output).

ebuild:invoke_batch(Location, Entries, Results) :-
  process_set_method(vfork),
  process_create(
    portage('Source/Domain/Gentoo/Ebuild/ebuild-depend.sh'),
    ['--batch', Location],
    [stdin(pipe(In)), stdout(pipe(Out)), stderr(null)]),
  set_stream(In, encoding(utf8)),
  set_stream(Out, encoding(utf8)),
  ebuild:write_batch_descriptors(In, Location, Entries),
  close(In),
  ebuild:read_batch_results(Out, Entries, Results),
  close(Out).


%! ebuild:write_batch_descriptors(+Stream, +Location, +Entries)
%
% Write one NUL-framed entry request per repository entry.

ebuild:write_batch_descriptors(_, _, []).
ebuild:write_batch_descriptors(In, Location, [Entry|Rest]) :-
  ( ebuild:entry_fields(Location, Entry, Fields),
    ebuild:write_entry_frame(In, Fields)
  -> flush_output(In)
  ; true
  ),
  ebuild:write_batch_descriptors(In, Location, Rest).


%! ebuild:read_batch_results(+Stream, +Entries, -Results)
%
% Read KEY=VALUE blocks delimited by ---END--- from stdout pipe.
% Returns Entry-Contents pairs.

ebuild:read_batch_results(_, [], []).
ebuild:read_batch_results(Out, [Entry|RestEntries], [Entry-Contents|RestResults]) :-
  ebuild:read_until_delimiter(Out, Contents),
  ebuild:read_batch_results(Out, RestEntries, RestResults).
ebuild:read_batch_results(_, _, []).


%! ebuild:read_until_delimiter(+Stream, -Lines)
%
% Read lines until ---END--- or end of stream.

ebuild:read_until_delimiter(Stream, Lines) :-
  read_line_to_string(Stream, Line),
  ( Line == end_of_file -> Lines = []
  ; Line == "---END---" -> Lines = []
  ; sub_string(Line, 0, 10, _, "---ERROR--") -> Lines = []
  ; Lines = [Line|Rest],
    ebuild:read_until_delimiter(Stream, Rest)
  ).


% -----------------------------------------------------------------------------
%  Coprocess (persistent server mode)
% -----------------------------------------------------------------------------

:- dynamic ebuild:coprocess_state/3.

%! ebuild:coprocess_start(+Location)
%
% Start ebuild-depend.sh in --server mode as a persistent coprocess.
% The process stays alive and accepts requests on stdin.

ebuild:coprocess_start(Location) :-
  ( ebuild:coprocess_state(Location, _, _)
  -> true
  ; process_set_method(vfork),
    process_create(
      portage('Source/Domain/Gentoo/Ebuild/ebuild-depend.sh'),
      ['--server', Location],
      [stdin(pipe(In)), stdout(pipe(Out)), stderr(null), process(Pid)]),
    set_stream(In, encoding(utf8)),
    set_stream(Out, encoding(utf8)),
    set_stream(In, buffer(full)),
    assert(ebuild:coprocess_state(Location, In-Out, Pid))
  ).


%! ebuild:coprocess_stop(+Location)
%
% Send quit to the server and close the coprocess.

ebuild:coprocess_stop(Location) :-
  ( retract(ebuild:coprocess_state(Location, In-Out, Pid))
  -> ( catch((ebuild:write_quit_frame(In), flush_output(In)), _, true),
       catch(close(In), _, true),
       catch(close(Out), _, true),
       catch(process_wait(Pid, _), _, true)
     )
  ; true
  ).


%! ebuild:coprocess_invoke(+Location, +Entry, -Contents)
%
% Send one ebuild request to the coprocess and read the result.

ebuild:coprocess_invoke(Location, Entry, Contents) :-
  ebuild:coprocess_state(Location, In-Out, _),
  ebuild:entry_fields(Location, Entry, Fields),
  ebuild:write_entry_frame(In, Fields),
  flush_output(In),
  ebuild:read_until_delimiter(Out, Contents).


% The predicates below use query:search/2 directly (not kb:query) so the
% compile-time macros inline the cache lookups (issue #57). They are called
% from the printer/builder per-ebuild loops, which only run where the KB is
% local (standalone, or server-side in client mode).

%! ebuild:distfile_scope(-Scope)
%
% The manifest scope of the distfiles a run fetches and displays:
% `preference` (the SRC_URI reachable under the active USE flags), or
% `all` under `--fetch-all-uri`.

ebuild:distfile_scope(Scope) :-
  ( preference:flag(fetchall)
  -> Scope = all
  ;  Scope = preference
  ).


%! ebuild:download_size(+Scope,+Repository://+Entry,-T)
%
% Retrieve total download size for all files corresponding to a given Entry

ebuild:download_size(Scope,Repository://Entry,T) :-
  aggregate_all(sum(S),F,query:search(manifest(Scope,_,F,S),Repository://Entry),T),!.

ebuild:download_size(_,_://_,0) :- !.


%! ebuild:is_virtual(+Repository://+Entry)
%
% True if an entry is a virtual

ebuild:is_virtual(Repository://Entry) :-
  query:search(category('virtual'),Repository://Entry).


%! ebuild:is_live(+Repository://+Entry)
%
% True if an entry is live

ebuild:is_live(Repository://Entry) :-
  query:search(properties(live),Repository://Entry).


%! ebuild:is_interactive(+Repository://+Entry)
%
% True if an entry is interactive

ebuild:is_interactive(Repository://Entry) :-
  query:search(properties(interactive),Repository://Entry).