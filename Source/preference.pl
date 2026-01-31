/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PREFERENCE
The preferences module contains build specific preferences
*/

:- module(preference, []).

:- dynamic preference:masked/1.

:- dynamic preference:local_use/1.
:- dynamic preference:local_env_use/1.
:- dynamic preference:local_accept_keywords/1.
:- dynamic preference:local_flag/1.

% Per-package USE overrides (from /etc/portage/package.use-like sources).
:- dynamic preference:package_use_override/4. % Category, Name, Use, State(positive|negative)

% Profile-enforced per-package USE constraints (from profiles/**/package.use.{mask,force}).
% These are *hard* constraints and override /etc/portage/package.use.
:- dynamic preference:profile_package_use_masked/2. % Spec, Use
:- dynamic preference:profile_package_use_forced/2. % Spec, Use


% =============================================================================
%  PREFERENCE declarations
% =============================================================================

%! preference:env_cflags(?Cflags)
%
% Fact which defines the CFLAGS environment variable

preference:env_cflags('-O3 -march=native -pipe').


%! preference:env_cxxflags(?Cxxflags)
%
% Fact which defines the CXXFLAGS environment variable

preference:env_cxxflags('-O3 -march=native -pipe').


%! preference:env_chost(?Chost)
%
% Fact which defines the CHOST environment variable

preference:env_chost('x86_64-pc-linux-gnu').


%! preference:env_makeopts(?Makeopts)
%
% Fact which defines the MAKEOPTS variable

preference:env_makeopts('-j36').


%! preference:env_features(?Features)
%
% Fact which defines the FEATURES variable

preference:env_features('sign -ccache -buildpkg -sandbox -usersandbox -ebuild-locks parallel-fetch parallel-install').

%! preference:default_env(+Name, -Value)
%
% Default values for Portage-like environment variables, used when the variable
% is not set in the OS environment.
%
% This lets you mirror a Gentoo `emerge --info` snapshot in `preference.pl`
% without having to export envvars before running portage-ng.

% Parity defaults taken from Gentoo /etc/portage/make.conf (vm-linux).
% NOTE: USE is incremental; duplicates are normalized (last occurrence wins).
preference:default_env('ACCEPT_KEYWORDS', '~amd64').
preference:default_env('PERL_FEATURES', 'ithreads').
preference:default_env('RUBY_TARGETS', 'ruby32 ruby33').
preference:default_env('VIDEO_CARDS', 'vmware vesa vga').
preference:default_env('INPUT_DEVICES', 'evdev keyboard mouse vmmouse').
preference:default_env('ALSA_CARDS', 'ens1371').
preference:default_env('CPU_FLAGS_X86', 'aes avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3').
% NOTE: USE is incremental; "last occurrence wins".
% Keep `introspection` enabled for GNOME/KDE stacks (many deps require glib[introspection]).
preference:default_env('USE', 'berkdb harfbuzz lto dnet resolutionkms o-flag-munging pgo graphite optimizations aio npm http split-usr -elogind policykit json -systemd -llvm -lua -berkdb -gdbm -introspection -vala -xen -hcache -ruby python gdbm fbcondecor messages smp qemu sqlite mmxext -svg avahi mmx sse sse2 sse3 ssse3 sse4 sse4_2 gmp cvs git x86emu gpg imap pop sidebar smime smtp dbus truetype X -xvmc xa xkb libkms cairo glitz png jpeg tiff gif mp3 opengl xcb xlib-xcb alsa aac aacplus jpeg2k fontconfig openssl ssh threads x264 x265 xvid dts md5sum a52 aalib zeroconf pkcs11 apng xattr nova account container object proxy directfb pcre16 -mdnsresponder-compat gpm').
% NOTE:
% USE_EXPAND selector variables like LUA_SINGLE_TARGET / LLVM_SLOT / VIDEO_CARDS
% typically come from Gentoo profile `make.defaults` and/or `/etc/portage/make.conf`.
% We intentionally do *not* default them here, because the wrong default causes
% large plan divergences (e.g. enabling multiple llvm_slot_* at once).
% If you use a single Ruby target in Portage, set it here too:
% preference:default_env('RUBY_SINGLE_TARGET', 'ruby33').

%! preference:getenv(+Name, -Value)
%
% Read an environment variable, falling back to preference:default_env/2.

preference:getenv(Name, Value) :-
  ( interface:getenv(Name, Value) ->
      true
  ; current_predicate(config:gentoo_env/2),
    config:gentoo_env(Name, Value),
    Value \== '' ->
      true
  ; preference:default_env(Name, Value)
  ).


%! preference:env_use(?Use)
%
% Predicate which returns a list of parsed USE variables,
% as read from the command line environment variable

