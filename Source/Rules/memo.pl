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
*/

:- module(memo, [clear_caches/0]).


% =============================================================================
%  Thread-local caching facts
% =============================================================================

:- thread_local memo:effective_use_fact/3.
:- thread_local memo:selected_cn_snap_/3.
:- thread_local memo:blocked_cn_source_snap_/3.
:- thread_local memo:cn_domain_reject_/2.
:- thread_local memo:rdepend_vbounds_cache_/5.
:- thread_local memo:keyword_cache_/6.
:- thread_local memo:iuse_default_cache_/3.
:- thread_local memo:iuse_info_cache_/3.
:- thread_local memo:eff_use_cache_/4.
:- thread_local memo:self_use_cache_/4.


%! clear_caches is det.
%
%  Retract all thread-local caching facts managed by this module.

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
