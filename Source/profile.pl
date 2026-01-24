/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROFILE
Gentoo profile reader for portage-ng.

This module reads a Gentoo profile directory from the Portage tree (including
inherited profiles via the `parent` file) and extracts *global* USE settings:

- make.defaults (USE, USE_EXPAND, and USE_EXPAND values)
- use.mask / use.force

It can produce `preference:profile_use/1` terms, ready to be imported in
portage-ng (e.g. written to a .pl file).

Scope / limitations (intentional, first cut):
- Only global USE is handled (no package.use / package.use.mask / package.use.force).
- Only USE masking/forcing is handled (package.mask etc. are not applied here).
*/

:- module(profile,
          [ profile_use_terms/2,          % +ProfileRel, -Terms
            write_profile_use_file/0,     % write to Source/Private/profile_use_generated.pl
            write_profile_use_file/1      % +File
          ]).

:- use_module(library(readutil)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(ordsets)).

:- use_module(portage('Source/os.pl')).
:- use_module(portage('Source/config.pl')).


%! profile_use_terms(+ProfileRel, -Terms:list)
%
% Compute a list of preference:profile_use/1 terms for the given profile path
% relative to the profiles root (e.g. 'default/linux/amd64/23.0/split-usr/no-multilib').
%
% Terms are *normalized* so a flag appears at most once, as either:
%   - preference:profile_use(Flag)
%   - preference:profile_use(minus(Flag))
%
profile_use_terms(ProfileRel, Terms) :-
  profile_dirs(ProfileRel, Dirs),
  profile_collect(Dirs, Data),
  profile_finalize(Data, Terms).


%! write_profile_use_file
%
% Writes computed profile_use terms to Source/Private/profile_use_generated.pl
% under the installation directory.
%
write_profile_use_file :-
  config:installation_dir(Root),
  os:compose_path([Root,'Source/Private/profile_use_generated.pl'], File),
  write_profile_use_file(File).


%! write_profile_use_file(+File)
%
% Write computed profile_use terms to File.
%
% The selected profile comes from config:gentoo_profile/1.
%
write_profile_use_file(File) :-
  ( config:gentoo_profile(ProfileRel) -> true
  ; throw(error(existence_error(predicate, config:gentoo_profile/1), profile:write_profile_use_file/1))
  ),
  profile_use_terms(ProfileRel, Terms),
  file_directory_name(File, Dir),
  os:ensure_directory_path(Dir),
  setup_call_cleanup(
    open(File, write, Out, [encoding(utf8)]),
    ( format(Out, '/* Auto-generated from Gentoo profile~n', []),
      format(Out, '   profile: ~w~n', [ProfileRel]),
      format(Out, '*/~n~n', []),
      forall(member(T, Terms),
             format(Out, '~q.~n', [T]))
    ),
    close(Out)
  ).


% -----------------------------------------------------------------------------
% Internal: resolve profile inheritance chain
% -----------------------------------------------------------------------------

profiles_root(ProfilesRoot) :-
  % Resolve Portage tree location from the configured repository instance.
  % (Host config registers `portage` repository.)
  portage:get_location(PortageRoot),
  os:compose_path(PortageRoot, 'profiles', ProfilesRoot).

profile_dir(ProfileRel, Dir) :-
  profiles_root(Root),
  os:compose_path(Root, ProfileRel, Dir).

profile_dirs(ProfileRel, Dirs) :-
  profile_dir(ProfileRel, LeafDir),
  profile_dirs_from_dir(LeafDir, [], Rev),
  reverse(Rev, Dirs).

profile_dirs_from_dir(Dir, Seen, Seen) :-
  memberchk(Dir, Seen),
  !.
profile_dirs_from_dir(Dir, Seen0, Seen) :-
  parent_file(Dir, ParentFile),
  ( exists_file(ParentFile) ->
      read_file_to_string(ParentFile, S, []),
      split_string(S, "\n", "\r\n\t ", Lines0),
      exclude(profile_comment_or_empty, Lines0, Lines),
      foldl(profile_parent_dir(Dir), Lines, Seen0, Seen1),
      Seen = [Dir|Seen1]
  ; Seen = [Dir|Seen0]
  ).

parent_file(Dir, ParentFile) :-
  os:compose_path(Dir, 'parent', ParentFile).

profile_comment_or_empty(Line) :-
  Line == '' ;
  sub_string(Line, 0, 1, _, "#").

profile_parent_dir(ChildDir, ParentRel0, Seen0, Seen) :-
  % Parent entries are paths relative to the current profile dir.
  normalize_space(string(ParentRel), ParentRel0),
  ( ParentRel == '' ->
      Seen = Seen0
  ; directory_file_path(ChildDir, ParentRel, ParentDir0),
    absolute_file_name(ParentDir0, ParentDir, [file_type(directory), access(read)]),
    profile_dirs_from_dir(ParentDir, Seen0, Seen)
  ).


