/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> MD5CACHE
Regression harness for the md5-cache extractor
Source/Domain/Gentoo/Ebuild/ebuild-depend.sh.

Sources every ebuild that has an on-disk md5-cache entry through the
script's --batch mode and diffs the produced KEY=VALUE block against the
cached version, key by key.

Usage from the project wrapper:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/md5cache'), [if(true)]).
  md5cache_validate([limit(50), verbose(true)]).
  halt.
  PL

Or for a full-tree run with a report file:

  md5cache_validate([out('/tmp/md5cache_report.pl')]).

Compared keys (intersection of both outputs):
  BDEPEND DEFINED_PHASES DEPEND DESCRIPTION EAPI HOMEPAGE IDEPEND
  INHERIT IUSE IUSE_RUNTIME KEYWORDS LICENSE PDEPEND PROPERTIES
  RDEPEND REQUIRED_USE RESTRICT SLOT SRC_URI
Skipped keys: _md5_, _eclasses_, INHERITED.
*/

:- module(md5cache, [md5cache_validate/0,
                    md5cache_validate/1]).

:- use_module(library(assoc)).
:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(process)).
:- use_module(library(readutil)).

% =============================================================================
%  MD5CACHE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Public entry points
% -----------------------------------------------------------------------------

%! md5cache_metadata_keys(-Keys) is det.
%
% List of metadata keys compared against md5-cache.

md5cache_metadata_keys([
    'BDEPEND', 'DEFINED_PHASES', 'DEPEND', 'DESCRIPTION', 'EAPI',
    'HOMEPAGE', 'IDEPEND', 'INHERIT', 'IUSE', 'IUSE_RUNTIME',
    'KEYWORDS', 'LICENSE', 'PDEPEND', 'PROPERTIES', 'RDEPEND',
    'REQUIRED_USE', 'RESTRICT', 'SLOT', 'SRC_URI'
]).


%! md5cache_validate is det.
%! md5cache_validate(+Options) is det.
%
% Run ebuild-depend.sh --batch over every md5-cache entry in the
% configured Portage tree and compare its output against the on-disk
% md5-cache file, key by key.
%
% Options:
%   * repo(Atom)      -- repository to validate (default: portage)
%   * limit(N)        -- only process the first N entries (0=all, default 0)
%   * verbose(Bool)   -- print every per-ebuild diff (default false)
%   * out(Path)       -- write a Prolog-term report to Path (default '')

md5cache_validate :-
  md5cache_validate([]).

md5cache_validate(Options) :-
  once(md5cache_validate_(Options)).

md5cache_validate_(Options) :-
  option(repo(Repo), Options, portage),
  option(limit(Limit), Options, 0),
  option(verbose(Verbose), Options, false),
  option(out(OutFile), Options, ''),
  Repo:get_location(RepoRoot),
  Repo:get_cache(CacheDir),
  config:working_dir(WorkingDir),
  atomic_list_concat([WorkingDir, '/Source/Domain/Gentoo/Ebuild/ebuild-depend.sh'],
                     Script),
  ( exists_file(Script)
  -> true
  ;  throw(error(existence_error(file, Script),
                 context(md5cache_validate/1, _)))
  ),
  format('% Discovering md5-cache entries under ~w ...~n', [CacheDir]),
  flush_output,
  md5cache_collect_entries(CacheDir, AllEntries),
  length(AllEntries, Total),
  ( Limit > 0
  -> ( length(AllEntries, ALen), ALen =< Limit
     -> Entries = AllEntries
     ;  length(Entries, Limit), append(Entries, _, AllEntries)
     )
  ;  Entries = AllEntries
  ),
  length(Entries, NEntries),
  format('% Found ~d md5-cache entries, processing ~d.~n', [Total, NEntries]),
  flush_output,
  md5cache_build_batch(Entries, RepoRoot, BatchLines, EntryMap, SkippedNoEbuild),
  length(BatchLines, NBatch),
  format('% ~d ebuilds matched, ~d skipped (no ebuild found).~n',
         [NBatch, SkippedNoEbuild]),
  format('% Running ~w --batch (~d ebuilds) ...~n', [Script, NBatch]),
  flush_output,
  get_time(T0),
  md5cache_run_batch(Script, RepoRoot, BatchLines, Blocks, ExitCode),
  get_time(T1),
  Elapsed is T1 - T0,
  length(Blocks, NBlocks),
  format('% Batch completed in ~3fs (exit=~d, ~d output blocks).~n',
         [Elapsed, ExitCode, NBlocks]),
  flush_output,
  empty_assoc(KAcc0),
  md5cache_compare_fold(EntryMap, Blocks, Verbose,
                        0-0-0-KAcc0-[],
                        Match-Diff-Missing-KAcc-DiffsRev),
  reverse(DiffsRev, DiffDetails),
  assoc_to_list(KAcc, KeyDiffs),
  md5cache_print_summary(Total, NBatch, SkippedNoEbuild, Missing,
                         Match, Diff, KeyDiffs, DiffDetails, Elapsed),
  ( OutFile == ''
  -> true
  ;  md5cache_write_report(OutFile, Total, NBatch, SkippedNoEbuild,
                           Missing, Match, Diff, Elapsed,
                           KeyDiffs, DiffDetails)
  ).


