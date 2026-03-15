/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> BUILDTIME
Build time estimation for packages using historical data and heuristics.

Reads actual build durations from emerge.log (when available) and installed
package sizes from the VDB. Provides per-package time estimates and total
plan duration estimates that account for parallel wave scheduling.
*/

:- module(buildtime, []).

% =============================================================================
%  BUILDTIME declarations
% =============================================================================

:- dynamic buildtime:duration/4.
:- dynamic buildtime:pkg_size/3.
:- dynamic buildtime:loaded/0.


% -----------------------------------------------------------------------------
% Configuration (delegates to config module)
% -----------------------------------------------------------------------------

%! buildtime:emerge_log_path(-Path) is semidet.
%
% Path to emerge.log. Fails if not configured or file does not exist.

buildtime:emerge_log_path(Path) :-
  config:emerge_log_path(Path),
  exists_file(Path).


% -----------------------------------------------------------------------------
% Data loading
% -----------------------------------------------------------------------------

%! buildtime:load is det.
%
% Load build time data from emerge.log (if available) and package sizes
% from the VDB. Skips if already loaded.

buildtime:load :-
  buildtime:loaded, !.

buildtime:load :-
  buildtime:load_vdb_sizes,
  ( buildtime:emerge_log_path(Path)
  -> buildtime:load_emerge_log(Path)
  ; true
  ),
  assertz(buildtime:loaded),
  aggregate_all(count, buildtime:duration(_, _, _, _), Nd),
  aggregate_all(count, buildtime:pkg_size(_, _, _), Ns),
  message:log(['Build time data: ', Nd, ' durations, ', Ns, ' sizes.']).


%! buildtime:load_vdb_sizes is det.
%
% Read SIZE files from VDB directories for all installed packages.

buildtime:load_vdb_sizes :-
  retractall(buildtime:pkg_size(_, _, _)),
  config:hostname(Hostname),
  config:pkg_directory(Hostname, VdbDir),
  forall(
    ( cache:entry_metadata(portage, Entry, installed, true),
      buildtime:read_vdb_file(VdbDir, Entry, 'SIZE', SizeAtom),
      atom_number(SizeAtom, Size)
    ),
    ( atomic_list_concat([Cat, _PV], '/', Entry),
      cache:ordered_entry(portage, Entry, Cat, Name, _)
    -> assertz(buildtime:pkg_size(Cat, Name, Size))
    ; true
    )
  ).


%! buildtime:read_vdb_file(+VdbDir, +Entry, +FileName, -Content) is semidet.
%
% Read a single-line file from the VDB entry directory.

buildtime:read_vdb_file(VdbDir, Entry, FileName, Content) :-
  atomic_list_concat([VdbDir, '/', Entry, '/', FileName], Path),
  exists_file(Path),
  setup_call_cleanup(
    open(Path, read, In),
    ( read_line_to_string(In, Line),
      atom_string(Content, Line)
    ),
    close(In)
  ).


%! buildtime:load_emerge_log(+Path) is det.
%
% Parse emerge.log for per-package build durations.
% Extracts start/end timestamps from lines like:
%   1234567890:  >>> emerge (1 of 10) cat/pkg-ver to /
%   1234567891:  ::: completed emerge (1 of 10) cat/pkg-ver to /

buildtime:load_emerge_log(Path) :-
  retractall(buildtime:duration(_, _, _, _)),
  setup_call_cleanup(
    open(Path, read, In),
    buildtime:parse_emerge_lines(In),
    close(In)
  ).


%! buildtime:parse_emerge_lines(+Stream) is det.
%
% Read emerge.log lines and extract build durations.

buildtime:parse_emerge_lines(In) :-
  read_line_to_string(In, Line),
  ( Line == end_of_file
  -> true
  ; ( buildtime:parse_emerge_start(Line, Epoch, CPV)
    -> assert(buildtime:start_marker(CPV, Epoch))
    ; buildtime:parse_emerge_end(Line, Epoch, CPV)
    -> ( retract(buildtime:start_marker(CPV, Start))
       -> Duration is Epoch - Start,
          Duration > 0,
          buildtime:cpv_to_cn(CPV, Cat, Name, Version),
          ( buildtime:duration(Cat, Name, Version, _)
          -> true
          ; assertz(buildtime:duration(Cat, Name, Version, Duration))
          )
       ; true
       )
    ; true
    ),
    buildtime:parse_emerge_lines(In)
  ).

