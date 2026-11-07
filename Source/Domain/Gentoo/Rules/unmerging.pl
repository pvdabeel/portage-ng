/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> UNMERGING
Unmerge rule set (depclean): planning laws + removal bindings.

The rule set depclean hands the generic prover to order uninstalls
(`prover:prove_once(unmerging, ...)`).  The *planning laws* (rule/2) are
the same three laws the ordering rule set uses — a step can be placed
once everything it requires is available — only the bindings differ:

  - step/1     : is this the unmerge of a removable package?
  - requires/2 : what does an unmerge require before it can be placed —
                 the release of every claim on the package, i.e. the
                 earlier unmerge of every removable consumer;
  - world/2    : nothing, on a real system.  Merge ordering can cite the
                 installed world because a dependency may already be
                 provided; an installed consumer's claim is a present
                 VDB fact, so the only release is the claimant's own
                 unmerge.  (Only the world_override/1 test hook lives
                 here.)

Cycles fall through the currently_proving guard into retained-claim
assumptions (`assumed(unreachable(R, C))`): the claimant C could not be
ordered before the package R it depends on, so R unmerges while C is
still installed — reported, not silently cut.  The wave projection over
the resulting availability proofs is the orderer's
(orderer:provider_edges/2 + orderer:wave_assignment/3); depclean flattens
the waves to the uninstall order.

Deliberately conservative: a claim by a removable consumer always
orders the consumer first, even when another kept package could satisfy
the consumer's dependency — matching the reverse-dependency order
traditional Portage uses for depclean unmerges.
*/

:- module(unmerging, []).

:- use_module(library(assoc)).

% =============================================================================
%  UNMERGING declarations
% =============================================================================

% -----------------------------------------------------------------------------
% Rule set: the planning laws
% -----------------------------------------------------------------------------
%
% Identical in shape to the ordering laws (Rules/ordering.pl), and for
% the same reasons: each clause is deterministic (if-then-else, not
% alternative clauses) so the prover's cycle-stack pops fire eagerly,
% and the `\+ prover:currently_proving/1` guard is what turns a cyclic
% claim chain into a world lookup / retained-claim assumption instead
% of a prover cycle-break marker.

%! unmerging:rule(+Literal, -Body)
%
% The unmerge-pass rule set. One clause per literal functor, each
% deterministic. The first clause strips the optional ?{Ctx}
% proof-context wrapper the prover's literal canonicalization may
% re-attach.

rule(Literal?{_}, Body) :-
  !,
  unmerging:rule(Literal, Body).

% An unmerge can be placed once every claim on the package is released:
rule(scheduled(H), Conds) :-
  unmerging:step(H),
  findall(available(H, D), unmerging:requires(H, D), Conds).

% A claim is released when the claimant is unmerged earlier, or — the
% cyclic case — when the world releases it (test hook only), or —
% failing both — by recording a retained-claim assumption instead of
% failing the pass:
rule(available(H, D), Body) :-
  (   unmerging:step(D),
      \+ prover:currently_proving(scheduled(D))
  ->  Body = [scheduled(D)]
  ;   unmerging:world(H, D)
  ->  Body = []
  ;   Body = [assumed(unreachable(H, D))]
  ).

rule(assumed(unreachable(_, _)), []).


% -----------------------------------------------------------------------------
% Pass state
% -----------------------------------------------------------------------------

%! unmerging:with_unmerge_pass(+Removable, :Goal)
%
% Run Goal with the removable set published for the bindings (step/1 and
% the consumer index) and the claim index prepared. Removable is a list
% of nodes (VDB Repo://Entry terms on a real system; plain atoms in the
% law unit tests).
%
% The index is built EAGERLY here, before Goal runs the unmerge prove:
% reading the VDB dependency models goes through the query layer's
% inlined model construction, which dispatches rules through the active
% rule module (prover:rule_call/2). Inside prove_once(unmerging, ...)
% that module is `unmerging` — which has no clauses for dependency
% literals — so a lazily built index would silently lose every claim
% whose model was not already memo-cached. Prepared here, the queries
% run under the default (resolving) rules.