% -----------------------------------------------------------------------------
%  Cache discovery and batch descriptors
% -----------------------------------------------------------------------------

%! md5cache_collect_entries(+CacheDir, -Entries) is det.
%
% Walk CacheDir and collect every md5-cache file as entry(Cat, PF, Path).

md5cache_collect_entries(CacheDir, Entries) :-
  ( exists_directory(CacheDir)
  -> true
  ;  throw(error(existence_error(directory, CacheDir),
                 context(md5cache_collect_entries/2, _)))
  ),
  directory_files(CacheDir, Cats0),
  exclude([X]>>memberchk(X, ['.', '..']), Cats0, Cats),
  findall(entry(Cat, PF, Path),
    ( member(Cat, Cats),
      os:compose_path(CacheDir, Cat, CatDir),
      exists_directory(CatDir),
      directory_files(CatDir, PFs0),
      member(PF, PFs0),
      \+ memberchk(PF, ['.', '..']),
      os:compose_path(CatDir, PF, Path),
      exists_file(Path)
    ),
    Entries0),
  sort(Entries0, Entries).


%! md5cache_build_batch(+Entries, +RepoRoot, -BatchLines, -EntryMap, -Skipped) is det.
%
% For each cache entry, locate the matching .ebuild file under RepoRoot
% and emit one NUL-framed entry request for ebuild-depend.sh --batch.
% EntryMap is a list of map(Idx, Cat, PF, Path, EntryId) entries indexed
% by their position in the batch input (= their position in the script's
% output blocks).

md5cache_build_batch(Entries, RepoRoot, BatchLines, EntryMap, Skipped) :-
  md5cache_build_batch_(Entries, RepoRoot, 0,
                        [], BLR, [], EMR, 0, Skipped),
  reverse(BLR, BatchLines),
  reverse(EMR, EntryMap).

md5cache_build_batch_([], _, _, BL, BL, EM, EM, S, S).

md5cache_build_batch_([entry(Cat, PF, Path)|Rest], RepoRoot, Idx,
                       BLAcc, BLOut, EMAcc, EMOut, SAcc, SOut) :-
  ( md5cache_find_ebuild(RepoRoot, Cat, PF, Ebuild, PN)
  -> md5cache_descriptor_fields(Cat, PN, PF, Ebuild, Fields),
     atomic_list_concat([Cat, '/', PF], EntryId),
     Idx1 is Idx + 1,
     md5cache_build_batch_(Rest, RepoRoot, Idx1,
                           [Fields|BLAcc], BLOut,
                           [map(Idx, Cat, PF, Path, EntryId)|EMAcc], EMOut,
                           SAcc, SOut)
  ;  S1 is SAcc + 1,
     md5cache_build_batch_(Rest, RepoRoot, Idx,
                           BLAcc, BLOut, EMAcc, EMOut, S1, SOut)
  ).


%! md5cache_find_ebuild(+RepoRoot, +Cat, +PF, -Ebuild, -PN) is semidet.
%
% Locate <RepoRoot>/<Cat>/<PN>/<PF>.ebuild by scanning the category
% directory for the matching package-name subdirectory.

md5cache_find_ebuild(RepoRoot, Cat, PF, Ebuild, PN) :-
  os:compose_path(RepoRoot, Cat, CatDir),
  exists_directory(CatDir),
  directory_files(CatDir, PNs),
  member(PN, PNs),
  \+ memberchk(PN, ['.', '..']),
  atomic_list_concat([CatDir, '/', PN, '/', PF, '.ebuild'], Ebuild),
  exists_file(Ebuild),
  !.


