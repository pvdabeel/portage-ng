/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> STATS
Test statistics table formatting, aggregation, and display.

Renders the accumulated test_stats summary (success/failure/assumption/cycle
counts, per-package timing and cost breakdowns, blocker analysis) used by
prover:test/1 whole-repo runs.
*/

:- module(stats, []).

% =============================================================================
%  STATS declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Table layout (derived from config)
% -----------------------------------------------------------------------------

%! stats:test_stats_item_col_width(-Width)
%
% Derived width for the item column in ranked tables.

stats:test_stats_item_col_width(W) :-
  config:test_stats_table_width(TW),
  config:test_stats_rank_col_width(RW),
  config:test_stats_count_col_width(CW),
  W is max(10, TW - 2 - RW - 2 - 1 - CW).


% -----------------------------------------------------------------------------
%  Text formatting utilities
% -----------------------------------------------------------------------------

%! stats:test_stats_to_atom(+Term, -Atom)
%
% Convert an arbitrary term to a printable atom.

stats:test_stats_to_atom(Term, Atom) :-
  ( atom(Term) -> Atom = Term
  ; with_output_to(atom(Atom),
                   write_term(Term, [quoted(false), numbervars(true)]))
  ).

%! stats:test_stats_fit_atom(+Atom0, +Width, -Atom)
%
% Truncate Atom0 to at most Width characters, appending ellipsis if needed.

stats:test_stats_fit_atom(Atom0, Width, Atom) :-
  ( atom_length(Atom0, L), L =< Width ->
      Atom = Atom0
  ; Width =< 1 ->
      Atom = '…'
  ; Width =:= 2 ->
      Atom = '…'
  ; Width1 is Width - 1,
    sub_atom(Atom0, 0, Width1, _After, Prefix),
    atom_concat(Prefix, '…', Atom)
  ).

%! stats:test_stats_pad_right(+Atom0, +Width, -Atom)
%
% Right-pad Atom0 with spaces to Width characters.

stats:test_stats_pad_right(Atom0, Width, Atom) :-
  atom_length(Atom0, L),
  ( L >= Width ->
      Atom = Atom0
  ; Pad is Width - L,
    length(Cs, Pad),
    maplist(=(' '), Cs),
    atom_chars(PadAtom, Cs),
    atom_concat(Atom0, PadAtom, Atom)
  ).

%! stats:test_stats_pad_left(+Atom0, +Width, -Atom)
%
% Left-pad Atom0 with spaces to Width characters.

stats:test_stats_pad_left(Atom0, Width, Atom) :-
  atom_length(Atom0, L),
  ( L >= Width ->
      Atom = Atom0
  ; Pad is Width - L,
    length(Cs, Pad),
    maplist(=(' '), Cs),
    atom_chars(PadAtom, Cs),
    atom_concat(PadAtom, Atom0, Atom)
  ).

%! stats:test_stats_int_atom(+Int, -Atom)
%
% Format an integer as an atom.

stats:test_stats_int_atom(Int, Atom) :-
  format(atom(Atom), '~d', [Int]).


% -----------------------------------------------------------------------------
%  Table rendering primitives
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Separators and key-value lines
% -----------------------------------------------------------------------------

%! stats:test_stats_print_sep
%
% Print a dashed separator line spanning the table width.

stats:test_stats_print_sep :-
  config:test_stats_table_width(W),
  format('  ~`-t~*|~n', [W]).

%! stats:test_stats_print_kv_int(+Label, +Value)
%
% Print a "Label: Value" line with column-aligned integer.

stats:test_stats_print_kv_int(Label, Value) :-
  format('  ~w~t~30|: ~d~n', [Label, Value]).

%! stats:test_stats_print_kv_int_percent(+Label, +Count, +Total)
%
% Print a "Label: Count (Pct%)" line.

stats:test_stats_print_kv_int_percent(Label, Count, Total) :-
  sampler:percent(Count, Total, P),
  format('  ~w~t~30|: ~d (~2f%)~n', [Label, Count, P]).


% -----------------------------------------------------------------------------
%  Summary table (Metric / Ebuilds / Ebuild% / Pkgs / Pkg%)
% -----------------------------------------------------------------------------

%! stats:test_stats_print_table_header
%
% Print column headers for the main test-stats summary table.

stats:test_stats_print_table_header :-
  config:test_stats_label_col_width(LW),
  config:test_stats_count_col_width(CW),
  config:test_stats_pct_col_width(PW),
  stats:test_stats_pad_right('Metric', LW, MetricHdr),
  stats:test_stats_pad_left('Ebuilds', CW, EbuildsHdr),
  stats:test_stats_pad_left('Ebuild %', PW, EbuildPctHdr),
  stats:test_stats_pad_left('Pkgs', CW, PkgsHdr),
  stats:test_stats_pad_left('Pkg %', PW, PkgPctHdr),
  format('  ~w ~w ~w ~w ~w~n',
         [MetricHdr, EbuildsHdr, EbuildPctHdr, PkgsHdr, PkgPctHdr]),
  stats:test_stats_print_sep.

