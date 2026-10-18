/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> SANITIZE
Input validation for values that end up in file paths or in the arguments
of external processes.

The checks in this module reject path traversal only: a value passing
safe_path_component/1, safe_filename/1, safe_portage_category/1 or
safe_portage_name/1 may still contain shell metacharacters such as `;`,
`$(...)` or spaces. A sanitized value is therefore safe as an argument,
not as program text. Pass it to process_create/3 as an argv element, as
ebuild_exec:reactivate_toolchain/2 and kernelconfig:apply_options/1 do.
When a shell is unavoidable, keep the `-c` script a fixed string and hand
the value over as a positional parameter ($1, $2, ...); see
ebuild_exec:spawn_ebuild/6 and download:async_multi_url_curl/3. Building
the script text with format/3 or atomic_list_concat/2 from a sanitized
value is command injection.
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


%! sanitize:safe_distfile_name(+Name) is semidet.
%
% True when Name is a safe DIST filename (one leaf component). Unlike
% safe_filename/1, an embedded `..` is allowed because it is harmless inside
% a leaf (`foo..tar`); the dot components `.` and `..`, separators, controls,
% and NUL are rejected.

sanitize:safe_distfile_name(Name) :-
  atom(Name),
  Name \== '',
  Name \== '.',
  Name \== '..',
  atom_codes(Name, Codes),
  Codes \== [],
  forall(member(Code, Codes),
         ( Code > 31,
           Code =\= 127,
           Code =\= 0'/,
           Code =\= 0'\\,
           Code =\= 0
         )).


%! sanitize:safe_relative_path(+Path) is semidet.
%
% True when Path is a non-empty relative path made only of ordinary leaf
% components. Absolute paths, empty/dot components, backslashes, controls,
% and NUL are rejected.

