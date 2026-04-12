/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PREFERENCE
Meta-layer that merges configuration from multiple sources into a
unified preference store.  All USE, mask, keyword, and license queries
go through this module.

Configuration sources (highest priority first):

  1. Profile tree 
  2. User configuration 
  3. Environment
  4. Per-ebuild defaults

Submodules:
  - profile.pl      : reads the profile tree
  - userconfig.pl   : reads user configurationfiles
  - fallback.pl     : hardcoded defaults fallback
*/

:- module(preference, []).

% =============================================================================
%  PREFERENCE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Dynamic state
% -----------------------------------------------------------------------------

% -- Package masking (profiles + /etc/portage/package.mask) --
%    Storage predicate; query via preference:masked/1 dispatcher.

:- dynamic preference:local_masked/1.

% -- Global USE / keywords / flags --

:- dynamic preference:local_use/1.
:- dynamic preference:local_env_use/1.
:- dynamic preference:local_accept_keywords/1.
:- dynamic preference:local_flag/1.

% -- Per-package USE overrides --
%    Storage predicates; query via dispatchers of the same name without local_.

:- dynamic preference:local_userconfig_use/4.          % Category, Name, Use, State(positive|negative)
:- dynamic preference:local_profile_use_soft/3.       % Spec, Use, State(positive|negative)
:- dynamic preference:local_userconfig_use_versioned/3. % Spec, Use, State(positive|negative)

% -- Profile USE constraints (use.mask / use.force / package.use.mask / package.use.force) --

:- dynamic preference:local_profile_masked_use_flag/1. % Use flag that is masked
:- dynamic preference:local_profile_forced_use_flag/1. % Use flag that is forced
:- dynamic preference:local_profile_use_masked/2.      % Spec, Use
:- dynamic preference:local_profile_use_forced/2.      % Spec, Use

% -- System packages (@system profile set) --

:- dynamic preference:system_pkg/2.

% -- Package sets --

:- dynamic preference:local_set/2.

% -- World entries (snapshot for client-server transfer) --

:- dynamic preference:local_world_entry/1.

% -- License acceptance --

:- dynamic preference:local_license_group_raw/2.       % GroupName, [RawMembers]
:- dynamic preference:local_accept_license_wildcard/0. % asserted when '*' is in effect
:- dynamic preference:local_accepted_license/1.        % individual accepted license atoms
:- dynamic preference:local_denied_license/1.          % individual denied license atoms (for '* -X' patterns)


% -----------------------------------------------------------------------------
%  Initialization
% -----------------------------------------------------------------------------

%! preference:init is det.
%
% Sets the active local USE flags and ACCEPT_KEYWORDS according to
% environment, profile, and /etc/portage overrides.  Also loads license
% groups and applies ACCEPT_LICENSE.  Must never fail.

preference:init :-

  % Retract all dynamic facts

  retractall(preference:local_masked(_)),
  retractall(preference:local_userconfig_use(_,_,_,_)),
  retractall(preference:local_profile_masked_use_flag(_)),
  retractall(preference:local_profile_forced_use_flag(_)),
  retractall(preference:local_profile_use_masked(_,_)),
  retractall(preference:local_profile_use_forced(_,_)),
  retractall(preference:local_profile_use_soft(_,_,_)),
  retractall(preference:local_userconfig_use_versioned(_,_,_)),
  retractall(preference:local_license_group_raw(_,_)),
  retractall(preference:local_accept_license_wildcard),
  retractall(preference:local_accepted_license(_)),
  retractall(preference:local_denied_license(_)),

  % Reset preference AVL indexes

  ( nb_current(pref_userconfig_use_soft_flags, _) -> nb_setval(pref_userconfig_use_soft_flags, t) ; true ),
  ( nb_current(pref_userconfig_use_soft_cns, _) -> nb_setval(pref_userconfig_use_soft_cns, t) ; true ),
  ( nb_current(pref_profile_use_soft_flags, _) -> nb_setval(pref_profile_use_soft_flags, t) ; true ), 
  ( nb_current(pref_profile_use_soft_cns, _) -> nb_setval(pref_profile_use_soft_cns, t) ; true ),
  ( nb_current(pref_profile_forced_cns, _) -> nb_setval(pref_profile_forced_cns, t) ; true ),
  ( nb_current(pref_profile_masked_cns, _) -> nb_setval(pref_profile_masked_cns, t) ; true ),

  % 1. Load /etc/portage configuration (if portage_confdir is set).
  %    When unset, fallback defaults are used instead (step 4).

  catch(userconfig:load, _, true),

  % 2. Compute global USE flags (env > make.conf > fallback).
  %    Incremental; last occurrence wins.

  ( catch(preference:env_use_terms(EnvUseTerms), _, EnvUseTerms = []) ->
      forall(member(Term, EnvUseTerms),
             preference:apply_env_use_term(Term))
  ; true
  ),
  forall(preference:env_use_expand(Use),     (assertz(preference:local_env_use(Use)), assertz(preference:local_use(Use)))),
  ( preference:use_cached_profile ->
      profile:cache_load(CachedUseTerms, Masked, Forced),
      ProfileTerms = CachedUseTerms
  ; preference:profile_use_terms(ProfileTerms),
    ( config:gentoo_profile(ProfileRel),
      catch(profile:profile_use_mask(ProfileRel, Masked), _, Masked = []),
      catch(profile:profile_use_force(ProfileRel, Forced), _, Forced = []) ->
        true
    ; Masked = [], Forced = []
    )
  ),
  forall(member(U, Masked), assertz(preference:local_profile_masked_use_flag(U))),
  forall(member(U, Forced), assertz(preference:local_profile_forced_use_flag(U))),

  % Explicit USE_EXPAND values override profile defaults for that prefix.

  findall(Prefix,
          ( preference:use_expand_env(EnvVar, Prefix),
            preference:getenv(EnvVar, Atom),
            Atom \== ''
          ),
          UseExpandOverridePrefixes0),
  sort(UseExpandOverridePrefixes0, UseExpandOverridePrefixes),
  forall(member(preference:profile_use(Term), ProfileTerms),
         ( ( Term = minus(U0) -> U = U0 ; U = Term ),
           ( member(Prefix, UseExpandOverridePrefixes),
             atom_concat(Prefix, '_', PrefixUnderscore),
             atom_concat(PrefixUnderscore, _, U)
           )
         ->
           true
         ; Term = minus(Use) ->
             (preference:local_use(Use) ; assertz(preference:local_use(minus(Use))))
         ; Use = Term,
           (preference:local_use(minus(Use)) ; assertz(preference:local_use(Use)))
         )),

  % Derive single targets from multi-targets when not explicitly set.
  forall(preference:single_target_source(SingleEnv, Prefix, TargetsEnv),
         catch(preference:maybe_derive_single_target(SingleEnv, Prefix, TargetsEnv), _, true)),

  % 3. Set accept_keywords
  %
  % Portage semantics: if ~arch is accepted, the corresponding stable arch is
  % also accepted. E.g. ACCEPT_KEYWORDS="~amd64" still accepts KEYWORDS="amd64".

   ( preference:env_accept_keywords(_) ->
       forall(preference:env_accept_keywords(Key),
              assertz(preference:local_accept_keywords(Key))),
       forall(preference:env_accept_keywords(unstable(Arch)),
              ( preference:local_accept_keywords(stable(Arch))
              -> true
              ;  assertz(preference:local_accept_keywords(stable(Arch)))
              ))
   ; ( current_predicate(message:inform/1) ->
         catch(message:inform(['Warning: ACCEPT_KEYWORDS not set in environment or config.']), _, true)
     ; true
     )
   ),

  % 4. Apply profile, then userconfig overrides (or fallback if no portage_confdir).

  ( preference:use_cached_profile ->
      catch(profile:apply_cached_profile_data, _, true)
  ; catch(preference:apply_profile_package_mask, _, true),
    catch(preference:apply_profile_package_use_mask, _, true),
    catch(preference:apply_profile_package_use_force, _, true),
    catch(preference:apply_profile_package_use,  _, true)
  ),
  ( current_predicate(config:portage_confdir/1),
    config:portage_confdir(_) ->
      true
  ; catch(preference:apply_fallback_package_mask,  _, true),
    catch(preference:apply_fallback_package_use,   _, true)
  ),

  % 4b. Load @system packages from profile chain.

  catch(preference:init_system_pkgs, _, true),

  % 4c. Load named sets from Source/Knowledge/Sets/.

  catch(preference:init_sets, _, true),

  % 4d. Snapshot world entries for client-server transfer.

  catch(preference:init_world_entries, _, true),

  % 5. Load license groups and apply ACCEPT_LICENSE.

  ( preference:use_cached_profile ->
      true
  ; catch(preference:load_license_groups, _, true)
  ),
  catch(preference:init_accept_license, _, true),

  % 6. Load USE flag descriptions (for --show-descriptions).

  catch(profile:load_use_descriptions, _, true),
  !.