%! stats:test_stats_print_table_row(+Label, +ECount, +ETotal, +PCount, +PTotal)
%
% Print one row of the main summary table.

stats:test_stats_print_table_row(Label, ECount, ETotal, PCount, PTotal) :-
  sampler:percent(ECount, ETotal, EP),
  sampler:percent(PCount, PTotal, PP),
  format(atom(EPAtom), '~2f %', [EP]),
  format(atom(PPAtom), '~2f %', [PP]),
  config:test_stats_label_col_width(LW),
  config:test_stats_count_col_width(CW),
  config:test_stats_pct_col_width(PW),
  stats:test_stats_pad_right(Label, LW, Lbl),
  stats:test_stats_int_atom(ECount, EC0),
  stats:test_stats_int_atom(PCount, PC0),
  stats:test_stats_pad_left(EC0, CW, EC),
  stats:test_stats_pad_left(EPAtom, PW, EPR),
  stats:test_stats_pad_left(PC0, CW, PC),
  stats:test_stats_pad_left(PPAtom, PW, PPR),
  format('  ~w ~w ~w ~w ~w~n',
         [Lbl, EC, EPR, PC, PPR]).


% -----------------------------------------------------------------------------
%  Assumption-types table (Type / Ebuilds / Ebuild% / Occ / Occ%)
% -----------------------------------------------------------------------------

%! stats:test_stats_print_assumption_types_table_header
%
% Print column headers for the assumption-types breakdown table.

stats:test_stats_print_assumption_types_table_header :-
  config:test_stats_label_col_width(LW),
  config:test_stats_count_col_width(CW),
  config:test_stats_pct_col_width(PW),
  stats:test_stats_pad_right('Type', LW, TypeHdr),
  stats:test_stats_pad_left('Ebuilds', CW, EbuildsHdr),
  stats:test_stats_pad_left('Ebuild %', PW, EbuildPctHdr),
  stats:test_stats_pad_left('Occ', CW, OccHdr),
  stats:test_stats_pad_left('Occ %', PW, OccPctHdr),
  format('  ~w ~w ~w ~w ~w~n',
         [TypeHdr, EbuildsHdr, EbuildPctHdr, OccHdr, OccPctHdr]),
  stats:test_stats_print_sep.

%! stats:test_stats_print_assumption_types_row(+Type, +ECount, +ETotal, +OCount, +OTotal)
%
% Print one row of the assumption-types table.

stats:test_stats_print_assumption_types_row(Type, ECount, ETotal, OCount, OTotal) :-
  sampler:percent(ECount, ETotal, EP),
  sampler:percent(OCount, OTotal, OP),
  format(atom(EPAtom), '~2f %', [EP]),
  format(atom(OPAtom), '~2f %', [OP]),
  config:test_stats_label_col_width(LW),
  config:test_stats_count_col_width(CW),
  config:test_stats_pct_col_width(PW),
  stats:test_stats_pad_right(Type, LW, TypeLbl),
  stats:test_stats_int_atom(ECount, EC0),
  stats:test_stats_int_atom(OCount, OC0),
  stats:test_stats_pad_left(EC0, CW, EC),
  stats:test_stats_pad_left(EPAtom, PW, EPR),
  stats:test_stats_pad_left(OC0, CW, OC),
  stats:test_stats_pad_left(OPAtom, PW, OPR),
  format('  ~w ~w ~w ~w ~w~n',
         [TypeLbl, EC, EPR, OC, OPR]).


% -----------------------------------------------------------------------------
%  Ranked Top-N table (Rank / Item / Value)
% -----------------------------------------------------------------------------

%! stats:test_stats_print_ranked_table_header(+Title, +RightHeader)
%
% Print a section header and column headers for a ranked Top-N table.

stats:test_stats_print_ranked_table_header(Title, RightHeader) :-
  nl,
  message:header(Title),
  nl,
  stats:test_stats_item_col_width(ItemW),
  config:test_stats_count_col_width(CountW),
  config:test_stats_rank_col_width(RankW),
  stats:test_stats_pad_left('Rank', RankW, RankHdr),
  stats:test_stats_pad_right('Item', ItemW, ItemHdr),
  stats:test_stats_pad_left(RightHeader, CountW, RHdr),
  format('  ~w  ~w ~w~n', [RankHdr, ItemHdr, RHdr]),
  stats:test_stats_print_sep.

%! stats:test_stats_print_ranked_table_rows(+Rows, +Limit, +Index, +Width)
%
% Print up to Limit rows of a ranked table. Rows are Count-Item pairs.

