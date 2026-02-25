/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> QUERY
An implementation of a query language for the knowledge base
*/

:- module(query,[]).


tilde_suffix_match(S, S) :- !.
tilde_suffix_match(S, CandS) :-
  atom_concat(S, Rev, CandS),
  atom_concat('-r', _, Rev).

% =============================================================================
%  OPTIONAL RUNTIME CALLSITE STATS (debugging)
% =============================================================================
%
% Goal-expansion should remove most `query:search/2` calls at compile time.
% Remaining runtime calls can happen when:
% - the call was constructed dynamically (e.g. via call/1)
% - goal-expansion didn't run due to load order / compilation context
% - a query form falls back to the runtime `search/2` clauses
%
% Additionally, SWI-Prolog's profiler often attributes work of meta-calls (call/1)
% to the caller, so `query:search/2` can appear hot even when executing compiled
% cache-level goals. These callsite stats help answer: "who is still calling
% query:search/2 at runtime?"

:- dynamic query:search_callsite_stats_enabled/0.
:- dynamic query:search_callsite/4. % File, Line, PI, Count
:- dynamic query:search_callsite_sig/5. % File, Line, PI, Sig, Count
:- dynamic query:search_callsite_sample_rate/1.

% Default: sample 1 out of 4096 calls to keep overhead low even on huge runs.
query:search_callsite_sample_rate(4096).

query:enable_search_callsite_stats :-
  ( query:search_callsite_stats_enabled -> true
  ; assertz(query:search_callsite_stats_enabled)
  ).

query:disable_search_callsite_stats :-
  retractall(query:search_callsite_stats_enabled).

query:reset_search_callsites :-
  retractall(query:search_callsite(_,_,_,_)),
  retractall(query:search_callsite_sig(_,_,_,_,_)),
  nb_setval(query_search_callsite_counter, 0).

query:set_search_callsite_sample_rate(Rate) :-
  integer(Rate),
  Rate > 0,
  retractall(query:search_callsite_sample_rate(_)),
  assertz(query:search_callsite_sample_rate(Rate)).