%! md5cache_descriptor_fields(+Cat, +PN, +PF, +Ebuild, -Fields) is det.
%
% Eight entry-frame fields, in the order ebuild:write_entry_frame/2 writes.

md5cache_descriptor_fields(Cat, PN, PF, Ebuild, Fields) :-
  md5cache_split_pf(PN, PF, PV, PR, PVR),
  atomic_list_concat([PN, '-', PV], P),
  Fields = [Cat, PN, PV, PR, PVR, PF, P, Ebuild].


%! md5cache_split_pf(+PN, +PF, -PV, -PR, -PVR) is det.
%
% Strip the PN- prefix and split a trailing -rN suffix off PVR. The
% revision split must pick the rightmost -rN that is followed only by
% digits, mirroring Portage's bash semantics.

md5cache_split_pf(PN, PF, PV, PR, PVR) :-
  atom_concat(PN, '-', PNDash),
  ( atom_concat(PNDash, PVR0, PF)
  -> PVR = PVR0
  ;  PVR = PF
  ),
  md5cache_split_pvr(PVR, PV, PR).

md5cache_split_pvr(PVR, PV, PR) :-
  ( findall(PV0-PR0,
      ( atom_concat(PV0, RevPart, PVR),
        atom_concat('-r', Digits, RevPart),
        atom_codes(Digits, DC), DC = [_|_],
        forall(member(C, DC), (C >= 0'0, C =< 0'9)),
        atom_concat(r, Digits, PR0)
      ), Solutions),
    Solutions \== []
  -> last(Solutions, PV-PR)
  ;  PV = PVR, PR = 'r0'
  ).


% -----------------------------------------------------------------------------
%  Subprocess invocation
% -----------------------------------------------------------------------------

%! md5cache_run_batch(+Script, +RepoRoot, +Requests, -Blocks, -ExitCode) is det.
%
% Spawn ebuild-depend.sh --batch, write NUL-framed entry requests to its
% stdin, and slurp its stdout into ---END--- delimited blocks.

md5cache_run_batch(Script, RepoRoot, Requests, Blocks, ExitCode) :-
  process_create(Script, ['--batch', RepoRoot],
                 [ stdin(pipe(In)),
                   stdout(pipe(Out)),
                   stderr(null),
                   process(Pid)
                 ]),
  set_stream(In, encoding(utf8)),
  catch(
    ( forall(member(Fields, Requests),
             ( ebuild:write_entry_frame(In, Fields),
               flush_output(In)
             )),
      close(In)
    ),
    E,
    ( catch(close(In, [force(true)]), _, true),
      catch(process_wait(Pid, _), _, true),
      throw(E)
    )
  ),
  read_string(Out, _, OutString),
  close(Out),
  process_wait(Pid, exit(ExitCode)),
  md5cache_split_blocks(OutString, Blocks).


%! md5cache_split_blocks(+OutString, -Blocks) is det.

md5cache_split_blocks(OutString, Blocks) :-
  split_string(OutString, "\n", "", Lines),
  md5cache_split_blocks_(Lines, [], [], Rev),
  reverse(Rev, Blocks).

md5cache_split_blocks_([], _, Acc, Acc).
md5cache_split_blocks_([L|Rest], Cur, Acc, Out) :-
  ( L == "---END---"
  -> reverse(Cur, BlockLines),
     md5cache_split_blocks_(Rest, [], [BlockLines|Acc], Out)
  ;  md5cache_split_blocks_(Rest, [L|Cur], Acc, Out)
  ).


% -----------------------------------------------------------------------------
%  KEY=VALUE parsing and comparison
% -----------------------------------------------------------------------------

%! md5cache_parse_kv_lines(+Lines, -KV) is det.
%
% Parse a list of "KEY=VALUE" strings into a list of Atom-Atom pairs.
% Whitespace inside the value is normalised (collapsed runs, trimmed).

md5cache_parse_kv_lines(Lines, KV) :-
  findall(Key-Norm,
    ( member(L, Lines),
      L \== "",
      sub_string(L, Eq, 1, _, "="),
      sub_string(L, 0, Eq, _, KS),
      EqAfter is Eq + 1,
      sub_string(L, EqAfter, _, 0, VS),
      atom_string(Key, KS),
      md5cache_normalize_value(VS, Norm)
    ),
    KV).


%! md5cache_normalize_value(+RawString, -NormAtom) is det.