%! preference:apply_env_use_term(+Term) is det.
%
% Apply one environment USE term with last-wins semantics: retract any
% prior assertion for the flag, then assert the new state.

preference:apply_env_use_term(minus(Use)) :-
  !,
  retractall(preference:local_env_use(Use)),
  retractall(preference:local_env_use(minus(Use))),
  retractall(preference:local_use(Use)),
  retractall(preference:local_use(minus(Use))),
  assertz(preference:local_env_use(minus(Use))),
  assertz(preference:local_use(minus(Use))).

preference:apply_env_use_term(Use) :-
  retractall(preference:local_env_use(Use)),
  retractall(preference:local_env_use(minus(Use))),
  retractall(preference:local_use(Use)),
  retractall(preference:local_use(minus(Use))),
  assertz(preference:local_env_use(Use)),
  assertz(preference:local_use(Use)).


%! preference:profile_use_terms(-Terms:list) is det.
%
% Obtains profile-derived USE terms.
%
% If `config:gentoo_profile/1` is defined and the Portage profile tree is
% available, we derive these from Gentoo's inherited profile files via
% `profile.pl`.  If the predicate is not defined at all, a warning is emitted.
% If defined but profile data cannot be loaded (e.g. during --sync before the
% profile tree is ready), silently falls back to an empty list.

preference:profile_use_terms(Terms) :-
  ( \+ current_predicate(config:gentoo_profile/1) ->
      ( current_predicate(message:inform/1) ->
          catch(message:inform(['Warning: config:gentoo_profile/1 not set; profile USE flags unavailable. please investigate']), _, true)
      ; true
      ),
      Terms = []
  ; config:gentoo_profile(ProfileRel),
    catch(profile:profile_use_terms(ProfileRel, Terms0), _, fail) ->
      Terms = Terms0
  ; Terms = []
  ).


%! preference:use_cached_profile is semidet.
%
% Succeeds when the current mode is configured for cached profile loading
% and a profile cache file (Knowledge/profile.qlf) is available.

preference:use_cached_profile :-
  current_predicate(interface:process_mode/1),
  catch(interface:process_mode(Mode), _, fail),
  current_predicate(config:profile_loading/2),
  config:profile_loading(Mode, cached),
  current_predicate(profile:cache_available/0),
  profile:cache_available.


% -----------------------------------------------------------------------------
%  Environment accessors
% -----------------------------------------------------------------------------

%! preference:getenv(+Name, -Value) is semidet.
%
% Reads an environment variable with the following fallback chain:
%   1. OS environment (interface:getenv/2)
%   2. /etc/portage/make.conf (userconfig:env/2, loaded by userconfig:load)
%   3. fallback:env/2 facts (development defaults)

preference:getenv(Name, Value) :-
  ( interface:getenv(Name, Value) ->
      true
  ; current_predicate(userconfig:env/2),
    userconfig:env(Name, Value),
    Value \== '' ->
      true
  ; current_predicate(fallback:env/2),
    fallback:env(Name, Value),
    Value \== '' ->
      true
  ).


%! preference:env_use_terms(-Terms:list) is semidet.
%
% Parses USE in one go, preserving order (incremental semantics).