query:report_search_callsites(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI,
          query:search_callsite(File, Line, PI, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite']),
  format('  ~`-t~80|~n', []),
  query:print_search_callsite_rows(Rows, TopN, 1).

query:report_search_callsites_sig(TopN) :-
  ( integer(TopN), TopN > 0 -> true ; TopN = 50 ),
  findall(Count-File-Line-PI-Sig,
          query:search_callsite_sig(File, Line, PI, Sig, Count),
          Rows0),
  keysort(Rows0, RowsAsc),
  reverse(RowsAsc, Rows),
  format('~n>>> query:search/2 runtime callsites (signature breakdown, Top ~d)~n~n', [TopN]),
  format('  ~` t~d~8|  ~` t~s~8|  ~` t~s~s~n', [8, 'Count', 'Line', 'Callsite / Signature']),
  format('  ~`-t~80|~n', []),
  query:print_search_callsite_sig_rows(Rows, TopN, 1).

query:print_search_callsite_sig_rows([], _, _) :- !.
query:print_search_callsite_sig_rows(_, TopN, I) :- I > TopN, !.
query:print_search_callsite_sig_rows([Count-File-Line-PI-Sig|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n      ~w~n', [Count, File, Line, PI, Sig]),
  I2 is I + 1,
  query:print_search_callsite_sig_rows(Rest, TopN, I2).

query:print_search_callsite_rows([], _, _) :- !.
query:print_search_callsite_rows(_, TopN, I) :- I > TopN, !.
query:print_search_callsite_rows([Count-File-Line-PI|Rest], TopN, I) :-
  format('  ~` t~d~8|  ~w:~w~n      ~w~n', [Count, File, Line, PI]),
  I2 is I + 1,
  query:print_search_callsite_rows(Rest, TopN, I2).

query:maybe_record_search_callsite(Q, RepoEntry) :-
  ( query:search_callsite_stats_enabled ->
      query:maybe_record_search_callsite_sampled(Q, RepoEntry)
  ; true
  ).

query:maybe_record_search_callsite_sampled(Q, RepoEntry) :-
  ( query:search_callsite_sample_rate(Rate) -> true ; Rate = 4096 ),
  ( nb_current(query_search_callsite_counter, C0) -> true ; C0 = 0 ),
  C is C0 + 1,
  nb_setval(query_search_callsite_counter, C),
  ( 0 is C mod Rate ->
      nb_setval(query_search_callsite_last_q, Q),
      nb_setval(query_search_callsite_last_entry, RepoEntry),
      query:record_search_callsite
  ; true
  ).

query:record_search_callsite :-
  ( prolog_current_frame(F),
    prolog_frame_attribute(F, parent, Parent0),
    query:find_non_trivial_caller_frame(Parent0, CallerFrame0),
    query:find_external_callsite_frame(CallerFrame0, CallerFrame),
    query:frame_callsite(CallerFrame, File, Line, PI),
    ( nb_current(query_search_callsite_last_q, Q) -> true ; Q = unknown ),
    ( nb_current(query_search_callsite_last_entry, E) -> true ; E = unknown ),
    query:search_call_signature(Q, E, Sig)
  -> with_mutex(query_search_callsite,
       ( ( retract(query:search_callsite(File, Line, PI, N0)) -> true ; N0 = 0 ),
         N is N0 + 1,
         assertz(query:search_callsite(File, Line, PI, N)),
         ( ( retract(query:search_callsite_sig(File, Line, PI, Sig, S0)) -> true ; S0 = 0 ),
           S is S0 + 1,
           assertz(query:search_callsite_sig(File, Line, PI, Sig, S))
         )
       ))
  ; true
  ).

% A cheap signature for sampled calls: helps identify which query forms are
% still reaching runtime `query:search/2`.
query:search_call_signature(Q, RepoEntry, sig(Kind, Head, Flags, EntryKind)) :-
  ( is_list(Q) ->
      Kind = list,
      length(Q, Len),
      Head = list(Len),
      query:search_sig_flags(Q, Flags0),
      sort(Flags0, Flags)
  ; compound(Q) ->
      Kind = compound,
      ( Q = select(Key, Op, _Value) ->
          query:select_sig_op(Op, OpTag),
          Head = select(Key, OpTag)
      ; functor(Q, F, A),
        Head = F/A
      ),
      Flags = []
  ; Kind = other,
    Head = other,
    Flags = []
  ),
  ( RepoEntry = _Repo://_Id -> EntryKind = op_slash_colon2
  ; EntryKind = other
  ).

query:select_sig_op(Op, OpTag) :-
  ( var(Op) ->
      OpTag = var
  ; atomic(Op) ->
      OpTag = Op
  ; compound(Op) ->
      functor(Op, F, A),
      ( Op = constraint(Inner, _Out) ->
          query:constraint_inner_tag(Inner, InnerTag),
          OpTag = constraint(InnerTag)
      ; OpTag = F/A
      )
  ; OpTag = other
  ).

query:constraint_inner_tag(Inner, Tag) :-
  ( var(Inner) -> Tag = var
  ; Inner == [] -> Tag = empty
  ; is_list(Inner) ->
      length(Inner, L),
      Tag = list(L)
  ; Tag = other
  ).

query:search_sig_flags([], []) :- !.
query:search_sig_flags([H|T], [Flag|Rest]) :-
  ( compound(H) ->
      functor(H, F, A),
      Flag = F/A
  ; Flag = atom
  ),
  query:search_sig_flags(T, Rest).

query:find_non_trivial_caller_frame(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = 0.
query:find_non_trivial_caller_frame(Frame0, Frame) :-
  ( query:frame_predicate_indicator(Frame0, PI),
    query:skip_callsite_pi(PI)
  -> ( prolog_frame_attribute(Frame0, parent, Parent),
       query:find_non_trivial_caller_frame(Parent, Frame)
     )
  ; Frame = Frame0
  ).

query:skip_callsite_pi(query:search/2).
query:skip_callsite_pi(query:memoized_search/2).
query:skip_callsite_pi(search/2).
query:skip_callsite_pi(system:call/1).
query:skip_callsite_pi(system:once/1).
query:skip_callsite_pi(apply:call_/2).
query:skip_callsite_pi(apply:maplist_/3).
query:skip_callsite_pi(apply:include_/3).
query:skip_callsite_pi(apply:exclude_/3).

query:frame_predicate_indicator(Frame, PI) :-
  prolog_frame_attribute(Frame, predicate_indicator, PI),
  !.
query:frame_predicate_indicator(_Frame, unknown/0).

query:frame_callsite(Frame, File, Line, PI) :-
  query:frame_predicate_indicator(Frame, PI),
  ( prolog_frame_attribute(Frame, clause, ClauseRef),
    clause_property(ClauseRef, file(File0))
  -> File = File0
  ; File = '<unknown>'
  ),
  ( prolog_frame_attribute(Frame, clause, ClauseRef2),
    ( clause_property(ClauseRef2, line(Line0))
    ; clause_property(ClauseRef2, line_count(Line0))
    )
  -> Line = Line0
  ; Line = '?'
  ).

% Walk up until we find a frame that isn't in query.pl (otherwise the report just
% points back at query:search/2 internals).
query:find_external_callsite_frame(Frame0, Frame) :-
  ( var(Frame0) ; Frame0 == 0 ), !,
  Frame = Frame0.
query:find_external_callsite_frame(Frame0, Frame) :-
  query:frame_callsite(Frame0, File, _Line, PI),
  ( File == '/Users/pvdabeel/Desktop/Prolog/Source/query.pl'
    ; query:skip_callsite_pi(PI)
  ),
  !,
  ( prolog_frame_attribute(Frame0, parent, Parent) ->
      query:find_external_callsite_frame(Parent, Frame)
  ; Frame = Frame0
  ).
query:find_external_callsite_frame(Frame0, Frame0).

% =============================================================================
%  QUERY MACROS
% =============================================================================

% Query essentially queries the cache facts, which are maintained
% by the knowledge base.
%
% All access to cache should happen through this module, as queries
% are optimized for efficiency at compile time using Prolog goal
% expansion (macro's). A fallback to runtime queries is provided
% if no goal_expansion macro is available.
%
% We deal with queries from command line:
%
%    1. a list of qualified target searches (--merge, --unmerge, --info)
%       each qualified target search identifies a proposed knowledge
%       base entry that needs to be realised by the proof / build plan
%
%    2. a list of key=value search pairs, (--search)
%       where = can be any of<,>,<=,>=,!=,~,:=. The last two implement
%       fuzzy search and wildcard search respectively on the value provided.
%
% We also support other queries from ebuild, printer, grapher, builder
% through a flexible query language which includes:
%
%    - negation (filtering of results)
%    - all (collecting all results)
%    - model (backtracks over solutions for a given statement))
%
% We expect query to be called from the knowledge base, which may
% be instantiated as a local knowledge base (standalone, server mode)
% or a remote knowledge base (client or mixed mode)
%
% A word on performance:
%
% During compilation of the prolog code, we substitute calls to query predicates
% with relevant cache:ordered_entry and cache:entry_metadata predicates, which
% have been indexed by the JIT indexer and essentially provide O(1) lookup.
%
% Over 50% of proving time is spent querying, by using Macros and working with
% an indexed data structure, we keep calling overhead to a minimum.

:- multifile user:goal_expansion/2.

% -----------------------------------------------------------------------------
%  GOAL EXPANSION
% -----------------------------------------------------------------------------

% We treat both list queries and compound queries

% IMPORTANT:
% Most callers invoke this predicate module-qualified as `query:search/2`.
% Provide goal-expansion rules for that form as well, otherwise no compile-time
% optimization happens and proving becomes dramatically slower.

user:goal_expansion(query:search(Q, Repo://Id), Expanded) :-
  is_list(Q),!,
  query:compile_query_list(Q, Repo://Id, Expanded),
  message:color(normal).

user:goal_expansion(query:search(Q, Repo://Id), Expanded) :-
  compound(Q),!,
  query:compile_query_compound(Q, Repo://Id, Expanded),
  message:color(normal).

user:goal_expansion(search(Q, Repo://Id), Expanded) :-
  is_list(Q),!,
  %write('Inside list macro: '),write(Q),nl,
  compile_query_list(Q, Repo://Id, Expanded),
  %write('Turned list into: '),write(Expanded),nl,nl,
  message:color(normal).

user:goal_expansion(search(Q, Repo://Id), Expanded) :-
  compound(Q),!,
  %write('Inside compound macro: '),write(Q),nl,
  compile_query_compound(Q, Repo://Id, Expanded),
  %write('Turned compound into: '),write(Expanded),nl,nl,
  message:color(normal).


% -----------------------------------------------------------------------------
%  LIST QUERY
% -----------------------------------------------------------------------------

% We turn list queries into joined compound queries

compile_query_list([], _Repo://_Id, true).

compile_query_list([S|Ss], Repo://Id, (One, Rest)) :-
  compile_query_compound(S, Repo://Id, One),
  compile_query_list(Ss, Repo://Id, Rest).


% -----------------------------------------------------------------------------
%  COMPOUND QUERY
% -----------------------------------------------------------------------------

% We turn compound queries into cache statements


% -----------------------------------------------------------------------------
%  PDEPEND helper: tag as its own dependency phase
% -----------------------------------------------------------------------------
%
% The EAPI grammar parses PDEPEND with the same dependency-sequence grammar as
% RDEPEND, producing package_dependency(run, ...) leaves. In order to model
% Portage-like "runtime_post" semantics, we re-tag PDEPEND leaves as their own
% phase so they can be handled as cycle-breakable edges by rules/scheduler.

query:pdepend_dep_as_pdepend(package_dependency(run,Strength,C,N,O,V,S,U),
                             package_dependency(pdepend,Strength,C,N,O,V,S,U)) :-
  !.
query:pdepend_dep_as_pdepend(use_conditional_group(Pol, Use, Self, Deps0),
                             use_conditional_group(Pol, Use, Self, Deps)) :-
  !,
  maplist(query:pdepend_dep_as_pdepend, Deps0, Deps).
query:pdepend_dep_as_pdepend(any_of_group(Deps0), any_of_group(Deps)) :-
  !,
  maplist(query:pdepend_dep_as_pdepend, Deps0, Deps).
query:pdepend_dep_as_pdepend(all_of_group(Deps0), all_of_group(Deps)) :-
  !,
  maplist(query:pdepend_dep_as_pdepend, Deps0, Deps).
query:pdepend_dep_as_pdepend(exactly_one_of_group(Deps0), exactly_one_of_group(Deps)) :-
  !,
  maplist(query:pdepend_dep_as_pdepend, Deps0, Deps).
query:pdepend_dep_as_pdepend(at_most_one_of_group(Deps0), at_most_one_of_group(Deps)) :-
  !,
  maplist(query:pdepend_dep_as_pdepend, Deps0, Deps).
query:pdepend_dep_as_pdepend(T, T).


% -----------------------------------------------------------------------------
%  Helpers: thread required_use "self" through proof
% -----------------------------------------------------------------------------
%
% The REQUIRED_USE grammar contains pure boolean constraints over USE flags.
% When proving it, we need access to the current ebuild to prefer alternatives
% already satisfied by effective USE (IUSE defaults + profile/env/package.use).
%
query:with_required_use_self(Self, Goal) :-
  ( nb_current(query_required_use_self, Old) -> HadOld = true ; HadOld = false ),
  nb_setval(query_required_use_self, Self),
  setup_call_cleanup(true,
                     Goal,
                     ( HadOld == true -> nb_setval(query_required_use_self, Old)
                     ; nb_delete(query_required_use_self)
                     )).


% 1. syntactic suggar

compile_query_compound(repository(Repo), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,_)) :- !.

compile_query_compound(entry(Id), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,_)) :- !.

compile_query_compound(ebuild(Id), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,_)) :- !.

compile_query_compound(package(C,N), Repo://Id,
  ( cache:package(Repo,C,N),
    once(cache:ordered_entry(Repo,Id,C,N,_)) )) :- !.


% 2. queries on ordered_entry metadata

compile_query_compound(name(Name), Repo://Id,
  cache:ordered_entry(Repo,Id,_,Name,_)) :- !.

compile_query_compound(category(Cat), Repo://Id,
  cache:ordered_entry(Repo,Id,Cat,_,_)) :- !.

compile_query_compound(version(Ver), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,Ver)) :- !.


% 3. queries on entry_metadata

compile_query_compound(slot(Slot), Repo://Id,
  cache:entry_metadata(Repo,Id,slot,slot(Slot))) :- !.

compile_query_compound(subslot(Slot), Repo://Id,
  cache:entry_metadata(Repo,Id,slot,subslot(Slot))) :- !.

compile_query_compound(keyword(KW), Repo://Id,
  cache:entry_metadata(Repo,Id,keywords,KW)) :- !.

compile_query_compound(keywords(KW), Repo://Id,
  cache:entry_metadata(Repo,Id,keywords,KW)) :- !.

compile_query_compound(installed(Bool),	Repo://Id,
  cache:entry_metadata(Repo,Id,installed,Bool)) :- !.

% VDB metadata: USE flags enabled for the installed package.
compile_query_compound(use(Use), Repo://Id,
  cache:entry_metadata(Repo,Id,use,Use)) :- !.

% VDB preserved-libs metadata (Portage).
compile_query_compound(needed_elf2(X), Repo://Id,
  cache:entry_metadata(Repo,Id,needed_elf2,X)) :- !.

compile_query_compound(provides_elf2(X), Repo://Id,
  cache:entry_metadata(Repo,Id,provides_elf2,X)) :- !.

compile_query_compound(required_use(Use),	Repo://Id,
  cache:entry_metadata(Repo,Id,required_use,Use)) :- !.

compile_query_compound(src_uri(Uri), Repo://Id,
  cache:entry_metadata(Repo,Id,src_uri,Uri)) :- !.

compile_query_compound(download(D), Repo://Id,
  cache:entry_metadata(Repo,Id,src_uri,uri(_,_,D))) :- !.

compile_query_compound(bdepend(B), Repo://Id,
  cache:entry_metadata(Repo,Id,bdepend,B)) :- !.

compile_query_compound(cdepend(C), Repo://Id,
  cache:entry_metadata(Repo,Id,cdepend,C)) :- !.

compile_query_compound(depend(D), Repo://Id,
  cache:entry_metadata(Repo,Id,depend,D)) :- !.

compile_query_compound(idepend(I), Repo://Id,
  cache:entry_metadata(Repo,Id,idepend,I)) :- !.

compile_query_compound(pdepend(P), Repo://Id,
  cache:entry_metadata(Repo,Id,pdepend,P)) :- !.

compile_query_compound(rdepend(P), Repo://Id,
  cache:entry_metadata(Repo,Id,rdepend,P)) :- !.

compile_query_compound(defined_phases(P), Repo://Id,
  cache:entry_metadata(Repo,Id,defined_phases,P)) :- !.

compile_query_compound(description(D), Repo://Id,
  cache:entry_metadata(Repo,Id,description,D)) :- !.

compile_query_compound(eapi(E), Repo://Id,
  cache:entry_metadata(Repo,Id,eapi,E)) :- !.

compile_query_compound(homepage(H), Repo://Id,
  cache:entry_metadata(Repo,Id,homepage,H)) :- !.

compile_query_compound(license(L), Repo://Id,
  cache:entry_metadata(Repo,Id,license,L)) :- !.

compile_query_compound(eclass(E), Repo://Id,
  cache:entry_metadata(Repo,Id,eclasses,[eclass(E),_])) :- !.

compile_query_compound(eclasses(E), Repo://Id,
  cache:entry_metadata(Repo,Id,eclasses,[eclass(E),_])) :- !.

compile_query_compound(properties(P), Repo://Id,
  cache:entry_metadata(Repo,Id,properties,P)) :- !.

compile_query_compound(restrict(R), Repo://Id,
  cache:entry_metadata(Repo,Id,restrict,R)) :- !.

compile_query_compound(timestamp(T), Repo://Id,
  cache:entry_metadata(Repo,Id,timestamp,T)) :- !.

compile_query_compound(md5(M), Repo://Id,
  cache:entry_metadata(Repo,Id,md5,M)) :- !.


% 4. special case: indicator for md5_cache that was generated locally

compile_query_compound(local(L), Repo://Id,
  cache:entry_metadata(Repo,Id,local,L)) :- !.

% Extra metadata commonly used by rules/prover logic
compile_query_compound(iuse(Iuse), Repo://Id,
  cache:entry_metadata(Repo,Id,iuse,Iuse)) :- !.


% 5. special case: masked ebuilds

compile_query_compound(masked(true), Repo://Id,
  preference:masked(Repo://Id) ) :- !.

compile_query_compound(masked(false), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    \+ preference:masked(Repo://Id) )) :- !.


% 6. rule helpers: dependency query for fetchonly, install & run rules

compile_query_compound(dependency(D,run), Repo://Id,
  ( cache:entry_metadata(Repo,Id,idepend,D)
  ; cache:entry_metadata(Repo,Id,rdepend,D) )) :- !.

compile_query_compound(dependency(D,install), Repo://Id,
  ( cache:entry_metadata(Repo,Id,bdepend,D)
  ; cache:entry_metadata(Repo,Id,cdepend,D)
  ; cache:entry_metadata(Repo,Id,depend,D) )) :- !.

compile_query_compound(dependency(D,fetchonly), Repo://Id,
  ( cache:entry_metadata(Repo,Id,bdepend,D)
  ; cache:entry_metadata(Repo,Id,cdepend,D)
  ; cache:entry_metadata(Repo,Id,depend,D)
  ; cache:entry_metadata(Repo,Id,idepend,D)
  ; cache:entry_metadata(Repo,Id,rdepend,D) )) :- !.


% 7. key=value queries needed for --search

compile_query_compound(select(Key,Cmp,Value), Repo://Id,
  ( search(select(Key,Cmp,Value), Repo://Id ) ))  :-
  nonground(Cmp,_),!.   % Important: filter out runtime bound Cmp

compile_query_compound(select(repository,notequal,R), Repo://Id,
  ( cache:ordered_entry(R,Id,_,_,_),
    R \== Repo ) ) :- !.

compile_query_compound(select(repository,equal,Repo), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,_) ) :- !.

compile_query_compound(select(repository,tilde,R), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    dwim_match(R,Repo) ) ) :- !.

compile_query_compound(select(repository,wildcard,R), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    wildcard_match(R,Repo) ) ) :- !.

compile_query_compound(select(name,equal,N), Repo://Id,
  cache:ordered_entry(Repo,Id,_,N,_)) :- !.

compile_query_compound(select(name,notequal,N), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,O,_),
    N \== O ) ) :- !.

compile_query_compound(select(name,tilde,N), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,M,_),
    dwim_match(N,M) ) ) :- !.

compile_query_compound(select(name,wildcard,N), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,M,_),
    wildcard_match(N,M) ) ) :- !.

compile_query_compound(select(category,equal,C), Repo://Id,
  cache:ordered_entry(Repo,Id,C,_,_)) :- !.

compile_query_compound(select(category,notequal,C), Repo://Id,
  ( cache:ordered_entry(Repo,Id,O,_,_),
    C \== O ) ) :- !.

compile_query_compound(select(category,tilde,C), Repo://Id,
  ( cache:ordered_entry(Repo,Id,M,_,_),
    dwim_match(C,M) ) ) :- !.

compile_query_compound(select(category,wildcard,C),	Repo://Id,
  ( cache:ordered_entry(Repo,Id,M,_,_),
    wildcard_match(C,M) ) ) :- !.

compile_query_compound(select(version,none,_), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,_)) :- !.

compile_query_compound(select(version,equal,[[], '', '', '', '']), Repo://Id,
 cache:ordered_entry(Repo,Id,_,_,_)) :- !.

% Treat version 'equal' constraints containing '*' as wildcard matches.
% Example: =dev-libs/libgit2-1.9* should match 1.9.1, 1.9.2, ...
compile_query_compound(select(version,equal,[_,_,_,Pattern]), Repo://Id,
  ( cache:ordered_entry(Repo, Id, _, _, [_,_,_,ProposedVersion]),
    wildcard_match(Pattern, ProposedVersion) )) :-
  atom(Pattern),
  sub_atom(Pattern, _, 1, 0, '*'),
  !.

compile_query_compound(select(version,equal,Ver), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,Ver)) :- !.

compile_query_compound(select(version,smaller,ReqVer), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
    eapi:version_compare(<,ProposedVersion,ReqVer) )) :- !.

compile_query_compound(select(version,greater,ReqVer), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
    eapi:version_compare(>,ProposedVersion,ReqVer) )) :- !.

compile_query_compound(select(version,smallerequal,ReqVer), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
    ( eapi:version_compare(<,ProposedVersion,ReqVer);
      eapi:version_compare(=,ProposedVersion,ReqVer) ) )) :- !.

compile_query_compound(select(version,greaterequal,ReqVer), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
    ( eapi:version_compare(>,ProposedVersion,ReqVer);
      eapi:version_compare(=,ProposedVersion,ReqVer) ) )) :- !.

compile_query_compound(select(version,notequal,ReqVer), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
    ProposedVersion \== ReqVer )) :- !.

compile_query_compound(select(version,wildcard,[_,_,_,V]),Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,[_,_,_,ProposedVersion]),
    wildcard_match(V,ProposedVersion) )) :- !.

compile_query_compound(select(version,tilde,[V,L,S,_]), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,[V,L,CandS,_]),
    query:tilde_suffix_match(S, CandS) )) :- !.

compile_query_compound(select(eapi,notequal,[_,_,_,V]), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,[_,_,_,O]),
    O \== V ) ) :- !.

compile_query_compound(select(eapi,equal,[_,_,_,V]), Repo://Id,
  cache:entry_metadata(Repo,Id,eapi,[_,_,_,V]) ) :- !.

compile_query_compound(select(eapi,wildcard,[_,_,_,V]), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,[_,_,_,ProposedVersion]),
    wildcard_match(V,ProposedVersion) ) ) :- !.

