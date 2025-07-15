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

We support any model available on these services. API url, key, model, max_tokens
and temperature are configured in the config module. (cfr. config.pl).

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

LLms can also send each other messages, by embedding the message in specific tags.
Cfr. config.pl for the prompts that explain these capabilities to the LLM.

LLM service specific code can be found in the files inside the 'Llm' subdirectory.
*/


% =============================================================================
%  LLM declarations
% =============================================================================

:- module(llm, [get_input/1]).


%! llm:stream(+Endpoint,+APIkey,+Model,+Message,-Response)
%
% Stream a message to an OpenAI-compatible LLM service.
%
%  - Endpoint: The URL through which the service can be reached
%  - APIkey:   The API key that provides access to the service
%  - Model:    The Large Language Model to be used
%  - Message:  The actual message
%
% The response is written in real-time to the current_output
% stream, and returned as a string through Response.
%
% Cfr config.pl for the different LLM configuration parameter.

llm:stream(Endpoint, APIKey, Model, Messages, Response) :-

  % Retrieve some additional configuration parameters
  config:llm_max_tokens(Max),
  config:llm_temperature(Temperature),

  % This ensures emoji are displayed properly
  set_stream(current_output,encoding(utf8)),

  % A Json payload is prepared
  Payload = _{
    model:       Model,
    messages:    Messages,
    stream:      json_true,
    max_tokens:  Max,
    temperature: Temperature
  },

  % We convert the payload to a Json message, ensuring 'true' is not a string
  % but an actual json true

  with_output_to(string(JsonString),
                 json_write_dict(current_output,
                                 Payload,
                                 [true(json_true),width(0)])),

  % We prepare a http post call of the payload, ensuring authentication
  % and setting streaming

  Headers = [method(post),
             post(string(JsonString)),
             authorization(bearer(APIKey)),
             request_header('Content-Type'='application/json'),
             request_header('Accept'='text/event-stream')],

  catch(( http_open(Endpoint,In,Headers),

          % ensure we support emojo and complex characters
          set_stream(In,encoding(utf8)),

          % stream the message and nicely wrap its output
          setup_call_cleanup((llm:begin_stream(Model)),
                             (llm:process_stream(In,Contents)),
                             (llm:end_stream(Model),
                              close(In))),

          % put the response in the message history
          llm:prepare_history(Contents,Messages,NewMessages),

          % set the response
          Response = _{contents: Contents, history: NewMessages}
        ),
        Error,
        (
          Response = _{error: Error, history: Messages}
        )
   ).


%! llm:begin_stream(+Model)
%
% Execute activities prior to the LLM writing to the current_output stream

llm:begin_stream(Model) :-
  message:color(lightgray),
  message:style(italic),
  message:hl(Model).


%! llm:end_stream(+Model)
%
% Execute activites post the LLM writing to the current_output stream

llm:end_stream(_Model) :-
  nl,
  message:hl,
  message:color(normal),
  message:style(normal).


%! llm:prepare_history(+Contents,+Messages,-NewMessages)
%
% Turn the different stream chuncks into a string representing the complete
% sentence, add this sentence to the message list, with the right OpenAI
% role.

llm:prepare_history(Contents,Messages,NewMessages) :-
  atomic_list_concat(Contents, ResponseContent),
  reverse(Messages, Reversed),
  find_first_assistant(Reversed, LastAssistantMessage),
  put_dict(content, LastAssistantMessage, ResponseContent, UpdatedAssistantMessage),
  (  append(Prefix, [LastAssistantMessage|Rest], Messages)
     -> append(Prefix, [UpdatedAssistantMessage|Rest], NewMessages)
     ;  append(Messages, [UpdatedAssistantMessage], NewMessages) ).


%! llm:process_stream(+Stream,-Contents)
%
% OpenAI-compatible services send us data lines, each embedding a
% part of the message. We need to process the different parts of
% the message, until we receive a message saying the streaming is done.

llm:process_stream(In, Contents) :-
    llm:process_stream(In, Contents, []).


%! llm:process_stream(+Stream,-Contents,-Acc)
%
% Helper predicate. Acc is used to accumulate the message contents.
% We not write each part of the message to the current_output stream
% as soon as we have received it. We don't wait for the full message
% to be received. (LLM Streaming)