% -----------------------------------------------------------------------------
% Internal: parse profile files
% -----------------------------------------------------------------------------

profile_collect(Dirs, st(Enabled, Disabled, Force, Mask)) :-
  foldl(profile_collect_dir, Dirs, st([], [], [], []), st(Enabled, Disabled, Force, Mask)).

profile_collect_dir(Dir, st(E0, D0, F0, M0), st(E, D, F, M)) :-
  parse_make_defaults_ops(Dir, UseOps),
  apply_default_use_ops(UseOps, E0, D0, E1, D1),
  parse_use_op_file(Dir, 'use.force', ForceOps),
  apply_set_ops(ForceOps, F0, F),
  parse_use_op_file(Dir, 'use.mask', MaskOps),
  apply_set_ops(MaskOps, M0, M),
  E = E1, D = D1.

parse_make_defaults_ops(Dir, Ops) :-
  os:compose_path(Dir, 'make.defaults', File),
  ( exists_file(File) ->
      read_file_to_string(File, S, []),
      make_defaults_kv(S, KV),
      % USE
      ( kv_get_join(KV, 'USE', UseStr) ->
          parse_default_use_ops(UseStr, Ops1)
      ; Ops1 = []
      ),
      % USE_EXPAND and corresponding vars
      ( kv_get_join(KV, 'USE_EXPAND', ExpandStr) ->
          split_string(ExpandStr, " ", "\t\r\n ", ExpandVars0),
          exclude(=(""), ExpandVars0, ExpandVars),
          findall(op(add, Flag),
                  ( member(VarS, ExpandVars),
                    string_upper(VarS, VarU0),
                    atom_string(VarA, VarU0),
                    ( kv_get_join(KV, VarA, ValStr) ->
                        use_expand_flag(VarA, ValStr, Flag)
                    ; fail
                    )
                  ),
                  ExpandOps0),
          append(Ops1, ExpandOps0, Ops2),
          Ops = Ops2
      ; Ops = Ops1
      )
  ; Ops = []
  ).

parse_use_op_file(Dir, Basename, Ops) :-
  os:compose_path(Dir, Basename, File),
  ( exists_file(File) ->
      read_file_to_string(File, S, []),
      split_string(S, "\n", "\r\n\t ", Lines0),
      exclude(profile_comment_or_empty, Lines0, Lines),
      findall(Op,
              ( member(L, Lines),
                split_string(L, " ", "\t ", Words0),
                member(W0, Words0),
                W0 \== "",
                valid_use_token(W0),
                ( sub_string(W0, 0, 1, _, "-") ->
                    strip_leading_dashes(W0, Name),
                    Name \== "",
                    atom_string(Flag, Name),
                    Op = op(del, Flag)         % '-' in use.mask/use.force means "remove from set"
                ; atom_string(Flag, W0),
                  Op = op(add, Flag)
                )
              ),
              Ops)
  ; Ops = []
  ).

make_defaults_kv(S, KV) :-
      split_string(S, "\n", "\r\n", Lines0),
  findall(K-V,
          ( member(Line0, Lines0),
            normalize_space(string(Line1), Line0),
            Line1 \== "",
            \+ sub_string(Line1, 0, 1, _, "#"),
            % drop leading 'export '
            ( sub_string(Line1, 0, 7, _, "export ") ->
                sub_string(Line1, 7, _, 0, Line)
            ; Line = Line1
            ),
            % split at first '='
            sub_string(Line, Before, 1, After, "="),
            sub_string(Line, 0, Before, _, K0),
            sub_string(Line, _, After, 0, V0),
            normalize_space(string(K1), K0),
            normalize_space(string(V1), V0),
            strip_key_operator(K1, K1Base),
            valid_key_string(K1Base),
            unquote(V1, V2),
            string_upper(K1Base, KuStr),
            atom_string(K, KuStr),
            V = V2
          ),
          Pairs),
  dict_create(KV0, kv, []),
  foldl(kv_add, Pairs, KV0, KV).

valid_key_string(K1) :-
  % Keep this conservative: only accept typical variable names.
  string_codes(K1, Cs),
  Cs \== [],
  forall(member(C, Cs),
         ( code_type(C, alnum)
         ; C =:= 0'_
         )).

% Handle make.defaults assignment operators like:
%   USE+=...
%   USE_EXPAND+=...
%   VAR?=...
%   VAR:=...
% We already split at the first '=', so the operator (if present) is the last
% character of the key string.
strip_key_operator(K0, K) :-
  ( sub_string(K0, 0, L, 0, K),
    L > 0,
    sub_string(K0, L, 1, 0, Op),
    member(Op, ["+","?",":"])
  -> true
  ; K = K0
  ).

