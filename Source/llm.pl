/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LLM
LLM implements interaction with publicly and privately hosted Large Language Model
services. We implement real-time streaming for OpenAI-compatible services.

Currently the following services are available:

- Grok
- ChatGPT
- LLama
- Gemini
- Claude

We also support real-time streaming to Ollama. (E.g. locally hosted)

We support any model available on these services.

Standard features include:

- Real-time (word by word) output of LLM stream to standard output,
- Output to Prolog string,
- Support for emoji and complex language characters (UTF-8),
- Input via Prolog string or integration with edit/1,
- Chat history per service,

Execution of commands:

- LLMs can embed prolog code in specific tags and have that code executed locally
- The code is executed in a sandbox, ensuring access to safe predicates only
- The output is captured and provided back to the LLM for evaluation

LLM service specific code can be found in the files inside the 'Llm' subdirectory.
*/


% ****************
% LLM declarations
% ****************

:- module(llm, [stream/5, process_stream/3, process_line/2, get_content_from_dict/2, get_input/1, extract_swi_prolog_calls/2, execute_and_get_output/2, make_function_message/2, find_first_assistant/2, handle_response/6]).

:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(edit)).
:- use_module(library(pcre)).
:- use_module(library(sandbox)).


% Streaming chat function for OpenAI-compatible services
stream(Endpoint, APIKey, Model, Messages, Response) :-
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

            process_stream(In, Contents),
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

% Process the streaming response for OpenAI-compatible services
process_stream(In, Contents) :-
    process_stream(In, Contents, []).

process_stream(In, Contents, Acc) :-
    read_line_to_string(In, Line),
    (  Line == end_of_file
    ->  reverse(Acc, Contents)
    ;  Line = ""
    -> process_stream(In,Contents, Acc)
    ;   process_line(Line, Content),
        (   Content == ""
        ->  process_stream(In, Contents, Acc)
        ;   write(Content), flush_output,
            process_stream(In, Contents, [Content|Acc])
        )
    ).

process_line(Line, Content) :-
    (   sub_string(Line, 0, 6, _, "data: ")
    ->  sub_string(Line, 6, _, 0, Data),
        (   Data = "[DONE]"
        ->  Content = ""
        ;   atom_json_dict(Data, Dict, []),
            get_content_from_dict(Dict, Content)
        )
    ;   Content = ""
    ).

get_content_from_dict(Dict, Content) :-
    get_dict(choices, Dict, Choices),
    Choices = [Choice|_],
    get_dict(delta, Choice, Delta),
    get_dict(content, Delta, Content),
    !.
get_content_from_dict(_,"") :- !.


% Extract SWI-Prolog calls from response content
extract_swi_prolog_calls(ResponseContent, Matches) :-
    pcre:re_compile('<call:swi_prolog>(.*?)</call:swi_prolog>', Re, [dotall(true)]),
    pcre:re_foldl(llm:get_group,Re, ResponseContent, [], Matches, [optimize(true),capture_type(string)]).

get_group(Match, Acc, [Group|Acc]) :-
    get_dict(1, Match, Group).

% Sandboxed execution in a temporary module
execute_llm_code(Src) :-
  config:llm_sandboxed_execution(Bool),
  open_chars_stream(Src,Stream),
        in_temporary_module(Module,
    load_files(Module,[stream(Stream),module(Module),sandboxed(Bool)]),
    true),
  close(Stream).

% Execute SWI-Prolog code safely and capture output
execute_and_get_output(Code, Output) :-
    catch(
        (
            %read_term_from_atom(Code, Term, [variable_names(_)]),
            catch(
                with_output_to(
                  string(OutputStr), %(call(Term) -> true ; format(string(OutputStr), 'Goal failed', []))),
                  execute_llm_code(Code)
                  %[capture([user_output,user_error]),color(true)]
                ),
                SafeError,
                format(string(OutputStr), 'Execution error: ~w', [SafeError])
            )
        ),
        ReadError,
        format(string(OutputStr), 'Parse error: ~w', [ReadError])
    ),
    Output = OutputStr.

% Make function message
make_function_message(Content, Message) :-
    %atomic_list_concat(['<command_output:swi_prolog>', Output, '</command_output:swi_prolog>'], Content),
    nl,
    message:hl('computer'),
    message:color(green),
    write(Content),
    message:color(normal),
    message:hl,
    nl,
    Message = _{role: 'function', name: 'swi_prolog_exec', content: Content}.

% Helper to find the first assistant message from the end
find_first_assistant([Message|_Rest], Message) :-
    get_dict(role, Message, 'assistant'), !.
find_first_assistant([_|Rest], Message) :-
    find_first_assistant(Rest, Message).
find_first_assistant([], _{role: 'assistant', content: ''}).

% Handle response with code execution
handle_response(ServiceAPIKey, ServiceModel, ServiceEndpoint, Service:UpdateHistory, ResponseContent, History) :-
  ( extract_swi_prolog_calls(ResponseContent, Codes),
    Codes \= []
    ->  maplist(execute_and_get_output, Codes, Outputs),
        maplist(make_function_message, Outputs, FunctionMessages),
        append(History, FunctionMessages, UpdatedHistory),
        stream(ServiceEndpoint, ServiceAPIKey, ServiceModel, UpdatedHistory, NewResponse),
        (   NewResponse = _{contents: NewContents, history: NewerHistory}
        ->
            atomic_list_concat(NewContents, NewResponseContent),
            handle_response(ServiceAPIKey, ServiceModel, ServiceEndpoint, Service:UpdateHistory, NewResponseContent, NewerHistory)
        ;   NewResponse = _{error: NewError, history: _}
        ->  write('Error: '), write(NewError), nl
        )
    ;   %write(ResponseContent), nl,
        call(Service:UpdateHistory, History)
    ).

% Input handling
get_input(Msg) :-
    tmp_file(chat_input, File),
    edit(File),
    read_file_to_string(File, Msg, []),
    delete_file(File).

% Informs the LLM about our capabilities
prompt(Capabilities) :-
  Capabilities = "If you send me SWI-prolog code, embedded between <TAG> and </TAG> where TAG is replaced with call:swi_prolog, this code will be executed locally and the output will be send back to you automatically. Do not mention the tags if you have not got swi-prolog code in between. After I have send you the output, you can also embed SWI-prolog code in your response between the tags. The code you write between tags is executed in a temporary module, in which your source code is loaded; write your code like it would be loaded from a separate source file. This implies you have to trigger execution of own main function using :- <yourmainfunction>. Like you would in separate source file. This is a prompt, no need to confirm or aknowledge. Everthing behind this is not a prompt and can be aknowledged or reacted to. ".

% Adds prompt tp to the first message to the LLM

prepare_message(History,Role,Input,Messages) :-
  add_prompt(History,Input,Msg),
  UserMessage = _{role: Role, content: Msg},
  append(History,[UserMessage],Messages).

add_prompt([],Msg,NewMsg) :-
  !,
  prompt(P),
  string_concat(P,Msg,NewMsg).

add_prompt(_,Msg,Msg) :- !.