llm:process_stream(In, Contents, Acc) :-
    read_line_to_string(In, Line),
    (  Line == end_of_file
    ->  reverse(Acc, Contents)
    ;  Line = ""
    -> llm:process_stream(In,Contents, Acc)
    ;   llm:process_line(Line, Content),
        (   Content == ""
        ->  llm:process_stream(In, Contents, Acc)
        ;   write(Content), flush_output,
            llm:process_stream(In, Contents, [Content|Acc])
        )
    ).


%! llm:process_line(+Line,-Content)
%
% Processes a line of content received from an OpenAI-compatible LLM
% service. A line either contains data, or signals the streaming is done.

process_line(Line, Content) :-
    (   sub_string(Line, 0, 6, _, "data: ")
    ->  sub_string(Line, 6, _, 0, Data),
        (   Data = "[DONE]"
        ->  Content = ""
        ;   atom_json_dict(Data, Dict, []),
            llm:get_content_from_dict(Dict, Content)
        )
    ;   Content = ""
    ).


%! llm:get_content_from_dict(+Dict,-Content)
%
% We receive a json dict structure in a data line from the OpenAI-compatible
% LLM service. This predicate gets the content part out of that dict.

llm:get_content_from_dict(Dict, Content) :-
    get_dict(choices, Dict, Choices),
    Choices = [Choice|_],
    get_dict(delta, Choice, Delta),
    get_dict(content, Delta, Content),
    !.
llm:get_content_from_dict(_,"") :- !.



%! llm:extract_calls(+Contents,-Matches)
%
% In our communication flow, we inform the LLM in the first message that the LLM can
% trigger specific capabilities by using XML tags in the message. We currently have two
% possible messages:
%
%   - <call:swi_prolog> Some prolog code </call:swi_prolog> will execute the prolog
%     code locally in a sandboxed context and send back the result to the LLM.
%
%   - <call:X> Some message </call:X> with X being either grok, gemini, claude, chatgpt
%     or ollama, will send the message between the tags to the mentioned LLM and send
%     back the result to the LLM. This allows LLMs to speak to each other.
%
% Matches is a list of Key-Value pairs. We use a compiled regular expression, which
% keeps performance high, even with long messages.

llm:extract_calls(ResponseContent, Matches) :-
    pcre:re_compile('<call:([a-zA-Z0-9_]+)>(.*?)</call:\\1>', Re, [dotall(true)]),
    pcre:re_foldl(llm:extract_key_value, Re, ResponseContent, [], Matches, [optimize(true), capture_type(string)]).


%! llm:extract_key_value(+Match,-Acc,-Result)
%
% Helper predicate to extract key-value pairs from regex matches

llm:extract_key_value(Match, Acc, [Key-Value|Acc]) :-
    get_dict(1, Match, Key),
    get_dict(2, Match, Value).


%! llm:execute_llm_code(+Src)
%
% We set up a temporary,sandboxed, module in which we load the code passed by the llm.
% This has to be called from within a with_output_to predicate to capture output for
% both regular and error streams.

llm:execute_llm_code(Src) :-
  config:llm_sandboxed_execution(Bool),
  open_chars_stream(Src,Stream),
  call_cleanup(catch((in_temporary_module(Module,
                                   load_files(Module,[stream(Stream),module(Module),sandboxed(Bool)]),
                                   true);true),
                      _Exception,
                      true),
               close(Stream)).


%! llm:execute_and_get_output(+Target-Msg,-Output)
%
% Based on the Target, handle the Message and return Output.

% 1. Speaking to other LLM

llm:execute_and_get_output("grok"-Msg, Output) :-
  grok(Msg,Output).

llm:execute_and_get_output("gemini"-Msg, Output) :-
  gemini(Msg,Output).

llm:execute_and_get_output("claude"-Msg, Output) :-
  claude(Msg,Output).

llm:execute_and_get_output("chatgpt"-Msg, Output) :-
  chatgpt(Msg,Output).

llm:execute_and_get_output("ollama"-Msg, Output) :-
  ollama(Msg,Output).


% 2. Execute SWI-Prolog code safely and capture output

llm:execute_and_get_output("swi_prolog"-Code, Output) :-
    catch(
        (
            %read_term_from_atom(Code, Term, [variable_names(_)]),
            catch(
                with_output_to(
                  string(OutputStr), %(call(Term) -> true ; format(string(OutputStr), 'Goal failed', []))),
                  llm:execute_llm_code(Code),
                  [capture([user_output,user_error]),color(true)]
                ),
                SafeError,
                format(string(OutputStr), 'Execution error: ~w', [SafeError])
            )
        ),
        ReadError,
        format(string(OutputStr), 'Parse error: ~w', [ReadError])
    ),
    Output = OutputStr.


