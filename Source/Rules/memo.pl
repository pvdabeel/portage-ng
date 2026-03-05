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
| selected_cn_snap_/3               | Snapshot of selected CN candidates              |
| blocked_cn_source_snap_/3          | Snapshot of blocked CN source entries            |
| cn_domain_reject_/2               | Rejected candidates per CN-domain key           |
| rdepend_vbounds_cache_/5           | Self-RDEPEND version bounds for a (C,N) pair    |
| keyword_cache_/6                   | Keyword-filtered candidate lists per action     |
| iuse_default_cache_/3              | Per-entry IUSE default map (AVL)                |
| iuse_info_cache_/3                 | Per-entry IUSE flag set + IUSE(+) set           |
| eff_use_cache_/4                   | Per-entry effective USE resolution               |
| self_use_cache_/4                  | Per-entry self-context USE resolution            |

All caches are invalidated together by clear_caches/0 at the start of each
proof run.  Individual caches (selected_cn_snap_, blocked_cn_source_snap_,
cn_domain_reject_) may also be saved/restored by heuristic:init_state/0 and
heuristic:cleanup_state/0 during reprove retries.
*/

:- module(memo, [clear_caches/0]).


% =============================================================================
%  Thread-local caching facts
% =============================================================================

:- thread_local memo:effective_use_fact/3.      % effective_use_fact(Repo, Entry, EnabledUseSet)
:- thread_local memo:selected_cn_snap_/3.       % selected_cn_snap_(C, N, CandidateList)
:- thread_local memo:blocked_cn_source_snap_/3. % blocked_cn_source_snap_(C, N, SourceList)
:- thread_local memo:cn_domain_reject_/2.       % cn_domain_reject_(Key, RejectedSet)
:- thread_local memo:rdepend_vbounds_cache_/5.  % rdepend_vbounds_cache_(Repo, Entry, C, N, ExtraDeps)
:- thread_local memo:keyword_cache_/6.          % keyword_cache_(Action, C, N, SlotReq, LockKey, Sorted)
:- thread_local memo:iuse_default_cache_/3.     % iuse_default_cache_(Repo, Entry, DefaultAVL)
:- thread_local memo:iuse_info_cache_/3.        % iuse_info_cache_(Repo, Entry, iuse_info(Set, PlusSet))
:- thread_local memo:eff_use_cache_/4.          % eff_use_cache_(Repo, Entry, Use, State)
:- thread_local memo:self_use_cache_/4.         % self_use_cache_(Repo, Entry, Use, State)


%! clear_caches is det.
%
%  Retract all thread-local caching facts managed by this module.
%  Called at the start of each proof run to ensure a clean state.

clear_caches :-
  retractall(memo:effective_use_fact(_, _, _)),
  retractall(memo:selected_cn_snap_(_, _, _)),
  retractall(memo:blocked_cn_source_snap_(_, _, _)),
  retractall(memo:cn_domain_reject_(_, _)),
  retractall(memo:rdepend_vbounds_cache_(_, _, _, _, _)),
  retractall(memo:keyword_cache_(_, _, _, _, _, _)),
  retractall(memo:iuse_default_cache_(_, _, _)),
  retractall(memo:iuse_info_cache_(_, _, _)),
  retractall(memo:eff_use_cache_(_, _, _, _)),
  retractall(memo:self_use_cache_(_, _, _, _)).