preference:env_use_terms(Terms) :-
  preference:getenv('USE', Atom),
  atom_codes(Atom, Codes),
  phrase(eapi:iuse(_://_, Terms), Codes),
  !.


%! preference:env_use_expand(?Use) is nondet.
%
% Imports USE_EXPAND-like environment variables (e.g. RUBY_TARGETS="ruby33")
% into portage-ng's USE flag space (e.g. ruby_targets_ruby33).
%
% This helps align portage-ng with Portage, where such variables influence USE
% but are not necessarily present in the global USE envvar string.
%
% NOTE: This is a pragmatic approximation: Portage applies these per-package
% based on IUSE_EXPAND. We model them as globally enabled flags.

preference:env_use_expand(Use) :-
  preference:use_expand_env(EnvVar, Prefix),
  preference:getenv(EnvVar, Atom),
  Atom \== '',
  split_string(Atom, " ", " \t\n", Parts),
  member(S, Parts),
  S \== "",
  atom_string(Token, S),
  atomic_list_concat([Prefix, Token], '_', Use).


%! preference:use_expand_env(?EnvVar, ?Prefix) is nondet.
%
% Derives the env var name from the canonical eapi:use_expand/1 list.

preference:use_expand_env(EnvVar, Prefix) :-
  eapi:use_expand(Prefix),
  upcase_atom(Prefix, EnvVar).


%! preference:env_accept_keywords(?Keyword) is nondet.
%
% Returns individual parsed ACCEPT_KEYWORDS terms as read from the
% ACCEPT_KEYWORDS environment variable.

preference:env_accept_keywords(Keyword) :-
  preference:getenv('ACCEPT_KEYWORDS',Atom),
  atom_codes(Atom,Codes),
  phrase(eapi:keywords(List),Codes),
  member(Keyword,List).


%! preference:any_local_use_prefix(+Prefix) is semidet.
%
% True if any asserted local_use/1 flag starts with Prefix followed by '_'.

preference:any_local_use_prefix(Prefix) :-
  atom(Prefix),
  atom_concat(Prefix, '_', PrefixUnderscore),
  preference:local_use(U),
  atom(U),
  sub_atom(U, 0, _, _, PrefixUnderscore),
  !.


%! preference:last_env_token(+Atom, -Token) is semidet.
%
% Splits Atom on whitespace and unifies Token with the last non-empty part.

preference:last_env_token(Atom, Token) :-
  atom(Atom),
  Atom \== '',
  split_string(Atom, " ", " \t\n", Parts0),
  exclude(=(""), Parts0, Parts),
  Parts \== [],
  last(Parts, LastS),
  atom_string(Token, LastS),
  Token \== ''.


%! preference:single_target_source(?SingleEnv, ?Prefix, ?TargetsEnv) is nondet.
%
% Derives *_SINGLE_TARGET / *_TARGETS pairs from eapi:use_expand/1.

preference:single_target_source(SingleEnv, SinglePrefix, TargetsEnv) :-
  eapi:use_expand(SinglePrefix),
  atom_concat(Base, '_single_target', SinglePrefix),
  atom_concat(Base, '_targets', TargetsPrefix),
  eapi:use_expand(TargetsPrefix),
  upcase_atom(SinglePrefix, SingleEnv),
  upcase_atom(TargetsPrefix, TargetsEnv).


%! preference:maybe_derive_single_target(+SingleEnv, +Prefix, +TargetsEnv) is det.
%
% If SingleEnv is not explicitly set, derive it from the last token of
% TargetsEnv.

preference:maybe_derive_single_target(SingleEnv, Prefix, TargetsEnv) :-
  ( preference:getenv(SingleEnv, Atom),
    Atom \== '' ->
      true
  ; preference:any_local_use_prefix(Prefix) ->
      true
  ; preference:getenv(TargetsEnv, TargetsAtom),
    TargetsAtom \== '',
    preference:last_env_token(TargetsAtom, Token),
    atomic_list_concat([Prefix, Token], '_', Use),
    ( preference:local_env_use(Use) -> true ; assertz(preference:local_env_use(Use)) ),
    ( preference:local_use(Use)     -> true ; assertz(preference:local_use(Use)) )
  ),
  !.

preference:maybe_derive_single_target(_, _, _).


% -----------------------------------------------------------------------------
%  Query predicates
% -----------------------------------------------------------------------------

%! preference:global_use(?Use) is nondet.
%
% Returns active USE flag settings.  In standalone mode, the flags are
% asserted by preference:init/0.  In client-server mode, they are
% injected as thread-local clauses by the Pengines sandbox.

preference:global_use(X) :-
  ( pengine_self(M) ->
      M:local_use(X)
  ; preference:local_use(X)
  ).


%! preference:global_use(?Use, +Source) is nondet.
%
% Returns USE flag settings filtered by Source:
%   - `env`   : only flags set via the environment
%   - `other` : all active flags (delegates to preference:global_use/1)

preference:global_use(X,env) :-
  ( pengine_self(M) ->
      M:local_env_use(X)
  ; preference:local_env_use(X)
  ).

preference:global_use(X,other) :-
  preference:global_use(X).


%! preference:accept_keywords(?Keyword) is nondet.
%
% Returns active ACCEPT_KEYWORDS settings.  In standalone mode, the
% keywords are asserted by preference:init/0.  In client-server mode,
% they are injected as thread-local clauses by the Pengines sandbox.

preference:accept_keywords(X) :-
  ( pengine_self(M) ->
      M:local_accept_keywords(X)
  ; preference:local_accept_keywords(X)
  ).


%! preference:package_keyword_accepted(+C, +N, +K) is semidet.
%
% True if keyword K is accepted for category C / name N via a
% per-package entry in /etc/portage/package.accept_keywords
% (loaded into userconfig:package_keyword/2 by userconfig:load).

preference:package_keyword_accepted(C, N, K) :-
  current_predicate(userconfig:package_keyword/2),
  atomic_list_concat([C, N], '/', CatPkg),
  userconfig:package_keyword(CatPkg, RawKW),
  preference:raw_keyword_matches_(RawKW, K),
  !.

preference:raw_keyword_matches_('**', _) :- !.
preference:raw_keyword_matches_('~*', unstable(_)) :- !.
preference:raw_keyword_matches_(RawKW, K) :-
  atom_codes(RawKW, Codes),
  catch(phrase(eapi:keywords([K0]), Codes), _, fail),
  K0 == K,
  !.


%! preference:flag(?Flag) is nondet.
%
% Returns active interface flags (deep, emptytree, etc.).
% In standalone mode, set by interface.  In client-server mode,
% injected as thread-local clauses by the Pengines sandbox.

preference:flag(Flag) :-
  ( pengine_self(M) ->
      M:local_flag(Flag)
  ; preference:local_flag(Flag)
  ).


%! preference:masked(?Entry) is nondet.
%
% Returns masked entries.  In standalone mode, the masks are asserted
% by preference:init/0.  In client-server mode, they are injected as
% thread-local clauses by the Pengines sandbox.

preference:masked(X) :-
  ( pengine_self(M) ->
      M:local_masked(X)
  ; preference:local_masked(X)
  ).


%! preference:userconfig_use(?C, ?N, ?Use, ?State) is nondet.
%
% Per-package USE overrides from /etc/portage/package.use.
% Dispatches to the Pengine module in client-server mode.

preference:userconfig_use(C, N, Use, State) :-
  ( pengine_self(M) ->
      M:local_userconfig_use(C, N, Use, State)
  ; preference:local_userconfig_use(C, N, Use, State)
  ).


%! preference:userconfig_use_versioned(?Spec, ?Use, ?State) is nondet.
%
% Versioned per-package USE overrides.
% Dispatches to the Pengine module in client-server mode.

preference:userconfig_use_versioned(Spec, Use, State) :-
  ( pengine_self(M) ->
      M:local_userconfig_use_versioned(Spec, Use, State)
  ; preference:local_userconfig_use_versioned(Spec, Use, State)
  ).


%! preference:profile_use_soft(?Spec, ?Use, ?State) is nondet.
%
% Soft per-package USE from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_soft(Spec, Use, State) :-
  ( pengine_self(M) ->
      M:local_profile_use_soft(Spec, Use, State)
  ; preference:local_profile_use_soft(Spec, Use, State)
  ).


%! preference:profile_use_masked(?Spec, ?Use) is nondet.
%
% Per-package USE masks from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_masked(Spec, Use) :-
  ( pengine_self(M) ->
      M:local_profile_use_masked(Spec, Use)
  ; preference:local_profile_use_masked(Spec, Use)
  ).


%! preference:profile_use_forced(?Spec, ?Use) is nondet.
%
% Per-package USE forces from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_forced(Spec, Use) :-
  ( pengine_self(M) ->
      M:local_profile_use_forced(Spec, Use)
  ; preference:local_profile_use_forced(Spec, Use)
  ).


%! preference:profile_masked_use_flag(?Use) is nondet.
%
% Global USE flags masked by the profile.
% Dispatches to the Pengine module in client-server mode.

preference:profile_masked_use_flag(U) :-
  ( pengine_self(M) ->
      M:local_profile_masked_use_flag(U)
  ; preference:local_profile_masked_use_flag(U)
  ).


%! preference:profile_forced_use_flag(?Use) is nondet.
%
% Global USE flags forced by the profile.
% Dispatches to the Pengine module in client-server mode.

preference:profile_forced_use_flag(U) :-
  ( pengine_self(M) ->
      M:local_profile_forced_use_flag(U)
  ; preference:local_profile_forced_use_flag(U)
  ).


%! preference:set(?Name, ?List) is nondet.
%
% Named package sets.
% Dispatches to the Pengine module in client-server mode.

preference:set(Name, List) :-
  ( pengine_self(M) ->
      M:local_set(Name, List)
  ; preference:local_set(Name, List)
  ).


%! preference:world_entry(?Entry) is nondet.
%
% World set entries.
% Dispatches to the Pengine module in client-server mode.

preference:world_entry(E) :-
  ( pengine_self(M) ->
      M:local_world_entry(E)
  ; preference:local_world_entry(E)
  ).


%! preference:license_group_raw(?Name, ?Members) is nondet.
%
% Raw license group definitions from the profile.
% Dispatches to the Pengine module in client-server mode.

preference:license_group_raw(Name, Members) :-
  ( pengine_self(M) ->
      M:local_license_group_raw(Name, Members)
  ; preference:local_license_group_raw(Name, Members)
  ).


%! preference:accept_license_wildcard is semidet.
%
% True when ACCEPT_LICENSE contains '*'.
% Dispatches to the Pengine module in client-server mode.

preference:accept_license_wildcard :-
  ( pengine_self(M) ->
      M:local_accept_license_wildcard
  ; preference:local_accept_license_wildcard
  ).


%! preference:accepted_license(?License) is nondet.
%
% Individual accepted license atoms.
% Dispatches to the Pengine module in client-server mode.

preference:accepted_license(L) :-
  ( pengine_self(M) ->
      M:local_accepted_license(L)
  ; preference:local_accepted_license(L)
  ).


%! preference:denied_license(?License) is nondet.
%
% Individual denied license atoms (for '* -X' patterns).
% Dispatches to the Pengine module in client-server mode.

preference:denied_license(L) :-
  ( pengine_self(M) ->
      M:local_denied_license(L)
  ; preference:local_denied_license(L)
  ).


%! preference:keyword_selection_mode(?Mode) is det.
%
% Controls how accepted keywords influence version selection:
%
% - max_version   : Portage-like. Treat ACCEPT_KEYWORDS as a set; prefer the
%                  highest version among all candidates that match any accepted
%                  keyword.
% - keyword_order : Legacy/experimental. Treat the enumeration order of
%                  preference:accept_keywords/1 as a preference (e.g. stable
%                  before unstable), even if a newer version exists under a
%                  later keyword.
%
% NOTE: This affects how `rules.pl` enumerates dependency candidates.

% For Portage parity with ACCEPT_KEYWORDS="amd64 ~amd64", Portage generally
% treats both as accepted and prefers the highest version available (i.e. don't
% artificially prefer stable over unstable when both are accepted).

preference:keyword_selection_mode(max_version).


% -----------------------------------------------------------------------------
%  Per-package USE resolution
% -----------------------------------------------------------------------------

%! preference:profile_package_use_spec(+Atom, -Spec) is semidet.
%
% Normalize a profile atom into a matching spec.  Supported forms:
%   - simple(C,N,SlotReq)                     (cat/pkg[:slot])
%   - versioned(Op,C,N,Ver,SlotReq)           (>=cat/pkg-1.2[:slot], ...)
%
% USE deps in the atom are intentionally ignored.
% A target of the form cat/pkg-1.2 (no operator) is treated like '=' (exact).

preference:profile_package_use_spec(Atom, Spec) :-
  atom(Atom),
  atom_codes(Atom, Codes),
  catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
  Q = qualified_target(Op, _Repo, C, N, Ver0, [SlotReq,_UseDeps]),
  nonvar(C), nonvar(N),
  ( Ver0 == version_none ->
      Spec = simple(C, N, SlotReq)
  ; Op == none ->
      Spec = versioned(equal, C, N, Ver0, SlotReq)
  ; Spec = versioned(Op, C, N, Ver0, SlotReq)
  ),
  !.


%! preference:is_simple_catpkg_atom_(+Atom) is semidet.
%
% True if Atom is a plain cat/pkg atom without version operators, slots,
% USE deps, or wildcards.

preference:is_simple_catpkg_atom_(Atom) :-
  atom(Atom),
  atomic_list_concat([_C, _N], '/', Atom),
  \+ sub_atom(Atom, 0, 1, _, '>'),
  \+ sub_atom(Atom, 0, 1, _, '<'),
  \+ sub_atom(Atom, 0, 1, _, '='),
  \+ sub_atom(Atom, 0, 1, _, '~'),
  \+ sub_atom(Atom, _, 1, _, ':'),
  \+ sub_atom(Atom, _, 1, _, '['),
  \+ sub_atom(Atom, _, 1, _, '*'),
  !.


%! preference:entry_satisfies_slot_req_(+Repo, +Id, +SlotReq) is semidet.
%
% Slot matching helper for profile atoms.  SlotReq is the parsed slot
% restriction list from eapi:qualified_target/1 (e.g. [], [slot('26')]).

preference:entry_satisfies_slot_req_(_Repo, _Id, []) :- !.

preference:entry_satisfies_slot_req_(Repo, Id, SlotReq) :-
  ( member(slot(S0), SlotReq) ->
      cache:entry_metadata(Repo, Id, slot, slot(S1)),
      preference:canon_slot_atom_(S0, S),
      preference:canon_slot_atom_(S1, Slot),
      S == Slot
  ; true
  ),
  !.


%! preference:canon_slot_atom_(+S0, -S) is det.
%
% Normalize a slot value to an atom (integers/numbers are converted).

preference:canon_slot_atom_(S0, S) :-
  ( atom(S0) -> S = S0
  ; integer(S0) -> atom_number(S, S0)
  ; number(S0) -> atom_number(S, S0)
  ; S = S0
  ),
  !.


%! preference:profile_package_use_cp_from_spec_(+Spec, -C, -N) is semidet.
%
% Extract category and name from a spec term.

preference:profile_package_use_cp_from_spec_(simple(C, N, _), C, N) :- !.
preference:profile_package_use_cp_from_spec_(versioned(_, C, N, _, _), C, N) :- !.


%! preference:profile_package_use_spec_matches_entry_(+Spec, +Repo, +Id, +C, +N, +ProposedVersion) is semidet.
%
% True if Spec matches the given entry (slot and version constraints checked).

preference:profile_package_use_spec_matches_entry_(simple(C, N, SlotReq), Repo, Id, C, N, _ProposedVersion) :-
  preference:entry_satisfies_slot_req_(Repo, Id, SlotReq),
  !.

preference:profile_package_use_spec_matches_entry_(versioned(Op, C, N, ReqVer, SlotReq), Repo, Id, C, N, ProposedVersion) :-
  preference:version_match(Op, ProposedVersion, ReqVer),
  preference:entry_satisfies_slot_req_(Repo, Id, SlotReq),
  !.


%! preference:profile_use_hard(+Entry, ?Use, -State, -Reason) is semidet.
%
% Determine whether a profile enforces a hard per-package USE state for
% an entry.  Precedence: mask wins over force (Portage-like).

preference:profile_use_hard(Repo://Id, Use, State, Reason) :-
  cache:ordered_entry(Repo, Id, C, N, ProposedVersion),
  ( preference:profile_masked_cn_known(C, N),
    ( preference:profile_use_masked(simple(C,N,SlotReq), Use),
      preference:entry_satisfies_slot_req_(Repo, Id, SlotReq)
    ; preference:profile_use_masked(versioned(Op,C,N,ReqVer,SlotReq), Use),
      preference:version_match(Op, ProposedVersion, ReqVer),
      preference:entry_satisfies_slot_req_(Repo, Id, SlotReq)
    ) ->
      State = negative,
      Reason = profile_package_use_mask
  ; preference:profile_forced_cn_known(C, N),
    ( preference:profile_use_forced(simple(C,N,SlotReq), Use),
      preference:entry_satisfies_slot_req_(Repo, Id, SlotReq)
    ; preference:profile_use_forced(versioned(Op,C,N,ReqVer,SlotReq), Use),
      preference:version_match(Op, ProposedVersion, ReqVer),
      preference:entry_satisfies_slot_req_(Repo, Id, SlotReq)
    ) ->
      State = positive,
      Reason = profile_package_use_force
  ),
  !.


%! preference:apply_profile_package_use_mask is det.
%
% Load package.use.mask files from the Gentoo profile tree and assert
% profile_use_masked/2 facts.

preference:apply_profile_package_use_mask :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_file(Dir, 'package.use.mask', masked), _, true))
  ; true
  ).


