/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LLAMA
Implements interaction with Meta Llama
We implement real-time streaming.

We support any model available, default is set to 'Llama-4-Maverick'.

Streaming to Claude follows OpenAI standards, but the response is in a specific
format, different from OpenAI. We define the Llama specific protocol in this file.
*/


% ******************
% LLAMA declarations
% ******************

:- module(llama, [llama/0, llama/1]).

% Dynamic predicate for conversation history
:- dynamic history/1.
history([]).

update_history(History) :-
  retractall(llama:history(_)),
  assertz(llama:history(History)).

% Llama-specific streaming chat function
llm_stream_llama(Endpoint, APIKey, Model, Messages, Response) :-
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
               authorization(bearer(APIKey)),
               request_header('Content-Type'='application/json'),
               request_header('Accept'='text/event-stream')],

    catch(
        (
            http_open(Endpoint, In, Headers),
            set_stream(In, encoding(utf8)),

            message:color(lightgray),
            message:style(italic),
            message:hl(Model),

            process_stream_llama(In, Contents),
            close(In),

	    nl,
            message:hl,
            message:color(normal),
            message:style(normal),

            atomic_list_concat(Contents, ResponseContent),
            % Find the last assistant message
            reverse(Messages, Reversed),
            find_first_assistant(Reversed, LastAssistantMessage),
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

% Process the streaming response for LLaMA
process_stream_llama(In, Contents) :-
    process_stream_llama(In, Contents, [], no).

process_stream_llama(In, Contents, Acc, ExpectingData) :-
    read_line_to_string(In, Line),
    (   Line == end_of_file
    ->  reverse(Acc, Contents)
    ;   (   ExpectingData == yes,
            sub_string(Line, 0, 6, _, "data: ")
        ->  sub_string(Line, 6, _, 0, Data),
            (   Data == "[DONE]"
            ->  Content = ""
            ;   catch(json_read_dict(Data, Dict), _, fail),
                (   get_dict(completion_message, Dict, Completion),
                    get_dict(delta, Completion, Delta),
                    get_dict(text, Delta, Content)
                ->  true
                ;   Content = ""
                )
            ),
            (   Content \= ""
            ->  write(Content), flush_output,
                NewAcc = [Content | Acc]
            ;   NewAcc = Acc
            ),
            process_stream_llama(In, Contents, NewAcc, no)
        ;   sub_string(Line, 0, 7, _, "event: "),
            sub_string(Line, 7, _, 0, Event),
            (   Event == "completion_message_delta"
            ->  process_stream_llama(In, Contents, Acc, yes)
            ;   Event == "error"
            ->  read_line_to_string(In, ErrorLine),
                (   sub_string(ErrorLine, 0, 6, _, "data: ")
                ->  sub_string(ErrorLine, 6, _, 0, ErrorData),
                    catch(json_read_dict(ErrorData, ErrorDict), _, fail),
                    (   get_dict(error, ErrorDict, ErrorInfo)
                    ->  get_dict(message, ErrorInfo, ErrorMessage),
                        write('Error: '), write(ErrorMessage), nl
                    ;   true
                    )
                ;   true
                ),
                process_stream_llama(In, Contents, Acc, no)
            ;   process_stream_llama(In, Contents, Acc, no)
            )
        ;   process_stream_llama(In, Contents, Acc, no)
        )
    ).

% LLaMA specific streaming chat callback
llama_llm_stream(APIKey, Model, History, Query, Response) :-
    llama_endpoint(Endpoint),
    UserMessage = _{role: user, content: Query},
    append(History, [UserMessage], Messages),
    llm_stream_llama(Endpoint, APIKey, Model, Messages, Response).

% Main entry points for Llama
llama(Input) :-
  Service = 'llama',
  config:llm_api_key(Service,Key),
  config:llm_model(Service,Model),
  config:llm_endpoint(Service,Endpoint),
  history(History),
  llm:prepare_message(History,'user',Input,Messages),
  llm_stream_llama(Endpoint, Key, Model, Messages, Response),
  (Response = _{contents: Contents, history: NewHistory}
   ->  atomic_list_concat(Contents, ResponseContent),
       handle_response(Key, Model, Endpoint, Service:update_history, ResponseContent, NewHistory)
   ;   Response = _{error: Error, history: _}
       ->  write('Error: '), write(Error), nl ).

llama :-
    get_input(Msg),
    llama(Msg).
