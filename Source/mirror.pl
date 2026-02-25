/*
  Distfiles mirror utilities (GLEP 75-aware)

  This module provides helpers for analyzing Gentoo distfiles availability:
  - A "mirror" directory with hashed layout (layout.conf, filename-hash)
  - A local flat distdir (e.g. /usr/portage/distfiles)

  Primary use cases:
  - Compare distfiles referenced by repository Manifests (DIST entries)
    against what's present on the mirror / local distdir.
  - Later: use this to annotate download plans with "already downloaded".

  References:
  - GLEP 75: Split distfile mirror directory structure
    https://www.gentoo.org/glep/glep-0075.html
*/

:- module(mirror, [
  layout/2,                       % +MirrorRoot, -Layout
  distfile_path/4,                % +Root,+Layout,+Filename,-Path
  mirror_present/3,               % +MirrorRoot,+Layout,+Filename
  flat_present/2,                 % +Distdir,+Filename
  repo_manifest_distfiles/2,      % +RepositoryAtom,-Ordset
  missing_on_mirror/3,            % +RepositoryAtom,+MirrorRoot,-MissingOrdset
  extra_on_mirror/3,              % +RepositoryAtom,+MirrorRoot,-ExtraOrdset
  missing_on_distdir/3,           % +RepositoryAtom,+Distdir,-MissingOrdset
  extra_on_distdir/3,             % +RepositoryAtom,+Distdir,-ExtraOrdset
  report/3,                       % +RepositoryAtom,+MirrorRoot,+Distdir
  test_stats/1,                   % +RepositoryAtom
  test_stats/2                    % +RepositoryAtom,+Options
]).


% -----------------------------------------------------------------------------
%  Layout parsing (layout.conf)
% -----------------------------------------------------------------------------

% layout(+MirrorRoot, -Layout)
%
% Layout is one of:
% - flat
% - filename_hash(AlgorithmAtom, CutoffsBitsList)
%
layout(MirrorRoot, Layout) :-
  atomic_list_concat([MirrorRoot, '/layout.conf'], LayoutConf),
  ( exists_file(LayoutConf) ->
      read_file_to_string(LayoutConf, S, []),
      ( parse_layout_conf(S, Layout0) -> Layout = Layout0 ; Layout = flat )
  ; Layout = flat
  ).

parse_layout_conf(S, Layout) :-
  split_string(S, "\n", "\r", Lines0),
  include(not_blank, Lines0, Lines1),
  strip_comments(Lines1, Lines),
  parse_layout_lines(Lines, none, Structures),
  pick_structure(Structures, Layout).

not_blank(Line) :- string_codes(Line, Cs), \+ phrase(blank, Cs).

blank --> [C], { code_type(C, space) }, blank.
blank --> [].

strip_comments([], []).
strip_comments([L0|Ls0], [L|Ls]) :-
  ( sub_string(L0, Before, _, _, "#") ->
      sub_string(L0, 0, Before, _, L1),
      normalize_space(string(L), L1)
  ; normalize_space(string(L), L0)
  ),
  strip_comments(Ls0, Ls).

parse_layout_lines([], _Section, []).
parse_layout_lines([L|Ls], _Section, Out) :-
  sub_string(L, 0, _, _, "["),
  sub_string(L, _, _, 0, "]"),
  !,
  sub_string(L, 1, _, 1, Sect0),
  string_lower(Sect0, Sect),
  parse_layout_lines(Ls, Sect, Out).
parse_layout_lines([L|Ls], Section, Out) :-
  ( Section == "structure" ->
      ( parse_structure_line(L, Struct) ->
          Out = [Struct|Rest],
          parse_layout_lines(Ls, Section, Rest)
      ; parse_layout_lines(Ls, Section, Out)
      )
  ; parse_layout_lines(Ls, Section, Out)
  ).

% Accepts lines like:
%   0 = flat
%   0 = filename-hash BLAKE2B 8
%   0 = filename-hash BLAKE2B 4:8
parse_structure_line(Line, structure(Index, Spec)) :-
  ( sub_string(Line, _, _, _, "=") -> true ; fail ),
  split_string(Line, "=", " \t", [K0,V0]),
  normalize_space(string(K), K0),
  normalize_space(string(V), V0),
  number_string(Index, K),
  parse_structure_spec(V, Spec).

