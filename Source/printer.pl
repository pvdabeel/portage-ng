/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PRINTER
The Printer takes a plan from the Planner and pretty prints it.
*/

:- module(printer, []).

% =============================================================================
%  PRINTER declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  PROVER state printing
% -----------------------------------------------------------------------------

printer:display_state([],_,_,_) :- !.
printer:display_state(Target, Proof, Model, Constraints) :-

    % prepare aguments

    ( Target = [ Current | Queue ]
      -> true
      ;  Current = Target, Queue = [] ),

    prover:proof_to_list(Proof,ProofList),
    prover:model_to_list(Model,ModelList),
    prover:constraints_to_list(Constraints,ConstraintList),

    message:hl,

    %tty_clear,

    % proving subtitle

    message:color(orange), message:style(bold),
    format('--- Proving ---~n'),
    message:color(normal), message:style(normal),
    format('  ~w~n~n', [Current]),

    % proving stack subtitle

    message:color(magenta), message:style(bold),
    format('--- Proving Stack (In Progress) ---~n'),
    message:color(normal), message:style(normal),
    ( ProofList == [] -> writeln('  (empty)') ;
      ( reverse(ProofList, Tmp),
        forall(member(rule(P,_), Tmp), format('  ~w~n', [P]))
      )
    ),
    nl,

    % to be proven queue subtitle

    message:color(cyan), message:style(bold),
    format('--- Proving Queue (To Do) ---~n'),
    message:color(normal), message:style(normal),
    ( Queue == [] -> writeln('  (empty)') ; forall(member(Q, Queue), format('  ~w~n', [Q])) ),
    nl,

    % model subtitle

    message:color(green), message:style(bold),
    format('--- Model (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ModelList  == [] -> writeln('  (empty)')
    ; forall(member(M, ModelList), ( format('  ~w~n', [M]) ))),
    nl,

    % constraints subtitle

    message:color(green), message:style(bold),
    format('--- Constraints (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ConstraintList  == [] -> writeln('  (empty)')
    ; forall(member(M, ConstraintList), ( format('  ~w~n', [M]) ))).

    %wait_for_input.


% Helper to wait for the user to press Enter.
printer:wait_for_input :-
    format('~nPress Enter to continue...'),
    get_char(_).


% -----------------------------------------------------------------------------
%  INDEX printing
% -----------------------------------------------------------------------------

%! printer:print_index(Generator)
%
% Print an index for a given Generator (repository:category, repository:package)

printer:print_index(Type,Title,TitleHtml,Generator,Template,Stylesheet) :-
  print_index_header(Title,TitleHtml,Stylesheet),
  forall(Generator,print_index_element(Type,Template)),
  print_index_footer.


%! printer:print_index_header(Name,Stylesheet)
%
% Print an index header with a given Name and Stylesheet

printer:print_index_header(Title,TitleHtml,Stylesheet) :-
  writeln('<?xml version=\"1.0\" encoding=\"UTF-8\" ?>'),
  writeln('<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Strict//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd\">'),
  writeln('<html xmlns=\"http://www.w3.org/1999/xhtml\">'),
  writeln('<head>'),
  writeln('<meta http-equiv=\"Content-Type\" content=\"application/xml+xhtml; charset=UTF-8\"/>'),
  write('<title>'),write(Title),write('</title>'),nl,
  write('<link rel=\"stylesheet\" href=\"'),write(Stylesheet),write('"/>'),
  writeln('</head>'),
  writeln('<body>'),
  write('<h1>'),write(TitleHtml),write('</h1>'),nl,
  writeln('<ul>').


%! printer:print_index_footer
%
% Print an index footer

printer:print_index_footer :-
  writeln('</ul>'),
  writeln('</body>'),
  writeln('</html>').


%! printer:print_index_element(E,Relpath)
%
% Print an element in the index

printer:print_index_element(repository,E) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),
  write('/index.html\">'),
  write(E),
  write('</a></li>'),
  nl.

printer:print_index_element(category,E) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),
  write('.html\">'),
  write(E),
  write('</a></li>'),
  nl.

printer:print_index_element(package,[E,V]) :-
  write('<li class=\"element\"><a href=\"./'),
  write(E),write('-'),write(V),
  write('.svg\">'),
  write(V),
  write('</a></li>'),
  nl.


% -----------------------------------------------------------------------------
%  Ebuild INFO printing
% -----------------------------------------------------------------------------