:- dynamic buildtime:start_marker/2.


%! buildtime:parse_emerge_start(+Line, -Epoch, -CPV) is semidet.
%
% Match "EPOCH:  >>> emerge (N of M) cat/pkg-ver to /"

buildtime:parse_emerge_start(Line, Epoch, CPV) :-
  split_string(Line, ":", "", [EpochStr|Rest]),
  number_string(Epoch, EpochStr),
  atomics_to_text(Rest, Joined),
  sub_string(Joined, _, _, _, ">>> emerge"),
  split_string(Joined, " ", " ", Tokens),
  buildtime:extract_cpv_from_emerge(Tokens, CPV).


%! buildtime:parse_emerge_end(+Line, -Epoch, -CPV) is semidet.
%
% Match "EPOCH:  ::: completed emerge (N of M) cat/pkg-ver to /"

buildtime:parse_emerge_end(Line, Epoch, CPV) :-
  split_string(Line, ":", "", [EpochStr|Rest]),
  number_string(Epoch, EpochStr),
  atomics_to_text(Rest, Joined),
  sub_string(Joined, _, _, _, "::: completed emerge"),
  split_string(Joined, " ", " ", Tokens),
  buildtime:extract_cpv_from_emerge(Tokens, CPV).


%! buildtime:extract_cpv_from_emerge(+Tokens, -CPV) is semidet.
%
% From token list [..., "(N", "of", "M)", "cat/pkg-ver", ...], extract CPV.

buildtime:extract_cpv_from_emerge(Tokens, CPV) :-
  append(_, ["of", _MStr | [CPVStr | _]], Tokens),
  sub_string(CPVStr, _, _, _, "/"),
  atom_string(CPV, CPVStr).


%! buildtime:cpv_to_cn(+CPV, -Cat, -Name, -Version) is semidet.
%
% Split a category/package-version atom into components.

buildtime:cpv_to_cn(CPV, Cat, Name, Version) :-
  atomic_list_concat([Cat, PV], '/', CPV),
  ( eapi:packageversion(PV, Name, Version)
  -> true
  ; Name = PV, Version = ''
  ).


% -----------------------------------------------------------------------------
% Build time estimation
% -----------------------------------------------------------------------------

%! buildtime:estimate(+Cat, +Name, -Seconds) is det.
%
% Estimate the build time in seconds for a package.
% Preference order:
%   1. Actual duration from emerge.log (most recent version)
%   2. SIZE-based heuristic from VDB
%   3. Default estimate based on category

buildtime:estimate(Cat, Name, Seconds) :-
  ( buildtime:duration(Cat, Name, _, Seconds)
  -> true
  ; buildtime:pkg_size(Cat, Name, Size)
  -> buildtime:size_to_seconds(Size, Seconds)
  ; buildtime:default_estimate(Cat, Seconds)
  ).


%! buildtime:size_to_seconds(+SizeBytes, -Seconds) is det.
%
% Estimate build time from installed package size.
% Empirical heuristic: ~1 second per 50KB of installed files,
% with a 5-second minimum for setup overhead.

buildtime:size_to_seconds(Size, Seconds) :-
  Raw is max(5, Size / 50000),
  Seconds is round(Raw).


%! buildtime:default_estimate(+Cat, -Seconds) is det.
%
% Fallback estimate when no size or historical data is available.

buildtime:default_estimate(Cat, Seconds) :-
  ( buildtime:heavy_category(Cat)
  -> Seconds = 300
  ; Seconds = 30
  ).


%! buildtime:heavy_category(+Cat) is semidet.
%
% Categories known to contain large, slow-building packages.