parse_structure_spec(V, flat) :-
  string_lower(V, "flat"),
  !.
parse_structure_spec(V, filename_hash(AlgAtom, CutoffsBits)) :-
  split_string(V, " \t", " \t", Parts0),
  Parts0 = [Kind|Rest],
  string_lower(Kind, "filename-hash"),
  Rest = [AlgStr|Tail],
  atom_string(AlgAtom0, AlgStr),
  normalize_hash_alg(AlgAtom0, AlgAtom),
  ( Tail = [CutoffsStr] ->
      parse_cutoffs(CutoffsStr, CutoffsBits)
  ; Tail = [CutoffsStr|More] ->
      % Be tolerant: if someone writes e.g. "BLAKE2B 8 layout", ignore trailing tokens.
      ( parse_cutoffs(CutoffsStr, CutoffsBits) -> true ; (More = _, fail) )
  ; fail
  ).

normalize_hash_alg(In, Out) :-
  atom(In),
  downcase_atom(In, Lower),
  ( memberchk(Lower, [blake2b, 'blake2b-512', blake2b_512, blake2b512, 'blake2b-8', blake2b8, 'blake2b-256', blake2b256]) ->
      Out = blake2b
  ; In == 'BLAKE2B' ->
      Out = blake2b
  ; Out = In
  ).

parse_cutoffs(CutoffsStr, CutoffsBits) :-
  split_string(CutoffsStr, ":", " \t", BitsStrs),
  BitsStrs \== [],
  maplist(number_string, CutoffsBits, BitsStrs),
  forall(member(B, CutoffsBits), 0 is B mod 4),
  forall(member(B, CutoffsBits), B >= 0).

pick_structure(Structures, Layout) :-
  % Prefer lowest index (0 is most preferred per spec).
  % Pick the first recognized structure in index order.
  sort(1, @=<, Structures, Sorted),
  pick_structure_(Sorted, Layout).

pick_structure_([structure(_Idx, flat)|_], flat) :- !.
pick_structure_([structure(_Idx, filename_hash(Alg, Cutoffs))|_], filename_hash(Alg, Cutoffs)) :- !.
pick_structure_([_|Rest], Layout) :-
  pick_structure_(Rest, Layout).


% -----------------------------------------------------------------------------
%  Path mapping + presence checks
% -----------------------------------------------------------------------------

distfile_path(Root, flat, Filename, Path) :-
  atomic_list_concat([Root, '/', Filename], Path).
distfile_path(Root, filename_hash(Alg, CutoffsBits), Filename, Path) :-
  filename_hash_hex(Alg, Filename, Hex),
  hash_segments(Hex, CutoffsBits, Segments),
  atomic_list_concat([Root|Segments], '/', Dir0),
  atomic_list_concat([Dir0, '/', Filename], Path).

mirror_present(MirrorRoot, Layout, Filename) :-
  % Prefer layout-based path, but allow flat fallback for compatibility.
  ( distfile_path(MirrorRoot, Layout, Filename, P), exists_file(P) )
  ; ( distfile_path(MirrorRoot, flat, Filename, P2), exists_file(P2) ).

flat_present(Distdir, Filename) :-
  distfile_path(Distdir, flat, Filename, P),
  exists_file(P).

filename_hash_hex(blake2b, Filename, HexLower) :-
  !,
  ( atom(Filename) -> Data = Filename ; atom_string(Data, Filename) ),
  % SWI-Prolog's crypto library exposes BLAKE2B via the blake2b512 hash name.
  crypto_data_hash(Data, Hex0, [algorithm(blake2b512)]),
  ( atom(Hex0) ->
      downcase_atom(Hex0, HexLower)
  ; string(Hex0) ->
      string_lower(Hex0, HexLower)
  ; % unexpected return type
    fail
  ).
filename_hash_hex(_OtherAlg, _Filename, _Hex) :-
  % For now, mirror support is focused on Gentoo's BLAKE2B filename-hash.
  fail.

hash_segments(Hex, CutoffsBits, Segments) :-
  hash_segments_(Hex, CutoffsBits, 0, Segments).

