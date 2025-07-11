/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GRAPHER
Outputs DOT language.

For a given ebuild, the following output can be produced:

 - detail:     A graph showing the ebuild, its run and compile dependencies, including
               strong and weak blockers and the potential ebuild candidates for realizing
               the dependencies.

 - depend:     A graph showing the full dependency tree for an ebuild; its dependencies as
               well as the dependencies of its dependencies and so on. Available for the
               different dependency types of an ebuild: bdepend, cdepend, depend, idepend,
               rdepend and pdepend.

 - merge:      A minimal dot file intended to show the output of merging the ebuild.

 - fetchonly:  A minimal dot file intended to show the output of fetching the ebuild.

 - info:       A minimal dot file intended to show the output of displaying ebuild info.

The DOT output is intended to be converted into scalable vector graphics (SVG). The output
contains interactive elements, enabling the user to click through to a dependency, change
the version, watch the output of a specific command, etc.
*/

:- module(grapher, []).

:- thread_local graph_visited/1.
:- thread_local counter/2.

% ********************
% GRAPHER declarations
% ********************

% -----------
% Graph types
% -----------

%! grapher:graph(+Type,+Repository://Id)
%
% For a given ebuild, identified by an Id, create a depedency graph.
%
% - detail   : shows the ebuild, its dependency syntax, and potential candidates
% - <type> : shows the ebuild in the full dependency tree
%
% <type> must be one of bdepend, cdepend, depend, idepend, rdepend, pdepend

grapher:graph(detail,Repository://Id) :-
  !,
  grapher:tl_gensym_reset(_),
  grapher:graph_header(detail,Repository://Id),
  grapher:graph_legend(detail,Repository://Id),
  grapher:graph_ebuild(detail,Repository://Id),
  grapher:graph_detail(detail,Repository://Id),
  grapher:graph_footer(detail,Repository://Id).

grapher:graph(merge,Repository://Id) :-
  !,
  grapher:graph_header(merge,Repository://Id),
  grapher:graph_legend(merge,Repository://Id),
  grapher:graph_root(merge,Repository://Id),
  grapher:graph_footer(merge,Repository://Id).

grapher:graph(fetchonly,Repository://Id) :-
  !,
  grapher:graph_header(fetchonly,Repository://Id),
  grapher:graph_legend(fetchonly,Repository://Id),
  grapher:graph_root(fetchonly,Repository://Id),
  grapher:graph_footer(fetchonly,Repository://Id).

grapher:graph(info,Repository://Id) :-
  !,
  grapher:graph_header(info,Repository://Id),
  grapher:graph_legend(info,Repository://Id),
  grapher:graph_root(info,Repository://Id),
  grapher:graph_footer(info,Repository://Id).

grapher:graph(Type,Repository://Id) :-
  member(Type,[bdepend,cdepend,depend,idepend,rdepend,pdepend]),!,
  grapher:graph_header(Type,Repository://Id),
  grapher:graph_legend(Type,Repository://Id),
  grapher:graph_root(Type,Repository://Id),
  grapher:graph_tree(Type,Repository://Id),
  grapher:graph_footer(Type,Repository://Id).


% -----------------------
% Graph component: header
% -----------------------

%! grapher:graph_header(Type,+Repository://Id)
%
% For a given ebuild, identified by an Id, create the header of the requested dependency graph.

grapher:graph_header(detail,_Repository://_Id) :-
  !,
  writeln('digraph prolog {'),
  nl,
  writeln('# *************'),
  writeln('# Graph options'),
  writeln('# *************'),
  nl,
  writeln('newrank=true;'),
  writeln('concentrate=true;'),
  writeln('compound=true;'),
  nl,
  writeln('graph [rankdir=LR,fontname=Helvetica,fontsize=10,ranksep=1.5];'),
  writeln('edge  [arrowhead=vee];'),
  writeln('node  [fontname=Helvetica,fontsize=10];'),
  nl.

grapher:graph_header(_Type,_Repository://_Id) :-
  !,
  writeln('digraph prolog {'),
  nl,
  writeln('newrank=true;'),
  writeln('concentrate=true;'),
  writeln('compound=true;'),
  nl,
  writeln('graph [rankdir=TD, ranksep=1, nodesep=0.2];'),
  writeln('edge  [arrowhead=vee arrowsize=0.6, constraint=true];'),
  writeln('node  [fontname=Helvetica,fontsize=10];'),
  nl.


% -----------------------
% Graph component: legend
% -----------------------

%! grapher:graph_legend(Type,Target)
%
% For a given ebuild, identified by an Id, create legend to be included in the full dependency graph.

grapher:graph_legend(Type,Repository://Id) :-
  config:graph_dependency_type(DepList),
  config:graph_proof_type(ProofList),
  length(DepList,DepLen),
  length(ProofList,ProofLen),
  grapher:graph_legend_header(DepLen,ProofLen),
  grapher:graph_legend_navigation(Type,Repository://Id),
  grapher:graph_legend_space,
  grapher:graph_legend_types(Type,DepList,Repository://Id),
  grapher:graph_legend_space,
  grapher:graph_legend_version(Type,Repository://Id),
  grapher:graph_legend_space,
  grapher:graph_legend_proof(Type,ProofList,Repository://Id),
  grapher:graph_legend_footer.


%! grapher:graph_legend_header(Deplen,Prooflen)
% 
% Create the header of the legend.

grapher:graph_legend_header(Deplen,Prooflen) :-
  write('graph [labelloc=t, labeljust=l, fontcolor=blue, fontname=Helvetica, fontsize=10, label='),
  write('<<TABLE BORDER=\'0\' CELLBORDER=\'1\' CELLSPACING=\'0\' CELLPADDING=\'6\'><TR>'),
  write('<TD COLSPAN=\'3\'><FONT COLOR=\'black\'><B>navigation</B></FONT></TD>'),
  write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
  write('<TD COLSPAN=\''),write(DepLen),write('\'><FONT COLOR=\'black\'><B>dependency graph</B></FONT></TD>'),
  write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
  write('<TD COLSPAN=\'4\'><FONT COLOR=\'black\'><B>version control</B></FONT></TD>'),
  write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
  write('<TD COLSPAN=\''),write(ProofLen),write('\'><FONT COLOR=\'black\'><B>command line</B></FONT></TD>'),
  write('</TR><TR>'),

%! grapher:graph_legend_space
% 
% Create a space in the legend.

grapher:graph_legend_space :- 
  write('<TD BORDER=\'0\'></TD>').


%! grapher:graph_legend_footer
% 
% Create the footer of the legend.

grapher:graph_legend_footer :- 
  write('</TR></TABLE>>];'),nl,
  nl.


%! grapher:graph_legend_navigation(Type,Repository://Id)
%
% Show a navigation pane in the legend enabling navigation to the repository, category or package index page.

grapher:graph_legend_navigation(_Type,Repository://Id) :-
  cache:ordered_entry(Repository,Id,Category,Name,_),
  grapher:graph_legend_href(index_repository,Repository://Id,Repository),
  grapher:graph_legend_href(index_category,Repository://Id,Category),
  grapher:graph_legend_href(index_package,Repository://Id,Name).


%! grapher:graph_legend_types(Type,List,Repository://Id)
%
% For a given ebuild, identified by an Id, create revelevant legend entries (as represented by List) to be included in the legend
% of a dependency graph. (detail, bdepend, cdepend, depend, idepend, rdepend, pdepend)

grapher:graph_legend_types(_Type,[],_Repository://_Id) :- !.

grapher:graph_legend_types(Type,[Type|Rest],Repository://Id) :-
  !,
  atomic_list_concat(['<u>',Type,'</u>'],Name),
  grapher:graph_legend_href(Type,Repository://Id,Name),
  grapher:graph_legend_types(Type,Rest,Repository://Id).

grapher:graph_legend_types(Type,[OtherType|Rest],Repository://Id) :-
  !,
  grapher:graph_legend_href(OtherType,Repository://Id,OtherType),
  grapher:graph_legend_types(Type,Rest,Repository://Id).


%! grapher:graph_legend_version(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, create version control bar to be included in legend. Enables
% changing the version of the ebuild graph shown.

grapher:graph_legend_version(Type,Repository://Id) :-
  query:search([category(C),name(N),select(version,equal,V)],Repository://Id),
  findall(E,query:search([category(C),name(N),select(version,greater,V)],Repository://E),Eg),
  findall(E,query:search([category(C),name(N),select(version,smaller,V)],Repository://E),Es),
  (last(Eg,Newer)          ; Newer  = []),!,
  (last(Es,Oldest)         ; Oldest = []),!,
  (once(member(Newest,Eg)) ; Newest = []),!,
  (once(member(Older,Es))  ; Older  = []),!,
  grapher:graph_legend_href(Type,Repository://Newest,'&lt;&lt; newest'),
  grapher:graph_legend_href(Type,Repository://Newer,'&lt; newer'),
  grapher:graph_legend_href(Type,Repository://Older,'older &gt;'),
  grapher:graph_legend_href(Type,Repository://Oldest,'oldest &gt;&gt;').


%! grapher:graph_legend_proof(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, create links to proofs to be included in legend.

grapher:graph_legend_proof(_Type,[],_Repository://_Id) :- !.

grapher:graph_legend_proof(Type,[Type|Rest],Repository://Id) :-
  !,
  atomic_list_concat(['--<u>',Type,'</u>&nbsp;'],Name),
  grapher:graph_legend_href(Type,Repository://Id,Name),
  grapher:graph_legend_proof(Type,Rest,Repository://Id).

grapher:graph_legend_proof(Type,[OtherType|Rest],Repository://Id) :-
  !,
  atomic_list_concat(['--',OtherType,'&nbsp;'],Name),
  grapher:graph_legend_href(OtherType,Repository://Id,Name),
  grapher:graph_legend_proof(Type,Rest,Repository://Id).


%! grapher:graph_legend_href(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, return the correct href URL to be included in the legend of a depedency graph

grapher:graph_legend_href(_,_://[],Name) :-
  !,
  write('<TD><FONT color=\"gray\">'),write(Name),write('</FONT></TD>').

grapher:graph_legend_href(repository,_Repository://_Id,Name) :-
  !,
  write('<TD><FONT color=\"gray\">'),write(Name),write('</FONT></TD>').

grapher:graph_legend_href(category,_Repository://_Id,Name) :-
  !,
  write('<TD><FONT color=\"gray\">'),write(Name),write('</FONT></TD>').

grapher:graph_legend_href(package,_Repository://_Id,Name) :-
  !,
  write('<TD><FONT color=\"gray\">'),write(Name),write('</FONT></TD>').

grapher:graph_legend_href(merge,Repository://Id,Name) :-
  !,
  write('<TD title=\"'),write(Repository://Id),write('\" href=\"../'),write(Id),write('-merge.svg'),write('\">'),write(Name),write('</TD>').

grapher:graph_legend_href(fetchonly,Repository://Id,Name) :-
  !,
  write('<TD title=\"'),write(Repository://Id),write('\" href=\"../'),write(Id),write('-fetchonly.svg'),write('\">'),write(Name),write('</TD>').

grapher:graph_legend_href(info,Repository://Id,Name) :-
  !,
  write('<TD title=\"'),write(Repository://Id),write('\" href=\"../'),write(Id),write('-info.svg'),write('\">'),write(Name),write('</TD>').

grapher:graph_legend_href(detail,Repository://Id,Name) :-
  !,
  write('<TD title=\"'),write(Repository://Id),write('\" href=\"../'),write(Id),write('.svg'),write('\">'),write(Name),write('</TD>').

grapher:graph_legend_href(index_repository,_Repository://_Id,Name) :-
  !,
  write('<TD title=\"repository\" href=\"../index.html\">'),write(Name),write('</TD>').

grapher:graph_legend_href(index_category,_Repository://_Id,Name) :-
  !,
  write('<TD title=\"repository\" href=\"./index.html\">'),write(Name),write('</TD>').

grapher:graph_legend_href(index_package,_Repository://_Id,Name) :-
  !,
  write('<TD title=\"repository\" href=\"./'),write(Name),write('.html\">'),write(Name),write('</TD>').

grapher:graph_legend_href(Depend,Repository://Id,Name) :-
  !,
  write('<TD title=\"'),write(Repository://Id),write('\" href=\"../'),write(Id),write('-'),write(Depend),write('.svg'),write('\">'),write(Name),write('</TD>').


% --------------------------
% Graph subcomponent: detail
% --------------------------

%! grapher:graph_ebuild(detail,Repository://Id)
%
% For a given ebuild, identified by an Id, create leftmost column showing ebuild information in the detail dependency graph.

grapher:graph_ebuild(detail,Repository://Id) :-
  !,
  writeln('# **********'),
  writeln('# The ebuild'),
  writeln('# **********'),
  nl,
  write('subgraph cluster_leftcol {'),nl,
  write('fontcolor=gray;'),nl,
  write('label=<<i>ebuild</i>>;'),nl,
  write('labelloc=t;'),nl,
  write('labeljust=c;'),nl,
  write('id [label=\"'),write(Repository://Id),write('\", color=red, width=4, penwidth=2, fontname=\"Helvetica-Bold\", href=\"../'),write(Id),write('.svg\"];'),nl,
  write('}'),nl,
  nl.


%! grapher:graph_detail(detail,Repository://Id)
%
% For a given ebuild, represented by Id, graph its compile and runtime dependencies.

grapher:graph_detail(detail,Repository://Id) :-
  !,
  writeln('# ****************'),
  writeln('# The dependencies'),
  writeln('# ****************'),
  nl,
  write('subgraph cluster_midcol {'),nl,
  write('fontcolor=gray;'),nl,
  write('label=<<i>dependencies</i>>;'),nl,
  write('labelloc=t;'),nl,
  write('labeljust=c'),nl,
  query:search(all(dependency(C,install)),Repository://Id),
  query:search(all(dependency(R,run)),Repository://Id),
  list_to_ord_set(C,OC),
  list_to_ord_set(R,OR),
  ord_intersection(OC,OR,OCR,OPR),
  ord_intersection(OR,OC,OCR,OPC),
  write('subgraph cluster_install {'),nl,
  write('fillcolor="#eeeeee";'),nl,
  write('style=filled;'),nl,
  write('label=<<i>install</i>>;'),nl,
  findall(Ch,(member(D,OPC),grapher:handle(detail,solid,vee,id,D,Ch)),AllChoices1),
  write('}'),nl,
  write('subgraph cluster_install_and_run {'),nl,
  write('fillcolor="#eeeeee";'),nl,
  write('style=filled;'),nl,
  write('label=<<i>install and run</i>>;'),nl,
  findall(Ch,(member(D,OCR),grapher:handle(detail,solid,odotvee,id,D,Ch)),AllChoices2),
  write('}'),nl,
  write('subgraph cluster_run {'),nl,
  write('fillcolor="#eeeeee";'),nl,
  write('style=filled;'),nl,
  write('label=<<i>run</i>>;'),nl,
  findall(Ch,(member(D,OPR),grapher:handle(detail,solid,odot,id,D,Ch)),AllChoices3),
  write('}'),nl,
  union(AllChoices1,AllChoices2,AllChoices12),
  union(AllChoices12,AllChoices3,AllChoices),
  write('}'),nl,
  nl,
  grapher:graph_candidates(detail,AllChoices).


%! grapher:graph_candidates(details,AllChoices)
%
% For a given set of dependency choices, graph the corresponding candidates.

grapher:graph_candidates(detail,AllChoices) :-
  !,
  writeln('# **************'),
  writeln('# The candidates'),
  writeln('# **************'),
  nl,
  write('subgraph cluster_choices {'),nl,
  write('rank=same;'),nl,
  write('fontcolor=gray;'),nl,
  write('label=<<i>candidates</i>>;'),nl,
  write('labelloc=t;'),nl,
  write('labeljust=c'),nl,
  nl,
  grapher:choices(detail,AllChoices),
  write('}'),nl.


% ---------------------
% Graph component: root
% ---------------------

%! grapher:graph_root(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, create the root of the full dependency graph.

grapher:graph_root(Type,_Repository://_Id) :-
  config:graph_proof_type(Types),
  memberchk(Type,Types),!,
  write('root [style=invis];'),nl,
  write('placeholder [style=invis, width=22, height=15];'),nl, % enough space to put an iframe with html inside
  write('root -> \"'),write(placeholder),write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'),nl,
  nl.

grapher:graph_root(_Type,Repository://Id) :-
  write('root [style=invis];'),nl,
  write('root -> \"'),write(Repository://Id),write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'),nl,
  nl.



% ---------------------
% Graph component: tree
% ---------------------

%! grapher:graph_tree(Type,Repository://Id),
%
% For a given ebuild, identified by an Id, create the full dependency graph

grapher:graph_tree(Type,Repository://Id) :-
  retractall(graph_visited(_)),
  grapher:graph_tree(Type,Repository://Id,Repository://Id),
  retractall(graph_visited(_)).


%! grapher:graph_tree(Type,Repository://RootId,Repository://Id)
%
% For a given ebuild, identified by an Id, create the full dependency graph

grapher:graph_tree(Type,RootRep://RootId,Repository://Id) :-
  \+(graph_visited(Repository://Id)),!,
  grapher:graph_node(Type,RootRep://RootId,Repository://Id),
  Statement =.. [Type,DS],
  query:search(all(Statement),Repository://Id),
  findall(Ch,(member(D,DS),grapher:handle(Type,solid,vee,Repository://Id,D,Ch)),AllChoices),
  assertz(graph_visited(Repository://Id)),
  grapher:choices(Type,AllChoices),
  forall(member(arrow(_,[Repository://Chs:_]),AllChoices),
    grapher:graph_tree(Type,RootRep://RootId,Repository://Chs)).

grapher:graph_tree(_,_,Repository://Id) :-
  graph_visited(Repository://Id),!.


%! grapher:graph_node(Type,Repository://RootId,Repository://Id)
%
% For a given ebuild, create its node in the full dependency graph

grapher:graph_node(Type,Repository://Id,Repository://Id) :-
  !,
  write('\"'),write(Repository://Id),write('\" [color=red, penwidth=2, fontname=\"Helvetica-Bold\", href=\"../'),write(Id),write('-'),write(Type),write('.svg\"];'),nl.

grapher:graph_node(Type,_://_,Repository://Id) :-
  !,
  write('\"'),write(Repository://Id),write('\" [color=red, penwidth=1, href=\"../'),write(Id),write('-'),write(Type),write('.svg\"];'),nl.


% -----------------------
% Graph component: footer
% -----------------------

%! grapher:graph_footer(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, create the footer of the full dependency graph.

grapher:graph_footer(_Type,_Repository://_Id) :-
  write('}'),nl.


% -------
% Helpers
% -------

%! grapher:choices(Type,List)
%
% Given a graph type outputs a list of ebuilds satisfying a dependency, while writing
% dot representing the different choices in the graph type format to the output stream.

grapher:choices(_,[]) :-
  !,true.

grapher:choices(detail,[arrow(D,Choices)|Rest]) :-
  !,
  write('subgraph '),write(' {'),nl,
  write('color=black;'),nl,
  write('nodesep=1;'),nl,
  forall(member(Repository://Ch,Choices),(
    write('\"'),write(Ch),write('\"'),
    write(' [label=\"'),write(Repository://Ch),write('\", color=red, width=4,href=\"../'),write(Ch),write('.svg\"];'),nl)),
  forall(member(Repository://Ch,Choices),(
    write(D),
    write(':e -> '),
    write('\"'),write(Ch),write('\"'),write(':w [style=dotted,weight=\"100\"];'),nl)),
  writeln('}'),
  grapher:choices(detail,Rest).

grapher:choices(Deptype,[arrow(D,[Repository://Choice:Type])|Rest]) :-
  !,
  write('\"'),write(D),write('\"'),
  write(' -> '),
  write('\"'),write(Repository://Choice),write('\"'),
  grapher:choice_type(Type),
  nl,
  grapher:choices(Deptype,Rest).

grapher:choices(Kind,[L|Rest]) :-
  \+L =..[arrow,_,_],
  !,
  grapher:choices(Kind,L),
  grapher:choices(Kind,Rest).


%! grapher:choice_type(Type)
%
% Correctly set attributes for strong and weak blockers

grapher:choice_type(no) :-
  !.

grapher:choice_type(weak) :-
  write(' [style=dashed, color=orange];').

grapher:choice_type(strong) :-
  write(' [style=dashed, color=red];').


% ----------------------
% Node and edge handling
% ----------------------

%! grapher:handle(+Type,+Style,+ArrowStyle,+Master,+Dependency,-Output)
%
% For a given graph style, create a meta representation of a dependency

% Common table attributes

grapher:format_table_attrs(F) :-
  F = "BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"".

% Edge format

grapher:format_edge_attrs(Master, D, Style, Arrow, Color, Weight) :-
  format("~w:e -> ~w:w [weight=~w, ~wstyle=\"~w\",arrowhead=\"~w\"];~n",
         [Master, D, Weight, Color, Style, Arrow]).

% Package dependency html node format

grapher:format_package_dep(D, Label, Type, Cat, Name, Cmpr, Ver, Color, Width) :-
  grapher:format_table_attrs(F),
  format("~w [label=<<TABLE ~w WIDTH=\"~w\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">~w</TD></TR>
                     <TR><TD WIDTH=\"110\">~w</TD></TR><TR><TD>~w</TD></TR><TR><TD>~w</TD></TR>
                     <TR><TD>~w</TD></TR><TR><TD>~w</TD></TR></TABLE>>, shape=none, color=~w];~n",
             [D, F, Width, Label, Type, Cat, Name, Cmpr, Ver, Color]).

% Group html node format

grapher:format_group(D, Label, Color) :-
  grapher:format_table_attrs(F),
  format("~w [label=<<TABLE ~w><TR><TD CELLPADDING=\"10\">~w</TD></TR></TABLE>>, shape=none, color=~w];~n",
         [D, F, Label, Color]).


% Detail graph - Case: Package dependency

grapher:handle(detail, Style, Arrow, Master, package_dependency(_, Type, Strength, Cat, Name, Cmpr, Ver, _, _), arrow(D, Choices)) :-
  !,
  ( Strength = no,     Label = "pack_dep",          Color = blue,   Sym = package_dependency, EdgeColor = ""
  ; Strength = weak,   Label = "blocking (weak)",   Color = orange, Sym = weak_blocker,       EdgeColor = "color=\"orange\", "
  ; Strength = strong, Label = "blocking (strong)", Color = red,    Sym = strong_blocker,     EdgeColor = "color=\"red\", "
  ),
  write("subgraph  {"), nl,
  tl_gensym(Sym, D),
  grapher:format_package_dep(D, Label, Type, Cat, Name, Cmpr, Ver, Color, 220),
  write("}"), nl,
  grapher:format_edge_attrs(Master, D, Style, Arrow, EdgeColor, 20),
  findall(R, query:search([name(Name), category(Cat), select(version, Cmpr, Ver)], R), Choices).


% Detail graph - Case: Use conditional group

grapher:handle(detail, Style, Arrow, Master, use_conditional_group(Type, Use, _, Deps), Choices) :-
  !,
  grapher:format_table_attrs(F),
  write("subgraph  {"), nl,
  tl_gensym(use_conditional_group, D),
  format("~w [label=<<TABLE ~w><TR><TD ROWSPAN=\"3\" CELLPADDING=\"10\">use_conditional</TD></TR>
          <TR><TD>~w</TD></TR><TR><TD>~w</TD></TR></TABLE>>, shape=none, color=red];~n",
         [D, F, Type, Use]),
  findall(Ch, (member(Dep, Deps), grapher:handle(detail, dashed, vee, D, Dep, Ch)), Choices),
  write("}"), nl,
  grapher:format_edge_attrs(Master, D, Style, Arrow, "", 20).


% Detail graph - Case: Any_of, all_of, exactly_one_of and at_most_one_of group

grapher:handle(detail, Style, Arrow, Master, Group, Choices) :-
  Group =.. [Type, Deps],
  member(Type, [any_of_group, all_of_group, exactly_one_of_group, at_most_one_of_group]),
  !,
  write("subgraph  {"), nl,
  tl_gensym(Type, D),
  grapher:format_group(D, Type, red),
  (   Type = any_of_group, SubStyle = dotted, SubArrow = oinv
  ;   Type = all_of_group, SubStyle = solid, SubArrow = inv
  ;   Type = exactly_one_of_group, SubStyle = dotted, SubArrow = tee
  ;   Type = at_most_one_of_group, SubStyle = dotted, SubArrow = onormal
  ),
  findall(Ch, (member(Dep, Deps), grapher:handle(detail, SubStyle, SubArrow, D, Dep, Ch)), Choices),
  write("}"), nl,
  grapher:format_edge_attrs(Master, D, Style, Arrow, "", 20).


% Detail graph - Case: Unknown dependency

grapher:handle(detail, _, _, Master, S, []) :-
  !,
  format("# *** UNKNOWN DEPENDENCY TYPE (TODO) ***~n# ~w -> ~w~n# *** END ***~n~n", [Master, S]).


% Full graph - package dependency

grapher:handle(_, _, _, Mastercontext://Master, package_dependency(_, _, Strength, Cat, Name, Cmpr, Ver, _, _),
  arrow(Mastercontext://Master, [Choicecontext://Choice:Strength])) :-
  query:search([name(Name), category(Cat), select(version, Cmpr, Ver)], Choicecontext://Choice), !.


% Full tree - different groups

grapher:handle(_, _, _, _, Group, []) :-
  member(Group, [use_conditional_group(_, _, _, _),
                 any_of_group(_),
                 all_of_group(_),
                 exactly_one_of_group(_),
                 at_most_one_of_group(_)]), !.

% Catch-all

grapher:handle(_, _, _, _, _, []) :- !.


% -------------
% Graph helpers
% -------------

%! grapher:tl_gensym(Atom,AtomCount)
%
% Thread-local implementation of gensym counter

grapher:tl_gensym(Atom,AtomCount) :-
  \+ counter(Atom,_),!,
  assert(counter(Atom,1)),
  atomic_concat(Atom,1,AtomCount).

grapher:tl_gensym(Atom,AtomCount) :-
  retract(counter(Atom,Count)),
  NewCount is Count + 1,
  assertz(counter(Atom,NewCount)),
  atomic_concat(Atom,NewCount,AtomCount).

grapher:tl_gensym_reset(Atom) :-
  retractall(counter(Atom,_)).


% -----------------
% Graph file output
% -----------------

%! grapher:write_graph_file(+Directory,+Repository://Entry)
%
% Create graphviz dot file(s) for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

grapher:write_graph_file(D,Repository://Entry) :-
  config:graph_dependency_type(Deptypes),
  config:graph_proof_type(Prooftypes),
  append(Deptypes,Prooftypes,Types),
  (forall(member(Type,Types),
      ((Type == detail
        -> atomic_list_concat([D,'/',Entry,'.dot'],F)
        ;  atomic_list_concat([D,'/',Entry,'-',Type,'.dot'],F)),
       tell(F),
       (grapher:graph(Type,Repository://Entry)
        -> told
        ;  (told,message:warning([Repository://Entry,' ',Type])))))).


%! printer:write_graph_files(+Directory,+Repository)
%
% Create graphviz dot file(s) for all entries in a repository
% Assumes directory exists. (See repository:prepare_directory)

grapher:write_graph_files(Directory,Repository) :-
  tester:test(parallel_verbose,
              'Writing graphs for',
              Repository://Entry,
              (Repository:entry(Entry),
               (config:graph_modified_only(true)
                -> Repository:entry(Entry,Time),
                   Repository:get_ebuild_file(Entry,Ebuild),
                   system:exists_file(Ebuild),
                   system:time_file(Ebuild,Modified),
                   Modified > Time
                ;  true)),
              (grapher:write_graph_file(Directory,Repository://Entry))).


% ------------------------------
% Graph conversion script caller
% ------------------------------

%! grapher:produce_svg(+Directory)
%
% For a given directory with dot files, convert the dot files into interactive
% scalable vector graphics (SVG).

grapher:produce_svg(Directory) :-
  message:scroll_notice(['Now running Graphviz dot...']),
  script:exec(graph,['dot',Directory]),
  message:scroll_notice(['Done running Graphviz dot.']),
  message:sc.


% -------
% Testers
% -------

%! grapher:test(+Repository)
%
% Outputs dot file for every entry in a given repository, reports using the default reporting style

grapherr:test(Repository) :-
  config:test_style(Style),
  grapher:test(Repository,Style).


%! grapher:test(+Repository,+Style)
%
% Outputs dot file for  every entry in a given repository, reports using a given reporting style

grapher:test(Repository,Style) :-
  config:graph_dependency_type(D),
  config:graph_proof_type(P),
  tester:test(Style,
              'Graphing',
              Repository://Entry,
              Repository:entry(Entry),
              (forall(member(I,D),
               with_output_to(string(_),grapher:graph(I,Repository://Entry))),
               forall(member(I,P),
               with_output_to(string(_),grapher:graph(I,Repository://Entry))))).


%! grapher:test_latest(+Repository)
%
% Same as grapher:test(+Repository), but only tests highest version of every package

grapher:test_latest(Repository) :-
  !,
  grapher:test_latest(Repository,parallel_verbose).

grapher:test_latest(Repository,Style) :-
  config:graph_dependency_type(D),
  config:graph_proof_type(P),
  tester:test(Style,
              'Graphing',
              Repository://Entry,
              (Repository:package(C,N),once(Repository:ebuild(Entry,C,N,_))),
              (forall(member(I,D),
               with_output_to(string(_),grapher:graph(I,Repository://Entry))),
               forall(member(I,P),
               with_output_to(string(_),grapher:graph(I,Repository://Entry))))).