compile_query_compound(select(eapi,smaller,ReqVer), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,ProposedVersion),
    system:compare(<,ProposedVersion,ReqVer) ) ) :- !.

compile_query_compound(select(eapi,greater,ReqVer), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,ProposedVersion),
    system:compare(>,ProposedVersion,ReqVer) ) ) :- !.

compile_query_compound(select(eapi,smallerequal,ReqVer), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,ProposedVersion),
    ( system:compare(<,ProposedVersion,ReqVer);
      system:compare(=,ProposedVersion,ReqVer) ) )) :- !.

compile_query_compound(select(eapi,greaterequal,ReqVer), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,ProposedVersion),
    ( system:compare(>,ProposedVersion,ReqVer);
      system:compare(=,ProposedVersion,ReqVer) ) )) :- !.

compile_query_compound(select(eclass,notequal,E),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(O),_]),
    O \== E )) :- !.

compile_query_compound(select(eclass,equal,E), Repo://Id,
  cache:entry_metadata(Repo,Id,eclasses,[eclass(E),_])) :- !.

compile_query_compound(select(eclass,tilde,E), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(M),_]),
    dwim_match(E,M) ) ) :- !.

compile_query_compound(select(eclass,wildcard,E),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(M),_]),
    wildcard_match(E,M) ) ) :- !.

