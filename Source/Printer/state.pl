/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> STATE
Interactive prover state display.

Provides the debugger display hook (display_state/4) that renders the
current proving literal, proof stack, to-do queue, model, and constraints,
plus the wait_for_input/0 TTY pause helper.
*/

:- module(state, []).


% =============================================================================
%  STATE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Prover state display
% -----------------------------------------------------------------------------

%! state:display_state(+Target, +Proof, +Model, +Constraints)
%
% Interactive debugger display: prints the current prover state including
% the literal being proved, the proof stack, the to-do queue, the completed
% model, and the active constraints.

state:display_state([],_,_,_) :- !.
state:display_state(Target, Proof, Model, Constraints) :-

    ( Target = [ Current | Queue ]
      -> true
      ;  Current = Target, Queue = [] ),

    prover:proof_to_list(Proof,ProofList),
    prover:model_to_list(Model,ModelList),
    constraint:constraints_to_list(Constraints,ConstraintList),

    message:hl,

    % --- Current literal ---
    message:color(orange), message:style(bold),
    format('--- Proving ---~n'),
    message:color(normal), message:style(normal),
    format('  ~w~n~n', [Current]),

    % --- Proof stack (in progress) ---
    message:color(magenta), message:style(bold),
    format('--- Proving Stack (In Progress) ---~n'),
    message:color(normal), message:style(normal),
    ( ProofList == [] -> writeln('  (empty)') ;
      ( reverse(ProofList, Tmp),
        forall(member(rule(P,_), Tmp), format('  ~w~n', [P]))
      )
    ),
    nl,

    % --- To-do queue ---
    message:color(cyan), message:style(bold),
    format('--- Proving Queue (To Do) ---~n'),
    message:color(normal), message:style(normal),
    ( Queue == [] -> writeln('  (empty)') ; forall(member(Q, Queue), format('  ~w~n', [Q])) ),
    nl,

    % --- Model (completed) ---
    message:color(green), message:style(bold),
    format('--- Model (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ModelList  == [] -> writeln('  (empty)')
    ; forall(member(M, ModelList), ( format('  ~w~n', [M]) ))),
    nl,

    % --- Constraints (completed) ---
    message:color(green), message:style(bold),
    format('--- Constraints (Completed) ---~n'),
    message:color(normal), message:style(normal),

    ( ConstraintList  == [] -> writeln('  (empty)')
    ; forall(member(M, ConstraintList), ( format('  ~w~n', [M]) ))).


% -----------------------------------------------------------------------------
%  TTY helpers
% -----------------------------------------------------------------------------

%! state:wait_for_input
%
% Block until the user presses Enter. No-op when stdin is not a TTY
% (e.g. here-doc piping, CI).

state:wait_for_input :-
    ( stream_property(user_input, tty(true)),
      \+ at_end_of_stream(user_input) ->
        format('~nPress Enter to continue...'),
        flush_output,
        catch(get_char(_), _E, true)
    ; true
    ).