preference:env_use(Use) :-
  preference:getenv('USE',Atom),
  atom_codes(Atom,Codes),
  phrase(eapi:iuse(_://_,List),Codes),
  member(Use,List).

%! preference:env_use_expand(Use)
%
% Import USE_EXPAND-like environment variables (e.g. RUBY_TARGETS="ruby33")
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

% Minimal set needed for Python/Ruby parity in plans.
preference:use_expand_env('PYTHON_TARGETS',        python_targets).
preference:use_expand_env('PYTHON_SINGLE_TARGET', python_single_target).
preference:use_expand_env('RUBY_TARGETS',         ruby_targets).
preference:use_expand_env('RUBY_SINGLE_TARGET',   ruby_single_target).
preference:use_expand_env('LUA_SINGLE_TARGET',    lua_single_target).
preference:use_expand_env('PERL_FEATURES',        perl_features).
preference:use_expand_env('LLVM_SLOT',            llvm_slot).
preference:use_expand_env('VIDEO_CARDS',          video_cards).


%! preference:env_accept_keywords_list(Keyword)
%
% Predicate which returns a list of parsed ACCEPT_KEYWORDS variables
% as read from the command line environment variable

preference:env_accept_keywords(Keyword) :-
  preference:getenv('ACCEPT_KEYWORDS',Atom),
  atom_codes(Atom,Codes),
  phrase(eapi:keywords(List),Codes),
  member(Keyword,List).


%! preference:use(X)
%
% Predicate which returns use flag setting. When running
% locally, these are set by preference:init. When running
% in client-server mode, these are typically passed by the
% client and injected as thread-local clauses in the current
% pengines context responsible for answering the client.

preference:use(X) :-
  pengine_self(M),!,
  M:local_use(X).                        % use client USE flags

preference:use(X) :-
  %\+pengine_self(_),
  preference:local_use(X).               % use local USE flags


%! preference:use(X,env)
%
% Enables retrieval of use flag settings overridden by the env

preference:use(X,env) :-
  pengine_self(M),!,
  M:local_env_use(X).

preference:use(X,env) :-
  %\+pengine_self(_),
  preference:local_env_use(X).

preference:use(X,other) :-
  preference:use(X).


%! preference:accept_keywords(X)
%
% Predicate which returns accept_keywords flag setting. When
% running locally, these are set by preference:init. When running
% in client-server mode, these are typically passed by the
% client and injected as thread-local clauses in the current
% pengines context responsible for answering the client.

preference:accept_keywords(X) :-
  pengine_self(M),!,
  M:local_accept_keywords(X).            % use client USE flags

preference:accept_keywords(X) :-
  %\+pengine_self(_),
  preference:local_accept_keywords(X).   % use local USE flags


%! preference:flag(?Flag)
%
% Predicate which returns whether the deep or emptytree flags are enabled
% Set by interface. When running locally, the flag is set by interface.
% When running in client-server mode, this flag typically passed
% by the client and injected as thread-local clause in the current
% pengines context responsible for answering the client.

preference:flag(Flag) :-
  pengine_self(M),!,
  M:local_flag(Flag).

preference:flag(Flag) :-
  %\+pengine_self(_),
  preference:local_flag(Flag).


%! preference:local_use(Use)
%
% Fact which defines local USE variables, taking into account
% environment and configuration (profile) settings.
%
% Dynamic, generated by preference:init


%! preference:local_env_use(Use)
%
% Fact which defines local USE variables, taking into account
% environment settings.
%
% Dynamic, generated by preference:init


%! preference:local_accept_keywords(Keyword)
%
% Fact which defines local ACCEPT_KEYWORDS variables, taking into
% account environment and configuration (profile) settings.
%
% Dynamic, generated by preference:init


%! preference:local_flag(Flag)
%
% Fact which defines local DEEP or EMPTYTREE flags, as set by the interface.
%
% Dynamic, set by the interface


%! preference:init
%
% Sets the active local use flags according to environment and profile defaults
% We do this for both USE flags and ACCEPT_KEYWORDS

%! preference:profile_use_terms(-Terms:list)
%
% Obtain profile-derived USE terms.
%
% If `config:gentoo_profile/1` is set and the Portage profile tree is available,
% we derive these from Gentoo's inherited profile files via `profile.pl`.
% Otherwise we fall back to the (legacy) static `preference:profile_use/1`
% facts declared in this file.
%
preference:profile_use_terms(Terms) :-
  findall(preference:profile_use(Use), preference:profile_override_use(Use), OverrideTerms),
  ( config:gentoo_profile(ProfileRel),
    catch(profile:profile_use_terms(ProfileRel, Terms0), _, fail) ->
      append(Terms0, OverrideTerms, Terms)
  ; findall(preference:profile_use(Use), preference:profile_use(Use), BaseTerms),
    append(BaseTerms, OverrideTerms, Terms)
  ).

%! preference:profile_override_use(?Use)
%
% Extra USE defaults layered *after* the Gentoo profile (if any).
% This is the right place for local policy tweaks that aren't encoded in the
% selected Gentoo profile tree.
%
% (Kept small on purpose; add more only when required by parity checks.)
%
preference:profile_override_use(minus(introspection)).
preference:profile_override_use(minus(launcher)).

preference:init :-

  % Reset derived state (important when regenerating lots of plans in one session).
  retractall(preference:masked(_)),
  retractall(preference:package_use_override(_,_,_,_)),
  retractall(preference:profile_package_use_masked(_,_)),
  retractall(preference:profile_package_use_forced(_,_)),

  % 1. Set use flags

  % IMPORTANT:
  % `preference:init/0` must never fail. If it fails, the application startup
  % will retry KB load/init paths and can surface unrelated errors. Be defensive:
  % treat unexpected issues as "skip that bit" rather than aborting init.
  forall(preference:env_use(Use),            (assertz(preference:local_env_use(Use)), assertz(preference:local_use(Use)))),
  forall(preference:env_use_expand(Use),     (assertz(preference:local_env_use(Use)), assertz(preference:local_use(Use)))),
  preference:profile_use_terms(ProfileTerms),
  % Portage semantics for *_SINGLE_TARGET variables:
  % when the environment sets e.g. LUA_SINGLE_TARGET="luajit", it overrides the
  % profile defaults for lua_single_target_* (do not union them).
  findall(Prefix,
          ( member(EnvVar, ['LUA_SINGLE_TARGET','PYTHON_SINGLE_TARGET','RUBY_SINGLE_TARGET']),
            preference:getenv(EnvVar, Atom),
            Atom \== '',
            preference:use_expand_env(EnvVar, Prefix)
          ),
          SingleTargetPrefixes),
  forall(member(preference:profile_use(Term), ProfileTerms),
         ( ( Term = minus(U0) -> U = U0 ; U = Term ),
           ( member(Prefix, SingleTargetPrefixes),
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

  % 2. Set accept_keywords
  %
  % Portage semantics: if ~arch is accepted, the corresponding stable arch is
  % also accepted. E.g. ACCEPT_KEYWORDS="~amd64" still accepts KEYWORDS="amd64".

   ( preference:env_accept_keywords(_) ->
       forall(preference:env_accept_keywords(Key),
              assertz(preference:local_accept_keywords(Key))),
       % Ensure stable(Arch) is implied by unstable(Arch)
       forall(preference:env_accept_keywords(unstable(Arch)),
              ( preference:local_accept_keywords(stable(Arch))
              -> true
              ;  assertz(preference:local_accept_keywords(stable(Arch)))
              ))
   ; forall(preference:default_accept_keywords(Key),
            assertz(preference:local_accept_keywords(Key)))
   ),

  % 3. Apply Gentoo profile + /etc/portage overrides (package.mask / package.use).
  %
  % These affect candidate selection (masking) and per-package USE evaluation.
  %
  catch(preference:apply_profile_package_mask, _, true),
  catch(preference:apply_profile_package_use_mask, _, true),
  catch(preference:apply_profile_package_use_force, _, true),
  catch(preference:apply_profile_package_use,  _, true),
  catch(preference:apply_gentoo_package_mask,  _, true),
  catch(preference:apply_gentoo_package_use,   _, true),
  !.

% ---------------------------------------------------------------------------
% Profile per-package USE constraints (package.use.mask / package.use.force)
% ---------------------------------------------------------------------------

% Normalize a profile atom into a matching spec.
%
% We support:
% - simple(C,N)                     (cat/pkg)
% - versioned(Op,C,N,Ver)           (>=cat/pkg-1.2, =cat/pkg-0*, ...)
%
% Notes:
% - We intentionally ignore slot restrictions and use deps in these atoms for now.
% - A target of the form cat/pkg-1.2 (no operator) is treated like '=' (exact).
preference:profile_package_use_spec(Atom, Spec) :-
  atom(Atom),
  atom_codes(Atom, Codes),
  catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
  Q = qualified_target(Op, _Repo, C, N, Ver0, _Filters),
  nonvar(C), nonvar(N),
  ( Ver0 == [[], '', '', '', ''] ->
      Spec = simple(C, N)
  ; Op == none ->
      Spec = versioned(equal, C, N, Ver0)
  ; Spec = versioned(Op, C, N, Ver0)
  ),
  !.

preference:apply_profile_package_use_mask :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_file(Dir, 'package.use.mask', masked), _, true))
  ; true
  ).

preference:apply_profile_package_use_force :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_file(Dir, 'package.use.force', forced), _, true))
  ; true
  ).

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