buildtime:heavy_category('dev-qt').
buildtime:heavy_category('dev-libs').
buildtime:heavy_category('sys-devel').
buildtime:heavy_category('sys-libs').
buildtime:heavy_category('www-client').
buildtime:heavy_category('app-office').
buildtime:heavy_category('dev-lang').
buildtime:heavy_category('kde-frameworks').
buildtime:heavy_category('kde-plasma').
buildtime:heavy_category('media-libs').
buildtime:heavy_category('net-libs').
buildtime:heavy_category('x11-libs').


% -----------------------------------------------------------------------------
% Plan estimation
% -----------------------------------------------------------------------------

%! buildtime:estimate_plan(+Actions, -WallSeconds, -CpuSeconds) is det.
%
% Estimate total build time for a list of Cat/Name actions.
% WallSeconds accounts for parallel waves (max per wave).
% CpuSeconds is the naive serial sum.

buildtime:estimate_plan(Actions, WallSeconds, CpuSeconds) :-
  buildtime:load,
  findall(S, ( member(Cat/Name, Actions),
               buildtime:estimate(Cat, Name, S) ),
          Times),
  sumlist(Times, CpuSeconds),
  WallSeconds = CpuSeconds.


%! buildtime:estimate_plan_waves(+Waves, -WallSeconds, -CpuSeconds) is det.
%
% Estimate build time for a wave-structured plan.
% Each wave is a list of Cat/Name pairs that execute in parallel;
% wall time per wave is the maximum, and total wall time is the sum
% of wave maxima.

buildtime:estimate_plan_waves(Waves, WallSeconds, CpuSeconds) :-
  buildtime:load,
  buildtime:estimate_waves_(Waves, 0, WallSeconds, 0, CpuSeconds).

buildtime:estimate_waves_([], Wall, Wall, Cpu, Cpu).

buildtime:estimate_waves_([Wave|Rest], WallAcc, WallTotal, CpuAcc, CpuTotal) :-
  findall(S, ( member(Cat/Name, Wave),
               buildtime:estimate(Cat, Name, S) ),
          Times),
  ( Times == []
  -> WaveMax = 0, WaveSum = 0
  ; max_list(Times, WaveMax),
    sumlist(Times, WaveSum)
  ),
  WallAcc1 is WallAcc + WaveMax,
  CpuAcc1 is CpuAcc + WaveSum,
  buildtime:estimate_waves_(Rest, WallAcc1, WallTotal, CpuAcc1, CpuTotal).


% -----------------------------------------------------------------------------
% Pretty printing
% -----------------------------------------------------------------------------

%! buildtime:format_duration(+Seconds, -Formatted) is det.
%
% Format seconds into human-readable duration (e.g. "2m 30s", "1h 15m").

buildtime:format_duration(Seconds, Formatted) :-
  S is round(Seconds),
  ( S >= 3600
  -> Hours is S // 3600,
     Rem is S mod 3600,
     Mins is Rem // 60,
     format(atom(Formatted), '~wh ~wm', [Hours, Mins])
  ; S >= 60
  -> Mins is S // 60,
     Secs is S mod 60,
     format(atom(Formatted), '~wm ~ws', [Mins, Secs])
  ; format(atom(Formatted), '~ws', [S])
  ).


%! buildtime:print_estimate(+Cat, +Name) is det.
%
% Print the estimated build time for a single package.

buildtime:print_estimate(Cat, Name) :-
  buildtime:load,
  buildtime:estimate(Cat, Name, Seconds),
  buildtime:format_duration(Seconds, Fmt),
  format('  ~w/~w: ~w~n', [Cat, Name, Fmt]).


%! buildtime:print_plan_estimate(+Actions) is det.
%
% Print the estimated total build time for a list of actions.

buildtime:print_plan_estimate(Actions) :-
  buildtime:estimate_plan(Actions, WallSec, CpuSec),
  buildtime:format_duration(WallSec, WallFmt),
  buildtime:format_duration(CpuSec, CpuFmt),
  length(Actions, N),
  ( WallSec =:= CpuSec
  -> format('% Estimated build time: ~w (~w packages)~n', [CpuFmt, N])
  ; format('% Estimated build time: ~w wall, ~w CPU (~w packages)~n',
           [WallFmt, CpuFmt, N])
  ).