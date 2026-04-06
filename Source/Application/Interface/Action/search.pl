/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% -----------------------------------------------------------------------------
%  Action: SEARCH
% -----------------------------------------------------------------------------

%! action:process_action(+search, +Args, +Options) is det.
%
% Handles the --search CLI flag. When the query parses as a structured
% key=value expression, performs a knowledge base search. Otherwise
% falls back to semantic (natural-language) search.

action:process_action(search,[],_) :-
  !,
  message:failure('Usage: portage-ng --search key=value | natural language query (e.g. name=gcc, or: text editor with syntax highlighting)').

action:process_action(search,Args,_Options) :-
  !,
  ( phrase(eapi:query(Q), Args)
  -> message:log(['Query:   ',Q]),
     aggregate_all(count, kb:query(Q, _), Count),
     forall(kb:query(Q, R://E), writeln(R://E)),
     ( Count =:= 0
     -> message:inform('No matching packages found.')
     ;  true
     )
  ; atomic_list_concat(Args, ' ', Query),
    process_semantic_search(Query)
  ).


% -----------------------------------------------------------------------------
%  Action: Semantic search (natural-language fallback)
% -----------------------------------------------------------------------------

%! action:process_semantic_search(+Query) is det.
%
% Fall back to semantic search when the query does not parse as a
% structured key=value expression. Checks the config toggle first;
% when the semantic module is not loaded, stubs.pl provides graceful
% fallback predicates.

action:process_semantic_search(Query) :-
  ( \+ catch(config:semantic_search_enabled(true), _, fail)
  -> message:warning(['Semantic search is disabled. Set config:semantic_search_enabled(true) to enable it.'])
  ; message:inform(['Semantic search: "', Query, '"']),
    config:semantic_top_n(TopN),
    ( catch(semantic:search(Query, TopN, Results), _, fail)
    -> semantic:print_results(Results)
    ; message:warning(['Semantic search unavailable. Run --train-model with Ollama running to build the index.'])
    )
  ).


% -----------------------------------------------------------------------------
%  Action: Train model (build semantic embedding index)
% -----------------------------------------------------------------------------

%! action:process_train_model is det.
%
% Build the semantic search embedding index from the current knowledge base.
% When the semantic module is not loaded, stubs.pl provides a graceful
% fallback.

action:process_train_model :-
  ( \+ catch(config:semantic_search_enabled(true), _, fail)
  -> message:warning(['Semantic search is disabled. Set config:semantic_search_enabled(true) to enable it.'])
  ; semantic:build_index
  ).


% -----------------------------------------------------------------------------
%  Action: Similar packages
% -----------------------------------------------------------------------------

%! action:process_similar(+Args) is det.
%
% Find packages semantically similar to the given target(s).
% Accepts category/name or bare package name arguments.

action:process_similar([]) :-
  message:failure('Usage: portage-ng --similar category/name').

action:process_similar(Args) :-
  ( \+ catch(config:semantic_search_enabled(true), _, fail)
  -> message:warning(['Semantic search is disabled. Set config:semantic_search_enabled(true) to enable it.'])
  ; config:semantic_top_n(TopN),
    forall(member(Arg, Args),
      ( interface:resolve_pkg_arg(Arg, Cat, Name)
      -> message:inform(['Packages similar to ', Cat, '/', Name, ':']),
         ( catch(semantic:similar(Cat, Name, TopN, Results), _, fail)
         -> semantic:print_results(Results)
         ; message:warning(['Could not find similar packages. Run --train-model to build the index.'])
         )
      ; message:warning(['Package not found: ', Arg])
      ))
  ).