%! preference:apply_profile_package_use_force is det.
%
% Load package.use.force files from the Gentoo profile tree and assert
% profile_use_forced/2 facts.

preference:apply_profile_package_use_force :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_file(Dir, 'package.use.force', forced), _, true))
  ; true
  ).


%! preference:apply_profile_package_use_file(+Dir, +Basename, +Kind) is det.
%
% Parse a single package.use.{mask,force} file and assert the appropriate
% per-package USE constraint facts.

preference:apply_profile_package_use_file(Dir, Basename, Kind) :-
  os:compose_path(Dir, Basename, File),
  ( exists_file(File) ->
      catch(read_file_to_string(File, S, []), _, S = ""),
      split_string(S, "\n", "\r\n", Lines0),
      forall(member(L0, Lines0),
             ( profile:profile_strip_comment(L0, L1),
               normalize_space(string(L2), L1),
               ( L2 == "" ->
                   true
               ; split_string(L2, " ", "\t ", Ws0),
                 exclude(=(""), Ws0, Ws),
                 ( Ws = [AtomS|FlagSs],
                   atom_string(AtomA, AtomS),
                   preference:profile_package_use_spec(AtomA, Spec) ->
                     forall(member(FlagS0, FlagSs),
                            preference:apply_profile_package_use_flag(Kind, Spec, FlagS0))
                 ; true
                 )
               )
             ))
  ; true
  ).


%! preference:apply_profile_package_use_flag(+Kind, +Spec, +FlagS0) is det.
%
% Parse a single flag string (possibly '-'-prefixed) and dispatch to
% apply_profile_package_use_op/4 to add or delete the constraint.

