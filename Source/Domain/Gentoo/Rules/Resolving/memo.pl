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
| memo_selected_cn_snap (nbstore)    | Selected CN candidates (keyed by C-N)           |
| memo_blocked_cn_source_snap (nbstore) | Blocked CN sources (keyed by C-N)            |
| memo_slot_meta_cache (nbstore)     | Slot metadata list per Repo-Id                  |
| cn_domain_reject_/2               | Rejected candidates per CN-domain key           |
| rdepend_vbounds_cache_/5           | Self-RDEPEND version bounds for a (C,N) pair    |
| rdepend_vbounds_walked_/2          | Parents whose RDEPEND bounds are all cached     |
| overlap_count_cache_/4             | Active `||` groups of a parent naming a (C,N)   |
| keyword_cache_/6                   | Keyword-filtered candidate lists per action     |
| iuse_info_cache_/3                 | Per-entry IUSE flag set + IUSE(+) set (also     |
|                                    | answers the per-flag default polarity)          |
| enabled_use_cache_/3               | Per-entry recorded (VDB) enabled USE set         |
| use_expand_selection_cache_/2      | Per-USE_EXPAND-prefix "explicitly selected" flag |
| eff_use_cache_/4                   | Per-entry effective USE resolution               |
| self_use_cache_/4                  | Per-entry self-context USE resolution            |
| candidate_bwu_/3                   | Per-(C,N) union of bracketed USE from all edges  |
|                                    | (seeded from full dep tree, then provider        |
|                                    | :install/:run and grouped_dep contexts)        |
| memo_bwu_seed_seen (nbstore)       | Edges already seeded into candidate_bwu_ this    |
|                                    | pass (ranking:seed_first_time/3)                 |

The nbstore entries are per-thread hash stores (Source/Logic/nbstore.pl)
rather than thread_local facts: they are rewritten thousands of times per
proof, and writes to thread_local predicates serialise process-wide.  The
per-(C,N) BWU tables (candidate_bwu_ and its HARD/EQ components,
bwu_force_seen_, bwu_eq_origin_) were measured as nbstore entries too and
stayed facts: a store lookup costs about six inferences against one for
an indexed fact, and on the KDE categories at ten threads the exchange was
+1.3% inferences for no wall-clock gain.

All caches are invalidated together by clear_caches/0 at the start of each
proof run.  Individual caches (memo_selected_cn_snap,
memo_blocked_cn_source_snap, cn_domain_reject_) may also be saved/restored
by heuristic:init_state/0 and heuristic:cleanup_state/0 during reprove
retries.

== Knowledge caches ==

Seven of the caches are functions of the knowledge base alone — repository
and VDB metadata plus the loaded profile and user configuration — and of
nothing the proof decides: iuse_info_cache_, enabled_use_cache_,
use_expand_selection_cache_, entry_version_pins_, entry_equality_usedeps_,
dep_model_choice_cns_ and self_use_cache_ (an entry's own IUSE state read
through eapi:categorize_use_for_entry/4).  A bulk harness that proves
thousands of entries against a knowledge base it never modifies may pin
the knowledge (with_pinned_knowledge/1): clear_caches/0 then keeps these
from one proof to the next, so a popular dependency's IUSE set is derived
once per worker thread instead of once per proof (about one write in four
of a proof's memo traffic, and every write to a thread_local predicate
takes a process-wide lock).  Outside a pin they are cleared with
everything else; no reload hook is needed anywhere.

== Variant caches ==

Three more caches are functions of the knowledge base and of the
variant-mode USE overrides (variant:use_override/4) only:
eff_use_cache_ (the USE precedence chain, which starts at the override),
and rdepend_vbounds_cache_ / rdepend_vbounds_walked_ /
overlap_count_cache_, which read the parent's effective USE.  They are
kept across proofs while the knowledge is pinned, like the knowledge
caches, and cleared whenever an override is installed or removed
(variant:apply/1, variant:cleanup/0 call clear_variant_caches/0), so
within a variant scope they have the per-proof lifetime they always had.
*/

:- module(memo, []).

% =============================================================================
%  MEMO declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Thread-local caching facts
% -----------------------------------------------------------------------------

