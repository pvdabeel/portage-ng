/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> DOT
Legacy Graphviz DOT graph generation for Gentoo ebuilds.

Produces DOT language output for dependency graphs that can be converted to SVG
via Graphviz.  Two graph styles are supported:

 - detail:  Three-column layout showing the ebuild, its dependency expressions,
            and candidate ebuilds.

 - deptree: Full recursive dependency tree for a single dependency type
            (bdepend, cdepend, depend, idepend, rdepend, pdepend).

All graphs include an interactive navigation legend with links to sibling
graph types, version control, and index pages.

This module is no longer part of the default --graph pipeline (which now
produces self-contained HTML).  It remains available for manual use via
dot:graph/2 and dot:produce_svg/1.
*/

:- module(dot, []).

% =============================================================================
%  DOT declarations
% =============================================================================


% -----------------------------------------------------------------------------
%  Entry points
% -----------------------------------------------------------------------------

%! dot:graph(+Type, +Repository://Id)
%
% Generate a complete DOT graph for the given type and ebuild.

dot:graph(detail, Repository://Id) :-
    !,
    dot:graph_header(detail, Repository://Id),
    dot:graph_legend(detail, Repository://Id),
    dot:graph_ebuild(detail, Repository://Id),
    dot:graph_depend(detail, Repository://Id),
    dot:graph_footer(detail, Repository://Id).

dot:graph(Type, Repository://Id) :-
    member(Type, [merge, fetchonly, info, emerge]),
    !,
    dot:graph_header(Type, Repository://Id),
    dot:graph_legend(Type, Repository://Id),
    dot:graph_root(Type, Repository://Id),
    dot:graph_footer(Type, Repository://Id).

dot:graph(Type, Repository://Id) :-
    member(Type, [bdepend, cdepend, depend, idepend, rdepend, pdepend]),
    !,
    dot:graph_header(Type, Repository://Id),
    dot:graph_legend(Type, Repository://Id),
    dot:graph_root(Type, Repository://Id),
    dot:graph_tree(Type, Repository://Id),
    dot:graph_footer(Type, Repository://Id).


% -----------------------------------------------------------------------------
%  Graph component: header
% -----------------------------------------------------------------------------

%! dot:graph_header(+Type, +Repository://Id)
%
% Emit the DOT digraph opening with appropriate layout settings.

dot:graph_header(detail, _Repository://_Id) :-
    !,
    writeln('digraph prolog {'),
    nl,
    writeln('newrank=true;'),
    writeln('concentrate=true;'),
    writeln('compound=true;'),
    nl,
    writeln('graph [rankdir=LR,fontname=Helvetica,fontsize=10,ranksep=1.5];'),
    writeln('edge  [arrowhead=vee];'),
    writeln('node  [fontname=Helvetica,fontsize=10];'),
    nl.

dot:graph_header(_Type, _Repository://_Id) :-
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


% -----------------------------------------------------------------------------
%  Graph component: footer
% -----------------------------------------------------------------------------

%! dot:graph_footer(+Type, +Repository://Id)
%
% Emit the closing brace of the DOT digraph.

dot:graph_footer(_Type, _Repository://_Id) :-
    write('}'), nl.


% -----------------------------------------------------------------------------
%  Graph component: legend
% -----------------------------------------------------------------------------

%! dot:graph_legend(+Type, +Target)
%
% Emit the full navigation legend as a DOT HTML-label table.

dot:graph_legend(Type, Repository://Id) :-
    config:graph_dependency_type(DepList),
    config:graph_proof_type(ProofList),
    config:graph_legacy_type(LegacyList),
    length(DepList, DepLen),
    length(ProofList, ProofLen),
    length(LegacyList, LegacyLen),
    dot:graph_legend_header(DepLen, ProofLen, LegacyLen),
    dot:graph_legend_navigation(Type, Repository://Id),
    dot:graph_legend_space,
    dot:graph_legend_types(Type, DepList, Repository://Id),
    dot:graph_legend_space,
    dot:graph_legend_version(Type, Repository://Id),
    dot:graph_legend_space,
    dot:graph_legend_proof(Type, ProofList, Repository://Id),
    dot:graph_legend_space,
    dot:graph_legend_legacy(Type, LegacyList, Repository://Id),
    dot:graph_legend_footer.


dot:graph_legend_header(DepLen, ProofLen, LegacyLen) :-
    write('graph [labelloc=t, labeljust=l, fontcolor=blue, fontname=Helvetica, fontsize=10, label='),
    write('<<TABLE BORDER=\'0\' CELLBORDER=\'1\' CELLSPACING=\'0\' CELLPADDING=\'6\'><TR>'),
    write('<TD COLSPAN=\'3\'><FONT COLOR=\'black\'><B>navigation</B></FONT></TD>'),
    write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
    write('<TD COLSPAN=\''), write(DepLen), write('\'><FONT COLOR=\'black\'><B>dependency graph</B></FONT></TD>'),
    write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
    write('<TD COLSPAN=\'4\'><FONT COLOR=\'black\'><B>version control</B></FONT></TD>'),
    write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
    write('<TD COLSPAN=\''), write(ProofLen), write('\'><FONT COLOR=\'black\'><B>command line</B></FONT></TD>'),
    write('<TD BORDER=\'0\' WIDTH=\'30\'></TD>'),
    write('<TD COLSPAN=\''), write(LegacyLen), write('\'><FONT COLOR=\'black\'><B>legacy</B></FONT></TD>'),
    write('</TR><TR>').


dot:graph_legend_space :-
    write('<TD BORDER=\'0\'></TD>').


dot:graph_legend_footer :-
    write('</TR></TABLE>>];'), nl,
    nl.


dot:graph_legend_navigation(_Type, Repository://Id) :-
    cache:ordered_entry(Repository, Id, Category, Name, _),
    dot:graph_legend_href(index_repository, Repository://Id, Repository),
    dot:graph_legend_href(index_category, Repository://Id, Category),
    dot:graph_legend_href(index_package, Repository://Id, Name).


dot:graph_legend_types(_Type, [], _Repository://_Id) :- !.

dot:graph_legend_types(Type, [Type|Rest], Repository://Id) :-
    !,
    atomic_list_concat(['<u>', Type, '</u>'], Name),
    dot:graph_legend_href(Type, Repository://Id, Name),
    dot:graph_legend_types(Type, Rest, Repository://Id).

dot:graph_legend_types(Type, [OtherType|Rest], Repository://Id) :-
    !,
    dot:graph_legend_href(OtherType, Repository://Id, OtherType),
    dot:graph_legend_types(Type, Rest, Repository://Id).


dot:graph_legend_version(Type, Repository://Id) :-
    query:search([category(C), name(N), version(V)], Repository://Id),
    findall(E, query:search([name(N), category(C), select(version, greater, V)], Repository://E), Eg),
    findall(E, query:search([name(N), category(C), select(version, smaller, V)], Repository://E), Es),
    (last(Eg, Newer)          ; Newer  = []), !,
    (last(Es, Oldest)         ; Oldest = []), !,
    (once(member(Newest, Eg)) ; Newest = []), !,
    (once(member(Older, Es))  ; Older  = []), !,
    dot:graph_legend_href(Type, Repository://Newest, '&lt;&lt; newest'),
    dot:graph_legend_href(Type, Repository://Newer, '&lt; newer'),
    dot:graph_legend_href(Type, Repository://Older, 'older &gt;'),
    dot:graph_legend_href(Type, Repository://Oldest, 'oldest &gt;&gt;').


dot:graph_legend_proof(_Type, [], _Repository://_Id) :- !.

dot:graph_legend_proof(Type, [Type|Rest], Repository://Id) :-
    !,
    atomic_list_concat(['--<u>', Type, '</u>&nbsp;'], Name),
    dot:graph_legend_href(Type, Repository://Id, Name),
    dot:graph_legend_proof(Type, Rest, Repository://Id).

dot:graph_legend_proof(Type, [OtherType|Rest], Repository://Id) :-
    !,
    atomic_list_concat(['--', OtherType, '&nbsp;'], Name),
    dot:graph_legend_href(OtherType, Repository://Id, Name),
    dot:graph_legend_proof(Type, Rest, Repository://Id).


dot:graph_legend_legacy(Type, LegacyTypes, Repository://Id) :-
    dot:graph_legend_types(Type, LegacyTypes, Repository://Id).


% -----------------------------------------------------------------------------
%  Legend href helpers
% -----------------------------------------------------------------------------

dot:graph_legend_href(_, _://[], Name) :-
    !,
    write('<TD><FONT color=\"gray\">'),
    write(Name), write('</FONT></TD>').

dot:graph_legend_href(repository, _Repository://_Id, Name) :-
    !,
    write('<TD><FONT color=\"gray\">'),
    write(Name), write('</FONT></TD>').

dot:graph_legend_href(category, _Repository://_Id, Name) :-
    !,
    write('<TD><FONT color=\"gray\">'),
    write(Name), write('</FONT></TD>').

dot:graph_legend_href(package, _Repository://_Id, Name) :-
    !,
    write('<TD><FONT color=\"gray\">'),
    write(Name), write('</FONT></TD>').

dot:graph_legend_href(merge, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('-merge.svg'), write('\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(fetchonly, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('-fetchonly.svg'), write('\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(info, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('-info.svg'), write('\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(emerge, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('-emerge.svg'), write('\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(detail, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('.svg'), write('\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(index_repository, _Repository://_Id, Name) :-
    !,
    write('<TD title=\"repository\" href=\"../index.html\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(index_category, _Repository://_Id, Name) :-
    !,
    write('<TD title=\"repository\" href=\"./index.html\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(index_package, _Repository://_Id, Name) :-
    !,
    write('<TD title=\"repository\" href=\"./'), write(Name), write('.html\">'),
    write(Name), write('</TD>').

dot:graph_legend_href(Depend, Repository://Id, Name) :-
    !,
    write('<TD title=\"'), write(Repository://Id), write('\" href=\"../'),
    write(Id), write('-'), write(Depend), write('.svg'), write('\">'),
    write(Name), write('</TD>').


% -----------------------------------------------------------------------------
%  Graph subcomponent: detail — ebuild column
% -----------------------------------------------------------------------------

%! dot:graph_ebuild(detail, +Repository://Id)
%
% Emit the leftmost column showing ebuild information.

dot:graph_ebuild(detail, Repository://Id) :-
    !,
    writeln('# **********'),
    writeln('# The ebuild'),
    writeln('# **********'),
    nl,
    write('subgraph cluster_leftcol {'), nl,
    write('fontcolor=gray;'), nl,
    write('label=<<i>ebuild</i>>;'), nl,
    write('labelloc=t;'), nl,
    write('labeljust=c;'), nl,
    write('id [label=\"'), write(Repository://Id),
    write('\", color=red, width=4, penwidth=2, fontname=\"Helvetica-Bold\", href=\"../'),
    write(Id), write('.svg\"];'), nl,
    write('}'), nl,
    nl.


% -----------------------------------------------------------------------------
%  Graph subcomponent: detail — dependencies column
% -----------------------------------------------------------------------------

%! dot:graph_depend(detail, +Repository://Id)
%
% Emit the middle column showing compile and runtime dependencies.

dot:graph_depend(detail, Repository://Id) :-
    !,
    dot:graph_depend_header,
    query:search(all(dependency(C, install)), Repository://Id),
    query:search(all(dependency(R, run)), Repository://Id),
    list_to_ord_set(C, OC),
    list_to_ord_set(R, OR),
    ord_intersection(OC, OR, OCR, OPR),
    ord_intersection(OR, OC, OCR, OPC),
    dot:graph_depend_cluster_install(OPC, AllChoices1),
    dot:graph_depend_cluster_install_and_run(OCR, AllChoices2),
    dot:graph_depend_cluster_run(OPR, AllChoices3),
    dot:graph_candidates(detail, AllChoices1, AllChoices2, AllChoices3).


dot:graph_depend_header :-
    writeln('# ****************'),
    writeln('# The dependencies'),
    writeln('# ****************'),
    nl,
    write('subgraph cluster_midcol {'), nl,
    write('fontcolor=gray;'), nl,
    write('label=<<i>dependencies</i>>;'), nl,
    write('labelloc=t;'), nl,
    write('labeljust=c'), nl.


dot:graph_depend_cluster_install(OPC, AllChoices1) :-
    write('subgraph cluster_install {'), nl,
    write('fillcolor="#eeeeee";'), nl,
    write('style=filled;'), nl,
    write('label=<<i>install</i>>;'), nl,
    findall(Ch, (member(D, OPC), dot:handle(detail, solid, vee, id, D, Ch)), AllChoices1),
    write('}'), nl.


dot:graph_depend_cluster_install_and_run(OCR, AllChoices2) :-
    write('subgraph cluster_install_and_run {'), nl,
    write('fillcolor="#eeeeee";'), nl,
    write('style=filled;'), nl,
    write('label=<<i>install and run</i>>;'), nl,
    findall(Ch, (member(D, OCR), dot:handle(detail, solid, odotvee, id, D, Ch)), AllChoices2),
    write('}'), nl.


dot:graph_depend_cluster_run(OPR, AllChoices3) :-
    write('subgraph cluster_run {'), nl,
    write('fillcolor="#eeeeee";'), nl,
    write('style=filled;'), nl,
    write('label=<<i>run</i>>;'), nl,
    findall(Ch, (member(D, OPR), dot:handle(detail, solid, odot, id, D, Ch)), AllChoices3),
    write('}'), nl,
    write('}'), nl,
    nl.


% -----------------------------------------------------------------------------
%  Graph subcomponent: detail — candidates column
% -----------------------------------------------------------------------------

%! dot:graph_candidates(detail, +AllChoices1, +AllChoices2, +AllChoices3)
%
% Emit the rightmost column showing candidate ebuilds.

dot:graph_candidates(detail, AllChoices1, AllChoices2, AllChoices3) :-
    !,
    union(AllChoices1, AllChoices2, AllChoices12),
    union(AllChoices12, AllChoices3, AllChoices),
    writeln('# **************'),
    writeln('# The candidates'),
    writeln('# **************'),
    nl,
    write('subgraph cluster_choices {'), nl,
    write('rank=same;'), nl,
    write('fontcolor=gray;'), nl,
    write('label=<<i>candidates</i>>;'), nl,
    write('labelloc=t;'), nl,
    write('labeljust=c'), nl,
    nl,
    dot:choices(detail, AllChoices),
    write('}'), nl.


% -----------------------------------------------------------------------------
%  Graph component: root
% -----------------------------------------------------------------------------

%! dot:graph_root(+Type, +Repository://Id)
%
% Emit the invisible root node for proof/legacy and deptree graphs.

dot:graph_root(Type, _Repository://_Id) :-
    ((config:graph_proof_type(Types), memberchk(Type, Types));
     (config:graph_legacy_type(Types), memberchk(Type, Types))),
    !,
    write('root [style=invis];'), nl,
    write('placeholder [style=invis, width=22, height=15];'), nl,
    write('root -> \"'), write(placeholder), write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'), nl,
    nl.

dot:graph_root(_Type, Repository://Id) :-
    write('root [style=invis];'), nl,
    write('root -> \"'), write(Repository://Id), write('\"[minlen=0.2, headport=n, tailport=s, style=invis];'), nl,
    nl.


% -----------------------------------------------------------------------------
%  Graph component: tree
% -----------------------------------------------------------------------------

:- thread_local dot:node_visited/1.
:- thread_local dot:node_counter/2.

%! dot:graph_tree(+Type, +Repository://Id)
%
% Emit the full recursive dependency tree.

dot:graph_tree(Type, Repository://Id) :-
    retractall(dot:node_visited(_)),
    dot:graph_tree(Type, Repository://Id, Repository://Id),
    retractall(dot:node_visited(_)).


dot:graph_tree(Type, RootRep://RootId, Repository://Id) :-
    \+(dot:node_visited(Repository://Id)), !,
    dot:graph_node(Type, RootRep://RootId, Repository://Id),
    Statement =.. [Type, DS],
    query:search(all(Statement), Repository://Id),
    findall(Ch, (member(D, DS), dot:handle(Type, solid, vee, Repository://Id, D, Ch)), AllChoices),
    assertz(dot:node_visited(Repository://Id)),
    dot:choices(Type, AllChoices),
    forall(member(arrow(_, [Repository://Chs:_]), AllChoices),
           dot:graph_tree(Type, RootRep://RootId, Repository://Chs)).

dot:graph_tree(_, _, Repository://Id) :-
    dot:node_visited(Repository://Id), !.


%! dot:graph_node(+Type, +Repository://RootId, +Repository://Id)
%
% Emit a single node in the dependency tree.

dot:graph_node(Type, Repository://Id, Repository://Id) :-
    !,
    write('\"'), write(Repository://Id),
    write('\" [color=red, penwidth=2, fontname=\"Helvetica-Bold\", href=\"../'),
    write(Id), write('-'), write(Type), write('.svg\"];'), nl.

dot:graph_node(Type, _://_,Repository://Id) :-
    !,
    write('\"'), write(Repository://Id),
    write('\" [color=red, penwidth=1, href=\"../'),
    write(Id), write('-'), write(Type), write('.svg\"];'), nl.


% -----------------------------------------------------------------------------
%  Choices and blocker types
% -----------------------------------------------------------------------------

%! dot:choices(+Type, +List)
%
% Emit DOT edges and subgraphs for dependency choices.

dot:choices(_, []) :- !, true.

dot:choices(detail, [arrow(D, Choices)|Rest]) :-
    !,
    write('subgraph '), write(' {'), nl,
    write('color=black;'), nl,
    write('nodesep=1;'), nl,
    forall(member(Repository://Ch, Choices),(
        write('\"'), write(Ch), write('\"'),
        write(' [label=\"'), write(Repository://Ch),
        write('\", color=red, width=4,href=\"../'), write(Ch), write('.svg\"];'), nl)),
    forall(member(Repository://Ch, Choices),(
        write(D),
        write(':e -> '),
        write('\"'), write(Ch),
        write('\"'), write(':w [style=dotted,weight=\"100\"];'), nl)),
    writeln('}'),
    dot:choices(detail, Rest).

dot:choices(Deptype, [arrow(D, [Repository://Choice:Type])|Rest]) :-
    !,
    write('\"'), write(D), write('\"'),
    write(' -> '),
    write('\"'), write(Repository://Choice), write('\"'),
    dot:choice_type(Type),
    nl,
    dot:choices(Deptype, Rest).

dot:choices(Kind, [L|Rest]) :-
    \+L =.. [arrow, _, _],
    !,
    dot:choices(Kind, L),
    dot:choices(Kind, Rest).


dot:choice_type(no) :- !.

dot:choice_type(weak) :-
    write(' [style=dashed, color=orange];').

dot:choice_type(strong) :-
    write(' [style=dashed, color=red];').


% -----------------------------------------------------------------------------
%  Node and edge handling
% -----------------------------------------------------------------------------

%! dot:handle(+Type, +Style, +ArrowStyle, +Master, +Dependency, -Output)
%
% Create a meta representation of a dependency for DOT output.

dot:format_table_attrs(F) :-
    F = "BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\"".

dot:format_edge_attrs(Master, D, Style, Arrow, Color, Weight) :-
    format("~w:e -> ~w:w [weight=~w, ~wstyle=\"~w\",arrowhead=\"~w\"];~n",
           [Master, D, Weight, Color, Style, Arrow]).

dot:format_package_dep(D, Label, Type, Cat, Name, Cmpr, Ver, Color, Width) :-
    dot:format_table_attrs(F),
    format("~w [label=<<TABLE ~w WIDTH=\"~w\"><TR><TD ROWSPAN=\"6\" CELLPADDING=\"30\">~w</TD></TR>
                     <TR><TD WIDTH=\"110\">~w</TD></TR><TR><TD>~w</TD></TR><TR><TD>~w</TD></TR>
                     <TR><TD>~w</TD></TR><TR><TD>~w</TD></TR></TABLE>>, shape=none, color=~w];~n",
           [D, F, Width, Label, Type, Cat, Name, Cmpr, Ver, Color]).

dot:format_group(D, Label, Color) :-
    dot:format_table_attrs(F),
    format("~w [label=<<TABLE ~w><TR><TD CELLPADDING=\"10\">~w</TD></TR></TABLE>>, shape=none, color=~w];~n",
           [D, F, Label, Color]).


dot:handle(detail, Style, Arrow, Master, package_dependency(Type, Strength, Cat, Name, Cmpr, Ver, _, _), arrow(D, Choices)) :-
    !,
    ( Strength = no,     Label = "pack_dep",          Color = blue,   Sym = package_dependency, EdgeColor = ""
    ; Strength = weak,   Label = "blocking (weak)",   Color = orange, Sym = weak_blocker,       EdgeColor = "color=\"orange\", "
    ; Strength = strong, Label = "blocking (strong)", Color = red,    Sym = strong_blocker,     EdgeColor = "color=\"red\", "
    ),
    write("subgraph  {"), nl,
    dot:tl_gensym(Sym, D),
    dot:format_package_dep(D, Label, Type, Cat, Name, Cmpr, Ver, Color, 220),
    write("}"), nl,
    dot:format_edge_attrs(Master, D, Style, Arrow, EdgeColor, 20),
    findall(R, query:search([name(Name), category(Cat), select(version, Cmpr, Ver)], R), Choices).


dot:handle(detail, Style, Arrow, Master, use_conditional_group(Type, Use, _, Deps), Choices) :-
    !,
    dot:format_table_attrs(F),
    write("subgraph  {"), nl,
    dot:tl_gensym(use_conditional_group, D),
    format("~w [label=<<TABLE ~w><TR><TD ROWSPAN=\"3\" CELLPADDING=\"10\">use_conditional</TD></TR>
          <TR><TD>~w</TD></TR><TR><TD>~w</TD></TR></TABLE>>, shape=none, color=red];~n",
           [D, F, Type, Use]),
    findall(Ch, (member(Dep, Deps), dot:handle(detail, dashed, vee, D, Dep, Ch)), Choices),
    write("}"), nl,
    dot:format_edge_attrs(Master, D, Style, Arrow, "", 20).


dot:handle(detail, Style, Arrow, Master, Group, Choices) :-
    Group =.. [Type, Deps],
    member(Type, [any_of_group, all_of_group, exactly_one_of_group, at_most_one_of_group]),
    !,
    write("subgraph  {"), nl,
    dot:tl_gensym(Type, D),
    dot:format_group(D, Type, red),
    (   Type = any_of_group, SubStyle = dotted, SubArrow = oinv
    ;   Type = all_of_group, SubStyle = solid, SubArrow = inv
    ;   Type = exactly_one_of_group, SubStyle = dotted, SubArrow = tee
    ;   Type = at_most_one_of_group, SubStyle = dotted, SubArrow = onormal
    ),
    findall(Ch, (member(Dep, Deps), dot:handle(detail, SubStyle, SubArrow, D, Dep, Ch)), Choices),
    write("}"), nl,
    dot:format_edge_attrs(Master, D, Style, Arrow, "", 20).


dot:handle(detail, _, _, Master, S, []) :-
    !,
    format("# *** UNKNOWN DEPENDENCY TYPE (TODO) ***~n# ~w -> ~w~n# *** END ***~n~n", [Master, S]).


dot:handle(_, _, _, Mastercontext://Master, package_dependency(_, Strength, Cat, Name, Cmpr, Ver, _, _),
           arrow(Mastercontext://Master, [Choicecontext://Choice:Strength])) :-
    query:search([name(Name), category(Cat), select(version, Cmpr, Ver)], Choicecontext://Choice), !.


dot:handle(_, _, _, _, Group, []) :-
    member(Group, [use_conditional_group(_, _, _, _),
                   any_of_group(_),
                   all_of_group(_),
                   exactly_one_of_group(_),
                   at_most_one_of_group(_)]), !.

dot:handle(_, _, _, _, _, []) :- !.


% -----------------------------------------------------------------------------
%  Helpers
% -----------------------------------------------------------------------------

%! dot:tl_gensym(+Atom, -AtomCount)
%
% Thread-local gensym counter for unique DOT node identifiers.

dot:tl_gensym(Atom, AtomCount) :-
    \+ dot:node_counter(Atom, _), !,
    assert(dot:node_counter(Atom, 1)),
    atomic_concat(Atom, 1, AtomCount).

dot:tl_gensym(Atom, AtomCount) :-
    retract(dot:node_counter(Atom, Count)),
    NewCount is Count + 1,
    assertz(dot:node_counter(Atom, NewCount)),
    atomic_concat(Atom, NewCount, AtomCount).

dot:tl_gensym_reset(Atom) :-
    retractall(dot:node_counter(Atom, _)).


% -----------------------------------------------------------------------------
%  SVG conversion
% -----------------------------------------------------------------------------

%! dot:produce_svg(+Directory)
%
% Convert DOT files in Directory to SVG via the Graphviz dot script.

dot:produce_svg(Directory) :-
    message:scroll_notice(['Now running Graphviz dot...']),
    message:hc,
    script:exec(graph, ['dot', Directory]),
    message:sc.