preference:apply_profile_package_use_op(add, masked, Spec, Flag) :-
  ( preference:profile_package_use_masked(Spec, Flag) -> true
  ; assertz(preference:profile_package_use_masked(Spec, Flag))
  ),
  !.
preference:apply_profile_package_use_op(del, masked, Spec, Flag) :-
  retractall(preference:profile_package_use_masked(Spec, Flag)),
  !.
preference:apply_profile_package_use_op(add, forced, Spec, Flag) :-
  ( preference:profile_package_use_forced(Spec, Flag) -> true
  ; assertz(preference:profile_package_use_forced(Spec, Flag))
  ),
  !.
preference:apply_profile_package_use_op(del, forced, Spec, Flag) :-
  retractall(preference:profile_package_use_forced(Spec, Flag)),
  !.

% Determine whether a profile enforces a hard per-package USE state for an entry.
% Precedence: mask wins over force (Portage-like).
preference:profile_package_use_override_for_entry(Repo://Id, Use, State, Reason) :-
  cache:ordered_entry(Repo, Id, C, N, ProposedVersion),
  ( ( preference:profile_package_use_masked(simple(C,N), Use)
    ; preference:profile_package_use_masked(versioned(Op,C,N,ReqVer), Use),
      preference:version_match(Op, ProposedVersion, ReqVer)
    ) ->
      State = negative,
      Reason = profile_package_use_mask
  ; ( preference:profile_package_use_forced(simple(C,N), Use)
    ; preference:profile_package_use_forced(versioned(Op,C,N,ReqVer), Use),
      preference:version_match(Op, ProposedVersion, ReqVer)
    ) ->
      State = positive,
      Reason = profile_package_use_force
  ),
  !.

% Apply per-package USE from the Gentoo profile tree (profiles/*/package.use).
% This is needed for Portage parity for lua-single defaults like:
%   dev-lua/luv lua_single_target_luajit -lua_single_target_lua5-1
preference:apply_profile_package_use :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      forall(member(Dir, Dirs),
             catch(preference:apply_profile_package_use_dir(Dir), _, true))
  ; true
  ).

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
                     % Only support simple cat/pkg atoms here (no operators/slots/usedep).
                     atom_string(AtomA, AtomS),
                     ( atomic_list_concat([_C,_N], '/', AtomA),
                       \+ sub_atom(AtomA, 0, 1, _, '>'),
                       \+ sub_atom(AtomA, 0, 1, _, '<'),
                       \+ sub_atom(AtomA, 0, 1, _, '='),
                       \+ sub_atom(AtomA, 0, 1, _, '~'),
                       \+ sub_atom(AtomA, _, 1, _, ':'),
                       \+ sub_atom(AtomA, _, 1, _, '['),
                       \+ sub_atom(AtomA, _, 1, _, '*')
                     ->
                       ( FlagSs == [] ->
                           true
                       ; atomic_list_concat(FlagSs, ' ', FlagAtomS),
                         atom_string(FlagAtom, FlagAtomS),
                         preference:register_package_use(AtomA, FlagAtom)
                       )
                     ; true
                     )
                 ; true
                 )
               )
             ))
  ; true
  ).


% -----------------------------------------------------------------------------
%  Gentoo /etc/portage integration (subset)
% -----------------------------------------------------------------------------

preference:apply_gentoo_package_mask :-
  ( current_predicate(config:gentoo_package_mask/1) ->
      forall(config:gentoo_package_mask(Atom),
             preference:mask_catpkg_atom(Atom))
  ; true
  ).

preference:apply_profile_package_mask :-
  ( current_predicate(config:gentoo_profile/1),
    catch(config:gentoo_profile(ProfileRel), _, fail),
    current_predicate(profile:profile_package_mask_atoms/2),
    catch(profile:profile_package_mask_atoms(ProfileRel, Atoms), _, fail) ->
      forall(member(Atom, Atoms),
             ( % Portage profile package.mask supports incremental unmasking:
               % lines starting with '-' remove an atom masked by parents.
               ( sub_atom(Atom, 0, 1, _, '-') ->
                   sub_atom(Atom, 1, _, 0, Atom1),
                   normalize_space(atom(Atom2), Atom1),
                   preference:unmask_profile_atom(Atom2)
               ; preference:mask_profile_atom(Atom)
               )))
  ; true
  ).

preference:mask_catpkg_atom(Atom) :-
  atom(Atom),
  atomic_list_concat([C,N], '/', Atom),
  % Mask all matching entries in the main repo (not VDB).
  forall(cache:ordered_entry(portage, Id, C, N, _),
         assertz(preference:masked(portage://Id))).

preference:unmask_catpkg_atom(Atom) :-
  atom(Atom),
  atomic_list_concat([C,N], '/', Atom),
  forall(cache:ordered_entry(portage, Id, C, N, _),
         retractall(preference:masked(portage://Id))).

% Best-effort profile package.mask support.
%
% - Supports simple cat/pkg atoms (mask all versions)
% - Supports version operators by parsing the atom using the EAPI qualified_target parser
%   and masking all matching portage entries.
% - Ignores slots/usedeps/repository qualifiers for now.
preference:mask_profile_atom(Atom) :-
  atom(Atom),
  % Fast path: simple cat/pkg
  ( atomic_list_concat([_C,_N], '/', Atom),
    \+ sub_atom(Atom, 0, 1, _, '>'),
    \+ sub_atom(Atom, 0, 1, _, '<'),
    \+ sub_atom(Atom, 0, 1, _, '='),
    \+ sub_atom(Atom, 0, 1, _, '~'),
    \+ sub_atom(Atom, _, 1, _, ':'),   % slots
    \+ sub_atom(Atom, _, 1, _, '['),   % usedeps
    \+ sub_atom(Atom, _, 1, _, '*')    % wildcards
  ) ->
    preference:mask_catpkg_atom(Atom)
  ; % Slow path: attempt to parse versioned atoms
    atom_codes(Atom, Codes),
    catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
    Q = qualified_target(Op, _Repo, C, N, Ver, _Filters),
    nonvar(C), nonvar(N) ->
      forall(cache:ordered_entry(portage, Id, C, N, _),
             ( cache:ordered_entry(portage, Id, C, N, ProposedVersion),
               ( preference:version_match(Op, ProposedVersion, Ver) ->
                 assertz(preference:masked(portage://Id))
               ; true
               )))
  ; true.

% Undo masking for a profile package.mask atom (Portage-style '-cat/pkg' lines).
preference:unmask_profile_atom(Atom) :-
  atom(Atom),
  ( atomic_list_concat([_C,_N], '/', Atom),
    \+ sub_atom(Atom, 0, 1, _, '>'),
    \+ sub_atom(Atom, 0, 1, _, '<'),
    \+ sub_atom(Atom, 0, 1, _, '='),
    \+ sub_atom(Atom, 0, 1, _, '~'),
    \+ sub_atom(Atom, _, 1, _, ':'),   % slots
    \+ sub_atom(Atom, _, 1, _, '['),   % usedeps
    \+ sub_atom(Atom, _, 1, _, '*')    % wildcards
  ) ->
    preference:unmask_catpkg_atom(Atom)
  ; atom_codes(Atom, Codes),
    catch(phrase(eapi:qualified_target(Q), Codes), _, fail),
    Q = qualified_target(Op, _Repo, C, N, Ver, _Filters),
    nonvar(C), nonvar(N) ->
      forall(cache:ordered_entry(portage, Id, C, N, _),
             ( cache:ordered_entry(portage, Id, C, N, ProposedVersion),
               ( preference:version_match(Op, ProposedVersion, Ver) ->
                 retractall(preference:masked(portage://Id))
               ; true
               )))
  ; true.

% Match an ebuild version against a profile atom comparator.
% This is used by profile package.mask/package.unmask processing.
%
% We intentionally avoid using `query:search/2` here because this code runs at
% initialization time and must remain correct even if query goal-expansion did
% not run for the calling context.
preference:version_match(none, _Proposed, _Req) :- !.
preference:version_match(equal, Proposed, Req) :-
  % Treat '=...-1.9*' as a wildcard match (rare in profiles but supported).
  Req = [_,_,_,Pattern],
  atom(Pattern),
  sub_atom(Pattern, _, 1, 0, '*'),
  !,
  Proposed = [_,_,_,ProposedStr],
  query:wildcard_match(Pattern, ProposedStr).
preference:version_match(equal, Proposed, Req) :-
  Proposed == Req,
  !.
preference:version_match(tilde, [V|_], [V|_]) :- !.
preference:version_match(wildcard, Proposed, [_,_,_,Pattern]) :-
  !,
  Proposed = [_,_,_,ProposedStr],
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


preference:apply_gentoo_package_use :-
  ( current_predicate(config:gentoo_package_use/2) ->
      forall(config:gentoo_package_use(CNAtom, UseStr),
             preference:register_package_use(CNAtom, UseStr))
  ; true
  ).

preference:register_package_use(CNAtom, UseStr) :-
  atom(CNAtom),
  atomic_list_concat([C,N], '/', CNAtom),
  atom_string(UseAtom, UseStr),
  split_string(UseAtom, " ", " \t\r\n", Parts0),
  exclude(=(""), Parts0, Parts),
  forall(member(P, Parts),
         ( sub_atom(P, 0, 1, _, '-') ->
             sub_atom(P, 1, _, 0, Flag0),
             Flag0 \== '',
             atom_string(Flag, Flag0),
             retractall(preference:package_use_override(C, N, Flag, _)),
             assertz(preference:package_use_override(C, N, Flag, negative))
         ; atom_string(Flag, P),
           retractall(preference:package_use_override(C, N, Flag, _)),
           assertz(preference:package_use_override(C, N, Flag, positive))
         )).


%! preference:default_accept_keywords(?Keyword)
%
% Fact which defines the default ACCEPT_KEYWORDS variable

preference:default_accept_keywords(unstable(amd64)).
preference:default_accept_keywords(stable(amd64)).

%! preference:keyword_selection_mode(?Mode)
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


%! preference:profile_use(?Use)
%
% Fact which defines the profile USE flags to be used

preference:profile_use('a52').
preference:profile_use('aac').
preference:profile_use('aacplus').
preference:profile_use('aalib').
preference:profile_use('abi_x86_64').
preference:profile_use('account').
preference:profile_use('acl').
preference:profile_use('ada_target_gcc_14').
preference:profile_use('aio').
preference:profile_use('alsa').
preference:profile_use('alsa_cards_ens1371').
preference:profile_use('amd64').
preference:profile_use('apache2_modules_auth_basic').
preference:profile_use('apache2_modules_authn_core').
preference:profile_use('apache2_modules_authn_file').
preference:profile_use('apache2_modules_authz_core').
preference:profile_use('apache2_modules_authz_host').
preference:profile_use('apache2_modules_dir').
preference:profile_use('apache2_modules_mime').
preference:profile_use('apache2_modules_socache_shmcb').
preference:profile_use('apache2_modules_unixd').
preference:profile_use('apng').
preference:profile_use('avahi').
preference:profile_use('bzip2').
preference:profile_use('cairo').
preference:profile_use('calligra_features_karbon').
preference:profile_use('calligra_features_sheets').
preference:profile_use('calligra_features_words').
preference:profile_use('cet').
preference:profile_use('collectd_plugins_df').
preference:profile_use('collectd_plugins_interface').
preference:profile_use('collectd_plugins_irq').
preference:profile_use('collectd_plugins_load').
preference:profile_use('collectd_plugins_memory').
preference:profile_use('collectd_plugins_rrdtool').
preference:profile_use('collectd_plugins_swap').
preference:profile_use('collectd_plugins_syslog').
preference:profile_use('container').
preference:profile_use('cpu_flags_x86_aes').
preference:profile_use('cpu_flags_x86_avx').
preference:profile_use('cpu_flags_x86_avx2').
preference:profile_use('cpu_flags_x86_avx512bw').
preference:profile_use('cpu_flags_x86_avx512cd').
preference:profile_use('cpu_flags_x86_avx512dq').
preference:profile_use('cpu_flags_x86_avx512f').
preference:profile_use('cpu_flags_x86_avx512vl').
preference:profile_use('cpu_flags_x86_f16c').
preference:profile_use('cpu_flags_x86_fma3').
preference:profile_use('cpu_flags_x86_mmx').
preference:profile_use('cpu_flags_x86_mmxext').
preference:profile_use('cpu_flags_x86_pclmul').
preference:profile_use('cpu_flags_x86_popcnt').
preference:profile_use('cpu_flags_x86_rdrand').
preference:profile_use('cpu_flags_x86_sse').
preference:profile_use('cpu_flags_x86_sse2').
preference:profile_use('cpu_flags_x86_sse3').
preference:profile_use('cpu_flags_x86_sse4_1').
preference:profile_use('cpu_flags_x86_sse4_2').
preference:profile_use('cpu_flags_x86_ssse3').
preference:profile_use('crypt').
preference:profile_use('cvs').
preference:profile_use('dbus').
preference:profile_use('directfb').
preference:profile_use('dnet').
preference:profile_use('dts').
preference:profile_use('elibc_glibc').
preference:profile_use('expat').
preference:profile_use('fbcondecor').
preference:profile_use('fontconfig').
preference:profile_use('gdbm').
preference:profile_use('gif').
preference:profile_use('git').
preference:profile_use('glitz').
preference:profile_use('gmp').
preference:profile_use('gpg').
preference:profile_use('gpm').
preference:profile_use('gpsd_protocols_aivdm').
preference:profile_use('gpsd_protocols_ashtech').
preference:profile_use('gpsd_protocols_earthmate').
preference:profile_use('gpsd_protocols_evermore').
preference:profile_use('gpsd_protocols_fv18').
preference:profile_use('gpsd_protocols_garmin').
preference:profile_use('gpsd_protocols_garmintxt').
preference:profile_use('gpsd_protocols_gpsclock').
preference:profile_use('gpsd_protocols_greis').
preference:profile_use('gpsd_protocols_isync').
preference:profile_use('gpsd_protocols_itrax').
preference:profile_use('gpsd_protocols_navcom').
preference:profile_use('gpsd_protocols_oceanserver').
preference:profile_use('gpsd_protocols_oncore').
preference:profile_use('gpsd_protocols_rtcm104v2').
preference:profile_use('gpsd_protocols_rtcm104v3').
preference:profile_use('gpsd_protocols_sirf').
preference:profile_use('gpsd_protocols_skytraq').
preference:profile_use('gpsd_protocols_superstar2').
preference:profile_use('gpsd_protocols_tnt').
preference:profile_use('gpsd_protocols_tripmate').
preference:profile_use('gpsd_protocols_tsip').
preference:profile_use('gpsd_protocols_ublox').
preference:profile_use('graphite').
preference:profile_use('guile_single_target_3-0').
preference:profile_use('guile_targets_3-0').
preference:profile_use('harfbuzz').
preference:profile_use('http').
preference:profile_use('iconv').
preference:profile_use('imap').
preference:profile_use('input_devices_evdev').
preference:profile_use('input_devices_keyboard').
preference:profile_use('input_devices_mouse').
preference:profile_use('input_devices_vmmouse').
preference:profile_use('ipv6').
preference:profile_use('jpeg').
preference:profile_use('jpeg2k').
preference:profile_use('json').
% Many GNOME packages default to +introspection; the Gentoo profile used for
% these comparisons disables it (see emerge plans). Mirror that here so portage-ng
% does not pull in gobject-introspection unnecessarily.
preference:profile_use(minus(introspection)).
% `sys-apps/dbus-broker` defaults to +launcher, which pulls systemd. On OpenRC
% profiles this is typically disabled, matching emerge plans.
preference:profile_use(minus(launcher)).
preference:profile_use('kernel_linux').
preference:profile_use('lcd_devices_bayrad').
preference:profile_use('lcd_devices_cfontz').
preference:profile_use('lcd_devices_glk').
preference:profile_use('lcd_devices_hd44780').
preference:profile_use('lcd_devices_lb216').
preference:profile_use('lcd_devices_lcdm001').
preference:profile_use('lcd_devices_mtxorb').
preference:profile_use('lcd_devices_text').
preference:profile_use('libkms').
preference:profile_use('libtirpc').
preference:profile_use('llvm_targets_x86').
preference:profile_use('lto').
preference:profile_use('lua_single_target_lua5-1').
preference:profile_use('lua_targets_lua5-1').
preference:profile_use('md5sum').
preference:profile_use('messages').
preference:profile_use('mmx').
preference:profile_use('mmxext').
preference:profile_use('mp3').
preference:profile_use('ncurses').
preference:profile_use('nls').
preference:profile_use('nova').
preference:profile_use('npm').
preference:profile_use('o-flag-munging').
preference:profile_use('object').
preference:profile_use('office_implementation_libreoffice').
preference:profile_use('opengl').
preference:profile_use('openmp').
preference:profile_use('openssl').
preference:profile_use('optimizations').
preference:profile_use('pam').
preference:profile_use('pcre').
preference:profile_use('pcre16').
preference:profile_use('perl_features_ithreads').
preference:profile_use('pgo').
preference:profile_use('php_targets_php8-3').
preference:profile_use('pkcs11').
preference:profile_use('png').
preference:profile_use('policykit').
preference:profile_use('pop').
preference:profile_use('postgres_targets_postgres17').
preference:profile_use('proxy').
preference:profile_use('python').
preference:profile_use('python_single_target_python3_13').
preference:profile_use('python_targets_python3_13').
preference:profile_use('qemu').
preference:profile_use('readline').
preference:profile_use('resolutionkms').
preference:profile_use('ruby_targets_ruby32').
preference:profile_use('ruby_targets_ruby33').
preference:profile_use('seccomp').
preference:profile_use('sidebar').
preference:profile_use('smime').
preference:profile_use('smp').
preference:profile_use('smtp').
preference:profile_use('split-usr').
preference:profile_use('sqlite').
preference:profile_use('sse').
preference:profile_use('sse2').
preference:profile_use('sse3').
preference:profile_use('sse4').
preference:profile_use('sse4_2').
preference:profile_use('ssh').
preference:profile_use('ssl').
preference:profile_use('ssse3').
preference:profile_use('test-rust').
preference:profile_use('threads').
preference:profile_use('tiff').
preference:profile_use('truetype').
preference:profile_use('unicode').
preference:profile_use('video_cards_vesa').
preference:profile_use('video_cards_vga').
preference:profile_use('video_cards_vmware').
preference:profile_use('x264').
preference:profile_use('x265').
preference:profile_use('x86emu').
preference:profile_use('xa').
preference:profile_use('xattr').
preference:profile_use('xcb').
preference:profile_use('xkb').
preference:profile_use('xlib-xcb').
preference:profile_use('xtables_addons_account').
preference:profile_use('xtables_addons_chaos').
preference:profile_use('xtables_addons_condition').
preference:profile_use('xtables_addons_delude').
preference:profile_use('xtables_addons_dhcpmac').
preference:profile_use('xtables_addons_fuzzy').
preference:profile_use('xtables_addons_geoip').
preference:profile_use('xtables_addons_iface').
preference:profile_use('xtables_addons_ipmark').
preference:profile_use('xtables_addons_ipp2p').
preference:profile_use('xtables_addons_ipv4options').
preference:profile_use('xtables_addons_length2').
preference:profile_use('xtables_addons_logmark').
preference:profile_use('xtables_addons_lscan').
preference:profile_use('xtables_addons_pknock').
preference:profile_use('xtables_addons_proto').
preference:profile_use('xtables_addons_psd').
preference:profile_use('xtables_addons_quota2').
preference:profile_use('xtables_addons_sysrq').
preference:profile_use('xtables_addons_tarpit').
preference:profile_use('xvid').
preference:profile_use('zeroconf').
preference:profile_use('zlib').

preference:profile_use(minus(test)).
%preference:profile_use(minus(static-libs)).
%preference:profile_use(minus(static)).


%! preference:use_expand_hidden(?Use)
%
% The printer does not print the expanding USE declared as hidden

preference:use_expand_hidden('abi_mips').
preference:use_expand_hidden('abi_ppc').
preference:use_expand_hidden('abi_riscv').
preference:use_expand_hidden('abi_s390').
preference:use_expand_hidden('abi_x86').
preference:use_expand_hidden('cpu_flags_arm').
preference:use_expand_hidden('cpu_flags_ppc').


%! preference:masked(?Repository://?Entry)
%
% Fact which masks a Repository entry

% The prover uses the dynamic 'proven:broken/1' to mark some entries as broken
% preference:masked(Repository://Entry) :- prover:broken(Repository://Entry).


%! preference:set(?Name,?List)
%
% A sample set for testing merging different packages

preference:set('@prolog',[ 'dev-lang/swi-prolog', 'portage://dev-lang/qu-prolog-10.8', 'portage-9999','>gentoo-sources-2.5' ]).


%! preference:world(?List)
%
% A sample world list for testing merging different packages

preference:world([ 'acct-group/avahi-0-r1','acct-group/input-0-r1','acct-group/kvm-0-r1','acct-group/locate-0-r1','acct-group/man-0-r1','acct-group/netdev-0-r1','acct-group/portage-0','acct-group/render-0-r1','acct-group/sshd-0-r1','acct-group/utmp-0-r1','acct-user/avahi-0-r1','acct-user/man-1-r1','acct-user/portage-0','acct-user/sshd-0-r1','app-admin/eselect-1.4.17','app-admin/logrotate-3.18.0','app-admin/metalog-20200113-r1','app-admin/perl-cleaner-2.28','app-admin/sudo-1.9.5_p2-r1','app-arch/afio-2.5.1-r2','app-arch/bzip2-1.0.8-r1','app-arch/gzip-1.10','app-arch/libarchive-3.5.1','app-arch/pbzip2-1.1.13','app-arch/tar-1.33','app-arch/unzip-6.0_p25-r1','app-arch/xz-utils-5.2.5','app-arch/zstd-1.4.8-r1','app-crypt/gnupg-2.2.27','app-crypt/gpgme-1.15.1','app-crypt/libb2-0.98.1-r3','app-crypt/openpgp-keys-gentoo-release-20200704','app-crypt/p11-kit-0.23.22','app-crypt/rhash-1.4.1','app-doc/xmltoman-0.4-r1','app-editors/nano-5.5','app-editors/vim-8.2.0814-r100','app-editors/vim-core-8.2.0814','app-emulation/open-vm-tools-11.2.5_p17337674','app-emulation/virt-what-1.20','app-eselect/eselect-fontconfig-1.1-r1','app-eselect/eselect-iptables-20200508','app-eselect/eselect-lib-bin-symlink-0.1.1-r1','app-eselect/eselect-pinentry-0.7.1','app-eselect/eselect-python-20200719','app-eselect/eselect-rust-20200419','app-eselect/eselect-vi-1.2','app-misc/c_rehash-1.7-r1','app-misc/editor-wrapper-4-r1','app-misc/mime-types-9','app-misc/pax-utils-1.2.9','app-misc/screen-4.8.0-r1','app-portage/cpuid2cpuflags-11','app-portage/elt-patches-20201205','app-portage/esearch-1.3-r3','app-portage/gemato-16.2','app-portage/genlop-0.30.10-r2','app-portage/gentoolkit-0.5.0-r2','app-portage/portage-utils-0.90.1','app-portage/repoman-3.0.2','app-portage/splat-0.08-r1','app-shells/bash-5.1_p4','app-shells/zsh-5.8','app-text/ansifilter-2.18','app-text/build-docbook-catalog-1.21','app-text/docbook-xml-dtd-4.2-r3','app-text/docbook-xml-dtd-4.1.2-r7','app-text/docbook-xsl-stylesheets-1.79.1-r2','app-text/manpager-1','app-text/opensp-1.5.2-r6','app-text/po4a-0.62','app-text/sgml-common-0.6.3-r7','app-text/xmlto-0.0.28-r3','app-vim/gentoo-syntax-20201216','dev-db/sqlite-3.34.0','dev-lang/nasm-2.15.05','dev-lang/perl-5.32.1','dev-lang/python-3.10.0_alpha5','dev-lang/python-3.9.1-r1','dev-lang/python-3.7.9-r2','dev-lang/python-exec-2.4.6-r4','dev-lang/python-exec-conf-2.4.6','dev-lang/rust-1.49.0','dev-lang/spidermonkey-78.7.1','dev-lang/swig-4.0.2','dev-lang/tcl-8.6.11','dev-libs/elfutils-0.183','dev-libs/expat-2.2.10','dev-libs/fribidi-1.0.9','dev-libs/gmp-6.2.1','dev-libs/icu-68.2','dev-libs/isl-0.23-r1','dev-libs/jsoncpp-1.9.4','dev-libs/libassuan-2.5.4','dev-libs/libbsd-0.10.0','dev-libs/libdaemon-0.14-r3','dev-libs/libdnet-1.14-r2','dev-libs/libedit-20191211.3.1','dev-libs/libevdev-1.11.0','dev-libs/libevent-2.1.12','dev-libs/libffi-3.3-r2','dev-libs/libksba-1.5.0','dev-libs/liblinear-242','dev-libs/libltdl-2.4.6','dev-libs/libmspack-0.10.1_alpha','dev-libs/libpcre-8.44','dev-libs/libpipeline-1.5.3','dev-libs/libtasn1-4.16.0','dev-libs/libunistring-0.9.10','dev-libs/libuv-1.40.0','dev-libs/libxml2-2.9.10-r4','dev-libs/libxslt-1.1.34-r1','dev-libs/libyaml-0.2.5','dev-libs/lzo-2.10','dev-libs/mpc-1.2.1','dev-libs/mpfr-4.1.0','dev-libs/npth-1.6-r1','dev-libs/nspr-4.29','dev-libs/openssl-1.1.1i','dev-libs/popt-1.18','dev-libs/xmlsec-1.2.31','dev-perl/Authen-SASL-2.160.0-r2','dev-perl/Date-Manip-6.820.0','dev-perl/DBD-SQLite-1.660.0','dev-perl/DBI-1.643.0','dev-perl/Devel-Size-0.830.0','dev-perl/Digest-HMAC-1.30.0-r2','dev-perl/Encode-Locale-1.50.0','dev-perl/Error-0.170.290','dev-perl/ExtUtils-Config-0.8.0','dev-perl/ExtUtils-Helpers-0.26.0','dev-perl/ExtUtils-InstallPaths-0.12.0','dev-perl/File-Listing-6.70.0','dev-perl/HTML-Parser-3.720.0','dev-perl/HTML-Tagset-3.200.0-r1','dev-perl/HTTP-Cookies-6.40.0','dev-perl/HTTP-Daemon-6.60.0','dev-perl/HTTP-Date-6.20.0-r1','dev-perl/HTTP-Message-6.130.0','dev-perl/HTTP-Negotiate-6.10.0-r1','dev-perl/IO-HTML-1.1.0','dev-perl/IO-Socket-INET6-2.720.0-r1','dev-perl/IO-Socket-SSL-2.66.0','dev-perl/libwww-perl-6.270.0','dev-perl/Locale-gettext-1.70.0','dev-perl/LWP-MediaTypes-6.20.0-r1','dev-perl/LWP-Protocol-https-6.70.0','dev-perl/MailTools-2.190.0','dev-perl/MIME-Charset-1.12.2','dev-perl/Module-Build-0.422.400','dev-perl/Module-Build-Tiny-0.39.0','dev-perl/Mozilla-CA-20999999','dev-perl/Net-Daemon-0.480.0-r2','dev-perl/Net-HTTP-6.170.0','dev-perl/Net-SSLeay-1.880.0','dev-perl/PlRPC-0.202.0-r3','dev-perl/Pod-Parser-1.630.0-r1','dev-perl/SGMLSpm-1.1-r1','dev-perl/Socket6-0.280.0','dev-perl/Sub-Name-0.210.0','dev-perl/TermReadKey-2.370.0','dev-perl/Text-CharWidth-0.40.0-r1','dev-perl/Text-WrapI18N-0.60.0-r1','dev-perl/TimeDate-2.330.0','dev-perl/Try-Tiny-0.300.0','dev-perl/Unicode-LineBreak-2019.1.0','dev-perl/URI-1.730.0','dev-perl/WWW-RobotRules-6.20.0-r1','dev-perl/XML-Parser-2.440.0','dev-perl/YAML-Tiny-1.730.0','dev-python/certifi-10001-r1','dev-python/chardet-4.0.0','dev-python/cython-0.29.21-r1','dev-python/idna-2.10-r1','dev-python/jinja-2.11.3','dev-python/lxml-4.6.2-r1','dev-python/mako-1.1.4','dev-python/markupsafe-1.1.1-r1','dev-python/PySocks-1.7.1-r1','dev-python/pyyaml-5.4.1','dev-python/requests-2.25.1-r1','dev-python/setuptools_scm-5.0.1','dev-util/cmake-3.19.4','dev-util/desktop-file-utils-0.26-r1','dev-util/glib-utils-2.66.4','dev-util/google-perftools-2.8','dev-util/gperf-3.1','dev-util/gtk-doc-am-1.33.1','dev-util/intltool-0.51.0-r2','dev-util/itstool-2.0.6-r1','dev-util/meson-format-array-0','dev-util/pkgconfig-0.29.2','dev-util/re2c-2.0.3','dev-vcs/cvsps-2.2_beta1-r1','gui-libs/display-manager-init-1.0-r2','mail-mta/nullmailer-2.2-r1','media-fonts/dejavu-2.37','media-fonts/encodings-1.0.5-r1','media-fonts/font-adobe-100dpi-1.0.3-r2','media-fonts/font-adobe-75dpi-1.0.3-r2','media-fonts/font-alias-1.0.4','media-fonts/font-misc-misc-1.1.2-r2','media-fonts/font-util-1.3.2-r1','media-gfx/graphite2-1.3.14','media-gfx/graphviz-2.44.1-r1','media-libs/fontconfig-2.13.1-r2','media-libs/freeglut-3.2.1','media-libs/freetype-2.10.4','media-libs/giflib-5.2.1-r1','media-libs/glu-9.0.1','media-libs/imlib2-1.7.1','media-libs/libepoxy-1.5.5','media-libs/libglvnd-1.3.2-r2','media-libs/libid3tag-0.15.1b-r4','media-libs/libjpeg-turbo-2.0.6','media-libs/libpng-1.6.37-r2','media-libs/tiff-4.2.0','net-analyzer/mtr-0.94','net-analyzer/nmap-7.91-r1','net-dns/avahi-0.8-r2','net-dns/libidn2-2.3.0','net-firewall/iptables-1.8.7','net-libs/gnutls-3.6.15','net-libs/libmnl-1.0.4','net-libs/libnsl-1.3.0-r1','net-libs/libpcap-1.10.0','net-libs/libssh2-1.9.0_p20200614','net-libs/rpcsvc-proto-1.4.2','net-misc/dhcpcd-9.4.0','net-misc/iputils-20210202','net-misc/keychain-2.8.5','net-misc/netifrc-0.7.3','net-misc/openssh-8.4_p1-r3','net-misc/rsync-3.2.3-r1','net-misc/sntpd-3.0-r1','net-misc/wget-1.21.1','perl-core/File-Temp-0.230.900','sys-apps/acl-2.2.53-r1','sys-apps/baselayout-2.7-r1','sys-apps/busybox-1.33.0','sys-apps/coreutils-8.32-r1','sys-apps/debianutils-4.11.2','sys-apps/diffutils-3.7-r1','sys-apps/fbset-2.1','sys-apps/file-5.39-r3','sys-apps/findutils-4.8.0','sys-apps/gawk-5.1.0','sys-apps/grep-3.6','sys-apps/groff-1.22.4','sys-apps/help2man-1.48.1','sys-apps/hwids-20201207','sys-apps/install-xattr-0.8','sys-apps/iproute2-5.10.0','sys-apps/kbd-2.4.0','sys-apps/kmod-28','sys-apps/less-563-r1','sys-apps/man-db-2.9.4','sys-apps/man-pages-5.10','sys-apps/man-pages-posix-2017a','sys-apps/mlocate-0.26-r3','sys-apps/net-tools-2.10','sys-apps/openrc-0.42.1-r1','sys-apps/opentmpfiles-0.2','sys-apps/pciutils-3.7.0','sys-apps/sandbox-2.20','sys-apps/sed-4.8','sys-apps/sysvinit-2.98-r1','sys-apps/texinfo-6.7','sys-apps/util-linux-2.36.2','sys-apps/which-2.21','sys-auth/nss-mdns-0.14.1','sys-auth/passwdqc-1.4.0-r1','sys-block/parted-3.4','sys-boot/efibootmgr-17','sys-devel/autoconf-2.69-r5','sys-devel/autoconf-2.13-r1','sys-devel/autoconf-archive-2019.01.06','sys-devel/autoconf-wrapper-13-r1','sys-devel/automake-1.16.3-r1','sys-devel/automake-wrapper-11','sys-devel/bc-1.07.1-r3','sys-devel/binutils-2.35.2','sys-devel/binutils-config-5.3.2','sys-devel/flex-2.6.4-r1','sys-devel/gcc-10.2.0-r5','sys-devel/gcc-config-2.3.3','sys-devel/gettext-0.21','sys-devel/gnuconfig-20210107','sys-devel/libtool-2.4.6-r6','sys-devel/llvm-11.0.1','sys-devel/llvm-common-11.0.1','sys-devel/m4-1.4.18-r1','sys-devel/make-4.3','sys-devel/patch-2.7.6-r4','sys-devel/prelink-20151030-r1','sys-fs/dosfstools-4.2','sys-fs/eudev-3.2.10','sys-fs/fuse-2.9.9-r1','sys-fs/fuse-common-3.10.1','sys-fs/udev-init-scripts-34','sys-kernel/installkernel-gentoo-2','sys-kernel/linux-headers-5.10','sys-libs/e2fsprogs-libs-1.46.1','sys-libs/efivar-37','sys-libs/glibc-2.32-r7','sys-libs/gpm-1.20.7-r2','sys-libs/libcap-2.48','sys-libs/libtermcap-compat-2.0.8-r4','sys-libs/libunwind-1.5.0-r1','sys-libs/libutempter-1.2.1','sys-libs/mtdev-1.1.6','sys-libs/ncurses-6.2_p20210123','sys-libs/ncurses-compat-6.2','sys-libs/pam-1.5.1','sys-libs/readline-8.1','sys-libs/timezone-data-2021a','sys-libs/zlib-1.2.11-r3','sys-process/cronbase-0.3.7-r6','sys-process/cronie-1.5.5-r1','sys-process/htop-3.0.5','sys-process/parallel-20210122','sys-process/procps-3.3.17','sys-process/psmisc-23.4','virtual/acl-0-r2','virtual/awk-1','virtual/cron-0-r2','virtual/dev-manager-0-r2','virtual/editor-0-r3','virtual/glu-9.0-r2','virtual/jpeg-100','virtual/libc-1-r1','virtual/libelf-3','virtual/libiconv-0-r2','virtual/libintl-0-r2','virtual/libudev-232-r3','virtual/logger-0-r1','virtual/man-0-r4','virtual/mta-1-r1','virtual/opengl-7.0-r2','virtual/os-headers-0-r2','virtual/package-manager-1','virtual/pager-0','virtual/perl-Carp-1.500.0-r3','virtual/perl-Compress-Raw-Bzip2-2.93.0','virtual/perl-Compress-Raw-Zlib-2.93.0','virtual/perl-CPAN-Meta-2.150.10-r4','virtual/perl-CPAN-Meta-YAML-0.18.0-r6','virtual/perl-Digest-SHA-6.20.0-r1','virtual/perl-Encode-3.60.0','virtual/perl-ExtUtils-CBuilder-0.280.234','virtual/perl-ExtUtils-Install-2.140.0-r3','virtual/perl-ExtUtils-Manifest-1.720.0-r1','virtual/perl-ExtUtils-ParseXS-3.400.0-r1','virtual/perl-File-Path-2.160.0-r1','virtual/perl-File-Spec-3.780.0-r1','virtual/perl-File-Temp-0.230.900','virtual/perl-Getopt-Long-2.510.0','virtual/perl-IO-1.430.0','virtual/perl-IO-Compress-2.93.0','virtual/perl-IO-Socket-IP-0.390.0-r3','virtual/perl-JSON-PP-4.40.0','virtual/perl-libnet-3.110.0-r4','virtual/perl-MIME-Base64-3.150.0-r7','virtual/perl-Module-Metadata-1.0.37','virtual/perl-parent-0.238.0','virtual/perl-Parse-CPAN-Meta-2.150.10-r4','virtual/perl-Perl-OSType-1.10.0-r4','virtual/perl-Pod-Parser-1.630.0-r8','virtual/perl-podlators-4.140.0','virtual/perl-Socket-2.29.0','virtual/perl-Storable-3.210.0','virtual/perl-Test-Harness-3.420.0-r3','virtual/perl-Text-ParseWords-3.300.0-r7','virtual/perl-Time-Local-1.280.0-r1','virtual/perl-version-0.992.400-r1','virtual/perl-XSLoader-0.300.0-r3','virtual/pkgconfig-2','virtual/service-manager-1','virtual/ssh-0','virtual/tmpfiles-0-r1','virtual/ttf-fonts-1-r1','virtual/udev-217-r2','virtual/yacc-0','x11-apps/bdftopcf-1.1','x11-apps/iceauth-1.0.8-r1','x11-apps/luit-20190106','x11-apps/mkfontscale-1.2.1','x11-apps/rgb-1.0.6-r1','x11-apps/setxkbmap-1.3.2','x11-apps/xauth-1.1','x11-apps/xinit-1.4.1-r1','x11-apps/xkbcomp-1.4.4','x11-apps/xmessage-1.0.5-r1','x11-apps/xrandr-1.5.1','x11-apps/xrdb-1.2.0','x11-base/xcb-proto-1.14.1','x11-base/xorg-drivers-1.20-r2','x11-base/xorg-proto-2020.1','x11-base/xorg-server-1.20.10-r3','x11-drivers/xf86-input-evdev-2.10.6','x11-drivers/xf86-input-vmmouse-13.1.0-r1','x11-drivers/xf86-video-vesa-2.5.0','x11-drivers/xf86-video-vmware-13.3.0','x11-libs/cairo-1.16.0-r4','x11-libs/gdk-pixbuf-2.42.2','x11-libs/libfontenc-1.1.4','x11-libs/libICE-1.0.10','x11-libs/libpciaccess-0.16','x11-libs/libSM-1.2.3-r1','x11-libs/libX11-1.7.0','x11-libs/libXau-1.0.9-r1','x11-libs/libXaw-1.0.13-r2','x11-libs/libxcb-1.14','x11-libs/libXdmcp-1.1.3','x11-libs/libXext-1.3.4','x11-libs/libXfixes-5.0.3-r3','x11-libs/libXfont2-2.0.4','x11-libs/libXft-2.3.3','x11-libs/libXi-1.7.10','x11-libs/libxkbfile-1.1.0','x11-libs/libXmu-1.1.3','x11-libs/libXpm-3.5.13','x11-libs/libXrandr-1.5.2','x11-libs/libXrender-0.9.10-r2','x11-libs/libxshmfence-1.3-r2','x11-libs/libXt-1.2.1','x11-libs/libXxf86vm-1.1.4-r2','x11-libs/pango-1.42.4-r2','x11-libs/pixman-0.40.0','x11-libs/xtrans-1.4.0','x11-misc/compose-tables-1.7.0','x11-misc/shared-mime-info-2.1','x11-misc/util-macros-1.19.3','x11-misc/xbitmaps-1.1.2-r1','x11-misc/xkeyboard-config-2.31','x11-terms/xterm-366','x11-wm/fluxbox-1.3.7-r4' ]).
