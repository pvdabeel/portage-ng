/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GRAPHER
This file contains predicates that convert:

 - ebuilds into DOT language directed graphs showing ebuild dependencies in detail
 - ebuilds into DOT language directed graphs showing full dependency tree

We have can output two type of diagrams: High level tree diagrams or detailled
diagrams showing, for a given ebuild, all dependencies and the ebuilds that
could satisfy the dependency.
*/

:- module(grapher, []).

% ********************
% GRAPHER declarations
% ********************


%! grapher:graph(+Type,+Id)
%
% For a given ebuild, identified by an Id, create a Graphviz dot file

grapher:graph(detail,Repository://Id) :-
  writeln('digraph prolog {'),
  nl,
  writeln('# *************'),
  writeln('# Graph options'),
  writeln('# *************'),
  nl,
  writeln('newrank=true;'),
  writeln('concentrate=true;'),
  writeln('compound=true;'),
  writeln('graph [rankdir=LR,fontname=Helvetica,fontsize=10,ranksep=1.5];#, ranksep=2.5, nodesep=0.2];'),
  writeln('edge  [arrowhead=vee];'),
  writeln('node  [fontname=Helvetica,fontsize=10];'),
  nl,
  writeln('# **********'),
  writeln('# The ebuild'),
  writeln('# **********'),
  nl,
  write('subgraph cluster_leftcol {'),nl,
  write('color=gray;'),nl,
  write('rank=same;'),nl,
  write('label=<<i>ebuild</i>>;'),nl,
  write('id [label=\"'),write(Repository://Id),write('\", color=red, width=4, href=\"../'),write(Id),write('.svg\"];'),nl,
  write('}'),nl,
  nl,
  writeln('# ****************'),
  writeln('# The dependencies'),
  writeln('# ****************'),
  nl,
  write('subgraph cluster_midcol {'),nl,
  write('color=gray;'),nl,
  write('label=<<i>dependencies</i>>;'),nl,
  ebuild:get(depend,Repository://Id,C),
  ebuild:get(rdepend,Repository://Id,R),
  list_to_ord_set(C,OC),
  list_to_ord_set(R,OR),
  ord_intersection(OC,OR,OCR,OPR),
  ord_intersection(OR,OC,OCR,OPC),
  writeln('subgraph cluster_compile {'),
  writeln('fillcolor="#eeeeee";'),
  writeln('style=filled;'),
  writeln('label=<<i>compile</i>>;'),
  findall(Ch,(member(D,OPC),grapher:handle(detail,solid,vee,id,D,Ch)),AllChoices1),
  writeln('}'),
  writeln('subgraph cluster_compileandrun {'),
  writeln('fillcolor="#eeeeee";'),
  writeln('style=filled;'),
  writeln('label=<<i>compile and run</i>>;'),
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
  writeln('color=gray;'),
  write('label=<<i>candidates</i>>;'),nl,
  nl,
  grapher:choices(detail,AllChoices),
  writeln('}'),
  nl,
  writeln('}').


%! grapher:graph(+Type,+Id)
%
% For a given ebuild, identified by an Id, create a full dependency diagram.

grapher:graph(Type,Repository://Id) :-
  member(Type,[depend,rdepend]),!,
  writeln('digraph prolog {'),
  nl,
  writeln('newrank=true;'),
  writeln('concentrate=true;'),
  writeln('compound=true;'),
  writeln('graph [rankdir=TD];#, ranksep=2.5, nodesep=0.2];'),
  writeln('edge  [arrowhead=vee];'), % arrowsize=0.6 constraint= true
  writeln('node  [fontname=Helvetica,fontsize=10];'),
  nl,
  retractall(graph_visited(_)),
  grapher:write_tree(Repository://Id,Type),
  writeln('}'),
  retractall(graph_visited(_)).


%! grapher:write_tree(+Id)
%
% For a given ebuild, identified by an Id, create a tree diagram.

grapher:write_tree(Repository://Id, Type) :-
  not(graph_visited(Repository://Id)),!,
  write('\"'),write(Repository://Id),write('\" [color=red, href=\"../'),write(Id),write('-'),write(Type),write('.svg\"];'),nl,
  ebuild:get(Type,Repository://Id,DS),
  findall(Ch,(member(D,DS),grapher:handle(Type,solid,vee,Repository://Id,D,Ch)),AllChoices),
  assert(graph_visited(Repository://Id)),
  grapher:choices(Type,AllChoices),
  forall(member(arrow(_,[Chs]),AllChoices),
    grapher:write_tree(Chs,Type)).

grapher:write_tree(Repository://Id,_Type) :-
  graph_visited(Repository://Id),!.


%! grapher:enconvert(+Id,-Code)
%
% Create a unique name for a given ebuild.

grapher:enconvert(Repository://Id,Code) :-
  string_codes(Id,List),
  atomic_list_concat([choice,Repository|List],Code).


%! grapher:choices(+Type,+List)
%
% Given a graph type (detail or full), outputs a list of ebuilds satisfying
% a dependency

grapher:choices(_,[]) :-
  !,true.

grapher:choices(detail,[arrow(D,Choices)|Rest]) :-
  !,
  gensym(choice,C),
  write('subgraph '),write(C),write(' {'),nl,
  write('color=black;'),nl,
  write('nodesep=1;'),nl,
  forall(member(Repository://Ch,Choices),(
    grapher:enconvert(Repository://Ch,Code),
    write(Code),
    write(' [label=\"'),write(Repository://Ch),write('\", color=red, width=4,href=\"../'),write(Ch),write('.svg\"];'),nl)),
  forall(member(Ch,Choices),(
    write(D),
    write(':e -> '),
    grapher:enconvert(Ch,Code),
    write(Code),write(':w [style=dotted,weight=\"100\"];'),nl)),
  writeln('}'),
  grapher:choices(detail,Rest).

grapher:choices(depend,[arrow(D,[Choice])|Rest]) :-
  !,
  write('\"'),write(D),write('\"'),
  write(' -> '),
  write('\"'),write(Choice),write('\"'),nl,
  grapher:choices(depend,Rest).

grapher:choices(cdepend,[arrow(D,[Choice])|Rest]) :-
  !,
  write('\"'),write(D),write('\"'),
  write(' -> '),
  write('\"'),write(Choice),write('\"'),nl,
  grapher:choices(cdepend,Rest).

grapher:choices(rdepend,[arrow(D,[Choice])|Rest]) :-
  !,
  write('\"'),write(D),write('\"'),
  write(' -> '),
  write('\"'),write(Choice),write('\"'),nl,
  grapher:choices(rdepend,Rest).

grapher:choices(Kind,[L|Rest]) :-
  !,
  grapher:choices(Kind,L),
  grapher:choices(Kind,Rest).


%! grapher:handle(+Type,+Style,+ArrowStyle,+Master,+Dependency,-Output)
%
% For a given graph style, create a meta reprensentation of a dependency

grapher:handle(depend,_Style,_Arrow,Mastercontext://Master,package_dependency(_,_Type,Cat,Name,_Comp,_Ver,_,_),arrow(Mastercontext://Master,[Choicecontext://Choice])) :-
  cache:entry(Choicecontext,Choice,_,Cat,Name,_,_),
  !, true.

grapher:handle(depend,_Style,_Arrow,_Master,use_conditional_group(_Type,_Use,_Deps),[]) :- !.

grapher:handle(depend,_Style,_Arrow,_Master,any_of_group(_),[]) :- !.

grapher:handle(depend,_Style,_Arrow,_Master,all_of_group(_),[]) :- !.

grapher:handle(depend,_Style,_Arrow,_Master,exactly_one_of_group(_),[]) :- !.

grapher:handle(depend,_Style,_Arrow,_Master,at_most_one_of_group(_),[]) :- !.

grapher:handle(depend,_Style,_Arrow,_Master,_,[]) :- !.


grapher:handle(rdepend,_Style,_Arrow,Mastercontext://Master,package_dependency(_,_Type,Cat,Name,_Comp,_Ver,_,_),arrow(Mastercontext://Master,[Choicecontext://Choice])) :-
  cache:entry(Choicecontext,Choice,_,Cat,Name,_,_),
  !, true.

grapher:handle(rdepend,_Style,_Arrow,_Master,use_conditional_group(_Type,_Use,_Deps),[]) :- !.

grapher:handle(rdepend,_Style,_Arrow,_Master,any_of_group(_),[]) :- !.

grapher:handle(rdepend,_Style,_Arrow,_Master,all_of_group(_),[]) :- !.

grapher:handle(rdepend,_Style,_Arrow,_Master,exactly_one_of_group(_),[]) :- !.

grapher:handle(rdepend,_Style,_Arrow,_Master,at_most_one_of_group(_),[]) :- !.

grapher:handle(rdepend,_Style,_Arrow,_Master,_,[]) :- !.


grapher:handle(detail,Style,Arrow,Master,package_dependency(_,Type,Cat,Name,Comp,Ver,_,_),arrow(D,Choices)) :-
  !,
  gensym(pack,P),
  write('subgraph '),write(P),write(' {'),nl,
  gensym(dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" WIDTH=\"220\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">pack_dep</TD></TR><TR><TD WIDTH=\"110\">'),
  write(Type),write('</TD></TR><TR><TD>'),write(Cat),write('</TD></TR><TR><TD>'),write(Name),write('</TD></TR><TR><TD>'),
  write(Comp),write('</TD></TR><TR><TD>'),write(Ver),write('</TD></TR></TABLE>>, shape=none, color=blue];'),nl,
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl,
  % findall(R,portage:query([category(Cat),name(Name)],R),Choices),
  % atom_string(Cata,Cat),
  findall(Repository://R,cache:entry(Repository,R,_,Cat,Name,_,_),Choices),
  !, true.

grapher:handle(detail,Style,Arrow,Master,use_conditional_group(Type,Use,Deps),Choices) :-
  !,
  gensym(cond,C),
  write('subgraph '),write(C),write(' {'),nl,
  gensym(dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD ROWSPAN=\"3\" CELLPADDING=\"10\">use_conditional</TD></TR><TR><TD>'),write(Type),write('</TD></TR><TR><TD>'),write(Use),
  write('</TD></TR></TABLE>>, shape=none, color=red];'),nl,
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dashed,vee,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,any_of_group(Deps),Choices) :-
  !,
  gensym(any,A),
  write('subgraph '),write(A),write(' {'),nl,
  gensym(dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">any_of_group</TD></TR></TABLE>>, shape=none, color=red];'),% nl, % nl
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dotted,oinv,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,all_of_group(Deps),Choices) :-
  !,
  gensym(all,A),
  write('subgraph '),write(A),write(' {'),nl,
  gensym(dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">all_of_group</TD></TR></TABLE>>, shape=none, color=red];'),% nl, % nl
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,solid,inv,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,exactly_one_of_group(Deps),Choices) :-
  !,
  gensym(exactlyone,A),
  write('subgraph '),write(A),write(' {'),nl,
  gensym(dependency,D),
  write(D),write(' [label=<<TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"><TR><TD CELLPADDING=\"10\">exactly_one_of_group</TD></TR></TABLE>>, shape=none, color=red];'), % nl, % nl,
  findall(Ch,(member(Dep,Deps),grapher:handle(detail,dotted,tee,D,Dep,Ch)),Choices),
  write('}'),nl,
  write(Master),write(':e -> '),write(D),write(':w [weight=20,style="'),write(Style),write('",arrowhead="'),write(Arrow),write('"];'),nl.

grapher:handle(detail,Style,Arrow,Master,at_most_one_of_group(Deps),Choices) :-
  !,
  gensym(atmostone,A),
  write('subgraph '),write(A),write(' {'),nl,
  gensym(dependency,D),
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


%! grapher:test(+Repository)
%
% For a given 'eapi' repository, create Graphviz dot files in the graph
% directory for all ebuilds in the repository. Triggers a script to convert
% the dot files into interactive scalable vector graphics (SVG).
%
% When an SVG graph is opened in a modern browser, it will show for a given
% ebuild what dependencies that ebuild has. The SVG diagram will have links
% to ebuilds that can satisfy the dependency. Each ebuild linked to can be
% opened by clicking on it in the diagram, enabling manual dependency graph
% traversal to debug issues with ebuild dependencies.

grapher:prepare_directory(D,Repository) :-
  config:graph_directory(D),
  system:exists_directory(D),!,
  message:inform(['Directory already exists! Updating...']),
  os:update_repository_dirs(Repository,D).

grapher:prepare_directory(D,Repository) :-
  config:graph_directory(D),
  not(system:exists_directory(D)),!,
  os:make_repository_dirs(Repository,D).

grapher:write_dot_files(D,Repository://Id) :-
  message:success(Id),
  atomic_list_concat([D,'/',Id,'.dot'],Fdetail),
  tell(Fdetail),
  grapher:graph(detail,Repository://Id),
  told.
%  atomic_list_concat([D,'/',Id,'-depend.dot'],Fdepend),
%  tell(Fdepend),
%  grapher:graph(depend,Repository://Id),
%  told,
%  atomic_list_concat([D,'/',Id,'-rdepend.dot'],Frdepend),
%  tell(Frdepend),
%  grapher:graph(rdepend,Repository://Id),
%  told.


%! grapher:test(Repository)
%
% Create or update a graph for a given repository

grapher:test(Repository) :-
  grapher:prepare_directory(D,Repository),
  config:graph_modified_only(true),!,
  forall((Repository:entry(E,Time),
           Repository:get_ebuild(E,Ebuild),
           system:time_file(Ebuild,Modified),
           Modified > Time),
         (grapher:write_dot_files(D,Repository://E))),
  script:exec(graph,['dot',D]).

grapher:test(Repository) :-
  grapher:prepare_directory(D,Repository),
  not(config:graph_modified_only(true)),!,
  forall(Repository:entry(E),
         (grapher:write_dot_files(D,Repository://E))),
  script:exec(graph,['dot',D]).
