% -----------------------------------------------------------------------------
%  Action: BUG REPORT DRAFTS
% -----------------------------------------------------------------------------

%! action:process_bugs(+ArgsSets, +Options) is det.
%
% Proves the given targets and prints only the domain-assumption bug report
% drafts (Gentoo Bugzilla style), without rendering the full plan.
%
% Example: Source/Application/Wrapper/portage-ng-dev --mode standalone --bugs ghc

process_bugs([], _Options) :-
  !,
  message:inform('Need more arguments').

process_bugs(ArgsSets, Options) :-
  interface:process_mode(Mode),
  interface:process_server(Host,Port),
  eapi:substitute_sets(ArgsSets,Args),
  findall(R://E:run?{[]}, ( member(Arg,Args),
                           atom_codes(Arg,Codes),
                           phrase(eapi:qualified_target(Q),Codes),
                           once(kb:query(Q,R://E))
                         ),
          Proposal),!,
  message:log(['Proposal:  ',Proposal]),
  ( Proposal == [] ->
      message:inform('No matching target found'),
      !
  ; true
  ),
  ( Mode == 'client' ->
      client:rpc_execute(Host,Port,
        ( prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
          action:print_bugreport_drafts_from_proof(ProofAVL)
        ),
        Output),
      writeln(Output)
  ; prover:prove(Proposal,t,ProofAVL,t,_ModelAVL,t,_Constraint,t,_Triggers),
    print_bugreport_drafts_from_proof(ProofAVL),
    ( memberchk(ci(true), Options) ->
        halt(0)
    ; true
    )
  ).

%! action:print_bugreport_drafts_from_proof(+ProofAVL) is det.
%
% Extracts domain assumptions from the proof AVL and delegates to
% warning:print_bugreport_drafts/1. Prints "(none)" when clean.

print_bugreport_drafts_from_proof(ProofAVL) :-
  findall(Content, assoc:gen_assoc(rule(assumed(Content)), ProofAVL, _), DomainAssumptions0),
  sort(DomainAssumptions0, DomainAssumptions),
  ( DomainAssumptions == [] ->
      message:header('Bug report drafts (Gentoo Bugzilla)'),
      nl,
      writeln('  (none)')
  ; warning:print_bugreport_drafts(DomainAssumptions)
  ).


% -----------------------------------------------------------------------------
%  Action: Search bugs (Bugzilla quicksearch)
% -----------------------------------------------------------------------------

%! action:process_search_bugs(+Args, +Options) is det.
%
% Searches Bugzilla for bugs matching the given terms.
% Args are joined as the search query. With no args, shows usage.

process_search_bugs(Args, _Options) :-
  bugs:check(Args).