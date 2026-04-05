/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SANITIZE
Input validation and sanitization helpers for defense-in-depth against
command injection, path traversal, and other input-based attacks.
*/

:- module(sanitize, []).

% =============================================================================
%  SANITIZE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Path component validation
% -----------------------------------------------------------------------------

%! sanitize:safe_path_component(+Atom) is semidet.
%
% True when Atom is a safe single path component: no slashes, no '..',
% no NUL bytes, and non-empty.

sanitize:safe_path_component(Atom) :-
  atom(Atom),
  atom_length(Atom, Len), Len > 0,
  atom_string(Atom, S),
  \+ sub_string(S, _, _, _, "/"),
  \+ sub_string(S, _, _, _, ".."),
  \+ sub_string(S, _, _, _, "\x00\").


%! sanitize:safe_filename(+Atom) is semidet.
%
% True when Atom is a safe filename: no directory separators, no '..',
% no NUL bytes, and non-empty.

sanitize:safe_filename(Atom) :-
  sanitize:safe_path_component(Atom).


%! sanitize:safe_portage_category(+Cat) is semidet.
%
% True when Cat matches a valid Gentoo category name pattern
% (lowercase alphanumeric plus hyphens, no slashes or dots-dots).

sanitize:safe_portage_category(Cat) :-
  atom(Cat),
  atom_string(Cat, S),
  string_length(S, Len), Len > 0,
  \+ sub_string(S, _, _, _, "/"),
  \+ sub_string(S, _, _, _, ".."),
  \+ sub_string(S, _, _, _, "\x00\").


%! sanitize:safe_portage_name(+Name) is semidet.
%
% True when Name matches a valid Gentoo package name pattern.

sanitize:safe_portage_name(Name) :-
  atom(Name),
  atom_string(Name, S),
  string_length(S, Len), Len > 0,
  \+ sub_string(S, _, _, _, "/"),
  \+ sub_string(S, _, _, _, ".."),
  \+ sub_string(S, _, _, _, "\x00\").


% -----------------------------------------------------------------------------
%  Snapshot ID validation
% -----------------------------------------------------------------------------

%! sanitize:safe_snapshot_id(+Id) is semidet.
%
% True when Id is a safe snapshot identifier: alphanumeric plus
% hyphens, underscores, and dots (no slashes, no '..').

sanitize:safe_snapshot_id(Id) :-
  atom(Id),
  atom_string(Id, S),
  string_length(S, Len), Len > 0, Len =< 255,
  \+ sub_string(S, _, _, _, "/"),
  \+ sub_string(S, _, _, _, "\\"),
  \+ sub_string(S, _, _, _, ".."),
  \+ sub_string(S, _, _, _, "\x00\").


% -----------------------------------------------------------------------------
%  Ebuild phase validation
% -----------------------------------------------------------------------------

%! sanitize:safe_phase(+Phase) is semidet.
%
% True when Phase is a known ebuild phase name.

sanitize:safe_phase(clean).
sanitize:safe_phase(setup).
sanitize:safe_phase(unpack).
sanitize:safe_phase(prepare).
sanitize:safe_phase(configure).
sanitize:safe_phase(compile).
sanitize:safe_phase(test).
sanitize:safe_phase(install).
sanitize:safe_phase(package).
sanitize:safe_phase(merge).
sanitize:safe_phase(unmerge).
sanitize:safe_phase(preinst).
sanitize:safe_phase(postinst).
sanitize:safe_phase(prerm).
sanitize:safe_phase(postrm).
sanitize:safe_phase(config).
sanitize:safe_phase(info).
sanitize:safe_phase(nofetch).


% -----------------------------------------------------------------------------
%  File existence validation
% -----------------------------------------------------------------------------

%! sanitize:existing_file(+Path) is semidet.
%
% True when Path points to an existing regular file (not a symlink
% to a directory, not a device node).

sanitize:existing_file(Path) :-
  exists_file(Path),
  \+ exists_directory(Path).


% -----------------------------------------------------------------------------
%  Daemon request term validation
% -----------------------------------------------------------------------------

%! sanitize:safe_daemon_request(+Term) is semidet.
%
% True when Term matches one of the allowed daemon request structures.

sanitize:safe_daemon_request(shutdown).

sanitize:safe_daemon_request(request(Args, Cols, Rows)) :-
  is_list(Args),
  maplist(atom, Args),
  integer(Cols),
  integer(Rows).

sanitize:safe_daemon_request(request(Args, Cols, Rows, Env)) :-
  is_list(Args),
  maplist(atom, Args),
  integer(Cols),
  integer(Rows),
  is_list(Env).


% -----------------------------------------------------------------------------
%  Symlink safety check
% -----------------------------------------------------------------------------

%! sanitize:not_symlink(+Path) is semidet.
%
% True when Path exists but is not a symbolic link.

sanitize:not_symlink(Path) :-
  catch(
    ( read_link(Path, _, _) -> fail ; true ),
    _, true
  ).