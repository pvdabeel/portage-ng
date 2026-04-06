/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: VARIANTS (multi-variant pretend)
% -----------------------------------------------------------------------------

%! action:run_variants(+VariantsOpt, +Proposal, +BaseProof, +BasePlan, +BaseTriggers) is det.
%
% Detects pivot points and proves variant plans in parallel, then
% prints each variant sequentially with a diff summary.

action:run_variants(VariantsOpt, Proposal, BaseProof, BasePlan, _BaseTriggers) :-
  variant:plan_entries(BasePlan, BaseEntries),
  build_variant_specs(VariantsOpt, Proposal, BaseProof, Specs),
  ( Specs == []
  -> message:inform('No variant pivot points detected.')
  ;  length(Specs, N),
     nl,
     message:color(cyan),
     ( N > 1 -> Plural = 's' ; Plural = '' ),
     format('Proving ~w variant~w in parallel...', [N, Plural]),
     message:color(normal), nl,
     flush_output,
     pipeline:prove_variants_parallel(Proposal, Specs, Results),
     print_variant_results(Results, BaseEntries, 1)
  ).


%! action:build_variant_specs(+Opt, +Proposal, +ProofAVL, -Specs) is det.
%
% Builds variant specifications from the --variants option value.

action:build_variant_specs(auto, Proposal, ProofAVL, Specs) :-
  !,
  variant:detect_pivots(ProofAVL, Proposal, 5, UsePivots, BranchPivots),
  variant:pivots_to_specs(UsePivots, BranchPivots, Specs).

action:build_variant_specs(all, Proposal, ProofAVL, Specs) :-
  !,
  variant:detect_use_pivots(ProofAVL, Proposal, 20, UsePivots),
  variant:pivots_to_specs(UsePivots, [], Specs).

action:build_variant_specs(FlagList, Proposal, ProofAVL, Specs) :-
  atomic_list_concat(Flags, ',', FlagList),
  variant:user_flags_to_specs(Flags, Proposal, ProofAVL, Specs).


%! action:print_variant_results(+Results, +BaseEntries, +N) is det.

action:print_variant_results([], _, _).

action:print_variant_results([variant_result(Spec, failed)|Rest], BaseEntries, N) :-
  !,
  Spec = variant(_, _, _, _, Label),
  nl,
  message:color(cyan),
  format('--- Variant ~w: ~w ---', [N, Label]),
  message:color(normal), nl,
  message:warning(['Variant proof failed.']),
  N1 is N + 1,
  print_variant_results(Rest, BaseEntries, N1).

action:print_variant_results([variant_result(Spec, _Proof, _Model, Plan, _Triggers)|Rest], BaseEntries, N) :-
  Spec = variant(_, _, _, _, Label),
  nl,
  plan:print_variant_header(N, Label),
  variant:plan_entries(Plan, VarEntries),
  length(VarEntries, VarCount),
  variant:plan_diff(BaseEntries, VarEntries, Diff),
  format('  Plan size: ~w actions~n', [VarCount]),
  plan:print_variant_diff(Diff),
  N1 is N + 1,
  print_variant_results(Rest, BaseEntries, N1).