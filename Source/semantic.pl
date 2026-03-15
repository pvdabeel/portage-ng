/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> SEMANTIC
Semantic search over the package knowledge base using vector embeddings.

Generates embeddings for package descriptions via a locally running Ollama
instance and stores them for fast cosine-similarity lookup. Queries are
embedded at search time and matched against the stored index.

Designed to leverage Apple Silicon's GPU/Neural Engine through Ollama's
Metal backend.
*/

:- module(semantic, []).

% =============================================================================
%  SEMANTIC declarations
% =============================================================================

:- dynamic semantic:embedding/3.
:- dynamic semantic:index_loaded/0.


% -----------------------------------------------------------------------------
% Configuration (delegates to config module)
% -----------------------------------------------------------------------------

%! semantic:embedding_model(-Model) is det.
%
% The Ollama model used for generating embeddings.
% Reads from config:semantic_model/1.

semantic:embedding_model(Model) :-
  config:semantic_model(Model).


%! semantic:embedding_endpoint(-URL) is det.
%
% The Ollama embeddings API endpoint.
% Reads from config:semantic_endpoint/1.

semantic:embedding_endpoint(Endpoint) :-
  config:semantic_endpoint(Endpoint).


%! semantic:index_file(-Path) is det.
%
% Path to the serialized embedding index.

semantic:index_file(Path) :-
  absolute_file_name(portage('Knowledge/embeddings.pl'), Path).


% -----------------------------------------------------------------------------
% Embedding generation
% -----------------------------------------------------------------------------

%! semantic:embed_text(+Text, -Embedding) is semidet.
%
% Generate an embedding vector for Text via the Ollama API.
% Handles both /api/embeddings (legacy) and /api/embed (current) response
% formats.

semantic:embed_text(Text, Embedding) :-
  semantic:embedding_model(Model),
  semantic:embedding_endpoint(Endpoint),
  Payload = _{model: Model, input: Text},
  catch(
    ( http_open(Endpoint, In,
                [method(post), post(json(Payload)),
                 request_header('Content-Type'='application/json')]),
      call_cleanup(
        json_read_dict(In, Response),
        close(In)),
      semantic:extract_embedding(Response, Embedding)
    ),
    _Error,
    fail
  ).


%! semantic:extract_embedding(+Response, -Embedding) is semidet.
%
% Extract the embedding vector from an Ollama response dict.
% Supports both response formats:
%   /api/embeddings (legacy): {"embedding": [...]}
%   /api/embed (current):     {"embeddings": [[...]]}

semantic:extract_embedding(Response, Embedding) :-
  ( is_dict(Response),
    get_dict(embedding, Response, E),
    is_list(E), E \== []
  -> Embedding = E
  ; is_dict(Response),
    get_dict(embeddings, Response, Es),
    is_list(Es), Es = [E|_],
    is_list(E), E \== []
  -> Embedding = E
  ).


%! semantic:package_text(+Repo, +Entry, -Text) is semidet.
%
% Build a textual representation of a package for embedding.
% Concatenates category/name, description, and USE flags.

semantic:package_text(Repo, Entry, Text) :-
  cache:ordered_entry(Repo, Entry, Category, Name, _Version),
  ( cache:entry_metadata(Repo, Entry, description, Desc),
    Desc \== ''
  -> true
  ; Desc = ''
  ),
  ( findall(U, ( cache:entry_metadata(Repo, Entry, iuse, Raw),
                 eapi:strip_use_default(Raw, U) ), Flags),
    Flags \== []
  -> atomic_list_concat(Flags, ' ', UseLine)
  ; UseLine = ''
  ),
  format(atom(Text), '~w/~w: ~w [~w]', [Category, Name, Desc, UseLine]).


% -----------------------------------------------------------------------------
% Index building
% -----------------------------------------------------------------------------

%! semantic:build_index is det.
%
% Generate embeddings for all unique category/name pairs in the knowledge
% base using the latest version's metadata. Stores results as
% semantic:embedding/3 facts and saves to disk.

