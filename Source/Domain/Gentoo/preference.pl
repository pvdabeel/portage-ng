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

Materialized preference state is written to `Knowledge/preference.qlf` via
`preference:cache_save/0` and reloaded by `preference:cache_try_load/0`
(controlled by `config:preference_cache/2`).
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
%    Stored as local_masked(Id, Repo) — entry id first so first-argument
%    indexing applies on the hot "is this entry masked" check.  (A plain
%    local_masked(Repo://Id) representation indexes only on the '://'
%    functor and degrades to a linear scan.)

:- dynamic preference:local_masked/2.

% -- Global USE / keywords / flags --

:- dynamic preference:local_use/1.
:- dynamic preference:local_env_use/1.
:- dynamic preference:local_accept_keywords/1.
:- dynamic preference:local_flag/1.
:- thread_local preference:scoped_flag/1.

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

% -- Stable USE (use.stable*, package.use.stable*) --
%    Applied only when the ebuild KEYWORDS list the host arch as stable.
%    use.stable is an explicit enable/disable (minus(Flag) stays negative).
%    use.stable.mask / use.stable.force are incremental sets, like use.mask.

:- dynamic preference:local_profile_stable_masked_use_flag/1.
:- dynamic preference:local_profile_stable_forced_use_flag/1.
:- dynamic preference:local_profile_stable_use/1.            % Flag | minus(Flag)
:- dynamic preference:local_profile_stable_use_soft/3.      % Spec, Flag, State
:- dynamic preference:local_profile_stable_use_masked/2.    % Spec, Flag
:- dynamic preference:local_profile_stable_use_forced/2.    % Spec, Flag
:- dynamic preference:local_profile_stable_soft_flag/1.
:- dynamic preference:local_profile_stable_pkg_masked/1.
:- dynamic preference:local_profile_stable_pkg_forced/1.

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
%
% When a valid `Knowledge/preference.qlf` stamp matches current inputs,
% reloads the materialized preference state instead of rebuilding it.

preference:init :-
  ( preference:cache_try_load ->
      !
  ; preference:init_fresh,
    preference:cache_save
  ).


%! preference:init_reset_indexes is det.
%
% Invalidate preference AVL index caches.  Called at the start of a fresh
% init and after loading `Knowledge/preference.qlf`.
%
% The indexes are lazily rebuilt by their lookup predicates on the first
% `nb_current/2` miss, so invalidation must delete the globals.  Writing an
% empty AVL instead would make every later lookup succeed against an empty
% index and never rebuild.

preference:init_reset_indexes :-
  nb_delete(pref_userconfig_use_soft_flags),
  nb_delete(pref_userconfig_use_soft_cns),
  nb_delete(pref_profile_use_soft_flags),
  nb_delete(pref_profile_use_soft_cns),
  nb_delete(pref_profile_forced_cns),
  nb_delete(pref_profile_masked_cns).


%! preference:init_fresh is det.
%
% Full preference rebuild from profile, userconfig, environment, and sets.

preference:init_fresh :-

  retractall(preference:local_masked(_,_)),
  retractall(preference:local_userconfig_use(_,_,_,_)),
  retractall(preference:local_profile_masked_use_flag(_)),
  retractall(preference:local_profile_forced_use_flag(_)),
  retractall(preference:local_profile_use_masked(_,_)),
  retractall(preference:local_profile_use_forced(_,_)),
  preference:clear_profile_stable_use,
  retractall(preference:local_profile_use_soft(_,_,_)),
  retractall(preference:local_userconfig_use_versioned(_,_,_)),
  retractall(preference:local_license_group_raw(_,_)),
  retractall(preference:local_accept_license_wildcard),
  retractall(preference:local_accepted_license(_)),
  retractall(preference:local_denied_license(_)),
  retractall(preference:local_use(_)),
  retractall(preference:local_env_use(_)),
  retractall(preference:local_accept_keywords(_)),
  retractall(preference:local_flag(_)),
  retractall(preference:local_set(_,_)),
  retractall(preference:local_world_entry(_)),
  retractall(preference:system_pkg(_,_)),
  preference:init_reset_indexes,

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
  catch(preference:apply_profile_stable_use, _, true),
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
  current_predicate(interface:get_mode/1),
  catch(interface:get_mode(Mode), _, fail),
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
%
% Step 3 is skipped when `config:portage_confdir/1` is configured: an
% explicit confdir means the user has a real /etc/portage that must be
% authoritative, even when it leaves a variable unset (e.g. an empty USE=
% in make.conf is a deliberate "no global USE" signal, not a request to
% inherit the developer's local hardcoded defaults). Consulting the
% fallback in that case silently injects flags like `alsa cairo dbus gif
% gpm harfbuzz jpeg png sqlite tiff` from the dev machine, which causes
% systematically larger plans than emerge produces and triggers
% downstream build failures for packages that the user never asked for.

preference:getenv(Name, Value) :-
  ( interface:getenv(Name, Value) ->
      true
  ; current_predicate(userconfig:env/2),
    userconfig:env(Name, Value),
    Value \== '' ->
      true
  ; \+ ( current_predicate(config:portage_confdir/1),
         config:portage_confdir(_) ),
    current_predicate(fallback:env/2),
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
%  Pengines dispatch
% -----------------------------------------------------------------------------

%! preference:pengine_module(-Module) is semidet.
%
% Unifies Module with the Pengines sandbox module when executing inside a
% pengine (client-server mode); fails in standalone mode.  The result of
% pengine_self/1 is memoized in a per-thread global variable, so the
% preference accessors — called millions of times per proof via
% effective_use_* — pay a single cheap nb_current/2 lookup instead of a
% pengine_self/1 dispatch test on every call.  Memoization is safe because
% a thread is either a pengine thread or a regular thread for its entire
% lifetime, and per-thread global variables die with the thread.

preference:pengine_module(M) :-
  ( nb_current(pref_pengine_module, M0) ->
      M0 \== none,
      M = M0
  ; pengine_self(M1) ->
      nb_setval(pref_pengine_module, M1),
      M = M1
  ; nb_setval(pref_pengine_module, none),
    fail
  ).


% -----------------------------------------------------------------------------
%  Query predicates
% -----------------------------------------------------------------------------

%! preference:global_use(?Use) is nondet.
%
% Returns active USE flag settings.  In standalone mode, the flags are
% asserted by preference:init/0.  In client-server mode, they are
% injected as thread-local clauses by the Pengines sandbox.

preference:global_use(X) :-
  ( preference:pengine_module(M) ->
      M:local_use(X)
  ; preference:local_use(X)
  ).


%! preference:global_use(?Use, +Source) is nondet.
%
% Returns USE flag settings filtered by Source:
%   - `env`   : only flags set via the environment
%   - `other` : all active flags (delegates to preference:global_use/1)

preference:global_use(X,env) :-
  ( preference:pengine_module(M) ->
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
  ( preference:pengine_module(M) ->
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
  userconfig:package_keyword(Spec, RawKW),
  preference:keyword_spec_matches_cn(Spec, C, N),
  preference:raw_keyword_matches_(RawKW, K),
  !.


%! preference:keyword_spec_matches_cn(+Spec, +C, +N) is semidet.
%
% True when a package.accept_keywords atom (optionally `::repo`)
% covers category C / name N. Supports `cat/pkg`, `cat/*`, and `*/*`.

preference:keyword_spec_matches_cn(Spec, C, N) :-
  preference:strip_repo_suffix(Spec, Atom),
  ( Atom == '*/*'
  ; atomic_list_concat([C, N], '/', Atom)
  ; atomic_list_concat([C, '*'], '/', Atom)
  ),
  !.


%! preference:strip_repo_suffix(+Spec, -Atom) is det.
%
% Strips a trailing `::repo` from a package.accept_keywords atom.

preference:strip_repo_suffix(Spec, Atom) :-
  sub_atom(Spec, B, 2, _, '::'),
  !,
  sub_atom(Spec, 0, B, _, Atom).
preference:strip_repo_suffix(Spec, Spec).


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
% preference:with_local_flag/2 asserts a per-thread scoped_flag/1 so
% parallel `--graph` writers cannot leak `--fetchonly` into a sibling
% merge print.

preference:flag(Flag) :-
  ( preference:scoped_flag(Flag)
  ; preference:pengine_module(M)
  -> M:local_flag(Flag)
  ; preference:local_flag(Flag)
  ).


%! preference:with_local_flag(+Flag, :Goal) is det.
%
% Asserts a thread-local scoped_flag(Flag) for the duration of Goal.
% Used by graph writers and tests that print or execute a :run plan
% under `--fetchonly` without going through interface:process_flags/0.

:- meta_predicate preference:with_local_flag(+, 0).

preference:with_local_flag(Flag, Goal) :-
  setup_call_cleanup(
    asserta(preference:scoped_flag(Flag), Ref),
    Goal,
    erase(Ref)).


%! preference:fetchonly_skips_action(+Action) is semidet.
%
% True when `--fetchonly` / `--fetch-all-uri` is active and Action is a
% merge-phase action that must not be printed or executed. Downloads and
% configuration pre-actions (unmask / keyword / USE / license) remain.

preference:fetchonly_skips_action(Action) :-
  preference:flag(fetchonly),
  preference:fetchonly_merge_action(Action).


%! preference:fetchonly_merge_action(+Action) is semidet.
%
% Merge-phase actions omitted from a fetchonly print or execute pass.

preference:fetchonly_merge_action(run).
preference:fetchonly_merge_action(install).
preference:fetchonly_merge_action(reinstall).
preference:fetchonly_merge_action(update).
preference:fetchonly_merge_action(downgrade).
preference:fetchonly_merge_action(upgrade).


%! preference:masked(?Entry) is nondet.
%
% Returns masked entries (Repo://Id).  In standalone mode, the masks are
% asserted by preference:init/0.  In client-server mode, they are
% injected as thread-local clauses by the Pengines sandbox.  Storage is
% keyed on the entry id (local_masked/2) so the bound check is an
% indexed lookup rather than a scan over all mask facts.

preference:masked(Repo://Id) :-
  ( preference:pengine_module(M) ->
      M:local_masked(Id, Repo)
  ; preference:local_masked(Id, Repo)
  ).


%! preference:userconfig_use(?C, ?N, ?Use, ?State) is nondet.
%
% Per-package USE overrides from /etc/portage/package.use.
% Dispatches to the Pengine module in client-server mode.

preference:userconfig_use(C, N, Use, State) :-
  ( preference:pengine_module(M) ->
      M:local_userconfig_use(C, N, Use, State)
  ; preference:local_userconfig_use(C, N, Use, State)
  ).


%! preference:userconfig_use_versioned(?Spec, ?Use, ?State) is nondet.
%
% Versioned per-package USE overrides.
% Dispatches to the Pengine module in client-server mode.

preference:userconfig_use_versioned(Spec, Use, State) :-
  ( preference:pengine_module(M) ->
      M:local_userconfig_use_versioned(Spec, Use, State)
  ; preference:local_userconfig_use_versioned(Spec, Use, State)
  ).


%! preference:profile_use_soft(?Spec, ?Use, ?State) is nondet.
%
% Soft per-package USE from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_soft(Spec, Use, State) :-
  ( preference:pengine_module(M) ->
      M:local_profile_use_soft(Spec, Use, State)
  ; preference:local_profile_use_soft(Spec, Use, State)
  ).


%! preference:profile_use_masked(?Spec, ?Use) is nondet.
%
% Per-package USE masks from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_masked(Spec, Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_use_masked(Spec, Use)
  ; preference:local_profile_use_masked(Spec, Use)
  ).


%! preference:profile_use_forced(?Spec, ?Use) is nondet.
%
% Per-package USE forces from the profile tree.
% Dispatches to the Pengine module in client-server mode.

preference:profile_use_forced(Spec, Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_use_forced(Spec, Use)
  ; preference:local_profile_use_forced(Spec, Use)
  ).


%! preference:profile_stable_use(?Flag) is nondet.
%
% Global use.stable token: a bare flag is enabled, minus(Flag) is disabled.

preference:profile_stable_use(Flag) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_use(Flag)
  ; preference:local_profile_stable_use(Flag)
  ).


%! preference:profile_stable_masked_use_flag(?Use) is nondet.
%
% Global use.stable.mask flag.

preference:profile_stable_masked_use_flag(Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_masked_use_flag(Use)
  ; preference:local_profile_stable_masked_use_flag(Use)
  ).


%! preference:profile_stable_forced_use_flag(?Use) is nondet.
%
% Global use.stable.force flag.

preference:profile_stable_forced_use_flag(Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_forced_use_flag(Use)
  ; preference:local_profile_stable_forced_use_flag(Use)
  ).


%! preference:profile_stable_use_soft(?Spec, ?Use, ?State) is nondet.
%
% package.use.stable fact. Last-wins is applied by the matcher.

preference:profile_stable_use_soft(Spec, Use, State) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_use_soft(Spec, Use, State)
  ; preference:local_profile_stable_use_soft(Spec, Use, State)
  ).


%! preference:profile_stable_use_masked(?Spec, ?Use) is nondet.
%
% package.use.stable.mask fact.

preference:profile_stable_use_masked(Spec, Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_use_masked(Spec, Use)
  ; preference:local_profile_stable_use_masked(Spec, Use)
  ).


%! preference:profile_stable_use_forced(?Spec, ?Use) is nondet.
%
% package.use.stable.force fact.

preference:profile_stable_use_forced(Spec, Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_use_forced(Spec, Use)
  ; preference:local_profile_stable_use_forced(Spec, Use)
  ).


%! preference:profile_stable_soft_flag(?Use) is semidet.
%
% True when Use appears in package.use.stable.

preference:profile_stable_soft_flag(Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_soft_flag(Use)
  ; preference:local_profile_stable_soft_flag(Use)
  ).


%! preference:profile_stable_pkg_masked(?Use) is semidet.
%
% True when Use appears in package.use.stable.mask.

preference:profile_stable_pkg_masked(Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_pkg_masked(Use)
  ; preference:local_profile_stable_pkg_masked(Use)
  ).


%! preference:profile_stable_pkg_forced(?Use) is semidet.
%
% True when Use appears in package.use.stable.force.

preference:profile_stable_pkg_forced(Use) :-
  ( preference:pengine_module(M) ->
      M:local_profile_stable_pkg_forced(Use)
  ; preference:local_profile_stable_pkg_forced(Use)
  ).


%! preference:profile_masked_use_flag(?Use) is nondet.
%
% Global USE flags masked by the profile.
% Dispatches to the Pengine module in client-server mode.

preference:profile_masked_use_flag(U) :-
  ( preference:pengine_module(M) ->
      M:local_profile_masked_use_flag(U)
  ; preference:local_profile_masked_use_flag(U)
  ).


%! preference:profile_forced_use_flag(?Use) is nondet.
%
% Global USE flags forced by the profile.
% Dispatches to the Pengine module in client-server mode.

preference:profile_forced_use_flag(U) :-
  ( preference:pengine_module(M) ->
      M:local_profile_forced_use_flag(U)
  ; preference:local_profile_forced_use_flag(U)
  ).


%! preference:set(?Name, ?List) is nondet.
%
% Named package sets.
% Dispatches to the Pengine module in client-server mode.

preference:set(Name, List) :-
  ( preference:pengine_module(M) ->
      M:local_set(Name, List)
  ; preference:local_set(Name, List)
  ).


%! preference:world_entry(?Entry) is nondet.
%
% World set entries.
% Dispatches to the Pengine module in client-server mode.

preference:world_entry(E) :-
  ( preference:pengine_module(M) ->
      M:local_world_entry(E)
  ; preference:local_world_entry(E)
  ).


%! preference:license_group_raw(?Name, ?Members) is nondet.
%
% Raw license group definitions from the profile.
% Dispatches to the Pengine module in client-server mode.

preference:license_group_raw(Name, Members) :-
  ( preference:pengine_module(M) ->
      M:local_license_group_raw(Name, Members)
  ; preference:local_license_group_raw(Name, Members)
  ).


%! preference:accept_license_wildcard is semidet.
%
% True when ACCEPT_LICENSE contains '*'.
% Dispatches to the Pengine module in client-server mode. The fact is an
% optional 0-arity instance (client:remote_predicate_instance/1): when the
% client has no wildcard, nothing is shipped and the pengine module has no
% definition at all, so an existence error here simply means "not set".

preference:accept_license_wildcard :-
  ( preference:pengine_module(M) ->
      catch(M:local_accept_license_wildcard,
            error(existence_error(procedure, _), _),
            fail)
  ; preference:local_accept_license_wildcard
  ).


%! preference:accepted_license(?License) is nondet.
%
% Individual accepted license atoms.
% Dispatches to the Pengine module in client-server mode.

preference:accepted_license(L) :-
  ( preference:pengine_module(M) ->
      M:local_accepted_license(L)
  ; preference:local_accepted_license(L)
  ).


%! preference:denied_license(?License) is nondet.
%
% Individual denied license atoms (for '* -X' patterns).
% Dispatches to the Pengine module in client-server mode.

preference:denied_license(L) :-
  ( preference:pengine_module(M) ->
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
% NOTE: This affects how `resolving.pl` enumerates dependency candidates.

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
  eapi:normalize_slot_value_(S0, S).


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
  ; preference:stable_package_masked(Repo, Id, C, N, ProposedVersion, Use) ->
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
  ; preference:stable_package_forced(Repo, Id, C, N, ProposedVersion, Use) ->
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
      reader:config_lines(File, Lines),
      forall(member(L2, Lines),
             ( split_string(L2, " ", "\t ", Ws0),
               exclude(=(""), Ws0, Ws),
               ( Ws = [AtomS|FlagSs],
                 atom_string(AtomA, AtomS),
                 preference:profile_package_use_spec(AtomA, Spec) ->
                   forall(member(FlagS0, FlagSs),
                          preference:apply_profile_package_use_flag(Kind, Spec, FlagS0))
               ; true
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

preference:apply_profile_package_use_op(add, stable_masked, Spec, Flag) :-
  ( preference:profile_stable_use_masked(Spec, Flag) ->
      true
  ; assertz(preference:local_profile_stable_use_masked(Spec, Flag)),
    preference:note_stable_pkg_flag(masked, Flag)
  ),
  !.

preference:apply_profile_package_use_op(del, stable_masked, Spec, Flag) :-
  ( preference:profile_package_use_cp_from_spec_(Spec, C, N) ->
      retractall(preference:local_profile_stable_use_masked(simple(C, N, _), Flag)),
      retractall(preference:local_profile_stable_use_masked(versioned(_, C, N, _, _), Flag))
  ; retractall(preference:local_profile_stable_use_masked(Spec, Flag))
  ),
  preference:forget_stable_pkg_flag(masked, Flag),
  !.

preference:apply_profile_package_use_op(add, stable_forced, Spec, Flag) :-
  ( preference:profile_stable_use_forced(Spec, Flag) ->
      true
  ; assertz(preference:local_profile_stable_use_forced(Spec, Flag)),
    preference:note_stable_pkg_flag(forced, Flag)
  ),
  !.

preference:apply_profile_package_use_op(del, stable_forced, Spec, Flag) :-
  ( preference:profile_package_use_cp_from_spec_(Spec, C, N) ->
      retractall(preference:local_profile_stable_use_forced(simple(C, N, _), Flag)),
      retractall(preference:local_profile_stable_use_forced(versioned(_, C, N, _, _), Flag))
  ; retractall(preference:local_profile_stable_use_forced(Spec, Flag))
  ),
  preference:forget_stable_pkg_flag(forced, Flag),
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
      reader:config_lines(File, Lines),
      forall(member(L2, Lines),
             ( split_string(L2, " ", "\t ", Ws0),
               exclude(=(""), Ws0, Ws),
               ( Ws = [AtomS|FlagSs],
                 atom_string(AtomA, AtomS),
                 preference:profile_package_use_spec(AtomA, Spec) ->
                   forall(member(FlagS0, FlagSs),
                          preference:apply_profile_use_soft_flag(Spec, FlagS0))
               ; true
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


%! preference:clear_profile_stable_use is det.
%
% Drop every stable-USE fact so a live profile walk can replace a cache
% snapshot without leaving both copies asserted.

preference:clear_profile_stable_use :-
  retractall(preference:local_profile_stable_masked_use_flag(_)),
  retractall(preference:local_profile_stable_forced_use_flag(_)),
  retractall(preference:local_profile_stable_use(_)),
  retractall(preference:local_profile_stable_use_soft(_, _, _)),
  retractall(preference:local_profile_stable_use_masked(_, _)),
  retractall(preference:local_profile_stable_use_forced(_, _)),
  retractall(preference:local_profile_stable_soft_flag(_)),
  retractall(preference:local_profile_stable_pkg_masked(_)),
  retractall(preference:local_profile_stable_pkg_forced(_)).


%! preference:apply_profile_stable_use is det.
%
% Load use.stable, use.stable.mask, use.stable.force, package.use.stable,
% package.use.stable.mask and package.use.stable.force from the profile
% tree. When the tree is readable it replaces any facts just applied from
% the profile cache, so a stale cache does not hide the files on disk.
% use.stable / package.use.stable require profile EAPI 9; the mask and
% force files require profile EAPI 5.

preference:apply_profile_stable_use :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail),
    Dirs \== [],
    foldl(preference:dir_stable_globals, Dirs, []-[]-[]-[],
          Masked-Forced-Enabled-Disabled) ->
      preference:clear_profile_stable_use,
      forall(member(Flag, Masked),
             assertz(preference:local_profile_stable_masked_use_flag(Flag))),
      forall(member(Flag, Forced),
             assertz(preference:local_profile_stable_forced_use_flag(Flag))),
      forall(member(Flag, Enabled),
             assertz(preference:local_profile_stable_use(Flag))),
      forall(member(Flag, Disabled),
             assertz(preference:local_profile_stable_use(minus(Flag)))),
      forall(member(Dir, Dirs),
             catch(preference:apply_stable_package_dir(Dir), _, true))
  ; true
  ).


%! preference:dir_stable_globals(+Dir, +Acc0, -Acc) is det.
%
% Fold one profile directory into Masked-Forced-Enabled-Disabled ordsets.
% A `-flag` in use.stable is an explicit disable, so it stays in Disabled
% rather than merely leaving the enabled set.

preference:dir_stable_globals(Dir, M0-F0-E0-D0, M-F-E-D) :-
  profile:dir_eapi(Dir, Eapi),
  ( profile:eapi_at_least(Eapi, 5) ->
      profile:parse_use_op_file(Dir, 'use.stable.mask', MaskOps),
      profile:apply_set_ops(MaskOps, M0, M),
      profile:parse_use_op_file(Dir, 'use.stable.force', ForceOps),
      profile:apply_set_ops(ForceOps, F0, F)
  ; M = M0,
    F = F0
  ),
  ( profile:eapi_at_least(Eapi, 9) ->
      profile:parse_use_op_file(Dir, 'use.stable', UseOps),
      preference:apply_stable_use_ops(UseOps, E0, D0, E, D)
  ; E = E0,
    D = D0
  ).


%! preference:apply_stable_use_ops(+Ops, +Enabled0, +Disabled0, -Enabled, -Disabled) is det.
%
% Incremental use.stable: add enables the flag, del disables it. The two
% sets stay disjoint.

preference:apply_stable_use_ops([], Enabled, Disabled, Enabled, Disabled).
preference:apply_stable_use_ops([op(add, Flag)|Ops], E0, D0, E, D) :-
  ord_del_element(D0, Flag, D1),
  ord_add_element(E0, Flag, E1),
  preference:apply_stable_use_ops(Ops, E1, D1, E, D).
preference:apply_stable_use_ops([op(del, Flag)|Ops], E0, D0, E, D) :-
  ord_del_element(E0, Flag, E1),
  ord_add_element(D0, Flag, D1),
  preference:apply_stable_use_ops(Ops, E1, D1, E, D).


%! preference:apply_stable_package_dir(+Dir) is det.
%
% package.use.stable.mask / force from EAPI 5 directories, and
% package.use.stable from EAPI 9 directories.

preference:apply_stable_package_dir(Dir) :-
  profile:dir_eapi(Dir, Eapi),
  ( profile:eapi_at_least(Eapi, 5) ->
      preference:apply_profile_package_use_file(Dir, 'package.use.stable.mask', stable_masked),
      preference:apply_profile_package_use_file(Dir, 'package.use.stable.force', stable_forced)
  ; true
  ),
  ( profile:eapi_at_least(Eapi, 9) ->
      preference:apply_stable_package_use_dir(Dir)
  ; true
  ).


%! preference:apply_stable_package_use_dir(+Dir) is det.
%
% Assert package.use.stable lines. Last-wins is resolved at lookup time.

preference:apply_stable_package_use_dir(Dir) :-
  os:compose_path(Dir, 'package.use.stable', File),
  ( exists_file(File) ->
      reader:config_lines(File, Lines),
      forall(member(Line, Lines),
             ( split_string(Line, " ", "\t ", Ws0),
               exclude(=(""), Ws0, Ws),
               ( Ws = [AtomS|FlagSs],
                 atom_string(AtomA, AtomS),
                 preference:profile_package_use_spec(AtomA, Spec) ->
                   forall(member(FlagS0, FlagSs),
                          preference:apply_stable_use_soft_flag(Spec, FlagS0))
               ; true
               )
             ))
  ; true
  ).


%! preference:apply_stable_use_soft_flag(+Spec, +FlagS0) is det.
%
% Parse one package.use.stable token and record its last state.

preference:apply_stable_use_soft_flag(Spec, FlagS0) :-
  normalize_space(string(FlagS), FlagS0),
  ( FlagS == "" ->
      true
  ; sub_string(FlagS, 0, 1, _, "-") ->
      sub_string(FlagS, 1, _, 0, Name0),
      normalize_space(string(Name), Name0),
      Name \== "",
      atom_string(Flag, Name),
      preference:assert_stable_use_soft(Spec, Flag, negative)
  ; atom_string(Flag, FlagS),
    preference:assert_stable_use_soft(Spec, Flag, positive)
  ),
  !.


%! preference:assert_stable_use_soft(+Spec, +Flag, +State) is det.
%
% Replace any previous state of Flag on Spec and keep the flag index.

preference:assert_stable_use_soft(Spec, Flag, State) :-
  retractall(preference:local_profile_stable_use_soft(Spec, Flag, _)),
  assertz(preference:local_profile_stable_use_soft(Spec, Flag, State)),
  ( preference:local_profile_stable_soft_flag(Flag) ->
      true
  ; assertz(preference:local_profile_stable_soft_flag(Flag))
  ).


%! preference:note_stable_pkg_flag(+Kind, +Flag) is det.
%
% Remember that Flag occurs in a stable package mask or force file.

preference:note_stable_pkg_flag(masked, Flag) :-
  ( preference:local_profile_stable_pkg_masked(Flag) -> true
  ; assertz(preference:local_profile_stable_pkg_masked(Flag))
  ).
preference:note_stable_pkg_flag(forced, Flag) :-
  ( preference:local_profile_stable_pkg_forced(Flag) -> true
  ; assertz(preference:local_profile_stable_pkg_forced(Flag))
  ).


%! preference:forget_stable_pkg_flag(+Kind, +Flag) is det.
%
% Drop the flag index when no spec still carries Flag.

preference:forget_stable_pkg_flag(masked, Flag) :-
  ( preference:local_profile_stable_use_masked(_, Flag) ->
      true
  ; retractall(preference:local_profile_stable_pkg_masked(Flag))
  ).
preference:forget_stable_pkg_flag(forced, Flag) :-
  ( preference:local_profile_stable_use_forced(_, Flag) ->
      true
  ; retractall(preference:local_profile_stable_pkg_forced(Flag))
  ).


%! preference:entry_has_stable_keyword(+Repo://Id) is semidet.
%
% True when Id's KEYWORDS contain the host arch as a stable keyword.
% Accepting ~arch does not make the package stable.

preference:entry_has_stable_keyword(Repo://Id) :-
  userconfig:current_arch(Arch),
  cache:entry_metadata(Repo, Id, keywords, stable(Arch)),
  !.


%! preference:stable_globally_masked(+Repo://Id, +Use) is semidet.
%
% use.stable.mask hit for a stable-keyworded entry.

preference:stable_globally_masked(Repo://Id, Use) :-
  preference:entry_has_stable_keyword(Repo://Id),
  preference:profile_stable_masked_use_flag(Use),
  !.


%! preference:stable_globally_forced(+Repo://Id, +Use) is semidet.
%
% use.stable.force hit. A global or stable mask still wins.

preference:stable_globally_forced(Repo://Id, Use) :-
  preference:entry_has_stable_keyword(Repo://Id),
  preference:profile_stable_forced_use_flag(Use),
  \+ preference:profile_masked_use_flag(Use),
  \+ preference:profile_stable_masked_use_flag(Use),
  !.


%! preference:stable_global_use(+Repo://Id, +Use, -State) is semidet.
%
% use.stable enable or disable for a stable-keyworded entry.

preference:stable_global_use(Repo://Id, Use, State) :-
  preference:entry_has_stable_keyword(Repo://Id),
  ( preference:profile_stable_use(Use) ->
      State = positive
  ; preference:profile_stable_use(minus(Use)) ->
      State = negative
  ),
  !.


%! preference:profile_stable_use_soft_match(+Entry, +Use, -State) is semidet.
%
% Last-wins package.use.stable state. Fails unless the entry is stable
% on the host arch.

preference:profile_stable_use_soft_match(Repo://Id, Use, State) :-
  preference:profile_stable_soft_flag(Use),
  preference:entry_has_stable_keyword(Repo://Id),
  cache:ordered_entry(Repo, Id, C, N, ProposedVersion),
  findall(State0,
          ( preference:profile_stable_use_soft(Spec, Use, State0),
            preference:profile_package_use_spec_matches_entry_(Spec, Repo, Id, C, N, ProposedVersion)
          ),
          States),
  States \== [],
  last(States, State),
  !.


%! preference:stable_package_masked(+Repo, +Id, +C, +N, +Version, +Use) is semidet.
%
% package.use.stable.mask hit for a stable-keyworded entry.

preference:stable_package_masked(Repo, Id, C, N, ProposedVersion, Use) :-
  preference:profile_stable_pkg_masked(Use),
  preference:entry_has_stable_keyword(Repo://Id),
  preference:profile_stable_use_masked(Spec, Use),
  preference:profile_package_use_spec_matches_entry_(Spec, Repo, Id, C, N, ProposedVersion),
  !.


%! preference:stable_package_forced(+Repo, +Id, +C, +N, +Version, +Use) is semidet.
%
% package.use.stable.force hit for a stable-keyworded entry.

preference:stable_package_forced(Repo, Id, C, N, ProposedVersion, Use) :-
  preference:profile_stable_pkg_forced(Use),
  preference:entry_has_stable_keyword(Repo://Id),
  preference:profile_stable_use_forced(Spec, Use),
  preference:profile_package_use_spec_matches_entry_(Spec, Repo, Id, C, N, ProposedVersion),
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
         assertz(preference:local_masked(Id, portage))).


%! preference:unmask_catpkg_atom(+Atom) is det.
%
% Unmask all portage entries matching a simple cat/pkg atom.

preference:unmask_catpkg_atom(Atom) :-
  atom(Atom),
  atomic_list_concat([C,N], '/', Atom),
  forall(cache:ordered_entry(portage, Id, C, N, _),
         retractall(preference:local_masked(Id, portage))).


%! preference:mask_profile_atom(+Atom) is det.
%
% Best-effort profile package.mask support.  Handles simple cat/pkg atoms
% (mask all versions) and versioned atoms parsed via eapi:qualified_target/1.
% Simple masks use `cache:ordered_entry/5` on category/name (indexed).
% Versioned masks iterate only matching category/name entries, not the full tree.

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
      forall(cache:ordered_entry(portage, Id, C, N, ProposedVersion),
             ( preference:version_match(Op, ProposedVersion, Ver),
               preference:slot_req_match_(SlotReq, portage, Id) ->
               assertz(preference:local_masked(Id, portage))
             ; true
             ))
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
      forall(cache:ordered_entry(portage, Id, C, N, ProposedVersion),
             ( preference:version_match(Op, ProposedVersion, Ver),
               preference:slot_req_match_(SlotReq, portage, Id) ->
               retractall(preference:local_masked(Id, portage))
             ; true
             ))
  ; true.


%! preference:slot_req_match_(+SlotReq, +Repo, +Id) is semidet.
%
% Slot restriction matcher for profile package.mask atoms.

preference:slot_req_match_([], _Repo, _Id) :- !.

preference:slot_req_match_([slot(S0)], Repo, Id) :-
  !,
  preference:entry_satisfies_slot_req_(Repo, Id, [slot(S0)]).

preference:slot_req_match_([slot(S0),subslot(Ss0)], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S1)),
  preference:canon_slot_atom_(S0, S),
  preference:canon_slot_atom_(S1, Slot),
  S == Slot,
  ( cache:entry_metadata(Repo, Id, slot, subslot(Ss))
  -> preference:canon_slot_atom_(Ss0, SsW),
     preference:canon_slot_atom_(Ss, SsC),
     SsW == SsC
  ; preference:canon_slot_atom_(Ss0, SsW),
     SsW == Slot
  ).

preference:slot_req_match_([slot(S0),equal], Repo, Id) :-
  !,
  preference:entry_satisfies_slot_req_(Repo, Id, [slot(S0)]).

preference:slot_req_match_([slot(S0),subslot(Ss0),equal], Repo, Id) :-
  !,
  cache:entry_metadata(Repo, Id, slot, slot(S1)),
  preference:canon_slot_atom_(S0, S),
  preference:canon_slot_atom_(S1, Slot),
  S == Slot,
  ( cache:entry_metadata(Repo, Id, slot, subslot(Ss))
  -> preference:canon_slot_atom_(Ss0, SsW),
     preference:canon_slot_atom_(Ss, SsC),
     SsW == SsC
  ; preference:canon_slot_atom_(Ss0, SsW),
     SsW == Slot
  ).

preference:slot_req_match_([any_same_slot], _Repo, _Id) :- !.

preference:slot_req_match_([any_different_slot], _Repo, _Id) :- !.

preference:slot_req_match_(_Other, _Repo, _Id) :- fail.


%! preference:version_match(+Op, +Proposed, +Req) is semidet.
%
% Match an ebuild version against a profile atom comparator.  Used by
% profile package.mask / package.unmask processing.  Avoids query:search/2
% because this runs at init time before goal-expansion.

preference:version_match(tilde, Proposed, Req) :-
  !,
  Proposed = version(N,A,SR,SN,SRe,_,_),
  Req = version(N,A,SR,SN,SRe,_,_).

preference:version_match(wildcard, Proposed, version(_,_,_,_,_,_,Pattern)) :-
  !,
  Proposed = version(_,_,_,_,_,_,ProposedStr),
  eapi:version_glob_match(Pattern, ProposedStr).

% Standard comparison operators share eapi:version_op_match/3; unknown operators
% (other than tilde/wildcard above) fail, as before.
preference:version_match(Op, Proposed, Req) :-
  eapi:version_op_match(Op, Proposed, Req).


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
    reader:config_lines(LicGroupFile, Lines),
    forall(member(Line, Lines),
           preference:parse_license_group_line_(Line))
  ; true
  ).


%! preference:parse_license_group_line_(+Line) is det.
%
% Parse one configuration line of the license_groups file: the group name
% followed by its members.

preference:parse_license_group_line_(Line) :-
  split_string(Line, " ", "", [GroupNameS | MemberSs]),
  atom_string(GroupName, GroupNameS),
  maplist([S,A]>>atom_string(A, S), MemberSs, Members),
  assertz(preference:local_license_group_raw(GroupName, Members)).


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
%  Materialized preference state (Knowledge/preference.qlf)
% -----------------------------------------------------------------------------

%! preference:cache_try_load is semidet.
%
% Load `Knowledge/preference.qlf` when the on-disk stamp matches current
% inputs.  On success, preference/userconfig/profile dynamics are restored
% and AVL index invalidation flags are set.

preference:cache_try_load :-
  preference:cache_enabled,
  preference:stamp_file(StampFile),
  preference:cache_file(QlfFile),
  exists_file(QlfFile),
  exists_file(StampFile),
  preference:cache_read_stamp(Stored),
  preference:cache_current_stamp(Current),
  Stored =@= Current,
  !,
  preference:cache_load_qlf(QlfFile),
  preference:init_reset_indexes.


%! preference:cache_save is det.
%
% Serialize the current materialized preference state to disk and write a
% matching stamp file.  Silently skips when caching is disabled.

preference:cache_save :-
  ( preference:cache_enabled ->
      working_directory(Cwd, Cwd),
      lock:with_system_lock(pref_cache_save(Cwd),
        preference:cache_save_locked)
  ; true
  ).


%! preference:cache_invalidate is det.
%
% Delete generated preference cache artefacts.

preference:cache_invalidate :-
  forall(member(File, ['Knowledge/preference.qlf',
                       'Knowledge/preference.raw',
                       'Knowledge/preference.stamp']),
         catch(delete_file(File), _, true)),
  catch(unload_file('Knowledge/preference.qlf'), _, true),
  retractall(preference:cache_loaded/0).


%! preference:cache_file(-File) is det.
%
% Path to the compiled preference cache (`Knowledge/preference.qlf`).

preference:cache_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/preference.qlf', File).


%! preference:raw_file(-File) is det.
%
% Path to the preference cache source (`Knowledge/preference.raw`).

preference:raw_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/preference.raw', File).


%! preference:stamp_file(-File) is det.
%
% Path to the preference cache stamp file (`Knowledge/preference.stamp`).

preference:stamp_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/preference.stamp', File).


preference:cache_enabled :-
  current_predicate(interface:get_mode/1),
  catch(interface:get_mode(Mode), _, fail),
  current_predicate(config:preference_cache/2),
  config:preference_cache(Mode, cached).


%! preference:cache_current_stamp(-Stamp) is det.

preference:cache_current_stamp(Stamp) :-
  findall(Input, preference:cache_stamp_input(Input), Inputs0),
  sort(Inputs0, Stamp).


% Serialization format version.  Bump whenever the shape of a cached
% entry changes (e.g. local_masked/1 -> local_masked/2), so stale
% preference.qlf files are rebuilt instead of silently misapplied.
preference:cache_stamp_input(format(2)).

preference:cache_stamp_input(src(Path, Mtime)) :-
  preference:cache_tracked_path(Path),
  preference:cache_path_mtime(Path, Mtime).

preference:cache_stamp_input(env(Name, Value)) :-
  member(Name, ['USE', 'ACCEPT_KEYWORDS', 'ACCEPT_LICENSE']),
  ( interface:getenv(Name, Value) -> true ; Value = '' ).


preference:cache_tracked_path('Knowledge/kb.qlf').
preference:cache_tracked_path('Knowledge/profile.qlf').

preference:cache_tracked_path(Path) :-
  current_predicate(config:world_file/1),
  config:world_file(Path).

preference:cache_tracked_path(Path) :-
  current_predicate(config:portage_confdir/1),
  config:portage_confdir(Dir),
  member(Base, [ 'make.conf',
                'package.use',
                'package.mask',
                'package.unmask',
                'package.accept_keywords',
                'package.license' ]),
  os:compose_path(Dir, Base, Path).

preference:cache_tracked_path(Path) :-
  current_predicate(config:set_dir/1),
  config:set_dir(Dir),
  exists_directory(Dir),
  directory_files(Dir, Names),
  member(Name, Names),
  \+ preference:cache_skip_set_name(Name),
  os:compose_path(Dir, Name, Path),
  exists_file(Path).

preference:cache_tracked_path(Path) :-
  catch(portage:get_location(Root), _, fail),
  os:compose_path([Root, 'profiles', 'use.desc'], Path).


preference:cache_skip_set_name(Name) :-
  ( sub_atom(Name, 0, 1, _, '.')
  ; Name == world
  ).


preference:cache_path_mtime(Path, Mtime) :-
  ( exists_file(Path) ->
      time_file(Path, Mtime)
  ; exists_directory(Path) ->
      Mtime = dir
  ; Mtime = missing
  ).


preference:cache_read_stamp(Stamp) :-
  preference:stamp_file(File),
  setup_call_cleanup(
    open(File, read, In, [encoding(utf8)]),
    read_term(In, Stamp, []),
    close(In)).


preference:cache_write_stamp(Stamp) :-
  preference:stamp_file(File),
  setup_call_cleanup(
    open(File, write, Out, [encoding(utf8)]),
    ( format(Out, '~q.~n', [Stamp]) ),
    close(Out)).


:- dynamic preference:cache_loaded/0.

preference:cache_load_qlf(QlfFile) :-
  preference:cache_clear_loaded_state,
  ensure_loaded(QlfFile),
  assertz(preference:cache_loaded),
  forall(preferencedata:entry(Type, Args),
         preference:cache_apply_entry(Type, Args)).


preference:cache_clear_loaded_state :-
  retractall(preference:cache_loaded/0),
  preference:cache_retract_preference_facts,
  retractall(userconfig:env(_, _)),
  retractall(userconfig:package_keyword(_, _)),
  retractall(userconfig:package_license_entry(_, _)),
  retractall(profile:use_description(_, _)).


preference:cache_retract_preference_facts :-
  retractall(preference:local_masked(_,_)),
  retractall(preference:local_use(_)),
  retractall(preference:local_env_use(_)),
  retractall(preference:local_accept_keywords(_)),
  retractall(preference:local_flag(_)),
  retractall(preference:local_userconfig_use(_,_,_,_)),
  retractall(preference:local_profile_use_soft(_,_,_)),
  retractall(preference:local_userconfig_use_versioned(_,_,_)),
  retractall(preference:local_profile_masked_use_flag(_)),
  retractall(preference:local_profile_forced_use_flag(_)),
  retractall(preference:local_profile_use_masked(_,_)),
  retractall(preference:local_profile_use_forced(_,_)),
  preference:clear_profile_stable_use,
  retractall(preference:local_set(_,_)),
  retractall(preference:local_world_entry(_)),
  retractall(preference:local_license_group_raw(_,_)),
  retractall(preference:local_accept_license_wildcard),
  retractall(preference:local_accepted_license(_)),
  retractall(preference:local_denied_license(_)),
  retractall(preference:system_pkg(_,_)).


preference:cache_apply_entry(local_masked, [Id, Repo]) :-
  assertz(preference:local_masked(Id, Repo)).
preference:cache_apply_entry(local_use, [Use]) :-
  assertz(preference:local_use(Use)).
preference:cache_apply_entry(local_env_use, [Use]) :-
  assertz(preference:local_env_use(Use)).
preference:cache_apply_entry(local_accept_keywords, [Key]) :-
  assertz(preference:local_accept_keywords(Key)).
preference:cache_apply_entry(local_flag, [Flag]) :-
  assertz(preference:local_flag(Flag)).
preference:cache_apply_entry(local_userconfig_use, [C,N,Use,State]) :-
  assertz(preference:local_userconfig_use(C,N,Use,State)).
preference:cache_apply_entry(local_profile_use_soft, [Spec,Flag,State]) :-
  assertz(preference:local_profile_use_soft(Spec,Flag,State)).
preference:cache_apply_entry(local_userconfig_use_versioned, [Spec,Use,State]) :-
  assertz(preference:local_userconfig_use_versioned(Spec,Use,State)).
preference:cache_apply_entry(local_profile_masked_use_flag, [U]) :-
  assertz(preference:local_profile_masked_use_flag(U)).
preference:cache_apply_entry(local_profile_forced_use_flag, [U]) :-
  assertz(preference:local_profile_forced_use_flag(U)).
preference:cache_apply_entry(local_profile_use_masked, [Spec,Flag]) :-
  assertz(preference:local_profile_use_masked(Spec,Flag)).
preference:cache_apply_entry(local_profile_use_forced, [Spec,Flag]) :-
  assertz(preference:local_profile_use_forced(Spec,Flag)).
preference:cache_apply_entry(local_profile_stable_masked_use_flag, [U]) :-
  assertz(preference:local_profile_stable_masked_use_flag(U)).
preference:cache_apply_entry(local_profile_stable_forced_use_flag, [U]) :-
  assertz(preference:local_profile_stable_forced_use_flag(U)).
preference:cache_apply_entry(local_profile_stable_use, [U]) :-
  assertz(preference:local_profile_stable_use(U)).
preference:cache_apply_entry(local_profile_stable_use_soft, [Spec,Flag,State]) :-
  preference:assert_stable_use_soft(Spec, Flag, State).
preference:cache_apply_entry(local_profile_stable_use_masked, [Spec,Flag]) :-
  preference:apply_profile_package_use_op(add, stable_masked, Spec, Flag).
preference:cache_apply_entry(local_profile_stable_use_forced, [Spec,Flag]) :-
  preference:apply_profile_package_use_op(add, stable_forced, Spec, Flag).
preference:cache_apply_entry(local_set, [Name,Entries]) :-
  assertz(preference:local_set(Name,Entries)).
preference:cache_apply_entry(local_world_entry, [Entry]) :-
  assertz(preference:local_world_entry(Entry)).
preference:cache_apply_entry(local_license_group_raw, [Name,Members]) :-
  assertz(preference:local_license_group_raw(Name,Members)).
preference:cache_apply_entry(local_accept_license_wildcard, []) :-
  assertz(preference:local_accept_license_wildcard).
preference:cache_apply_entry(local_accepted_license, [Lic]) :-
  assertz(preference:local_accepted_license(Lic)).
preference:cache_apply_entry(local_denied_license, [Lic]) :-
  assertz(preference:local_denied_license(Lic)).
preference:cache_apply_entry(system_pkg, [Cat,Name]) :-
  assertz(preference:system_pkg(Cat,Name)).
preference:cache_apply_entry(userconfig_env, [K,V]) :-
  assertz(userconfig:env(K,V)).
preference:cache_apply_entry(userconfig_package_keyword, [Atom,KW]) :-
  assertz(userconfig:package_keyword(Atom,KW)).
preference:cache_apply_entry(userconfig_package_license, [Atom,Lic]) :-
  assertz(userconfig:package_license_entry(Atom,Lic)).
preference:cache_apply_entry(use_description, [Flag,Desc]) :-
  assertz(profile:use_description(Flag,Desc)).
preference:cache_apply_entry(_, _).


preference:cache_save_locked :-
  preference:raw_file(RawFile),
  preference:cache_collect_entries(Entries),
  setup_call_cleanup(
    open(RawFile, write, Out, [encoding(utf8)]),
    preference:cache_write_raw(Out, Entries),
    close(Out)),
  catch(qcompile(RawFile), _, true),
  preference:cache_current_stamp(Stamp),
  preference:cache_write_stamp(Stamp).


preference:cache_write_raw(Out, Entries) :-
  format(Out, ':- module(preferencedata, []).~n', []),
  format(Out, '% Auto-generated preference cache — do not edit.~n~n', []),
  format(Out, ':- dynamic entry/2.~n~n', []),
  forall(member(entry(Type, Args), Entries),
         format(Out, '~q.~n', [entry(Type, Args)])).


preference:cache_collect_entries(Entries) :-
  findall(entry(Type, Args), preference:cache_collect_entry(Type, Args), Entries).


preference:cache_collect_entry(local_masked, [Id, Repo]) :-
  preference:local_masked(Id, Repo).
preference:cache_collect_entry(local_use, [Use]) :-
  preference:local_use(Use).
preference:cache_collect_entry(local_env_use, [Use]) :-
  preference:local_env_use(Use).
preference:cache_collect_entry(local_accept_keywords, [Key]) :-
  preference:local_accept_keywords(Key).
preference:cache_collect_entry(local_flag, [Flag]) :-
  preference:local_flag(Flag).
preference:cache_collect_entry(local_userconfig_use, [C,N,Use,State]) :-
  preference:local_userconfig_use(C,N,Use,State).
preference:cache_collect_entry(local_profile_use_soft, [Spec,Flag,State]) :-
  preference:local_profile_use_soft(Spec,Flag,State).
preference:cache_collect_entry(local_userconfig_use_versioned, [Spec,Use,State]) :-
  preference:local_userconfig_use_versioned(Spec,Use,State).
preference:cache_collect_entry(local_profile_masked_use_flag, [U]) :-
  preference:local_profile_masked_use_flag(U).
preference:cache_collect_entry(local_profile_forced_use_flag, [U]) :-
  preference:local_profile_forced_use_flag(U).
preference:cache_collect_entry(local_profile_use_masked, [Spec,Flag]) :-
  preference:local_profile_use_masked(Spec,Flag).
preference:cache_collect_entry(local_profile_use_forced, [Spec,Flag]) :-
  preference:local_profile_use_forced(Spec,Flag).
preference:cache_collect_entry(local_profile_stable_masked_use_flag, [U]) :-
  preference:local_profile_stable_masked_use_flag(U).
preference:cache_collect_entry(local_profile_stable_forced_use_flag, [U]) :-
  preference:local_profile_stable_forced_use_flag(U).
preference:cache_collect_entry(local_profile_stable_use, [U]) :-
  preference:local_profile_stable_use(U).
preference:cache_collect_entry(local_profile_stable_use_soft, [Spec,Flag,State]) :-
  preference:local_profile_stable_use_soft(Spec,Flag,State).
preference:cache_collect_entry(local_profile_stable_use_masked, [Spec,Flag]) :-
  preference:local_profile_stable_use_masked(Spec,Flag).
preference:cache_collect_entry(local_profile_stable_use_forced, [Spec,Flag]) :-
  preference:local_profile_stable_use_forced(Spec,Flag).
preference:cache_collect_entry(local_set, [Name,Entries]) :-
  preference:local_set(Name,Entries).
preference:cache_collect_entry(local_world_entry, [Entry]) :-
  preference:local_world_entry(Entry).
preference:cache_collect_entry(local_license_group_raw, [Name,Members]) :-
  preference:local_license_group_raw(Name,Members).
preference:cache_collect_entry(local_accept_license_wildcard, []) :-
  preference:local_accept_license_wildcard.
preference:cache_collect_entry(local_accepted_license, [Lic]) :-
  preference:local_accepted_license(Lic).
preference:cache_collect_entry(local_denied_license, [Lic]) :-
  preference:local_denied_license(Lic).
preference:cache_collect_entry(system_pkg, [Cat,Name]) :-
  preference:system_pkg(Cat,Name).
preference:cache_collect_entry(userconfig_env, [K,V]) :-
  userconfig:env(K,V).
preference:cache_collect_entry(userconfig_package_keyword, [Atom,KW]) :-
  userconfig:package_keyword(Atom,KW).
preference:cache_collect_entry(userconfig_package_license, [Atom,Lic]) :-
  userconfig:package_license_entry(Atom,Lic).
preference:cache_collect_entry(use_description, [Flag,Desc]) :-
  profile:use_description(Flag,Desc).


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
  ( preference:cache_enabled ->
      format('    Preference cache: enabled (Knowledge/preference.qlf)~n')
  ; format('    Preference cache: disabled~n')
  ),
  aggregate_all(count, preference:global_use(_), UseCount),
  aggregate_all(count, preference:masked(_), MaskCount),
  aggregate_all(count, preference:userconfig_use(_,_,_,_), PkgUseCount),
  format('    Global USE:     ~d flags~n', [UseCount]),
  format('    Package masks:  ~d entries~n', [MaskCount]),
  format('    Package USE:    ~d overrides~n', [PkgUseCount]),
  nl.