with_unmerge_pass(Removable, Goal) :-
  sort(Removable, Sorted),
  setup_call_cleanup(
    ( nb_setval(portage_unmerging_set, Sorted),
      unmerging:prepare_pass
    ),
    Goal,
    ( nb_setval(portage_unmerging_set, []),
      nb_setval(portage_unmerging_consumers, none)
    )).


%! unmerging:prepare_pass
%
% Build and publish the claim index for the current removable set (see
% with_unmerge_pass/2 for why this must happen outside the prove).

prepare_pass :-
  unmerging:build_consumer_index(Idx),
  nb_setval(portage_unmerging_consumers, Idx).


%! unmerging:removable(-Set)
%
% The removable ord_set published by with_unmerge_pass/2.

removable(Set) :-
  nb_current(portage_unmerging_set, Set),
  Set \== [].


% -----------------------------------------------------------------------------
% Bindings: steps and claims
% -----------------------------------------------------------------------------

%! unmerging:step(+H)
%
% H is the unmerge of a removable package.

step(Node:unmerge) :-
  unmerging:removable(Set),
  ord_memberchk(Node, Set).


%! unmerging:requires(+H, -D)
%
% Hard requirement: before package R can be unmerged, every claim on it
% must be released — each removable consumer C (a package whose runtime
% dependency model resolves to R) is unmerged first. Consumers outside
% the removable set never appear here: a kept consumer would have kept R
% in the required closure, so R would not be removable at all.

requires(R:unmerge, C:unmerge) :-
  unmerging:consumer_index(Idx),
  get_assoc(R, Idx, Consumers),
  member(C, Consumers).


%! unmerging:world_override(+D)
%
% Test hook: unit tests assert world facts here to exercise the laws
% without a VDB (see Source/Test/Unit/synthetictest.pl).

:- dynamic world_override/1.


%! unmerging:world(+H, +D)
%
% On a real system: nothing. An installed consumer's claim is a present
% fact in the VDB — there is no "already provided" escape like merge
% ordering has — so the only release is the claimant's earlier unmerge,
% and cyclic claim chains surface as retained-claim assumptions.

world(_H, D) :-
  unmerging:world_override(D).


% -----------------------------------------------------------------------------
% Per-pass consumer index
% -----------------------------------------------------------------------------

%! unmerging:consumes_override(?C, ?R)
%
% Test hook: unit tests assert "C consumes R" facts here to exercise the
% laws without a VDB. When any override is present the VDB reading is
% skipped entirely.

:- dynamic consumes_override/2.


%! unmerging:consumer_index(-Idx)
%
% The claim index for the current pass: an assoc mapping each removable
% package R to the removable consumers whose runtime dependency models
% resolve to R (the reverse reading of depclean:direct_deps_installed/2,
% restricted to the removable set). Normally prepared eagerly by
% with_unmerge_pass/2; the lazy fallback only serves direct binding use
% outside a prover pass.

consumer_index(Idx) :-
  ( nb_current(portage_unmerging_consumers, Idx0), Idx0 \== none ->
      Idx = Idx0
  ; unmerging:build_consumer_index(Idx),
    nb_setval(portage_unmerging_consumers, Idx)
  ).


%! unmerging:build_consumer_index(-Idx)
%
% Build the claim index from the consumes_override/2 test facts when
% present, from the VDB dependency models otherwise.

build_consumer_index(Idx) :-
  unmerging:removable(Set),
  ( unmerging:consumes_override(_, _) ->
      findall(R-C,
              ( unmerging:consumes_override(C, R),
                ord_memberchk(C, Set),
                ord_memberchk(R, Set)
              ),
              Pairs0)
  ; findall(R-C,
            ( member(C, Set),
              ( depclean:direct_deps_installed(C, Deps) -> true ; Deps = [] ),
              member(R, Deps),
              ord_memberchk(R, Set),
              R \== C
            ),
            Pairs0)
  ),
  sort(Pairs0, Pairs),
  empty_assoc(I0),
  foldl(unmerging:consumer_index_put, Pairs, I0, Idx).


%! unmerging:consumer_index_put(+Pair, +IdxIn, -IdxOut)
%
% Add one R-C claim pair to the index.

consumer_index_put(R-C, In, Out) :-
  ( get_assoc(R, In, Cs) -> true ; Cs = [] ),
  put_assoc(R, In, [C|Cs], Out).