sanitize:safe_relative_path(Path) :-
  atom(Path),
  Path \== '',
  \+ sub_atom(Path, 0, 1, _, '/'),
  \+ sub_atom(Path, _, _, _, '\\'),
  \+ sub_atom(Path, _, _, _, '\x00\'),
  atomic_list_concat(Components, '/', Path),
  Components \== [],
  forall(member(Component, Components),
         sanitize:safe_relative_component(Component)).


%! sanitize:safe_relative_component(+Component) is semidet.
%
% Validate one component of a relative path.

sanitize:safe_relative_component(Component) :-
  Component \== '',
  Component \== '.',
  Component \== '..',
  atom_codes(Component, Codes),
  forall(member(Code, Codes), (Code > 31, Code =\= 127)).


%! sanitize:contained_regular_file(+Root, +Relative, -Canonical) is semidet.
%
% Resolve Relative below Root and return its canonical path. Every relative
% component and the final file must be a non-symlink, and canonical resolution
% must remain below Root. Root itself may be a trusted configured symlink.

sanitize:contained_regular_file(Root, Relative, Canonical) :-
  sanitize:safe_relative_path(Relative),
  absolute_file_name(Root, CanonicalRoot,
                     [file_type(directory), access(read), file_errors(fail)]),
  atomic_list_concat(Components, '/', Relative),
  sanitize:no_symlink_components(CanonicalRoot, Components),
  os:compose_path(CanonicalRoot, Relative, Candidate),
  sanitize:not_symlink(Candidate),
  absolute_file_name(Candidate, Canonical,
                     [file_type(regular), access(read), file_errors(fail)]),
  sanitize:path_below(CanonicalRoot, Canonical).


%! sanitize:no_symlink_components(+Root, +Components) is semidet.
%
% Fail when any path component below Root is a symbolic link.

sanitize:no_symlink_components(_, []).
sanitize:no_symlink_components(Root, [Component|Rest]) :-
  os:compose_path(Root, Component, Path),
  sanitize:not_symlink(Path),
  sanitize:no_symlink_components(Path, Rest).


%! sanitize:path_below(+Root, +Path) is semidet.
%
% True when canonical Path is strictly below canonical Root.

sanitize:path_below(Root, Path) :-
  ( sub_atom(Root, _, 1, 0, '/')
  -> Prefix = Root
  ;  atom_concat(Root, '/', Prefix)
  ),
  atom_concat(Prefix, _, Path).


%! sanitize:safe_portage_category(+Cat) is semidet.
%
% True when Cat is safe to use as a single path component (no slashes,
% no '..', no NUL bytes, non-empty). This is NOT a full PMS category
% name check: shell metacharacters (e.g. '-rf', '$(cmd)', ';reboot')
% pass. Callers must pass Cat as a process_create/3 argument-vector
% element, never interpolate it into a shell command string.

sanitize:safe_portage_category(Cat) :-
  sanitize:safe_path_component(Cat).


%! sanitize:safe_portage_name(+Name) is semidet.
%
% True when Name is safe to use as a single path component (no slashes,
% no '..', no NUL bytes, non-empty). This is NOT a full PMS package
% name check: shell metacharacters (e.g. '-rf', '$(cmd)', ';reboot')
% pass. Callers must pass Name as a process_create/3 argument-vector
% element, never interpolate it into a shell command string.

sanitize:safe_portage_name(Name) :-
  sanitize:safe_path_component(Name).


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


%! sanitize:safe_git_commit(+Commit) is semidet.
%
% True when Commit is a full Git object name: 40 (SHA-1) or 64 (SHA-256)
% lowercase/uppercase hexadecimal characters. Rejects short SHAs, branch
% names, and anything with path/shell metacharacters.

sanitize:safe_git_commit(Commit) :-
  atom(Commit),
  atom_string(Commit, S),
  string_length(S, Len),
  memberchk(Len, [40, 64]),
  string_lower(S, Lower),
  re_match('^[0-9a-f]+$', Lower),
  !.


% -----------------------------------------------------------------------------
%  File integrity (SHA-256 sidecars)
% -----------------------------------------------------------------------------

%! sanitize:sha256_sidecar(+Path, -SidePath) is det.
%
% Path of the SHA-256 sidecar written next to Path (`Path.sha256`).

sanitize:sha256_sidecar(Path, SidePath) :-
  atom_concat(Path, '.sha256', SidePath).


%! sanitize:file_sha256(+Path, -Hash) is semidet.
%
% Unify Hash with the lowercase hex SHA-256 of Path's contents.

sanitize:file_sha256(Path, Hash) :-
  process_create(path(openssl), ['dgst', '-sha256', Path],
                 [stdout(pipe(Out)), stderr(null), process(Pid)]),
  call_cleanup(
    read_string(Out, _, Raw),
    ( close(Out), process_wait(Pid, Status) )
  ),
  Status == exit(0),
  split_string(Raw, "=", " \t\n\r", Parts),
  last(Parts, HashStr),
  HashStr \== "",
  string_lower(HashStr, Lower),
  atom_string(Hash, Lower),
  atom_length(Hash, 64).


%! sanitize:write_sha256_sidecar(+Path) is det.
%
% Write Path.sha256 containing the SHA-256 of Path. Best-effort: failures
% are swallowed so a digest write never aborts the caller.

sanitize:write_sha256_sidecar(Path) :-
  catch(
    ( sanitize:file_sha256(Path, Hash),
      sanitize:sha256_sidecar(Path, Side),
      setup_call_cleanup(
        open(Side, write, S),
        format(S, '~w~n', [Hash]),
        close(S))
    ),
    _, true).


%! sanitize:verify_sha256_sidecar(+Path) is semidet.
%
% Succeeds when Path.sha256 exists and matches the current SHA-256 of Path.

sanitize:verify_sha256_sidecar(Path) :-
  sanitize:sha256_sidecar(Path, Side),
  exists_file(Side),
  sanitize:file_sha256(Path, Got),
  setup_call_cleanup(
    open(Side, read, S),
    read_string(S, _, Raw),
    close(S)),
  split_string(Raw, "\n", " \t\n\r", [ExpectedStr|_]),
  atom_string(Expected, ExpectedStr),
  Got == Expected.


%! sanitize:effective_file_integrity(-Mode) is det.
%
% Resolve the integrity policy in force. A per-mode override
% (config:file_integrity_mode/2 — `require` for the long-lived server
% and daemon modes, whose Knowledge/*.qlf files are loaded code) wins
% over the global config:file_integrity/1. The fallback default is
% prefer.

sanitize:effective_file_integrity(Mode) :-
  ( sanitize:current_run_mode(RunMode),
    current_predicate(config:file_integrity_mode/2),
    config:file_integrity_mode(RunMode, Mode)
  -> true
  ; ( current_predicate(config:file_integrity/1),
      config:file_integrity(Mode)
    -> true
    ;  Mode = prefer
    )
  ).


%! sanitize:current_run_mode(-Mode) is semidet.
%
% The operating mode of this run, when the interface module is loaded
% and has parsed one from the command line.

sanitize:current_run_mode(Mode) :-
  current_predicate(interface:get_mode/1),
  catch(interface:get_mode(Mode), _, fail),
  !.


%! sanitize:ensure_file_integrity(+Path) is semidet.
%
% Enforce the effective integrity policy (see
% sanitize:effective_file_integrity/1) against Path:
%   * require — sidecar must verify (fail otherwise)
%   * prefer  — verify when sidecar exists; warn and succeed when missing
%   * off     — always succeed
% Default is prefer, overridden to require in server/daemon modes.

sanitize:ensure_file_integrity(Path) :-
  sanitize:effective_file_integrity(Mode),
  sanitize:ensure_file_integrity(Path, Mode).

sanitize:ensure_file_integrity(_Path, off) :- !.
sanitize:ensure_file_integrity(Path, require) :-
  !,
  ( sanitize:verify_sha256_sidecar(Path)
  -> true
  ;  message:failure(['Integrity check failed for ', Path,
                      ' (missing or mismatched .sha256 sidecar). ',
                      'Regenerate the file with a current portage-ng save/write path.']),
     !, fail
  ).
sanitize:ensure_file_integrity(Path, prefer) :-
  sanitize:sha256_sidecar(Path, Side),
  ( exists_file(Side)
  -> ( sanitize:verify_sha256_sidecar(Path)
     -> true
     ;  message:failure(['Integrity check failed for ', Path,
                         ' (.sha256 mismatch). Refusing to load.']),
        !, fail
     )
  ;  message:warning(['No integrity sidecar for ', Path,
                      '; loading without verification. ',
                      'Re-save to create ', Side, '.']),
     true
  ).


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
  \+ exists_directory(Path),
  sanitize:not_symlink(Path).


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
%  Portage config tokens (package.* lines)
% -----------------------------------------------------------------------------

%! sanitize:safe_use_flag(+Flag) is semidet.
%
% True when Flag is a single USE flag token for a package.use line:
% starts alphanumeric or underscore, then alphanumerics plus
% `_ + @ . -`. Whitespace, `#`, quotes and newlines never pass, so a
% validated flag cannot break out of its config line.

sanitize:safe_use_flag(Flag) :-
  atom(Flag),
  atom_string(Flag, S),
  re_match("^[A-Za-z0-9_][A-Za-z0-9_+@.\\-]*$", S).


%! sanitize:safe_keyword(+Keyword) is semidet.
%
% True when Keyword is a single package.accept_keywords token: an
% arch keyword (`amd64`, `~amd64`, `-amd64`), or a wildcard (`*`,
% `**`, `-*`, `~*`).

sanitize:safe_keyword(Keyword) :-
  atom(Keyword),
  atom_string(Keyword, S),
  re_match("^(~|-)?[a-z][a-z0-9_\\-]*$|^(~|-)?\\*\\*?$", S).


%! sanitize:safe_atom_token(+Atom) is semidet.
%
% True when Atom is an exact-version package atom token of the form
% `=category/name-version` with no whitespace or line breaks (the
% shape builder:atom_for_entry/3 persists to package.* files).

sanitize:safe_atom_token(Atom) :-
  atom(Atom),
  atom_string(Atom, S),
  re_match("^=[A-Za-z0-9._\\-]+/[A-Za-z0-9_+@.\\-]+$", S).


%! sanitize:safe_config_line(+Line) is semidet.
%
% True when Line is a single config line: non-empty, at most 8192
% characters, and free of newline, carriage-return and NUL bytes. A
% validated line appended to a package.* file cannot inject further
% lines into that file.

sanitize:safe_config_line(Line) :-
  ( atom(Line)
  -> atom_string(Line, S)
  ;  string(Line)
  -> S = Line
  ;  fail
  ),
  string_length(S, Len), Len > 0, Len =< 8192,
  \+ sub_string(S, _, _, _, "\n"),
  \+ sub_string(S, _, _, _, "\r"),
  \+ sub_string(S, _, _, _, "\x00\").


% -----------------------------------------------------------------------------
%  Symlink safety check
% -----------------------------------------------------------------------------

%! sanitize:not_symlink(+Path) is semidet.
%
% True when Path exists but is not a symbolic link.

sanitize:not_symlink(Path) :-
  catch(
    ( read_link(Path, _, _) -> fail ; true ),
    _, fail
  ).