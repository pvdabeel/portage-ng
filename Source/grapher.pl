/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GRAPHER
This file contains predicates that convert:

 - ebuilds into DOT language directed graphs showing ebuild dependencies in detail
 - ebuilds into DOT language directed graphs showing full dependency tree for the
   different dependency types

We have can output two type of graphs: High level tree diagrams or detailled
graphs showing, for a given ebuild, all dependencies and the ebuilds that
could satisfy the dependency.
*/

:- module(grapher, []).

:- thread_local graph_visited/1.
:- thread_local counter/2.

% ********************
% GRAPHER declarations
% ********************


%! grapher:graph(Type,Repository://Id)
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
  grapher:graph_detail(details,Repository://Id),
  grapher:graph_footer(details,Repository://Id).

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


%! grapher:graph(repository,Repository://Category)
%
% For a given repository, create a dot graph showing all categories

grapher:graph(repository,Repository) :-
  !,
  grapher:graph_header(repository,Repository://_),
  grapher:graph_legend(repository,Repository://_),
  grapher:graph_root(repository,Repository://_),
  grapher:graph_footer(repository,Repository://_).


%! grapher:graph(category,Repository://Category)
%
% For a given category of a repository, create a dot graph showing all packages

grapher:graph(category,Repository://Category) :-
  !,
  grapher:graph_header(category,Repository://Category),
  grapher:graph_legend(category,Repository://Category),
  grapher:graph_root(category,Repository://Category),
  grapher:graph_footer(category,Repository://Category).


%! grapher:graph(package,Repository://Package)
%
% For a given package in a category in a repository, create a dot graph showing all ebuilds

grapher:graph(package,Repository://Package) :-
  !,
  grapher:graph_header(package,Repository://Package),
  grapher:graph_legend(package,Repository://Package),
  grapher:graph_root(package,Repository://Package),
  grapher:graph_tree(package,Repository://Package),
  grapher:graph_footer(package,Repository://Package).


%! grapher:graph_header(Type,Repository://Id)
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


%! grapher:graph_legend(Type,Target)
%
% For a given ebuild, identified by an Id, create legend to be included in the full dependency graph.

grapher:graph_legend(Type,Repository://Id) :-
  config:graph_dependency_type(DepList),
  config:graph_proof_type(ProofList),
  length(DepList,DepLen),
  length(ProofList,ProofLen),
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
  grapher:graph_legend_navigation(Type,Repository://Id),
  write('<TD BORDER=\'0\'></TD>'),
  grapher:graph_legend_types(Type,DepList,Repository://Id),
  write('<TD BORDER=\'0\'></TD>'),
  grapher:graph_legend_version(Type,Repository://Id),
  write('<TD BORDER=\'0\'></TD>'),
  grapher:graph_legend_proof(Type,ProofList,Repository://Id),
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
% of a dependency graph.

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
% For a given ebuild, identified by an Id, create version control bar to be included in legend.

grapher:graph_legend_version(Type,Repository://_Id) :-
  memberchk(Type,[repository,category,package]),!,
  Newer  = [],
  Oldest = [],
  Newest = [],
  Older  = [],
  grapher:graph_legend_href(Type,Repository://Newest,'&lt;&lt; newest'),
  grapher:graph_legend_href(Type,Repository://Newer,'&lt; newer'),
  grapher:graph_legend_href(Type,Repository://Older,'older &gt;'),
  grapher:graph_legend_href(Type,Repository://Oldest,'oldest &gt;&gt;').

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
  write('labeljust=c'),nl,
  write('id [label=\"'),write(Repository://Id),write('\", color=red, width=4, penwidth=2, fontname=\"Helvetica-Bold\", href=\"../'),write(Id),write('.svg\"];'),nl,
  write('}'),nl,
  nl.


%! grapher:graph_details(details,Repository://Id)
%
% For a given ebuild, represented by Id, graph its details (compile & runtime dependencies, corresponding candidates)
%
% todo: refactor, this needs to be shorter

grapher:graph_detail(details,Repository://Id) :-
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
  writeln('subgraph cluster_install {'),
  writeln('fillcolor="#eeeeee";'),
  writeln('style=filled;'),
  writeln('label=<<i>install</i>>;'),
  findall(Ch,(member(D,OPC),grapher:handle(detail,solid,vee,id,D,Ch)),AllChoices1),
  writeln('}'),
  writeln('subgraph cluster_install_and_run {'),
  writeln('fillcolor="#eeeeee";'),
  writeln('style=filled;'),
  writeln('label=<<i>install and run</i>>;'),
  findall(Ch,(member(D,OCR),grapher:handle(detail,solid,odotvee,id,D,Ch)),AllChoices2),
  writeln('}'),
  writeln('subgraph cluster_run {'),
  writeln('fillcolor="#eeeeee";'),
  writeln('style=filled;'),
  writeln('label=<<i>run</i>>;'),
  findall(Ch,(member(D,OPR),grapher:handle(detail,solid,odot,id,D,Ch)),AllChoices3),
  writeln('}'),
  union(AllChoices1,AllChoices2,AllChoices12),
  union(AllChoices12,AllChoices3,AllChoices),
  write('}'),nl,
  nl,
  writeln('# **************'),
  writeln('# The candidates'),
  writeln('# **************'),
  nl,
  writeln('subgraph cluster_choices {'),
  writeln('rank=same;'),
  writeln('fontcolor=gray;'),
  write('label=<<i>candidates</i>>;'),nl,
  write('labelloc=t;'),nl,
  write('labeljust=c'),nl,
  nl,
  grapher:choices(detail,AllChoices),
  writeln('}').


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

grapher:graph_root(repository,Repository://_Id) :-
  write('root [style=invis];'),nl,
  write(Repository),write(' [color=red, penwidth=2, fontname=\"Helvetica-Bold\"];'),nl,
  write('root -> \"'),write(Repository),write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'),nl,
  nl.

grapher:graph_root(_Type,Repository://Id) :-
  write('root [style=invis];'),nl,
  write('root -> \"'),write(Repository://Id),write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'),nl,
  nl.


%! grapher:graph_root(Type,Repository://Id)
%
% For a given ebuild, identified by an Id, create the footer of the full dependency graph.

grapher:graph_footer(_Type,_Repository://_Id) :-
  write('}'),nl.


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
  query:search(all(Statement),Repository://Id), % todo: this does not get optimized by the compiler
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


%! grapher:choices(Type,List)
%
% Given a graph type (detail or full), outputs a list of ebuilds satisfying
% a dependency

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


grapher:choice_type(no) :-
  !.

grapher:choice_type(weak) :-
  write(' [style=dashed, color=orange];').

grapher:choice_type(strong) :-
  write(' [style=dashed, color=red];').


%! grapher:handle(+Type,+Style,+ArrowStyle,+Master,+Dependency,-Output)
%
% For a given graph style, create a meta representation of a dependency

% detail tree graphing
%
% todo: refactor, this needs to be shorter

grapher:handle(detail,Style,Arrow,Master,package_dependency(_,Type,no,Cat,Name,Comp,Ver,_Slot,_Bwu),arrow(D,Choices)) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(package_dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" WIDTH=\"220\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">pack_dep</TD></TR><TR><TD WIDTH=\"110\">'),
  write(Type),write('</TD></TR><TR><TD>'),write(Cat),write('</TD></TR><TR><TD>'),write(Name),write('</TD></TR><TR><TD>'),
  write(Comp),write('</TD></TR><TR><TD>'),write(Ver),write('</TD></TR></TABLE>>, shape=none, color=blue];'),nl,
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl,
  findall(R,query:search([select(name,equal,Name),select(category,equal,Cat),select(version,Comp,Ver)],R),Choices),
  !, true.

grapher:handle(detail,Style,Arrow,Master,package_dependency(_,Type,weak,Cat,Name,Comp,Ver,_Slot,_Bwu),arrow(D,Choices)) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(package_dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" WIDTH=\"220\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">blocking (weak)</TD></TR><TR><TD WIDTH=\"110\">'),
  write(Type),write('</TD></TR><TR><TD>'),write(Cat),write('</TD></TR><TR><TD>'),write(Name),write('</TD></TR><TR><TD>'),
  write(Comp),write('</TD></TR><TR><TD>'),write(Ver),write('</TD></TR></TABLE>>, shape=none, color=orange];'),nl,
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20, color="orange", style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl,
  findall(R,query:search([select(name,equal,Name),select(category,equal,Cat),select(version,Comp,Ver)],R),Choices),
  !, true.

grapher:handle(detail,Style,Arrow,Master,package_dependency(_,Type,strong,Cat,Name,Comp,Ver,_Slot,_Bwu),arrow(D,Choices)) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(package_dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" WIDTH=\"220\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">blocking (strong)</TD></TR><TR><TD WIDTH=\"110\">'),
  write(Type),write('</TD></TR><TR><TD>'),write(Cat),write('</TD></TR><TR><TD>'),write(Name),write('</TD></TR><TR><TD>'),
  write(Comp),write('</TD></TR><TR><TD>'),write(Ver),write('</TD></TR></TABLE>>, shape=none, color=red];'),nl,
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20, color="red", style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl,
  findall(R,query:search([select(name,equal,Name),select(category,equal,Cat),select(version,Comp,Ver)],R),Choices),
  !, true.

grapher:handle(detail,Style,Arrow,Master,use_conditional_group(Type,Use,_,Deps),Choices) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(use_conditional_group,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD ROWSPAN=\"3\" CELLPADDING=\"10\">use_conditional</TD></TR><TR><TD>'),write(Type),write('</TD></TR><TR><TD>'),write(Use),
  write('</TD></TR></TABLE>>, shape=none, color=red];'),nl,
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dashed,vee,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,any_of_group(Deps),Choices) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(any_of_group,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">any_of_group</TD></TR></TABLE>>, shape=none, color=red];'),% nl, % nl
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dotted,oinv,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,all_of_group(Deps),Choices) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(all_of_group,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">all_of_group</TD></TR></TABLE>>, shape=none, color=red];'),% nl, % nl
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,solid,inv,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,exactly_one_of_group(Deps),Choices) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(exactly_one_of_group,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">exactly_one_of_group</TD></TR></TABLE>>, shape=none, color=red];'), % nl, % nl,
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dotted,tee,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,at_most_one_of_group(Deps),Choices) :-
  !,
  write('subgraph '),write(' {'),nl,
  tl_gensym(at_most_one_of_group,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">at_most_one_of_group</TD></TR></TABLE>>, shape=none, color=red];'), %nl, % nl,
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dotted,onormal,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,_Style,_Arrow,Master,S,[]) :-
  !,
  writeln('# *** BEGIN UNKNOWN DEPENDENCY TYPE (TODO) ***'),
  write('# '),write(Master), write(' -> '), write(S),nl,
  writeln('# *** END UNKNOWN DEPENDENCY TYPE (TODO) ***'),
  nl.

% Full tree graphing

grapher:handle(_Deptype,_Style,_Arrow,Mastercontext://Master,package_dependency(_,_,no,Cat,Name,Comp,Ver,_,_),arrow(Mastercontext://Master,[Choicecontext://Choice:no])) :-
  query:search([name(Name),category(Cat),select(version,Comp,Ver)],Choicecontext://Choice),
  !, true.

grapher:handle(_Deptype,_Style,_Arrow,Mastercontext://Master,package_dependency(_,_,weak,Cat,Name,Comp,Ver,_,_),arrow(Mastercontext://Master,[Choicecontext://Choice:weak])) :-
  query:search([name(Name),category(Cat),select(version,Comp,Ver)],Choicecontext://Choice),
  !, true.

grapher:handle(_Deptype,_Style,_Arrow,Mastercontext://Master,package_dependency(_,_,strong,Cat,Name,Comp,Ver,_,_),arrow(Mastercontext://Master,[Choicecontext://Choice:strong])) :-
  query:search([name(Name),category(Cat),select(version,Comp,Ver)],Choicecontext://Choice),
  !, true.

grapher:handle(_Deptype,_Style,_Arrow,_Master,use_conditional_group(_,_Type,_Use,_Deps),[]) :- !.

grapher:handle(_Deptype,_Style,_Arrow,_Master,any_of_group(_),[]) :- !.

grapher:handle(_Deptype,_Style,_Arrow,_Master,all_of_group(_),[]) :- !.

grapher:handle(_Deptype,_Style,_Arrow,_Master,exactly_one_of_group(_),[]) :- !.

grapher:handle(_Deptype,_Style,_Arrow,_Master,at_most_one_of_group(_),[]) :- !.

grapher:handle(_Deptype,_Style,_Arrow,_Master,_,[]) :- !.


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


%! grapher:produce_svg(+Directory)
%
% For a given directory with dot files, convert the dot files into interactive
% scalable vector graphics (SVG).

grapher:produce_svg(Directory) :-
  message:scroll_notice(['Now running Graphviz dot...']),
  script:exec(graph,['dot',Directory]),
  message:scroll_notice(['Done running Graphviz dot.']),
  message:sc.


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
