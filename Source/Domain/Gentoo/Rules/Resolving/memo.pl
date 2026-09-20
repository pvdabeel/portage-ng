/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> MEMO
Thread-local declarations and memoization support for the rules engine.

All thread-local caching facts and the clear_caches/0 predicate that resets
them live here, isolating mutable state from declarative rule definitions.

== Cache facts ==

Each thread-local predicate caches a different aspect of resolver state:

| Predicate                          | Cached data                                    |
|------------------------------------|------------------------------------------------|
| effective_use_fact/3               | Effective USE set for a repo entry (candidate)  |
| memo_selected_cn_snap (nb_setval)  | AVL of selected CN candidates (keyed by C-N)    |
| memo_blocked_cn_source_snap (nb)   | AVL of blocked CN sources (keyed by C-N)        |
| cn_domain_reject_/2               | Rejected candidates per CN-domain key           |
| rdepend_vbounds_cache_/5           | Self-RDEPEND version bounds for a (C,N) pair    |
| keyword_cache_/6                   | Keyword-filtered candidate lists per action     |
| iuse_default_cache_/3              | Per-entry IUSE default map (AVL)                |
| iuse_info_cache_/3                 | Per-entry IUSE flag set + IUSE(+) set           |
| eff_use_cache_/4                   | Per-entry effective USE resolution               |
| self_use_cache_/4                  | Per-entry self-context USE resolution            |
| candidate_bwu_/3                   | Per-(C,N) union of bracketed USE from all edges  |
|                                    | (seeded from full dep tree, then provider        |
|                                    | :install/:run and grouped_dep contexts)        |

All caches are invalidated together by clear_caches/0 at the start of each
proof run.  Individual caches (selected_cn_snap_, blocked_cn_source_snap_,
cn_domain_reject_) may also be saved/restored by heuristic:init_state/0 and
heuristic:cleanup_state/0 during reprove retries.
*/

:- module(memo, []).

:- use_module(library(assoc), [empty_assoc/1]).

% =============================================================================
%  MEMO declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Thread-local caching facts
% -----------------------------------------------------------------------------

:- thread_local memo:effective_use_fact/3.      % effective_use_fact(Repo, Entry, EnabledUseSet)
:- thread_local memo:cn_domain_reject_/2.       % cn_domain_reject_(Key, RejectedSet)
:- thread_local memo:rdepend_vbounds_cache_/5.  % rdepend_vbounds_cache_(Repo, Entry, C, N, ExtraDeps)
:- thread_local memo:keyword_cache_/6.          % keyword_cache_(Action, C, N, SlotReq, LockKey, Sorted)
:- thread_local memo:iuse_default_cache_/3.     % iuse_default_cache_(Repo, Entry, DefaultAVL)
:- thread_local memo:iuse_info_cache_/3.        % iuse_info_cache_(Repo, Entry, iuse_info(Set, PlusSet))
:- thread_local memo:eff_use_cache_/4.          % eff_use_cache_(Repo, Entry, Use, State)
:- thread_local memo:self_use_cache_/4.         % self_use_cache_(Repo, Entry, Use, State)
:- thread_local memo:assumption_reason_cache_/4. % assumption_reason_cache_(Action, C, N, Reason)
:- thread_local memo:visibility_override_/2.    % visibility_override_(Repo, Entry) -- entry passes eligibility despite mask/keyword filtering (portage-ng#14 last-resort dep concretization)
:- thread_local memo:keyword_suggestion_cache_/3. % keyword_suggestion_cache_(C, N, SuggestedKw)
:- thread_local memo:requse_violation_/3.        % requse_violation_(C, N, ViolDesc)
:- thread_local memo:slot_conflict_/3.          % slot_conflict_(C, N, Entries)
:- thread_local memo:candidate_bwu_/3.          % candidate_bwu_(C, N, BWU) -- effective (HARD beats EQ)
:- thread_local memo:candidate_bwu_hard_/3.     % candidate_bwu_hard_(C, N, BWU) -- forcing directives ([F]/[F?]/[!F]/[!F?])
:- thread_local memo:candidate_bwu_eq_/3.       % candidate_bwu_eq_(C, N, BWU) -- following directives ([F=]/[!F=])
:- thread_local memo:bwu_force_seen_/3.         % bwu_force_seen_(C, N, HardEn) -- last HARD set processed by the shared-dep USE forcing pass (#91 sub-mechanism B)
:- thread_local memo:bwu_force_pending_/3.      % bwu_force_pending_(C, N, ForceEn) -- forces learned this pass, awaiting the end-of-pass batched reprove (#94)
:- thread_local memo:bwu_eq_origin_/6.          % bwu_eq_origin_(C, N, Flag, Projected, Mode, Consumer) -- which consumer's [F=]/[!F=] edge projected Projected onto provider (C,N) (#121)
:- thread_local memo:eq_follow_pending_/4.      % eq_follow_pending_(C, N, BWU, provider(PC,PN)) -- consumer-side equality follows learned this pass, awaiting the same batched reprove (#121)
:- thread_local memo:dep_model_cache_/5.        % dep_model_cache_(Repo, Id, Phase, Key, Merged) -- dependency-model query results, hazard-encoded key (see query.pl)
:- thread_local memo:dep_model_choice_cns_/3.   % dep_model_choice_cns_(Repo, Id, CNs) -- static C-N pairs appearing in choice groups of the entry's dep metadata


%! memo:clear_caches
%
% Retracts all thread-local caching facts managed by this module.
% Called at the start of each proof run to ensure a clean state.

clear_caches :-
  retractall(memo:effective_use_fact(_, _, _)),
  empty_assoc(EmptyAVL),
  nb_setval(memo_selected_cn_snap, EmptyAVL),
  nb_setval(memo_blocked_cn_source_snap, EmptyAVL),
  nb_setval(memo_slot_meta_cache, EmptyAVL),
  retractall(memo:cn_domain_reject_(_, _)),
  retractall(memo:rdepend_vbounds_cache_(_, _, _, _, _)),
  retractall(memo:keyword_cache_(_, _, _, _, _, _)),
  retractall(memo:iuse_default_cache_(_, _, _)),
  retractall(memo:iuse_info_cache_(_, _, _)),
  retractall(memo:eff_use_cache_(_, _, _, _)),
  retractall(memo:self_use_cache_(_, _, _, _)),
  retractall(memo:assumption_reason_cache_(_, _, _, _)),
  retractall(memo:visibility_override_(_, _)),
  retractall(memo:keyword_suggestion_cache_(_, _, _)),
  retractall(memo:requse_violation_(_, _, _)),
  retractall(memo:slot_conflict_(_, _, _)),
  retractall(memo:candidate_bwu_(_, _, _)),
  retractall(memo:candidate_bwu_hard_(_, _, _)),
  retractall(memo:candidate_bwu_eq_(_, _, _)),
  retractall(memo:bwu_eq_origin_(_, _, _, _, _, _)),
  retractall(memo:eq_follow_pending_(_, _, _, _)),
  retractall(memo:dep_model_cache_(_, _, _, _, _)),
  retractall(memo:dep_model_choice_cns_(_, _, _)).