semantic:build_index :-
  semantic:check_ollama,
  !,
  message:inform('Building semantic search index...'),
  retractall(semantic:embedding(_, _, _)),
  retractall(semantic:index_loaded),
  findall(Repo-Cat-Name,
    ( cache:package(Repo, Cat, Name) ),
    Packages),
  sort(Packages, UniquePackages),
  length(UniquePackages, Total),
  message:inform(['Embedding ', Total, ' packages...']),
  semantic:embed_packages(UniquePackages, 0, Total),
  semantic:save_index,
  assertz(semantic:index_loaded),
  semantic:count_embeddings(Indexed),
  message:inform(['Semantic index built: ', Indexed, ' / ', Total, ' packages.']).

semantic:build_index :-
  message:warning(['Aborted: could not connect to Ollama.']).


%! semantic:check_ollama is semidet.
%
% Verify that Ollama is reachable and the configured embedding model
% is available. Fails with a warning if not.

semantic:check_ollama :-
  semantic:embedding_endpoint(Endpoint),
  message:log(['Testing Ollama at ', Endpoint, '...']),
  ( semantic:embed_text("test", TestEmb)
  -> semantic:log_check_ok(TestEmb)
  ; message:warning(['Could not obtain an embedding from ', Endpoint, '.']),
    message:warning(['Ensure Ollama is running (ollama serve) and the model is pulled (ollama pull nomic-embed-text).']),
    fail
  ).


%! semantic:log_check_ok(+Embedding) is det.
%
% Log a successful Ollama connectivity check with the embedding dimension.

semantic:log_check_ok(Embedding) :-
  length(Embedding, Dim),
  message:log(['Ollama OK: embedding dimension = ', Dim]).


%! semantic:count_embeddings(-N) is det.
%
% Count the number of stored embeddings.

semantic:count_embeddings(N) :-
  aggregate_all(count, semantic:embedding(_, _, _), N).


%! semantic:embed_packages(+Packages, +Done, +Total) is det.
%
% Embed each category/name pair, using the latest version's description.

semantic:embed_packages([], _, _).

semantic:embed_packages([Repo-Cat-Name|Rest], Done, Total) :-
  ( cache:ordered_entry(Repo, Entry, Cat, Name, _),
    semantic:package_text(Repo, Entry, Text),
    semantic:embed_text(Text, Embedding),
    semantic:normalize_vector(Embedding, Normalized)
  -> assertz(semantic:embedding(Cat, Name, Normalized)),
     Done1 is Done + 1,
     ( Done1 mod 100 =:= 0
     -> format(user_error, '\r  ~w / ~w', [Done1, Total]),
        flush_output(user_error)
     ; true
     )
  ; ( Done =:= 0
    -> message:warning(['Failed to embed first package: ', Cat, '/', Name]),
       semantic:diagnose_first_failure(Repo, Cat, Name)
    ; true
    ),
    Done1 is Done + 1
  ),
  !,
  semantic:embed_packages(Rest, Done1, Total).


%! semantic:diagnose_first_failure(+Repo, +Cat, +Name) is det.
%
% Report which step fails for the first package that could not be embedded.

semantic:diagnose_first_failure(Repo, Cat, Name) :-
  ( cache:ordered_entry(Repo, Entry, Cat, Name, _)
  -> ( semantic:package_text(Repo, Entry, Text)
     -> ( catch(semantic:embed_text(Text, _Emb), Err,
               (message:warning(['  embed_text threw: ', Err]), fail))
        -> message:warning(['  normalize_vector failed'])
        ; message:warning(['  embed_text failed for: ', Text])
        )
     ; message:warning(['  package_text failed for entry: ', Entry])
     )
  ; message:warning(['  No ordered_entry found for ', Cat, '/', Name])
  ).


% -----------------------------------------------------------------------------
% Index persistence
% -----------------------------------------------------------------------------

%! semantic:save_index is det.
%
% Save all embedding/3 facts to disk.

semantic:save_index :-
  semantic:index_file(Path),
  setup_call_cleanup(
    open(Path, write, Out),
    forall(semantic:embedding(Cat, Name, Emb),
      format(Out, '~q.~n', [semantic:embedding(Cat, Name, Emb)])),
    close(Out)),
  message:inform(['Saved semantic index to ', Path]).


%! semantic:load_index is det.
%
% Load the embedding index from disk if not already loaded.

semantic:load_index :-
  semantic:index_loaded, !.