%! printer:print_entry(Repository://Entry)
%
% Prints information an a repository entry

printer:print_entry(Repository://Entry) :-
  !,
  nl,
  message:header(['Printing information for: ',Repository://Entry]),
  printer:print_metadata(Repository://Entry).


%! printer:print_metadata(Repository://Entry)
%
% Prints information an a repository entry metadata

printer:print_metadata(Repository://Entry) :-
  config:printable_metadata(List),
  forall(member(I,List),printer:print_metadata_item(I,Repository://Entry)).


%! printer:print_metadata_item(Item,Repository://Entry)
%
% Prints specific metadata item

printer:print_metadata_item(blank,_) :-
  !,
  nl.

printer:print_metadata_item(hl,_) :-
  !,
  message:hl.

printer:print_metadata_item(Item,Repository://Entry) :-
  message:style(bold),
  message:color(darkgray),
  write(Item),write(' : '),
  message:style(normal),
  nl,
  Query =.. [Item,Value],
  findall(Value,kb:query(Query,Repository://Entry),Values),
  printer:print_metadata_item_details(Item,Values).


%! printer:print_metadata_item_details(Item,List)
%
% Prints specific metadata item detail list

printer:print_metadata_item_details(_Item,[]) :-
  !,
  Prefix = '   ',
  message:style(italic),
  message:color(lightgray),
  write(Prefix),
  write('[not set]'),
  message:style(normal),
  message:color(normal),
  nl.

printer:print_metadata_item_details(Item,List) :-
  Prefix = '   ',
  forall(member(Value,List),(printer:print_metadata_item_detail(Item,Prefix,Value),nl)).


%! printer:print_metadata_item_detail(Item,Prefix,Value)
%
% Prints specific metadata item detail

printer:print_metadata_item_detail(eapi,Prefix,[_,_,_,Value]) :-
  write(Prefix),
  write(Value).

printer:print_metadata_item_detail(src_uri,Prefix,uri(_,_,Value)) :-
  !,
  write(Prefix),
  write(Value).

printer:print_metadata_item_detail(Item,Prefix,use_conditional_group(Type,Use,_Id,Values)) :-
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
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,any_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,any),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,all_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,all),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,exactly_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write(' '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,at_most_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:bubble(darkgray,one),
  write('[one] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,none,[[],_,_,_,_],Slot,Use)) :-
  !,
  write(Prefix),
  printer:print_blocking(Blocking),
  write(Category),
  write('/'),
  write(Name),
  printer:print_slot_restriction(Slot),
  printer:print_use_dependencies(Use).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,Blocking,Category,Name,Comparator,[_,_,_,Version],Slot,Use)) :-
  !,
  write(Prefix),
  printer:print_blocking(Blocking),
  printer:print_comparator(Comparator),
  write(Category),
  write('/'),
  write(Name),
  write('-'),
  write(Version),
  printer:print_slot_restriction(Slot),
  printer:print_use_dependencies(Use).

printer:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_C,_N,List)) :-
  !,
  forall(member(V,List),(
    printer:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

printer:print_metadata_item_detail(_,Prefix,grouped_package_dependency(_X,_C,_N,List)) :-
  !,
  forall(member(V,List),(
    printer:print_metadata_item_detail(_,Prefix,V),
    nl
  )).

printer:print_metadata_item_detail(_,Prefix,Value) :-
  write(Prefix),
  write(Value).


%! printer:print_blocking(Type)
%
% Prints metadata for a blocking dependency

printer:print_blocking(no) :- !.

printer:print_blocking(weak) :-
  message:color(lightgray),
  message:style(italic),
  write('[weak block] '),
  message:style(normal),
  message:color(normal).

printer:print_blocking(strong) :-
  message:color(lightgray),
  message:style(italic),
  write('[strong block] '),
  message:style(normal),
  message:color(normal).


%! printer:print_comparator(Type)
%
% Prints short version of comparator

printer:print_comparator(greaterequal) :- write('>=').
printer:print_comparator(greater)      :- write('>').
printer:print_comparator(smallerequal) :- write('<=').
printer:print_comparator(smaller)      :- write('>').
printer:print_comparator(equal)        :- write('=').
printer:print_comparator(tilde)        :- write('~').
printer:print_comparator(none)         :- write('').


%! printer:print_use_dependencies(Use)
%
% Prints use dependencies

printer:print_use_dependencies([]) :- !.

printer:print_use_dependencies(Use) :-
  message:color(cyan),
  write(' [ '),
  forall(member(D,Use),(printer:print_use_dependency(D),write(' '))),
  write(']'),
  message:color(normal).


%! printer:print_use_dependency(Use)
%
% Print use dependency

printer:print_use_dependency(use(inverse(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D).

printer:print_use_dependency(use(equal(U),D)) :-
  write(U),
  print_use_default(D),
  write('=').

printer:print_use_dependency(use(optdisable(U),D)) :-
  write('!'),
  write(U),
  print_use_default(D),
  write('?').

printer:print_use_dependency(use(optenable(U),D)) :-
  write(U),
  print_use_default(D),
  write('?').

printer:print_use_dependency(use(disable(U),D)) :-
  write('-'),
  write(U),
  print_use_default(D).

printer:print_use_dependency(use(enable(U),D)) :-
  write(U),
  print_use_default(D).


%! printer:print_use_default(D)
%
% Prints use default for a use dependency

printer:print_use_default(positive) :-
  write('(+)').

printer:print_use_default(negative) :-
  write('(-)').

printer:print_use_default(none) :- !.


%! printer:print_slot_restriction(S)
%
% Prints slot restriction for a package dependency

printer:print_slot_restriction([]) :- !.

printer:print_slot_restriction([any_different_slot]) :-
  message:color(lightgray),
  write(':*'),
  message:color(normal).

printer:print_slot_restriction([any_same_slot]) :-
  message:color(lightgray),
  write(':='),
  message:color(normal).

printer:print_slot_restriction([slot(Slot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('='),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),subslot(Subslot)]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  message:color(normal).

printer:print_slot_restriction([slot(Slot),subslot(Subslot),equal]) :-
  message:color(lightgray),
  write(':'),
  write(Slot),
  write('/'),
  write(Subslot),
  write('='),
  message:color(normal).


% -----------------------------------------------------------------------------
%  Plan printing
% -----------------------------------------------------------------------------

%! printer:printable_element(+Literal)
%
% Declares which Literals are printable

printer:printable_element(rule(uri(_,_,_),_)) :- !.
printer:printable_element(rule(uri(_),_)) :- !.
printer:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:run?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:download?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:install?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:reinstall?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:uninstall?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:update?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:upgrade?_,_)) :- !.
printer:printable_element(assumed(rule(_Repository://_Entry:_?_,_))) :- !.
printer:printable_element(rule(assumed(_Repository://_Entry:_?_,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):install?_,_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_):run?_,_))) :- !.
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):install?_,_))) :- !. % todo: phase out
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_,_):run?_,_))) :- !. % todo: phase out
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_):install?_,_))) :- !.
printer:printable_element(assumed(rule(grouped_package_dependency(_,_,_):run?_,_))) :- !.
printer:printable_element(rule(assumed(grouped_package_dependency(_,_,_):install?_),_)) :- !.
printer:printable_element(rule(assumed(grouped_package_dependency(_,_,_):run?_),_)) :- !.


% Uncomment if you want 'confirm' steps shown in the plan:
% printer:printable_element(rule(package_dependency(run,_,_,_,_,_,_,_),_)) :- !.


%! printer:element_weight(+Literal)
%
% Declares a weight for ordering elements of a step in a plan

printer:element_weight(assumed(_),                                      0) :- !. % assumed
printer:element_weight(rule(assumed(_),_),                              0) :- !. % assumed
printer:element_weight(rule(uri(_),_),                                  0) :- !. % provide
printer:element_weight(rule(uri(_,_,_),_),                              1) :- !. % fetch
printer:element_weight(rule(package_dependency(_,_,_,_,_,_,_,_),_),     1) :- !. % confirm
printer:element_weight(rule(_Repository://_Entry:verify?_,_),           2) :- !. % verify
printer:element_weight(rule(_Repository://_Entry:run?_,_),              3) :- !. % run
printer:element_weight(rule(_Repository://_Entry:download?_,_),         4) :- !. % download
printer:element_weight(rule(_Repository://_Entry:fetchonly?_,_),        5) :- !. % fetchonly
printer:element_weight(rule(_Repository://_Entry:install?_,_),          5) :- !. % install
printer:element_weight(rule(_Repository://_Entry:reinstall?_,_),        6) :- !. % reinstall
printer:element_weight(rule(_Repository://_Entry:uninstall?_,_),        6) :- !. % uninstall
printer:element_weight(rule(_Repository://_Entry:update?_,_),           6) :- !. % update
printer:element_weight(rule(_Repository://_Entry:upgrade?_,_),          6) :- !. % upgrade
printer:element_weight(_,                                               7) :- !. % everything else


%! printer:sort_by_weight(+Comparator,+Literal,+Literal)
%
% Sorts elements in a plan by weight

printer:sort_by_weight(C,L1,L2) :-
  printer:element_weight(L1,W1),
  printer:element_weight(L2,W2),
  compare(C,W1:L1,W2:L2).


%! printer:print_element(+Printable)
%
% Prints a printable Literal

printer:print_element(_,rule(package_dependency(run_post,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).



% ---------------------------------------------
% CASE: simple package, is a target of the plan
% ---------------------------------------------

printer:print_element(Target,rule(Repository://Entry:Action?{Context},_)) :-
  member(Repository://Entry:Action?_,Target),
  !,
  %message:color(cyan),
  message:bubble(green,Action),
  message:style(bold),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------
% CASE: simple package, is not a target of the plan
% -------------------------------------------------

printer:print_element(_,rule(Repository://Entry:Action?{Context},_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% --------------------------------------------------------------
% CASE: verify that packages that need to be running are running
% --------------------------------------------------------------

printer:print_element(_,rule(package_dependency(run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(24,Repository://Entry),
  message:color(normal).


% ----------------
% CASE: a download
% ----------------

printer:print_element(_,rule(uri(Protocol,Remote,_Local),_)) :-
  !,
  message:color(cyan),
  message:print('fetch'),
  message:color(green),
  message:column(24,Protocol://Remote),
  message:color(normal).

printer:print_element(_,rule(uri(Local),_)) :-
  !,
  message:color(cyan),
  message:print('provide'),
  message:color(green),
  message:column(24,Local),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency on a non-existent installed package
% ---------------------------------------------------------------

printer:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


printer:print_element(_,rule(assumed(package_dependency(install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (non-existent, assumed installed)'),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed dependency on a non-existent running package
% -------------------------------------------------------------

printer:print_element(_,rule(assumed(grouped_package_dependency(C,N,_Deps):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal).


printer:print_element(_,rule(assumed(package_dependency(run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal).


% ---------------------------------
% CASE: an assumed unmasked package
% ---------------------------------

printer:print_element(_,rule(assumed(Repository://Entry:unmask?{_Context}),_Body)) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (masked)'),
  message:color(normal).


% ----------------------------------
% CASE: an assumed installed package
% ----------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:install?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal).


% --------------------------------
% CASE: an assumed running package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:run?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed running) '),
  message:color(normal).


% --------------------------------
% CASE: an assumed fetched package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:fetchonly?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  message:column(24,Repository://Entry),
  message:print(' (assumed fetched) '),
  message:color(normal).


% -------------------------------------
% CASE: an assumed installed dependency
% -------------------------------------

printer:print_element(_,assumed(rule(package_dependency(install,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).


% -----------------------------------
% CASE: an assumed running dependency
% -----------------------------------

printer:print_element(_,assumed(rule(package_dependency(run,_,C,N,_,_,_,_):_Action?{_Context},_Body))) :-
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed circular dependency
% -------------------------------------------------------------

printer:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):install?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed installed) '),
  message:color(normal).

printer:print_element(_,assumed(rule(grouped_package_dependency(_X,C,N,_Deps):run?{_Context},_Body))) :-
  !,
  message:bubble(red,'verify'),
  message:color(red),
  atomic_list_concat([C,'/',N],P),
  message:column(24,P),
  message:print(' (assumed running) '),
  message:color(normal).


%! printer:print_config_prefix(+Word)
%
% prints the prefix for a config item

% -------------------------------
% CASE: Fancy build plan printing
% -------------------------------

printer:print_config_prefix(Word) :-
  config:printing_style('fancy'),!,
  nl,write('             │           '),
  message:color(darkgray),
  message:print('└─ '),
  message:print(Word),
  message:print(' ─┤ '),
  message:color(normal).

% -------------------------------
% CASE: Short build plan printing
% -------------------------------

printer:print_config_prefix(_Word) :-
  config:printing_style('short'),!,
  nl,write('             │           ').

% --------------------------------
% CASE: Column build plan printing
% --------------------------------

printer:print_config_prefix(file) :-
  config:printing_style('column'),!,
  message:column(104,' ').

printer:print_config_prefix(live) :-
  config:printing_style('column'),!,
  message:column(104,' ').

printer:print_config_prefix('conf') :-
  config:printing_style('column'), !,
  message:column(104,' ').


%! printer:print_config_prefix
%
% prints the prefix for a config item

printer:print_config_prefix :-
  config:printing_style('fancy'),!,
  nl,write('             │          '),
  message:color(darkgray),
  message:print('          │ '),
  message:color(normal).

printer:print_config_prefix :-
  config:printing_style('short'),!,
  nl,write('             │           ').

printer:print_config_prefix :-
  config:printing_style('column'),!,
  nl,write('             │ '),
  message:column(104,' ').


%! printer:print_config(+Repository://+Entry:+Action:+Context)
%
% Prints the configuration for a given repository entry (USE flags, USE expand, ...)

% ----------------------
% CASE: fetchonly action
% ----------------------

% iuse empty

printer:print_config(Repository://Entry:fetchonly?{_Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!.

% use flags to show - to rework: performance

printer:print_config(Repository://Entry:fetchonly?{Context}) :-
 !,
 findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (printer:print_config_prefix('conf'),	                  % Use flags not empty
    printer:print_config_item('use',Useflags,Assumed))).    % Use flags not empty



% ---------------------
% CASE: download action
% ---------------------

% live downloads

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  ebuild:is_live(Repository://Ebuild),!,
  printer:print_config_prefix('live'),
  printer:print_config_item('download','git repository','live').


% no downloads

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  \+(kb:query(manifest(preference,_,_,_),Repository://Ebuild)),!.


% at least one download

printer:print_config(Repository://Ebuild:download?{_Context}) :-
  !,
  findall([File,Size],kb:query(manifest(preference,_,File,Size),Repository://Ebuild),Downloads),
  sort(Downloads,[[FirstFile,FirstSize]|Rest]),
  printer:print_config_prefix('file'),
  printer:print_config_item('download',FirstFile,FirstSize),
  forall(member([RestFile,RestSize],Rest),
         (printer:print_config_prefix,
          printer:print_config_item('download',RestFile,RestSize))).


% --------------------
% CASE: Install action
% --------------------

% iuse empty

printer:print_config(Repository://Entry:install?{Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!,
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> (Slot \== [slot('0')] ->
        printer:print_config_prefix('conf'),
        printer:print_config_item('slot',Slot)
      ; true)
  ;  true).

% use flags to show

printer:print_config(Repository://Entry:install?{Context}) :-
  !,
  findall(Use,
         (member(Term,Context),
          (Term = required_use(Uses) ; Term = build_with_use(Uses)),
           member(assumed(Use),Uses)),
         Assumed),

  % Get regular USE flags (filtered, excluding USE_EXPAND)
  findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

  % Get all USE flags (including USE_EXPAND ones) for USE_EXPAND processing
  findall(Use, kb:query(iuse(Use, _Reason), Repository://Entry), AllUseFlags),

  % Separate regular USE flags from USE_EXPAND flags
  partition(printer:is_use_expand_flag, AllUseFlags, UseExpandFlags, _RegularUseFlags),

  % Group USE_EXPAND flags by expand key and reason
  findall([ExpandKey, ExpandFlags],
          printer:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry),
          UseExpandVariables),

  % Filter out empty USE_EXPAND variables
  include(printer:valid_use_expand, UseExpandVariables, ValidUseExpandVariables),

  % Check if a slot is present in the context
  (memberchk(slot(_,_,Slot):{Repository://Entry},Context)
  -> % Check if slot is relevant to print
     (Slot \== [slot('0')]
     -> % Case 1: Use flags and Expanded Use flags empty
         (Useflags == [], ValidUseExpandVariables == []
          -> % print just the slot
             printer:print_config_prefix('conf'),
             printer:print_config_item('slot',Slot)
          ;  % print algined configuration
           printer:print_config_prefix('conf'),
           printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot)
        )
     ; (Useflags == [], ValidUseExpandVariables == [] ;
          (printer:print_config_prefix('conf'),
           printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, []))))
  ;  (Useflags == [], ValidUseExpandVariables == [] ;
       (printer:print_config_prefix('conf'),
        printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, [])))),!.


% ----------------
% CASE: Run action
% ----------------

printer:print_config(_://_:run?{_Context}) :- !.


% -------------------
% CASE: Other actions
% -------------------

printer:print_config(_://_:_?_) :- !.



% Helper predicate: Check if a USE flag is a USE_EXPAND flag
printer:is_use_expand_flag(UseFlag) :-
  eapi:use_expand(ExpandKey),
  eapi:check_prefix_atom(ExpandKey, UseFlag).

% Helper predicate: Group USE_EXPAND flags by expand key
printer:group_use_expand_flags(UseExpandFlags, ExpandKey, ExpandFlags, Repository://Entry) :-
  eapi:use_expand(ExpandKey),
  \+ preference:use_expand_hidden(ExpandKey),
  findall(UseFlag,
          (member(UseFlag, UseExpandFlags),
           eapi:check_prefix_atom(ExpandKey, UseFlag)),
          MatchingFlags),
  MatchingFlags \== [],
  % Group by reason and extract suffix
  findall([Reason, Group],
          group_by(Reason, Suffix,
                   (member(UseFlag, MatchingFlags),
                    eapi:strip_prefix_atom(ExpandKey, UseFlag, Suffix),
                    kb:query(iuse(UseFlag, Reason), Repository://Entry)),
                   Group),
          ExpandFlags).

% Helper predicate: Check if USE_EXPAND variable is valid (not empty)
printer:valid_use_expand([_Key, Flags]) :-
  Flags \== [].



% Helper predicate: Collect flags for USE_EXPAND variables
printer:collect_expand_flags(Keyflags, AllFlags) :-
  (memberchk([negative:default,NegDefa],Keyflags);    NegDefa=[]),
  (memberchk([negative:ebuild,NegEbui],Keyflags);     NegEbui=[]),
  (memberchk([negative:preference,NegPref],Keyflags); NegPref=[]),
  (memberchk([positive:ebuild,PosEbui],Keyflags);     PosEbui=[]),
  (memberchk([positive:preference,PosPref],Keyflags); PosPref=[]),
  sort(PosPref, OPosPref),
  sort(PosEbui, OPosEbui),
  sort(NegPref, ONegPref),
  sort(NegEbui, ONegEbui),
  sort(NegDefa, ONegDefa),
  maplist(printer:to_flag_term(positive:preference, []), OPosPref, FlagsPosPref),
  maplist(printer:to_flag_term(positive:ebuild, []), OPosEbui, FlagsPosEbui),
  maplist(printer:to_flag_term(negative:preference, []), ONegPref, FlagsNegPref),
  maplist(printer:to_flag_term(negative:ebuild, []), ONegEbui, FlagsNegEbui),
  maplist(printer:to_flag_term(negative:default, []), ONegDefa, FlagsNegDefa),
  append([FlagsPosPref, FlagsPosEbui, FlagsNegPref, FlagsNegEbui, FlagsNegDefa], AllFlags).


% Helper predicate: Print configuration items with aligned equals signs
printer:print_config_items_aligned(Useflags, ValidUseExpandVariables, Assumed, Slot) :-

  % 1. First print USE flags with proper formatting and alignment
  printer:print_config_item_aligned('use', Useflags, Assumed),

  % 2. Second print USE_EXPAND variables with proper formatting and alignment
  (ValidUseExpandVariables == [] -> true ;
   forall(member([Key, Keyflags], ValidUseExpandVariables),
          (printer:print_config_prefix,
           printer:print_config_item_aligned(Key, Keyflags, [])))),

  % 3. Lastly print SLOT with proper formatting and alignment
  (Slot == [] -> true ;
   (printer:print_config_prefix,
    printer:print_config_item_aligned('slot', Slot, []))).



% Helper predicate: Collect all configuration items
printer:collect_config_items(Useflags, ValidUseExpandVariables, Assumed, Slot, ConfigItems) :-
  findall(Item, printer:collect_single_config_item(Useflags, ValidUseExpandVariables, Assumed, Slot, Item), ConfigItems).

% Helper predicate: Collect individual configuration items
printer:collect_single_config_item(Useflags, _, Assumed, _, config_item('use', Useflags, Assumed)) :-
  Useflags \== [].
printer:collect_single_config_item(_, ValidUseExpandVariables, _, _, config_item(Key, Keyflags, [])) :-
  member([Key, Keyflags], ValidUseExpandVariables).
printer:collect_single_config_item(_, _, _, Slot, config_item('slot', Slot, [])) :-
  Slot \== [].


% Helper predicate: Print aligned configuration items
printer:print_aligned_config_items([]).
printer:print_aligned_config_items([config_item(Key, Value, Assumed)|Rest]) :-
  printer:print_aligned_config_item(Key, Value, Assumed),
  printer:print_aligned_config_items(Rest).

% Helper predicate: Print a single aligned configuration item
printer:print_aligned_config_item(Key, Value, Assumed) :-
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  printer:print_config_value(Key, Value, Assumed),
  message:print('"').


% Helper predicate: Print Use flags
printer:print_config_item_aligned('use', List, Assumed) :-
  !,
  upcase_atom('use', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
	printer:collect_all_flags(List, Assumed, AllFlags),
        printer:print_flags_wrapped(AllFlags, StartCol, TermWidth)
      ),
      error(io_error(check, stream(_)), _),
      ( printer:collect_all_flags(List, Assumed, AllFlags),
        printer:print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').


printer:print_config_item_aligned('slot', Slot, _) :-
  !,
  upcase_atom('slot', KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  message:color(darkgray),
  printer:print_slot_value(Slot),
  message:color(normal),
  message:print('"').

printer:print_config_item_aligned(Key, Keyflags, _) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:bubble(darkgray,KeyU),
  message:print(' = "'),
  config:printing_tty_size(_, TermWidth),
  line_position(current_output, StartCol),
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_wrapped(AllFlags,StartCol,TermWidth),
  message:print('"').

% Helper predicate: Print configuration value based on type
printer:print_config_value('use', List, Assumed) :-
  !,
  printer:collect_all_flags(List, Assumed, AllFlags),
  printer:print_flags_unwrapped(AllFlags).
printer:print_config_value('slot', Slot, _) :-
  !,
  printer:print_slot_value(Slot).
printer:print_config_value(Key, Keyflags, _) :-
  eapi:use_expand(Key),
  !,
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_unwrapped(AllFlags).



%! printer:print_config_item(+Key,+Value)
%
% Prints a configuration item for a given repository entry

printer:print_config_item('download',File,'live') :-
  !,
  message:color(magenta),
  message:print_bytes('live'),
  message:color(normal),
  message:print(' '),
  message:print(File).

printer:print_config_item('download',File,Size) :-
  !,
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(File).

printer:print_config_item('use',List,Assumed) :- !,
  upcase_atom('use',KeyU),
  message:print(KeyU),
  message:print('="'),
  catch(
      ( config:printing_tty_size(_, TermWidth),
        line_position(current_output, StartCol),
        collect_all_flags(List, Assumed, AllFlags),
        print_flags_wrapped(AllFlags, StartCol, TermWidth, StartCol, 0)
      ),
      error(io_error(check, stream(_)), _),
      ( collect_all_flags(List, Assumed, AllFlags),
        print_flags_unwrapped(AllFlags)
      )
  ),
  message:print('"').

printer:print_config_item('slot',Slot) :- !,
  upcase_atom('slot',KeyS),
  message:bubble(darkgray,KeyS),
  message:print(' = "'),
  message:color(darkgray),
  printer:print_slot_value(Slot),
  message:color(normal),
  message:print('"').


% New print_config_item for USE_EXPAND variables
printer:print_config_item(Key, Keyflags) :-
  eapi:use_expand(Key),
  !,
  upcase_atom(Key, KeyU),
  message:print(KeyU),
  message:print('="'),
  printer:collect_expand_flags(Keyflags, AllFlags),
  printer:print_flags_unwrapped(AllFlags),
  message:print('"').


%! printer:print_slot_value(+Slot)
%
% Prints the slot value in a readable format

printer:print_slot_value([slot(Slot)]) :-
  !,
  message:print(Slot).

printer:print_slot_value([slot(Slot),subslot(Subslot)]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot).

printer:print_slot_value([slot(Slot),subslot(Subslot),equal]) :-
  !,
  message:print(Slot),
  message:print('/'),
  message:print(Subslot),
  message:print('=').

printer:print_slot_value([slot(Slot),equal]) :-
  !,
  message:print(Slot),
  message:print('=').

printer:print_slot_value(Slot) :-
  message:print(Slot).


%! printer:print_flags_wrapped(+AllFlags, +StartCol, +TermWidth, +IndentForWrap, +SpacesNeeded)
%
% Prints a list of flags wrapped to the terminal width.

printer:print_flags_wrapped([], _, _, _, _) :- !.
printer:print_flags_wrapped(AllFlags, StartCol, TermWidth) :-
    foldl(printer:print_one_flag_wrapped(StartCol,TermWidth),
          AllFlags,
          [StartCol, true],
          _).


%! printer:print_one_flag_wrapped(+TermWidth, +IndentForWrap, +SpacesNeeded, +FlagTerm, +StateIn, -StateOut)
%
% Prints a single flag wrapped to the terminal width.

printer:print_one_flag_wrapped(StartCol, TermWidth, flag(Type, Flag, Assumed), [ColIn, IsFirst], [ColOut, false]) :-
    printer:get_flag_length(Type, Flag, Assumed, FlagLen),
    (IsFirst -> SpaceLen = 0 ; SpaceLen = 1),
    (
        ( ColIn + SpaceLen + FlagLen > TermWidth )
    ->  % Wrap
        (
            printer:print_continuation_prefix(StartCol),      % go to next line, print prefix, jump to start position
            printer:print_use_flag(Type, Flag, Assumed),      % print flag
            ColOut is StartCol + FlagLen
        )
    ;   % No wrap
        (
            (IsFirst -> true ; write(' ')),
            printer:print_use_flag(Type, Flag, Assumed),
            ColOut is ColIn + SpaceLen + FlagLen
        )
    ).


%! printer:print_continuation_prefix(+IndentColumn)
%
% Prints the continuation prefix for wrapped flags.

printer:print_continuation_prefix(StartColumn) :-
    nl,

    ( config:printing_style('short')  ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );

    ( config:printing_style('column') ->
        write('             │ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    ( config:printing_style('fancy')  ->
        write('             │                    '),
        message:color(darkgray),
        write('│ '),
        NewStartColumn is StartColumn - 1,
        message:column(NewStartColumn,'')
    );
    true.


%! printer:collect_all_flags(+List, +Assumed, -AllFlags)
%
% Collects all flags from the list and assumed flags.

printer:collect_all_flags(List, Assumed, AllFlags) :-
    (memberchk([negative:default,NegDefa],List);    NegDefa=[]),
    (memberchk([negative:ebuild,NegEbui],List);     NegEbui=[]),
    (memberchk([negative:preference,NegPref],List); NegPref=[]),
    (memberchk([positive:ebuild,PosEbui],List);     PosEbui=[]),
    (memberchk([positive:preference,PosPref],List); PosPref=[]),
    sort(PosPref, OPosPref),
    sort(PosEbui, OPosEbui),
    sort(NegPref, ONegPref),
    sort(NegEbui, ONegEbui),
    sort(NegDefa, ONegDefa),
    maplist(to_flag_term(positive:preference, Assumed), OPosPref, FlagsPosPref),
    maplist(to_flag_term(positive:ebuild, Assumed), OPosEbui, FlagsPosEbui),
    maplist(to_flag_term(negative:preference, Assumed), ONegPref, FlagsNegPref),
    maplist(to_flag_term(negative:ebuild, Assumed), ONegEbui, FlagsNegEbui),
    maplist(to_flag_term(negative:default, Assumed), ONegDefa, FlagsNegDefa),
    append([FlagsPosPref, FlagsPosEbui, FlagsNegPref, FlagsNegEbui, FlagsNegDefa], AllFlags).


%! printer:to_flag_term(+Type, +Assumed, +Flag, -FlagTerm)
%
% Converts a flag to a flag term.

printer:to_flag_term(Type, Assumed, Flag, flag(Type, Flag, Assumed)).


%! printer:print_flags_unwrapped(+AllFlags)
%
% Prints a list of flags unwrapped.

printer:print_flags_unwrapped([]) :- !.
printer:print_flags_unwrapped([flag(Type, Flag, Assumed)|Rest]) :-
    printer:print_use_flag(Type, Flag, Assumed),
    (Rest == [] -> true ; write(' ')),
    printer:print_flags_unwrapped(Rest).


%! printer:get_flag_length(+Type, +Flag, +Assumed, -Length)
%
% Gets the length of a flag.

printer:get_flag_length(Type, Flag, Assumed, Length) :-
    (   memberchk(minus(Flag), Assumed) -> atom_length(Flag, L), Length is L + 1
    ;   memberchk(Flag, Assumed) -> atom_length(Flag, Length)
    ;   printer:get_flag_length_typed(Type, Flag, Length)
    ).

printer:get_flag_length_typed(positive:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(Flag,env) -> Length is L + 1 ; Length is L).

printer:get_flag_length_typed(positive:ebuild, Flag, Length) :-
    atom_length(Flag, Length).

printer:get_flag_length_typed(negative:preference, Flag, Length) :-
    atom_length(Flag, L),
    ( preference:use(minus(Flag),env) -> Length is L + 2 ; Length is L + 1).

printer:get_flag_length_typed(negative:ebuild, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.

printer:get_flag_length_typed(negative:default, Flag, Length) :-
    atom_length(Flag, L),
    Length is L + 1.


%! printer:print_use_flag(+Reason,+Flag,Assumed)
%
% Prints a single flag.

printer:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(minus(Flag), Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(_Reason, Flag, Assumed) :-
  memberchk(Flag, Assumed), !,
  message:color(orange),
  %message:style(bold),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:preference, Flag, _Assumed) :-
  preference:use(Flag,env), !,
  message:color(green),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(positive:preference, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:ebuild, Flag, _Assumed) :-
  !,
  message:color(red),
  message:style(italic),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:preference, Flag, _Assumed) :-
  preference:use(minus(Flag),env), !,
  message:color(green),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(negative:preference, Flag, _Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:ebuild, Flag, _Assumed) :-
  !,
  message:color(lightblue),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:default, Flag, _Assumed) :-
  !,
  message:color(darkgray),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).


%! printer:check_assumptions(+Model)
%
% Checks whether the Model contains assumptions

printer:check_assumptions(Model) :-
  member(assumed(_),Model),!.


%! printer:print_header(+Target)
%
% Prints the header for a given target

printer:print_header(Target) :-
  nl,
  message:header('Emerging ',Target),
  message:color(green),
  message:print('These are the packages that would be merged, in order:'),nl,
  nl,
  message:color(normal),
  message:print('Calculating dependencies... done!'),nl,
  nl.


%! printer:print_body(+Target,+Plan,+Call,-Steps)
%
% Prints the body for a given plan.
printer:print_body(Target, Plan, Call, Steps) :-
  printer:print_steps_in_plan(Target, Plan, Call, 0, Steps).


%! printer:print_steps_in_plan(+Target,+Plan,+Call,+Count,-NewCount)
%
% Print the steps in a plan.

printer:print_steps_in_plan(_, [], _, Count, Count) :- !.

printer:print_steps_in_plan(Target, [Step|Rest], Call, Count, CountFinal) :-
  predsort(printer:sort_by_weight, Step, SortedRules),
  printer:print_first_in_step(Target, SortedRules, Count, CountNew),
  call(Call, SortedRules), !,
  printer:print_steps_in_plan(Target, Rest, Call, CountNew, CountFinal).


%! printer:print_first_in_step(+Target,+Step,+Count,-NewCount)
%
% Print a step in a plan
printer:print_first_in_step(_,[],Count,Count) :- !.

printer:print_first_in_step(Target,[Rule|Rest],Count,NewCount) :-
  printer:printable_element(Rule),
  NewCount is Count + 1,
  format(atom(AtomNewCount),'~t~0f~2|',[NewCount]),
  format(atom(StepNewCount),'step ~a',[AtomNewCount]),
  !,
  write(' └─'),
  message:bubble(darkgray,StepNewCount),
  write('─┤ '),
  printer:print_element(Target,Rule),
  printer:print_next_in_step(Target,Rest).

printer:print_first_in_step(Target,[_|Rest],Count,NewCount) :-
  printer:print_first_in_step(Target,Rest,Count,NewCount).


%! printer:print_next_in_step(+Target,+Step)
%
% Print a step in a plan
printer:print_next_in_step(_,[]) :- nl,nl,!.

printer:print_next_in_step(Target,[Rule|Rest]) :-
  printer:printable_element(Rule),
  !,
  nl,
  write('             │ '),
  printer:print_element(Target,Rule),
  printer:print_next_in_step(Target,Rest).

printer:print_next_in_step(Target,[_|Rest]) :-
  !,
  printer:print_next_in_step(Target,Rest).


%! printer:print_footer(+Plan, +ModelAVL, +PrintedSteps)
%
% Prints the footer for a given plan.

printer:print_footer(_Plan, ModelAVL, PrintedSteps) :-
  printer:footer_stats(ModelAVL, S),
  printer:pluralize(S.actions, action, actions, TotalStr),
  printer:pluralize(S.downloads, download, downloads, DStr),
  printer:pluralize(S.installs, install, installs, IStr),
  printer:pluralize(S.reinstalls, reinstall, reinstalls, RIStr),
  printer:pluralize(S.runs, run, runs, RStr),
  printer:pluralize(PrintedSteps, step, steps, PStr),
  format('Total: ~d ~w (~d ~w, ~d ~w, ~d ~w, ~d ~w), grouped into ~d ~w.~n',
         [S.actions, TotalStr, S.downloads, DStr, S.installs, IStr, S.reinstalls, RIStr, S.runs, RStr, PrintedSteps, PStr]),
  message:convert_bytes(S.total_dl, BytesStr),
  format('~7|~w to be downloaded.~n~n', [BytesStr]).


%! printer:pluralize(+Count, +Singular, +Plural, -Result)
%
% Pluralizes a word based on a count.

printer:pluralize(1, Singular, _, Singular) :- !.
printer:pluralize(_, _, Plural, Plural).


%! printer:footer_stats(+ModelAVL, -Stats)
%
% Calculates statistics by iterating over the ModelAVL using gen_assoc.

printer:footer_stats(ModelAVL, Stats) :-
   StatsInitial = stats{ass:0, con:0, naf:0, actions:0, fetches:0,
                        downloads:0, runs:0, installs:0, reinstalls:0, total_dl:0},
   findall(Key, assoc:gen_assoc(Key, ModelAVL, _), Keys),
   foldl(printer:update_stats, Keys, StatsInitial, Stats).

%! printer:update_stats(+Key, +StatsIn, -StatsOut)
%
% Foldl helper to update stats

printer:update_stats(Key, S0, S) :-
  printer:update_stats_clauses(Key, S0, S).


%! printer:update_stats_clauses(+Key, +StatsIn, -StatsOut)
%
% The logic for updating stats based on a key.

printer:update_stats_clauses(assumed(_), S0, S) :-
  NewAss is S0.ass + 1, S = S0.put(ass, NewAss).
printer:update_stats_clauses(constraint(_), S0, S) :-
  NewCon is S0.con + 1, S = S0.put(con, NewCon).
printer:update_stats_clauses(naf(_), S0, S) :-
  NewNaf is S0.naf + 1, S = S0.put(naf, NewNaf).
printer:update_stats_clauses(_://_:fetchonly, S0, S) :-
  NewFetches is S0.fetches + 1, % NewActions is S0.actions + 1,
  S = S0.put(_{fetches:NewFetches}). %, actions:NewActions}).
printer:update_stats_clauses(R://E:download, S0, S) :-
  (ebuild:download_size(preference, R://E, Bytes) -> true ; Bytes = 0),
  NewDownloads is S0.downloads + 1, NewTotalDl is S0.total_dl + Bytes, NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, actions:NewActions}).
printer:update_stats_clauses(_://_:run, S0, S) :-
  NewRuns is S0.runs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{runs:NewRuns, actions:NewActions}).
printer:update_stats_clauses(_://_:install, S0, S) :-
  NewInstalls is S0.installs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{installs:NewInstalls, actions:NewActions}).
printer:update_stats_clauses(_://_:reinstall, S0, S) :-
  NewReinstalls is S0.reinstalls + 1, NewActions is S0.actions + 1,
  S = S0.put(_{reinstalls:NewReinstalls, actions:NewActions}).
printer:update_stats_clauses(_://_:_, S0, S) :-
  NewActions is S0.actions + 1, S = S0.put(actions, NewActions).
printer:update_stats_clauses(_, S, S).


%! printer:print_warnings(+ModelAVL, +ProofAVL, +TriggersAVL)
%
% Efficiently checks and prints assumptions using library predicates.

printer:print_warnings(ModelAVL, ProofAVL, TriggersAVL) :-
  once((assoc:gen_assoc(Key, ModelAVL, _), Key = assumed(_))),
  !,
  nl,
  message:bubble(red,'Error'),
  message:color(red),
  message:print(' The proof for your build plan contains assumptions. Please verify:'), nl, nl,
  message:color(red),
  forall(assoc:gen_assoc(ProofKey, ProofAVL, _ProofValue),
         (printer:handle_assumption(ProofKey, ProofAVL, TriggersAVL))
  ),
  nl,
  message:color(normal),nl.

printer:print_warnings(_,_,_) :- !, nl.


%! printer:handle_assumption(+ProofKey)
%
% Helper to print details for both domain driven and prover driven assumption formats.

printer:handle_assumption(ProofKey) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  ;
      true
  ).


%! printer:handle_assumption(+ProofKey,+ProofAVL,+TriggersAVL)
%
% Extended assumption printer that can use proof and triggers for explanations.
printer:handle_assumption(ProofKey, _ProofAVL, TriggersAVL) :-
  % Case 1: key format: rule(assumed(...)) % domain driven assumption
  (   ProofKey = rule(assumed(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      nl
  % Case 2: key format: assumed(rule(...)) % prover driven assumption
  ;   ProofKey = assumed(rule(Content)) ->
      printer:print_assumption_detail(rule(Content, [])),
      printer:print_cycle_explanation(Content, TriggersAVL),
      nl
  ;
      true
  ).


% -----------------------------------------------------------------------------
%  Cycle explanation (minimal "works now" implementation)
% -----------------------------------------------------------------------------

%! printer:print_cycle_explanation(+StartKey,+TriggersAVL)
printer:print_cycle_explanation(StartKey, TriggersAVL) :-
  % Accept both package keys (R://E:install) and non-package keys (X:install),
  % so cycles can still be found even when the assumption is a grouped dep term.
  ( StartKey = _://_:install ; StartKey = _://_:run ; StartKey = _://_:fetchonly
  ; StartKey = _:install     ; StartKey = _:run     ; StartKey = _:fetchonly
  ),
  printer:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath0),
  printer:cycle_display_path(CyclePath0, CyclePath),
  CyclePath = [_|_],
  !,
  message:color(darkgray),
  message:print('  Cycle (reverse dependency path):'), nl,
  message:color(normal),
  printer:print_cycle_tree(CyclePath).
printer:print_cycle_explanation(_, _) :-
  true.

% Print a cycle path as a simple "tree chain" using └─> connectors.
printer:print_cycle_tree([]) :- !.
printer:print_cycle_tree([First|Rest]) :-
  BaseIndent = '    ',
  printer:print_cycle_tree_line(BaseIndent, First),
  ( Rest == [] -> true ; nl ),
  atom_concat(BaseIndent, '    ', NextIndent),
  printer:print_cycle_tree_rest(Rest, NextIndent).

printer:print_cycle_tree_rest([], _Indent) :- !.
printer:print_cycle_tree_rest([Node|Rest], Indent) :-
  printer:print_cycle_tree_line(Indent, Node),
  ( Rest == [] -> true ; nl ),
  atom_concat(Indent, '    ', Indent1),
  printer:print_cycle_tree_rest(Rest, Indent1).

% Print one cycle node line as: "└─<action bubble>─> <entry>"
printer:print_cycle_tree_line(Indent, Node) :-
  message:print(Indent),
  printer:cycle_node_parts(Node, Entry, Action),
  message:color(darkgray),
  message:print('└─'),
  message:color(normal),
  message:bubble(darkgray,Action),
  message:color(darkgray),
  message:print('─> '),
  message:color(normal),
  message:print(Entry),
  nl.

% Extract Entry and Action from a cycle node (already filtered to package keys).
% Examples:
%   portage://dev-libs/libxml2-2.15.1:install  -> Entry=dev-libs/libxml2-2.15.1, Action=install
%   portage://dev-libs/libxml2-2.15.1          -> Entry=dev-libs/libxml2-2.15.1, Action=unknown
printer:cycle_node_parts(_Repo://Entry:Action, Entry, Action) :- !.
printer:cycle_node_parts(_Repo://Entry,        Entry, unknown) :- !.
printer:cycle_node_parts(Entry:Action,         Entry, Action) :- !.
printer:cycle_node_parts(Entry,               Entry, unknown).

% Keep only the human-meaningful nodes: package keys (R://E or R://E:Action).
printer:cycle_display_path(CyclePath0, CyclePath) :-
  findall(P,
          ( member(N, CyclePath0),
            printer:cycle_node_package_key(N, P)
          ),
          P0),
  printer:dedup_consecutive(P0, CyclePath).

printer:cycle_node_package_key(R://E:A, R://E:A) :- !.
printer:cycle_node_package_key(R://E,   R://E)   :- !.

printer:dedup_consecutive([], []).
printer:dedup_consecutive([X|Xs], [X|Ys]) :-
  printer:dedup_consecutive_(Xs, X, Ys).

printer:dedup_consecutive_([], _Prev, []).
printer:dedup_consecutive_([X|Xs], Prev, Ys) :-
  ( X == Prev ->
      printer:dedup_consecutive_(Xs, Prev, Ys)
  ;
      Ys = [X|Rest],
      printer:dedup_consecutive_(Xs, X, Rest)
  ).


%! printer:find_cycle_via_triggers(+StartKey,+TriggersAVL,-CyclePath)
printer:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath) :-
  MaxDepth = 25,
  printer:dfs_cycle(StartKey, StartKey, TriggersAVL, [StartKey], 0, MaxDepth, [StartKey], RevPath),
  reverse(RevPath, CyclePath),
  CyclePath = [StartKey|_].


%! printer:dfs_cycle(+Start,+Node,+Triggers,+Visited,+Depth,+MaxDepth,+Acc,-Out)
printer:dfs_cycle(Start, Node, TriggersAVL, _Visited, Depth, _MaxDepth, Acc, [Start|Acc]) :-
  Depth > 0,
  printer:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Start, Neigh),
  !.
printer:dfs_cycle(Start, Node, TriggersAVL, Visited, Depth, MaxDepth, Acc, Out) :-
  Depth < MaxDepth,
  printer:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Next, Neigh),
  \+ memberchk(Next, Visited),
  Depth1 is Depth + 1,
  printer:dfs_cycle(Start, Next, TriggersAVL, [Next|Visited], Depth1, MaxDepth, [Next|Acc], Out).


%! printer:trigger_neighbors(+Key,+TriggersAVL,-NeighborKeys)
%
% Neighbors are dependents of Key in the triggers graph, canonicalized to keys
% (dropping context) to keep the search space manageable.
printer:trigger_neighbors(Key, TriggersAVL, NeighborKeys) :-
  ( get_assoc(Key, TriggersAVL, Dependents) -> true ; Dependents = [] ),
  findall(K,
          ( member(Dep, Dependents),
            prover:canon_literal(Dep, K, _)
          ),
          Ks),
  sort(Ks, NeighborKeys).


%! printer:print_assumption_detail(+RuleTerm)
%
% Prints formatted, non-garbled assumption details.

printer:print_assumption_detail(rule(package_dependency(T,A,C,N,X,Y,Z,XX):_YY?{_ZZ},_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Non-existent '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    printer:print_metadata_item_detail(_,'  ',package_dependency(T,A,C,N,X,Y,Z,XX)),nl.

printer:print_assumption_detail(rule(grouped_package_dependency(C,N,R):T?{_},_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Non-existent '),
    message:print(T),
    message:print(' dependency: '),
    message:style(normal),
    nl,
    message:color(normal),
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(C,N,R)),nl.

printer:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),
    nl,
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

printer:print_assumption_detail(rule(grouped_package_dependency(X,C,N,R):run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),
    nl,
    printer:print_metadata_item_detail(_,'  ',grouped_package_dependency(X,C,N,R)),nl.

printer:print_assumption_detail(rule(R://E:install,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed installed: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

printer:print_assumption_detail(rule(R://E:run,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Assumed running: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

printer:print_assumption_detail(rule(R://E:unmask,_)) :- !,
    message:color(lightred),
    message:style(bold),
    message:print('- Masked: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(R://E), nl.

printer:print_assumption_detail(rule(C,_)) :-
    message:color(lightred),
    message:style(bold),
    message:print('- Other: '),
    message:style(normal),
    message:color(normal),nl,
    message:print('  '),
    message:print(C), nl.


%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan,+TriggersAVL)
%
% Prints a plan. Triggers are required so the printer can explain assumptions
% (e.g. dependency cycles) when present.
printer:print(Target,ModelAVL,ProofAVL,Plan,TriggersAVL) :-
  printer:print(Target,ModelAVL,ProofAVL,Plan,printer:dry_run,TriggersAVL).

%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan,+Call,+TriggersAVL)
printer:print(Target,ModelAVL,ProofAVL,Plan,Call,TriggersAVL) :-
  printer:print_header(Target),
  printer:print_body(Target,Plan,Call,Steps),
  printer:print_footer(Plan,ModelAVL,Steps),
  printer:print_warnings(ModelAVL,ProofAVL,TriggersAVL).


%! printer:dry_run(+Step)
%
% Default execution strategy for building steps in a plan

printer:dry_run(_Step) :-
  true.
  %message:color(darkgray),
  %message:print(['building step : ',Step]),nl,
  %message:color(normal).


%! printer:write_repository_index_file(+Directory,+Repository)
%
% Write the index file for a given repository, listing all categories.

printer:write_repository_index_file(Directory,Repository) :-
  atomic_list_concat(['Repository: ',Repository],Title),
  atomic_list_concat([Directory,'/index.html'],File),
  tell(File),
  print_index(repository,Title,Title,cache:category(Repository,Category),Category,'./.index.css'),
  told.


%! printer:write_category_index_file(+Directory,+Repository,+Category)
%
% Write the index file for a given category, listing all packages.

printer:write_category_index_file(Directory,Repository,Category) :-
  atomic_list_concat(['Category: ',Repository,'://',Category],Title),
  atomic_list_concat(['Category: <a href=\"../index.html\">',Repository,'</a>://',Category],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/index.html'],File),
  tell(File),
  print_index(category,Title,TitleHtml,cache:package(Repository,Category,Name),Name,'../.index.css'),
  told.


%! printer:write_package_index_file(+Directory,+Repository,+Category,+Name)
%
% Write the index file for a given package, listing all entries

printer:write_package_index_file(Directory,Repository,Category,Name) :-
  atomic_list_concat(['Package: ',Repository,'://',Category,'/',Name],Title),
  atomic_list_concat(['Package: <a href=\"../index.html\">',Repository,'</a>://<a href=\"./index.html\">',Category,'</a>/',Name],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/',Name,'.html'],File),
  tell(File),
  print_index(package,Title,TitleHtml,cache:ordered_entry(Repository,_,Category,Name,[_,_,_,Version]),[Name,Version],'../.index.css'),
  told.


%! printer:write_merge_file(+Directory,+Repository://Entry)
%
% Print merge plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_merge_file(Directory,Repository://Entry) :-
  Action = run,
  Extension = '.merge',
  (with_q(prover:prove(Repository://Entry:Action?{[]},t,Proof,t,Model,t,_Constraints,t,Triggers)),
   with_q(planner:plan(Proof,Triggers,t,Plan)),
   atomic_list_concat([Directory,'/',Entry,Extension],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan,Triggers)
   -> told
   ; (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',Action])))).


%! printer:write_fetchonly_file(+Directory,+Repository://Entry)
%
% Print fetchonly plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_fetchonly_file(Directory,Repository://Entry) :-
  Action = fetchonly,
  Extension = '.fetchonly',
  (with_q(prover:prove(Repository://Entry:Action?{[]},t,Proof,t,Model,t,_Constraints,t,Triggers)),
   with_q(planner:plan(Proof,Triggers,t,Plan)),
   atomic_list_concat([Directory,'/',Entry,Extension],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan,Triggers)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',Action])))).


%! printer:write_info_file(+Directory,+Repository://Entry)
%
% Print info to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_info_file(Directory,Repository://Entry) :-
  (atomic_list_concat([Directory,'/',Entry,'.info'],File)),
  (tell(File),
   set_stream(current_output,tty(true)), % otherwise we lose color
   printer:print_entry(Repository://Entry)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',info])))).


%! printer:write_index_files(+Directory,+Repository)
%
% Print index files for repository, its categories and packages.
% Assumes directory exists. (See repository:prepare_directory)

printer:write_index_files(Directory,Repository) :-

  printer:write_repository_index_file(Directory,Repository),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://Category,
              cache:category(Repository,Category),
              printer:write_category_index_file(Directory,Repository,Category)),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://CategoryName,
              (cache:package(Repository,Category,Name),
               atomic_list_concat([Category,'/',Name],CategoryName)),
              printer:write_package_index_file(Directory,Repository,Category,Name)).


%! printer:write_proof_files(+Directory,+Repository)
%
% Print merge, fetchonly & info to file for all entries in a repository
% Assumes directory exists. (See repository:prepare_directory)

printer:write_proof_files(Directory,Repository) :-
  tester:test(parallel_verbose,
              'Writing proof files',
              Repository://Entry,
              (Repository:entry(Entry),
               (config:graph_modified_only(true)
                -> Repository:entry(Entry,Time),
                   Repository:get_ebuild_file(Entry,Ebuild),
                   system:exists_file(Ebuild),
                   system:time_file(Ebuild,Modified),
                   Modified > Time
                ;  true)),
	      ((printer:write_merge_file(Directory,Repository://Entry);true),
	       (printer:write_fetchonly_file(Directory,Repository://Entry);true),
               (printer:write_info_file(Directory,Repository://Entry);true))).


%! printer:produce_html(+Directory)
%
% For a given directory with proof files, convert the files into html.

printer:produce_html(Directory) :-
  message:scroll_notice(['Now running Aha ...']),
  message:hc,
  script:exec(print,['aha',Directory]),
  message:sc.


%! unify(+A,+B)
%
% Helper predicate to check if two terms are unifiable.

unify(A,B) :- unifiable(A,B,_),!.


% -----------------------------------------------------------------------------
%  Testing
% -----------------------------------------------------------------------------

%! printer:test(+Repository)
%
% Proves and prints every entry in a given repository, reports using the default reporting style

printer:test(Repository) :-
  config:test_style(Style),
  printer:test(Repository,Style).


%! printer:test(+Repository,+Style)
%
% Proves and prints every entry in a given repository, reports using a given reporting style

printer:test(Repository,parallel_fast) :-
  !,
  printer:test(Repository,parallel_verbose).

printer:test(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Printing',
              Repository://Entry,
              (Repository:entry(Entry)),
              ( % --- REFACTORED LOGIC ---
                % 1. Call prover and planner.
                with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers)),
                with_q(planner:plan(ProofAVL,Triggers,t,Plan))
                % No conversion here! AVLs are kept as-is.
              ),
              % 2. Call the newly refactored print predicate.
              printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers),
              false).


%! printer:test_latest(+Repository)
%
% Same as printer:test(+Repository), but only tests highest version of every package

printer:test_latest(Repository) :-
  !,
  printer:test_latest(Repository,parallel_verbose).

printer:test_latest(Repository,Style) :-
  config:proving_target(Action),
  tester:test(Style,
              'Printing latest',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              ( % --- REFACTORED LOGIC ---
                with_q(prover:prove(Repository://Entry:Action?{[]},t,ProofAVL,t,ModelAVL,t,_Constraint,t,Triggers)),
                with_q(planner:plan(ProofAVL,Triggers,t,Plan))
              ),
              (printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan,Triggers)),
              false).