kv_add(K-V, KV0, KV) :-
  ( get_dict(K, KV0, Vs0) ->
      append(Vs0, [V], Vs),
      put_dict(K, KV0, Vs, KV)
  ; put_dict(K, KV0, [V], KV)
  ).

kv_get_join(KV, Key, Joined) :-
  get_dict(Key, KV, Vs),
  Vs \== [],
  maplist(atom_string, As, Vs),
  atomic_list_concat(As, ' ', Atom),
  atom_string(Atom, Joined).

unquote(S0, S) :-
  string_length(S0, L),
  ( L >= 2,
    sub_string(S0, 0, 1, _, Q),
    (Q == "\"" ; Q == "'" ),
    L1 is L - 1,
    sub_string(S0, L1, 1, 0, Q) ->
      L2 is L - 2,
      sub_string(S0, 1, L2, 1, S)
  ; S = S0
  ).

parse_default_use_ops(S, Ops) :-
  split_string(S, " ", "\t\r\n ", Parts0),
  exclude(=(""), Parts0, Parts),
  findall(Op,
          ( member(P0, Parts),
            valid_use_token(P0),
            normalize_space(string(P), P0),
            ( sub_string(P, 0, 1, _, "-") ->
                strip_leading_dashes(P, Name),
                Name \== "",
                atom_string(Flag, Name),
                Op = op(del, Flag)
            ; atom_string(Flag, P),
              Op = op(add, Flag)
            )
          ),
          Ops).

valid_use_token(P) :-
  % Ignore shell placeholders and wildcard markers from make.defaults
  \+ sub_string(P, _, _, _, "$"),
  \+ sub_string(P, _, _, _, "{"),
  \+ sub_string(P, _, _, _, "}"),
  \+ sub_string(P, _, _, _, "*"),
  \+ sub_string(P, _, _, _, "="),
  \+ sub_string(P, 0, 2, _, "||"),
  \+ sub_string(P, 0, 1, _, "("),
  \+ sub_string(P, 0, 1, _, ")"),
  % and ignore empty after trimming
  normalize_space(string(P1), P),
  P1 \== "".

strip_leading_dashes(P0, Name) :-
  % Portage profiles sometimes use patterns like "--foo" in incremental vars.
  % Treat any leading '-' as negation marker(s).
  ( sub_string(P0, 0, 1, Rest, "-") ->
      sub_string(P0, 1, Rest, 0, P1),
      strip_leading_dashes(P1, Name)
  ; Name = P0
  ).
use_expand_flag(VarU, ValStr, Flag) :-
  % VarU is e.g. 'VIDEO_CARDS'
  atom(VarU),
  atom_string(VarU, VarUStr),
  split_string(ValStr, " ", "\t\r\n ", Parts0),
  member(P, Parts0),
  P \== "",
  string_lower(VarUStr, VarLower0),
  % Portage uses lowercased prefix with '_' (e.g. video_cards_vmware)
  atom_string(VarLower, VarLower0),
  atom_string(Token, P),
  atomic_list_concat([VarLower, Token], '_', Flag).

apply_default_use_ops([], E, D, E, D).
apply_default_use_ops([op(add, Flag)|Ops], E0, D0, E, D) :-
  ord_add_element(E0, Flag, E1),
  ord_del_element(D0, Flag, D1),
  apply_default_use_ops(Ops, E1, D1, E, D).
apply_default_use_ops([op(del, Flag)|Ops], E0, D0, E, D) :-
  ord_del_element(E0, Flag, E1),
  ord_add_element(D0, Flag, D1),
  apply_default_use_ops(Ops, E1, D1, E, D).

apply_set_ops([], S, S).
apply_set_ops([op(add, Flag)|Ops], S0, S) :-
  ord_add_element(S0, Flag, S1),
  apply_set_ops(Ops, S1, S).
apply_set_ops([op(del, Flag)|Ops], S0, S) :-
  ord_del_element(S0, Flag, S1),
  apply_set_ops(Ops, S1, S).


% -----------------------------------------------------------------------------
% Internal: normalize to preference:profile_use/1 terms
% -----------------------------------------------------------------------------

profile_finalize(st(Enabled0, Disabled0, Force0, Mask0), Terms) :-
  sort(Enabled0, Enabled),
  sort(Disabled0, Disabled),
  sort(Force0, Force),
  sort(Mask0, Mask),
  % Apply mask/force precedence on defaults.
  ord_subtract(Enabled, Mask, Enabled1),
  ord_union(Enabled1, Force, EnabledFinal),
  ord_subtract(Disabled, Force, Disabled1),
  ord_union(Disabled1, Mask, Disabled2),
  ord_subtract(Disabled2, EnabledFinal, DisabledFinal),
  findall(preference:profile_use(Flag), member(Flag, EnabledFinal), EnabledTerms),
  findall(preference:profile_use(minus(Flag)), member(Flag, DisabledFinal), DisabledTerms),
  append(EnabledTerms, DisabledTerms, Terms).