md5cache_normalize_value(Raw, Norm) :-
  ( atom(Raw) -> atom_string(Raw, S) ; S = Raw ),
  split_string(S, " \t\n\r", " \t\n\r", Tokens0),
  exclude([X]>>(X == ""), Tokens0, Tokens),
  atomic_list_concat(Tokens, ' ', Norm).


%! md5cache_read_md5_cache_file(+Path, -KV) is det.

md5cache_read_md5_cache_file(Path, KV) :-
  read_file_to_string(Path, Content, []),
  split_string(Content, "\n", "", Lines),
  md5cache_parse_kv_lines(Lines, KV).


%! md5cache_pairs_to_assoc(+Pairs, -Assoc) is det.
%
% Last-write-wins fold over Key-Value pairs (avoids the
% domain_error(unique_key_pairs, _) thrown by list_to_assoc/2 on
% duplicate keys).

md5cache_pairs_to_assoc(Pairs, Assoc) :-
  empty_assoc(E),
  foldl([K-V, In, Out]>>put_assoc(K, In, V, Out), Pairs, E, Assoc).


%! md5cache_diff_entry(+CacheKV, +OurKV, -Diffs) is det.
%
% Compare on the intersection of metadata keys. Diffs is a list of
% Key-CacheVal-OurVal triples; missing keys on either side are normalised
% to the empty atom ''.

md5cache_diff_entry(CacheKV, OurKV, Diffs) :-
  md5cache_metadata_keys(Keys),
  md5cache_pairs_to_assoc(CacheKV, CacheAssoc),
  md5cache_pairs_to_assoc(OurKV, OurAssoc),
  findall(Key-CV-OV,
    ( member(Key, Keys),
      ( get_assoc(Key, CacheAssoc, CV) -> true ; CV = '' ),
      ( get_assoc(Key, OurAssoc, OV)   -> true ; OV = '' ),
      CV \== OV
    ),
    Diffs).


%! md5cache_compare_fold(+EntryMap, +Blocks, +Verbose, +State0, -State) is det.
%
% State carries Match-Diff-Missing-KeyAssoc-DiffDetailsRev.

md5cache_compare_fold([], _, _, S, S).

md5cache_compare_fold([map(Idx, _Cat, _PF, Path, EntryId)|Rest],
                       Blocks, Verbose,
                       M-D-X-K-Diffs, OutState) :-
  ( nth0(Idx, Blocks, BlockLines),
    md5cache_parse_kv_lines(BlockLines, OurKV),
    OurKV \== []
  -> md5cache_read_md5_cache_file(Path, CacheKV),
     md5cache_diff_entry(CacheKV, OurKV, EntryDiffs),
     ( EntryDiffs == []
     -> M1 is M + 1,
        md5cache_compare_fold(Rest, Blocks, Verbose,
                              M1-D-X-K-Diffs, OutState)
     ;  D1 is D + 1,
        ( Verbose == true -> md5cache_print_diffs(EntryId, EntryDiffs) ; true ),
        md5cache_accumulate_keydiffs(EntryDiffs, K, K1),
        md5cache_compare_fold(Rest, Blocks, Verbose,
                              M-D1-X-K1-[diff(EntryId, EntryDiffs)|Diffs],
                              OutState)
     )
  ;  X1 is X + 1,
     md5cache_compare_fold(Rest, Blocks, Verbose,
                           M-D-X1-K-Diffs, OutState)
  ).


%! md5cache_accumulate_keydiffs(+Diffs, +AssocIn, -AssocOut) is det.

md5cache_accumulate_keydiffs([], A, A).
md5cache_accumulate_keydiffs([Key-_-_|Rest], AIn, AOut) :-
  ( get_assoc(Key, AIn, N) -> N1 is N + 1 ; N1 = 1 ),
  put_assoc(Key, AIn, N1, A1),
  md5cache_accumulate_keydiffs(Rest, A1, AOut).


% -----------------------------------------------------------------------------
%  Output
% -----------------------------------------------------------------------------

%! md5cache_print_diffs(+EntryId, +Diffs) is det.

md5cache_print_diffs(EntryId, Diffs) :-
  format('~n  DIFF: ~w~n', [EntryId]),
  forall(member(Key-CV-OV, Diffs),
    ( md5cache_truncate(CV, 120, CVT),
      md5cache_truncate(OV, 120, OVT),
      format('    ~w:~n      expected: ~w~n           got: ~w~n',
             [Key, CVT, OVT])
    )).


