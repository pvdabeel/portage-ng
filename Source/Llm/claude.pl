/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CLAUDE
Implements interaction with Anthropic Claude.
We implement real-time streaming.

We support any model available, default is set to 'claude-3-7-sonnet'.

Interfacing with Claude requires a specific protocol, different from OpenAI.
We define the Claude specific protocol in this file.
*/


% =============================================================================
%  CLAUDE declarations
% =============================================================================

:- module(claude, [claude/0, claude/1, claude/2]).


% Dynamic predicate for conversation history
:- dynamic history/1.
history([]).

update_history(History) :-
  retractall(claude:history(_)),
  assertz(claude:history(History)).

% Claude-specific streaming chat function
llm_stream_claude(Endpoint, APIKey, Model, Messages, Response) :-
    config:llm_max_tokens(Max),
    config:llm_temperature(Temperature),
    set_stream(current_output, encoding(utf8)),
    Payload = _{
        model: Model,
        messages: Messages,
        stream: json_true,
        max_tokens: Max,
        temperature: Temperature
    },
    with_output_to(string(JsonString),
		    json_write_dict(current_output, Payload, [true(json_true), width(0)])),
    Headers = [method(post),
               post(string(JsonString)),
               request_header('x-api-key'=APIKey),
               request_header('anthropic-version'='2023-06-01'),
               request_header('Content-Type'='application/json'),
               request_header('Accept'='text/event-stream')],

    catch(
        (
            http_open(Endpoint, In, Headers),
            set_stream(In, encoding(utf8)),

            message:color(lightgray),
            message:style(italic),
            message:hl(Model),

	    process_stream_claude(In, Contents),
            close(In),

            nl,
            message:hl,
            message:color(normal),
            message:style(normal),

            atomic_list_concat(Contents, ResponseContent),

            % Find the last assistant message
            reverse(Messages, Reversed),
            llm:find_first_assistant(Reversed, LastAssistantMessage),
            % Update the last assistant message with full content
            put_dict(content, LastAssistantMessage, ResponseContent, UpdatedAssistantMessage),
            % Replace the last message in Messages with UpdatedAssistantMessage
            (  append(Prefix, [LastAssistantMessage|Rest], Messages)
            -> append(Prefix, [UpdatedAssistantMessage|Rest], NewMessages)
            ;  append(Messages, [UpdatedAssistantMessage], NewMessages) ),
            Response = _{contents: Contents, history: NewMessages}
        ),
        Error,
        (
            Response = _{error: Error, history: Messages}
        )
    ).

% Process the streaming response for Claude
process_stream_claude(In, Contents) :-
    process_stream_claude(In, Contents, []). % Initial call with accumulator

process_stream_claude(In, Contents, Acc) :-
    read_line_to_string(In, Line),
    (   Line == end_of_file
    ->  reverse(Acc, Contents)
    ;   % Handle 'event:' lines
        (   sub_string(Line, 0, 7, _, 'event: ')
        ->  % We can log the event type if needed for debugging
            % sub_string(Line, 7, _, 0, EventType),
            % format('~NEvent: ~w~n', [EventType]),
            process_stream_claude(In, Contents, Acc) % Continue reading after an event
        % Handle 'data:' lines
        ;   sub_string(Line, 0, 6, _, "data: ")
        ->  sub_string(Line, 6, _, 0, Data),
            (   Data == "[DONE]"
            ->  reverse(Acc, Contents) % Stream is done
            ;   % Attempt to parse JSON data
                (   atom_json_dict(Data, Dict, []) % Use atom_json_dict for direct JSON atom parsing
                ->  (   get_dict(type, Dict, "content_block_delta") % Look for content delta specifically
                    ->  get_dict(delta, Dict, Delta),
                        get_dict(text, Delta, Content)
                    ;   % Handle other data types or ignore if not content delta
                        % For example, message_delta might also have content
                        (   get_dict(type, Dict, "message_delta"),
                            get_dict(delta, Dict, MessageDelta),
                            get_dict(text, MessageDelta, Content)
                        )
                        ->  true
                        ;   Content = "" % No relevant content found in this data block
                    )
                ;   Content = "" % JSON parsing failed
                ),
                (   Content \= ""
                ->  write(Content), flush_output,
                    process_stream_claude(In, Contents, [Content | Acc])
                ;   process_stream_claude(In, Contents, Acc) % No content, just continue
                )
            )
        % Ignore empty lines or other non-event/non-data lines
        ;   process_stream_claude(In, Contents, Acc)
        )
    ).


% Claude specific streaming chat callback
claude_llm_stream(APIKey, Model, History, Query, Response) :-
    config:llm_endpoint(claude,Endpoint),
    UserMessage = _{role: user, content: Query},
    append(History, [UserMessage], Messages),
    llm_stream_claude(Endpoint, APIKey, Model, Messages, Response).

% Main entry points for Claude
claude(Input,ResponseContent) :-
  Service = 'claude',
  config:llm_api_key(Service,Key),
  config:llm_model(Service,Model),
  config:llm_endpoint(Service,Endpoint),
  history(History),
  llm:prepare_message(History,'user',Input,Messages),
  llm_stream_claude(Endpoint, Key, Model, Messages, Response),
  (Response = _{contents: Contents, history: NewHistory}
   ->  atomic_list_concat(Contents, ResponseContent),
       llm:handle_response(Key, Model, Endpoint, Service:update_history, ResponseContent, NewHistory)
   ;   Response = _{error: Error, history: _}
       ->  write('Error: '), write(Error), nl ),!.

claude(Input) :-
  claude(Input,_).

claude :-
  llm:get_input(Msg),
  claude(Msg).
