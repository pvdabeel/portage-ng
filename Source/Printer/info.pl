/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INFO
Ebuild metadata display and index rendering.

Handles printing of individual ebuild metadata (print_entry, print_metadata),
package dependency and USE flag details, and HTML-style index pages
(print_index).
*/

:- module(info, []).

% -----------------------------------------------------------------------------
%  INDEX printing
% -----------------------------------------------------------------------------

%! info:print_index(Generator)
%
% Print an index for a given Generator (repository:category, repository:package)

info:print_index(Type,Title,TitleHtml,Generator,Template,Stylesheet) :-
  print_index_header(Title,TitleHtml,Stylesheet),
  forall(Generator,print_index_element(Type,Template)),
  print_index_footer.


%! info:print_index_header(Name,Stylesheet)
%
% Print an index header with a given Name and Stylesheet

info:print_index_header(Title,TitleHtml,Stylesheet) :-
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


%! info:print_index_footer
%
% Print an index footer

info:print_index_footer :-
  writeln('</ul>'),
  writeln('</body>'),
  writeln('</html>').


%! info:print_index_element(E,Relpath)
%
% Print an element in the index

info:print_index_element(repository,E) :-
  write('<li class="element"><a href="./'),
  write(E),
  write('/index.html">'),
  write(E),
  write('</a></li>'),
  nl.

info:print_index_element(category,E) :-
  write('<li class="element"><a href="./'),
  write(E),
  write('.html">'),
  write(E),
  write('</a></li>'),
  nl.

info:print_index_element(package,[E,V]) :-
  write('<li class="element"><a href="./'),
  write(E),write('-'),write(V),
  write('.svg">'),
  write(V),
  write('</a></li>'),
  nl.


% -----------------------------------------------------------------------------
%  Ebuild INFO printing
% -----------------------------------------------------------------------------

