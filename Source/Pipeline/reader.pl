/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> READER
The reader reads lines from a file.
Input:  A full path to a file
Output: A list of strings, each string represents a line.

It also provides the one reading of Gentoo-style configuration files
(profiles, /etc/portage, layout.conf): `#` comments dropped, whitespace
normalized, blank lines removed (reader:config_lines/2).
*/

:- module(reader, []).

% =============================================================================
%  READER declarations
% =============================================================================

%! reader:invoke(+File, -Contents)
%
% File: The full path of the cache.
%
% Contents: A list of strings, each string represents a line

reader:invoke(Stream, Contents) :-
  is_stream(Stream), !,
  reader:read_lines_to_strings(Stream, Contents),
  close(Stream).

reader:invoke(File, Contents) :-
  exists_file(File), !,
  ( reader:decompressor(File, Program, Args)
  -> reader:invoke_compressed(Program, Args, Contents)
  ;  open(File, read, Stream, [lock(none)]),
     reader:read_lines_to_strings(Stream, Contents),
     close(Stream)
  ).

reader:invoke(_, []) :-
  !.


%! reader:decompressor(+File, -Program, -Args) is semidet.
%
% External decompressor for a compressed file, by suffix: gzip,
% bzip2, xz and lzma (xz reads lzma streams). Used for GLEP 61
% compressed Manifest files; any compressed file handed to the reader
% is decompressed transparently. Fails for uncompressed files.

reader:decompressor(File, path(gzip), ['-dc', File]) :-
  file_name_extension(_, gz, File), !.
reader:decompressor(File, path(bzip2), ['-dc', File]) :-
  file_name_extension(_, bz2, File), !.
reader:decompressor(File, path(xz), ['-dc', File]) :-
  file_name_extension(_, xz, File), !.
reader:decompressor(File, path(xz), ['-dc', File]) :-
  file_name_extension(_, lzma, File), !.


%! reader:invoke_compressed(+Program, +Args, -Contents) is det.
%
% Run Program with Args and read its standard output as lines. A
% missing or failing decompressor yields [] (the reader's usual
% unreadable-file answer).

reader:invoke_compressed(Program, Args, Contents) :-
  ( catch(process_create(Program, Args,
                         [stdout(pipe(Out)), stderr(null), process(Pid)]),
          _, fail)
  -> setup_call_cleanup(true,
                        reader:read_lines_to_strings(Out, Contents),
                        close(Out)),
     process_wait(Pid, _)
  ;  Contents = []
  ),
  !.


%! reader:read_lines_to_strings(+Stream, -Lines)
%
% Given a stream, reads all lines from the stream and returns them as a list of 
% strings

reader:read_lines_to_strings(Stream, Lines) :-
  read_line_to_string(Stream, L),
  ( L == end_of_file
    ->  Lines = []
    ;   Lines = [L|Rest],
        reader:read_lines_to_strings(Stream, Rest) ).

%! reader:read_lines_to_codes(+Stream, -Lines)
%
% Retained for compatibility with code expecting character codes
% Given a stream, reads all lines from the stream and returns as a list of codes

reader:read_lines_to_codes(Stream, Lines) :-
  read_line_to_codes(Stream, L),
  ( L == end_of_file
    ->  Lines = []
    ;   Lines = [L|Rest],
        reader:read_lines_to_codes(Stream, Rest)
    ).


%! reader:config_lines(+File, -Lines)
%
% The meaningful lines of a Gentoo-style configuration file, as strings in
% file order: `#` comments are dropped, whitespace is normalized and blank
% lines are removed. A missing or unreadable file yields [].

reader:config_lines(File, Lines) :-
  catch(read_file_to_string(File, S, []), _, S = ""),
  reader:string_config_lines(S, Lines).


%! reader:string_config_lines(+String, -Lines)
%
% As reader:config_lines/2, for configuration content already in memory.

reader:string_config_lines(S, Lines) :-
  split_string(S, "\n", "\r", Raw),
  findall(L, ( member(R, Raw), reader:config_line(R, L), L \== "" ), Lines).


%! reader:config_line(+Raw, -Line)
%
% Normalize one configuration line: drop a `#` comment and collapse
% whitespace. Line is "" for blank and comment-only lines.

reader:config_line(Raw, Line) :-
  ( sub_string(Raw, Before, _, _, "#")
  -> sub_string(Raw, 0, Before, _, S0)
  ;  S0 = Raw
  ),
  normalize_space(string(Line), S0).


%! reader:test(+Repository)
%
% Predicate tests whether all cache entries belonging to a given repository
% instance can be read correctly.
%
% Repository: The repository instance from which to read all cache entries.

reader:test(Repository) :-
  time(forall(Repository:get_cache_file(E, C),
              (reader:invoke(C, _); (message:failure(E)))
            )),
  Repository:get_size(S), !,
  message:inform(['read ', S, ' ', Repository, ' entries.']).