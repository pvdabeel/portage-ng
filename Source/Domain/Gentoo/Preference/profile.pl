/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROFILE
Pure I/O layer: reads the Gentoo profile tree and provides cache
serialization.

This module reads a Gentoo profile directory from the Portage tree (including
inherited profiles via the `parent` file) and extracts USE settings, masks,
per-package USE, and license groups.  It performs no policy decisions; the
results are consumed by preference.pl which controls layering and precedence.

During `--sync`, `profile:cache_save/0` serializes parsed profile data to
`Knowledge/profile.qlf`.  At startup, `preference:init` can load the
pre-parsed cache instead of re-walking the profile tree, controlled by the
per-mode `config:profile_loading/2` setting.
*/

:- module(profile, []).

% =============================================================================
%  PROFILE declarations
% =============================================================================

% =============================================================================
%  I. Profile tree reader — public API
% =============================================================================

%! profile:profile_use_terms(+ProfileRel, -Terms:list)
%
% Compute a list of preference:profile_use/1 terms for the given profile path
% relative to the profiles root (e.g. 'default/linux/amd64/23.0/split-usr/no-multilib').
%
% Terms are *normalized* so a flag appears at most once, as either:
%   - preference:profile_use(Flag)
%   - preference:profile_use(minus(Flag))

profile:profile_use_terms(ProfileRel, Terms) :-
  profile:profile_dirs(ProfileRel, Dirs),
  profile:profile_collect(Dirs, Data),
  profile:profile_finalize(Data, Terms).


%! profile:profile_use_mask(+ProfileRel, -MaskedFlags:list)
%
% Return the effective global use.mask set for the profile chain rooted
% at ProfileRel.  Useful for Portage-like display markers (e.g. '%').

profile:profile_use_mask(ProfileRel, Mask) :-
  profile:profile_dirs(ProfileRel, Dirs),
  profile:profile_collect(Dirs, st(_Enabled,_Disabled,_Force,Mask)),
  !.


%! profile:profile_use_force(+ProfileRel, -ForcedFlags:list)
%
% Return the effective global use.force set for the profile chain rooted
% at ProfileRel.

profile:profile_use_force(ProfileRel, Force) :-
  profile:profile_dirs(ProfileRel, Dirs),
  profile:profile_collect(Dirs, st(_Enabled,_Disabled,Force,_Mask)),
  !.


%! profile:profile_package_mask_atoms(+ProfileRel, -Atoms:list)
%
% Collect raw package.mask atoms from the selected profile (including parents),
% plus the global masks/unmasks from the Portage tree.
%
% Notes:
% - This is intentionally *minimal* and only returns raw atoms as strings/atoms.
% - We include unmask operations by returning them as '-atom' entries, matching
%   Portage's incremental semantics and the consumer logic in preference.pl.

profile:profile_package_mask_atoms(ProfileRel, Atoms) :-
  profile:profile_dirs(ProfileRel, Dirs),
  findall(A,
          ( % Global masks (apply to all profiles)
            profile:global_package_mask_file(File),
            exists_file(File),
            profile:profile_read_atoms_file(File, As),
            member(A, As)
          ; % Global unmasks (apply to all profiles)
            profile:global_package_unmask_file(File),
            exists_file(File),
            profile:profile_read_atoms_file(File, As0),
            member(A0, As0),
            atom_concat('-', A0, A)
          ; % Profile chain masks/unmasks (root -> leaf, preserving order)
            member(Dir, Dirs),
            ( profile:package_mask_file(Dir, File),
              exists_file(File),
              profile:profile_read_atoms_file(File, As),
              member(A, As)
            ; profile:package_unmask_file(Dir, File),
              exists_file(File),
              profile:profile_read_atoms_file(File, As0),
              member(A0, As0),
              atom_concat('-', A0, A)
            )
          ),
          Atoms0),
  % IMPORTANT: keep order.
  %
  % Gentoo profiles use incremental semantics for package.mask, including
  % unmasking with '-cat/pkg' in child profiles. Order is therefore significant:
  % later entries (closer to the leaf profile) override earlier ones.
  %
  % Do NOT sort/dedupe here; consumers (preference:init) apply the operations
  % sequentially.
  %
  % Exclude empty atoms (can occur from malformed or empty lines in mask files).
  exclude(==(''), Atoms0, Atoms).


% =============================================================================
%  I.b  @system set — profile `packages` file reader
% =============================================================================

%! profile:system_packages(+ProfileRel, -Packages:list) is det.
%
% Collect @system package atoms from the `packages` files across the
% full profile inheritance chain for ProfileRel.  Only lines prefixed
% with `*` are included (per Gentoo PMS).  Version/slot constraints
% are stripped so the result is a list of Category-Name pairs.