stats:test_stats_print_ranked_table_rows([], _Limit, _I, _W) :- !.
stats:test_stats_print_ranked_table_rows(_, 0, _I, _W) :- !.
stats:test_stats_print_ranked_table_rows([N-Item|Rest], Limit, I, W) :-
  stats:test_stats_item_col_width(ItemW),
  stats:test_stats_to_atom(Item, ItemAtom0),
  stats:test_stats_fit_atom(ItemAtom0, ItemW, ItemAtom1),
  stats:test_stats_pad_right(ItemAtom1, ItemW, ItemAtom),
  config:test_stats_rank_col_width(RankW),
  format(atom(RankAtom0), '~d', [I]),
  stats:test_stats_pad_left(RankAtom0, RankW, RankAtom),
  config:test_stats_count_col_width(CountW),
  format(atom(NAtom0), '~d', [N]),
  stats:test_stats_pad_left(NAtom0, CountW, NAtom),
  format('  ~w  ~w ~w~n', [RankAtom, ItemAtom, NAtom]),
  I1 is I + 1,
  Limit1 is Limit - 1,
  stats:test_stats_print_ranked_table_rows(Rest, Limit1, I1, W).

%! stats:test_stats_print_top_cycle_mentions(+Sorted, +Limit, +Index)
%
% Print up to Limit ranked cycle-mention rows.

stats:test_stats_print_top_cycle_mentions([], _Limit, I) :- !,
  ( I =:= 1 -> writeln('  (none)') ; true ).
stats:test_stats_print_top_cycle_mentions(_, 0, _I) :- !.
stats:test_stats_print_top_cycle_mentions([N-RepoEntry|Rest], Limit, I) :-
  format('  ~t~d~3+. ~w (~d)~n', [I, RepoEntry, N]),
  I1 is I + 1,
  Limit1 is Limit - 1,
  stats:test_stats_print_top_cycle_mentions(Rest, Limit1, I1).


% -----------------------------------------------------------------------------
%  Main summary display
% -----------------------------------------------------------------------------

%! stats:test_stats_print
%
% Print the accumulated test_stats summary using the configured Top-N
% (defaults to 10).

stats:test_stats_print :-
  ( config:test_stats_top_n(TopN) -> true ; TopN = 10 ),
  stats:test_stats_print(TopN).

%! stats:test_stats_print(+TopN)
%
% Print the full test_stats summary, showing top lists up to TopN.

stats:test_stats_print(TopN) :-
  sampler:value(label, Label),
  sampler:value(expected_total, Expected),
  sampler:value(expected_unique_packages, ExpectedPkgs),
  sampler:value(processed, Processed),
  sampler:value(entries_with_assumptions, WithAss),
  sampler:value(entries_with_package_assumptions, WithPkgAss),
  sampler:value(entries_with_cycles, WithCycles),
  sampler:value(cycles_found, CyclesFound),
  sampler:pkg_count(processed, ProcessedPkgs),
  sampler:pkg_count(with_assumptions, WithAssPkgs),
  sampler:pkg_count(with_package_assumptions, WithPkgAssPkgs),
  sampler:pkg_count(with_cycles, WithCyclesPkgs),

  % --- Overview (all stages) ---
  nl,
  message:header(['Test statistics (',Label,')']),
  nl,
  stats:test_stats_print_table_header,
  stats:test_stats_print_table_row('Total', Expected, Expected, ExpectedPkgs, ExpectedPkgs),
  stats:test_stats_print_table_row('Processed', Processed, Expected, ProcessedPkgs, ExpectedPkgs),
  ( Processed > 0 ->
      stats:test_stats_print_table_row('With assumptions', WithAss, Processed, WithAssPkgs, ProcessedPkgs),
      stats:test_stats_print_table_row('With package assumptions', WithPkgAss, Processed, WithPkgAssPkgs, ProcessedPkgs),
      stats:test_stats_print_table_row('With cycles', WithCycles, Processed, WithCyclesPkgs, ProcessedPkgs),
      nl,
      format('  ~w~t~30|: ~d total~n', ['Cycles found', CyclesFound]),
      format('  ~w~t~30|: ~2f cycles per processed entry~n', ['Cycles per entry', CyclesFound/Processed])
  ; true
  ),

  % --- Failure breakdown (all stages) ---
  ( Expected =\= Processed ->
      stats:test_stats_print_failure_breakdown(Expected, Processed)
  ; true
  ),

  % --- Assumption types (all stages) ---
  ( Processed > 0 ->
      stats:test_stats_print_assumption_types(Processed)
  ; true
  ),

  % --- Performance: prover-level (all stages) ---
  stats:test_stats_print_slowest_entries(TopN),
  stats:test_stats_print_slowest_packages_total(TopN),
  stats:test_stats_print_expensive_inferences(TopN),
  stats:test_stats_print_ctx_union_cost(TopN),
  stats:test_stats_print_ctx_union_walltime(TopN),
  stats:test_stats_print_ctx_share(TopN),
  stats:test_stats_print_ctx_length_distribution(TopN),
  stats:test_stats_print_ordset_impact,
  stats:test_stats_print_largest_contexts(TopN),
  stats:test_stats_print_slowest_packages_max(TopN),

  % --- Assumption detail: per-type Top-N entries ---
  ( Processed > 0 ->
      findall(Type, sampler:fact(type(Type, _, _)), Types0),
      sort(Types0, Types),
      stats:test_stats_print_per_type_entries(Types, TopN)
  ; true
  ),

  % --- Blocker analysis ---
  ( Processed > 0 ->
      stats:test_stats_print_blocker_analysis(TopN)
  ; true
  ),

  % --- Other assumptions ---
  ( Processed > 0 ->
      stats:test_stats_print_other_assumptions
  ; true
  ),

  % --- Cycle mentions ---
  ( Processed > 0 ->
      stats:test_stats_print_cycle_mentions(TopN)
  ; true
  ).


