/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GEMINI
Implements interaction with Google Gemini
We implement real-time streaming.

We support any model available, default is set to 'gemini-1.5-flash'.
*/


% =============================================================================
%  GEMINI declarations
% =============================================================================

:- module(gemini, [gemini/0, gemini/1, gemini/2]).

% Dynamic predicate for conversation history
:- dynamic history/1.
history([]).

update_history(History) :-
  retractall(gemini:history(_)),
  assertz(gemini:history(History)).

% Main entry points for Gemini
gemini(Input,ResponseContent) :-
  Service = 'gemini',
  config:llm_api_key(Service, Key),
  config:llm_model(Service, Model),
  config:llm_endpoint(Service,Endpoint),
  history(History),
  llm:prepare_message(History,'user',Input,Messages),
  llm:stream(Endpoint, Key, Model, Messages, Response),
  (Response = _{contents: Contents, history: NewHistory}
  ->  atomic_list_concat(Contents, ResponseContent),
      llm:handle_response(Key, Model, Endpoint, Service:update_history, ResponseContent, NewHistory)
  ;   Response = _{error: Error, history: _}
      ->  write('Error: '), write(Error), nl ),!.

gemini(Input) :-
  gemini(Input,_).

gemini :-
  llm:get_input(Msg),
  gemini(Msg).
