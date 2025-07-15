/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> OLLAMA
Implements interaction with Ollama (typically locally running)
We implement real-time streaming.

We support any model available, default is set to 'llama3.2'.
*/


% =============================================================================
%  OLLAMA declarations
% =============================================================================

:- module(ollama, [ollama/0, ollama/1, ollama/2]).

% Dynamic predicate for conversation history
:- dynamic history/1.
history([]).

update_history(History) :-
  retractall(ollama:history(_)),
  assertz(ollama:history(History)).

% Main entry points for Ollama
ollama(Input,ResponseContent) :-
  Service = 'ollama',
  config:llm_api_key(Service,Key),
  config:llm_model(Service,Model),
  config:llm_endpoint(Service,Endpoint),
  history(History),
  llm:prepare_message(History,'user',Input,Messages),
  llm:stream(Endpoint, Key, Model, Messages, Response),
  (Response = _{contents: Contents, history: NewHistory}
   ->  atomic_list_concat(Contents, ResponseContent),
       llm:handle_response(Key, Model, Endpoint, Service:update_history, ResponseContent, NewHistory)
   ;   Response = _{error: Error, history: _}
       ->  write('Error: '), write(Error), nl ),!.

ollama(Input) :-
  ollama(Input,_).

ollama :-
  get_input(Msg),
  ollama(Msg).
