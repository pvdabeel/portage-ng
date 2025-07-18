/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

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
  message:color(lightgray),
  message:style(italic),
  write('[use] '),
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
  message:color(lightgray),
  message:style(italic),
  write('[any] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,all_of_group(Values)) :-
  !,
  write(Prefix),
  message:color(lightgray),
  message:style(italic),
  write('[all] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,exactly_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:color(lightgray),
  message:style(italic),
  write('[one] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(Item,Prefix,at_most_one_of_group(Values)) :-
  !,
  write(Prefix),
  message:color(lightgray),
  message:style(italic),
  write('[one] '),
  message:color(normal),
  atom_concat('   ',Prefix,NewPrefix),
  forall(member(V,Values),(nl,message:color(darkgray),message:color(normal),printer:print_metadata_item_detail(Item,NewPrefix,V))).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,_,Blocking,Category,Name,none,[[],_,_,_,_],Slot,Use)) :-
  !,
  write(Prefix),
  printer:print_blocking(Blocking),
  write(Category),
  write('/'),
  write(Name),
  printer:print_slot_restriction(Slot),
  printer:print_use_dependencies(Use).

printer:print_metadata_item_detail(_,Prefix,package_dependency(_,_,Blocking,Category,Name,Comparator,[_,_,_,Version],Slot,Use)) :-
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

printer:print_slot_restriction(any_different_slot) :-
  message:color(lightgray),
  write(':*'),
  message:color(normal).

printer:print_slot_restriction(any_same_slot) :-
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
%printer:printable_element(rule(_Repository://_Entry:fetchonly?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:install?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:reinstall?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:uninstall?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:update?_,_)) :- !.
printer:printable_element(rule(_Repository://_Entry:upgrade?_,_)) :- !.
printer:printable_element(assumed(rule(_Repository://_Entry:_?_,_))) :- !.
printer:printable_element(rule(assumed(_Repository://_Entry:_?_,_))) :- !.
printer:printable_element(assumed(rule(package_dependency(_,_,_,_,_,_,_,_,_):_?_,_))) :- !.
printer:printable_element(rule(assumed(package_dependency(_,_,_,_,_,_,_,_,_):_?_,_))) :- !.

% Uncomment if you want 'confirm' steps shown in the plan:
% printer:printable_element(rule(package_dependency(_,run,_,_,_,_,_,_,_),_)) :- !.


%! printer:element_weight(+Literal)
%
% Declares a weight for ordering elements of a step in a plan

printer:element_weight(assumed(_),                                      0) :- !. % assumed
printer:element_weight(rule(assumed(_),_),                              0) :- !. % assumed
printer:element_weight(rule(uri(_),_),                                  0) :- !. % provide
printer:element_weight(rule(uri(_,_,_),_),                              1) :- !. % fetch
printer:element_weight(rule(package_dependency(_,_,_,_,_,_,_,_,_),_),   1) :- !. % confirm
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

% ---------------------------------------------
% CASE: simple package, is a target of the plan
% ---------------------------------------------

printer:print_element(Target,rule(Repository://Entry:Action?{Context},_)) :-
  member(Repository://Entry:Action?_,Target),
  !,
  message:color(cyan),
  message:print(Action),
  message:style(bold),
  message:color(green),
  message:column(39,Repository://Entry),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% -------------------------------------------------
% CASE: simple package, is not a target of the plan
% -------------------------------------------------

printer:print_element(_,rule(Repository://Entry:Action?{Context},_)) :-
  message:color(cyan),
  message:print(Action),
  message:color(green),
  message:column(34,Repository://Entry),
  message:color(normal),
  printer:print_config(Repository://Entry:Action?{Context}).


% --------------------------------------------------------------
% CASE: verify that packages that need to be running are running
% --------------------------------------------------------------

printer:print_element(_,rule(package_dependency(_,run,_,_C,_N,_,_,_,_),[Repository://Entry:_Action?{_Context}])) :-
  !,
  message:color(cyan),
  message:print('confirm'),
  message:color(green),
  message:column(34,Repository://Entry),
  message:color(normal).


% ----------------
% CASE: a download
% ----------------

printer:print_element(_,rule(uri(Protocol,Remote,_Local),_)) :-
  !,
  message:color(cyan),
  message:print('fetch'),
  message:color(green),
  message:column(34,Protocol://Remote),
  message:color(normal).

printer:print_element(_,rule(uri(Local),_)) :-
  !,
  message:color(cyan),
  message:print('provide'),
  message:color(green),
  message:column(34,Local),
  message:color(normal).


% ---------------------------------------------------------------
% CASE: an assumed dependency on a non-existent installed package
% ---------------------------------------------------------------

printer:print_element(_,rule(assumed(package_dependency(_,install,no,C,N,_,_,_,_):install?{_Context}),[])) :-
  message:color(red),
  message:print('verify'),
  atomic_list_concat([C,'/',N],P),
  message:column(29,P),
  message:print([' (non-existent, assumed installed)']),
  message:color(normal).


% -------------------------------------------------------------
% CASE: an assumed dependency on a non-existent running package
% -------------------------------------------------------------

printer:print_element(_,rule(assumed(package_dependency(_,run,no,C,N,_,_,_,_):run?{_Context}),[])) :-
  message:color(red),
  message:print('verify'),
  atomic_list_concat([C,'/',N],P),
  message:column(29,P),
  message:print([' (non-existent, assumed running)']),
  message:color(normal).


% ---------------------------------
% CASE: an assumed unmasked package
% ---------------------------------

printer:print_element(_,rule(assumed(Repository://Entry:unmask?{_Context}),_Body)) :-
  message:color(red),
  message:print('verify'),
  message:column(29,Repository://Entry),
  message:print(' (masked)'),
  message:color(normal).


% ----------------------------------
% CASE: an assumed installed package
% ----------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:install?{_Context},_Body))) :-
  message:color(red),
  message:print('verify'),
  message:column(29,Repository://Entry),
  message:print(' (assumed installed)'),
  message:color(normal).


% --------------------------------
% CASE: an assumed running package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:run?{_Context},_Body))) :-
  message:color(red),
  message:print('verify'),
  message:column(29,Repository://Entry),
  message:print(' (assumed running) '),
  message:color(normal).


% --------------------------------
% CASE: an assumed fetched package
% --------------------------------

printer:print_element(_,assumed(rule(Repository://Entry:fetchonly?{_Context},_Body))) :-
  message:color(red),
  message:print('verify'),
  message:column(29,Repository://Entry),
  message:print(' (assumed fetched) '),
  message:color(normal).


% -------------------------------------
% CASE: an assumed installed dependency
% -------------------------------------

printer:print_element(_,assumed(rule(package_dependency(_,install,_,C,N,_,_,_,_),_Body))) :-
  message:color(red),
  message:print('verify'),
  atomic_list_concat([C,'/',N],P),
  message:column(28,P),
  message:print(' (assumed installed) '),
  message:color(normal).


% -----------------------------------
% CASE: an assumed running dependency
% -----------------------------------

printer:print_element(_,assumed(rule(package_dependency(_,run,_,C,N,_,_,_,_),_Body))) :-
  message:color(red),
  message:print('verify'),
  atomic_list_concat([C,'/',N],P),
  message:column(28,P),
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
  write(' ').

% --------------------------------
% CASE: Column build plan printing
% --------------------------------

printer:print_config_prefix(file) :-
  config:printing_style('column'),!,
  message:column(115,' ').

printer:print_config_prefix(_Word) :-
  config:printing_style('column'),!,
  message:column(110,' ').


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
  write(' ').

printer:print_config_prefix :-
  config:printing_style('column'),!,
  nl,write('             │ '),
  message:column(85,' ').


%! printer:print_config(+Repository://+Entry:+Action:+Context)
%
% Prints the configuration for a given repository entry (USE flags, USE expand, ...)

% ----------------------
% CASE: fetchonly action
% ----------------------

%printer:print_config(_Repository://_Ebuild:fetchonly:_Context).% :-
  %printer:print_config_prefix('done'),
  %printer:print_config_item('fetchonly','fetching all','downloads').


% iuse empty

printer:print_config(Repository://Entry:fetchonly?{_Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!.

% use flags to show - to rework: performance

printer:print_config(Repository://Entry:fetchonly?{Context}) :-
 !,
 findall(Use, member(assumed(Use),Context), Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (printer:print_config_prefix('conf'),	            % Use flags not empty
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

  % If you want to show use flags right before the downloads:

  % findall(Use, member(assumed(Use),Context), Assumed),
  % findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Ebuild), Group), Useflags),

  % (Useflags == [] ;
  %  (printer:print_config_prefix('conf'),	    	      % Use flags not empty
  %   printer:print_config_item('use',Useflags,Assumed))),    % Use flags not empty


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

printer:print_config(Repository://Entry:install?{_Context}) :-
  \+(kb:query(iuse(_),Repository://Entry)),!.

% use flags to show - to rework: performance

printer:print_config(Repository://Entry:install?{Context}) :-
 !,
 findall(Use, member(assumed(Use),Context), Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (printer:print_config_prefix('conf'),	            % Use flags not empty
    printer:print_config_item('use',Useflags,Assumed))).    % Use flags not empty

  %config:print_expand_use(false) ; (
  %findall([Key,Keyflags], ( preference:use_expand_hidden(Key),
  %			      Statement =.. [Key,Use,Reason],
  %                           (findall([Reason,Group],
  %                                     group_by(Reason,Use,kb:query(Statement,Repository://Entry), Group),
  %                                     Keyflags ) ),
  %                            \+(Keyflags == [])),
  %                          Expandedkeys),

  % (forall(member([Key,Keyflags],Expandedkeys),
  %  ((Useflags == [] ->				    % Expandedkeys not empty
  %    printer:print_config_prefix('conf');	            % Expandedkeys not empty, use flags empty
  %    printer:print_config_prefix),		            % Expandedkeys not empty, use flags not empty
  %   printer:print_config_item(Key,Keyflags))))),!.        % Expandedkeys not empty


% ----------------
% CASE: Run action
% ----------------

printer:print_config(_://_:run?{_Context}) :- !.


% --------------
% CASE: All info
% --------------

printer:print_config(Repository://Entry:all?{Context}) :-
 !,

 findall(Use, member(assumed(Use),Context), Assumed),
 findall([Reason,Group], group_by(Reason, Use, kb:query(iuse_filtered(Use,Reason),Repository://Entry), Group), Useflags),

 (Useflags == [] ;
   (message:print('└─ '),
    message:print(' ─┤ '),
    printer:print_config_item('use',Useflags,Assumed))),

  findall([File,Size],kb:query(manifest(preference,_,File,Size),Repository://Entry),[[FirstFile,FirstSize]|Rest]),!,

  printer:print_config_item('download',FirstFile,FirstSize),
  forall(member([RestFile,RestSize],Rest),
        (printer:print_config_prefix,
         printer:print_config_item('download',RestFile,RestSize))).


% -------------------
% CASE: Other actions
% -------------------

printer:print_config(_://_:_?_) :- !.

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
  %message:color(normal).

printer:print_config_item('download',File,Size) :-
  !,
  message:color(magenta),
  message:print_bytes(Size),
  message:color(normal),
  message:print(' '),
  message:print(File).


%! printer:print_config_item(+Key,List,Assumed) % PosPref,PosEbui,NegPref,NegEbui,NegDefa)
%
% Prints a configuration item for a given repository entry

printer:print_config_item(Key,List,Assumed) :- % PosPref,PosEbui,NegPref,NegEbui,NegDefa) :-
  !,
  upcase_atom(Key,KeyU),
  message:print(KeyU),
  message:print('="'),
  printer:print_use_flag_sets(List,Assumed),
  message:print('"').


%! printer:print_use_flag_sets(+List,+Assumed)
%
% Prints a list of Enabled and Disabled Use flags

printer:print_use_flag_sets(List,Assumed) :-
  (memberchk([negative:default,NegDefa],List);    NegDefa=[]),!,
  (memberchk([negative:ebuild,NegEbui],List);     NegEbui=[]),!,
  (memberchk([negative:preference,NegPref],List); NegPref=[]),!,
  (memberchk([positive:ebuild,PosEbui],List);     PosEbui=[]),!,
  (memberchk([positive:preference,PosPref],List); PosPref=[]),!,
  printer:print_use_flag_set(positive:preference,PosPref,Assumed,'',D1),
  printer:print_between(D1,PosEbui),
  printer:print_use_flag_set(positive:ebuild,PosEbui,Assumed,D1,D2),
  printer:print_between(D2,NegPref),
  printer:print_use_flag_set(negative:preference,NegPref,Assumed,D2,D3),
  printer:print_between(D3,NegEbui),
  printer:print_use_flag_set(negative:ebuild,NegEbui,Assumed,D3,D4),
  printer:print_between(D4,NegDefa),
  printer:print_use_flag_set(negative:default,NegDefa,Assumed,D4,_),!.


%! printer:print_between_use_flag_set(D,Future)
%
% Prints a delayed char if future is non-empty

printer:print_between(_,[]) :- !.

printer:print_between(D,_) :-
  !,
  write(D).


%! printer:print_use_flag_set(+Type,+Flags,+Assumed,Char,NextChar))
%
% Sorts, then prints a list of USE flags

printer:print_use_flag_set(_,[],_,D,D) :- !.

printer:print_use_flag_set(Type,Flags,Assumed,_,' ') :-
  !,
  sort(Flags,Orderedflags),
  printer:print_use_flag(Type,Orderedflags,Assumed).


%! printer:print_use_flag(+Reason,+Flags,Assumed)
%
% Prints a list of USE flags

printer:print_use_flag(_,[],_) :-
  !.

printer:print_use_flag(_Reason,[Flag],Assumed) :-
  memberchk(minus(Flag),Assumed),!,
  message:color(orange),
  %message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print('').

printer:print_use_flag(_Reason,[Flag|Rest],Assumed) :-
  memberchk(minus(Flag),Assumed),!,
  message:color(orange),
  %message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print(' '),
  printer:print_use_flag(positive:preference,Rest,Assumed).


printer:print_use_flag(_Reason,[Flag],Assumed) :-
  memberchk(Flag,Assumed),!,
  message:color(orange),
  %message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print('').

printer:print_use_flag(_Reason,[Flag|Rest],Assumed) :-
  member(Flag,Assumed),!,
  message:color(orange),
  %message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print(' '),
  printer:print_use_flag(positive:preference,Rest,Assumed).

printer:print_use_flag(positive:preference,[Flag],_Assumed) :-
  preference:use(Flag,env),!,
  message:color(green),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(positive:preference,[Flag],_Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:preference,[Flag|Rest],Assumed) :-
  preference:use(Flag,env),!,
  message:color(green),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print('* '),
  printer:print_use_flag(positive:preference,Rest,Assumed).

printer:print_use_flag(positive:preference,[Flag|Rest],Assumed) :-
  !,
  message:color(red),
  message:style(bold),
  message:print(Flag),
  message:color(normal),
  message:print(' '),
  printer:print_use_flag(positive:preference,Rest,Assumed).

printer:print_use_flag(positive:ebuild,[Flag],_Assumed) :-
  !,
  message:color(red),
  message:style(italic),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(positive:ebuild,[Flag|Rest],Assumed) :-
  !,
  message:color(red),
  message:style(italic),
  message:print(Flag),
  message:print(' '),
  message:color(normal),!,
  printer:print_use_flag(positive:ebuild,Rest,Assumed).

printer:print_use_flag(negative:preference,[Flag],_Assumed) :-
  preference:use(minus(Flag),env),!,
  message:color(green),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print('*').

printer:print_use_flag(negative:preference,[Flag],_Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:preference,[Flag|Rest],Assumed) :-
  preference:use(minus(Flag),env),!,
  message:color(green),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print('* '),
  printer:print_use_flag(negative:preference,Rest,Assumed).

printer:print_use_flag(negative:preference,[Flag|Rest],Assumed) :-
  !,
  message:color(blue),
  message:style(bold),
  message:print('-'),
  message:print(Flag),
  message:color(normal),
  message:print(' '),
  printer:print_use_flag(negative:preference,Rest,Assumed).

printer:print_use_flag(negative:ebuild,[Flag],_Assumed) :-
  !,
  message:color(lightblue),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:ebuild,[Flag|Rest],Assumed) :-
  !,
  message:color(lightblue),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:print(' '),
  message:color(normal),
  printer:print_use_flag(negative:ebuild,Rest,Assumed).

printer:print_use_flag(negative:default,[Flag],_Assumed) :-
  !,
  message:color(darkgray),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:color(normal).

printer:print_use_flag(negative:default,[Flag|Rest],Assumed) :-
  !,
  message:color(darkgray),
  message:style(italic),
  message:print('-'),
  message:print(Flag),
  message:print(' '),
  message:color(normal),!,
  printer:print_use_flag(negative:default,Rest,Assumed).


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
  !,
  write(' └─ step '),write(AtomNewCount), write(' ─┤ '),
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
printer:print_footer(_Plan, ModelAVL, PrintedSteps) :-
  footer_stats(ModelAVL, S),
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
   foldl(update_stats, Keys, StatsInitial, Stats).

%! printer:update_stats(+Key, +StatsIn, -StatsOut)
%
% Foldl helper

update_stats(Key, S0, S) :-
  update_stats_clauses(Key, S0, S).

%! printer:update_stats_clauses(+Key, +StatsIn, -StatsOut)
%
% The logic for updating stats based on a key.

update_stats_clauses(assumed(_), S0, S) :-
  NewAss is S0.ass + 1, S = S0.put(ass, NewAss).
update_stats_clauses(constraint(_), S0, S) :-
  NewCon is S0.con + 1, S = S0.put(con, NewCon).
update_stats_clauses(naf(_), S0, S) :-
  NewNaf is S0.naf + 1, S = S0.put(naf, NewNaf).
update_stats_clauses(_://_:fetchonly, S0, S) :-
  NewFetches is S0.fetches + 1, NewActions is S0.actions + 1,
  S = S0.put(_{fetches:NewFetches, actions:NewActions}).
update_stats_clauses(R://E:download, S0, S) :-
  (ebuild:download_size(preference, R://E, Bytes) -> true ; Bytes = 0),
  NewDownloads is S0.downloads + 1, NewTotalDl is S0.total_dl + Bytes, NewActions is S0.actions + 1,
  S = S0.put(_{downloads:NewDownloads, total_dl:NewTotalDl, actions:NewActions}).
update_stats_clauses(_://_:run, S0, S) :-
  NewRuns is S0.runs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{runs:NewRuns, actions:NewActions}).
update_stats_clauses(_://_:install, S0, S) :-
  NewInstalls is S0.installs + 1, NewActions is S0.actions + 1,
  S = S0.put(_{installs:NewInstalls, actions:NewActions}).
update_stats_clauses(_://_:reinstall, S0, S) :-
  NewReinstalls is S0.reinstalls + 1, NewActions is S0.actions + 1,
  S = S0.put(_{reinstalls:NewReinstalls, actions:NewActions}).
update_stats_clauses(_://_:_, S0, S) :-
  NewActions is S0.actions + 1, S = S0.put(actions, NewActions).
update_stats_clauses(_, S, S).


%! printer:print_warnings(+ModelAVL, +ProofAVL)
%
% Efficiently checks and prints assumptions using library predicates.

printer:print_warnings(ModelAVL, ProofAVL) :-
  once((assoc:gen_assoc(Key, ModelAVL, _), Key = assumed(_))),
  !,
  message:color(red), message:print('Error: The proof for your build plan contains assumptions. Please verify:'), nl, nl,
  message:color(red),
  forall(assoc:gen_assoc(ProofKey, ProofAVL, _ProofValue),
         printer:handle_assumption(ProofKey)
  ),
  nl,
  message:color(normal),nl.

printer:print_warnings(_,_) :- !, nl.


%! printer:handle_assumption(+ProofKey)
%
% Helper to print details for both correct and inconsistent assumption formats.

handle_assumption(ProofKey) :-
    % Case 1: Handles the inconsistent key format: rule(assumed(CONTENT))
    (   ProofKey = rule(assumed(Content)) ->
        % Reconstruct a rule/2 term to pass to the detail printer.
        printer:print_assumption_detail(rule(Content, []))
    % Case 2: Handles the correct key format: assumed(rule(CONTENT))
    ;   ProofKey = assumed(rule(Content)) ->
        % Reconstruct a rule/2 term to pass to the detail printer.
        printer:print_assumption_detail(rule(Content, []))
    ;
        true
    ).


%! printer:print_assumption_detail(+RuleTerm)
%
% Prints formatted, non-garbled assumption details.

printer:print_assumption_detail(rule(package_dependency(R://E,T,_,C,N,_,_,_,_):_?{_},_)) :- !,
    message:print(' - Non-existent or failed '), message:print(T),
    message:print(' dependency: '), message:print(C), message:print('/'), message:print(N),
    message:print(' for ebuild '), message:print(R://E), nl.
printer:print_assumption_detail(rule(R://E:install,_)) :- !,
    message:print(' - Assumed installed (not in world file or proof failed): '),
    message:print(R://E), nl.
printer:print_assumption_detail(rule(R://E:run,_)) :- !,
    message:print(' - Assumed running (not in world file or proof failed): '),
    message:print(R://E), nl.
printer:print_assumption_detail(rule(R://E:unmask,_)) :- !,
    message:print(' - Assumed unmasked (ebuild is masked): '),
    message:print(R://E), nl.
printer:print_assumption_detail(rule(C,_)) :-
    message:print(' - General assumption made: '), message:print(C), nl.



%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan)
%
% Prints a plan.

printer:print(Target,ModelAVL,ProofAVL,Plan) :-
  printer:print(Target,ModelAVL,ProofAVL,Plan,printer:dry_run).

%! printer:print(+Target,+ModelAVL,+ProofAVL,+Plan,+Call)
printer:print(Target,ModelAVL,ProofAVL,Plan,Call) :-
  printer:print_header(Target),
  printer:print_body(Target,Plan,Call,Steps),
  printer:print_footer(Plan,ModelAVL,Steps),
  printer:print_warnings(ModelAVL,ProofAVL).



%! printer:dry_run(+Step)
%
% Default execution strategy for building steps in a plan

printer:dry_run(_Step) :-
  true.
  %message:color(darkgray),
  %message:print(['building step : ',Step]),nl,
  %message:color(normal).


%! printer:unify(+A,+B)
%
% Helper predicate to check if two terms are unifiable.

unify(A,B) :- unifiable(A,B,_),!.


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
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan)
   -> told
   ; (told,with_mutex(mutex,message:warning([Repository://Entry,' ',Action])))).


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
   printer:print([Repository://Entry:Action?{[]}],Model,Proof,Plan)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository://Entry,' ',Action])))).


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
   ;  (told,with_mutex(mutex,message:warning([Repository://Entry,' ',info])))).


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
              (printer:write_merge_file(Directory,Repository://Entry),
	       printer:write_fetchonly_file(Directory,Repository://Entry),
               printer:write_info_file(Directory,Repository://Entry))).


%! printer:produce_html(+Directory)
%
% For a given directory with proof files, convert the files into html.

printer:produce_html(Directory) :-
  message:scroll_notice(['Now running Aha ...']),
  script:exec(print,['aha',Directory]),
  message:scroll_notice(['Done running Aha.']),
  message:sc.


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
              printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan),
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
              (printer:print([Repository://Entry:Action?{[]}],ModelAVL,ProofAVL,Plan)),
              false).
