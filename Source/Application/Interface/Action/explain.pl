/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: EXPLAIN (LLM-powered plan Q&A)
% -----------------------------------------------------------------------------

%! action:run_explain(+ExplainOpt, +Proposal, +ProofAVL, +ModelAVL, +Plan, +TriggersAVL) is det.
%
% Dispatches to the explain module. Requires LLM modules to be loaded.
% ExplainOpt is either 'true' (conversational mode) or a question atom
% (single-shot mode).

action:run_explain(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL) :-
  ( predicate_property(explain:explain_plan(_,_,_,_,_,_), defined)
  -> ( ExplainOpt == true
     -> explain:explain_plan_interactive(Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL)
     ;  explain:explain_plan(ExplainOpt, Proposal, ProofAVL, ModelAVL, Plan, TriggersAVL)
     )
  ;  message:warning('--explain requires LLM support. LLM modules are not loaded.')
  ).


% -----------------------------------------------------------------------------
%  Action: LLM chat
% -----------------------------------------------------------------------------

%! action:extract_llm_opt(+Options, -LlmOpt) is semidet.
%
% Succeeds when --llm was passed on the command line. Unifies LlmOpt
% with 'true' when no service name was given, or the service name atom.

action:extract_llm_opt(Options, LlmOpt) :-
  memberchk(llm(Val), Options),
  Val \== none,
  ( Val == '' -> LlmOpt = true ; LlmOpt = Val ).


%! action:process_llm_chat(+LlmOpt) is det.
%
% Starts an interactive chat session with the specified LLM service.
% LlmOpt is either 'true' (use default service) or a service name atom.

action:process_llm_chat(LlmOpt) :-
  ( predicate_property(explainer:call_llm(_,_,_), defined)
  -> ( LlmOpt == true
     -> config:llm_default(Service)
     ;  Service = LlmOpt
     ),
     ( config:llm_model(Service, Model)
     -> nl,
        message:color(cyan),
        format('Chat session with ~w (~w). Type "quit" or "exit" to leave.~n', [Service, Model]),
        message:color(normal),
        nl,
        llm_chat_loop(Service)
     ;  message:warning(['Unknown LLM service: ', Service,
                         '. Available: claude, grok, chatgpt, gemini, ollama.'])
     )
  ;  message:warning('--llm requires LLM support. LLM modules are not loaded.')
  ).


%! action:llm_chat_loop(+Service) is det.
%
% Interactive read-eval-print loop for LLM chat. Reads user input,
% sends it to the LLM service, prints the streamed response, and
% recurses until the user types quit/exit/q or EOF.

action:llm_chat_loop(Service) :-
  message:color(green),
  format('~w> ', [Service]),
  message:color(normal),
  flush_output,
  catch(
    read_line_to_string(user_input, Line),
    _,
    Line = end_of_file
  ),
  ( Line == end_of_file
  -> nl
  ; string_lower(Line, Lower),
    ( member(Lower, ["quit", "exit", "q"])
    -> true
    ; Line == ""
    -> llm_chat_loop(Service)
    ; nl,
      explainer:call_llm(Service, Line, _Response),
      nl, nl,
      llm_chat_loop(Service)
    )
  ).