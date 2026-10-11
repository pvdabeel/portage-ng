/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> INFO
Ebuild metadata and system overview display.

Handles printing of individual ebuild metadata (print_entry, print_metadata),
package dependency and USE flag details, and the system overview shown by
--version and --info without a target.

HTML index rendering has moved to Source/Printer/index.pl (module index).
*/

:- module(info, []).

% =============================================================================
%  INFO declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  System overview
% -----------------------------------------------------------------------------

%! info:print_repositories is det.
%
% Prints the registered repositories with name, git version and path in
% aligned columns.

info:print_repositories :-
  findall(Name-Loc-Ver,
    ( context:instances(repository, Name),
      Name:get_location(Loc),
      interface:repo_git_version(Loc, Ver)
    ),
    Repos),
  ( Repos == []
  -> true
  ;  aggregate_all(max(L), (member(N-_-_, Repos), atom_length(N, L)), MaxN),
     aggregate_all(max(L), (member(_-_-V, Repos), atom_length(V, L)), MaxV),
     Col1 is MaxN + 4,
     Col2 is Col1 + MaxV + 2,
     forall(member(N-Loc-V, Repos),
       format('  ~w~t~*|~w~t~*|~w~n', [N, Col1, V, Col2, Loc])
     )
  ).


%! info:print_system is det.
%
% Prints the system overview shown by --info without a target: version,
% profile, hostname, installation directory, terminal size, repositories
% and the world set.

info:print_system :-
  interface:version(Version),
  current_prolog_flag(version, PrologVer),
  config:hostname(Hostname),
  ( config:gentoo_profile(Profile) -> true ; Profile = unknown ),
  nl,
  format('portage-ng ~w (SWI-Prolog ~w, ~w)~n', [Version, PrologVer, Profile]),
  format('================================================================~n'),
  format('System hostname: ~w~n', [Hostname]),
  ( config:installation_dir(Dir)
  -> format('Install dir:     ~w~n', [Dir])
  ;  true
  ),
  ( console:printing_tty_size(H, W)
  -> format('Terminal size:   ~wx~w~n', [W, H])
  ;  format('Terminal size:   (not a TTY)~n')
  ),
  nl,
  format('Repositories:~n'),
  info:print_repositories,
  nl,
  format('World set:~n'),
  ( catch(forall(world::entry(E), format('  ~w~n', [E])), _, fail)
  -> true
  ;  format('  (not loaded)~n')
  ).


% -----------------------------------------------------------------------------
%  Entry points
% -----------------------------------------------------------------------------

%! info:print_entry(+Repository://Entry)
%
% Prints information on a repository entry.

info:print_entry(Repository://Entry) :-
  !,
  nl,
  message:header(['Printing information for: ',Repository://Entry]),
  info:print_metadata(Repository://Entry).


% -----------------------------------------------------------------------------
%  Metadata dispatch
% -----------------------------------------------------------------------------

%! info:print_metadata(+Repository://Entry)
%
% Iterates over the printable metadata list and prints each item.

info:print_metadata(Repository://Entry) :-
  config:printable_metadata(List),
  forall(member(I,List),info:print_metadata_item(I,Repository://Entry)).


%! info:print_metadata_item(+Item, +Repository://Entry)
%
% Prints a single metadata item (or separator).

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


% -----------------------------------------------------------------------------
%  Metadata item details
% -----------------------------------------------------------------------------

%! info:print_metadata_item_details(+Item, +Values)
%
% Prints the detail list for a metadata item, or "[not set]" if empty.

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


% -----------------------------------------------------------------------------
%  Detail: EAPI version
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(eapi,Prefix,version(_,_,_,_,_,_,Value)) :-
  write(Prefix),
  write(Value).


% -----------------------------------------------------------------------------
%  Detail: source URI
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(src_uri,Prefix,uri(_,_,Value)) :-
  !,
  write(Prefix),
  write(Value).


% -----------------------------------------------------------------------------
%  Detail: dependency groups (USE conditional, any_of, all_of, exactly_one_of,
%          at_most_one_of)
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Detail: package dependencies
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,none,version_none,Slot,Use)) :-
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


% -----------------------------------------------------------------------------
%  Detail: grouped package dependencies
% -----------------------------------------------------------------------------

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


% -----------------------------------------------------------------------------
%  Detail: IUSE flags
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(iuse,Prefix,plus(U)) :-
  !,
  write(Prefix),
  message:color(green),
  write('+'),
  write(U),
  message:color(normal).

info:print_metadata_item_detail(iuse,Prefix,minus(U)) :-
  !,
  write(Prefix),
  message:color(red),
  write('-'),
  write(U),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Detail: required_use flags
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(required_use,Prefix,required(U)) :-
  !,
  write(Prefix),
  write(U).

info:print_metadata_item_detail(required_use,Prefix,blocking(U)) :-
  !,
  write(Prefix),
  write('!'),
  write(U).


% -----------------------------------------------------------------------------
%  Detail: catch-all
% -----------------------------------------------------------------------------

info:print_metadata_item_detail(_,Prefix,Value) :-
  write(Prefix),
  write(Value).


% -----------------------------------------------------------------------------
%  Dependency annotation helpers
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Blockers
% -----------------------------------------------------------------------------

%! info:print_blocking(+Type)
%
% Prints blocker annotation for a dependency (no, weak, strong).

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


% -----------------------------------------------------------------------------
%  Comparators
% -----------------------------------------------------------------------------

%! info:print_comparator(+Op)
%
% Prints the symbol for a comparator operator.

info:print_comparator(Op) :-
  eapi:comparator_symbol(Op, Sym),
  write(Sym).


% -----------------------------------------------------------------------------
%  USE dependencies
% -----------------------------------------------------------------------------

%! info:print_use_dependencies(+Use)
%
% Prints the USE dependency list for a package dependency.

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


%! info:print_use_dependency(+Dep)
%
% Prints a single USE dependency term.

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


%! info:print_use_default(+Default)
%
% Prints the default indicator for a USE dependency.

info:print_use_default(positive) :-
  write('(+)').

info:print_use_default(negative) :-
  write('(-)').

info:print_use_default(none) :- !.


% -----------------------------------------------------------------------------
%  Slot restrictions
% -----------------------------------------------------------------------------

%! info:print_slot_restriction(+SlotSpec)
%
% Prints the slot restriction suffix for a package dependency.

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