%! llm:make_function_message(+Service,+Content,-Message)
%
% Prepare a json message to be send back to the LLM.
% Write the output to stream, wrapping it as computer output

llm:make_function_message(Service,Content, Message) :-
    % atomic_list_concat(['<command_output:swi_prolog>', Output, '</command_output:swi_prolog>'], Content),
    nl,
    message:hl('computer'),
    message:color(green),
    write(Content),
    message:color(normal),
    message:hl,
    nl,
    (Service = gemini
     -> Message = _{ role: 'user', parts: [ _{function_response: _{ name: 'swi_prolog_exec',response: _{ result_key: Content }}}]}
     ;  Message = _{role: 'function', name: 'swi_prolog_exec', content: Content}).


%! llm:find_first_assistant(+Messages,-Message)
%
% Helper to find the first assistant message in the message list.

llm:find_first_assistant([Message|_Rest], Message) :-
    get_dict(role, Message, 'assistant'), !.
llm:find_first_assistant([_|Rest], Message) :-
    llm:find_first_assistant(Rest, Message).
llm:find_first_assistant([], _{role: 'assistant', content: ''}).



%! llm:handle_response(+ApiKey,+Model,+Endpoint,+HistoryUpdater,+Response,+History)
%
% Called with the response of the LLM, handles execution and message passing to other LLM

llm:handle_response(ServiceAPIKey, ServiceModel, ServiceEndpoint, Service:UpdateHistory, ResponseContent, History) :-
  ( llm:extract_calls(ResponseContent, Pairs),
    Pairs \= []

    ->  % something to process, execute and get ouput:

        maplist(llm:execute_and_get_output, Pairs, Outputs),

        % prepare the automated response to the llm

        maplist(llm:make_function_message(Service), Outputs, FunctionMessages),
        append(History, FunctionMessages, UpdatedHistory),

        % send back the automated response to the llm

        stream(ServiceEndpoint, ServiceAPIKey, ServiceModel, UpdatedHistory, NewResponse),

        % handle the new response from the
        (
            NewResponse = _{contents: NewContents, history: NewerHistory}
            ->
            % keep handling responses

            atomic_list_concat(NewContents, NewResponseContent),
            llm:handle_response(ServiceAPIKey, ServiceModel, ServiceEndpoint, Service:UpdateHistory, NewResponseContent, NewerHistory)

            ;   NewResponse = _{error: NewError, history: _}
                ->  write('Error: '), write(NewError), nl
        )
    ;
       % update the history
       call(Service:UpdateHistory, History)
   ).


%! llm:get_input(Msg)
%
% Launches the configured editor on a temporary file, and returns file contents on editor
% exit. Temporary file is then deleted.
%
% Allows to use vim / your favorite editor to send a message to the LLM

llm:get_input(Msg) :-
    tmp_file(chat_input, File),
    edit(File),
    read_file_to_string(File, Msg, []),
    delete_file(File).


%! llm:prompt(Prompt)
%
% Put together a prompt for the LLM based on capabilities defined in config.pl

llm:prompt(Prompt) :-
  findall(Capability,
          config:llm_capability(_, Capability),
          Cs),
  atomic_list_concat(Cs, ' ', Capabilities),
  PromptEnding = " This was a prompt message, no need to acknowledge or respond to the previous sentences.
                   Everything behind this final sentence is not a prompt and can be reacted to and acknowledged as regular input.",
  normalize_space(string(Ending),PromptEnding),
  string_concat(Capabilities,Ending,Prompt).


%! llm:prepare_message(+History,+Role,+Input,-Messages)
%
% Adds prompt in the first message to the LLM

llm:prepare_message(History,Role,Input,Messages) :-
  llm:add_prompt(History,Input,Msg),
  UserMessage = _{role: Role, content: Msg},
  append(History,[UserMessage],Messages).

llm:add_prompt([],Msg,NewMsg) :-
  !,
  llm:prompt(P),
  string_concat(P,Msg,NewMsg).

llm:add_prompt(_,Msg,Msg) :- !.