hash_segments_(_Hex, [], _OffsetNibbles, []).
hash_segments_(Hex, [Bits|Rest], Off0, [Seg|Segs]) :-
  Nibbles is Bits // 4,
  sub_string(Hex, Off0, Nibbles, _, Seg),
  Off1 is Off0 + Nibbles,
  hash_segments_(Hex, Rest, Off1, Segs).


% -----------------------------------------------------------------------------
%  Distfiles referenced by repository metadata (Manifest DIST)
% -----------------------------------------------------------------------------

repo_manifest_distfiles(RepositoryAtom, DistfilesOrdset) :-
  % Uses query.pl's manifest search, which matches SRC_URI "Binary" items to
  % Manifest entries (cache:manifest_metadata/6).
  findall(F,
          kb:query(manifest(all, dist, F, _Size), RepositoryAtom://_Entry),
          Fs0),
  sort(Fs0, Fs),
  list_to_ord_set(Fs, DistfilesOrdset).


% -----------------------------------------------------------------------------
%  Scanning directories (for "extra on mirror/distdir")
% -----------------------------------------------------------------------------

scan_all_files(Root, FilesOrdset) :-
  findall(Base,
          ( directory_member(Root, File,
                             [recursive(true), follow_links(true), file_type(regular)]),
            file_base_name(File, Base),
            Base \== "layout.conf"
          ),
          Bases0),
  sort(Bases0, Bases),
  list_to_ord_set(Bases, FilesOrdset).


% -----------------------------------------------------------------------------
%  High-level diffs
% -----------------------------------------------------------------------------

missing_on_mirror(RepositoryAtom, MirrorRoot, MissingOrdset) :-
  layout(MirrorRoot, Layout),
  repo_manifest_distfiles(RepositoryAtom, Needed),
  findall(F,
          ( ord_memberchk(F, Needed),
            \+ mirror_present(MirrorRoot, Layout, F)
          ),
          Missing0),
  sort(Missing0, Missing),
  list_to_ord_set(Missing, MissingOrdset).

extra_on_mirror(RepositoryAtom, MirrorRoot, ExtraOrdset) :-
  layout(MirrorRoot, Layout),
  repo_manifest_distfiles(RepositoryAtom, Needed),
  scan_all_files(MirrorRoot, Present),
  % If the mirror is hashed, we *still* compare by filename (basenames).
  ( Layout = Layout -> true ; true ),
  ord_subtract(Present, Needed, ExtraOrdset).

missing_on_distdir(RepositoryAtom, Distdir, MissingOrdset) :-
  repo_manifest_distfiles(RepositoryAtom, Needed),
  findall(F,
          ( ord_memberchk(F, Needed),
            \+ flat_present(Distdir, F)
          ),
          Missing0),
  sort(Missing0, Missing),
  list_to_ord_set(Missing, MissingOrdset).

extra_on_distdir(RepositoryAtom, Distdir, ExtraOrdset) :-
  repo_manifest_distfiles(RepositoryAtom, Needed),
  scan_all_files(Distdir, Present),
  ord_subtract(Present, Needed, ExtraOrdset).


% -----------------------------------------------------------------------------
%  Reporting
% -----------------------------------------------------------------------------

report(RepositoryAtom, MirrorRoot, Distdir) :-
  layout(MirrorRoot, Layout),
  format('Mirror root: ~w~n', [MirrorRoot]),
  format('Mirror layout: ~w~n', [Layout]),
  format('Local distdir: ~w~n~n', [Distdir]),
  repo_manifest_distfiles(RepositoryAtom, Needed),
  ord_set_size(Needed, NeededN),
  format('Manifest DIST files: ~d~n', [NeededN]),
  missing_on_mirror(RepositoryAtom, MirrorRoot, MissingM),
  ord_set_size(MissingM, MissingMN),
  format('Missing on mirror: ~d~n', [MissingMN]),
  missing_on_distdir(RepositoryAtom, Distdir, MissingD),
  ord_set_size(MissingD, MissingDN),
  format('Missing on distdir: ~d~n', [MissingDN]),
  true.


% -----------------------------------------------------------------------------
%  Manifest verification + stats
% -----------------------------------------------------------------------------
%
% We verify distfiles against Manifest metadata:
% - cache:manifest/5 identifies the Manifest path for a package
% - cache:manifest_metadata/6 contains distfile size + checksum tokens
%
% For performance reasons, test_stats/1 defaults to:
% - presence checks (mirror + distdir)
% - size verification (when present)
% Hash verification is optional via test_stats/2 options.
%
% Options (test_stats/2):
% - mirror_root(Path)            default: env PORTAGE_NG_MIRROR_ROOT or '/Volumes/Storage/Distfiles/distfiles'
% - distdir(Path)               default: env PORTAGE_NG_DISTDIR or '/usr/portage/distfiles'
% - verify_hashes(none|sample(N)|all) default: none
%

test_stats(RepositoryAtom) :-
  test_stats(RepositoryAtom, []).

test_stats(RepositoryAtom, Options0) :-
  mirror:stats_options(Options0, Options),
  mirror:stats_paths(Options, MirrorRoot, Distdir),
  mirror:layout(MirrorRoot, Layout),
  mirror:manifest_distfile_specs(RepositoryAtom, Specs),
  length(Specs, TotalFiles),
  mirror:sum_sizes(Specs, TotalBytes),
  mirror:verify_specs(Specs, MirrorRoot, Layout, Distdir, Options, Stats),
  mirror:print_test_stats(RepositoryAtom, MirrorRoot, Layout, Distdir, TotalFiles, TotalBytes, Stats).

stats_options(Options0, Options) :-
  ( memberchk(verify_hashes(V0), Options0) ->
      V = V0
  ; ( current_predicate(config:mirror_verify_hashes_default/1),
      config:mirror_verify_hashes_default(V1) ->
        V = V1
    ; V = none
    )
  ),
  Options = [verify_hashes(V)|Options0].

stats_paths(Options, MirrorRoot, Distdir) :-
  ( memberchk(mirror_root(MirrorRoot), Options) -> true
  ; ( current_predicate(config:mirror_root/1), config:mirror_root(MirrorRoot) -> true
    ; getenv_default('PORTAGE_NG_MIRROR_ROOT', '/Volumes/Storage/Distfiles/distfiles', MirrorRoot)
    )
  ),
  ( memberchk(distdir(Distdir), Options) -> true
  ; ( current_predicate(config:distdir/1), config:distdir(Distdir) -> true
    ; getenv_default('PORTAGE_NG_DISTDIR', '/var/cache/distfiles', Distdir)
    )
  ).

getenv_default(Env, Default, Value) :-
  ( getenv(Env, V0), V0 \== '' -> Value = V0 ; Value = Default ).

% Build a unique list of distfile specs from cache:manifest_metadata.
% Spec = spec(Filename, Size, ChecksumPairs)
manifest_distfile_specs(RepositoryAtom, Specs) :-
  findall(spec(Filename, Size, Pairs),
          ( cache:manifest_metadata(RepositoryAtom, _ManifestPath, dist, Filename, Size, ChecksumsStr),
            mirror:parse_manifest_checksums(ChecksumsStr, Pairs)
          ),
          Specs0),
  mirror:dedupe_specs_by_filename(Specs0, Specs).

dedupe_specs_by_filename(Specs0, Specs) :-
  % Prefer the first seen spec per filename; additionally detect size mismatches
  % across Manifests and keep the maximum size (conservative).
  sort(1, @=<, Specs0, Sorted),
  dedupe_specs_by_filename_(Sorted, [], SpecsRev),
  reverse(SpecsRev, Specs).

dedupe_specs_by_filename_([], Acc, Acc).
dedupe_specs_by_filename_([spec(F, S, P)|Rest], Acc, Out) :-
  ( select(spec(F, S0, P0), Acc, Acc1) ->
      ( S >= S0 -> Acc2 = [spec(F, S, P)|Acc1] ; Acc2 = [spec(F, S0, P0)|Acc1] )
  ; Acc2 = [spec(F, S, P)|Acc]
  ),
  dedupe_specs_by_filename_(Rest, Acc2, Out).

sum_sizes(Specs, Total) :-
  foldl([spec(_F,S,_P),In,Out]>>(Out is In + S), Specs, 0, Total).

% Parse the checksum tail from Manifest lines. In our cache this is currently a string.
% Example token stream:
%   "BLAKE2B <hex> SHA512 <hex>"
parse_manifest_checksums(ChecksumsStr, Pairs) :-
  ( string(ChecksumsStr) -> Str = ChecksumsStr
  ; atom(ChecksumsStr)   -> atom_string(ChecksumsStr, Str)
  ; % unknown format
    Pairs = [], !
  ),
  split_string(Str, " \t", " \t", Tokens0),
  exclude(=(""), Tokens0, Tokens),
  mirror:tokens_to_pairs(Tokens, Pairs),
  !.

tokens_to_pairs([], []).
tokens_to_pairs([AlgS, HashS|Rest], [alg_hash(Alg, Hash)|Pairs]) :-
  atom_string(Alg0, AlgS),
  downcase_atom(Alg0, AlgLower),
  mirror:normalize_manifest_alg(AlgLower, Alg),
  string_lower(HashS, HashLowerS),
  atom_string(Hash, HashLowerS),
  tokens_to_pairs(Rest, Pairs).
tokens_to_pairs([_Odd], []) :- !.

normalize_manifest_alg('blake2b',  blake2b512) :- !.
normalize_manifest_alg('sha512',   sha512)     :- !.
normalize_manifest_alg('sha256',   sha256)     :- !.
normalize_manifest_alg('sha1',     sha1)       :- !.
normalize_manifest_alg('rmd160',   rmd160)     :- !.
normalize_manifest_alg(Other,      Other).

verify_specs(Specs0, MirrorRoot, Layout, Distdir, Options, stats(MissM, SizeBadM, HashBadM, UnsupM, PresentD, SizeBadD, HashBadD, UnsupD, Sampled)) :-
  memberchk(verify_hashes(Mode), Options),
  mirror:select_for_hash_verification(Mode, Specs0, SpecsHash, Sampled),
  list_to_ord_set(SpecsHash, HashSet),
  foldl(mirror:verify_one(MirrorRoot, Layout, Distdir, HashSet),
        Specs0,
        stats(0,0,0,0,0,0,0,0,Sampled),
        stats(MissM, SizeBadM, HashBadM, UnsupM, PresentD, SizeBadD, HashBadD, UnsupD, Sampled)).

select_for_hash_verification(none, _Specs, [], 0) :- !.
select_for_hash_verification(all, Specs, Specs, N) :- !, length(Specs, N).
select_for_hash_verification(sample(N), Specs, Sample, N) :-
  integer(N), N >= 0,
  length(Prefix, N),
  append(Prefix, _, Specs),
  !,
  Sample = Prefix.
select_for_hash_verification(sample(N), Specs, Specs, M) :-
  integer(N), length(Specs, M),
  M < N,
  !.

verify_one(MirrorRoot, Layout, Distdir, HashSet, spec(F, S, Pairs),
           stats(MissM0, SizeBadM0, HashBadM0, UnsupM0, PresentD0, SizeBadD0, HashBadD0, UnsupD0, Sampled),
           stats(MissM,  SizeBadM,  HashBadM,  UnsupM,  PresentD,  SizeBadD,  HashBadD,  UnsupD,  Sampled)) :-
  % Mirror
  ( mirror:distfile_path(MirrorRoot, Layout, F, PM), exists_file(PM) ->
      mirror:verify_size(PM, S, SizeOKM),
      ( SizeOKM == true -> SizeBadM1 = SizeBadM0 ; SizeBadM1 is SizeBadM0 + 1 ),
      ( ord_memberchk(spec(F,S,Pairs), HashSet) ->
          mirror:verify_hashes(PM, Pairs, HashOKM, UnsupDeltaM),
          UnsupM1 is UnsupM0 + UnsupDeltaM,
          ( HashOKM == true -> HashBadM1 = HashBadM0 ; HashBadM1 is HashBadM0 + 1 )
      ; UnsupM1 = UnsupM0, HashBadM1 = HashBadM0
      ),
      MissM1 = MissM0
  ; MissM1 is MissM0 + 1,
    SizeBadM1 = SizeBadM0,
    HashBadM1 = HashBadM0,
    UnsupM1 = UnsupM0
  ),
  % Distdir (flat)
  ( mirror:flat_present(Distdir, F) ->
      PresentD1 is PresentD0 + 1,
      mirror:distfile_path(Distdir, flat, F, PD),
      mirror:verify_size(PD, S, SizeOKD),
      ( SizeOKD == true -> SizeBadD1 = SizeBadD0 ; SizeBadD1 is SizeBadD0 + 1 ),
      ( ord_memberchk(spec(F,S,Pairs), HashSet) ->
          mirror:verify_hashes(PD, Pairs, HashOKD, UnsupDeltaD),
          UnsupD1 is UnsupD0 + UnsupDeltaD,
          ( HashOKD == true -> HashBadD1 = HashBadD0 ; HashBadD1 is HashBadD0 + 1 )
      ; UnsupD1 = UnsupD0, HashBadD1 = HashBadD0
      )
  ; PresentD1 = PresentD0,
    SizeBadD1 = SizeBadD0,
    HashBadD1 = HashBadD0,
    UnsupD1 = UnsupD0
  ),
  MissM = MissM1, SizeBadM = SizeBadM1, HashBadM = HashBadM1, UnsupM = UnsupM1,
  PresentD = PresentD1, SizeBadD = SizeBadD1, HashBadD = HashBadD1, UnsupD = UnsupD1.

verify_size(Path, Expected, true) :-
  catch(size_file(Path, Size), _Any, fail),
  Size =:= Expected,
  !.
verify_size(_Path, _Expected, false).

verify_hashes(_Path, [], true, 0) :- !.
verify_hashes(Path, Pairs, OK, UnsupportedCount) :-
  foldl(mirror:verify_one_hash(Path), Pairs, state(true,0), state(OK,UnsupportedCount)).

verify_one_hash(Path, alg_hash(Alg, Expected), state(OK0,U0), state(OK,U)) :-
  ( mirror:crypto_supported_alg(Alg) ->
      crypto:crypto_file_hash(Path, Got0, [algorithm(Alg)]),
      ( atom(Got0) -> downcase_atom(Got0, Got) ; Got = Got0 ),
      ( Got == Expected -> OK1 = OK0 ; OK1 = false ),
      OK = OK1,
      U = U0
  ; OK = OK0,
    U is U0 + 1
  ).

crypto_supported_alg(Alg) :-
  % Conservative allowlist; extend as needed based on your Manifest hash set.
  memberchk(Alg, [blake2b512, sha512, sha256, sha1, rmd160]).

print_test_stats(RepositoryAtom, MirrorRoot, Layout, Distdir, TotalFiles, TotalBytes,
                 stats(MissM, SizeBadM, HashBadM, UnsupM, PresentD, SizeBadD, HashBadD, UnsupD, Sampled)) :-
  nl,
  message:header('Mirror test statistics'),
  nl,
  format('  Repository:            ~w~n', [RepositoryAtom]),
  format('  Mirror root:           ~w~n', [MirrorRoot]),
  format('  Mirror layout:         ~w~n', [Layout]),
  format('  Local distdir:         ~w~n', [Distdir]),
  nl,
  format('  Distfiles (Manifest):  ~d~n', [TotalFiles]),
  format('  Total bytes (Manifest):~d~n', [TotalBytes]),
  nl,
  format('  Mirror missing:        ~d~n', [MissM]),
  format('  Mirror size mismatch:  ~d~n', [SizeBadM]),
  ( Sampled > 0 ->
      format('  Mirror hash mismatch:  ~d (sampled ~d)~n', [HashBadM, Sampled]),
      format('  Mirror hash unsupported: ~d (sampled ~d)~n', [UnsupM, Sampled])
  ; true
  ),
  nl,
  format('  Distdir present:       ~d~n', [PresentD]),
  format('  Distdir size mismatch: ~d~n', [SizeBadD]),
  ( Sampled > 0 ->
      format('  Distdir hash mismatch: ~d (sampled ~d)~n', [HashBadD, Sampled]),
      format('  Distdir hash unsupported: ~d (sampled ~d)~n', [UnsupD, Sampled])
  ; true
  ),
  nl.

