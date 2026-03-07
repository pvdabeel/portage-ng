/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INDEX
HTML index page rendering for repository, category, and package listings.
*/

:- module(index, []).


% -----------------------------------------------------------------------------
%  INDEX printing
% -----------------------------------------------------------------------------

%! index:print_index(+Type, +Title, +TitleHtml, +Generator, +Template, +Stylesheet)
%
% Print an index for a given Generator (repository:category, repository:package)

index:print_index(Type,Title,TitleHtml,Generator,Template,Stylesheet) :-
  index:print_index_header(Title,TitleHtml,Stylesheet),
  forall(Generator, index:print_index_element(Type,Template)),
  index:print_index_footer.


%! index:print_index_header(+Title, +TitleHtml, +Stylesheet)
%
% Print an index header with a given Title and Stylesheet

index:print_index_header(Title,TitleHtml,Stylesheet) :-
  writeln('<?xml version="1.0" encoding="UTF-8" ?>'),
  writeln('<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">'),
  writeln('<html xmlns="http://www.w3.org/1999/xhtml">'),
  writeln('<head>'),
  writeln('<meta http-equiv="Content-Type" content="application/xml+xhtml; charset=UTF-8"/>'),
  write('<title>'),write(Title),write('</title>'),nl,
  write('<link rel="stylesheet" href="'),write(Stylesheet),write('"/>'),
  writeln('</head>'),
  writeln('<body>'),
  write('<h1>'),write(TitleHtml),write('</h1>'),nl,
  writeln('<ul>').


%! index:print_index_footer
%
% Print an index footer

index:print_index_footer :-
  writeln('</ul>'),
  writeln('</body>'),
  writeln('</html>').


%! index:print_index_element(+Type, +Element)
%
% Print an element in the index

index:print_index_element(repository,E) :-
  write('<li class="element"><a href="./'),
  write(E),
  write('/index.html">'),
  write(E),
  write('</a></li>'),
  nl.

index:print_index_element(category,E) :-
  write('<li class="element"><a href="./'),
  write(E),
  write('.html">'),
  write(E),
  write('</a></li>'),
  nl.

index:print_index_element(package,[E,V]) :-
  write('<li class="element"><a href="./'),
  write(E),write('-'),write(V),
  write('.svg">'),
  write(V),
  write('</a></li>'),
  nl.