%! info:print_entry(Repository://Entry)
%
% Prints information an a repository entry

info:print_entry(Repository://Entry) :-
  !,
  nl,
  message:header(['Printing information for: ',Repository://Entry]),
  info:print_metadata(Repository://Entry).


%! info:print_metadata(Repository://Entry)
%
% Prints information an a repository entry metadata

info:print_metadata(Repository://Entry) :-
  config:printable_metadata(List),
  forall(member(I,List),info:print_metadata_item(I,Repository://Entry)).


%! info:print_metadata_item(Item,Repository://Entry)
%
% Prints specific metadata item

info:print_metadata_item(blank,_) :-
  !,
  nl.

info:print_metadata_item(hl,_) :-
  !,
  message:hl.

info:print_metadata_item(Item,Repository://Entry) :-
  message:style(bold),
  message:color(darkgray),
  write(Item),write(' : '),
  message:style(normal),
  nl,
  Query =.. [Item,Value],
  findall(Value,kb:query(Query,Repository://Entry),Values),
  info:print_metadata_item_details(Item,Values).


%! info:print_metadata_item_details(Item,List)
%
% Prints specific metadata item detail list

info:print_metadata_item_details(_Item,[]) :-
  !,
  Prefix = '   ',
  message:style(italic),
  message:color(lightgray),
  write(Prefix),
  write('[not set]'),
  message:style(normal),
  message:color(normal),
  nl.

info:print_metadata_item_details(Item,List) :-
  Prefix = '   ',
  forall(member(Value,List),(info:print_metadata_item_detail(Item,Prefix,Value),nl)).


%! info:print_metadata_item_detail(Item,Prefix,Value)
%
% Prints specific metadata item detail

info:print_metadata_item_detail(eapi,Prefix,version(_,_,_,_,_,_,Value)) :-
  write(Prefix),
  write(Value).

info:print_metadata_item_detail(src_uri,Prefix,uri(_,_,Value)) :-
  !,
  write(Prefix),
  write(Value).

info:print_metadata_item_detail(Item,Prefix,use_conditional_group(Type,Use,_Id,Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,use),
  write(' '),
  (Type == negative
   -> (message:color(red),write('-'))
   ;   message:color(green)),
  write(Use),
  message:color(lightgray),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),info:print_metadata_item_detail(Item,NewPrefix,V))).

info:print_metadata_item_detail(Item,Prefix,any_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,any),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),info:print_metadata_item_detail(Item,NewPrefix,V))).

info:print_metadata_item_detail(Item,Prefix,all_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,all),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),info:print_metadata_item_detail(Item,NewPrefix,V))).

info:print_metadata_item_detail(Item,Prefix,exactly_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),info:print_metadata_item_detail(Item,NewPrefix,V))).

info:print_metadata_item_detail(Item,Prefix,at_most_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write('[one] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),info:print_metadata_item_detail(Item,NewPrefix,V))).

info:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,none,[[],_,_,_,_],Slot,Use)) :-
  !,
  write(Prefix),
  info:print_blocking(Blocking),
  write(Category),
  write('/'),
  write(Name),
  info:print_slot_restriction(Slot),
  info:print_use_dependencies(Use).

info:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,Comparator,version(_,_,_,_,_,_,Version),Slot,Use)) :-
  !,
  write(Prefix),
  info:print_blocking(Blocking),
  info:print_comparator(Comparator),
  write(Category),
  write('/'),
  write(Name),
  write('-'),
  write(Version),
  info:print_slot_restriction(Slot),
  info:print_use_dependencies(Use).

info:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_C,_N,List)) :-
  !,
  forall(member(V,List),(
    info:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

info:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_X,_C,_N,List)) :-
  !,
  forall(member(V,List),(
    info:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

info:print_metadata_item_detail(_,Prefix,Value) :-
  write(Prefix),
  write(Value).


%! info:print_blocking(Type)
%
% Prints metadata for a blocking dependency

info:print_blocking(no) :- !.

info:print_blocking(weak) :-
  message:color(lightgray),
  message:style(italic),
  write('[weak block] '),
  message:style(normal),
  message:color(normal).

info:print_blocking(strong) :-
  message:color(lightgray),
  message:style(italic),
  write('[strong block] '),
  message:style(normal),
  message:color(normal).


%! info:print_comparator(Type)
%
% Prints short version of comparator

info:print_comparator(greaterequal) :- write('>=').
info:print_comparator(greater)      :- write('>').
info:print_comparator(smallerequal) :- write('<=').
info:print_comparator(smaller)      :- write('<').
info:print_comparator(equal)        :- write('=').
info:print_comparator(tilde)        :- write('~').
info:print_comparator(none)         :- write('').


%! info:print_use_dependencies(Use)
%
% Prints use dependencies

info:print_use_dependencies([]) :- !.

info:print_use_dependencies(Use) :-
  ( var(Use) ; \+ is_list(Use) ),
  !.
info:print_use_dependencies(Use) :-
  message:color(cyan),
  write(' [ '),
  forall(member(D,Use),(info:print_use_dependency(D),write(' '))),
  write(']'),
  message:color(normal).


%! info:print_use_dependency(Use)
%
% Print use dependency

info:print_use_dependency(use(inverse(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D).

info:print_use_dependency(use(equal(U),D)) :-
  write(U),
  print_use_default(D),
  write('=').

info:print_use_dependency(use(optdisable(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D),
  write('?').

info:print_use_dependency(use(optenable(U),D)) :-
  write(U),
  print_use_default(D),
  write('?').

info:print_use_dependency(use(disable(U),D)) :-
  write('-'),
  write(U),
  print_use_default(D).

info:print_use_dependency(use(enable(U),D)) :-
  write(U),
  print_use_default(D).

info:print_use_dependency(Other) :-
  write(Other).


%! info:print_use_default(D)
%
% Prints use default for a use dependency

info:print_use_default(positive) :-
  write('(+)').

info:print_use_default(negative) :-
  write('(-)').

info:print_use_default(none) :- !.


%! info:print_slot_restriction(S)
%
% Prints slot restriction for a package dependency

info:print_slot_restriction([]) :- !.

info:print_slot_restriction([any_different_slot]) :-
  message:color(lightgray),
  write(':*'),
  message:color(normal).

info:print_slot_restriction([any_same_slot]) :-
  message:color(lightgray),
  write(':='),
  message:color(normal).

info:print_slot_restriction([slot(Slot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  message:color(normal).

info:print_slot_restriction([slot(Slot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('='),
  message:color(normal).

info:print_slot_restriction([slot(Slot),subslot(Subslot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  message:color(normal).

info:print_slot_restriction([slot(Slot),subslot(Subslot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  write('='),
  message:color(normal).
