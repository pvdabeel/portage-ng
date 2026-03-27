/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> LINKAGE
Detects broken shared library linkage in installed packages by scanning
ELF binaries (Linux: ldd) or Mach-O binaries (macOS: otool) for missing
shared library references. Produces a list of packages that need rebuilding.
*/

:- module(linkage, []).

% =============================================================================
%  LINKAGE declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Broken linkage detection
% -----------------------------------------------------------------------------

%! linkage:check(-Results) is det.
%
% Scans installed packages for broken shared library linkage.
% Results is a list of Entry-BrokenLibs pairs.

linkage:check(Results) :-
  findall(Entry-BrokenLibs,
    ( vdb:find_installed_pkg(portage://Entry),
      linkage:check_package(Entry, BrokenLibs),
      BrokenLibs \== []
    ),
    Results).


%! linkage:check_package(+Entry, -BrokenLibs) is det.
%
% Checks a single installed package for broken linkage.

linkage:check_package(Entry, BrokenLibs) :-
  vdb:read_contents(Entry, Contents),
  findall(Lib,
    ( member(obj(Path, _, _), Contents),
      linkage:is_linkable(Path),
      linkage:broken_libs(Path, Libs),
      member(Lib, Libs)
    ),
    BrokenLibs0),
  sort(BrokenLibs0, BrokenLibs).


%! linkage:is_linkable(+Path) is semidet.
%
% True when Path is a file type that may have shared library deps
% (ELF binaries, shared objects).

linkage:is_linkable(Path) :-
  atom_string(Path, PS),
  ( sub_string(PS, _, _, 0, ".so")
  ; sub_string(PS, _, _, _, ".so.")
  ; sub_string(PS, 0, _, _, "/usr/bin/")
  ; sub_string(PS, 0, _, _, "/usr/sbin/")
  ; sub_string(PS, 0, _, _, "/usr/lib")
  ; sub_string(PS, 0, _, _, "/bin/")
  ; sub_string(PS, 0, _, _, "/sbin/")
  ; sub_string(PS, 0, _, _, "/lib")
  ).


%! linkage:broken_libs(+Path, -Broken) is det.
%
% Returns shared libraries that Path links against but cannot be found.

linkage:broken_libs(Path, Broken) :-
  ( \+ exists_file(Path) ->
    Broken = []
  ; current_prolog_flag(apple, true) ->
    linkage:broken_libs_macos(Path, Broken)
  ; linkage:broken_libs_linux(Path, Broken)
  ).


%! linkage:broken_libs_linux(+Path, -Broken) is det.
%
% Uses ldd to detect broken linkage on Linux.

linkage:broken_libs_linux(Path, Broken) :-
  catch(
    ( process_create(path(ldd), [Path],
        [stdout(pipe(Out)), stderr(null), process(Pid)]),
      call_cleanup(
        ( read_string(Out, _, Output),
          split_string(Output, "\n", "\n", Lines),
          findall(Lib,
            ( member(Line, Lines),
              sub_string(Line, _, _, _, "not found"),
              split_string(Line, " \t", " \t", Parts),
              Parts = [LibS|_],
              atom_string(Lib, LibS)
            ),
            Broken)
        ),
        ( close(Out), process_wait(Pid, _) )
      )
    ),
    _,
    Broken = []
  ).


%! linkage:broken_libs_macos(+Path, -Broken) is det.
%
% Uses otool -L to detect broken linkage on macOS.

linkage:broken_libs_macos(Path, Broken) :-
  catch(
    ( process_create(path(otool), ['-L', Path],
        [stdout(pipe(Out)), stderr(null), process(Pid)]),
      call_cleanup(
        ( read_string(Out, _, Output),
          split_string(Output, "\n", "\n", Lines),
          findall(Lib,
            ( member(Line, Lines),
              split_string(Line, " \t", " \t", [LibS|_]),
              atom_string(Lib, LibS),
              Lib \== Path,
              \+ sub_atom(Lib, 0, _, _, '/System/'),
              \+ sub_atom(Lib, 0, _, _, '/usr/lib/'),
              \+ exists_file(Lib)
            ),
            Broken)
        ),
        ( close(Out), process_wait(Pid, _) )
      )
    ),
    _,
    Broken = []
  ).