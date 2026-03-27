/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> NEWS
GLEP 42 news item display.

Reads and renders news items from a portage repository's metadata/news/
directory. Each news item follows the GLEP 42 format: a directory named
after the item containing a .en.txt file with RFC 2822-style headers
(Title, Author, Posted, etc.) followed by a blank line and the body text.
*/

:- module(news, []).

% =============================================================================
%  NEWS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Entry point
% -----------------------------------------------------------------------------

%! news:check is det.
%
% Reads and displays GLEP 42 news items from the portage tree's
% metadata/news/ directory.

news:check :-
  ( kb:repository(portage),
    portage:get_location(Location)
  -> atomic_list_concat([Location, '/metadata/news'], NewsDir),
     ( exists_directory(NewsDir)
     -> news:display_items(NewsDir)
     ;  message:inform('No news directory found.')
     )
  ;  message:inform('No portage repository registered.')
  ).


% -----------------------------------------------------------------------------
%  Display news items
% -----------------------------------------------------------------------------

%! news:display_items(+NewsDir) is det.
%
% Enumerates news item directories and prints each item's title,
% date and content.

news:display_items(NewsDir) :-
  directory_files(NewsDir, Entries0),
  include(\=('.'), Entries0, Entries1),
  include(\=('..'), Entries1, Entries2),
  sort(Entries2, Sorted),
  reverse(Sorted, Items),
  ( Items == []
  -> message:inform('No news items found.')
  ;  length(Items, N),
     message:topheader(['Found ', N, ' news items']),
     nl,
     forall(member(Item, Items),
       news:display_single(NewsDir, Item)
     )
  ).


%! news:display_single(+NewsDir, +ItemName) is det.
%
% Reads and displays a single GLEP 42 news item. Looks for a
% .en.txt file in the item directory.

news:display_single(NewsDir, ItemName) :-
  atomic_list_concat([NewsDir, '/', ItemName], ItemDir),
  ( exists_directory(ItemDir)
  -> atomic_list_concat([ItemDir, '/', ItemName, '.en.txt'], TxtFile),
     ( exists_file(TxtFile)
     -> news:print_file(TxtFile)
     ;  true
     )
  ;  true
  ).


% -----------------------------------------------------------------------------
%  News file parsing and rendering
% -----------------------------------------------------------------------------

%! news:print_file(+File) is det.
%
% Parses a GLEP 42 news file (RFC 2822 headers + body) and prints
% the title and posted date, followed by body text.

news:print_file(File) :-
  read_file_to_string(File, Content, []),
  split_string(Content, "\n", "", Lines),
  news:extract_header(Lines, "Title", Title),
  news:extract_header(Lines, "Posted", Posted),
  message:color(green),
  format(' * '),
  message:color(normal),
  message:style(bold),
  format('~s', [Title]),
  message:style(normal),
  message:color(darkgray),
  format('  (~s)', [Posted]),
  message:color(normal),
  nl,
  news:print_body(Lines),
  nl.


%! news:extract_header(+Lines, +Key, -Value) is det.
%
% Extracts the value of a header line "Key: Value" from the news file.

news:extract_header([], _Key, "unknown") :- !.

news:extract_header([Line|Rest], Key, Value) :-
  ( string_concat(Key, ": ", Prefix),
    string_concat(Prefix, V, Line)
  -> Value = V
  ;  news:extract_header(Rest, Key, Value)
  ).


%! news:print_body(+Lines) is det.
%
% Prints the body of a news item (everything after the first blank line
% following the headers).

news:print_body(Lines) :-
  news:skip_headers(Lines, Body),
  forall(member(L, Body),
    ( message:color(darkgray),
      format('   '),
      message:color(normal),
      format('~s~n', [L])
    )).


%! news:skip_headers(+Lines, -Body) is det.
%
% Skips RFC 2822 header lines until the first blank line, returning
% the remaining body lines.

news:skip_headers([], []).
news:skip_headers([""|Rest], Rest) :- !.
news:skip_headers([_|Rest], Body) :-
  news:skip_headers(Rest, Body).