% -----------------------------------------------------------------------------
%  Summary subsections
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Failure breakdown
% -----------------------------------------------------------------------------

stats:test_stats_print_failure_breakdown(Expected, Processed) :-
  sampler:value(entries_failed_blocker, FailedBlocker),
  sampler:value(entries_failed_timeout, FailedTimeout),
  sampler:value(entries_failed_other, FailedOther),
  FailedTotal is Expected - Processed,
  Unknown0 is FailedTotal - FailedBlocker - FailedTimeout - FailedOther,
  Unknown is max(0, Unknown0),
  format('  ~w~t~30|: ~d entries did not produce a plan/proof (failed/timeout).~n',
         ['Note', FailedTotal]),
  ( FailedBlocker > 0 ->
      format('  ~w~t~30|: ~d failed due to blockers (detected).~n',
             ['Blocker failures', FailedBlocker])
  ; true
  ),
  ( FailedTimeout > 0 ->
      format('  ~w~t~30|: ~d timed out (detected).~n',
             ['Timeout failures', FailedTimeout])
  ; true
  ),
  ( FailedOther > 0 ->
      format('  ~w~t~30|: ~d failed for other reasons (detected).~n',
             ['Other failures', FailedOther])
  ; true
  ),
  ( Unknown > 0 ->
      format('  ~w~t~30|: ~d failed/timeout with unknown reason (not classified).~n',
             ['Unknown', Unknown])
  ; true
  ),
  stats:test_stats_print_failed_pkg_context.

