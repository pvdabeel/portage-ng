/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CHATGPT
Implements interaction with OpenAI ChatGPT
We implement real-time streaming.

We support any model available, default is set to 'gpt-4.1'.
*/


% =============================================================================
%  CHATGPT declarations
% =============================================================================

:- module(chatgpt, [chatgpt/0, chatgpt/1, chatgpt/2]).

% Dynamic predicate for conversation history
:- dynamic history/1.

history([]).

update_history(History) :-
  retractall(chatgpt:history(_)),
  assertz(chatgpt:history(History)).

% Main entry points for ChatGPT
chatgpt(Input,ResponseContent) :-
  Service = 'chatgpt',
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

chatgpt(Input) :-
  chatgpt(Input,_).

chatgpt :-
    llm:get_input(Msg),
    chatgpt(Msg).
