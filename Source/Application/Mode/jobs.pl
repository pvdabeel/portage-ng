/*
 Author: Pieter Van den Abeele
 E-mail: pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/

/** <module> JOBS
Lease-bound state for distributed prove jobs.

Each submission receives a numeric id and an opaque token. Requeue keeps
the id and replaces the token. A result is published only when the token
still matches the in-flight lease; a repeat of an already published id is
a duplicate, not a second result.
*/

:- module(jobs, []).

% =============================================================================
% JOBS declarations
% =============================================================================

:- dynamic jobs:batch_no/1.
:- dynamic jobs:seq/1.
:- dynamic jobs:submitted/1.
:- dynamic jobs:inflight/6.
:- dynamic jobs:published/2.


% -----------------------------------------------------------------------------
% Batch and counters
% -----------------------------------------------------------------------------

%! jobs:current_batch(-Batch) is det.
%
% The batch that new submissions and dequeues belong to.

jobs:current_batch(Batch) :-
  jobs:batch_no(Batch0),
  !,
  Batch = Batch0.
jobs:current_batch(1).


%! jobs:reset is det.
%
% Start a new batch and drop leases, published ids and the submitted
% counter. Queued envelopes from the previous batch no longer match.

jobs:reset :-
  with_mutex(jobs_state,
    ( ( jobs:batch_no(Prev) -> Next is Prev + 1 ; Next = 1 ),
      retractall(jobs:batch_no(_)),
      assertz(jobs:batch_no(Next)),
      retractall(jobs:submitted(_)),
      retractall(jobs:inflight(_, _, _, _, _, _)),
      retractall(jobs:published(_, _))
    )).


%! jobs:submitted_count(-N) is det.

jobs:submitted_count(N) :-
  ( jobs:submitted(N0) -> N = N0 ; N = 0 ).


%! jobs:inflight_count(-N) is det.

jobs:inflight_count(N) :-
  aggregate_all(count, jobs:inflight(_, _, _, _, _, _), N).


% -----------------------------------------------------------------------------
% Submit, accept, finish
% -----------------------------------------------------------------------------

%! jobs:enqueue(+Target, -Envelope) is det.
%
% Allocate a fresh id and token in the current batch and count one
% expected result. Envelope is job(Id, Token, Batch, Target).

jobs:enqueue(Target, job(Id, Token, Batch, Target)) :-
  with_mutex(jobs_state,
    ( jobs:current_batch(Batch),
      jobs:allocate(Id, Token),
      jobs:bump_submitted
    )).


%! jobs:current_envelope(+Envelope) is semidet.
%
% An envelope may be dequeued. done is always current. A job envelope
% must belong to the current batch.

jobs:current_envelope(done) :- !.
jobs:current_envelope(job(_, _, Batch, _)) :-
  jobs:current_batch(Batch).


%! jobs:accept(+Envelope, +Worker, +Now, -Job) is det.
%
% Record the lease for a current job envelope. Job is the worker-facing
% term job(Id, Token, Target), or done.

jobs:accept(done, _Worker, _Now, done) :- !.
jobs:accept(job(Id, Token, Batch, Target), Worker, Now, job(Id, Token, Target)) :-
  with_mutex(jobs_state,
    assertz(jobs:inflight(Id, Token, Batch, Worker, Now, Target))).


%! jobs:complete(+Id, +Token, +Result, -Outcome) is det.
%
% Outcome is publish(Target, Result), duplicate, or reject. publish is
% returned once, when Token is the live lease. A later post for the same
% id is duplicate. A token that lost the lease is reject.

jobs:complete(Id, Token, Result, Outcome) :-
  with_mutex(jobs_state, jobs:complete_locked(Id, Token, Result, Outcome)).

jobs:complete_locked(Id, _Token, _Result, duplicate) :-
  jobs:published(Id, _),
  !.
jobs:complete_locked(Id, Token, Result, publish(Target, Result)) :-
  retract(jobs:inflight(Id, Token, _Batch, _Worker, _Since, Target)),
  !,
  assertz(jobs:published(Id, result(Target, Result))).
jobs:complete_locked(_Id, _Token, _Result, reject).


%! jobs:renew(+Id, +Token, +Now) is semidet.
%
% Refresh the lease timestamp when Token is still current.

jobs:renew(Id, Token, Now) :-
  with_mutex(jobs_state,
    ( retract(jobs:inflight(Id, Token, Batch, Worker, _Since, Target)),
      assertz(jobs:inflight(Id, Token, Batch, Worker, Now, Target))
    )).


%! jobs:requeue(+Id, +Token, -Envelope) is semidet.
%
% Replace Token with a new token and return the envelope to queue, when
% that token is still the in-flight lease. The id is unchanged, so the
% collector still expects one result.

jobs:requeue(Id, Token, job(Id, NewToken, Batch, Target)) :-
  with_mutex(jobs_state,
    ( retract(jobs:inflight(Id, Token, Batch, _Worker, _Since, Target)),
      jobs:allocate_token(NewToken)
    )).


%! jobs:held(?Id, ?Token, ?Worker, ?Since) is nondet.
%
% A lease that a liveness check may requeue.

jobs:held(Id, Token, Worker, Since) :-
  jobs:inflight(Id, Token, _, Worker, Since, _).


% -----------------------------------------------------------------------------
% Allocation
% -----------------------------------------------------------------------------

%! jobs:allocate(-Id, -Token) is det.
%
% Next id and a fresh token. Caller holds jobs_state.

jobs:allocate(Id, Token) :-
  ( retract(jobs:seq(Prev)) -> true ; Prev = 0 ),
  Id is Prev + 1,
  assertz(jobs:seq(Id)),
  jobs:allocate_token(Token).


%! jobs:allocate_token(-Token) is det.

jobs:allocate_token(Token) :-
  random_between(1, 2147483647, High),
  random_between(1, 2147483647, Low),
  Token is High * 2147483647 + Low.


%! jobs:bump_submitted is det.
%
% Caller holds jobs_state.

jobs:bump_submitted :-
  ( retract(jobs:submitted(Prev)) -> true ; Prev = 0 ),
  Next is Prev + 1,
  assertz(jobs:submitted(Next)).


% -----------------------------------------------------------------------------
% Collector accounting
% -----------------------------------------------------------------------------

%! jobs:note_result(+Id, +Seen, +Remaining, -SeenOut, -RemainingOut) is det.
%
% Record Id in the assoc Seen. A new id decrements Remaining. A repeat
% leaves both outputs equal to the inputs' updated assoc and the same
% remaining count.

jobs:note_result(Id, Seen, Remaining, Seen, Remaining) :-
  get_assoc(Id, Seen, _),
  !.
jobs:note_result(Id, Seen, Remaining, SeenOut, RemainingOut) :-
  put_assoc(Id, Seen, true, SeenOut),
  RemainingOut is Remaining - 1.