profile:system_packages(ProfileRel, Packages) :-
  profile:profile_dirs(ProfileRel, Dirs),
  findall(Cat-Name,
          ( member(Dir, Dirs),
            os:compose_path(Dir, 'packages', File),
            exists_file(File),
            catch(read_file_to_string(File, S, []), _, fail),
            split_string(S, "\n", "\r\n", Lines),
            member(L0, Lines),
            profile:profile_strip_comment(L0, L1),
            normalize_space(string(L2), L1),
            L2 \== "",
            sub_string(L2, 0, 1, _, "*"),
            sub_string(L2, 1, _, 0, AtomStr0),
            normalize_space(string(AtomStr), AtomStr0),
            AtomStr \== "",
            profile:parse_system_atom(AtomStr, Cat, Name)
          ),
          Packages0),
  sort(Packages0, Packages).


%! profile:parse_system_atom(+AtomStr, -Category, -Name) is semidet.
%
% Parse a package atom string from a profile `packages` file into
% Category and Name, stripping version constraints and slot specs.

profile:parse_system_atom(AtomStr, Cat, Name) :-
  atom_string(Atom0, AtomStr),
  profile:strip_version_prefix(Atom0, Atom1),
  profile:strip_slot(Atom1, Atom2),
  profile:strip_version_suffix(Atom2, CatName),
  atomic_list_concat([Cat, Name], '/', CatName),
  Cat \== '',
  Name \== ''.


%! profile:strip_version_prefix(+Atom0, -Atom) is det.
%
% Remove leading version operators (>=, <=, >, <, =, ~).

profile:strip_version_prefix(Atom0, Atom) :-
  atom_string(Atom0, S0),
  ( sub_string(S0, 0, 2, _, ">=") -> sub_string(S0, 2, _, 0, S)
  ; sub_string(S0, 0, 2, _, "<=") -> sub_string(S0, 2, _, 0, S)
  ; sub_string(S0, 0, 1, _, ">")  -> sub_string(S0, 1, _, 0, S)
  ; sub_string(S0, 0, 1, _, "<")  -> sub_string(S0, 1, _, 0, S)
  ; sub_string(S0, 0, 1, _, "=")  -> sub_string(S0, 1, _, 0, S)
  ; sub_string(S0, 0, 1, _, "~")  -> sub_string(S0, 1, _, 0, S)
  ; S = S0
  ),
  atom_string(Atom, S).


%! profile:strip_slot(+Atom0, -Atom) is det.
%
% Remove slot specification (:SLOT) from a package atom.

profile:strip_slot(Atom0, Atom) :-
  atom_string(Atom0, S0),
  ( sub_string(S0, Before, _, _, ":") ->
      sub_string(S0, 0, Before, _, S)
  ; S = S0
  ),
  atom_string(Atom, S).


%! profile:strip_version_suffix(+Atom0, -CatName) is det.
%
% Given a cat/name-version atom, extract just cat/name by splitting
% at the last hyphen followed by a digit.

profile:strip_version_suffix(Atom0, CatName) :-
  atom_string(Atom0, S0),
  string_codes(S0, Codes),
  ( profile:last_version_split(Codes, 0, -1, SplitPos),
    SplitPos > 0 ->
      sub_string(S0, 0, SplitPos, _, S)
  ; S = S0
  ),
  atom_string(CatName, S).


%! profile:last_version_split(+Codes, +Pos, +LastSplit, -SplitPos) is det.
%
% Find the position of the last '-' followed by a digit in the code list.

profile:last_version_split([], _, Split, Split).