:- thread_local memo:effective_use_fact/3.      % effective_use_fact(Repo, Entry, EnabledUseSet)
:- thread_local memo:cn_domain_reject_/2.       % cn_domain_reject_(Key, RejectedSet)
:- thread_local memo:rdepend_vbounds_cache_/5.  % rdepend_vbounds_cache_(Repo, Entry, C, N, ExtraDeps)
:- thread_local memo:rdepend_vbounds_walked_/2. % rdepend_vbounds_walked_(Repo, Entry) -- every (C,N) of the entry's RDEPEND bounds is cached
:- thread_local memo:overlap_count_cache_/4.    % overlap_count_cache_(Repo, Entry, C-N, Count) -- active || groups of the entry naming (C,N)
:- thread_local memo:keyword_cache_/6.          % keyword_cache_(Action, C, N, SlotReq, LockKey, Sorted)
:- thread_local memo:iuse_info_cache_/3.        % iuse_info_cache_(Repo, Entry, iuse_info(Set, PlusSet))
:- thread_local memo:enabled_use_cache_/3.      % enabled_use_cache_(Repo, Entry, EnabledSet) -- sorted use/1 metadata (VDB built USE)
:- thread_local memo:use_expand_selection_cache_/2. % use_expand_selection_cache_(Prefix, true|false) -- some global USE flag carries the USE_EXPAND prefix
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
:- thread_local memo:entry_version_pins_/2.     % entry_version_pins_(Repo://Entry, Pins) -- hard version pins in DEPEND/RDEPEND/BDEPEND (#123)
:- thread_local memo:entry_equality_usedeps_/2. % entry_equality_usedeps_(Repo://Entry, EqDeps) -- unconditional [F=]/[!F=] USE deps in DEPEND/RDEPEND/BDEPEND
:- thread_local memo:dep_model_cache_/5.        % dep_model_cache_(Repo, Id, Phase, Key, Merged) -- dependency-model query results, hazard-encoded key (see query.pl)
:- thread_local memo:dep_model_choice_cns_/3.   % dep_model_choice_cns_(Repo, Id, CNs) -- static C-N pairs appearing in choice groups of the entry's dep metadata

:- dynamic memo:knowledge_pinned/0.             % set for the duration of with_pinned_knowledge/1 (shared by all threads)


%! memo:clear_caches
%
% Resets the caching facts managed by this module.  Called at the start
% of each proof run to ensure a clean state.  While the knowledge base is
% pinned (with_pinned_knowledge/1) the knowledge and variant caches are
% kept.

clear_caches :-
  memo:clear_proof_caches,
  ( memo:knowledge_pinned ->
      true
  ; memo:clear_knowledge_caches
  ).


%! memo:clear_proof_caches
%
% Resets the caches whose content depends on the proof in progress.

clear_proof_caches :-
  retractall(memo:effective_use_fact(_, _, _)),
  nbstore:reset(memo_selected_cn_snap),
  nbstore:reset(memo_blocked_cn_source_snap),
  nbstore:reset(memo_slot_meta_cache),
  nbstore:reset(memo_bwu_seed_seen),
  retractall(memo:cn_domain_reject_(_, _)),
  retractall(memo:keyword_cache_(_, _, _, _, _, _)),
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
  retractall(memo:dep_model_cache_(_, _, _, _, _)).


%! memo:clear_knowledge_caches
%
% Resets the caches that are functions of the knowledge base alone (see
% the module documentation), and with them the variant caches, which
% depend on the knowledge base as well.

clear_knowledge_caches :-
  retractall(memo:iuse_info_cache_(_, _, _)),
  retractall(memo:enabled_use_cache_(_, _, _)),
  retractall(memo:use_expand_selection_cache_(_, _)),
  retractall(memo:entry_version_pins_(_, _)),
  retractall(memo:entry_equality_usedeps_(_, _)),
  retractall(memo:dep_model_choice_cns_(_, _, _)),
  retractall(memo:self_use_cache_(_, _, _, _)),
  memo:clear_variant_caches.


%! memo:clear_variant_caches
%
% Resets the caches that depend on the variant-mode USE overrides (see
% the module documentation).  Called from variant:apply/1 and
% variant:cleanup/0 around every override.

clear_variant_caches :-
  retractall(memo:eff_use_cache_(_, _, _, _)),
  retractall(memo:rdepend_vbounds_cache_(_, _, _, _, _)),
  retractall(memo:rdepend_vbounds_walked_(_, _)),
  retractall(memo:overlap_count_cache_(_, _, _, _)).


%! memo:with_pinned_knowledge(:Goal)
%
% Runs Goal with the knowledge base declared immutable: repository and
% VDB metadata, profile and user configuration are not reloaded or
% edited while Goal runs, so every thread may keep its knowledge caches
% across the proofs it performs.  The pin is a process-wide fact so the
% worker threads a bulk harness spawns inherit it.  On exit the calling
% thread's knowledge caches are cleared (worker threads end with the
% harness).  Nested pins are governed by the outermost one.

memo:with_pinned_knowledge(Goal) :-
  ( memo:knowledge_pinned ->
      call(Goal)
  ; setup_call_cleanup(assertz(memo:knowledge_pinned),
                       Goal,
                       ( retractall(memo:knowledge_pinned),
                         memo:clear_knowledge_caches
                       ))
  ).