stats:test_stats_print_failed_pkg_context :-
  findall(C-N,
          ( sampler:fact(failed_entry(Repo0://Entry0, _R)),
            cache:ordered_entry(Repo0, Entry0, C, N, _)
          ),
          FailedCNs0),
  sort(FailedCNs0, FailedCNs),
  length(FailedCNs, FailedPkgsTotal),
  findall(C-N,
          ( member(C-N, FailedCNs),
            sampler:fact(pkg(processed, C, N))
          ),
          MixedCNs0),
  sort(MixedCNs0, MixedCNs),
  length(MixedCNs, FailedPkgsWithSomeSuccess),
  FailedPkgsAllFail is FailedPkgsTotal - FailedPkgsWithSomeSuccess,
  ( FailedPkgsTotal > 0 ->
      format('  ~w~t~30|: ~d unique packages had at least one failing entry.~n',
             ['Note', FailedPkgsTotal])
  ; true
  ),
  ( FailedPkgsWithSomeSuccess > 0 ->
      format('  ~w~t~30|: ~d failing packages have another version that proved OK.~n',
             ['Note', FailedPkgsWithSomeSuccess])
  ; true
  ),
  ( FailedPkgsAllFail > 0 ->
      format('  ~w~t~30|: ~d failing packages have no version that proved OK.~n',
             ['Note', FailedPkgsAllFail])
  ; true
  ),
  ( MixedCNs \== [] ->
      format('  ~w~t~30|: ~w~n', ['Mixed (sample)', MixedCNs])
  ; true
  ).


% -----------------------------------------------------------------------------
%  Assumption types
% -----------------------------------------------------------------------------

stats:test_stats_print_assumption_types(Processed) :-
  nl,
  message:header('Assumption types'),
  nl,
  findall(O, sampler:fact(type(_, occurrences, O)), Occs),
  sum_list(Occs, TotalOccs),
  findall(Type, sampler:fact(type(Type, _, _)), Types0),
  sort(Types0, Types),
  ( Types == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_assumption_types_table_header,
    forall(member(Type, Types),
           ( ( sampler:fact(type(Type, entries, E)) -> true ; E = 0 ),
             ( sampler:fact(type(Type, occurrences, O)) -> true ; O = 0 ),
             stats:test_stats_print_assumption_types_row(Type, E, Processed, O, TotalOccs)
           ))
  ).


% -----------------------------------------------------------------------------
%  Performance: timing and cost Top-N tables
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Slowest entries
% -----------------------------------------------------------------------------

stats:test_stats_print_slowest_entries(TopN) :-
  nl,
  message:header(['Top ',TopN,' slowest proofs']),
  nl,
  findall(Ms-RepoEntry, sampler:fact(entry_time(RepoEntry, Ms)), Times0),
  keysort(Times0, TimesAsc),
  reverse(TimesAsc, TimesSorted),
  ( TimesSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Slowest entries', 'ms'),
    config:test_stats_table_width(Wt),
    stats:test_stats_print_ranked_table_rows(TimesSorted, TopN, 1, Wt)
  ).


% -----------------------------------------------------------------------------
%  Slowest packages (total walltime)
% -----------------------------------------------------------------------------

stats:test_stats_print_slowest_packages_total(TopN) :-
  nl,
  message:header(['Top ',TopN,' slowest packages (total)']),
  nl,
  findall(SumMs-C-N, sampler:fact(pkg_time(C, N, SumMs, _MaxMs, _Cnt)), PkgTimes0),
  keysort(PkgTimes0, PkgAsc0),
  reverse(PkgAsc0, PkgSorted0),
  findall(SumMs-PkgAtom,
          ( member(SumMs-C-N, PkgSorted0),
            atomic_list_concat([C,N], '/', PkgAtom)
          ),
          PkgSorted),
  ( PkgSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Slowest packages', 'ms'),
    config:test_stats_table_width(Wp),
    stats:test_stats_print_ranked_table_rows(PkgSorted, TopN, 1, Wp)
  ).


% -----------------------------------------------------------------------------
%  Most expensive packages (inferences)
% -----------------------------------------------------------------------------

stats:test_stats_print_expensive_inferences(TopN) :-
  nl,
  message:header(['Top ',TopN,' most expensive packages (inferences)']),
  nl,
  findall(SumInf-PkgAtomInf,
          ( sampler:fact(pkg_cost(Ci, Ni, _MsI, SumInf, _RuleI, _CntI)),
            atomic_list_concat([Ci,Ni], '/', PkgAtomInf)
          ),
          PkgInf0),
  keysort(PkgInf0, PkgInfAsc),
  reverse(PkgInfAsc, PkgInfSorted),
  ( PkgInfSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Costly packages', 'inferences'),
    config:test_stats_table_width(Wi),
    stats:test_stats_print_ranked_table_rows(PkgInfSorted, TopN, 1, Wi)
  ).


% -----------------------------------------------------------------------------
%  Performance: context union analysis
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Context union cost (operations)
% -----------------------------------------------------------------------------

stats:test_stats_print_ctx_union_cost(TopN) :-
  nl,
  message:header(['Top ',TopN,' most expensive packages (context unions)']),
  nl,
  findall(SumCtxCost-PkgAtomCtx,
          ( sampler:fact(pkg_ctx(Cc, Nc, SumCtxCost, _MaxLenC, _SumMsC, _CntC)),
            atomic_list_concat([Cc,Nc], '/', PkgAtomCtx)
          ),
          PkgCtx0),
  keysort(PkgCtx0, PkgCtxAsc),
  reverse(PkgCtxAsc, PkgCtxSorted),
  ( PkgCtxSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Costly packages', 'ctx-union-cost'),
    config:test_stats_table_width(Wctx),
    stats:test_stats_print_ranked_table_rows(PkgCtxSorted, TopN, 1, Wctx)
  ).


% -----------------------------------------------------------------------------
%  Context union walltime (estimated)
% -----------------------------------------------------------------------------

stats:test_stats_print_ctx_union_walltime(TopN) :-
  nl,
  message:header(['Top ',TopN,' most expensive packages (context unions walltime, est)']),
  nl,
  findall(UnionMs-CcMs-NcMs,
          sampler:fact(pkg_ctx(CcMs, NcMs, _SumCtxCostMs, _MaxLenMs, UnionMs, _CntMs)),
          PkgCtxMsCN0),
  keysort(PkgCtxMsCN0, PkgCtxMsAscCN),
  reverse(PkgCtxMsAscCN, PkgCtxMsSortedCN),
  findall(UnionMs-PkgAtomCtxMs,
          ( member(UnionMs-CcMs-NcMs, PkgCtxMsSortedCN),
            atomic_list_concat([CcMs,NcMs], '/', PkgAtomCtxMs)
          ),
          PkgCtxMsSorted),
  ( PkgCtxMsSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Costly packages', 'ctx-union-ms'),
    config:test_stats_table_width(Wctxms),
    stats:test_stats_print_ranked_table_rows(PkgCtxMsSorted, TopN, 1, Wctxms)
  ).


% -----------------------------------------------------------------------------
%  Context union time share
% -----------------------------------------------------------------------------

stats:test_stats_print_ctx_share(TopN) :-
  nl,
  message:header(['Top ',TopN,' packages by context union time share (est)']),
  nl,
  stats:test_stats_ctx_share_rows(ShareRowsSorted),
  ( ShareRowsSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Packages', 'ctx%*10'),
    config:test_stats_table_width(Wshare),
    stats:test_stats_print_ranked_table_rows(ShareRowsSorted, TopN, 1, Wshare)
  ).


% -----------------------------------------------------------------------------
%  Context length distribution
% -----------------------------------------------------------------------------

stats:test_stats_print_ctx_length_distribution(TopN) :-
  nl,
  message:header('Context length distribution (sampled, ctx_union output)'),
  nl,
  findall(Len-Cnt, sampler:fact(ctx_len_bin(Len, Cnt)), LenBins0),
  keysort(LenBins0, LenBins),
  ( LenBins == [] ->
      writeln('  (none)')
  ; findall(C, member(_L-C, LenBins), LenCnts),
    sum_list(LenCnts, LenTotal),
    format('  Samples: ~d~n', [LenTotal]),
    stats:test_stats_ctx_len_bucket(LenBins, 3,  Le3),
    stats:test_stats_ctx_len_bucket(LenBins, 5,  Le5),
    stats:test_stats_ctx_len_bucket(LenBins, 10, Le10),
    B0_3 is Le3,
    B4_5 is max(0, Le5 - Le3),
    B6_10 is max(0, Le10 - Le5),
    B11 is max(0, LenTotal - Le10),
    ( LenTotal =:= 0 ->
        true
    ; format('  0-3:   ~d (~2f%%)~n', [B0_3, 100*B0_3/LenTotal]),
      format('  4-5:   ~d (~2f%%)~n', [B4_5, 100*B4_5/LenTotal]),
      format('  6-10:  ~d (~2f%%)~n', [B6_10, 100*B6_10/LenTotal]),
      format('  11+:   ~d (~2f%%)~n', [B11,  100*B11/LenTotal])
    ),
    nl,
    stats:test_stats_print_ranked_table_header('ctx-len', 'samples'),
    config:test_stats_table_width(Wlenhist),
    findall(Cnt-LenAtom,
            ( member(Len-Cnt, LenBins),
              format(atom(LenAtom), '~d', [Len])
            ),
            LenByCount0),
    keysort(LenByCount0, LenByCountAsc),
    reverse(LenByCountAsc, LenByCount),
    stats:test_stats_print_ranked_table_rows(LenByCount, min(TopN, 25), 1, Wlenhist)
  ).


% -----------------------------------------------------------------------------
%  Ordset impact estimate
% -----------------------------------------------------------------------------

stats:test_stats_print_ordset_impact :-
  ( sampler:fact(ctx_cost_model(SumMul, SumAdd, SamplesModel)),
    SamplesModel > 0,
    SumMul > 0,
    SumAdd > 0 ->
      Speedup is SumMul / SumAdd,
      findall(SumMs0, sampler:fact(pkg_ctx(_Ccm,_Ncm,_Costcm,_Maxcm,SumMs0,_Cntcm)), Ms0s),
      sum_list(Ms0s, TotalCtxMsEst),
      OrdMsEst0 is TotalCtxMsEst / Speedup,
      OrdMsEst is round(OrdMsEst0),
      SavedMs is max(0, TotalCtxMsEst - OrdMsEst),
      nl,
      message:header('Estimated ordset impact (from sampled ctx_union sizes)'),
      nl,
      format('  ~w~t~30|: ~d~n',   ['Samples used', SamplesModel]),
      format('  ~w~t~30|: ~d~n',   ['Cost proxy (list)  sum L0*L1', SumMul]),
      format('  ~w~t~30|: ~d~n',   ['Cost proxy (ord)   sum L0+L1', SumAdd]),
      format('  ~w~t~30|: ~2f×~n', ['Estimated speedup factor', Speedup]),
      format('  ~w~t~30|: ~d ms~n',['Total ctx-union-ms (est)', TotalCtxMsEst]),
      format('  ~w~t~30|: ~d ms~n',['Est ctx-union-ms w/ ordsets', OrdMsEst]),
      format('  ~w~t~30|: ~d ms~n',['Est savings', SavedMs])
  ; true
  ).


% -----------------------------------------------------------------------------
%  Largest contexts observed
% -----------------------------------------------------------------------------

stats:test_stats_print_largest_contexts(TopN) :-
  nl,
  message:header(['Top ',TopN,' largest contexts observed']),
  nl,
  findall(MaxLen-PkgAtomLen,
          ( sampler:fact(pkg_ctx(Cc2, Nc2, _SumCtxCost2, MaxLen, _SumCtxMs2, _CntC2)),
            atomic_list_concat([Cc2,Nc2], '/', PkgAtomLen)
          ),
          PkgLen0),
  keysort(PkgLen0, PkgLenAsc),
  reverse(PkgLenAsc, PkgLenSorted),
  ( PkgLenSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Packages', 'max-ctx-len'),
    config:test_stats_table_width(Wlen),
    stats:test_stats_print_ranked_table_rows(PkgLenSorted, TopN, 1, Wlen)
  ).


% -----------------------------------------------------------------------------
%  Slowest packages (max single-entry time)
% -----------------------------------------------------------------------------

stats:test_stats_print_slowest_packages_max(TopN) :-
  nl,
  message:header(['Top ',TopN,' slowest packages (max)']),
  nl,
  findall(MaxMs-C-N, sampler:fact(pkg_time(C, N, _SumTotalMs2, MaxMs, _Cnt2)), PkgMax0),
  keysort(PkgMax0, PkgMaxAsc0),
  reverse(PkgMaxAsc0, PkgMaxSorted0),
  findall(MaxMs-PkgAtom2,
          ( member(MaxMs-C2-N2, PkgMaxSorted0),
            atomic_list_concat([C2,N2], '/', PkgAtom2)
          ),
          PkgMaxSorted),
  ( PkgMaxSorted == [] ->
      writeln('  (none)')
  ; stats:test_stats_print_ranked_table_header('Slowest packages', 'ms'),
    config:test_stats_table_width(Wp2),
    stats:test_stats_print_ranked_table_rows(PkgMaxSorted, TopN, 1, Wp2)
  ).


% -----------------------------------------------------------------------------
%  Assumption detail: per-type and blocker analysis
% -----------------------------------------------------------------------------

% -----------------------------------------------------------------------------
%  Per-type Top-N entries
% -----------------------------------------------------------------------------

stats:test_stats_print_per_type_entries([], _TopN) :- !.
stats:test_stats_print_per_type_entries([Type|Types], TopN) :-
  findall(N-RepoEntry, sampler:fact(type_entry_mention(Type, RepoEntry, N)), P0),
  keysort(P0, PAsc),
  reverse(PAsc, PSorted),
  ( PSorted == [] ->
      true
  ; atomic_list_concat(['Top ',TopN,' entries for ',Type], TypeHeader),
    stats:test_stats_print_ranked_table_header(TypeHeader, 'Occ'),
    config:test_stats_table_width(W),
    stats:test_stats_print_ranked_table_rows(PSorted, TopN, 1, W)
  ),
  stats:test_stats_print_per_type_entries(Types, TopN).


% -----------------------------------------------------------------------------
%  Blocker analysis
% -----------------------------------------------------------------------------

stats:test_stats_print_blocker_analysis(TopN) :-
  ( sampler:fact(type(blocker_assumption, occurrences, BlockOcc)),
    BlockOcc > 0 ->
      stats:test_stats_print_blocker_breakdown(TopN)
  ; true
  ).

stats:test_stats_print_blocker_breakdown(TopN) :-
  % Strength/phase breakdown
  nl,
  message:header('Blocker assumptions (breakdown)'),
  nl,
  stats:test_stats_print_ranked_table_header('Strength/phase', 'Occ'),
  stats:test_stats_blocker_sp_rows(SpSorted),
  ( SpSorted == [] ->
      writeln('  (none)'),
      ( sampler:fact(blocker_example(Ex)) ->
          format('  Note: could not parse blocker term for breakdown; example: ~q~n', [Ex])
      ; true
      )
  ; config:test_stats_table_width(Wsp),
    stats:test_stats_print_ranked_table_rows(SpSorted, 10, 1, Wsp)
  ),

  % Blocker reasons (all phases)
  nl,
  message:header(['Top ',TopN,' blocker reasons']),
  nl,
  stats:test_stats_print_ranked_table_header('Reasons', 'Occ'),
  stats:test_stats_blocker_reason_rows(ReasonRows),
  ( ReasonRows == [] ->
      writeln('  (none)')
  ; config:test_stats_table_width(Wbr),
    stats:test_stats_print_ranked_table_rows(ReasonRows, TopN, 1, Wbr)
  ),

  % Blocker reasons (install)
  nl,
  message:header(['Top ',TopN,' blocker reasons (install)']),
  nl,
  stats:test_stats_print_ranked_table_header('Reasons', 'Occ'),
  stats:test_stats_blocker_reason_phase_rows(install, RInstRows),
  ( RInstRows == [] ->
      writeln('  (none)')
  ; config:test_stats_table_width(Wbri),
    stats:test_stats_print_ranked_table_rows(RInstRows, TopN, 1, Wbri)
  ),

  % Blocker reasons (run)
  nl,
  message:header(['Top ',TopN,' blocker reasons (run)']),
  nl,
  stats:test_stats_print_ranked_table_header('Reasons', 'Occ'),
  stats:test_stats_blocker_reason_phase_rows(run, RRunRows),
  ( RRunRows == [] ->
      writeln('  (none)')
  ; config:test_stats_table_width(Wbrr),
    stats:test_stats_print_ranked_table_rows(RRunRows, TopN, 1, Wbrr)
  ),

  % Most-blocking packages
  nl,
  message:header(['Top ',TopN,' most-blocking packages (C/N)']),
  nl,
  stats:test_stats_print_ranked_table_header('Packages', 'Occ'),
  findall(OccCN-CN,
          ( sampler:fact(blocker_cn(Cb, Nb, OccCN)),
            atomic_list_concat([Cb,Nb], '/', CN)
          ),
          Cn0),
  keysort(Cn0, CnAsc),
  reverse(CnAsc, CnSorted),
  ( CnSorted == [] ->
      writeln('  (none)')
  ; config:test_stats_table_width(Wcn),
    stats:test_stats_print_ranked_table_rows(CnSorted, TopN, 1, Wcn)
  ).


% -----------------------------------------------------------------------------
%  Other assumptions
% -----------------------------------------------------------------------------

stats:test_stats_print_other_assumptions :-
  ( ( sampler:fact(type(other, occurrences, OtherOcc)), OtherOcc > 0 ) ->
      nl,
      findall(N-Key, sampler:fact(other_head(Key, N)), H0),
      keysort(H0, HAsc),
      reverse(HAsc, HSorted),
      stats:test_stats_print_ranked_table_header('Top 15 other assumption heads', 'Count'),
      config:test_stats_table_width(W),
      stats:test_stats_print_ranked_table_rows(HSorted, 15, 1, W)
  ; true
  ).


% -----------------------------------------------------------------------------
%  Cycle mentions
% -----------------------------------------------------------------------------

stats:test_stats_print_cycle_mentions(TopN) :-
  nl,
  atomic_list_concat(['Top ',TopN,' cycle mentions (run)'], HeaderRun),
  findall(N-RepoEntry, sampler:fact(cycle_mention(run, RepoEntry, N)), RunPairs0),
  keysort(RunPairs0, RunSortedAsc),
  reverse(RunSortedAsc, RunSorted),
  ( RunSorted == [] ->
      true
  ; stats:test_stats_print_ranked_table_header(HeaderRun, 'Mentions'),
    config:test_stats_table_width(W1),
    stats:test_stats_print_ranked_table_rows(RunSorted, TopN, 1, W1)
  ),
  atomic_list_concat(['Top ',TopN,' cycle mentions (install)'], HeaderInstall),
  findall(N-RepoEntry, sampler:fact(cycle_mention(install, RepoEntry, N)), InstallPairs0),
  keysort(InstallPairs0, InstallSortedAsc),
  reverse(InstallSortedAsc, InstallSorted),
  ( InstallSorted == [] ->
      true
  ; stats:test_stats_print_ranked_table_header(HeaderInstall, 'Mentions'),
    config:test_stats_table_width(W2),
    stats:test_stats_print_ranked_table_rows(InstallSorted, TopN, 1, W2)
  ).


% -----------------------------------------------------------------------------
%  Data collection helpers
% -----------------------------------------------------------------------------

%! stats:test_stats_ctx_len_bucket(+LenBins, +Threshold, -CountLe)
%
% Count how many samples in LenBins (Len-Count pairs) have Len =< Threshold.

stats:test_stats_ctx_len_bucket(LenBins, Threshold, CountLe) :-
  findall(Cnt,
          ( member(Len-Cnt, LenBins),
            Len =< Threshold
          ),
          Cnts),
  sum_list(Cnts, CountLe).

%! stats:test_stats_blocker_sp_rows(-SpSorted)
%
% Collect blocker strength/phase rows sorted descending by occurrence count.

stats:test_stats_blocker_sp_rows(SpSorted) :-
  findall(Occ-Label,
          ( sampler:fact(blocker_sp(S, P, Occ)),
            format(atom(Label), '~w/~w', [S, P])
          ),
          Sp0),
  keysort(Sp0, SpAsc),
  reverse(SpAsc, SpSorted).

%! stats:test_stats_blocker_reason_rows(-RowsSorted)
%
% Collect blocker reason rows sorted descending by occurrence count.

stats:test_stats_blocker_reason_rows(RowsSorted) :-
  findall(Occ-ReasonAtom,
          ( sampler:fact(blocker_reason(Reason, Occ)),
            format(atom(ReasonAtom), '~w', [Reason])
          ),
          R0),
  keysort(R0, RAsc),
  reverse(RAsc, RowsSorted).

%! stats:test_stats_blocker_reason_phase_rows(+Phase, -RowsSorted)
%
% Collect blocker reason rows for a specific Phase, sorted descending.

stats:test_stats_blocker_reason_phase_rows(Phase, RowsSorted) :-
  findall(Occ-ReasonAtom,
          ( sampler:fact(blocker_rp(Reason, Phase, Occ)),
            format(atom(ReasonAtom), '~w', [Reason])
          ),
          R0),
  keysort(R0, RAsc),
  reverse(RAsc, RowsSorted).

%! stats:test_stats_ctx_share_rows(-ShareRowsSorted)
%
% Build rows for the context-time share table, sorted descending by share.

stats:test_stats_ctx_share_rows(ShareRowsSorted) :-
  findall(Pct10-Label,
          ( sampler:fact(pkg_ctx(C, N, _SumCost, _MaxLen, UnionMs, _CntCtx)),
            UnionMs > 0,
            sampler:fact(pkg_time(C, N, TotalMs, _MaxMs, _CntTime)),
            TotalMs > 0,
            Pct10 is round(UnionMs * 1000 / TotalMs),
            Pct1 is Pct10 / 10,
            atomic_list_concat([C,N], '/', PkgAtomShare),
            format(atom(Label), '~w (~1f%%)', [PkgAtomShare, Pct1])
          ),
          ShareRows0),
  keysort(ShareRows0, ShareRowsAsc),
  reverse(ShareRowsAsc, ShareRowsSorted).