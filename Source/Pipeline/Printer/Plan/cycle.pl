/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CYCLE
Cycle explanation and visualization for dependency proofs.

Provides DFS/BFS-based cycle path finding on the TriggersAVL (and
optionally ProofAVL), minimal cycle witness recovery, USE-guard
extraction from cached dependency metadata, and cycle path display.
*/

:- module(cycle, []).

% =============================================================================
%  CYCLE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Cycle explanation
% -----------------------------------------------------------------------------

%! cycle:print_cycle_explanation(+StartKey,+ProofAVL,+TriggersAVL)
cycle:print_cycle_explanation(StartKey, ProofAVL, TriggersAVL) :-
  ( StartKey = _://_:install ; StartKey = _://_:run ; StartKey = _://_:fetchonly
  ; StartKey = _:install     ; StartKey = _:run     ; StartKey = _:fetchonly
  ),
  ( is_assoc(ProofAVL),
    ( prover:canon_literal(StartKey, Canon, _) -> true ; Canon = StartKey ),
    get_assoc(cycle_path(Canon), ProofAVL, CyclePath0a) ->
      cycle:cycle_display_path(CyclePath0a, CyclePath),
      CyclePath0 = CyclePath0a
  ; ( cycle:cycle_start_pkg_key(StartKey, TriggersAVL, StartPkg),
      cycle:find_cycle_via_triggers_pkg(StartPkg, TriggersAVL, CyclePath),
      CyclePath0 = CyclePath
    ; cycle:cycle_start_pkg_key(StartKey, TriggersAVL, StartPkg),
      cycle:find_cycle_via_triggers(StartPkg, TriggersAVL, CyclePath0a),
      cycle:cycle_display_path(CyclePath0a, CyclePath),
      CyclePath0 = CyclePath0a
    ; cycle:find_cycle_via_proof(StartKey, ProofAVL, CyclePath0a),
      cycle:cycle_display_path(CyclePath0a, CyclePath),
      CyclePath0 = CyclePath0a
    )
  ),
  ( CyclePath = [_|_] ->
    sampler:record(cycle(CyclePath0, CyclePath)),
    nl,
    message:color(darkgray),
    message:print('  Reason : Dependency cycle :'), nl,
    message:color(normal),
    nl,
    ( catch(call_with_time_limit(0.25, cycle:cycle_edge_guard_map(CyclePath0, GuardMap0)),
           time_limit_exceeded,
           GuardMap0 = _),
      ( is_assoc(GuardMap0) -> GuardMap = GuardMap0 ; empty_assoc(GuardMap) )
    ),
    cycle:print_cycle_tree(CyclePath, GuardMap)
  ;
    message:color(darkgray),
    message:print('  (cycle path not found)'),
    message:color(normal),
    nl
  ),
  !.
cycle:print_cycle_explanation(_, _, _) :-
  true.

% Backward compatibility (older callers).
cycle:print_cycle_explanation(StartKey, TriggersAVL) :-
  cycle:print_cycle_explanation(StartKey, t, TriggersAVL).

% Pick a reasonable package-key node to anchor cycle search.
% For grouped deps / other non-package nodes, we look 1-2 hops in the triggers graph
% for the first package key.
cycle:cycle_start_pkg_key(StartKey, _TriggersAVL, StartPkg) :-
  cycle:cycle_node_package_key(StartKey, StartPkg),
  !.
cycle:cycle_start_pkg_key(StartKey, TriggersAVL, StartPkg) :-
  cycle:trigger_neighbors(StartKey, TriggersAVL, Neigh),
  member(N, Neigh),
  cycle:cycle_node_package_key(N, StartPkg),
  !.
cycle:cycle_start_pkg_key(StartKey, TriggersAVL, StartPkg) :-
  cycle:trigger_neighbors(StartKey, TriggersAVL, Neigh1),
  member(N1, Neigh1),
  cycle:trigger_neighbors(N1, TriggersAVL, Neigh2),
  member(N2, Neigh2),
  cycle:cycle_node_package_key(N2, StartPkg),
  !.