%! md5cache_truncate(+Value, +Max, -Truncated) is det.

md5cache_truncate(V, Max, T) :-
  ( atom(V)
  -> atom_length(V, L),
     ( L =< Max -> T = V ; sub_atom(V, 0, Max, _, T) )
  ;  string_length(V, L),
     ( L =< Max -> T = V ; sub_string(V, 0, Max, _, T) )
  ).


%! md5cache_print_summary(+Total, +NBatch, +Skipped, +Missing,
%!                       +Match, +Diff, +KeyDiffs, +DiffDetails, +Elapsed) is det.

md5cache_print_summary(Total, NBatch, SkippedNoEbuild, MissingOutput,
                       Match, Diff, KeyDiffs, DiffDetails, Elapsed) :-
  Denom is max(Match + Diff, 1),
  Pct is 100.0 * Match / Denom,
  ( NBatch > 0 -> PerEbuild is 1000.0 * Elapsed / NBatch ; PerEbuild = 0.0 ),
  nl,
  format('~`=t~60|~n', []),
  writeln('VALIDATION SUMMARY'),
  format('~`=t~60|~n', []),
  format('Total md5-cache entries:   ~d~n', [Total]),
  format('Processed:                 ~d~n', [NBatch]),
  format('Skipped (no ebuild):       ~d~n', [SkippedNoEbuild]),
  format('Missing output:            ~d~n', [MissingOutput]),
  format('Exact match:               ~d~n', [Match]),
  format('Mismatched:                ~d~n', [Diff]),
  format('Match rate:                ~2f%~n', [Pct]),
  format('Batch time:                ~3fs~n', [Elapsed]),
  format('Per-ebuild avg:            ~1fms~n', [PerEbuild]),
  ( KeyDiffs == []
  -> true
  ;  nl, writeln('Mismatches by key:'),
     md5cache_sort_keydiffs_desc(KeyDiffs, Sorted),
     forall(member(K-N, Sorted), format('  ~w: ~d~n', [K, N]))
  ),
  ( DiffDetails == []
  -> true
  ;  nl, writeln('First 10 mismatches:'),
     length(DiffDetails, NDiffs),
     ShowN is min(10, NDiffs),
     length(Show, ShowN),
     append(Show, _, DiffDetails),
     forall(member(diff(EID, Ds), Show),
       ( format('  ~w:~n', [EID]),
         forall(member(Key-CV-OV, Ds),
           ( md5cache_truncate(CV, 80, CVT),
             md5cache_truncate(OV, 80, OVT),
             format('    ~w: expected=~q~n', [Key, CVT]),
             format('    ~w:      got=~q~n', [Key, OVT])
           ))
       ))
  ).


%! md5cache_sort_keydiffs_desc(+KVs, -Sorted) is det.

md5cache_sort_keydiffs_desc(KVs, Sorted) :-
  predsort(md5cache_keydiff_cmp, KVs, Sorted).

md5cache_keydiff_cmp(Order, K1-N1, K2-N2) :-
  compare(O1, N2, N1),
  ( O1 == (=) -> compare(Order, K1, K2) ; Order = O1 ).


%! md5cache_write_report(+OutFile, +Total, +NBatch, +Skipped, +Missing,
%!                      +Match, +Diff, +Elapsed, +KeyDiffs, +DiffDetails) is det.
%
% Writes the report as a single Prolog term: md5cache_report([Tag(...), ...]).
% First 100 mismatches are kept, mirroring the original Python output.

md5cache_write_report(OutFile, Total, NBatch, Skipped, Missing,
                      Match, Diff, Elapsed, KeyDiffs, DiffDetails) :-
  length(DiffDetails, NDiff),
  TopN is min(100, NDiff),
  length(Top, TopN),
  append(Top, _, DiffDetails),
  Term = md5cache_report(
    [ total_cache(Total),
      processed(NBatch),
      skipped_no_ebuild(Skipped),
      missing_output(Missing),
      exact_match(Match),
      mismatched(Diff),
      batch_time_s(Elapsed),
      key_diff_counts(KeyDiffs),
      diff_details(Top)
    ]),
  setup_call_cleanup(
    open(OutFile, write, S),
    ( format(S, '% md5-cache validation report~n', []),
      portray_clause(S, Term)
    ),
    close(S)
  ),
  format('~nReport written to ~w~n', [OutFile]).