semantic:load_index :-
  semantic:index_file(Path),
  ( exists_file(Path)
  -> retractall(semantic:embedding(_, _, _)),
     setup_call_cleanup(
       open(Path, read, In),
       semantic:read_terms(In),
       close(In)),
     assertz(semantic:index_loaded),
     semantic:log_index_count
  ; message:log(['No semantic index found. Run --train-model to build it.'])
  ).


%! semantic:log_index_count is det.
%
% Log the number of loaded embeddings.

semantic:log_index_count :-
  aggregate_all(count, semantic:embedding(_, _, _), N),
  message:log(['Loaded semantic index: ', N, ' embeddings.']).


%! semantic:read_terms(+Stream) is det.
%
% Read and assert all terms from Stream.

semantic:read_terms(In) :-
  read_term(In, Term, []),
  ( Term == end_of_file
  -> true
  ; assert(Term),
    semantic:read_terms(In)
  ).


% -----------------------------------------------------------------------------
% Similarity search
% -----------------------------------------------------------------------------

%! semantic:search(+Query, +TopN, -Results) is det.
%
% Embed the query string and return the TopN most similar packages.
% Results is a list of Score-Category/Name pairs, sorted descending.

semantic:search(Query, TopN, Results) :-
  semantic:load_index,
  ( \+ semantic:index_loaded
  -> Results = [],
     message:warning(['No semantic index available. Run --train-model to build it.'])
  ; ( semantic:embed_text(Query, QueryEmb),
      semantic:normalize_vector(QueryEmb, QueryNorm)
    -> findall(Score-Cat/Name,
         ( semantic:embedding(Cat, Name, PkgNorm),
           semantic:dot_product(QueryNorm, PkgNorm, Score)
         ),
         AllScores),
       msort(AllScores, Sorted),
       reverse(Sorted, Descending),
       semantic:take(TopN, Descending, Results)
    ; Results = [],
      message:warning(['Could not generate embedding. Is Ollama running?'])
    )
  ).


%! semantic:take(+N, +List, -Prefix) is det.
%
% Take at most N elements from List.

semantic:take(0, _, []) :- !.

semantic:take(_, [], []) :- !.

semantic:take(N, [X|Xs], [X|Ys]) :-
  N1 is N - 1,
  semantic:take(N1, Xs, Ys).


%! semantic:dot_product(+A, +B, -Dot) is det.
%
% Accumulator-based dot product for tail recursion.

semantic:dot_product(A, B, Dot) :-
  semantic:dot_product_(A, B, 0.0, Dot).

semantic:dot_product_([], [], Acc, Acc).

semantic:dot_product_([X|Xs], [Y|Ys], Acc, Dot) :-
  Acc1 is Acc + X * Y,
  semantic:dot_product_(Xs, Ys, Acc1, Dot).


%! semantic:normalize_vector(+V, -Normalized) is det.
%
% L2-normalize a vector so cosine similarity reduces to dot product.

semantic:normalize_vector(V, Normalized) :-
  semantic:sum_squares_(V, 0.0, SumSq),
  Mag is sqrt(SumSq),
  ( Mag > 0.0
  -> semantic:divide_vector(V, Mag, Normalized)
  ; Normalized = V
  ).


%! semantic:divide_vector(+V, +Divisor, -Result) is det.

semantic:divide_vector([], _, []).

semantic:divide_vector([X|Xs], D, [Y|Ys]) :-
  Y is X / D,
  semantic:divide_vector(Xs, D, Ys).


%! semantic:sum_squares_(+V, +Acc, -Sum) is det.

semantic:sum_squares_([], Acc, Acc).

semantic:sum_squares_([X|Xs], Acc, Sum) :-
  Acc1 is Acc + X * X,
  semantic:sum_squares_(Xs, Acc1, Sum).


% -----------------------------------------------------------------------------
% Pretty printing
% -----------------------------------------------------------------------------

%! semantic:print_results(+Results) is det.
%
% Display semantic search results with similarity scores.

semantic:print_results([]) :-
  message:inform('No results found.').

semantic:print_results(Results) :-
  forall(member(Score-Cat/Name, Results),
    ( Pct is Score * 100,
      format('  ~1f%  ~w/~w~n', [Pct, Cat, Name]),
      ( cache:ordered_entry(_, Entry, Cat, Name, _),
        cache:entry_metadata(_, Entry, description, [Desc|_])
      -> format('         ~w~n', [Desc])
      ; true
      )
    )).