preference:apply_profile_package_use_flag(Kind, Spec, FlagS0) :-
  normalize_space(string(FlagS), FlagS0),
  ( FlagS == "" -> true
  ; sub_string(FlagS, 0, 1, _, "-") ->
      sub_string(FlagS, 1, _, 0, Name0),
      normalize_space(string(Name), Name0),
      Name \== "",
      atom_string(Flag, Name),
      preference:apply_profile_package_use_op(del, Kind, Spec, Flag)
  ; atom_string(Flag, FlagS),
    preference:apply_profile_package_use_op(add, Kind, Spec, Flag)
  ),
  !.


%! preference:apply_profile_package_use_op(+Action, +Kind, +Spec, +Flag) is det.
%
% Assert or retract a profile_use_masked/2 or
% profile_use_forced/2 fact for the given Spec and Flag.

preference:apply_profile_package_use_op(add, masked, Spec, Flag) :-
  ( preference:profile_use_masked(Spec, Flag) -> true
  ; assertz(preference:local_profile_use_masked(Spec, Flag))
  ),
  !.

preference:apply_profile_package_use_op(del, masked, Spec, Flag) :-
  ( preference:profile_package_use_cp_from_spec_(Spec, C, N) ->
      retractall(preference:local_profile_use_masked(simple(C, N, _), Flag)),
      retractall(preference:local_profile_use_masked(versioned(_, C, N, _, _), Flag))
  ; retractall(preference:local_profile_use_masked(Spec, Flag))
  ),
  !.

preference:apply_profile_package_use_op(add, forced, Spec, Flag) :-
  ( preference:profile_use_forced(Spec, Flag) -> true
  ; assertz(preference:local_profile_use_forced(Spec, Flag))
  ),
  !.

preference:apply_profile_package_use_op(del, forced, Spec, Flag) :-
  ( preference:profile_package_use_cp_from_spec_(Spec, C, N) ->
      retractall(preference:local_profile_use_forced(simple(C, N, _), Flag)),
      retractall(preference:local_profile_use_forced(versioned(_, C, N, _, _), Flag))
  ; retractall(preference:local_profile_use_forced(Spec, Flag))
  ),
  !.


