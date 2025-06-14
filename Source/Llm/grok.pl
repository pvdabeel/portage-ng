/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GROK
Implements interaction with x.AI Grok
We implement real-time streaming.

We support any model available, default is set to 'gpt-3'.
*/


% *****************
% GROK declarations
% *****************

:- module(grok, [grok/0, grok/1]).

% Dynamic predicate for conversation history
:- dynamic grok_history/1.
grok_history([]).

% Service-specific helpers
service_history('grok', History) 	:- grok_history(History).

update_history('grok', History) :-
    retractall(grok_history(_)),
    assertz(grok_history(History)).

% Main entry points for Grok
grok(Input) :-
    Service = 'grok',
    config:llm_api_key(Service,Key),
    config:llm_model(Service,Model),
    config:llm_endpoint(Service,Endpoint),
    service_history(Service,History),
    (History == []
     -> llm:prompt(Prompt),
        string_concat(Prompt,Input,Msg)
     ; Msg = Input),
    UserMessage = _{role: 'user', content: Msg},
    append(History, [UserMessage], Messages),
    llm:llm_stream(Endpoint, Key, Model, Messages, Response),
    (   Response = _{contents: Contents, history: NewHistory}
    ->  atomic_list_concat(Contents, ResponseContent),
        llm:handle_response(Key, Model, Endpoint, grok:update_history(Service), ResponseContent, NewHistory)
    ;   Response = _{error: Error, history: _}
    ->  write('Error: '), write(Error), nl
    ).


grok :-
    llm:get_input(Msg),
    grok(Msg).