% -----------------------------------------------------------------------------
%  On-demand USE-guard extraction for cycle edges
% -----------------------------------------------------------------------------

% Build a map ToPkgKey -> GuardText (e.g. "-expat +python") for the cycle edges
% found in the raw trigger cycle path. This is computed on-demand at print time
% and does not affect proving performance.
cycle:cycle_edge_guard_map(CyclePath0, GuardMap) :-
  cycle:cycle_edges_from_raw(CyclePath0, Edges),
  empty_assoc(Empty),
  foldl(cycle:edge_guard_put, Edges, Empty, GuardMap).

cycle:edge_guard_put(edge(From, Dep, To), In, Out) :-
  ( cycle:edge_guard_text(From, Dep, To, Text),
    Text \== ''
  -> put_assoc(To, In, Text, Out)
  ;  Out = In
  ).

% Extract the minimal USE guards that enabled this dependency edge.
% We anchor on the concrete package_dependency leaf inside the grouped dep node,
% and then locate that leaf inside the cached dependency metadata tree under
% use_conditional_group/4 nodes.
% Note: the cycle path is a *reverse dependency* path. An edge:
%   FromPkg -> DepNode -> ToPkg
% means: ToPkg depends on FromPkg (potentially under USE conditions).
% Therefore we must look up the dependency leaf (which matches FromPkg) in
% ToPkg's metadata tree.
cycle:edge_guard_text(FromPkg, DepNode, ToPkg, Text) :-
  cycle:cycle_dep_leaf(DepNode, FromPkg, LeafDep),
  cycle:cycle_pkg_repo_entry(ToPkg, Repo://Entry, _Action),
  cycle:metadata_use_guards_for_leaf(Repo://Entry, LeafDep, Guards),
  cycle:guards_to_text(Guards, Text).

cycle:cycle_pkg_repo_entry(Repo://Entry:Action, Repo://Entry, Action) :- !.
cycle:cycle_pkg_repo_entry(Repo://Entry,        Repo://Entry, unknown) :- !.

cycle:cycle_dep_leaf(DepNode, FromPkg, Leaf) :-
  ( cycle:cycle_pkg_cat_name(FromPkg, FromC, FromN) -> true ; FromC = _, FromN = _ ),
  ( DepNode = grouped_package_dependency(_C,_N,List):_Action
  ; DepNode = grouped_package_dependency(_X,_C,_N,List):_Action
  ),
  !,
  ( member(Leaf, List),
    Leaf = package_dependency(_,_,FromC,FromN,_,_,_,_)
  -> true
  ; member(Leaf, List),
    Leaf = package_dependency(_,_,_,_,_,_,_,_)
  ).
cycle:cycle_dep_leaf(package_dependency(_,_,_,_,_,_,_,_):_Action, _FromPkg, Leaf) :-
  !,
  Leaf = package_dependency(_,_,_,_,_,_,_,_).
cycle:cycle_dep_leaf(package_dependency(_,_,_,_,_,_,_,_), _FromPkg, Leaf) :-
  !,
  Leaf = package_dependency(_,_,_,_,_,_,_,_).

% Best-effort category/name extraction for a package key in the cycle.
% Uses cache metadata (fast indexed lookup) and falls back to parsing.
cycle:cycle_pkg_cat_name(Repo://Entry:_Action, C, N) :-
  !,
  ( cache:ordered_entry(Repo, Entry, C, N, _) -> true
  ; atom(Entry),
    atomic_list_concat([C, Rest], '/', Entry),
    sub_atom(Rest, 0, _, _, N)
  ).
cycle:cycle_pkg_cat_name(Repo://Entry, C, N) :-
  !,
  ( cache:ordered_entry(Repo, Entry, C, N, _) -> true
  ; atom(Entry),
    atomic_list_concat([C, Rest], '/', Entry),
    sub_atom(Rest, 0, _, _, N)
  ).

cycle:cycle_edges_from_raw([], []) :- !.
cycle:cycle_edges_from_raw([_], []) :- !.
cycle:cycle_edges_from_raw([_,_], []) :- !.
cycle:cycle_edges_from_raw([A,Dep,B|Rest], [edge(A,Dep,B)|Edges]) :-
  cycle:is_pkg_key(A),
  \+ cycle:is_pkg_key(Dep),
  cycle:is_pkg_key(B),
  !,
  cycle:cycle_edges_from_raw([B|Rest], Edges).
cycle:cycle_edges_from_raw([_|Rest], Edges) :-
  cycle:cycle_edges_from_raw(Rest, Edges).

cycle:is_pkg_key(_://_:_) :- !.

% Retrieve the cached dependency metadata trees for an ebuild.
% We search all relevant dependency variables to avoid any fuzzy mapping.
cycle:metadata_dep_trees(Repo://Entry, Trees) :-
  findall(T, kb:query(depend(T),  Repo://Entry), T1),
  findall(T, kb:query(bdepend(T), Repo://Entry), T2),
  findall(T, kb:query(rdepend(T), Repo://Entry), T3),
  findall(T, kb:query(pdepend(T), Repo://Entry), T4),
  append([T1,T2,T3,T4], Trees0),
  Trees = Trees0.

% Find a minimal guard list by iterative deepening on the number of USE guards.
cycle:metadata_use_guards_for_leaf(Repo://Entry, LeafDep, Guards) :-
  cycle:metadata_dep_trees(Repo://Entry, Trees),
  between(0, 6, MaxGuards),
  once((
    member(Tree, Trees),
    cycle:metadata_find_leaf_guards(Tree, LeafDep, [], Rev, MaxGuards)
  )),
  !,
  reverse(Rev, Guards).
cycle:metadata_use_guards_for_leaf(_Repo://_Entry, _LeafDep, []).

% Walk only the metadata dependency tree; this is not a dependency-graph DFS and
% cannot loop back into itself unless the term is cyclic (which would be unusual).
% The MaxGuards bound keeps this search minimal and fast.
% Unwrap context/action decorations like X:install?{...} or X:config, so we can
% match against the underlying metadata terms.
cycle:metadata_find_leaf_guards(Full, Leaf, Acc, Out, Max) :-
  Full = (Inner ? {_Ctx}),
  !,
  cycle:metadata_find_leaf_guards(Inner, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(Full, Leaf, Acc, Out, Max) :-
  Full = (Inner : _Action),
  !,
  cycle:metadata_find_leaf_guards(Inner, Leaf, Acc, Out, Max).

cycle:metadata_find_leaf_guards(use_conditional_group(Type,Use,_Id,Values), Leaf, Acc, Out, Max) :-
  ( Type == positive -> G = guard(positive,Use) ; G = guard(negative,Use) ),
  length(Acc, L),
  L1 is L + 1,
  L1 =< Max,
  !,
  cycle:metadata_find_leaf_guards_list(Values, Leaf, [G|Acc], Out, Max).
cycle:metadata_find_leaf_guards(any_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(all_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(exactly_one_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(at_most_one_of_group(Vals), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(Vals, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(grouped_package_dependency(_C,_N,List), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(List, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(grouped_package_dependency(_X,_C,_N,List), Leaf, Acc, Out, Max) :-
  !, cycle:metadata_find_leaf_guards_list(List, Leaf, Acc, Out, Max).
cycle:metadata_find_leaf_guards(package_dependency(_A,_B,C,N,_O,_V,_S,_U),
                                 package_dependency(_A2,_B2,C2,N2,_O2,_V2,_S2,_U2),
                                 Acc, Acc, _Max) :-
  C == C2, N == N2,
  !.
cycle:metadata_find_leaf_guards(_Other, _Leaf, _Acc, _Out, _Max) :-
  fail.

cycle:metadata_find_leaf_guards_list([X|Xs], Leaf, Acc, Out, Max) :-
  ( cycle:metadata_find_leaf_guards(X, Leaf, Acc, Out, Max)
  ; cycle:metadata_find_leaf_guards_list(Xs, Leaf, Acc, Out, Max)
  ).

cycle:guards_to_text([], '') :- !.
cycle:guards_to_text(Guards, Text) :-
  findall(A,
          ( member(guard(Type,Use), Guards),
            ( Type == positive -> A = Use ; atom_concat('-', Use, A) )
          ),
          Atoms0),
  sort(Atoms0, Atoms),
  atomic_list_concat(Atoms, ' ', Text).

% Print a cycle path with a "box + return arrow" on the right side:
% - first line gets a left-pointing arrow to the right-side vertical bar (◄───┐)
% - middle lines show a vertical bar (│)
% - last line closes the box (───┘)
% This visually indicates the last node loops back to the first.
cycle:print_cycle_tree([]) :- !.
cycle:print_cycle_tree(CyclePath) :-
  empty_assoc(Empty),
  cycle:print_cycle_tree(CyclePath, Empty).

cycle:print_cycle_tree(CyclePath, GuardMap) :-
  cycle:cycle_tree_parts(CyclePath, GuardMap, Parts0),
  cycle:cycle_tree_trim_repeat(Parts0, Parts1),
  cycle:cycle_tree_apply_closing_guard(CyclePath, GuardMap, Parts1, Parts),
  length(Parts, N),
  ( N < 2 ->
      Parts = [part(Indent, Entry, Action, GuardInText, GuardBackText, _LineWidth)],
      cycle:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText), nl
  ;
      cycle:cycle_tree_right_width(Parts, RightWidth),
      cycle:print_cycle_tree_parts(Parts, 1, N, RightWidth)
  ).

% If the cycle path ends with the same node it starts with, drop the last one.
% This keeps the visual cycle closure without printing the start node twice.
cycle:cycle_tree_trim_repeat([First|Rest], Parts) :-
  Rest \= [],
  append(Mid, [Last], Rest),
  First = part(_, Entry, Action, _GuardIn, _GuardBack, _),
  Last  = part(_, Entry, Action, _GuardIn2, _GuardBack2, _),
  Mid \= [],
  !,
  Parts = [First|Mid].
cycle:cycle_tree_trim_repeat(Parts, Parts).

% Per-edge labeling: the guard for the closing edge (last -> first) is attached
% to the last printed line as "↩ USE: ...", instead of being shown on the first
% node line (which can be confusing in a cycle).
cycle:cycle_tree_apply_closing_guard(CyclePath, GuardMap, PartsIn, PartsOut) :-
  ( CyclePath = [FirstNode|_],
    get_assoc(FirstNode, GuardMap, ClosingGuard),
    ClosingGuard \== '',
    PartsIn = [part(FIndent, FEntry, FAction, _FirstGuardIn, FBack, _FW0)|Tail0],
    append(Front, [part(Indent, Entry, Action, GuardIn, _OldBack, _W0)], Tail0)
  ->
    cycle:cycle_tree_line_width(FIndent, FEntry, FAction, '', FBack, FW1),
    FirstPart = part(FIndent, FEntry, FAction, '', FBack, FW1),
    cycle:cycle_tree_line_width(Indent, Entry, Action, GuardIn, ClosingGuard, W1),
    append([FirstPart|Front], [part(Indent, Entry, Action, GuardIn, ClosingGuard, W1)], PartsOut)
  ;
    PartsOut = PartsIn
  ).

cycle:cycle_tree_parts(CyclePath, Parts) :-
  BaseIndent = 4,
  cycle:cycle_tree_parts_(CyclePath, BaseIndent, Parts).

cycle:cycle_tree_parts(CyclePath, GuardMap, Parts) :-
  BaseIndent = 4,
  cycle:cycle_tree_parts_(CyclePath, GuardMap, BaseIndent, Parts).

cycle:cycle_tree_parts_([], _Indent, []) :- !.
cycle:cycle_tree_parts_([Node|Rest], Indent, [part(Indent, Entry, Action, '', '', LineWidth)|Parts]) :-
  cycle:cycle_node_parts(Node, Entry, Action),
  cycle:cycle_tree_line_width(Indent, Entry, Action, '', '', LineWidth),
  Indent1 is Indent + 4,
  cycle:cycle_tree_parts_(Rest, Indent1, Parts).

cycle:cycle_tree_parts_([], _GuardMap, _Indent, []) :- !.
cycle:cycle_tree_parts_([Node|Rest], GuardMap, Indent, [part(Indent, Entry, Action, GuardText, '', LineWidth)|Parts]) :-
  cycle:cycle_node_parts(Node, Entry, Action),
  ( get_assoc(Node, GuardMap, GuardText0) -> GuardText = GuardText0 ; GuardText = '' ),
  cycle:cycle_tree_line_width(Indent, Entry, Action, GuardText, '', LineWidth),
  Indent1 is Indent + 4,
  cycle:cycle_tree_parts_(Rest, GuardMap, Indent1, Parts).

cycle:cycle_tree_right_width(Parts, RightWidth) :-
  findall(W, member(part(_,_,_,_,_,W), Parts), Ws),
  max_list(Ws, MaxW),
  ( config:printing_tty_size(_, TermW) -> true ; TermW = 120 ),
  TargetW is MaxW + 6,
  CapW is max(0, TermW - 2),
  RightWidth0 is min(CapW, TargetW),
  ( RightWidth0 >= MaxW + 6 -> RightWidth = RightWidth0 ; RightWidth = MaxW + 6 ).

cycle:print_cycle_tree_parts([], _I, _N, _RightWidth) :- !.
cycle:print_cycle_tree_parts([part(Indent, Entry, Action, GuardInText, GuardBackText, LineWidth)|Rest], I, N, RightWidth) :-
  cycle:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText),
  cycle:print_cycle_tree_right(I, N, RightWidth, LineWidth),
  nl,
  ( I < N ->
      cycle:print_cycle_tree_spacer(RightWidth),
      nl
  ;
      true
  ),
  I1 is I + 1,
  cycle:print_cycle_tree_parts(Rest, I1, N, RightWidth).

cycle:print_cycle_tree_main(Indent, Entry, Action, GuardInText, GuardBackText) :-
  cycle:print_n(' ', Indent),
  message:color(darkgray),
  message:print('└─'),
  message:color(normal),
  message:bubble(darkgray,Action),
  message:color(darkgray),
  message:print('─> '),
  message:color(normal),
  message:print(Entry),
  cycle:print_cycle_tree_guard_suffix(GuardInText),
  cycle:print_cycle_tree_back_guard_suffix(GuardBackText).

cycle:print_cycle_tree_guard_suffix('') :- !.
cycle:print_cycle_tree_guard_suffix(GuardText) :-
  message:color(darkgray),
  message:print(' [USE: '),
  message:print(GuardText),
  message:print(']'),
  message:color(normal).

cycle:print_cycle_tree_back_guard_suffix('') :- !.
cycle:print_cycle_tree_back_guard_suffix(GuardText) :-
  message:color(darkgray),
  message:print(' [↩ USE: '),
  message:print(GuardText),
  message:print(']'),
  message:color(normal).

cycle:print_cycle_tree_right(I, N, RightWidth, LineWidth) :-
  Pad0 is RightWidth - LineWidth,
  Pad is max(2, Pad0),
  message:print(' '),
  Pad1 is max(1, Pad - 1),
  message:color(lightred),
  ( I =:= 1 ->
      message:print('<'),
      Dashes is max(0, Pad1 - 2),
      cycle:print_n('─', Dashes),
      message:print('┐')
  ; I =:= N ->
      Dashes is max(1, Pad1 - 1),
      cycle:print_n('─', Dashes),
      message:print('┘')
  ;
      Spaces is max(0, Pad1 - 1),
      cycle:print_n(' ', Spaces),
      message:print('│')
  ),
  message:color(normal).

cycle:print_cycle_tree_spacer(RightWidth) :-
  message:color(lightred),
  cycle:print_n(' ', max(0, RightWidth - 1)),
  message:print('│'),
  message:color(normal).

cycle:cycle_tree_line_width(Indent, Entry, Action, GuardText, BackGuardText, Width) :-
  cycle:term_visible_length(Entry, EntryLen),
  cycle:term_visible_length(Action, ActionLen),
  cycle:term_visible_length(GuardText, GuardLen),
  cycle:term_visible_length(BackGuardText, BackGuardLen),
  ( GuardLen =:= 0
    -> GuardExtra = 0
    ;  GuardExtra is 7 + GuardLen + 1
  ),
  ( BackGuardLen =:= 0
    -> BackExtra = 0
    ;  BackExtra is 9 + BackGuardLen + 1
  ),
  Width is Indent + 2 + (ActionLen + 2) + 3 + EntryLen + GuardExtra + BackExtra.

cycle:term_visible_length(Term, Len) :-
  ( atomic(Term) ->
      atom_length(Term, Len)
  ;
      term_to_atom(Term, Atom),
      atom_length(Atom, Len)
  ).

cycle:print_n(_Char, N) :-
  N =< 0,
  !.
cycle:print_n(Char, N) :-
  message:print(Char),
  N1 is N - 1,
  cycle:print_n(Char, N1).

% Extract Entry and Action from a cycle node (already filtered to package keys).
% Examples:
%   portage://dev-libs/libxml2-2.15.1:install  -> Entry=dev-libs/libxml2-2.15.1, Action=install
%   portage://dev-libs/libxml2-2.15.1          -> Entry=dev-libs/libxml2-2.15.1, Action=unknown
cycle:cycle_node_parts(grouped(C,N):Action, Entry, Action) :-
  !,
  format(atom(Entry), '~w/~w (group)', [C, N]).
cycle:cycle_node_parts(_Repo://Entry:Action, Entry, Action) :- !.
cycle:cycle_node_parts(_Repo://Entry,        Entry, unknown) :- !.
cycle:cycle_node_parts(Entry:Action,         Entry, Action) :- !.
cycle:cycle_node_parts(Entry,               Entry, unknown).

% Keep only the human-meaningful nodes: package keys (R://E or R://E:Action).
cycle:cycle_display_path(CyclePath0, CyclePath) :-
  findall(P,
          ( member(N, CyclePath0),
            cycle:cycle_node_package_key(N, P)
          ),
          P0),
  cycle:dedup_consecutive(P0, CyclePath).

% Strip nested context wrappers like X?{...} that can occur in trigger nodes.
cycle:cycle_strip_ctx(X?{_Ctx}, Out) :-
  !,
  cycle:cycle_strip_ctx(X, Out).
cycle:cycle_strip_ctx(X, X).

% Normalize to stable package keys: Repo://Entry or Repo://Entry:Action.
cycle:cycle_node_package_key(Node0, Key) :-
  cycle:cycle_strip_ctx(Node0, Node1),
  ( Node1 = R://E:A ->
      cycle:cycle_strip_ctx(E, E1),
      ( E1 = EAtom:Act0 -> Key = R://EAtom:Act0
      ; Key = R://E1:A
      )
  ; Node1 = R://E ->
      cycle:cycle_strip_ctx(E, E1),
      ( E1 = EAtom:Act0 -> Key = R://EAtom:Act0
      ; Key = R://E1
      )
  ; Node1 = grouped_package_dependency(_Strength, C, N, _PackageDeps):A ->
      Key = grouped(C, N):A
  ; Node1 = E:A ->
      cycle:cycle_strip_ctx(E, E1),
      atomic(E1),
      Key = E1:A
  ; fail
  ),
  !.

% Special case: keep a 2-element [X,X] list intact so a direct self-cycle can
% still be rendered as a cycle (instead of collapsing to a single node).
cycle:dedup_consecutive([X,X], [X,X]) :- !.
cycle:dedup_consecutive([], []).
cycle:dedup_consecutive([X|Xs], [X|Ys]) :-
  cycle:dedup_consecutive_(Xs, X, Ys).

cycle:dedup_consecutive_([], _Prev, []).
cycle:dedup_consecutive_([X|Xs], Prev, Ys) :-
  ( X == Prev ->
      cycle:dedup_consecutive_(Xs, Prev, Ys)
  ;
      Ys = [X|Rest],
      cycle:dedup_consecutive_(Xs, X, Rest)
  ).


%! cycle:find_cycle_via_triggers(+StartKey,+TriggersAVL,-CyclePath)
cycle:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath) :-
  config:print_prover_cycles_max_depth(MaxDepth),
  cycle:dfs_cycle(StartKey, StartKey, TriggersAVL, [StartKey], 0, MaxDepth, [StartKey], RevPath),
  reverse(RevPath, CyclePath),
  CyclePath = [StartKey|_].

% Fallback: find any cycle reachable from StartKey (StartKey itself may be a
% grouped dependency node, while the actual cycle is between package nodes).
cycle:find_cycle_via_triggers(StartKey, TriggersAVL, CyclePath) :-
  cycle:find_any_cycle_via_triggers(StartKey, TriggersAVL, CyclePath),
  !.

cycle:find_any_cycle_via_triggers(StartKey, TriggersAVL, CyclePath) :-
  config:print_prover_cycles_max_depth(MaxDepth),
  cycle:dfs_any_cycle(StartKey, TriggersAVL, [StartKey], 0, MaxDepth, RevCycle),
  reverse(RevCycle, CyclePath),
  CyclePath = [_|_].

% DFS that detects a back-edge to any node on the current path.
cycle:dfs_any_cycle(Node, TriggersAVL, PathRev, Depth, MaxDepth, CycleRev) :-
  Depth < MaxDepth,
  cycle:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Next, Neigh),
  ( memberchk(Next, PathRev) ->
      cycle:take_until(PathRev, Next, PrefixToNext),
      CycleRev = [Next|PrefixToNext]
  ; Depth1 is Depth + 1,
    cycle:dfs_any_cycle(Next, TriggersAVL, [Next|PathRev], Depth1, MaxDepth, CycleRev)
  ).

% Take prefix of PathRev until (and including) Stop.
cycle:take_until([Stop|_], Stop, [Stop]) :- !.
cycle:take_until([X|Xs], Stop, [X|Out]) :-
  cycle:take_until(Xs, Stop, Out).

% Fast cycle witness on "package keys" only (BFS with budget).
% This is used for printing: it prefers a short, human-meaningful cycle quickly
% over an exhaustive search through grouped/package_dependency nodes.
cycle:find_cycle_via_triggers_pkg(StartPkg, TriggersAVL, CyclePath) :-
  config:print_prover_cycles_max_depth(MaxDepth),
  Budget0 = 3000,
  sort([StartPkg], Visited0),
  cycle:bfs_cycle_pkg([q(StartPkg, 0, [StartPkg])], Visited0, StartPkg, TriggersAVL, MaxDepth, Budget0, RevCycle),
  reverse(RevCycle, CyclePath),
  CyclePath = [StartPkg|_],
  !.

cycle:bfs_cycle_pkg([q(Node, Depth, PathRev)|Queue], Visited0, Start, TriggersAVL, MaxDepth, Budget0, CycleRev) :-
  Budget0 > 0,
  ( Depth >= MaxDepth ->
      Budget1 is Budget0 - 1,
      cycle:bfs_cycle_pkg(Queue, Visited0, Start, TriggersAVL, MaxDepth, Budget1, CycleRev)
  ; cycle:trigger_neighbors_pkg(Node, TriggersAVL, NeighPkgs),
    ( memberchk(Start, NeighPkgs),
      Depth > 0 ->
        CycleRev = [Start|PathRev]
    ; findall(q(Next, Depth1, [Next|PathRev]),
              ( member(Next, NeighPkgs),
                Next \== Start,
                \+ memberchk(Next, Visited0),
                Depth1 is Depth + 1
              ),
              NewQs),
      findall(Next,
              member(q(Next,_,_), NewQs),
              NewNodes),
      append(Queue, NewQs, Queue1),
      append(Visited0, NewNodes, Visited1a),
      sort(Visited1a, Visited1),
      Budget1 is Budget0 - 1,
      cycle:bfs_cycle_pkg(Queue1, Visited1, Start, TriggersAVL, MaxDepth, Budget1, CycleRev)
    )
  ).

% Neighbors, but keep only stable package keys for cycle display.
cycle:trigger_neighbors_pkg(Node, TriggersAVL, Pkgs) :-
  cycle:trigger_neighbors(Node, TriggersAVL, Ns),
  findall(P,
          ( member(N, Ns),
            cycle:cycle_node_package_key(N, P)
          ),
          P0),
  sort(P0, Pkgs).

% -----------------------------------------------------------------------------
%  Proof-based cycle finding (fallback when triggers are insufficient)
% -----------------------------------------------------------------------------

cycle:find_cycle_via_proof(StartKey, ProofAVL, CyclePath) :-
  config:print_prover_cycles_max_depth(MaxDepth),
  cycle:dfs_cycle_proof(StartKey, StartKey, ProofAVL, [StartKey], 0, MaxDepth, [StartKey], RevPath),
  reverse(RevPath, CyclePath),
  CyclePath = [StartKey|_],
  !.

cycle:dfs_cycle_proof(Start, Node, ProofAVL, _Visited, Depth, _MaxDepth, Acc, [Start|Acc]) :-
  cycle:proof_neighbors(Node, ProofAVL, Neigh),
  memberchk(Start, Neigh),
  Depth > 0,
  !.
cycle:dfs_cycle_proof(Start, Node, ProofAVL, Visited, Depth, MaxDepth, Acc, Out) :-
  Depth < MaxDepth,
  cycle:proof_neighbors(Node, ProofAVL, Neigh),
  member(Next, Neigh),
  \+ memberchk(Next, Visited),
  Depth1 is Depth + 1,
  cycle:dfs_cycle_proof(Start, Next, ProofAVL, [Next|Visited], Depth1, MaxDepth, [Next|Acc], Out).

cycle:proof_neighbors(Node, ProofAVL, NeighKeys) :-
  ( get_assoc(rule(Node), ProofAVL, dep(_, Body)?_)
  ; get_assoc(assumed(rule(Node)), ProofAVL, dep(_, Body)?_)
  ),
  !,
  findall(K,
          ( member(Dep, Body),
            \+ constraint:is_constraint(Dep),
            prover:canon_literal(Dep, K, _)
          ),
          NeighKeys0),
  sort(NeighKeys0, NeighKeys).
cycle:proof_neighbors(_Node, _ProofAVL, []).


%! cycle:dfs_cycle(+Start,+Node,+Triggers,+Visited,+Depth,+MaxDepth,+Acc,-Out)
cycle:dfs_cycle(Start, Node, TriggersAVL, _Visited, Depth, _MaxDepth, Acc, [Start|Acc]) :-
  Depth > 0,
  cycle:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Start, Neigh),
  !.
cycle:dfs_cycle(Start, Node, TriggersAVL, Visited, Depth, MaxDepth, Acc, Out) :-
  Depth < MaxDepth,
  cycle:trigger_neighbors(Node, TriggersAVL, Neigh),
  member(Next, Neigh),
  \+ memberchk(Next, Visited),
  Depth1 is Depth + 1,
  cycle:dfs_cycle(Start, Next, TriggersAVL, [Next|Visited], Depth1, MaxDepth, [Next|Acc], Out).


%! cycle:trigger_neighbors(+Key,+TriggersAVL,-NeighborKeys)
%
% Neighbors are dependents of Key in the triggers graph, canonicalized to keys
% (dropping context) to keep the search space manageable.
cycle:trigger_neighbors(Key, TriggersAVL, NeighborKeys) :-
  ( get_assoc(Key, TriggersAVL, Dependents) -> true ; Dependents = [] ),
  findall(K,
          ( member(Dep, Dependents),
            prover:canon_literal(Dep, K, _)
          ),
          Ks),
  sort(Ks, NeighborKeys).