%! preference:apply_profile_package_use is det.
%
% Apply per-package USE from the Gentoo profile tree (profiles/*/package.use).
% Needed for Portage parity for lua-single defaults and similar.

preference:apply_profile_package_use :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_dir(Dir), _, true))
  ; true
  ).


%! preference:apply_profile_package_use_dir(+Dir) is det.
%
% Parse a single profile directory's package.use file and assert soft
% per-package USE overrides.

preference:apply_profile_package_use_dir(Dir) :-
  os:compose_path(Dir, 'package.use', File),
  ( exists_file(File) ->
      catch(read_file_to_string(File, S, []), _, S = ""),
      split_string(S, "\n", "\r\n", Lines0),
      forall(member(L0, Lines0),
             ( profile:profile_strip_comment(L0, L1),
               normalize_space(string(L2), L1),
               ( L2 == "" ->
                   true
               ; split_string(L2, " ", "\t ", Ws0),
                 exclude(=(""), Ws0, Ws),
                 ( Ws = [AtomS|FlagSs] ->
                     atom_string(AtomA, AtomS),
                     ( preference:profile_package_use_spec(AtomA, Spec) ->
                         forall(member(FlagS0, FlagSs),
                                preference:apply_profile_use_soft_flag(Spec, FlagS0))
                     ; true )
                 ; true
                 )
               )
             ))
  ; true
  ).


%! preference:apply_profile_use_soft_flag(+Spec, +FlagS0) is det.
%
% Parse a single flag string and assert a profile_use_soft/3 fact.

preference:apply_profile_use_soft_flag(Spec, FlagS0) :-
  normalize_space(string(FlagS), FlagS0),
  ( FlagS == "" ->
      true
  ; sub_string(FlagS, 0, 1, _, "-") ->
      sub_string(FlagS, 1, _, 0, Name0),
      normalize_space(string(Name), Name0),
      Name \== "",
      atom_string(Flag, Name),
      retractall(preference:local_profile_use_soft(Spec, Flag, _)),
      assertz(preference:local_profile_use_soft(Spec, Flag, negative))
  ; atom_string(Flag, FlagS),
    retractall(preference:local_profile_use_soft(Spec, Flag, _)),
    assertz(preference:local_profile_use_soft(Spec, Flag, positive))
  ),
  !.


%! preference:profile_use_soft_match(+Entry, ?Use, -State) is semidet.
%
% Look up the soft (profile-derived) per-package USE override for Entry.
% Last-wins semantics across matching specs.

preference:profile_use_soft_match(Repo://Id, Use, State) :-
  preference:profile_use_soft_flag_known(Use),
  cache:ordered_entry(Repo, Id, C, N, ProposedVersion),
  preference:profile_use_soft_cn_known(C, N),
  findall(State0,
          ( preference:profile_use_soft(Spec, Use, State0),
            preference:profile_package_use_spec_matches_entry_(Spec, Repo, Id, C, N, ProposedVersion)
          ),
          States),
  States \== [],
  last(States, State),
  !.


%! preference:apply_fallback_package_use is det.
%
% Apply per-package USE overrides from fallback defaults
% (fallback:package_use/2).  Only effective when config:portage_confdir/1
% is not set (no real /etc/portage configured).

preference:apply_fallback_package_use :-
  ( current_predicate(fallback:package_use/2) ->
      forall(fallback:package_use(CNAtom, UseStr),
             preference:register_fallback_package_use(CNAtom, UseStr))
  ; true
  ).


%! preference:register_fallback_package_use(+CNAtom, +UseStr) is det.
%
% Register a single package.use line from fallback or /etc/portage.
% Simple cat/pkg atoms produce userconfig_use/4; versioned atoms
% produce userconfig_use_versioned/3 soft overrides.

preference:register_fallback_package_use(CNAtom, UseStr) :-
  atom(CNAtom),
  ( preference:is_simple_catpkg_atom_(CNAtom) ->
      preference:register_package_use(CNAtom, UseStr)
  ; preference:profile_package_use_spec(CNAtom, Spec) ->
      preference:register_userconfig_use_soft(Spec, UseStr)
  ; true
  ),
  !.

preference:register_fallback_package_use(_, _) :-
  true.


%! preference:register_package_use(+CNAtom, +UseStr) is det.
%
% Register per-package USE overrides for a simple cat/pkg atom.  Asserts
% userconfig_use/4 facts with positive/negative state.

preference:register_package_use(CNAtom, UseStr) :-
  atom(CNAtom),
  atomic_list_concat([C,N], '/', CNAtom),
  ( string(UseStr) ->
      UseS = UseStr
  ; atom(UseStr) ->
      atom_string(UseStr, UseS)
  ; % Unexpected input type - ignore defensively
    UseS = ""
  ),
  split_string(UseS, " ", " \t\r\n", Parts0),
  exclude(=(""), Parts0, Parts),
  forall(member(P, Parts),
         ( sub_atom(P, 0, 1, _, '-') ->
             sub_atom(P, 1, _, 0, Flag0),
             Flag0 \== '',
             atom_string(Flag, Flag0),
             retractall(preference:local_userconfig_use(C, N, Flag, _)),
             assertz(preference:local_userconfig_use(C, N, Flag, negative))
         ; atom_string(Flag, P),
           retractall(preference:local_userconfig_use(C, N, Flag, _)),
           assertz(preference:local_userconfig_use(C, N, Flag, positive))
         )).


%! preference:register_userconfig_use_soft(+Spec, +UseStr) is det.
%
% Register per-package USE overrides for a versioned/slotted spec.

preference:register_userconfig_use_soft(Spec, UseStr) :-
  ( string(UseStr) ->
      UseS = UseStr
  ; atom(UseStr) ->
      atom_string(UseStr, UseS)
  ; UseS = ""
  ),
  split_string(UseS, " ", " \t\r\n", Parts0),
  exclude(=(""), Parts0, Parts),
  forall(member(P, Parts),
         preference:apply_userconfig_use_soft_flag(Spec, P)),
  !.


%! preference:apply_userconfig_use_soft_flag(+Spec, +P) is det.
%
% Parse and assert a single USE flag for a userconfig soft override.

preference:apply_userconfig_use_soft_flag(Spec, P) :-
  ( sub_atom(P, 0, 1, _, '-') ->
      sub_atom(P, 1, _, 0, Flag0),
      Flag0 \== '',
      atom_string(Flag, Flag0),
      retractall(preference:local_userconfig_use_versioned(Spec, Flag, _)),
      assertz(preference:local_userconfig_use_versioned(Spec, Flag, negative))
  ; atom_string(Flag, P),
    retractall(preference:local_userconfig_use_versioned(Spec, Flag, _)),
    assertz(preference:local_userconfig_use_versioned(Spec, Flag, positive))
  ),
  !.


%! preference:userconfig_use_match(+Entry, ?Use, -State) is semidet.
%
% Look up the soft (userconfig/fallback-derived) per-package USE override
% for Entry.  Last-wins semantics across matching specs.

preference:userconfig_use_match(Repo://Id, Use, State) :-
  preference:userconfig_use_soft_flag_known(Use),
  cache:ordered_entry(Repo, Id, C, N, ProposedVersion),
  preference:userconfig_use_soft_cn_known(C, N),
  findall(State0,
          ( preference:userconfig_use_versioned(Spec, Use, State0),
            preference:profile_package_use_spec_matches_entry_(Spec, Repo, Id, C, N, ProposedVersion)
          ),
          States),
  States \== [],
  last(States, State),
  !.


%! preference:userconfig_use_soft_flag_known(+Use) is semidet.
%
% True if any userconfig_use_versioned/3 fact references Use.
% Builds a lazy AVL index on first call.

preference:userconfig_use_soft_flag_known(Use) :-
  ( nb_current(pref_userconfig_use_soft_flags, FlagSet) ->
      true
  ;
      findall(F-true, preference:userconfig_use_versioned(_, F, _), Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] ->
          empty_assoc(FlagSet)
      ;
          list_to_assoc(Pairs, FlagSet)
      ),
      nb_setval(pref_userconfig_use_soft_flags, FlagSet)
  ),
  get_assoc(Use, FlagSet, _).


%! preference:profile_use_soft_flag_known(+Use) is semidet.
%
% True if any profile_use_soft/3 fact references Use.
% Builds a lazy AVL index on first call.

preference:profile_use_soft_flag_known(Use) :-
  ( nb_current(pref_profile_use_soft_flags, FlagSet) ->
      true
  ;
      findall(F-true, preference:profile_use_soft(_, F, _), Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] ->
          empty_assoc(FlagSet)
      ;
          list_to_assoc(Pairs, FlagSet)
      ),
      nb_setval(pref_profile_use_soft_flags, FlagSet)
  ),
  get_assoc(Use, FlagSet, _).


%! preference:userconfig_use_soft_cn_known(+C, +N) is semidet.
%
% True if any userconfig_use_versioned/3 fact references category C, name N.
% Builds a lazy AVL index on first call.

preference:userconfig_use_soft_cn_known(C, N) :-
  ( nb_current(pref_userconfig_use_soft_cns, CNSet) ->
      true
  ;
      findall(cn(C0,N0)-true,
              ( preference:userconfig_use_versioned(Spec, _, _),
                preference:soft_spec_cn(Spec, C0, N0)
              ),
              Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] -> empty_assoc(CNSet) ; list_to_assoc(Pairs, CNSet) ),
      nb_setval(pref_userconfig_use_soft_cns, CNSet)
  ),
  get_assoc(cn(C,N), CNSet, _).


%! preference:profile_use_soft_cn_known(+C, +N) is semidet.
%
% True if any profile_use_soft/3 fact references category C, name N.
% Builds a lazy AVL index on first call.

preference:profile_use_soft_cn_known(C, N) :-
  ( nb_current(pref_profile_use_soft_cns, CNSet) ->
      true
  ;
      findall(cn(C0,N0)-true,
              ( preference:profile_use_soft(Spec, _, _),
                preference:soft_spec_cn(Spec, C0, N0)
              ),
              Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] -> empty_assoc(CNSet) ; list_to_assoc(Pairs, CNSet) ),
      nb_setval(pref_profile_use_soft_cns, CNSet)
  ),
  get_assoc(cn(C,N), CNSet, _).


%! preference:soft_spec_cn(+Spec, -C, -N) is semidet.
%
% Extract category and name from a simple or versioned spec term.

preference:soft_spec_cn(simple(C, N, _), C, N).
preference:soft_spec_cn(versioned(_, C, N, _, _), C, N).


%! preference:profile_forced_cn_known(+C, +N) is semidet.
%
% True if any profile_use_forced/2 fact references category C, name N.
% Builds a lazy AVL index on first call.

preference:profile_forced_cn_known(C, N) :-
  ( nb_current(pref_profile_forced_cns, CNSet) ->
      true
  ;
      findall(cn(C0,N0)-true,
              ( preference:profile_use_forced(Spec, _),
                preference:soft_spec_cn(Spec, C0, N0)
              ),
              Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] -> empty_assoc(CNSet) ; list_to_assoc(Pairs, CNSet) ),
      nb_setval(pref_profile_forced_cns, CNSet)
  ),
  get_assoc(cn(C,N), CNSet, _).


%! preference:profile_masked_cn_known(+C, +N) is semidet.
%
% True if any profile_use_masked/2 fact references category C, name N.
% Builds a lazy AVL index on first call.

preference:profile_masked_cn_known(C, N) :-
  ( nb_current(pref_profile_masked_cns, CNSet) ->
      true
  ;
      findall(cn(C0,N0)-true,
              ( preference:profile_use_masked(Spec, _),
                preference:soft_spec_cn(Spec, C0, N0)
              ),
              Pairs0),
      sort(1, @<, Pairs0, Pairs),
      ( Pairs == [] -> empty_assoc(CNSet) ; list_to_assoc(Pairs, CNSet) ),
      nb_setval(pref_profile_masked_cns, CNSet)
  ),
  get_assoc(cn(C,N), CNSet, _).


% -----------------------------------------------------------------------------
%  Package masking
% -----------------------------------------------------------------------------

%! preference:apply_fallback_package_mask is det.
%
% Apply package masks from fallback defaults (fallback:package_mask/1).
% Only effective when config:portage_confdir/1 is not set (no real
% /etc/portage configured).

preference:apply_fallback_package_mask :-
  ( current_predicate(fallback:package_mask/1) ->
      forall(fallback:package_mask(Atom),
             preference:mask_catpkg_atom(Atom))
  ; true
  ).


%! preference:apply_profile_package_mask is det.
%
% Apply package masks from the Gentoo profile tree.  Supports incremental
% unmasking ('-' prefixed atoms remove masks set by parent profiles).

preference:apply_profile_package_mask :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_package_mask_atoms/2),
    catch(profile:profile_package_mask_atoms(ProfileRel, Atoms), _, fail) ->
      forall(member(Atom, Atoms),
             ( ( sub_atom(Atom, 0, 1, _, '-') ->
                   sub_atom(Atom, 1, _, 0, Atom1),
                   normalize_space(atom(Atom2), Atom1),
                   preference:unmask_profile_atom(Atom2)
               ; preference:mask_profile_atom(Atom)
               )))
  ; true
  ).


%! preference:mask_catpkg_atom(+Atom) is det.
%
% Mask all portage entries matching a simple cat/pkg atom.

preference:mask_catpkg_atom(Atom) :-
  atom(Atom),
  atomic_list_concat([C,N], '/', Atom),
  forall(cache:ordered_entry(portage, Id, C, N, _),
         assertz(preference:local_masked(portage://Id))).


%! preference:unmask_catpkg_atom(+Atom) is det.
%
% Unmask all portage entries matching a simple cat/pkg atom.

preference:unmask_catpkg_atom(Atom) :-
  atom(Atom),
  atomic_list_concat([C,N], '/', Atom),
  forall(cache:ordered_entry(portage, Id, C, N, _),
         retractall(preference:local_masked(portage://Id))).


%! preference:mask_profile_atom(+Atom) is det.
%
% Best-effort profile package.mask support.  Handles simple cat/pkg atoms
% (mask all versions) and versioned atoms parsed via eapi:qualified_target/1.

preference:mask_profile_atom(Atom) :-
  atom(Atom),
  ( atomic_list_concat([_C,_N], '/', Atom),
    \+ sub_atom(Atom, 0, 1, _, '>'),
    \+ sub_atom(Atom, 0, 1, _, '<'),
    \+ sub_atom(Atom, 0, 1, _, '='),
    \+ sub_atom(Atom, 0, 1, _, '~'),
    \+ sub_atom(Atom, _, 1, _, ':'),
    \+ sub_atom(Atom, _, 1, _, '['),
    \+ sub_atom(Atom, _, 1, _, '*')
  ) ->
    preference:mask_catpkg_atom(Atom)
  ; atom_codes(Atom, Codes),
    catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
    Q = qualified_target(Op, _Repo, C, N, Ver, Filters),
    nonvar(C), nonvar(N) ->
      ( Filters = [SlotReq,UseReq], UseReq == [] -> true ; SlotReq = [] ),
      forall(cache:ordered_entry(portage, Id, C, N, _),
             ( cache:ordered_entry(portage, Id, C, N, ProposedVersion),
               ( preference:version_match(Op, ProposedVersion, Ver),
                 preference:slot_req_match_(SlotReq, portage, Id) ->
                 assertz(preference:local_masked(portage://Id))
               ; true
               )))
  ; true.


%! preference:unmask_profile_atom(+Atom) is det.
%
% Undo masking for a profile package.mask atom (Portage-style '-cat/pkg' lines).

preference:unmask_profile_atom(Atom) :-
  atom(Atom),
  ( atomic_list_concat([_C,_N], '/', Atom),
    \+ sub_atom(Atom, 0, 1, _, '>'),
    \+ sub_atom(Atom, 0, 1, _, '<'),
    \+ sub_atom(Atom, 0, 1, _, '='),
    \+ sub_atom(Atom, 0, 1, _, '~'),
    \+ sub_atom(Atom, _, 1, _, ':'),
    \+ sub_atom(Atom, _, 1, _, '['),
    \+ sub_atom(Atom, _, 1, _, '*')
  ) ->
    preference:unmask_catpkg_atom(Atom)
  ; atom_codes(Atom, Codes),
    catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
    Q = qualified_target(Op, _Repo, C, N, Ver, Filters),
    nonvar(C), nonvar(N) ->
      ( Filters = [SlotReq,UseReq], UseReq == [] -> true ; SlotReq = [] ),
      forall(cache:ordered_entry(portage, Id, C, N, _),
             ( cache:ordered_entry(portage, Id, C, N, ProposedVersion),
               ( preference:version_match(Op, ProposedVersion, Ver),
                 preference:slot_req_match_(SlotReq, portage, Id) ->
                 retractall(preference:local_masked(portage://Id))
               ; true
               )))
  ; true.


%! preference:slot_req_match_(+SlotReq, +Repo, +Id) is semidet.
%
% Slot restriction matcher for profile package.mask atoms.

preference:slot_req_match_([], _Repo, _Id) :- !.

preference:slot_req_match_([slot(S0)], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S0)).

preference:slot_req_match_([slot(S0),subslot(Ss0)], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S0)),
  ( cache:entry_metadata(Repo, Id, slot, subslot(Ss))
  -> Ss == Ss0
  ; Ss0 == S0
  ).

preference:slot_req_match_([slot(S0),equal], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S0)).

preference:slot_req_match_([slot(S0),subslot(Ss0),equal], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S0)),
  ( cache:entry_metadata(Repo, Id, slot, subslot(Ss))
  -> Ss == Ss0
  ; Ss0 == S0
  ).

preference:slot_req_match_([any_same_slot], _Repo, _Id) :- !.

preference:slot_req_match_([any_different_slot], _Repo, _Id) :- !.

preference:slot_req_match_(_Other, _Repo, _Id) :- fail.


%! preference:version_match(+Op, +Proposed, +Req) is semidet.
%
% Match an ebuild version against a profile atom comparator.  Used by
% profile package.mask / package.unmask processing.  Avoids query:search/2
% because this runs at init time before goal-expansion.

preference:version_match(none, _Proposed, _Req) :- !.

preference:version_match(equal, Proposed, Req) :-
  Proposed == Req,
  !.

preference:version_match(tilde, Proposed, Req) :-
  Proposed = version(N,A,SR,SN,SRe,_,_),
  Req = version(N,A,SR,SN,SRe,_,_),
  !.

preference:version_match(wildcard, Proposed, version(_,_,_,_,_,_,Pattern)) :-
  !,
  Proposed = version(_,_,_,_,_,_,ProposedStr),
  query:wildcard_match(Pattern, ProposedStr).

preference:version_match(smaller, Proposed, Req) :-
  !,
  eapi:version_compare(<, Proposed, Req).

preference:version_match(greater, Proposed, Req) :-
  !,
  eapi:version_compare(>, Proposed, Req).

preference:version_match(smallerequal, Proposed, Req) :-
  !,
  ( eapi:version_compare(<, Proposed, Req)
  ; eapi:version_compare(=, Proposed, Req)
  ).

preference:version_match(greaterequal, Proposed, Req) :-
  !,
  ( eapi:version_compare(>, Proposed, Req)
  ; eapi:version_compare(=, Proposed, Req)
  ).

preference:version_match(notequal, Proposed, Req) :-
  Proposed \== Req,
  !.


% -----------------------------------------------------------------------------
%  License acceptance
% -----------------------------------------------------------------------------

%! preference:load_license_groups is det.
%
% Reads the profiles/license_groups file and asserts raw group definitions.
% Each group is stored as preference:local_license_group_raw(GroupName, Members)
% where Members is a list of atoms (license names or @GroupRef).

preference:load_license_groups :-
  retractall(preference:local_license_group_raw(_, _)),
  ( portage:get_location(PortageRoot) ->
    os:compose_path(PortageRoot, 'profiles/license_groups', LicGroupFile),
    ( exists_file(LicGroupFile) ->
      read_file_to_string(LicGroupFile, Content, []),
      split_string(Content, "\n", "\r", Lines),
      forall(member(Line, Lines),
             preference:parse_license_group_line_(Line))
    ; true
    )
  ; true
  ).


%! preference:parse_license_group_line_(+Line) is det.
%
% Parse a single line from the license_groups file.  Blank lines and
% '#'-prefixed comments are ignored.

preference:parse_license_group_line_(Line) :-
  normalize_space(string(Trimmed), Line),
  string_codes(Trimmed, Codes),
  ( Codes = [] -> true
  ; Codes = [0'#|_] -> true
  ; split_string(Trimmed, " \t", " \t", Tokens),
    ( Tokens = [GroupNameS | MemberSs],
      GroupNameS \== "" ->
      atom_string(GroupName, GroupNameS),
      maplist([S,A]>>atom_string(A, S), MemberSs, Members0),
      exclude(==(''), Members0, Members),
      assertz(preference:local_license_group_raw(GroupName, Members))
    ; true
    )
  ).


%! preference:expand_license_group(+GroupName, -Licenses:list) is det.
%
% Recursively expands a license group to its flat set of license atoms.
% @-prefixed members are resolved as sub-group references.

preference:expand_license_group(GroupName, Licenses) :-
  preference:expand_license_group_(GroupName, [], Licenses0),
  sort(Licenses0, Licenses).


%! preference:expand_license_group_(+GroupName, +Seen, -Licenses) is det.
%
% Recursive worker for expand_license_group/2.  Seen prevents cycles.

preference:expand_license_group_(GroupName, Seen, []) :-
  memberchk(GroupName, Seen), !.

preference:expand_license_group_(GroupName, Seen, Licenses) :-
  ( preference:license_group_raw(GroupName, Members) ->
    foldl(preference:expand_license_member_([GroupName|Seen]), Members, [], Licenses)
  ; Licenses = []
  ).


%! preference:expand_license_member_(+Seen, +Member, +Acc0, -Acc) is det.
%
% Expand a single license group member.  @-prefixed members recurse
% into sub-groups; plain atoms are collected directly.

preference:expand_license_member_(Seen, Member, Acc0, Acc) :-
  ( atom_concat('@', GroupRef, Member) ->
    preference:expand_license_group_(GroupRef, Seen, Expanded),
    append(Acc0, Expanded, Acc)
  ; Acc = [Member|Acc0]
  ).

%! preference:init_accept_license is det.
%
% Parses the ACCEPT_LICENSE string and builds the accepted/denied license sets.
% Supports tokens: * (all), -* (none), @GROUP, -@GROUP, LICENSE, -LICENSE.
% Semantics are incremental left-to-right (like Portage).

preference:init_accept_license :-
  retractall(preference:local_accept_license_wildcard),
  retractall(preference:local_accepted_license(_)),
  retractall(preference:local_denied_license(_)),
  ( preference:getenv('ACCEPT_LICENSE', Atom), Atom \== '' ->
    split_string(Atom, " ", " \t", TokenSs),
    maplist([S,A]>>atom_string(A, S), TokenSs, Tokens0),
    exclude(==(''), Tokens0, Tokens),
    forall(member(T, Tokens),
           preference:apply_accept_license_token_(T))
  ; true
  ).


%! preference:apply_accept_license_token_(+Token) is det.
%
% Apply a single ACCEPT_LICENSE token with incremental semantics.

preference:apply_accept_license_token_('*') :- !,
  retractall(preference:local_denied_license(_)),
  ( preference:accept_license_wildcard -> true
  ; assertz(preference:local_accept_license_wildcard)
  ).

preference:apply_accept_license_token_('-*') :- !,
  retractall(preference:local_accept_license_wildcard),
  retractall(preference:local_accepted_license(_)),
  retractall(preference:local_denied_license(_)).

preference:apply_accept_license_token_(Token) :-
  atom_concat('-@', GroupRef, Token), !,
  preference:expand_license_group(GroupRef, Lics),
  forall(member(L, Lics),
         ( ( preference:accept_license_wildcard ->
               ( preference:denied_license(L) -> true
               ; assertz(preference:local_denied_license(L))
               )
           ; retractall(preference:local_accepted_license(L))
           )
         )).

preference:apply_accept_license_token_(Token) :-
  atom_concat('@', GroupRef, Token), !,
  preference:expand_license_group(GroupRef, Lics),
  forall(member(L, Lics),
         ( ( preference:accept_license_wildcard ->
               retractall(preference:local_denied_license(L))
           ; ( preference:accepted_license(L) -> true
             ; assertz(preference:local_accepted_license(L))
             )
           )
         )).

preference:apply_accept_license_token_(Token) :-
  atom_concat('-', Lic, Token),
  Lic \== '', !,
  ( preference:accept_license_wildcard ->
    ( preference:denied_license(Lic) -> true
    ; assertz(preference:local_denied_license(Lic))
    )
  ; retractall(preference:local_accepted_license(Lic))
  ).

preference:apply_accept_license_token_(Lic) :-
  ( preference:accept_license_wildcard ->
    retractall(preference:local_denied_license(Lic))
  ; ( preference:accepted_license(Lic) -> true
    ; assertz(preference:local_accepted_license(Lic))
    )
  ).


%! preference:license_accepted(+License:atom) is semidet.
%
% True if License is accepted by the current ACCEPT_LICENSE configuration.

preference:license_accepted(License) :-
  ( preference:accept_license_wildcard ->
    \+ preference:denied_license(License)
  ; preference:accepted_license(License)
  ).


% -----------------------------------------------------------------------------
%  System packages, sets, and world
% -----------------------------------------------------------------------------

%! preference:system_pkg(+Category, +Name) is semidet.
%
% Packages belonging to the @system set as defined by the profile
% `packages` files.  Dynamically asserted during profile loading from
% profile:system_packages/2.


%! preference:init_system_pkgs is det.
%
% Load @system packages from the profile chain and assert them as
% preference:system_pkg/2 facts.  Called during preference:init.

preference:init_system_pkgs :-
  retractall(preference:system_pkg(_, _)),
  ( preference:use_cached_profile ->
      true
  ; current_predicate(config:gentoo_profile/1),
    config:gentoo_profile(ProfileRel) ->
      catch(( profile:system_packages(ProfileRel, Pkgs),
              forall(member(Cat-Name, Pkgs),
                     assertz(preference:system_pkg(Cat, Name)))
            ), _, true)
  ; true
  ).


%! preference:init_sets is det.
%
% Load named set files from config:set_dir/1.  Each file whose name
% does not start with '.' becomes a preference:local_set('@Name', Entries)
% fact.  The 'world' subdirectory is excluded (handled separately).

preference:init_sets :-
  retractall(preference:local_set(_, _)),
  ( current_predicate(config:set_dir/1),
    config:set_dir(Dir),
    exists_directory(Dir) ->
      directory_files(Dir, Files0),
      exclude(preference:set_skip_entry_, Files0, Files),
      forall(member(F, Files),
             catch(preference:load_set_file_(Dir, F), _, true))
  ; true
  ).


%! preference:set_skip_entry_(+Name) is semidet.
%
% True if Name should be skipped when scanning the sets directory.

preference:set_skip_entry_(Name) :-
  ( sub_atom(Name, 0, 1, _, '.')
  ; Name == world
  ).


%! preference:load_set_file_(+Dir, +Name) is det.
%
% Read a single set file and assert preference:local_set/2.

preference:load_set_file_(Dir, Name) :-
  os:compose_path(Dir, Name, File),
  ( exists_directory(File) -> true
  ; exists_file(File) ->
      read_file_to_string(File, Content, []),
      split_string(Content, "\n", "\r\n", Lines0),
      exclude(=(""), Lines0, Lines),
      maplist([S,A]>>atom_string(A, S), Lines, Entries),
      atom_concat('@', Name, SetName),
      assertz(preference:local_set(SetName, Entries))
  ; true
  ).


%! preference:init_world_entries is det.
%
% Snapshot the file-backed world set into preference:world_entry/1 facts.
% These are transferred to the server in client-server mode so that
% eapi:substitute_sets/2 can resolve @world on the server side.

preference:init_world_entries :-
  retractall(preference:local_world_entry(_)),
  ( current_predicate(world:entry/1) ->
      forall(world::entry(E),
             assertz(preference:local_world_entry(E)))
  ; true
  ).


% -----------------------------------------------------------------------------
%  Configuration status
% -----------------------------------------------------------------------------

%! preference:status is det.
%
% Display which configuration sources are currently active.

preference:status :-
  format('~n  Configuration sources:~n'),
  ( current_predicate(config:portage_confdir/1),
    config:portage_confdir(Dir) ->
      format('    /etc/portage:   ~w~n', [Dir])
  ; format('    /etc/portage:   not configured (using fallback defaults)~n')
  ),
  ( current_predicate(config:gentoo_profile/1),
    config:gentoo_profile(P) ->
      format('    Profile:        ~w~n', [P])
  ; format('    Profile:        not configured~n')
  ),
  ( preference:use_cached_profile ->
      format('    Profile cache:  active (Knowledge/profile.qlf)~n')
  ; format('    Profile cache:  not used (live parsing)~n')
  ),
  aggregate_all(count, preference:global_use(_), UseCount),
  aggregate_all(count, preference:masked(_), MaskCount),
  aggregate_all(count, preference:userconfig_use(_,_,_,_), PkgUseCount),
  format('    Global USE:     ~d flags~n', [UseCount]),
  format('    Package masks:  ~d entries~n', [MaskCount]),
  format('    Package USE:    ~d overrides~n', [PkgUseCount]),
  nl.