compile_query_compound(select(eclasses,notequal,E),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(O),_]),
    O \== E )) :- !.

compile_query_compound(select(eclasses,equal,E), Repo://Id,
  cache:entry_metadata(Repo,Id,eclasses,[eclass(E),_])) :- !.

compile_query_compound(select(eclasses,tilde,E), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(M),_]),
    dwim_match(E,M) ) ) :- !.

compile_query_compound(select(eclasses,wildcard,E),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,eclasses,[eclass(M),_]),
    wildcard_match(E,M) ) ) :- !.

compile_query_compound(select(download,notequal,F),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,src_uri,uri(_,_,O)),
    O \== F ) ) :- !.

compile_query_compound(select(download,equal,F), Repo://Id,
  cache:entry_metadata(Repo,Id,src_uri,uri(_,_,F))) :- !.

compile_query_compound(select(download,tilde,F), Repo://Id,
  ( cache:entry_metadata(Repo,Id,src_uri,uri(_,_,M)),
    dwim_match(F,M) ) ) :- !.

compile_query_compound(select(download,wildcard,F), Repo://Id,
  ( cache:entry_metadata(Repo,Id,src_uri,uri(_,_,M)),
    wildcard_match(F,M) ) ) :- !.

compile_query_compound(select(slot,notequal,S),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(O)),
    O \== S ) ) :- !.

compile_query_compound(select(slot,equal,S), Repo://Id,
  cache:entry_metadata(Repo,Id,slot,slot(S))) :- !.

compile_query_compound(select(slot,tilde,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(M)),
    dwim_match(S,M) ) ) :- !.

compile_query_compound(select(slot,wildcard,S),	Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(M)),
    wildcard_match(S,M) ) ) :- !.

compile_query_compound(select(subslot,notequal,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,subslot(O)),
    O \== S ) ) :- !.

compile_query_compound(select(subslot,equal,S), Repo://Id,
  cache:entry_metadata(Repo,Id,slot,subslot(S))) :- !.

compile_query_compound(select(slot,tilde,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,subslot(M)),
    dwim_match(S,M) ) ) :- !.

compile_query_compound(select(subslot,wildcard,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,subslot(M)),
    wildcard_match(S,M) ) ) :- !.

compile_query_compound(select(slot,constraint([]),Sn), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)) ) :- !. 				% will work: test40

compile_query_compound(select(slot,constraint([slot(S)]),Sn), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)) ) :- !. 				% will work: test41

compile_query_compound(select(slot,constraint([slot(S),subslot(Ss)]),Sn), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)) ) :- !. 				% will work: test44

compile_query_compound(select(slot,constraint([slot(S),equal]),Sn), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)) ) :- !.					% adds chosen slot as a requirement to context - no test yet

compile_query_compound(select(slot,constraint([slot(S),subslot(Ss),equal]),Sn), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)) ) :- !.					% adds chosen slot and subslot as a requirement to context - no test yet

compile_query_compound(select(slot,constraint([any_same_slot]),Sn), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    % For := (any_same_slot) we only want to lock the SLOT, not the SUBSLOT.
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn)) ) :- !.					% adds chosen slot as a requirement to context - test43

compile_query_compound(select(slot,constraint([any_different_slot]),Sn), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn)) ) :- !.					% adds chosen slot as a requirement to context - test 42



compile_query_compound(select(keyword,equal,K),	Repo://Id,
  cache:entry_metadata(Repo,Id,keyword,K)) :- !.

compile_query_compound(select(keywords,equal,K), Repo://Id,
  cache:entry_metadata(Repo,Id,keyword,K)) :- !.