profile:last_version_split([0'-,D|Rest], Pos, _, Split) :-
  code_type(D, digit), !,
  Pos1 is Pos + 2,
  profile:last_version_split(Rest, Pos1, Pos, Split).

profile:last_version_split([_|Rest], Pos, Acc, Split) :-
  Pos1 is Pos + 1,
  profile:last_version_split(Rest, Pos1, Acc, Split).


% =============================================================================
%  II. Profile inheritance chain
% =============================================================================

%! profile:profiles_root(-ProfilesRoot) is det
%
% Resolve the absolute path to the profiles/ directory inside the
% configured Portage tree.

profile:profiles_root(ProfilesRoot) :-
  portage:get_location(PortageRoot),
  os:compose_path(PortageRoot, 'profiles', ProfilesRoot).


%! profile:profile_dir(+ProfileRel, -Dir) is det
%
% Map a profile-relative path to its absolute directory.

profile:profile_dir(ProfileRel, Dir) :-
  profile:profiles_root(Root),
  os:compose_path(Root, ProfileRel, Dir).


%! profile:profile_dirs(+ProfileRel, -Dirs:list) is det
%
% Compute the full profile inheritance chain (root-first) for ProfileRel
% by following `parent` files recursively.

profile:profile_dirs(ProfileRel, Dirs) :-
  profile:profile_dir(ProfileRel, LeafDir),
  profile:profile_dirs_from_dir(LeafDir, [], Rev),
  reverse(Rev, Dirs).


%! profile:profile_dirs_from_dir(+Dir, +Seen0, -Seen) is det
%
% Recursive worker for profile_dirs/2.  Follows `parent` file entries
% and falls back to implicit filesystem-parent inheritance when no
% `parent` file exists but the parent directory looks like a valid profile.

profile:profile_dirs_from_dir(Dir, Seen, Seen) :-
  memberchk(Dir, Seen),
  !.
profile:profile_dirs_from_dir(Dir, Seen0, Seen) :-
  profile:parent_file(Dir, ParentFile),
  ( exists_file(ParentFile) ->
      read_file_to_string(ParentFile, S, []),
      split_string(S, "\n", "\r\n\t ", Lines0),
      exclude(profile:profile_comment_or_empty, Lines0, Lines),
      foldl(profile:profile_parent_dir(Dir), Lines, Seen0, Seen1),
      Seen = [Dir|Seen1]
  ; % Gentoo profile trees contain some subprofiles without an explicit `parent`
    % file (notably `profiles/arch/<arch>/no-multilib/`). In Portage these
    % directories still inherit from their containing directory.
    %
    % Emulate this by implicitly inheriting from the filesystem parent *if* that
    % parent looks like a real profile directory (has make.defaults or parent).
    ( profile:profile_implicit_parent_dir(Dir, ParentDir) ->
        profile:profile_dirs_from_dir(ParentDir, Seen0, Seen1),
        Seen = [Dir|Seen1]
    ; Seen = [Dir|Seen0]
    )
  ).


%! profile:profile_implicit_parent_dir(+Dir, -ParentDir) is semidet
%
% Compute an implicit parent profile directory for Dir.  Only succeeds
% when the filesystem parent is still inside profiles/ and contains
% make.defaults or a parent file.

profile:profile_implicit_parent_dir(Dir, ParentDir) :-
  directory_file_path(Dir, '..', ParentDir0),
  absolute_file_name(ParentDir0, ParentDir, [file_type(directory), access(read)]),
  profile:profiles_root(Root),
  sub_atom(ParentDir, 0, _, _, Root),
  ParentDir \== Dir,
  ( os:compose_path(ParentDir, 'make.defaults', MD),
    exists_file(MD)
  ; profile:parent_file(ParentDir, PF),
    exists_file(PF)
  ),
  !.


%! profile:parent_file(+Dir, -ParentFile) is det
%
% Path to the `parent` file inside a profile directory.

profile:parent_file(Dir, ParentFile) :-
  os:compose_path(Dir, 'parent', ParentFile).


% -----------------------------------------------------------------------------
%  Profile file path helpers
% -----------------------------------------------------------------------------

%! profile:global_package_mask_file(-File) is det
%
% Path to the tree-wide profiles/package.mask file.

profile:global_package_mask_file(File) :-
  profile:profiles_root(Root),
  os:compose_path(Root, 'package.mask', File).


%! profile:global_package_unmask_file(-File) is det
%
% Path to the tree-wide profiles/package.unmask file.

profile:global_package_unmask_file(File) :-
  profile:profiles_root(Root),
  os:compose_path(Root, 'package.unmask', File).


%! profile:package_mask_file(+Dir, -File) is det
%
% Path to the package.mask file inside a profile directory.

profile:package_mask_file(Dir, File) :-
  os:compose_path(Dir, 'package.mask', File).


%! profile:package_unmask_file(+Dir, -File) is det
%
% Path to the package.unmask file inside a profile directory.

profile:package_unmask_file(Dir, File) :-
  os:compose_path(Dir, 'package.unmask', File).


% -----------------------------------------------------------------------------
%  Line parsing helpers
% -----------------------------------------------------------------------------

%! profile:profile_strip_comment(+S0, -S) is det
%
% Strip '#' comments from a line (Gentoo profile file style).

profile:profile_strip_comment(S0, S) :-
  ( sub_string(S0, Before, _, _, "#") ->
      sub_string(S0, 0, Before, _, S)
  ; S = S0
  ).


%! profile:profile_comment_or_empty(+Line) is semidet
%
% Succeeds when Line is empty or starts with '#'.

profile:profile_comment_or_empty(Line) :-
  Line == '' ;
  sub_string(Line, 0, 1, _, "#").


%! profile:profile_parent_dir(+ChildDir, +ParentRel0, +Seen0, -Seen) is det
%
% Resolve a single parent-relative path from a `parent` file entry and
% recurse into its profile chain.  Used as foldl/4 goal.

profile:profile_parent_dir(ChildDir, ParentRel0, Seen0, Seen) :-
  normalize_space(string(ParentRel), ParentRel0),
  ( ParentRel == '' ->
      Seen = Seen0
  ; directory_file_path(ChildDir, ParentRel, ParentDir0),
    absolute_file_name(ParentDir0, ParentDir, [file_type(directory), access(read)]),
    profile:profile_dirs_from_dir(ParentDir, Seen0, Seen)
  ).


% =============================================================================
%  III. USE flag collection and finalization
% =============================================================================

%! profile:profile_read_atoms_file(+File, -Atoms:list) is det
%
% Read a package.mask / package.unmask style file and return its atoms
% in order, preserving leading '-' for incremental unmask operations.

profile:profile_read_atoms_file(File, Atoms) :-
  read_file_to_string(File, S, []),
  split_string(S, "\n", "\r\n", Lines0),
  findall(A,
          ( member(L0, Lines0),
            profile:profile_strip_comment(L0, L1),
            normalize_space(string(L), L1),
            L \== '',
            \+ profile:profile_comment_or_empty(L),
            atom_string(A, L)
          ),
          Atoms).


%! profile:profile_collect(+Dirs, -Data) is det
%
% Fold over the profile directory chain (root-first) and accumulate
% the enabled/disabled USE flags plus use.force and use.mask sets into
% a st(Enabled, Disabled, Force, Mask) term.

profile:profile_collect(Dirs, st(Enabled, Disabled, Force, Mask)) :-
  foldl(profile:profile_collect_dir, Dirs, st([], [], [], []), st(Enabled, Disabled, Force, Mask)).


%! profile:profile_collect_dir(+Dir, +State0, -State) is det
%
% Process a single profile directory: parse make.defaults for USE ops,
% then parse use.force and use.mask, threading the accumulator state.

profile:profile_collect_dir(Dir, st(E0, D0, F0, M0), st(E, D, F, M)) :-
  profile:parse_make_defaults_ops(Dir, UseOps),
  profile:apply_default_use_ops(UseOps, E0, D0, E1, D1),
  profile:parse_use_op_file(Dir, 'use.force', ForceOps),
  profile:apply_set_ops(ForceOps, F0, F),
  profile:parse_use_op_file(Dir, 'use.mask', MaskOps),
  profile:apply_set_ops(MaskOps, M0, M),
  E = E1, D = D1.


%! profile:parse_make_defaults_ops(+Dir, -Ops:list) is det
%
% Parse make.defaults in Dir and return a list of op(add,Flag) /
% op(del,Flag) terms for USE and USE_EXPAND variables.

profile:parse_make_defaults_ops(Dir, Ops) :-
  os:compose_path(Dir, 'make.defaults', File),
  ( exists_file(File) ->
      read_file_to_string(File, S, []),
      profile:make_defaults_kv(S, KV),
      % USE
      ( profile:kv_get_join(KV, 'USE', UseStr) ->
          profile:parse_default_use_ops(UseStr, Ops1)
      ; Ops1 = []
      ),
      % USE_EXPAND and corresponding vars
      ( profile:kv_get_join(KV, 'USE_EXPAND', ExpandStr) ->
          split_string(ExpandStr, " ", "\t\r\n ", ExpandVars0),
          exclude(=(""), ExpandVars0, ExpandVars),
          findall(op(add, Flag),
                  ( member(VarS, ExpandVars),
                    string_upper(VarS, VarU0),
                    atom_string(VarA, VarU0),
                    ( profile:kv_get_join(KV, VarA, ValStr) ->
                        profile:use_expand_flag(VarA, ValStr, Flag)
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


%! profile:parse_use_op_file(+Dir, +Basename, -Ops:list) is det
%
% Parse a use.mask or use.force file (identified by Basename) in Dir
% and return add/del operations for the flags it lists.

profile:parse_use_op_file(Dir, Basename, Ops) :-
  os:compose_path(Dir, Basename, File),
  ( exists_file(File) ->
      read_file_to_string(File, S, []),
      split_string(S, "\n", "\r\n\t ", Lines0),
      exclude(profile:profile_comment_or_empty, Lines0, Lines),
      findall(Op,
              ( member(L, Lines),
                split_string(L, " ", "\t ", Words0),
                member(W0, Words0),
                W0 \== "",
                profile:valid_use_token(W0),
                ( sub_string(W0, 0, 1, _, "-") ->
                    profile:strip_leading_dashes(W0, Name),
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


% -----------------------------------------------------------------------------
%  make.defaults key-value parser
% -----------------------------------------------------------------------------

%! profile:make_defaults_kv(+S, -KV) is det
%
% Parse a make.defaults string S into a dict mapping upper-cased
% variable names to lists of value strings.  Handles `export`, quoting,
% assignment operators (+=, ?=, :=), and '#' comments.

profile:make_defaults_kv(S, KV) :-
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
            profile:strip_key_operator(K1, K1Base),
            profile:valid_key_string(K1Base),
            profile:unquote(V1, V2),
            string_upper(K1Base, KuStr),
            atom_string(K, KuStr),
            V = V2
          ),
          Pairs),
  dict_create(KV0, kv, []),
  foldl(profile:kv_add, Pairs, KV0, KV).


%! profile:valid_key_string(+K1) is semidet
%
% Succeeds when K1 is a non-empty alphanumeric-or-underscore string
% (a valid make.defaults variable name).

profile:valid_key_string(K1) :-
  string_codes(K1, Cs),
  Cs \== [],
  forall(member(C, Cs),
         ( code_type(C, alnum)
         ; C =:= 0'_
         )).


%! profile:strip_key_operator(+K0, -K) is det
%
% Strip trailing assignment operators (+, ?, :) from a make.defaults
% variable name.  E.g. "USE+" becomes "USE".

profile:strip_key_operator(K0, K) :-
  ( sub_string(K0, 0, L, 0, K),
    L > 0,
    sub_string(K0, L, 1, 0, Op),
    member(Op, ["+","?",":"])
  -> true
  ; K = K0
  ).


%! profile:kv_add(+K-V, +KV0, -KV) is det
%
% Append value V to the list stored under key K in dict KV0.

profile:kv_add(K-V, KV0, KV) :-
  ( get_dict(K, KV0, Vs0) ->
      append(Vs0, [V], Vs),
      put_dict(K, KV0, Vs, KV)
  ; put_dict(K, KV0, [V], KV)
  ).


%! profile:kv_get_join(+KV, +Key, -Joined:string) is semidet
%
% Look up Key in KV dict and join all stored values with spaces.

profile:kv_get_join(KV, Key, Joined) :-
  get_dict(Key, KV, Vs),
  Vs \== [],
  maplist(atom_string, As, Vs),
  atomic_list_concat(As, ' ', Atom),
  atom_string(Atom, Joined).


%! profile:unquote(+S0, -S) is det
%
% Remove matching outer quotes (single or double) from S0.

profile:unquote(S0, S) :-
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


% -----------------------------------------------------------------------------
%  USE token parsing and expansion
% -----------------------------------------------------------------------------

%! profile:parse_default_use_ops(+S, -Ops:list) is det
%
% Parse a USE string from make.defaults into a list of op(add,Flag) /
% op(del,Flag) terms.  Tokens prefixed with '-' produce del operations.

profile:parse_default_use_ops(S, Ops) :-
  split_string(S, " ", "\t\r\n ", Parts0),
  exclude(=(""), Parts0, Parts),
  findall(Op,
          ( member(P0, Parts),
            profile:valid_use_token(P0),
            normalize_space(string(P), P0),
            ( sub_string(P, 0, 1, _, "-") ->
                profile:strip_leading_dashes(P, Name),
                Name \== "",
                atom_string(Flag, Name),
                Op = op(del, Flag)
            ; atom_string(Flag, P),
              Op = op(add, Flag)
            )
          ),
          Ops).


%! profile:valid_use_token(+P) is semidet
%
% Succeeds when P is a genuine USE flag token (not a shell placeholder,
% wildcard, or conditional syntax fragment).

profile:valid_use_token(P) :-
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


%! profile:strip_leading_dashes(+P0, -Name) is det
%
% Strip all leading '-' characters.  Portage profiles sometimes use
% "--foo" in incremental vars; all leading dashes are negation markers.

profile:strip_leading_dashes(P0, Name) :-
  ( sub_string(P0, 0, 1, Rest, "-") ->
      sub_string(P0, 1, Rest, 0, P1),
      profile:strip_leading_dashes(P1, Name)
  ; Name = P0
  ).


%! profile:use_expand_flag(+VarU, +ValStr, -Flag) is nondet
%
% For a USE_EXPAND variable VarU (e.g. 'VIDEO_CARDS') and its value
% string, unify Flag with each expanded flag atom (e.g. video_cards_vmware).

profile:use_expand_flag(VarU, ValStr, Flag) :-
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


% -----------------------------------------------------------------------------
%  Ordered set operations for USE accumulation
% -----------------------------------------------------------------------------

%! profile:apply_default_use_ops(+Ops, +E0, +D0, -E, -D) is det
%
% Apply a list of add/del USE operations to the ordered Enabled/Disabled
% sets.  An `add` moves a flag from Disabled to Enabled; a `del` does
% the reverse.

profile:apply_default_use_ops([], E, D, E, D).
profile:apply_default_use_ops([op(add, Flag)|Ops], E0, D0, E, D) :-
  ord_add_element(E0, Flag, E1),
  ord_del_element(D0, Flag, D1),
  profile:apply_default_use_ops(Ops, E1, D1, E, D).
profile:apply_default_use_ops([op(del, Flag)|Ops], E0, D0, E, D) :-
  ord_del_element(E0, Flag, E1),
  ord_add_element(D0, Flag, D1),
  profile:apply_default_use_ops(Ops, E1, D1, E, D).


%! profile:apply_set_ops(+Ops, +S0, -S) is det
%
% Apply add/del operations to an ordered set (used for use.mask and
% use.force accumulation).

profile:apply_set_ops([], S, S).
profile:apply_set_ops([op(add, Flag)|Ops], S0, S) :-
  ord_add_element(S0, Flag, S1),
  profile:apply_set_ops(Ops, S1, S).
profile:apply_set_ops([op(del, Flag)|Ops], S0, S) :-
  ord_del_element(S0, Flag, S1),
  profile:apply_set_ops(Ops, S1, S).


% -----------------------------------------------------------------------------
%  Finalization: normalize to preference:profile_use/1 terms
% -----------------------------------------------------------------------------

%! profile:profile_finalize(+State, -Terms:list) is det
%
% Convert the accumulated st(Enabled, Disabled, Force, Mask) state into
% a list of preference:profile_use/1 terms.  Applies Portage-like
% precedence: use.mask wins over use.force unless explicitly unmasked
% in a child profile.

profile:profile_finalize(st(Enabled0, Disabled0, Force0, Mask0), Terms) :-
  sort(Enabled0, Enabled),
  sort(Disabled0, Disabled),
  sort(Force0, Force),
  sort(Mask0, Mask),
  % Apply Portage-like precedence.
  %
  % Key point: `use.mask` wins over `use.force` unless explicitly unmasked in a
  % child profile. Gentoo uses this pattern (forced+masked in base, unmask in
  % specific arch/features profiles), e.g. `big-endian`.
  ord_union(Enabled, Force, Enabled1),
  ord_subtract(Enabled1, Mask, EnabledFinal),
  ord_union(Disabled, Mask, Disabled1),
  ord_subtract(Disabled1, EnabledFinal, DisabledFinal),
  findall(preference:profile_use(Flag), member(Flag, EnabledFinal), EnabledTerms),
  findall(preference:profile_use(minus(Flag)), member(Flag, DisabledFinal), DisabledTerms),
  append(EnabledTerms, DisabledTerms, Terms).


% =============================================================================
%  IV. Profile cache — file paths
% =============================================================================
%
%  During --sync, profile:cache_save/0 walks the Gentoo profile tree and
%  serializes the parsed data (USE flags, masks, per-package USE, license
%  groups) to a cache file (Knowledge/profile.qlf).  At startup, preference:init can
%  load the pre-parsed cache instead of re-walking the profile tree,
%  controlled by the per-mode config:profile_loading/2 setting.

%! profile:cache_file(-File) is det.
%
% Returns the path to the profile cache file (Knowledge/profile.qlf) in the
% working directory.

profile:cache_file(File) :-
  working_directory(Cwd, Cwd),
  directory_file_path(Cwd, 'Knowledge/profile.qlf', File).

profile:raw_file(File) :-
  working_directory(Cwd, Cwd),
  directory_file_path(Cwd, 'Knowledge/profile.raw', File).


% =============================================================================
%  V. Cache serialization (called during --sync)
% =============================================================================

%! profile:cache_save is det.
%
% Parse the Gentoo profile tree and serialize all profile-derived data
% to Knowledge/profile.qlf.  Requires config:gentoo_profile/1 to be set.

profile:cache_save :-
  profile:raw_file(RawFile),
  ( current_predicate(config:gentoo_profile/1),
    config:gentoo_profile(ProfileRel) ->
      profile:cache_save_profile(ProfileRel, RawFile)
  ; format(user_error, '% profile:cache_save — no gentoo_profile configured, skipping.~n', [])
  ).

profile:cache_save_profile(ProfileRel, RawFile) :-
  ( catch(profile:profile_use_terms(ProfileRel, UseTerms), _, UseTerms = []) -> true ; UseTerms = [] ),
  ( catch(profile:profile_use_mask(ProfileRel, UseMask), _, UseMask = []) -> true ; UseMask = [] ),
  ( catch(profile:profile_use_force(ProfileRel, UseForce), _, UseForce = []) -> true ; UseForce = [] ),
  ( catch(profile:profile_package_mask_atoms(ProfileRel, PkgMaskAtoms), _, PkgMaskAtoms = []) -> true ; PkgMaskAtoms = [] ),
  profile:collect_profile_package_use(ProfileRel, PkgUseEntries),
  profile:collect_profile_package_use_mask(ProfileRel, PkgUseMaskEntries),
  profile:collect_profile_package_use_force(ProfileRel, PkgUseForceEntries),
  profile:collect_license_groups(LicenseGroups),
  ( catch(profile:system_packages(ProfileRel, SystemPkgs), _, SystemPkgs = []) -> true ; SystemPkgs = [] ),
  setup_call_cleanup(
    open(RawFile, write, Out, [encoding(utf8)]),
    ( format(Out, ':- module(profiledata, []).~n', []),
      format(Out, '% Auto-generated profile cache — do not edit.~n', []),
      format(Out, '% Profile: ~w~n~n', [ProfileRel]),
      format(Out, ':- dynamic entry/3.~n~n', []),
      forall(member(T, UseTerms),
             format(Out, '~q.~n', [entry(use, T, profile)])),
      forall(member(U, UseMask),
             format(Out, '~q.~n', [entry(use, U, masked)])),
      forall(member(U, UseForce),
             format(Out, '~q.~n', [entry(use, U, forced)])),
      forall(member(A, PkgMaskAtoms),
             ( A \== '' -> format(Out, '~q.~n', [entry(package_mask, A, true)]) ; true )),
      forall(member(pkg_use(Spec, Flag, State), PkgUseEntries),
             format(Out, '~q.~n', [entry(package_use, Spec, use(Flag, State))])),
      forall(member(pkg_use_mask(Spec, Flag), PkgUseMaskEntries),
             format(Out, '~q.~n', [entry(package_use_mask, Spec, Flag)])),
      forall(member(pkg_use_force(Spec, Flag), PkgUseForceEntries),
             format(Out, '~q.~n', [entry(package_use_force, Spec, Flag)])),
      forall(member(lic_group(Name, Members), LicenseGroups),
             format(Out, '~q.~n', [entry(license_group, Name, Members)])),
      forall(member(Cat-Name, SystemPkgs),
             format(Out, '~q.~n', [entry(system_pkg, Cat, Name)]))
    ),
    close(Out)
  ),
  catch(qcompile(RawFile), E,
        format(user_error, '% profile:cache_save — qcompile failed: ~w~n', [E])),
  format('% Profile cache saved to Knowledge/profile.qlf~n', []).


% =============================================================================
%  VI. Cache deserialization (called during preference:init)
% =============================================================================

%! profile:cache_load(-UseTerms, -UseMask, -UseForce) is semidet.
%
% Load profile cache and return the USE-related data needed by
% preference:init steps 1-2.  Fails if no cache file exists.

profile:cache_load(UseTerms, UseMask, UseForce) :-
  profile:cache_file(File),
  exists_file(File),
  profile:ensure_loaded_cache(File),
  ( current_predicate(profiledata:entry/3) ->
      findall(T, profiledata:entry(use, T, profile), UseTerms),
      findall(U, profiledata:entry(use, U, masked),  UseMask),
      findall(U, profiledata:entry(use, U, forced),  UseForce)
  ; UseTerms = [], UseMask = [], UseForce = []
  ).


%! profile:apply_cached_profile_data is det.
%
% Apply all cached profile data (masks, per-package USE, license groups)
% from the normalized profiledata:entry/3 store into preference predicates.

profile:apply_cached_profile_data :-
  ( current_predicate(profiledata:entry/3) ->
      forall(profiledata:entry(Type, Key, Value),
             profile:apply_entry(Type, Key, Value))
  ; true
  ).

profile:apply_entry(package_mask, Atom, true) :-
  !,
  ( sub_atom(Atom, 0, 1, _, '-') ->
      sub_atom(Atom, 1, _, 0, Atom1),
      normalize_space(atom(Atom2), Atom1),
      catch(preference:unmask_profile_atom(Atom2), _, true)
  ; catch(preference:mask_profile_atom(Atom), _, true)
  ).

profile:apply_entry(package_use, Spec, use(Flag, State)) :-
  !,
  assertz(preference:local_profile_use_soft(Spec, Flag, State)).

profile:apply_entry(package_use_mask, Spec, Flag) :-
  !,
  assertz(preference:local_profile_use_masked(Spec, Flag)).

profile:apply_entry(package_use_force, Spec, Flag) :-
  !,
  assertz(preference:local_profile_use_forced(Spec, Flag)).

profile:apply_entry(license_group, Name, Members) :-
  !,
  assertz(preference:local_license_group_raw(Name, Members)).

profile:apply_entry(system_pkg, Cat, Name) :-
  !,
  ( preference:system_pkg(Cat, Name) -> true
  ; assertz(preference:system_pkg(Cat, Name))
  ).

profile:apply_entry(_, _, _).


%! profile:cache_available is semidet.
%
% Succeeds when a profile cache file exists and can be loaded.

profile:cache_available :-
  profile:cache_file(File),
  exists_file(File).


% -----------------------------------------------------------------------------
%  Cache loading state
% -----------------------------------------------------------------------------

:- dynamic profile:cache_loaded/0.

profile:ensure_loaded_cache(File) :-
  ( profile:cache_loaded -> true
  ; ensure_loaded(File),
    assertz(profile:cache_loaded)
  ).

profile:reset_cache :-
  retractall(profile:cache_loaded).


% =============================================================================
%  VII. Data collection for cache serialization
% =============================================================================

%! profile:collect_profile_package_use(+ProfileRel, -Entries) is det.
%
% Walk profile dirs and collect per-package USE entries.

profile:collect_profile_package_use(ProfileRel, Entries) :-
  ( current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      findall(pkg_use(Spec, Flag, State),
              ( member(Dir, Dirs),
                profile:collect_package_use_from_dir(Dir, Spec, Flag, State)
              ),
              Entries)
  ; Entries = []
  ).

profile:collect_package_use_from_dir(Dir, Spec, Flag, State) :-
  os:compose_path(Dir, 'package.use', File),
  exists_file(File),
  catch(read_file_to_string(File, S, []), _, fail),
  split_string(S, "\n", "\r\n", Lines0),
  member(L0, Lines0),
  profile:profile_strip_comment(L0, L1),
  normalize_space(string(L2), L1),
  L2 \== "",
  split_string(L2, " ", "\t ", Ws0),
  exclude(=(""), Ws0, Ws),
  Ws = [AtomS|FlagSs],
  FlagSs \== [],
  atom_string(AtomA, AtomS),
  preference:profile_package_use_spec(AtomA, Spec),
  member(FlagS0, FlagSs),
  profile:parse_use_flag(FlagS0, Flag, State).

profile:parse_use_flag(FlagS0, Flag, State) :-
  ( sub_string(FlagS0, 0, 1, _, "-") ->
      sub_string(FlagS0, 1, _, 0, Flag0),
      Flag0 \== "",
      atom_string(Flag, Flag0),
      State = negative
  ; atom_string(Flag, FlagS0),
    State = positive
  ).


%! profile:collect_profile_package_use_mask(+ProfileRel, -Entries) is det.

profile:collect_profile_package_use_mask(ProfileRel, Entries) :-
  profile:collect_profile_package_use_file(ProfileRel, 'package.use.mask', Entries).


%! profile:collect_profile_package_use_force(+ProfileRel, -Entries) is det.

profile:collect_profile_package_use_force(ProfileRel, Entries) :-
  profile:collect_profile_package_use_file(ProfileRel, 'package.use.force', Entries).

profile:collect_profile_package_use_file(ProfileRel, Basename, Entries) :-
  ( current_predicate(profile:profile_dirs/2),
    catch(profile:profile_dirs(ProfileRel, Dirs), _, fail) ->
      findall(Entry,
              ( member(Dir, Dirs),
                os:compose_path(Dir, Basename, File),
                exists_file(File),
                catch(read_file_to_string(File, S, []), _, fail),
                split_string(S, "\n", "\r\n", Lines0),
                member(L0, Lines0),
                profile:profile_strip_comment(L0, L1),
                normalize_space(string(L2), L1),
                L2 \== "",
                split_string(L2, " ", "\t ", Ws0),
                exclude(=(""), Ws0, Ws),
                Ws = [AtomS|FlagSs],
                FlagSs \== [],
                atom_string(AtomA, AtomS),
                preference:profile_package_use_spec(AtomA, Spec),
                member(FlagS0, FlagSs),
                atom_string(FlagAtom, FlagS0),
                ( Basename == 'package.use.mask' ->
                    Entry = pkg_use_mask(Spec, FlagAtom)
                ; Entry = pkg_use_force(Spec, FlagAtom)
                )
              ),
              Entries)
  ; Entries = []
  ).


%! profile:collect_license_groups(-Groups) is det.
%
% Read license_groups from the portage tree.

profile:collect_license_groups(Groups) :-
  ( catch(portage:get_location(Root), _, fail),
    os:compose_path([Root, 'profiles', 'license_groups'], File),
    exists_file(File) ->
      catch(read_file_to_string(File, S, []), _, S = ""),
      split_string(S, "\n", "\r\n", Lines0),
      findall(lic_group(Name, Members),
              ( member(L0, Lines0),
                profile:profile_strip_comment(L0, L1),
                normalize_space(string(L2), L1),
                L2 \== "",
                split_string(L2, " ", "\t ", Ws0),
                exclude(=(""), Ws0, Ws),
                Ws = [NameS|MemberSs],
                atom_string(Name, NameS),
                maplist([MS,MA]>>atom_string(MA, MS), MemberSs, Members)
              ),
              Groups)
  ; Groups = []
  ).


% =============================================================================
%  VI. USE flag descriptions
% =============================================================================

:- dynamic profile:use_description/2.

%! profile:load_use_descriptions is det.
%
% Loads USE flag descriptions from profiles/use.desc in the
% portage tree. Each line has the format: flag - Description text.

profile:load_use_descriptions :-
  retractall(profile:use_description(_, _)),
  ( catch(portage:get_location(Root), _, fail),
    os:compose_path([Root, 'profiles', 'use.desc'], File),
    exists_file(File) ->
      catch(read_file_to_string(File, S, []), _, S = ""),
      split_string(S, "\n", "\r\n", Lines),
      forall(
        member(Line, Lines),
        ( profile:parse_use_desc_line(Line, Flag, Desc) ->
          assertz(profile:use_description(Flag, Desc))
        ; true
        )
      )
  ; true
  ).


%! profile:parse_use_desc_line(+Line, -Flag, -Description) is semidet.
%
% Parses a use.desc line of the form "flag - Description text".

profile:parse_use_desc_line(Line, Flag, Desc) :-
  \+ sub_string(Line, 0, 1, _, "#"),
  Line \== "",
  ( sub_string(Line, Before, 3, _, " - ") ->
    sub_string(Line, 0, Before, _, FlagStr),
    After is Before + 3,
    sub_string(Line, After, _, 0, DescStr),
    normalize_space(string(FlagNorm), FlagStr),
    FlagNorm \== "",
    atom_string(Flag, FlagNorm),
    atom_string(Desc, DescStr)
  ; fail
  ).