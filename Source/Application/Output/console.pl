/*
 Author:   Pieter Van den Abeele
 E-mail:   pvdabeel@mac.com
 Copyright (c) 2005-2026, Pieter Van den Abeele

 Distributed under the terms of the LICENSE file in the root directory of this
 project.
*/


/** <module> CONSOLE
What the current output destination is.

A terminal or not, its size, which glyphs it can draw, and which
printing style applies. The settings themselves stay in config:
`config:default_printing_style/1` and the dynamic
`config:interface_printing_style/1`.
*/

:- module(console, []).

% =============================================================================
%  CONSOLE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Terminal destination
% -----------------------------------------------------------------------------

%! console:output_tty is semidet.
%
% Succeeds when the ultimate output destination is a real terminal.
% In daemon/IPC mode the daemon's user_output is a socket, but the
% client's stdout may be a terminal. daemon:client_is_tty is asserted
% when the client reports one.

:- dynamic console:output_tty_cached/1.

console:output_tty :-
  ( console:output_tty_cached(Val)
  -> Val == true
  ; ( ( stream_property(user_output, tty(true))
      ; catch(daemon:client_is_tty, _, fail)
      )
    -> asserta(console:output_tty_cached(true))
    ;  asserta(console:output_tty_cached(false)),
       fail
    )
  ).


%! console:terminal_env_term(-Term) is semidet.
%
% TERM from the client-forwarded environment (daemon/IPC) or the
% local process environment.

console:terminal_env_term(Term) :-
  ( catch(daemon:client_env('TERM', Term), _, fail)
  -> true
  ;  catch(system:getenv('TERM', Term), _, fail)
  ).


%! console:powerline_bubbles_env_ok is semidet.
%
% True when TERM is absent or is not the Linux console.

console:powerline_bubbles_env_ok :-
  ( catch(console:terminal_env_term(Term), _, fail)
  -> Term \== linux
  ;  true
  ).


%! console:powerline_bubbles is semidet.
%
% Succeeds when Powerline private-use bubble caps (U+E0B6/U+E0B4)
% are appropriate for the output terminal. Fails on the Linux console
% (TERM=linux), where angle-bracket bubbles are used instead.

:- dynamic console:powerline_bubbles_cached/1.

console:powerline_bubbles :-
  ( console:powerline_bubbles_cached(Val)
  -> Val == true
  ; ( console:powerline_bubbles_env_ok
    -> asserta(console:powerline_bubbles_cached(true))
    ;  asserta(console:powerline_bubbles_cached(false)),
       fail
    )
  ).



% -----------------------------------------------------------------------------
%  Printing style
% -----------------------------------------------------------------------------

%! console:printing_style(?Style)
%
% The printing style in force: 'short', 'column', or 'fancy'.
% A Pengines server uses the style shipped by the client. Otherwise
% the interface style wins, then config:default_printing_style/1.

console:printing_style(Style) :-
  pengine_self(M),
  !,
  M:printing_style(Style).

console:printing_style(Style) :-
  config:interface_printing_style(Style),!.

console:printing_style(Style) :-
  \+(config:interface_printing_style(_)),
  config:default_printing_style(Style).



% -----------------------------------------------------------------------------
%  Terminal size
% -----------------------------------------------------------------------------

%! console:printing_tty_size(?Rows, ?Cols)
%
% The terminal size to print against. A Pengines server uses the
% connected client's size. A daemon uses the size the IPC client
% forwarded. Otherwise the local terminal is used.

console:printing_tty_size(Rows, Cols) :-
  pengine_self(M),
  !,
  M:printing_tty_size(Rows, Cols).

console:printing_tty_size(Rows, Cols) :-
  catch(daemon:client_tty_size(Rows, Cols), _, fail),
  !.

console:printing_tty_size(Rows, Cols) :-
  console:local_tty_size(Rows, Cols).


%! console:local_tty_size(-Rows, -Cols) is det.
%
% The local process terminal size, or 80 rows by 160 columns when
% stdout is not a terminal (tty_size/2 may throw outside one).
%
% This does not ask a remote client, so the lightweight IPC client can
% duplicate it without loading library(pengines).

console:local_tty_size(Rows, Cols) :-
  ( catch(tty_size(Rows, Cols), _, fail) -> true ; Rows = 80, Cols = 160 ).