compile_query_compound(select(masked,equal,true), Repo://Id,
  preference:masked(Repo://Id) ) :- !.

compile_query_compound(select(masked,equal,false), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    \+ preference:masked(Repo://Id) )) :- !.

compile_query_compound(select(masked,notequal,false), Repo://Id,
  preference:masked(Repo://Id) ) :- !.

compile_query_compound(select(masked,notequal,true), Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    \+ preference:masked(Repo://Id) )) :- !.


% 8. all query is treated at runtime, except for a few exceptions

compile_query_compound(all(S), Repo://Id,
  query:search(all(S),Repo://Id))	:-
  var(S),!.

compile_query_compound(all(S):A?{C}, Repo://Id,
  query:search(all(S):A?{C},Repo://Id)) :-
  var(S),!.


% 9. the exceptions for all

compile_query_compound(all(src_uri(U)), Repo://Id,
  findall(Uri,
          cache:entry_metadata(Repo,Id,src_uri,Uri),
          U)) :- !.

compile_query_compound(all(required_use(U)), Repo://Id,
  findall(Use,
          cache:entry_metadata(Repo,Id,required_use,Use),
          U)) :- !.

compile_query_compound(all(bdepend(B)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,bdepend,Dep),
          B)) :- !.

compile_query_compound(all(depend(D)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,depend,Dep),
          D)) :- !.

compile_query_compound(all(cdepend(C)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,cdepend,Dep),
          C)) :- !.

compile_query_compound(all(idepend(I)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,idepend,Dep),
          I)) :- !.

compile_query_compound(all(rdepend(R)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,rdepend,Dep),
          R)) :- !.

compile_query_compound(all(pdepend(P)), Repo://Id,
  findall(Dep,
          cache:entry_metadata(Repo,Id,pdepend,Dep),
          P)) :- !.

compile_query_compound(all(dependency(D,run)), Repo://Id,
  findall(Dep,
          ( cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          D)) :- !.

compile_query_compound(all(dependency(D,install)), Repo://Id,
  findall(Dep,
          ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          ),
          D)) :- !.

compile_query_compound(all(dependency(D,fetchonly)), Repo://Id,
  findall(Dep,
          ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          ; cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          D)) :- !.

compile_query_compound(all(dependency(D,run)):A?{C}, Repo://Id,
  findall(Dep:A?{C},
          ( cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          D)) :- !.

compile_query_compound(all(dependency(D,install)):A?{C}, Repo://Id,
  findall(Dep:A?{C},
          ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          ),
          D)) :- !.

compile_query_compound(all(dependency(D,fetchonly)):A?{C}, Repo://Id,
  findall(Dep:A?{C},
          ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          ; cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          D)) :- !.


% 10. some model queries are rewritten

compile_query_compound(model(FullModel,required_use(Model),build_with_use(Input)), Repo://Id,
  ( findall(ReqUse,
            cache:entry_metadata(Repo,Id,required_use,ReqUse),
            AllReqUse),
    sort(AllReqUse, AllReqUseU),
    prover:with_delay_triggers(
      ( % NOTE (performance): do NOT prove build_with_use/1 items as literals here.
        % They are meant to be threaded as a feature term in action contexts.
        % Proving them into the model creates large, highly-variable model-key lists
        % and defeats memoization on big stacks (OCaml/Qt/KDE).
        %
        % We only compute the REQUIRED_USE model here; build_with_use is returned
        % as a feature-value pair in FullModel.
        query:with_required_use_self(Repo://Id,
          prover:prove_model(AllReqUseU, t, AvlModel, t, _ConsOut, t))
      ) ),
    findall(Key,
            (gen_assoc(Key,AvlModel,_),
   	     \+eapi:abstract_syntax_construct(Key)),
            Model),
    % FullModel is a compact context passed into dependency-model construction.
    % Keep it small + stable to maximize memoization hits.
    %
    % IMPORTANT:
    % `Input` must NOT be left as a free variable. During dependency-model
    % construction we thread `build_with_use` through contexts; if this starts as
    % an unbound variable, constraints can accidentally leak across unrelated
    % branches within the same model proof (e.g. PYTHON_TARGETS contaminating
    % bracketed USE requirements), causing spurious rebuilds like:
    %   clustershell -> python (rebuild_reason(build_with_use))
    %
    % Start from an explicit empty monotone USE state *only if not provided*.
    % Callers may thread a non-empty build_with_use state through action contexts
    % (e.g. deps like dev-lang/ocaml:=[ocamlopt?]). In that case, preserve it.
    ( var(Input) -> Input = use_state([], []) ; true ),
    % IMPORTANT:
    % `required_use/1` is a property of the *current* ebuild and must NOT be
    % threaded into dependency contexts (otherwise it can be misinterpreted as
    % the child's REQUIRED_USE model, leading to spurious failures when proving
    % child :install/:run actions).
    %
    % Only thread `build_with_use/1` to support bracketed USE deps.
    FullModel = [build_with_use:Input]
  ) ) :- !.

compile_query_compound(model(required_use(Model)), Repo://Id,
  ( findall(ReqUse,
            cache:entry_metadata(Repo,Id,required_use,ReqUse),
            AllReqUse),
    sort(AllReqUse, AllReqUseU),
    prover:with_delay_triggers(
      query:with_required_use_self(Repo://Id,
        prover:prove_model(AllReqUseU, t, AvlModel, t, _ConsOut, t))),
    findall(Key,
            (gen_assoc(Key,AvlModel,_Value),
   	     \+eapi:abstract_syntax_construct(Key)),
            Model) ) ) :- !.

compile_query_compound(model(dependency(Model,run)):config?{Context}, Repo://Id,
  ( findall(Dep:config?{Context},
          ( cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          Deps),
  sort(Deps, DepsU),
  prover:with_delay_triggers(
    prover:prove_model(DepsU, t, AvlModel, t, _ConsOut, t)),
  % IMPORTANT: keep dependency "phase" (install/run) distinct from the literal's
  % action tag. We tag each dependency literal by its Phase, so grouped deps never
  % mix install+run package_dependency terms in one group.
  findall(Fact:Phase?{CtxOut},
          ( gen_assoc(Fact:_,AvlModel,CtxIn),
            Fact =.. [package_dependency|_],
            Fact =.. [package_dependency,Phase|_],
            ( CtxIn == {} -> CtxOut = [] ; CtxOut = CtxIn )
          ),
          Model) ) ) :- !.

compile_query_compound(model(dependency(Model,pdepend)):config?{Context}, Repo://Id,
  ( findall(Dep:config?{Context},
          ( cache:entry_metadata(Repo,Id,pdepend,Dep0),
            query:pdepend_dep_as_pdepend(Dep0, Dep)
          ),
          Deps),
  sort(Deps, DepsU),
  prover:with_delay_triggers(
    prover:prove_model(DepsU, t, AvlModel, t, _ConsOut, t)),
  % Tag PDEPEND dependencies as :run actions, so the grouped dependency resolver
  % (`grouped_package_dependency/4`) can resolve them. The *dependency phase* is
  % carried by the package_dependency(pdepend, ...) term and will be preserved
  % by grouping, so pdepend edges remain distinguishable from regular runtime deps.
  findall(Fact:run?{CtxOut},
          ( gen_assoc(Fact:_,AvlModel,CtxIn),
            Fact =.. [package_dependency|_],
            ( CtxIn == {} -> CtxOut = [] ; CtxOut = CtxIn )
          ),
          Model) ) ) :- !.

compile_query_compound(model(dependency(Model,install)):config?{Context}, Repo://Id,
  ( findall(Dep:config?{Context},
          ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          % Portage merges build-time dependencies as full packages, so their
          % runtime deps must be present too. Including IDEPEND/RDEPEND here
          % fixes missing transitive deps (e.g. python libs pulled via BDEPEND).
          % These will be tagged as :run dependencies (not :install), preserving
          % the historical separation between install and run obligations.
          ; cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          Deps),
  sort(Deps, DepsU),
  prover:with_delay_triggers(
    prover:prove_model(DepsU, t, AvlModel, t, _ConsOut, t)),
  findall(Fact:Phase?{CtxOut},
           ( gen_assoc(Fact:_,AvlModel,CtxIn),
             Fact =.. [package_dependency|_],
             Fact =.. [package_dependency,Phase|_],
             ( CtxIn == {} -> CtxOut = [] ; CtxOut = CtxIn )
           ),
          Model) ) ) :- !.

compile_query_compound(model(dependency(Model,fetchonly)):config?{Context}, Repo://Id,
  ( findall(Dep:config?{Context},
    	  ( cache:entry_metadata(Repo,Id,bdepend,Dep)
          ; cache:entry_metadata(Repo,Id,cdepend,Dep)
          ; cache:entry_metadata(Repo,Id,depend,Dep)
          ; cache:entry_metadata(Repo,Id,idepend,Dep)
          ; cache:entry_metadata(Repo,Id,rdepend,Dep)
          ),
          Deps),
  sort(Deps, DepsU),
  prover:with_delay_triggers(
    prover:prove_model(DepsU, t, AvlModel, t, _ConsOut, t)),
  findall(Fact:fetchonly?{CtxOut},
          ( gen_assoc(Fact:_,AvlModel,CtxIn),
            Fact =.. [package_dependency|_],
            ( CtxIn == {} -> CtxOut = [] ; CtxOut = CtxIn )
          ),
          Model) ) ) :- !.


% 11. qualified_target queries, generated by --merge, --unmerge and --info

compile_query_compound(qualified_target(none,Repo,C,P,[[],'','','',''],_F), Repo://Id,
  cache:ordered_entry(Repo,Id,C,P,_)) :- !.

compile_query_compound(qualified_target(none,Repo,C,P,V,_F), Repo://Id,
  cache:ordered_entry(Repo,Id,C,P,V)) :- !.

compile_query_compound(qualified_target(greater,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,PV),
    system:compare(>,PV,V),
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(greaterequal,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,PV),
    (system:compare(>,PV,V);
     system:compare(=,PV,V)),
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(smaller,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,PV),
    system:compare(<,PV,V),
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(smallerequal,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,PV),
    (system:compare(<,PV,V);
     system:compare(=,PV,V)),
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(equal,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,V),
    query:apply_filters(Repo://Id,F) ) ) :- !.

compile_query_compound(qualified_target(notequal,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,PV),
    PV \== V,
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(tilde,Repo,C,P,[V,_,_,_,_],F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,[V,_,_,_,_]),
    query:apply_filters(Repo://Id,F) )) :- !.



% 12. Fallback – Stuff for which a macro doesn't exist, we fall back to regular predicates

compile_query_compound(Stmt, Entry,
  search(Stmt,Entry)).



% =============================================================================
%  QUERY PREDICATES
% =============================================================================

% These are evaluated at runtime.

% -----------------------------------------------------------------------------
%  Query: Search
% -----------------------------------------------------------------------------

%! query:search(Query)
%
% Search - iterate over list
% Traverse a list of statements that narrow down the search results.

% Runtime optimization:
% Even if goal-expansion did not run for a given caller (e.g. due to load order),
% we can still compile common query forms into cache-level goals and execute them.
% If there is no compilation rule, `compile_query_compound/3` falls back to
% `search(Stmt,Entry)`; detect that and let the normal runtime clauses handle it.
search(Q, Repository://Entry) :-
  query:maybe_record_search_callsite(Q, Repository://Entry),
  ( is_list(Q)
    -> compile_query_list(Q, Repository://Entry, Goal)
    ; compound(Q)
    -> compile_query_compound(Q, Repository://Entry, Goal)
  ),
  Goal \== search(Q, Repository://Entry),
  !,
  call(Goal).

search([],_Repository://_Entry) :- !.

search([Statement|Rest],Repository://Entry) :-
  !,
  search(Statement,Repository://Entry),
  search(Rest,Repository://Entry).



% -----------------------------------------------------------------------------
%  Query  meta predicates
% -----------------------------------------------------------------------------

% Case : a not statement

%search(not(Statement),Repository://Entry) :-
%  !,
%  cache:ordered_entry(Repository,Entry,_,_,_),
%  \+(search(Statement,Repository://Entry)).


% Case : an all statement (single argument, contextualized)

search(all(Statement):Context,Repository://Entry) :-
  Statement =.. [Key,Values],
  !,
  findall(InnerValueA:Context,
          (InnerStatement =.. [Key,InnerValueA],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (single argument, no context)

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values],
  !,
  findall(InnerValue,
          (InnerStatement =.. [Key,InnerValue],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (dual argument, contextualized)

search(all(Statement):Context,Repository://Entry) :-
  Statement =.. [Key,Values,Filter],
  !,
  findall(InnerValueA:Context,
          (InnerStatement =.. [Key,InnerValueA,Filter],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (dual argument, no context)

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values,Filter],
  !,
  findall(InnerValueA,
          (InnerStatement =.. [Key,InnerValueA,Filter],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : a model statement (dual argument, contextualized),Add commentMore actions

search(model(Statement):Action?{Context},Repository://Id) :-
  Statement =.. [Key,Model,Arg],
  !,
  StatementA =.. [Key,AllValues,Arg],
  search(all(StatementA):Action?{Context},Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (dual argument, no context),

search(model(Statement),Repository://Id) :-
  Statement =.. [Key,Model,Arg],
  !,
  StatementA =.. [Key,AllValues,Arg],
  search(all(StatementA),Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (single argument, contextualized)

search(model(Statement):Action?{Context},Repository://Id) :-
  Statement =.. [Key,Model],
  !,
  StatementA =.. [Key,AllValues],
  search(all(StatementA):Action?{Context},Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (single argument, no context)

search(model(Statement),Repository://Id) :-
  Statement =.. [Key,Model],
  !,
  StatementA =.. [Key,AllValues],
  search(all(StatementA),Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a latest statement, returs only latest version

search(latest(Statement),R://I) :-
  search(Statement,R://I),!. % deliberate choicepoint cut (once)


% -----------------------------------------------------------------------------
%  Search: command line key=value pairs
% -----------------------------------------------------------------------------

search(select(Key,Comparator,Value),R://I) :-
  select(Key,Comparator,Value,R://I).


% -----------------------------------------------------------------------------
%  Search: Qualified target
% -----------------------------------------------------------------------------

% A Qualified target is defined in the EAPI spec as:
%
%  <operator><repository>://<category/<package>-<version>:<slot>[<usedeps>]
%
% or
%
%  <operator><category><package>-<version>:<slot>[<usedeps>]
%
% or
%
%  <operator><package>-<version>:<slot>[<usedeps>]
%
% where <operator>, <version>, <slot> and <usedeps are optional.
%
% The provided EAPI parser converts this to a
%
%  qualified_target(operator,repository,category,package,version,filters)
%
% where filters is a list of slot and usedep constraints.
% where operator is one of:
%
%    - greaterequal
%    - greater
%    - smallerequal
%    - smaller
%    - tilde
%    - equal
%    - notequal
%    - none
%
% In case repository is not provided, it is supplied as an unbound variable
% In case category is not provided, it is supplied as an unbound variable
%
% Version is defined in EAPI spec and is essentially a list of:
%
%    - Numberpart, (an atom. e.g. 6.5.4)
%    - Alphapart, (an atom e.g. dev)
%    - Suffixpart, (an atom. e.g. _alpha, _beta, _pre, _rc, -r)
%    - Fullversion, (an atom combining number, alpha and suffix. E.g. 6.5.4dev-r1
%
% In case version is not provided, it is supplied as a list of empty atoms i.e. ['','','','']
%
% Filter is a list that can be empty. It contains lists as elements, each with filters.
% e.g. [[slot(4)],[usedep([positive(useflag),negative(otheruseflag)])]]


% Instead of using a generator, generating a lot of backtrack points, and filtering
% out options, we try to maximize usage of the JIT indexing of prolog.
%
% Essentially, repository, category, package name and even version can be hashed,
% permitting hash indexed-lookup or cache predicates, limiting the choicepoints.
%
% This search based on qualified_target makes lookup initial lookup very fast. We
% apply filtering on the remaining choicepoints.

% -----------------------------------------------------------------------------
%  Search: Version
% -----------------------------------------------------------------------------

search(select(version,none,_),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,_).

search(select(version,equal,[[], '', '', '', '']),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,_).

% Treat version 'equal' constraints containing '*' as wildcard matches.
% Example: =dev-libs/libgit2-1.9* should match 1.9.1, 1.9.2, ...
search(select(version,equal,[_,_,_,Pattern]), Repo://Id) :-
  atom(Pattern),
  sub_atom(Pattern, _, 1, 0, '*'),
  !,
  cache:ordered_entry(Repo, Id, _, _, [_,_,_,ProposedVersion]),
  wildcard_match(Pattern, ProposedVersion).

search(select(version,equal,Ver),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,Ver).

search(select(version,smaller,ReqVer),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
  eapi:version_compare(<,ProposedVersion,ReqVer).

search(select(version,greater,ReqVer),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
  eapi:version_compare(>,ProposedVersion,ReqVer).

search(select(version,smallerequal,ReqVer),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
  ( eapi:version_compare(<,ProposedVersion,ReqVer);
    eapi:version_compare(=,ProposedVersion,ReqVer) ).

search(select(version,greaterequal,ReqVer),Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
  ( eapi:version_compare(>,ProposedVersion,ReqVer);
    eapi:version_compare(=,ProposedVersion,ReqVer) ).

search(select(version,notequal,ReqVer), Repo://Id) :-
  !,
  cache:ordered_entry(Repo,Id,_,_,ProposedVersion),
  ProposedVersion \== ReqVer.

search(select(version,wildcard,[_,_,_,V]),Repo://Id) :-
  cache:ordered_entry(Repo,Id,_,_,[_,_,_,ProposedVersion]),
  wildcard_match(V,ProposedVersion).

search(select(version,tilde,[V,L,S,_]),Repo://Id) :-
  cache:ordered_entry(Repo,Id,_,_,[V,L,CandS,_]),
  query:tilde_suffix_match(S, CandS).


search(select(slot,constraint([]),Sn), Repo://Id) :-
  !,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)). 					% will work: test40

search(select(slot,constraint([slot(S)]),Sn), Repo://Id) :-
  !,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)). 					% will work: test41

search(select(slot,constraint([slot(S),subslot(Ss)]),Sn), Repo://Id) :-
  !,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)). 					% will work: test44

search(select(slot,constraint([slot(S),equal]),Sn), Repo://Id) :-
  !,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)).					% adds chosen slot as a requirement to context - no test yet

search(select(slot,constraint([slot(S),subslot(Ss),equal]),Sn), Repo://Id) :-
  !,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn)).					% adds chosen slot and subslot as a requirement to context - no test yet

search(select(slot,constraint([any_same_slot]),Sn), Repo://Id) :-
  !,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    % For := (any_same_slot) we only want to lock the SLOT, not the SUBSLOT.
    % SUBSLOT is a rebuild trigger, not a satisfiability constraint.
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn)).					% adds chosen slot as a requirement to context - test43

search(select(slot,constraint([any_different_slot]),Sn), Repo://Id) :-
  !,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    % Like any_same_slot, we only propagate the SLOT component.
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn)).					% adds chosen slot as a requirement to context - test 42


% -----------------------------------------------------------------------------
%  Search: Manifest
% -----------------------------------------------------------------------------

search(manifest(Scope,Type,Binary,Size),R://I) :-
   !,
   cache:ordered_entry(R,I,Category,Name,_),
   search(all(src_uri(Model)),R://I),
   deep_member(Scope,uri(_,_,Binary),Model),
   cache:manifest(R,P,_,Category,Name),
   cache:manifest_metadata(R,P,Type,Binary,Size,_Checksums).


% -----------------------------------------------------------------------------
%  Search: iuse
% -----------------------------------------------------------------------------

search(iuse(Iuse),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Value),
  eapi:strip_use_default(Value,Iuse).

% -----------------------------------------------------------------------------
%  Search: select(iuse, ...)
% -----------------------------------------------------------------------------
%
% Support CLI queries like:
%   -s iuse=minimal
%   -s iuse:=mini*
%
% Note: IUSE entries may be prefixed with +/- defaults. We strip those before
% matching, so users can search by the "clean" flag name.

search(select(iuse,equal,Flag), R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Raw),
  query:iuse_flag_atom(Raw, Flag),
  atom(Flag).

search(select(iuse,wildcard,Pattern), R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Raw),
  query:iuse_flag_atom(Raw, Flag),
  atom(Flag),
  wildcard_match(Pattern, Flag).


% -----------------------------------------------------------------------------
%  Search: iuse with use flag state
% -----------------------------------------------------------------------------

search(iuse(Iuse,State:Reason),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Value),
  eapi:categorize_use_for_entry(Value,R://I,State,Reason),
  eapi:strip_use_default(Value,Iuse).


% -----------------------------------------------------------------------------
%  Search: iuse without use_expand
% -----------------------------------------------------------------------------

search(iuse_filtered(Iuse),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:strip_use_default(Arg,Iuse),
  \+(eapi:check_use_expand_atom(Iuse)).


% -----------------------------------------------------------------------------
%  Search: iuse without use_expand, with use flag state
% -----------------------------------------------------------------------------

search(iuse_filtered(Iuse,State:Reason),R://I) :-
  !,
  setof(Iuse0,
        Arg0^(cache:entry_metadata(R,I,iuse,Arg0),
              eapi:strip_use_default(Arg0,Iuse0),
              \+ eapi:check_use_expand_atom(Iuse0)),
        IuseFlags),
  member(Iuse, IuseFlags),
  findall(State0:Reason0,
          ( cache:entry_metadata(R,I,iuse,Arg),
            eapi:strip_use_default(Arg,Iuse),
            eapi:categorize_use_for_entry(Arg,R://I,State0,Reason0)
          ),
          States0),
  query:iuse_effective_state_(States0, State, Reason).


% -----------------------------------------------------------------------------
%  Search: use expand
% -----------------------------------------------------------------------------

search(Statement,R://I) :-
  Statement =.. [Key,Value],
  eapi:use_expand(Key),!,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:strip_use_default(Arg,ArgB),
  eapi:check_prefix_atom(Key,ArgB),
  eapi:strip_prefix_atom(Key,ArgB,Value).


% -----------------------------------------------------------------------------
%  Search: use expand with use flag state
% -----------------------------------------------------------------------------

search(Statement,R://I) :-
  Statement =.. [Key,Value,State:Reason],
  eapi:use_expand(Key),!,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:categorize_use_for_entry(Arg,R://I,State,Reason),
  eapi:strip_use_default(Arg,ArgB),
  eapi:check_prefix_atom(Key,ArgB),
  eapi:strip_prefix_atom(Key,ArgB,Value).


% -----------------------------------------------------------------------------
%  Search: Metadata
% -----------------------------------------------------------------------------

% metadata can be anything, so this needs to be at the bottom

search(Q,R://I) :-
  !,
  Q =.. [Key,Value],
  select(Key,equal,Value,R://I).
  %cache:entry_metadata(R,I,Key,Value).

query:iuse_effective_state_(States, State, Reason) :-
  findall(P-State0-Reason0,
          ( member(State0:Reason0, States),
            query:iuse_state_priority_(State0, Reason0, P)
          ),
          Ranked0),
  keysort(Ranked0, RankedAsc),
  reverse(RankedAsc, [_BestP-State-Reason|_]),
  !.

query:iuse_state_priority_(positive, profile_package_use_force, 1000) :- !.
query:iuse_state_priority_(negative, profile_package_use_mask, 1000) :- !.
query:iuse_state_priority_(_, package_use, 900) :- !.
query:iuse_state_priority_(_, preference, 800) :- !.
query:iuse_state_priority_(positive, ebuild, 700) :- !.
query:iuse_state_priority_(negative, ebuild, 650) :- !.
query:iuse_state_priority_(_, default, 600) :- !.
query:iuse_state_priority_(positive, _, 500) :- !.
query:iuse_state_priority_(negative, _, 400) :- !.


% -----------------------------------------------------------------------------
%  Special case - set membership
% -----------------------------------------------------------------------------

select(set,notequal,S,R://I) :-
  !,
  preference:set(S,Set),
  findall(Rc://Ic,(member(Ta,Set),
                   atom_codes(Ta,Tc),
                   phrase(eapi:qualified_target(Q),Tc),
                   search(Q,Rc://Ic)),
          Candidates),
  cache:ordered_entry(R,I,_,_,_),
  \+(memberchk(R://I,Candidates)).

select(set,equal,S,R://I) :-
  !,
  preference:set(S,Set),
  member(Ta,Set),
  atom_codes(Ta,Tc),
  phrase(eapi:qualified_target(Q),Tc),
  search(Q,R://I).

select(set,tilde,N,R://I) :-
  !,
  preference:set(S,Set),
  dwim_match(N,S),
  member(Ta,Set),
  atom_codes(Ta,Tc),
  phrase(eapi:qualified_target(Q),Tc),
  search(Q,R://I).

select(set,wildcard,N,R://I) :-
  !,
  preference:set(S,Set),
  wildcard_match(N,S),
  member(Ta,Set),
  atom_codes(Ta,Tc),
  phrase(eapi:qualified_target(Q),Tc),
  search(Q,R://I).


% -----------------------------------------------------------------------------
%  Default - Entry Metadata
% -----------------------------------------------------------------------------

select(Key,notequal,Value,R://I) :-
  !,
  \+cache:entry_metadata(R,I,Key,Value).

% Special-case IUSE because metadata values may be wrapped in plus/1 or minus/1,
% and users typically want to search by the bare flag name.

select(iuse,equal,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Raw),
  eapi:parse_iuse_search_value(Value, RequiredSign, Pattern),
  query:iuse_sign_matches(Raw, RequiredSign),
  query:iuse_flag_atom(Raw, Flag),
  Flag == Pattern.

% Fuzzy search (~) for IUSE, with optional leading + / - in the pattern.
% Examples:
%   -s iuse~mini
%   -s iuse~+mini
%   -s iuse~-mini

select(iuse,tilde,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Raw),
  eapi:parse_iuse_search_value(Value, RequiredSign, Pattern),
  query:iuse_sign_matches(Raw, RequiredSign),
  query:iuse_flag_atom(Raw, Flag),
  dwim_match(Pattern, Flag).

select(Key,equal,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,Key,Value).

select(Key,tilde,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,Key,Match),
  dwim_match(Value,Match).

select(iuse,wildcard,Pattern,R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Raw),
  eapi:parse_iuse_search_value(Pattern, RequiredSign, Pattern1),
  query:iuse_sign_matches(Raw, RequiredSign),
  query:iuse_flag_atom(Raw, Flag),
  wildcard_match(Pattern1, Flag).



select(Key,wildcard,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,Key,Match),
  wildcard_match(Value,Match).


% -----------------------------------------------------------------------------
%  Query: Memoized Search - only dependency models for now
% -----------------------------------------------------------------------------

%! query:memoized_search(+Query, +Target)
%
%  A wrapper for query:search that provides memoization for expensive
%  model computations.

% Note: We cache *grouped* dependencies (via group_dependencies/2) because
% grouping dominates runtime and the dependency model is already memoized.
% We use distinct keys (install_grouped/run_grouped/fetchonly_grouped) to avoid
% mixing old cached values with the new representation in long-running sessions.

memoized_search(model(dependency(Merged,install)):config?{R}, Repository://Ebuild) :-
  !,
  ( memberchk(self(Repository://Ebuild), R)
    -> RSearch = R
    ;  RSearch = [self(Repository://Ebuild)|R]
  ),
  query:search(model(dependency(D0,install)):config?{RSearch},Repository://Ebuild),
  group_dependencies(D0, Merged).

memoized_search(model(dependency(Merged,run)):config?{R}, Repository://Ebuild) :-
  !,
  ( memberchk(self(Repository://Ebuild), R)
    -> RSearch = R
    ;  RSearch = [self(Repository://Ebuild)|R]
  ),
  query:search(model(dependency(D0,run)):config?{RSearch},Repository://Ebuild),
  group_dependencies(D0, Merged).

memoized_search(model(dependency(Merged,pdepend)):config?{R}, Repository://Ebuild) :-
  !,
  ( memberchk(self(Repository://Ebuild), R)
    -> RSearch = R
    ;  RSearch = [self(Repository://Ebuild)|R]
  ),
  query:search(model(dependency(D0,pdepend)):config?{RSearch},Repository://Ebuild),
  group_dependencies(D0, Merged).

memoized_search(model(dependency(Merged,fetchonly)):config?{R}, Repository://Ebuild) :-
  !,
  ( memberchk(self(Repository://Ebuild), R)
    -> RSearch = R
    ;  RSearch = [self(Repository://Ebuild)|R]
  ),
  query:search(model(dependency(D0,fetchonly)):config?{RSearch},Repository://Ebuild),
  group_dependencies(D0, Merged).


% -----------------------------------------------------------------------------
%  Grouping dependencies
% -----------------------------------------------------------------------------

%! dependency_key(+Dependency, -Key)
%
% Sets the grouping key for dependencies.

% Grouping key for dependencies:
% - group by block strength + category/name
% - and by dependency phase (install vs run), so grouped dependencies remain phase-homogeneous
%   (avoids confusing groups like grouped_package_dependency(...):install containing :run deps)
% - and by slot restriction, because different explicit slots (e.g. ruby:3.2 vs ruby:3.3)
%   must NOT be merged into a single grouped dependency (they are satisfiable as
%   separate slotted installs).
%
dependency_key((package_dependency(Phase,T,C,N,_,_,S,_):_?{_}), Phase-T-C-N-S).

%! group_dependencies(+List, -Groups)
%
% Groups dependencies by their key. (Category & Name) This is used to merge
% dependencies with the same key.

group_dependencies(L, Groups) :-
    findall(grouped_package_dependency(T,C,N,Group):Action?{Context},
		    group_by(Phase-T-C-N-S:Action?{Context}, E, (member(E:Action?{Context}, L), dependency_key(E:Action?{Context}, Phase-T-C-N-S)), Group),
            Groups).



% -----------------------------------------------------------------------------
%  Helper: Filter predicates
% -----------------------------------------------------------------------------

% Filter out versions based on comparison


% Filtering of slot & usedep for qualified_target

apply_filters(_R://_I,[]) :- !.

apply_filters(R://I,[H|T]) :-
  !,
  apply_filter(R://I,H),
  apply_filters(R://I,T).

apply_filter(_R://_I,[]) :- !.


% -----------------------------------------------------------------------------
%  Helper: iuse_flag_atom
% -----------------------------------------------------------------------------

% Robust extraction of the "bare" USE flag atom from IUSE metadata values.
% Examples:
%   plus(foo)     -> foo
%   minus(foo)    -> foo
%   foo           -> foo

iuse_flag_atom(plus(X), Atom)  :- !, iuse_flag_atom(X, Atom).
iuse_flag_atom(minus(X), Atom) :- !, iuse_flag_atom(X, Atom).
iuse_flag_atom(X, Atom) :-
  atom(X),
  !,
  Atom = X.
query:iuse_flag_atom(X, Atom) :-
  compound(X),
  X =.. [_F, Inner],
  !,
  iuse_flag_atom(Inner, Atom).


% -----------------------------------------------------------------------------
%  Helper: iuse_sign_matches
% -----------------------------------------------------------------------------

query:iuse_sign_matches(_Raw, any) :- !.
query:iuse_sign_matches(plus(_), plus) :- !.
query:iuse_sign_matches(minus(_), minus) :- !.


% -----------------------------------------------------------------------------
%  Helper predicates
% -----------------------------------------------------------------------------

%! deep_member(Type,Predicate,Model)
%
% Recursively searches model for a predicate, taking into account
% use_conditional_group

deep_member(all,Predicate,Model) :-
  member(Predicate,Model);
  (member(use_conditional_group(_,_,_,Conditional),Model),
   deep_member(all,Predicate,Conditional)).

deep_member(preference,Predicate,Model) :-
  member(Predicate,Model);
  (member(use_conditional_group(Sign,Use,_,Conditional),Model),
   (Sign == positive -> preference:use(Use) ; preference:use(minus(Use))),
     deep_member(preference,Predicate,Conditional)).
