/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> QUERY
Compile-time query language that makes common cache lookups as fast as
possible.
*/

:- module(query,[]).

% =============================================================================
%  QUERY MACROS
% =============================================================================

% The goal of this module is to make the common knowledge-base cache
% queries as performant as possible. The knowledge base owns the cache
% facts; every lookup should go through query so those calls can be
% compiled down to indexed cache:ordered_entry / cache:entry_metadata
% predicates via goal expansion. A runtime fallback remains when no
% macro applies.
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

% -----------------------------------------------------------------------------
%  GOAL EXPANSION
% -----------------------------------------------------------------------------

% search/2 expansion is module-local (query:goal_expansion/2), not
% user:goal_expansion/2. SWI strips the qualifier when compiling
% `query:search(Q, R://Id)` and consults this module's hooks with the
% bare term, so every qualified caller (and bare search/2 here) is
% inlined. A bare search/2 in another module never reaches this hook;
% callers must write query:search/2 to opt in.

goal_expansion(search(Q, Repo://Id), Expanded) :-
  is_list(Q),!,
  compile_query_list(Q, Repo://Id, Expanded).

goal_expansion(search(Q, Repo://Id), Expanded) :-
  compound(Q),!,
  compile_query_compound(Q, Repo://Id, Expanded).

% Hot candidate.pl predicates are inlined via candidate:goal_expansion/2
% for the same qualifier-stripping reason. The hooks live here (not in
% candidate.pl/target.pl) because query.pl loads before resolving.pl —
% the main consumer — while those files load after it.
%
% Expanded bodies go through compile_query_compound/3 so they cannot
% drift from the predicate definitions. Each clause nonvar/==-checks
% Action before committing: head unification must not bind a variable
% Action at expansion time.
%
% The multifile declaration is required: loading candidate.pl would
% otherwise abolish these hook clauses.

:- multifile candidate:goal_expansion/2.

candidate:goal_expansion(installed(Repo://Id), Expanded) :-
  query:compile_query_compound(installed(true), Repo://Id, Expanded).

candidate:goal_expansion(eligible(Repo://Id:Action?{_}), Expanded) :-
  nonvar(Action),
  ( Action == download
  -> query:compile_query_compound(ebuild(Id), Repo://Id, Expanded)
  ;  query:compile_query_compound(masked(true), Repo://Id, Masked),
     Expanded =
       ( ( Masked -> ( prover:assuming(unmask) -> true
                     ; memo:visibility_override_(Repo, Id) )
         ; true ),
         ( acceptance:entry_has_accepted_keyword(Repo://Id) -> true
         ; prover:assuming(keyword_acceptance) -> true
         ; memo:visibility_override_(Repo, Id) ) )
  ).

candidate:goal_expansion(resolve(_Repo://_Id:Action?{Context}, Conditions), Expanded) :-
  Action == download,
  Expanded = featureterm:get(after, Context, Conditions).


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

% Clauses are grouped by query type (entry_metadata, select, all, etc.).
:- discontiguous compile_query_compound/3.

% We turn compound queries into cache statements


% -----------------------------------------------------------------------------
%  Helpers: annotate REQUIRED_USE terms for :validate proof
% -----------------------------------------------------------------------------
%
% The REQUIRED_USE grammar contains pure boolean constraints over USE flags.
% When proving them, we annotate every term with :validate?{[self(Self)]} so
% the rules know (a) we are validating, and (b) which ebuild provides the
% effective USE context.  No global flag is needed.

query:with_required_use_validate(Self, Terms, AnnotatedTerms) :-
  Ctx = [self(Self)],
  maplist(query:annotate_validate(Ctx), Terms, AnnotatedTerms).

query:annotate_validate(Ctx, T, T:validate?{Ctx}).


%! query:strip_validate_annotation(+AnnotatedKey, -Key)
%
% Strips :validate?{_} annotation from model keys produced by
% REQUIRED_USE validation. Non-annotated keys pass through unchanged.

query:strip_validate_annotation(AKey, Key) :-
  ( AKey = Key0:validate -> Key = Key0 ; Key = AKey ).


%! query:repo_not_vdb(?Repo)
%
% Guard used by the compiled `select(repository,notequal,pkg)` query: when
% Repo is already bound it must not be a VDB repository; when still unbound
% it passes (Repo is bound by later compounds in the compiled conjunction,
% mirroring the permissiveness of the previous `pkg \== Repo` check).

query:repo_not_vdb(Repo) :-
  ( var(Repo) ->
      true
  ;   \+ knowledgebase:is_vdb_repository(Repo)
  ).


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

% Installed-state lookups resolve the active VDB repository at runtime via
% knowledgebase:vdb_repository/1 (memoized): `pkg` in standalone mode, the
% per-client import (`pkg@<clienthost>`) in a Pengines sandbox context.

compile_query_compound(installed(true), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(VdbRepo, Id, _, _, _),
    (var(Repo) -> Repo = VdbRepo ; true) )) :- !.
compile_query_compound(installed(false), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(Repo, Id, _, _, _),
    \+ cache:ordered_entry(VdbRepo, Id, _, _, _) )) :- !.

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

compile_query_compound(maintainer(M), Repo://Id,
  ( cache:entry_metadata(Repo,Id,maintainer,Maintainers),
    member(M,Maintainers) )) :- !.

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

compile_query_compound(build_time(T), Repo://Id,
  cache:entry_metadata(Repo,Id,build_time,T)) :- !.

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


% 5b. GLSA bridges (advisories are not a package repository; join onto
%     an existing Repo://Entry via glsa.pl facts)

compile_query_compound(vulnerable(true), Repo://Id,
  ( current_predicate(glsa:entry_covered/2),
    glsa:ensure_loaded,
    glsa:search([vulnerable(true)], GlsaId),
    glsa:entry_covered(GlsaId, Repo://Id) )) :- !.

compile_query_compound(vulnerable(false), Repo://Id,
  ( cache:ordered_entry(Repo, Id, _, _, _),
    \+ ( current_predicate(glsa:entry_covered/2),
         glsa:ensure_loaded,
         glsa:search([vulnerable(true)], GlsaId),
         glsa:entry_covered(GlsaId, Repo://Id) ) )) :- !.

compile_query_compound(glsa(GlsaId), Repo://Id,
  ( current_predicate(glsa:entry_covered/2),
    glsa:entry_covered(GlsaId, Repo://Id) )) :- !.


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
  ; cache:entry_metadata(Repo,Id,rdepend,D)
  ; cache:entry_metadata(Repo,Id,pdepend,D) )) :- !.


% 7. key=value queries needed for --search

% Variable operator: emit a runtime dispatch over the operator. The Key is
% ==-checked so a query with a variable key is never miscompiled by binding
% it to 'version' at expansion time.

compile_query_compound(select(Key, Op, Ver), Repo://Id, Expanded) :-
  Key == version,
  var(Op), !,
  Expanded = (
    Op == none ->
      cache:ordered_entry(Repo, Id, _, _, _)
  ; Op == equal ->
      cache:ordered_entry(Repo, Id, _, _, Ver)
  ; Op == smaller ->
      ( cache:ordered_entry(Repo, Id, _, _, PV1),
        eapi:version_compare(<, PV1, Ver) )
  ; Op == greater ->
      ( cache:ordered_entry(Repo, Id, _, _, PV2),
        eapi:version_compare(>, PV2, Ver) )
  ; Op == smallerequal ->
      ( cache:ordered_entry(Repo, Id, _, _, PV3),
        ( eapi:version_compare(<, PV3, Ver)
        ; eapi:version_compare(=, PV3, Ver) ) )
  ; Op == greaterequal ->
      ( cache:ordered_entry(Repo, Id, _, _, PV4),
        ( eapi:version_compare(>, PV4, Ver)
        ; eapi:version_compare(=, PV4, Ver) ) )
  ; Op == notequal ->
      ( cache:ordered_entry(Repo, Id, _, _, PV5),
        PV5 \== Ver )
  ; Op == wildcard ->
      ( Ver = version(_,_,_,_,_,_,VW),
        cache:ordered_entry(Repo, Id, _, _, version(_,_,_,_,_,_,PV6)),
        wildcard_match(VW, PV6) )
  ; Op == tilde ->
      ( Ver = version(VT,LT,SRT,SNT,SReT,_,_),
        cache:ordered_entry(Repo, Id, _, _, version(VT,LT,SRT,SNT,SReT,_,_)) )
  ; var(Op) ->
      % Unbound operator at call time: behave like the 'none' operator
      % (this mirrors the former runtime search/2 clause, which unified a
      % variable operator with 'none' and enumerated all entries).
      ( Op = none,
        cache:ordered_entry(Repo, Id, _, _, _) )
  ; fail   % unknown operator: fail instead of re-entering runtime search
  ).

% Slot-constraint queries dispatch on the constraint-list skeleton. The
% skeleton must be a proper list of nonvar elements so compiling never
% binds variables in the caller's query term; inner slot/subslot
% arguments may stay unbound (they are outputs). This clause must
% precede the generic nonground-Cmp fallback below.

compile_query_compound(select(Key,Cmp,Sn), Repo://Id, Goal) :-
  Key == slot,
  nonvar(Cmp),
  Cmp = constraint(C),
  nonvar(C),
  query:slot_constraint_goal(C, Sn, Repo://Id, Goal),
  !.

compile_query_compound(select(Key,Cmp,Value), Repo://Id,
  ( search(select(Key,Cmp,Value), Repo://Id ) ))  :-
  nonground(Cmp,_),!.   % Important: filter out runtime bound Cmp

% `select(repository,notequal,pkg)` is the tree counterpart of an
% installed entry: Id must exist in the VDB, while Repo must not be a
% VDB repository. The atom `pkg` means the active VDB
% (`knowledgebase:vdb_repository/1`), so the same call sites work in
% standalone mode and against per-client imports (`pkg@<clienthost>`).

compile_query_compound(select(repository,notequal,pkg), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(VdbRepo,Id,_,_,_),
    query:repo_not_vdb(Repo) ) ) :- !.

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

compile_query_compound(select(version,equal,version_none), Repo://Id,
 cache:ordered_entry(Repo,Id,_,_,_)) :- !.

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

compile_query_compound(select(version,wildcard,version(_,_,_,_,_,_,V)),Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,version(_,_,_,_,_,_,ProposedVersion)),
    wildcard_match(V,ProposedVersion) )) :- !.

compile_query_compound(select(version,tilde,version(V,L,SR,SN,SRe,_,_)), Repo://Id,
  cache:ordered_entry(Repo,Id,_,_,version(V,L,SR,SN,SRe,_,_)) ) :- !.

compile_query_compound(select(eapi,notequal,version(_,_,_,_,_,_,V)), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,version(_,_,_,_,_,_,O)),
    O \== V ) ) :- !.

compile_query_compound(select(eapi,equal,version(_,_,_,_,_,_,V)), Repo://Id,
  cache:entry_metadata(Repo,Id,eapi,version(_,_,_,_,_,_,V)) ) :- !.

compile_query_compound(select(eapi,wildcard,version(_,_,_,_,_,_,V)), Repo://Id,
  ( cache:entry_metadata(Repo,Id,eapi,version(_,_,_,_,_,_,ProposedVersion)),
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

compile_query_compound(select(subslot,tilde,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,subslot(M)),
    dwim_match(S,M) ) ) :- !.

compile_query_compound(select(subslot,wildcard,S), Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,subslot(M)),
    wildcard_match(S,M) ) ) :- !.


%! query:slot_constraint_goal(+Constraint, ?Sn, +RepoId, -Goal)
%
% Maps a slot-constraint list to its cache-level goal. Fails (without
% binding anything in Constraint) when the skeleton is not sufficiently
% instantiated, in which case the query is deferred to runtime via the
% nonground-Cmp fallback above.

slot_constraint_goal(C, Sn, Repo://Id, Goal) :-
  is_list(C),
  maplist(nonvar, C),
  slot_constraint_goal_(C, Sn, Repo://Id, Goal).

slot_constraint_goal_([], Sn, Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn) )). 					% will work: test40

slot_constraint_goal_([slot(S)], Sn, Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn) )). 					% will work: test41

slot_constraint_goal_([slot(S),subslot(Ss)], Sn, Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn) )). 					% will work: test44

slot_constraint_goal_([slot(S),equal], Sn, Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn) )).					% adds chosen slot as a requirement to context - no test yet

slot_constraint_goal_([slot(S),subslot(Ss),equal], Sn, Repo://Id,
  ( cache:entry_metadata(Repo,Id,slot,slot(S)),
    cache:entry_metadata(Repo,Id,slot,subslot(Ss)),
    findall(R,cache:entry_metadata(Repo,Id,slot,R),Sn) )).					% adds chosen slot and subslot as a requirement to context - no test yet

slot_constraint_goal_([any_same_slot], Sn, Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    % For := (any_same_slot) we only want to lock the SLOT, not the SUBSLOT.
    % SUBSLOT is a rebuild trigger, not a satisfiability constraint.
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn) )).			% adds chosen slot as a requirement to context - test43

slot_constraint_goal_([any_different_slot], Sn, Repo://Id,
  ( cache:ordered_entry(Repo,Id,_,_,_),
    % Like any_same_slot, we only propagate the SLOT component.
    findall(slot(S), cache:entry_metadata(Repo,Id,slot,slot(S)), Sn) )).			% adds chosen slot as a requirement to context - test 42


compile_query_compound(select(keyword,equal,K),	Repo://Id,
  cache:entry_metadata(Repo,Id,keywords,K)) :- !.

compile_query_compound(select(keywords,equal,K), Repo://Id,
  cache:entry_metadata(Repo,Id,keywords,K)) :- !.

compile_query_compound(select(maintainer,equal,Pattern), Repo://Id,
  ( cache:entry_metadata(Repo,Id,maintainer,Maintainers),
    member(M,Maintainers),
    dwim_match(Pattern,M) )) :- !.

compile_query_compound(select(maintainer,wildcard,Pattern), Repo://Id,
  ( cache:entry_metadata(Repo,Id,maintainer,Maintainers),
    member(M,Maintainers),
    wildcard_match(Pattern,M) )) :- !.

compile_query_compound(select(maintainer,tilde,Pattern), Repo://Id,
  ( cache:entry_metadata(Repo,Id,maintainer,Maintainers),
    member(M,Maintainers),
    dwim_match(Pattern,M) )) :- !.

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

% Like installed(true)/installed(false) above: the active VDB repository is
% resolved at runtime via knowledgebase:vdb_repository/1 (memoized).
compile_query_compound(select(installed,equal,true), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(VdbRepo, Id, _, _, _),
    (var(Repo) -> Repo = VdbRepo ; true) )) :- !.

compile_query_compound(select(installed,equal,false), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(Repo, Id, _, _, _),
    \+ cache:ordered_entry(VdbRepo, Id, _, _, _) )) :- !.

compile_query_compound(select(installed,notequal,true), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(Repo, Id, _, _, _),
    \+ cache:ordered_entry(VdbRepo, Id, _, _, _) )) :- !.

compile_query_compound(select(installed,notequal,false), Repo://Id,
  ( knowledgebase:vdb_repository(VdbRepo),
    cache:ordered_entry(VdbRepo, Id, _, _, _),
    (var(Repo) -> Repo = VdbRepo ; true) )) :- !.


% 8. all query is treated at runtime, except for a few exceptions

compile_query_compound(all(S), Repo://Id,
  search(all(S),Repo://Id))	:-
  var(S),!.

compile_query_compound(all(S):A?{C}, Repo://Id,
  search(all(S):A?{C},Repo://Id)) :-
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
          ; cache:entry_metadata(Repo,Id,pdepend,Dep)
          ),
          D)) :- !.


% 10. some model queries are rewritten

% -----------------------------------------------------------------------------
%  Dependency-model cache key (hazard encoding)
% -----------------------------------------------------------------------------

% model(dependency) queries are cached per proof with a hazard-encoded key
% (memo:dep_model_cache_/5, gated by config:dep_model_cache/1).
%
% Model construction depends on mutable proof state beyond the explicit
% proof-context (`?{Context}`) argument.  Instead of clearing the cache
% whenever that state might change (two earlier, abandoned attempts),
% every mutable input is encoded in the cache key, so entries stay valid
% for the whole proof (across fallback tiers, reprove passes and partial
% restarts).  The hazards and their key encodings:
%
%   1. Proof-context (build_with_use:use_state(Pos,Neg)) — the same
%      (Ebuild,Phase) is reached through different dependency paths that
%      impose different USE requirements (e.g. qtbase reached with
%      [concurrent,dbus,...] vs [gui]).
%      -> the full (ground) proof-context term is part of the key.  This
%      also means no re-contextualisation is needed on a hit: the cached
%      output embeds exactly the keyed proof context.
%
%   2. prover:assuming(keyword_acceptance) / assuming(unmask) / assuming
%      (conflicts) / assuming(blockers) — nb_setval flags that change between
%      fallback tiers.  any_of_config_dep_ok calls
%      acceptance:accepted_keyword_candidate, which checks these flags.
%      -> the list of active flags among dep_model_assuming_hazards/1 is
%      part of the key (dep_model_assuming/1).
%
%   3. memo_selected_cn_snap — evolves during a single proof attempt as
%      packages are selected.  any_of_group:config calls
%      prioritize_deps_keep_all, whose snap_all / snap_admits criteria
%      reorder OR branches and lock a different choice into the model.
%      Presence is not enough: cabal's text-1.2 arm vs text-2 arm both
%      see "text is selected", and a model cached for text-2.1 stays
%      cached after a reprove selects text-1.2 (portage-ng#123).
%      -> per-entry choice-group C/N pairs are extracted once from the dep
%      metadata (memo:dep_model_choice_cns_/3); each pair that currently
%      has a snapshot contributes that pair plus the selected entry ids
%      (dep_model_selected_choice_cns/3). Entries without choice groups
%      contribute [] and are immune to this hazard.
%
%   4. variant:use_override/4 and variant:branch_prefer/1 — thread_local state
%      active only during variant exploration; affects effective_use_for_entry
%      (per-package USE flips) and OR group ordering.
%      -> cache bypassed entirely while variant state is active (key = none).
%
%   5. prover learned constraints (prover_learned_constraints) — the
%      learned cn_domain store persists across reprove passes and is
%      reset per fallback tier. any_of_config_dep_ok reads it through
%      candidate:config_candidate_blocked (an arm whose version match lies
%      outside a learned domain, or whose hard pins have no candidate left
%      inside one, is not kept; portage-ng#123). A model cached before
%      `ghc < 9.5` was learned must not answer after it.
%      -> the learned store term is part of the key
%      (dep_model_learned/1); `none` when no store is active. Learning is
%      rare (pass boundaries), so this costs one miss per change.
%
% Remaining inputs (VDB installed state, /etc/portage preferences, profile,
% keyword/license/mask config, favour/avoid flags) are constant within one
% proof; the cache is thread_local and cleared by memo:clear_caches at the
% start of each proof run, so cross-proof drift cannot leak.
%
% Profiling shows 25-30% of proving time in these queries.  Two earlier
% caches failed to produce wall-clock wins because they were cleared per
% pass to dodge hazards 2/3, capturing only ~6% of calls on heavy meta
% packages.  Measurement on kde-apps-meta (2718 calls, 995 distinct
% (entry,phase) pairs) shows the redundancy is cross-pass: an exact-key
% cache valid across passes hits 58.9%.  Projection-keyed variants
% (guard-flag / conditional-flip projections of the BWU context) add only
% ~3pp over the exact key — the distinct BWU states are genuinely
% different inputs, since the flags consumers force are exactly the flags
% gating conditionals — so the simple exact key is used.

%! query:dep_model_key(+Repo, +Id, +Context, -Key) is det
%
% Compute the hazard-encoded cache key for a model(dependency) query, or
% `none` when the query must not be cached (cache disabled, variant
% exploration active, or non-ground context).

query:dep_model_key(Repo, Id, Context, Key) :-
  ( query:dep_model_cache_enabled,
    \+ query:dep_model_variant_active,
    ground(Context)
  ->
    query:dep_model_assuming(Assuming),
    query:dep_model_selected_choice_cns(Repo, Id, Selected),
    query:dep_model_learned(Learned),
    Key = key(Context, Assuming, Selected, Learned)
  ; Key = none
  ).


%! query:dep_model_learned(-Learned) is det
%
% The prover's learned constraint store as it stands now (hazard 5), or
% `none` outside any reprove-managed proof.

query:dep_model_learned(Learned) :-
  ( nb_current(prover_learned_constraints, Store) ->
      Learned = Store
  ; Learned = none
  ).


%! query:dep_model_cache_enabled is semidet
%
% Gate for the dependency-model cache; config:dep_model_cache(false)
% disables it.

query:dep_model_cache_enabled :-
  ( current_predicate(config:dep_model_cache/1) ->
      config:dep_model_cache(true)
  ; true
  ).


%! query:dep_model_variant_active is semidet
%
% True while variant-exploration thread-local state is active (hazard 4);
% the cache is bypassed entirely in that case.

query:dep_model_variant_active :-
  current_predicate(variant:use_override/4),
  ( variant:use_override(_, _, _, _) -> true ; variant:branch_prefer(_) ),
  !.


%! query:dep_model_assuming_hazards(-Flags) is det
%
% The prover:assuming/1 flags that influence config-phase model
% construction (hazard 2).

query:dep_model_assuming_hazards([keyword_acceptance, unmask, conflicts, blockers]).


%! query:dep_model_assuming(-Active) is det
%
% The currently active flags among dep_model_assuming_hazards/1, in
% declaration order.

query:dep_model_assuming(Active) :-
  query:dep_model_assuming_hazards(Flags),
  include(prover:assuming, Flags, Active).


%! query:dep_model_selected_choice_cns(+Repo, +Id, -Selected) is det
%
% The entry's choice-group member C/N pairs that currently have a
% selected_cn snapshot, each paired with the selected entry ids
% (hazard 3). The entry ids matter: snap_admits ranks an arm by whether
% it admits the selected candidate, so a version change must miss the
% cache (portage-ng#123). Order follows dep_model_choice_cns/3. [] when
% the entry's dep metadata contains no choice groups, or none of those
% C/N pairs are selected yet.

query:dep_model_selected_choice_cns(Repo, Id, Selected) :-
  query:dep_model_choice_cns(Repo, Id, CNs),
  findall(C-N-Entries,
          ( member(C-N, CNs),
            query:dep_model_cn_selected(C-N, Entries)
          ),
          Selected).


%! query:dep_model_cn_selected(+CN, -Entries) is semidet
%
% Entries is the sorted list of selected repo-entries for CN.

query:dep_model_cn_selected(C-N, Entries) :-
  cnselect:snapshot_selected_cn_candidates(C, N, Entries), !.


%! query:dep_model_choice_cns(+Repo, +Id, -CNs) is det
%
% Sorted list of C-N pairs occurring inside choice groups (any_of,
% exactly_one_of, at_most_one_of) anywhere in the entry's dependency
% metadata.  Static per entry; memoized in memo:dep_model_choice_cns_/3.

query:dep_model_choice_cns(Repo, Id, CNs) :-
  ( memo:dep_model_choice_cns_(Repo, Id, Cached) ->
      CNs = Cached
  ; findall(CN,
            ( member(Kind, [depend, rdepend, bdepend, cdepend, idepend, pdepend]),
              cache:entry_metadata(Repo, Id, Kind, Term),
              query:dep_model_choice_cn(Term, CN)
            ),
            CNs0),
    sort(CNs0, CNs1),
    assertz(memo:dep_model_choice_cns_(Repo, Id, CNs1)),
    CNs = CNs1
  ).


%! query:dep_model_choice_cn(+Term, -CN) is nondet
%
% Enumerate C-N pairs of package deps inside choice groups of a dep AST
% term.  Descends group wrappers; only package deps that sit under a
% choice group are yielded.

query:dep_model_choice_cn(any_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_choice_cn(exactly_one_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_choice_cn(at_most_one_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_choice_cn(all_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_choice_cn(D, CN).

query:dep_model_choice_cn(use_conditional_group(_, _, _, Deps), CN) :-
  member(D, Deps),
  query:dep_model_choice_cn(D, CN).


%! query:dep_model_cn_under(+Term, -CN) is nondet
%
% All package-dep C-N pairs in a subtree (used for choice-group members,
% which may themselves be nested groups).

query:dep_model_cn_under(package_dependency(_, _, C, N, _, _, _, _), C-N).

query:dep_model_cn_under(all_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_cn_under(any_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_cn_under(exactly_one_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_cn_under(at_most_one_of_group(Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).

query:dep_model_cn_under(use_conditional_group(_, _, _, Deps), CN) :-
  member(D, Deps),
  query:dep_model_cn_under(D, CN).


compile_query_compound(model(FullModel,required_use(Model),build_with_use(Input)), Repo://Id,
  ( findall(ReqUse,
            cache:entry_metadata(Repo,Id,required_use,ReqUse),
            AllReqUse),
    sort(AllReqUse, AllReqUseU),
    query:with_required_use_validate(Repo://Id, AllReqUseU, AnnotatedReqUse),
    prover:prove_model(AnnotatedReqUse, t, AvlModel, t, _ConsOut, t),
    findall(Key,
            (gen_assoc(AKey,AvlModel,_),
             query:strip_validate_annotation(AKey, Key),
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
    query:with_required_use_validate(Repo://Id, AllReqUseU, AnnotatedReqUse2),
    prover:prove_model(AnnotatedReqUse2, t, AvlModel, t, _ConsOut, t),
    findall(Key,
            (gen_assoc(AKey,AvlModel,_Value),
             query:strip_validate_annotation(AKey, Key),
   	     \+eapi:abstract_syntax_construct(Key)),
            Model) ) ) :- !.

% The dependency model of an ebuild for one phase: the package_dependency
% leaves of the metadata trees that phase draws on (dep_model_sources/5),
% proven into a model (USE conditionals flattened), tagged with the phase
% the consumer proves them under (dep_model_leaf/4) and grouped. Cached
% per proof under the hazard-encoded key (see "Dependency-model cache
% key" above). One template, instantiated at compile time per phase.

compile_query_compound(model(dependency(Merged,Phase)):config?{Context}, Repo://Id, Goal) :-
  atom(Phase),
  query:dep_model_sources(Phase, Repo, Id, Dep, Sources),
  query:dep_model_leaf(Phase, Fact, LeafPhase, LeafPhaseGoals),
  append([ [ gen_assoc(Fact:_,AvlModel,CtxIn),
             Fact =.. [package_dependency|_] ],
           LeafPhaseGoals,
           [ ( CtxIn == {} -> CtxOut = [] ; CtxOut = CtxIn ) ] ],
         LeafGoals),
  query:goals_conjunction(LeafGoals, LeafGoal),
  Goal =
  ( query:dep_model_key(Repo, Id, Context, CacheKey),
    ( CacheKey \== none,
      memo:dep_model_cache_(Repo, Id, Phase, CacheKey, CachedMerged)
    ->
      Merged = CachedMerged
    ;
    ( memberchk(self(Repo://Id), Context)
      -> CtxSelf = Context
      ;  CtxSelf = [self(Repo://Id)|Context]
    ),
    findall(Dep:config?{CtxSelf}, Sources, Deps),
    sort(Deps, DepsU),
    prover:prove_model(DepsU, t, AvlModel, t, _ConsOut, t),
    findall(Fact:LeafPhase?{CtxOut}, LeafGoal, Model0),
    query:group_dependencies(Model0, Merged),
    ( CacheKey == none
      -> true
      ;  assertz(memo:dep_model_cache_(Repo, Id, Phase, CacheKey, Merged))
    ) ) ),
  !.


%! query:dep_model_sources(+Phase, +Repo, +Id, -Dep, -Sources)
%
% The goal enumerating the dependency trees Dep that the model of Phase
% is built from: the runtime trees for :run, PDEPEND alone for :pdepend,
% every build- and run-time tree (plus BDEPEND discovered at build time,
% feedback:discovered_bdepend_dep/3) for :install, and every tree
% including PDEPEND for :fetchonly, which must fetch the sources of the
% whole closure.

query:dep_model_sources(run, Repo, Id, Dep,
  ( cache:entry_metadata(Repo,Id,idepend,Dep)
  ; cache:entry_metadata(Repo,Id,rdepend,Dep)
  )).
query:dep_model_sources(pdepend, Repo, Id, Dep,
    cache:entry_metadata(Repo,Id,pdepend,Dep)).
query:dep_model_sources(install, Repo, Id, Dep,
  ( cache:entry_metadata(Repo,Id,bdepend,Dep)
  ; cache:entry_metadata(Repo,Id,cdepend,Dep)
  ; cache:entry_metadata(Repo,Id,depend,Dep)
  ; cache:entry_metadata(Repo,Id,idepend,Dep)
  ; cache:entry_metadata(Repo,Id,rdepend,Dep)
  ; feedback:discovered_bdepend_dep(Repo,Id,Dep)
  )).
query:dep_model_sources(fetchonly, Repo, Id, Dep,
  ( cache:entry_metadata(Repo,Id,bdepend,Dep)
  ; cache:entry_metadata(Repo,Id,cdepend,Dep)
  ; cache:entry_metadata(Repo,Id,depend,Dep)
  ; cache:entry_metadata(Repo,Id,idepend,Dep)
  ; cache:entry_metadata(Repo,Id,rdepend,Dep)
  ; cache:entry_metadata(Repo,Id,pdepend,Dep)
  )).


%! query:dep_model_leaf(+Phase, ?Fact, -LeafPhase, -Goals)
%
% How a proven package_dependency leaf Fact is tagged in the model of
% Phase. The :run and :install models keep the leaf's own phase tag
% (install / run / pdepend, read from the term); a PDEPEND leaf is a
% runtime dependency of the consumer and a fetch-only model fetches
% every leaf, so those two carry a fixed tag and need no extra goal.

query:dep_model_leaf(run,       Fact, Phase,     [Fact =.. [package_dependency,Phase|_]]).
query:dep_model_leaf(install,   Fact, Phase,     [Fact =.. [package_dependency,Phase|_]]).
query:dep_model_leaf(pdepend,   _,    run,       []).
query:dep_model_leaf(fetchonly, _,    fetchonly, []).


%! query:goals_conjunction(+Goals, -Conjunction)
%
% A non-empty list of goals as a right-nested conjunction.

query:goals_conjunction([G], G) :- !.
query:goals_conjunction([G|Gs], (G, C)) :-
  query:goals_conjunction(Gs, C).


% 11. qualified_target queries, generated by --merge, --unmerge and --info

compile_query_compound(qualified_target(none,Repo,C,P,version_none,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,_),
    query:apply_filters(Repo://Id,F) )) :- !.

compile_query_compound(qualified_target(none,Repo,C,P,V,F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,V),
    query:apply_filters(Repo://Id,F) )) :- !.

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

% Tilde (~) matches any revision of the given version: all version/7
% components except the revision and the full atom must coincide (same
% semantics as select(version,tilde,...) above).

compile_query_compound(qualified_target(tilde,Repo,C,P,version(V,L,SR,SN,SRe,_,_),F), Repo://Id,
  ( cache:ordered_entry(Repo,Id,C,P,version(V,L,SR,SN,SRe,_,_)),
    query:apply_filters(Repo://Id,F) )) :- !.



% 12. Fallback – Stuff for which a macro doesn't exist, we fall back to regular predicates

% The fallback goal is emitted unqualified: the goal-expansion machinery
% preserves the query:-qualifier of the original call site when inlining,
% and the runtime compile-then-call clause executes it inside this module,
% so it always resolves to query:search/2. Emitting the same term that was
% compiled also makes the recursive expansion reach its fixpoint at once.

compile_query_compound(Stmt, Entry,
  search(Stmt,Entry)).



% =============================================================================
%  QUERY PREDICATES
% =============================================================================

% These are evaluated at runtime.

% -----------------------------------------------------------------------------
%  Query: Search
% -----------------------------------------------------------------------------

%! query:search(+Query, ?Entry) is nondet.
%
% Compile-then-call: `compile_query_compound/3` is the single source of
% truth for every query form it covers. A runtime call compiles the
% query and executes the cache-level goal, so macro-covered forms have
% exactly one implementation. When there is no compilation rule, the
% compiler falls back to `search(Stmt, Entry)` (the deferred nonground
% Cmp clause does the same); detect that and let the runtime-only
% clauses below handle the query (all/model/latest, manifest, iuse
% state, use-expand, set membership, generic metadata).

search(Q, Repository://Entry) :-
  sampler:maybe_record_callsite(Q, Repository://Entry),
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


% Case : an all statement (single argument, with ?{Context})

search(all(Statement):Context,Repository://Entry) :-
  Statement =.. [Key,Values],
  !,
  findall(InnerValueA:Context,
          (InnerStatement =.. [Key,InnerValueA],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (single argument, without ?{Context})

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values],
  !,
  findall(InnerValue,
          (InnerStatement =.. [Key,InnerValue],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (dual argument, with ?{Context})

search(all(Statement):Context,Repository://Entry) :-
  Statement =.. [Key,Values,Filter],
  !,
  findall(InnerValueA:Context,
          (InnerStatement =.. [Key,InnerValueA,Filter],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : an all statement (dual argument, without ?{Context})

search(all(Statement),Repository://Entry) :-
  Statement =.. [Key,Values,Filter],
  !,
  findall(InnerValueA,
          (InnerStatement =.. [Key,InnerValueA,Filter],
           search(InnerStatement,Repository://Entry)),
          Values).


% Case : a model statement (dual argument, with ?{Context})

search(model(Statement):Action?{Context},Repository://Id) :-
  Statement =.. [Key,Model,Arg],
  !,
  StatementA =.. [Key,AllValues,Arg],
  search(all(StatementA):Action?{Context},Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (dual argument, without ?{Context})

search(model(Statement),Repository://Id) :-
  Statement =.. [Key,Model,Arg],
  !,
  StatementA =.. [Key,AllValues,Arg],
  search(all(StatementA),Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (single argument, with ?{Context})

search(model(Statement):Action?{Context},Repository://Id) :-
  Statement =.. [Key,Model],
  !,
  StatementA =.. [Key,AllValues],
  search(all(StatementA):Action?{Context},Repository://Id),
  prover:prove_recursive(AllValues,t,_,t,AvlModel,t,_,t,_),
  prover:model_to_list(AvlModel,Model).


% Case : a model statement (single argument, without ?{Context})

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
%  Search: slot constraint with an under-instantiated skeleton
% -----------------------------------------------------------------------------

% Runtime-only: reached when compile-then-call deferred the query because
% the constraint skeleton still contains variables. Compilation must not
% bind the caller's term; at call time that binding is the generator.
% once/1 commits to the first matching skeleton pattern of
% slot_constraint_goal_/4 (a fully unbound constraint unifies with []
% first and enumerates all entries); the cache goal then backtracks
% freely.

search(select(slot,constraint(C),Sn), Repo://Id) :-
  !,
  once(slot_constraint_goal_(C, Sn, Repo://Id, Goal)),
  call(Goal).

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
%  Search: iuse with use flag state
% -----------------------------------------------------------------------------

search(iuse(Iuse,State:Reason),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Value),
  eapi:categorize_use_for_entry(Value,R://I,State,Reason),
  eapi:use_flag_name(Value,Iuse).


% -----------------------------------------------------------------------------
%  Search: iuse without use_expand
% -----------------------------------------------------------------------------

search(iuse_filtered(Iuse),R://I) :-
  !,
  cache:entry_metadata(R,I,iuse,Arg),
  eapi:use_flag_name(Arg,Iuse),
  \+(eapi:check_use_expand_atom(Iuse)).


% -----------------------------------------------------------------------------
%  Search: iuse without use_expand, with use flag state
% -----------------------------------------------------------------------------

search(iuse_filtered(Iuse,State:Reason),R://I) :-
  !,
  setof(Iuse0,
        Arg0^(cache:entry_metadata(R,I,iuse,Arg0),
              eapi:use_flag_name(Arg0,Iuse0),
              \+ eapi:check_use_expand_atom(Iuse0)),
        IuseFlags),
  member(Iuse, IuseFlags),
  findall(State0:Reason0,
          ( cache:entry_metadata(R,I,iuse,Arg),
            eapi:use_flag_name(Arg,Iuse),
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
  eapi:use_flag_name(Arg,ArgB),
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
  eapi:use_flag_name(Arg,ArgB),
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

%! query:iuse_state_precedence(-Patterns) is det.
%
% USE flag state readings, strongest first. A flag that IUSE lists more
% than once (e.g. `+foo` and `foo`) yields one State:Reason reading per
% occurrence; the effective reading is the one matching the earliest
% pattern here. Profile force/mask are hard; package.use and make.conf
% preferences are soft overrides; then the ebuild default, then the
% implicit default. The last two patterns catch any other reason.

query:iuse_state_precedence(
  [ positive:profile_package_use_force,
    negative:profile_package_use_mask,
    positive:profile_use_force,
    negative:profile_use_mask,
    _:package_use,
    _:preference,
    positive:ebuild,
    negative:ebuild,
    _:default,
    positive:_,
    negative:_ ]).


%! query:iuse_effective_state_(+Readings, -State, -Reason) is semidet.
%
% The State:Reason reading of Readings that matches the earliest
% iuse_state_precedence/1 pattern.

query:iuse_effective_state_(Readings, State, Reason) :-
  query:iuse_state_precedence(Patterns),
  member(Pattern, Patterns),
  member(State:Reason, Readings),
  subsumes_term(Pattern, State:Reason),
  !.


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
  eapi:use_flag_name(Raw, Flag),
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
  eapi:use_flag_name(Raw, Flag),
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
  eapi:use_flag_name(Raw, Flag),
  wildcard_match(Pattern1, Flag).



select(Key,wildcard,Value,R://I) :-
  !,
  cache:entry_metadata(R,I,Key,Match),
  wildcard_match(Value,Match).


% -----------------------------------------------------------------------------
%  Grouping dependencies
% -----------------------------------------------------------------------------

%! group_dependencies(+Deps, -Groups)
%
% Groups the package dependencies of a model into
% grouped_package_dependency(BlockType, C, N, Members):Action?{Context}
% terms, one per distinct grouping key, in key order. Two dependencies
% share a group when they agree on phase, block type, category, name,
% slot restriction, action and proof context: a group is therefore
% phase-homogeneous, and explicit slots such as ruby:3.2 and ruby:3.3
% stay separate because they are satisfiable as separate slotted
% installs.
%
% A regular (non-blocker) group whose members still target several slots
% or several exactish versions of the same C/N (slotmeta:
% should_split_grouped_dep/1) is emitted as one singleton group per
% member, so each of them is resolved independently instead of as
% alternatives for one merge.

group_dependencies(Deps, Groups) :-
  maplist(dep_group_key, Deps, Keyed),
  msort(Keyed, Sorted),
  group_pairs_by_key(Sorted, Grouped),
  dep_groups(Grouped, Groups).


%! dep_group_key(+Dep, -Key-Dep)
%
% Pairs a package dependency E:Action?{Context} with its grouping key.

dep_group_key(E:Action?{Context}, (Phase-T-C-N-S:Action?{Context})-E) :-
  E = package_dependency(Phase,T,C,N,_,_,S,_).


%! dep_groups(+KeyedGroups, -Groups)
%
% Turns the Key-Members pairs of group_pairs_by_key/2 into grouped
% dependencies, splitting the multi-slot / multi-version regular groups
% into singletons. Variables in Action and Context stay shared with the
% input (no copying).

dep_groups([], []).
dep_groups([(_Phase-T-C-N-_S:Action?{Ctx})-Members|Rest], Groups) :-
  ( T == no,
    slotmeta:should_split_grouped_dep(Members)
  -> maplist(singleton_group(C, N, Action, Ctx), Members, Singletons),
     append(Singletons, Groups1, Groups)
  ;  Groups = [grouped_package_dependency(T,C,N,Members):Action?{Ctx}|Groups1]
  ),
  dep_groups(Rest, Groups1).


%! singleton_group(+C, +N, +Action, +Ctx, +Dep, -Group)

singleton_group(C, N, Action, Ctx, D, grouped_package_dependency(no,C,N,[D]):Action?{Ctx}).



% -----------------------------------------------------------------------------
%  Helper: Filter predicates
% -----------------------------------------------------------------------------

%! query:apply_filters(+RepoEntry, +Filters)
%
% Apply the slot/usedep filter list parsed by eapi:qualified_target/1 to a
% candidate entry. Filters is the [SlotReq, UseDeps] pair, where SlotReq is a
% slot restriction (e.g. [], [slot('5')], [any_same_slot]) and UseDeps is a
% list of use(Spec, Default) terms. Both elements are applied in turn; an
% entry passes only when it satisfies every filter element.

apply_filters(_R://_I,[]) :- !.

apply_filters(R://I,[H|T]) :-
  !,
  apply_filter(R://I,H),
  apply_filters(R://I,T).


%! query:apply_filter(+RepoEntry, +Filter)
%
% Apply a single filter element. An empty element imposes no restriction. A
% use dependency list requires every referenced flag to be supported by the
% candidate's IUSE (honouring (+)/(-) defaults for absent flags). Any other
% non-empty element is treated as a slot restriction and matched against the
% entry's slot metadata via preference:entry_satisfies_slot_req_/3.

apply_filter(_R://_I,[]) :- !.

apply_filter(R://I,[use(Spec,Default)|Rest]) :-
  !,
  forall(member(use(S,D), [use(Spec,Default)|Rest]),
         apply_use_filter(R://I, use(S,D))).

apply_filter(R://I,SlotReq) :-
  preference:entry_satisfies_slot_req_(R, I, SlotReq).


%! query:apply_use_filter(+RepoEntry, +UseDep)
%
% Selection-time check for a single use dependency: the candidate must declare
% the flag in its IUSE, unless the dependency's IUSE default ((+)/(-)) has the
% polarity the directive requires, which makes an absent flag acceptable.
% Optional directives (optenable/optdisable) only constrain when the flag is
% present, so they never exclude a candidate here. This is a presence filter
% only: it decides which ebuilds qualify, not which flags are enabled.
% Enabling/disabling a flag remains governed by the USE environment,
% package.use and the profile -- never by the target atom.

apply_use_filter(_R://_I, use(optenable(_), _)) :- !.

apply_use_filter(_R://_I, use(optdisable(_), _)) :- !.

apply_use_filter(R://I, use(Spec, Default)) :-
  eapi:use_flag_polarity(Spec, Polarity, Use),
  ( use:candidate_iuse_present(R://I, Use)
  -> true
  ;  Default == Polarity
  ).


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
   (Sign == positive -> preference:global_use(Use) ; preference:global_use(minus(Use))),
     deep_member(preference,Predicate,Conditional)).


% -----------------------------------------------------------------------------
%  Load-time check: compile_query_compound/3 only
% -----------------------------------------------------------------------------

% Catch typos that accidentally define compile_query_compound/4 or /5.

:- ( ( current_predicate(query:compile_query_compound/4)
     ; current_predicate(query:compile_query_compound/5) )
   -> throw(error(existence_error(macro_clause_arity,
                                  query:compile_query_compound/3),
                  'query.pl defines compile_query_compound/4 or /5: a macro clause was written with body goals as extra head arguments'))
   ; true ).