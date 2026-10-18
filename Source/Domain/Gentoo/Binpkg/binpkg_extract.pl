/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BINPKG_EXTRACT
Low-level extraction helpers for Portage gpkg binary packages.

A gpkg is a tar archive containing a single inner directory named after
the package's PF + BUILD_ID (e.g. `jq-1.8.1-9/`). That inner directory
holds three artefacts:

  - `image.tar.zst`    — zstd-compressed tar of `image/` (the files that
                         will be merged to the live filesystem at `$ROOT`)
  - `metadata.tar.zst` — zstd-compressed tar of `metadata/` (per-binpkg
                         build metadata: USE, IUSE, SLOT, RDEPEND,
                         BUILD_ID, environment.bz2, etc.)
  - `Manifest`         — checksums + sizes of the above

This module reproduces, in Prolog, the file-system preparation that
emerge's `_emerge/Binpkg.py` performs before a binary merge. The output
layout (under `$PORTAGE_BUILDDIR`) matches what `ebuild qmerge` and
`portage/dbapi/vartree.py:merge()` expect:

  $PORTAGE_BUILDDIR/
    image/                   <- contents of image.tar.zst (live FS payload)
    build-info/              <- contents of metadata.tar.zst (NOTE: rename
                                from `metadata/` to `build-info/`; merge()
                                reads the VDB metadata from build-info/)
    temp/
      environment            <- decompressed from build-info/environment.bz2
    .installed               <- mandatory marker, qmerge bails without it

After `prepare_builddir/6` succeeds, callers (i.e. `binpkg_exec`) can
spawn `ebuild --skip-manifest <SOURCE_EBUILD> qmerge` with environment
`MERGE_TYPE=binary`, `PORTAGE_BINPKG_FILE=<gpkg>`, `PORTAGE_BUILDDIR=...`.

Every tar (outer gpkg, `image.tar.zst`, `metadata.tar.zst`) is listed and
checked before extraction. Absolute paths, `..` components, device/fifo
nodes, hardlinks that escape, and writes through a symlink whose target
leaves the destination (Gentoo bug 982208) are refused. Metadata members
must be regular files or directories.

This whole flow was validated end-to-end against `app-misc/jq-1.8.1`
BUILD_IDs 8 (oniguruma=on) and 10 (oniguruma=off) during initial bring-up.
*/

:- module(binpkg_extract, []).

:- use_module(library(uuid), [uuid/1]).

% =============================================================================
%  BINPKG_EXTRACT declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Top-level orchestrator
% -----------------------------------------------------------------------------

%! binpkg_extract:prepare_builddir(+GpkgPath, +InnerName, +BuildDir, +ExpectedSize, +Hashes, -StagedGpkg) is semidet.
%
% Idempotent end-to-end build directory preparation:
%
%   1. Wipe and recreate `BuildDir` with the canonical sub-tree
%      (`image/`, `build-info/`, `temp/`, `work/`).
%   2. Extract the outer tar to a private scratch dir (cleaned up at end).
%   3. Extract `image.tar.zst`     -> `BuildDir/image/`.
%   4. Extract `metadata.tar.zst`  -> `BuildDir/build-info/`
%      (with `--transform 's,^metadata/,build-info/,'`).
%   5. Decompress `environment.bz2` -> `BuildDir/temp/environment`.
%   5b. Rewrite `temp/environment` for binary merge (`MERGE_TYPE`,
%       `EMERGE_FROM`) and refresh `build-info/environment.bz2`.
%   5c. Copy `image/etc/env.d/*` into `temp/` when absent (ebuilds such as
%       `app-backup/amanda` expect `${T}/97amanda` during postinst).
%   6. Backfill `CATEGORY` / `PF` in `build-info/` if the gpkg omitted them.
%   7. Touch `BuildDir/.installed` (qmerge precondition).
%
% Fails (with a logged error message) if any step fails. The scratch
% directory is always cleaned up. Caller is responsible for assembling the
% `ebuild qmerge` invocation that consumes the prepared directory.

binpkg_extract:prepare_builddir(GpkgPath, InnerName, BuildDir,
                                ExpectedSize, Hashes, StagedGpkg) :-
  binpkg_extract:wipe_and_create_builddir(BuildDir),
  ( binpkg_extract:stage_verified_gpkg(GpkgPath, BuildDir,
                                       ExpectedSize, Hashes, StagedGpkg)
  -> setup_call_cleanup(
       binpkg_extract:make_scratch_dir(BuildDir, ScratchDir),
       binpkg_extract:populate_builddir(StagedGpkg, InnerName,
                                        BuildDir, ScratchDir),
       binpkg_extract:remove_scratch_dir(ScratchDir))
  ;  catch(delete_file(StagedGpkg), _, true),
     fail
  ).


%! binpkg_extract:populate_builddir(+GpkgPath, +InnerName, +BuildDir, +ScratchDir) is semidet.
%
% Steps 2-7 of `prepare_builddir/3`. Split out so the scratch dir is
% guaranteed cleaned up even if any sub-step fails.

binpkg_extract:populate_builddir(GpkgPath, InnerName, BuildDir, ScratchDir) :-
  binpkg_extract:extract_outer(GpkgPath, ScratchDir),
  os:compose_path([ScratchDir, InnerName], InnerDir),
  ( exists_directory(InnerDir)
  -> true
  ;  format(user_error, 'binpkg_extract: expected inner dir ~w not found in gpkg ~w~n', [InnerDir, GpkgPath]),
     fail
  ),
  binpkg_extract:verify_gpkg_manifest(InnerDir),
  os:compose_path([InnerDir, 'image.tar.zst'],    ImageTar),
  os:compose_path([InnerDir, 'metadata.tar.zst'], MetaTar),
  binpkg_extract:extract_image(ImageTar, BuildDir),
  binpkg_extract:extract_metadata_to_build_info(MetaTar, BuildDir),
  os:compose_path([BuildDir, 'build-info'], BuildInfoDir),
  os:compose_path([BuildDir, 'temp', 'environment'], EnvFile),
  binpkg_extract:decompress_environment_if_present(BuildInfoDir, EnvFile),
  binpkg_extract:patch_binary_merge_environment(EnvFile, BuildInfoDir),
  binpkg_extract:backfill_temp_envd_from_image(BuildDir),
  binpkg_extract:backfill_category_pf(InnerName, BuildInfoDir),
  binpkg_extract:touch_installed_marker(BuildDir).


% -----------------------------------------------------------------------------
%  Build directory life-cycle
% -----------------------------------------------------------------------------

%! binpkg_extract:wipe_and_create_builddir(+BuildDir) is det.
%
% Removes any existing BuildDir (recursively) and recreates the empty
% sub-tree expected by qmerge: `image/`, `build-info/`, `temp/`, `work/`.

binpkg_extract:wipe_and_create_builddir(BuildDir) :-
  ( exists_directory(BuildDir)
  -> binpkg_extract:run_command(path(rm), ['-rf', BuildDir], _)
  ;  true
  ),
  forall(
    member(Sub, ['image', 'build-info', 'temp', 'work']),
    ( os:compose_path([BuildDir, Sub], Path),
      os:ensure_directory_path(Path)
    )).


%! binpkg_extract:make_scratch_dir(+BuildDir, -ScratchDir) is det.
%
% Allocates a fresh private scratch directory under BuildDir.
% Used for the outer-tar extraction (we don't want to clutter the
% PORTAGE_BUILDDIR with the inner gpkg contents).

binpkg_extract:make_scratch_dir(BuildDir, ScratchDir) :-
  uuid(UUID),
  format(atom(Name), '.portage-ng-extract-~w', [UUID]),
  os:compose_path(BuildDir, Name, ScratchDir),
  make_directory(ScratchDir),
  filesex:chmod(ScratchDir, 0o700).


%! binpkg_extract:remove_scratch_dir(+ScratchDir) is det.
%
% Cleanup hook for `setup_call_cleanup/3`. Best-effort: we log but do not
% fail if the directory has already been removed.

binpkg_extract:remove_scratch_dir(ScratchDir) :-
  ( exists_directory(ScratchDir)
  -> catch(binpkg_extract:run_command(path(rm), ['-rf', ScratchDir], _),
           _, true)
  ;  true
  ).


%! binpkg_extract:stage_verified_gpkg(+Source, +BuildDir, +Size, +Pairs, -Staged) is semidet.
%
% Copy Source into the private build directory and verify that immutable copy
% against the Packages SIZE/MD5/SHA1 metadata before any tar command runs.

binpkg_extract:stage_verified_gpkg(Source, BuildDir, Size, Pairs, Staged) :-
  os:compose_path(BuildDir, '.portage-ng-verified.gpkg.tar', Staged),
  setup_call_cleanup(
    open(Source, read, In, [type(binary)]),
    setup_call_cleanup(
      open(Staged, write, Out, [type(binary)]),
      copy_stream_data(In, Out),
      close(Out)),
    close(In)),
  sanitize:existing_file(Staged),
  mirror:verify_size(Staged, Size, true),
  mirror:verify_hashes(Staged, Pairs, true, 0).


% -----------------------------------------------------------------------------
%  Internal gpkg Manifest and OpenPGP verification
% -----------------------------------------------------------------------------

%! binpkg_extract:verify_gpkg_manifest(+InnerDir) is semidet.
%
% Verify every outer member against the internal Manifest before either
% compressed tar is opened. Unsigned gpkg-1 is accepted under the default
% `auto` policy. If any signature is present, the clear-signed Manifest and
% every detached member signature are mandatory and must be fully trusted.

binpkg_extract:verify_gpkg_manifest(InnerDir) :-
  os:compose_path(InnerDir, 'Manifest', ManifestPath),
  sanitize:existing_file(ManifestPath),
  read_file_to_string(ManifestPath, ManifestWire, [encoding(utf8)]),
  binpkg_extract:inner_files(InnerDir, Files),
  binpkg_extract:signature_mode(ManifestWire, Files, Signed),
  binpkg_extract:signature_policy(Policy),
  ( Signed == true
  -> binpkg_extract:gpg_cleartext(InnerDir, ManifestPath, ManifestText)
  ; Policy == require
  -> format(user_error, 'binpkg_extract: unsigned gpkg rejected by signature policy~n', []),
     fail
  ;  ManifestText = ManifestWire
  ),
  binpkg_extract:parse_gpkg_manifest(ManifestText, Records),
  binpkg_extract:verify_manifest_correspondence(Files, Records),
  forall(member(gpkg_record(Name, Size, Pairs), Records),
         binpkg_extract:verify_manifest_record(InnerDir, Name, Size, Pairs)),
  ( Signed == true
  -> binpkg_extract:verify_member_signatures(InnerDir, Files)
  ;  true
  ).


%! binpkg_extract:signature_policy(-Policy) is det.

binpkg_extract:signature_policy(Policy) :-
  ( current_predicate(config:binpkg_signature_policy/1),
    config:binpkg_signature_policy(P)
  -> ( memberchk(P, [auto, require]) -> Policy = P ; Policy = require )
  ;  Policy = auto
  ).


%! binpkg_extract:inner_files(+InnerDir, -Files) is det.
%
% Sorted regular non-symlink leaf names other than Manifest.

binpkg_extract:inner_files(InnerDir, Files) :-
  directory_files(InnerDir, Names0),
  exclude(binpkg_extract:hidden_or_manifest, Names0, Names),
  findall(Name,
          ( member(Name, Names),
            sanitize:safe_distfile_name(Name),
            os:compose_path(InnerDir, Name, Path),
            sanitize:existing_file(Path)
          ),
          Files0),
  sort(Files0, Files),
  length(Names, N),
  length(Files, N).


binpkg_extract:hidden_or_manifest(Name) :-
  ( Name == '.'
  ; Name == '..'
  ; Name == 'Manifest'
  ).


%! binpkg_extract:signature_mode(+ManifestWire, +Files, -Signed) is det.

binpkg_extract:signature_mode(ManifestWire, Files, true) :-
  ( sub_string(ManifestWire, _, _, _, "-----BEGIN PGP SIGNED MESSAGE-----")
  ; member(File, Files), sub_atom(File, _, 4, 0, '.sig')
  ),
  !.
binpkg_extract:signature_mode(_, _, false).


%! binpkg_extract:parse_gpkg_manifest(+Text, -Records) is semidet.
%
% Parse DATA leaf size algorithm/hash records, rejecting duplicates and
% malformed or unsupported-only records.

binpkg_extract:parse_gpkg_manifest(Text, Records) :-
  split_string(Text, "\n", "\r", Lines0),
  exclude(=(""), Lines0, Lines),
  maplist(binpkg_extract:parse_gpkg_manifest_line, Lines, Records),
  findall(Name, member(gpkg_record(Name, _, _), Records), Names),
  sort(Names, Unique),
  same_length(Names, Unique).


binpkg_extract:parse_gpkg_manifest_line(Line, gpkg_record(Name, Size, Pairs)) :-
  split_string(Line, " \t", " \t", ["DATA", NameString, SizeString|HashTokens]),
  atom_string(Name, NameString),
  sanitize:safe_distfile_name(Name),
  number_string(Size, SizeString),
  integer(Size),
  Size >= 0,
  mirror:tokens_to_pairs(HashTokens, Pairs),
  include(mirror:strong_hash_pair, Pairs, Strong),
  Strong \== [].


%! binpkg_extract:verify_manifest_correspondence(+Files, +Records) is semidet.

binpkg_extract:verify_manifest_correspondence(Files, Records) :-
  findall(Name, member(gpkg_record(Name, _, _), Records), Names0),
  sort(Names0, Names),
  Files == Names,
  memberchk('gpkg-1', Files),
  memberchk('image.tar.zst', Files),
  memberchk('metadata.tar.zst', Files).


%! binpkg_extract:verify_manifest_record(+Dir, +Name, +Size, +Pairs) is semidet.

binpkg_extract:verify_manifest_record(Dir, Name, Size, Pairs) :-
  os:compose_path(Dir, Name, Path),
  sanitize:existing_file(Path),
  mirror:verify_size(Path, Size, true),
  mirror:verify_strong_hashes(Path, Pairs).


%! binpkg_extract:verify_member_signatures(+InnerDir, +Files) is semidet.

binpkg_extract:verify_member_signatures(InnerDir, Files) :-
  forall(
    ( member(Name, Files),
      Name \== 'gpkg-1',
      \+ sub_atom(Name, _, 4, 0, '.sig')
    ),
    ( atom_concat(Name, '.sig', SignatureName),
      memberchk(SignatureName, Files),
      os:compose_path(InnerDir, SignatureName, SignaturePath),
      os:compose_path(InnerDir, Name, DataPath),
      binpkg_extract:gpg_verify_detached(InnerDir, SignaturePath, DataPath)
    )).


%! binpkg_extract:gpg_cleartext(+WorkDir, +Manifest, -PlainText) is semidet.

binpkg_extract:gpg_cleartext(WorkDir, Manifest, PlainText) :-
  binpkg_extract:gpg_home(Home),
  binpkg_extract:run_gpg(WorkDir,
    ['--homedir', Home, '--batch', '--no-tty', '--status-fd', '2',
     '--decrypt', Manifest],
    PlainText, Status),
  binpkg_extract:gpg_status_trusted(Status).


%! binpkg_extract:gpg_verify_detached(+WorkDir, +Signature, +Data) is semidet.

binpkg_extract:gpg_verify_detached(WorkDir, Signature, Data) :-
  binpkg_extract:gpg_home(Home),
  binpkg_extract:run_gpg(WorkDir,
    ['--homedir', Home, '--batch', '--no-tty', '--status-fd', '2',
     '--verify', Signature, Data],
    _Output, Status),
  binpkg_extract:gpg_status_trusted(Status).


%! binpkg_extract:gpg_home(-Home) is semidet.

binpkg_extract:gpg_home(Home) :-
  ( current_predicate(config:binpkg_gpg_verify_home/1),
    config:binpkg_gpg_verify_home(Home0)
  -> Home = Home0
  ;  catch(preference:getenv('BINPKG_GPG_VERIFY_GPG_HOME', Home1), _, fail),
     Home1 \== '',
     Home = Home1
  ),
  exists_directory(Home).


%! binpkg_extract:run_gpg(+WorkDir, +Args, -Output, -StatusText) is semidet.
%
% Run GPG with stdout/status captured in private files to avoid pipe deadlock.

binpkg_extract:run_gpg(WorkDir, Args, Output, StatusText) :-
  uuid(UUID),
  format(atom(OutName), '.portage-ng-gpg-~w.out', [UUID]),
  format(atom(StatusName), '.portage-ng-gpg-~w.status', [UUID]),
  os:compose_path(WorkDir, OutName, OutPath),
  os:compose_path(WorkDir, StatusName, StatusPath),
  setup_call_cleanup(
    ( open(OutPath, write, Out, [type(binary)]),
      open(StatusPath, write, Err, [type(binary)])
    ),
    ( binpkg_extract:gpg_command(Command),
      binpkg_extract:executable_spec(Command, Executable),
      process_create(Executable, Args,
                     [stdin(null), stdout(stream(Out)), stderr(stream(Err)),
                      process(Pid)]),
      process_wait(Pid, Exit),
      close(Out),
      close(Err),
      Exit == exit(0),
      read_file_to_string(OutPath, Output, [encoding(utf8)]),
      read_file_to_string(StatusPath, StatusText, [encoding(utf8)])
    ),
    ( catch(close(Out, [force(true)]), _, true),
      catch(close(Err, [force(true)]), _, true),
      catch(delete_file(OutPath), _, true),
      catch(delete_file(StatusPath), _, true)
    )).


%! binpkg_extract:gpg_command(-Command) is det.

binpkg_extract:gpg_command(Command) :-
  ( current_predicate(config:binpkg_gpg_command/1),
    config:binpkg_gpg_command(C)
  -> Command = C
  ;  Command = gpg
  ).


%! binpkg_extract:executable_spec(+Command, -Spec) is det.

binpkg_extract:executable_spec(Command, Command) :-
  atom(Command),
  sub_atom(Command, 0, 1, _, '/'),
  !.
binpkg_extract:executable_spec(Command, path(Command)).


%! binpkg_extract:gpg_status_trusted(+Status) is semidet.

binpkg_extract:gpg_status_trusted(Status) :-
  sub_string(Status, _, _, _, "[GNUPG:] VALIDSIG "),
  ( sub_string(Status, _, _, _, "[GNUPG:] TRUST_FULLY")
  ; sub_string(Status, _, _, _, "[GNUPG:] TRUST_ULTIMATE")
  ),
  \+ sub_string(Status, _, _, _, "[GNUPG:] BADSIG "),
  \+ sub_string(Status, _, _, _, "[GNUPG:] ERRSIG ").


% -----------------------------------------------------------------------------
%  Tar / zstd / bunzip2 wrappers
% -----------------------------------------------------------------------------

%! binpkg_extract:extract_outer(+GpkgPath, +ScratchDir) is semidet.
%
% Untars the outer (uncompressed) gpkg archive into ScratchDir. The result
% is a single sub-directory named after the package PF + BUILD_ID
% (e.g. `jq-1.8.1-9/`) holding `image.tar.zst`, `metadata.tar.zst`,
% `gpkg-1`, and `Manifest`. Refuses the archive when the listing is unsafe.

binpkg_extract:extract_outer(GpkgPath, ScratchDir) :-
  binpkg_extract:safe_extract(GpkgPath, ScratchDir, [], outer).


%! binpkg_extract:extract_image(+ImageTarZst, +BuildDir) is semidet.
%
% Decompresses + untars `image.tar.zst` into BuildDir. The archive
% includes the `image/` prefix, so the result lands at `BuildDir/image/`.
% Requires GNU tar (uses `-I zstd` to delegate decompression to the zstd
% command in PATH). Refuses the archive when the listing is unsafe.

binpkg_extract:extract_image(ImageTarZst, BuildDir) :-
  binpkg_extract:safe_extract(ImageTarZst, BuildDir, ['-I', 'zstd'], image).


%! binpkg_extract:extract_metadata_to_build_info(+MetaTarZst, +BuildDir) is semidet.
%
% Decompresses + untars `metadata.tar.zst` into BuildDir, then rewrites
% a leading `metadata/` prefix to `build-info/` (matching what
% `portage/dbapi/vartree.py:merge()` expects). Metadata members must be
% regular files or directories. Refuses the archive when the listing is
% unsafe (including metadata symlinks, Gentoo bug 982208).

binpkg_extract:extract_metadata_to_build_info(MetaTarZst, BuildDir) :-
  binpkg_extract:safe_extract(MetaTarZst, BuildDir, ['-I', 'zstd'], metadata),
  binpkg_extract:relocate_metadata_prefix(BuildDir).


% -----------------------------------------------------------------------------
%  Safe tar extract (list, check, then extract)
% -----------------------------------------------------------------------------

%! binpkg_extract:safe_extract(+Archive, +DestDir, +ExtraTarArgs, +Kind) is semidet.
%
% Lists Archive (ExtraTarArgs are inserted before `-t`/`-x`, e.g. `-I zstd`),
% refuses it when `members_safe/2` fails, then extracts into DestDir.
% Kind is `outer`, `image`, or `metadata` (metadata forbids link members).

binpkg_extract:safe_extract(Archive, DestDir, ExtraTarArgs, Kind) :-
  ( binpkg_extract:archive_members(Archive, ExtraTarArgs, Members)
  -> true
  ;  format(user_error, 'binpkg_extract: cannot list archive ~w~n', [Archive]),
     fail
  ),
  ( binpkg_extract:members_safe(Kind, Members)
  -> true
  ;  format(user_error, 'binpkg_extract: refused unsafe archive ~w (~w)~n', [Archive, Kind]),
     fail
  ),
  append(ExtraTarArgs, ['-xf', Archive, '-C', DestDir], ExtractArgs),
  binpkg_extract:run_command(path(tar), ExtractArgs, 0).


%! binpkg_extract:archive_members(+Archive, +ExtraTarArgs, -Members) is semidet.
%
% Members is a list of `member(Type, Name, Target)` from a paired
% `tar -tf` / `tar -tvf` listing. Type is `file`, `dir`, `symlink`,
% `hardlink`, `device`, `fifo`, `socket`, `skip`, or `other`. Target is
% the link destination for symlink/hardlink members and `''` otherwise.

binpkg_extract:archive_members(Archive, ExtraTarArgs, Members) :-
  append(ExtraTarArgs, ['-tf', Archive], NameArgs),
  append(ExtraTarArgs, ['-tvf', Archive], VerboseArgs),
  binpkg_extract:run_command_lines(path(tar), NameArgs, NameLines0),
  binpkg_extract:run_command_lines(path(tar), VerboseArgs, VerboseLines0),
  exclude(binpkg_extract:blank_line, NameLines0, NameLines),
  exclude(binpkg_extract:blank_line, VerboseLines0, VerboseLines),
  length(NameLines, N),
  length(VerboseLines, N),
  maplist(binpkg_extract:pair_listing, NameLines, VerboseLines, Members).


%! binpkg_extract:blank_line(+Line) is semidet.

binpkg_extract:blank_line(Line) :-
  split_string(Line, " \t", " \t", []).


%! binpkg_extract:pair_listing(+Name, +VerboseLine, -Member) is det.

binpkg_extract:pair_listing(Name0, VerboseLine, member(Type, Name, Target)) :-
  binpkg_extract:normalize_member_name(Name0, Name),
  binpkg_extract:tv_type_target(VerboseLine, Type, Target).


%! binpkg_extract:tv_type_target(+Line, -Type, -Target) is det.

binpkg_extract:tv_type_target(Line, Type, Target) :-
  ( sub_string(Line, 0, 1, _, TypeChar)
  -> binpkg_extract:type_char(TypeChar, Type)
  ;  Type = other
  ),
  ( Type == symlink
  -> ( binpkg_extract:tv_after(Line, " -> ", Target0)
     -> binpkg_extract:normalize_link_target(Target0, Target)
     ;  Target = ''
     )
  ; Type == hardlink
  -> ( binpkg_extract:tv_after(Line, " link to ", Target0)
     -> binpkg_extract:normalize_link_target(Target0, Target)
     ;  Target = ''
     )
  ;  Target = ''
  ).


%! binpkg_extract:type_char(+Char, -Type) is det.

binpkg_extract:type_char("-", file) :- !.
binpkg_extract:type_char("d", dir) :- !.
binpkg_extract:type_char("l", symlink) :- !.
binpkg_extract:type_char("h", hardlink) :- !.
binpkg_extract:type_char("b", device) :- !.
binpkg_extract:type_char("c", device) :- !.
binpkg_extract:type_char("p", fifo) :- !.
binpkg_extract:type_char("s", socket) :- !.
binpkg_extract:type_char("g", skip) :- !.
binpkg_extract:type_char("x", skip) :- !.
binpkg_extract:type_char(_, other).


%! binpkg_extract:tv_after(+Line, +Delim, -After) is semidet.

binpkg_extract:tv_after(Line, Delim, After) :-
  sub_string(Line, Pos, DelimLen, AfterLen, Delim),
  AfterLen > 0,
  Start is Pos + DelimLen,
  sub_string(Line, Start, AfterLen, 0, After0),
  \+ sub_string(After0, _, _, _, Delim),
  After = After0.


%! binpkg_extract:normalize_member_name(+Raw, -Name) is det.

binpkg_extract:normalize_member_name(Raw, Name) :-
  atom_string(Raw, S0),
  binpkg_extract:strip_trailing_slash(S0, S1),
  ( sub_string(S1, 0, 2, _, "./")
  -> sub_string(S1, 2, _, 0, S2)
  ;  S2 = S1
  ),
  atom_string(Name, S2).


%! binpkg_extract:normalize_link_target(+Raw, -Target) is det.

binpkg_extract:normalize_link_target(Raw, Target) :-
  split_string(Raw, "", " \t", [S]),
  atom_string(Target, S).


%! binpkg_extract:strip_trailing_slash(+S0, -S) is det.

binpkg_extract:strip_trailing_slash(S0, S) :-
  ( string_length(S0, L), L > 1,
    sub_string(S0, _, 1, 0, "/")
  -> L1 is L - 1,
     sub_string(S0, 0, L1, _, S1),
     binpkg_extract:strip_trailing_slash(S1, S)
  ;  S = S0
  ).


%! binpkg_extract:members_safe(+Kind, +Members) is semidet.
%
% True when every member may be extracted into a fresh destination.
% Kind `metadata` also rejects symlink and hardlink members.

binpkg_extract:members_safe(Kind, Members) :-
  binpkg_extract:members_safe_loop(Kind, Members, []),
  !.


%! binpkg_extract:members_safe_loop(+Kind, +Members, +Seen) is semidet.

binpkg_extract:members_safe_loop(_, [], _) :- !.
binpkg_extract:members_safe_loop(Kind, [member(skip, _, _)|Rest], Seen) :-
  !,
  binpkg_extract:members_safe_loop(Kind, Rest, Seen).
binpkg_extract:members_safe_loop(Kind, [member(Type, Name, Target)|Rest], Seen) :-
  binpkg_extract:check_member(Kind, Type, Name, Target, Seen, Seen1),
  binpkg_extract:members_safe_loop(Kind, Rest, Seen1).


%! binpkg_extract:check_member(+Kind, +Type, +Name, +Target, +Seen, -Seen1) is semidet.

binpkg_extract:check_member(Kind, Type, Name, Target, Seen, Seen1) :-
  \+ binpkg_extract:forbidden_type(Kind, Type),
  \+ binpkg_extract:name_unsafe(Name),
  ( Type == hardlink
  -> \+ binpkg_extract:name_unsafe(Target)
  ;  true
  ),
  binpkg_extract:path_components(Name, Comps),
  Comps \== [],
  append(ParentComps, [_Leaf], Comps),
  binpkg_extract:resolve_components(ParentComps, Seen, _ResolvedParent),
  ( Type == symlink
  -> binpkg_extract:normalize_member_name(Name, Norm),
     Seen1 = [symlink(Norm, Target)|Seen]
  ;  Seen1 = Seen
  ).


%! binpkg_extract:forbidden_type(+Kind, +Type) is semidet.

binpkg_extract:forbidden_type(_, device).
binpkg_extract:forbidden_type(_, fifo).
binpkg_extract:forbidden_type(_, socket).
binpkg_extract:forbidden_type(_, other).
binpkg_extract:forbidden_type(outer, symlink).
binpkg_extract:forbidden_type(outer, hardlink).
binpkg_extract:forbidden_type(metadata, symlink).
binpkg_extract:forbidden_type(metadata, hardlink).


%! binpkg_extract:name_unsafe(+Name) is semidet.

binpkg_extract:name_unsafe(Name) :-
  atom_string(Name, S),
  ( S == ""
  ; sub_string(S, 0, 1, _, "/")
  ; binpkg_extract:path_components(S, Comps),
    member("..", Comps)
  ).


%! binpkg_extract:path_components(+Name, -Components) is det.

binpkg_extract:path_components(Name, Components) :-
  atom_string(Name, S),
  split_string(S, "/", "/", Parts0),
  exclude(binpkg_extract:skip_component, Parts0, Components).

binpkg_extract:skip_component("").
binpkg_extract:skip_component(".").


%! binpkg_extract:resolve_components(+Comps, +Seen, -Resolved) is semidet.
%
% Walks Comps, following previously listed symlink members. Fails when a
% followed target is absolute or pops above the extract root.

binpkg_extract:resolve_components(Comps, Seen, Resolved) :-
  binpkg_extract:resolve_components(Comps, Seen, [], Resolved, 32).

binpkg_extract:resolve_components([], _Seen, Acc, Acc, _) :- !.
binpkg_extract:resolve_components([Comp|Rest], Seen, Acc, Resolved, Depth) :-
  Depth > 0,
  append(Acc, [Comp], Next0),
  binpkg_extract:follow_symlinks(Next0, Seen, Next, Depth),
  Depth1 is Depth - 1,
  binpkg_extract:resolve_components(Rest, Seen, Next, Resolved, Depth1).


%! binpkg_extract:follow_symlinks(+Acc, +Seen, -Out, +Depth) is semidet.

binpkg_extract:follow_symlinks(Acc, _Seen, Acc, Depth) :-
  Depth =< 0, !, fail.
binpkg_extract:follow_symlinks(Acc, Seen, Out, Depth) :-
  atomic_list_concat(Acc, '/', Path),
  memberchk(symlink(Path, Target), Seen),
  !,
  \+ binpkg_extract:name_unsafe(Target),
  \+ sub_atom(Target, 0, 1, _, '/'),
  append(Parent, [_], Acc),
  binpkg_extract:join_target(Parent, Target, Joined),
  Depth1 is Depth - 1,
  binpkg_extract:follow_symlinks(Joined, Seen, Out, Depth1).
binpkg_extract:follow_symlinks(Acc, _Seen, Acc, _).


%! binpkg_extract:join_target(+Parent, +Target, -Joined) is semidet.

binpkg_extract:join_target(Parent, Target, Joined) :-
  binpkg_extract:path_components(Target, TComps),
  binpkg_extract:apply_components(Parent, TComps, Joined).

binpkg_extract:apply_components(Acc, [], Acc) :- !.
binpkg_extract:apply_components(Acc, [".."|Rest], Out) :-
  !,
  Acc = [_|_],
  append(Parent, [_], Acc),
  binpkg_extract:apply_components(Parent, Rest, Out).
binpkg_extract:apply_components(Acc, [Comp|Rest], Out) :-
  append(Acc, [Comp], Acc1),
  binpkg_extract:apply_components(Acc1, Rest, Out).


%! binpkg_extract:relocate_metadata_prefix(+BuildDir) is det.
%
% Moves `BuildDir/metadata/` onto `BuildDir/build-info/` when the archive
% used the stock gpkg `metadata/` prefix. No-op when that directory is
% absent (the members already landed at the destination names).

binpkg_extract:relocate_metadata_prefix(BuildDir) :-
  os:compose_path([BuildDir, 'metadata'], MetaDir),
  os:compose_path([BuildDir, 'build-info'], InfoDir),
  ( exists_directory(MetaDir)
  -> binpkg_extract:move_dir_contents(MetaDir, InfoDir),
     binpkg_extract:run_command(path(rm), ['-rf', MetaDir], _)
  ;  true
  ).


%! binpkg_extract:move_dir_contents(+SrcDir, +DestDir) is det.

binpkg_extract:move_dir_contents(SrcDir, DestDir) :-
  os:ensure_directory_path(DestDir),
  directory_files(SrcDir, Names0),
  exclude(=('.'), Names0, Names1),
  exclude(=('..'), Names1, Names),
  forall(
    member(Name, Names),
    ( os:compose_path([SrcDir, Name], Src),
      os:compose_path([DestDir, Name], Dest),
      rename_file(Src, Dest)
    )).


%! binpkg_extract:decompress_environment_if_present(+BuildInfoDir, +EnvFile) is det.
%
% Decompresses `BuildInfoDir/environment.bz2` to EnvFile via bunzip2.
% Silently no-ops if the binpkg shipped without a saved environment
% (some legacy or hand-built packages omit it; ebuild qmerge then falls
% back to a fresh environment).

binpkg_extract:decompress_environment_if_present(BuildInfoDir, EnvFile) :-
  os:compose_path([BuildInfoDir, 'environment.bz2'], EnvBz2),
  ( exists_file(EnvBz2)
  -> binpkg_extract:bunzip2_to_file(EnvBz2, EnvFile)
  ;  true
  ).


%! binpkg_extract:bunzip2_to_file(+InputBz2, +OutputFile) is semidet.
%
% Spawns `bunzip2 -c <input>` and pipes stdout to OutputFile. We avoid
% shelling out via `sh -c '... > ...'` to keep the path/argv contract
% explicit and quote-safe.  The stdout pipe is read in octet mode so
% ISO-8859 bytes in saved binpkg environments copy through unchanged.

binpkg_extract:bunzip2_to_file(InputBz2, OutputFile) :-
  setup_call_cleanup(
    open(OutputFile, write, OutStream, [type(binary)]),
    ( process_create(
        path(bunzip2),
        ['-c', InputBz2],
        [stdout(pipe(InPipe)), process(Pid)]),
      set_stream(InPipe, encoding(octet)),
      copy_stream_data(InPipe, OutStream),
      close(InPipe),
      process_wait(Pid, exit(0))
    ),
    close(OutStream)
  ).


%! binpkg_extract:patch_binary_merge_environment(+EnvFile, +BuildInfoDir) is det.
%
% Rewrites `temp/environment` for binary qmerge and, when the gpkg shipped
% `build-info/environment.bz2`, recompresses the patched file back into
% place.  The saved environment was captured during a source build; qmerge
% preinst re-saves `${T}/environment` via `__save_ebuild_env`, so a
% trailing append alone is not durable.  Stripping prior `MERGE_TYPE` /
% `EMERGE_FROM` exports and writing canonical binary markers mirrors
% `_emerge/Binpkg.py`.

binpkg_extract:patch_binary_merge_environment(EnvFile, BuildInfoDir) :-
  binpkg_extract:rewrite_binary_merge_markers(EnvFile),
  binpkg_extract:recompress_environment_bz2_if_present(EnvFile, BuildInfoDir).


%! binpkg_extract:rewrite_binary_merge_markers(+EnvFile) is det.

binpkg_extract:rewrite_binary_merge_markers(EnvFile) :-
  ( exists_file(EnvFile)
  -> setup_call_cleanup(
       open(EnvFile, read, In, [type(binary)]),
       binpkg_extract:read_env_lines(In, Lines),
       close(In)
     ),
     exclude(binpkg_extract:binary_merge_env_export_line, Lines, Kept),
     append(Kept,
            ["", 'export MERGE_TYPE="binary"', 'export EMERGE_FROM="binary"'],
            OutLines),
     setup_call_cleanup(
       open(EnvFile, write, Out, [type(binary)]),
       binpkg_extract:write_env_lines(Out, OutLines),
       close(Out)
     )
  ;  setup_call_cleanup(
       open(EnvFile, write, Out, [type(binary)]),
       ( format(Out, 'export MERGE_TYPE="binary"~n', []),
         format(Out, 'export EMERGE_FROM="binary"~n', [])
       ),
       close(Out)
     )
  ).


%! binpkg_extract:read_env_lines(+Stream, -Lines) is det.

binpkg_extract:read_env_lines(In, Lines) :-
  read_line_to_string(In, Line0),
  binpkg_extract:read_env_lines_loop(In, Line0, Lines).

binpkg_extract:read_env_lines_loop(_, end_of_file, []) :- !.
binpkg_extract:read_env_lines_loop(In, Line, [Line|Rest]) :-
  read_line_to_string(In, Line0),
  binpkg_extract:read_env_lines_loop(In, Line0, Rest).


%! binpkg_extract:write_env_lines(+Stream, +Lines) is det.

binpkg_extract:write_env_lines(_, []).
binpkg_extract:write_env_lines(Out, [Line|Rest]) :-
  format(Out, '~s~n', [Line]),
  binpkg_extract:write_env_lines(Out, Rest).


%! binpkg_extract:binary_merge_env_export_line(+Line) is semidet.
%
% True when Line is an environment export of `MERGE_TYPE` or
% `EMERGE_FROM` at column zero (not ebuild snippet text embedded in the
% saved environment).

binpkg_extract:binary_merge_env_export_line(Line) :-
  ( Line == "export MERGE_TYPE=\"binary\""
  ; Line == "export EMERGE_FROM=\"binary\""
  ; sub_string(Line, 0, _, _, "export MERGE_TYPE=")
  ; sub_string(Line, 0, _, _, "export EMERGE_FROM=")
  ).


%! binpkg_extract:recompress_environment_bz2_if_present(+EnvFile, +BuildInfoDir) is det.
%
% When the gpkg shipped `environment.bz2`, rewrite it from the patched
% `temp/environment` so any later extraction sees binary-merge markers.

binpkg_extract:recompress_environment_bz2_if_present(EnvFile, BuildInfoDir) :-
  os:compose_path([BuildInfoDir, 'environment.bz2'], EnvBz2),
  ( exists_file(EnvBz2)
  -> setup_call_cleanup(
       open(EnvBz2, write, OutStream, [type(binary)]),
       ( process_create(
           path(bzip2),
           ['-c', EnvFile],
           [stdout(pipe(InPipe)), process(Pid)]),
         set_stream(InPipe, encoding(octet)),
         copy_stream_data(InPipe, OutStream),
         close(InPipe),
         process_wait(Pid, exit(0))
       ),
       close(OutStream)
     )
  ;  true
  ).


%! binpkg_extract:backfill_temp_envd_from_image(+BuildDir) is det.
%
% Copies `image/etc/env.d/*` into `${T}/` when the temp counterpart is
% absent.  Some ebuilds write config to `${T}/${ENVDFILE}` during setup
% and expect that file (or a binary-merge fallback to `${EROOT}/etc/env.d`)
% during postinst.  Binpkgs only carry the installed payload in `image/`,
% not the transient temp files from the producer's setup phase.

binpkg_extract:backfill_temp_envd_from_image(BuildDir) :-
  os:compose_path([BuildDir, 'image', 'etc', 'env.d'], ImageEnvDir),
  os:compose_path([BuildDir, 'temp'], TempDir),
  ( exists_directory(ImageEnvDir)
  -> directory_files(ImageEnvDir, Names0),
     exclude(=('.'), Names0, Names1),
     exclude(=('..'), Names1, Names),
     forall(
       ( member(Name, Names),
         \+ sub_string(Name, 0, 1, _, '.'),
         os:compose_path([ImageEnvDir, Name], Src),
         os:compose_path([TempDir, Name], Dest),
         exists_file(Src),
         \+ exists_file(Dest)
       ),
       copy_file(Src, Dest)
     )
  ;  true
  ).


% -----------------------------------------------------------------------------
%  Build-info backfill + qmerge marker
% -----------------------------------------------------------------------------

%! binpkg_extract:backfill_category_pf(+InnerName, +BuildInfoDir) is det.
%
% `_emerge/Binpkg.py` writes CATEGORY and PF into build-info if the
% binpkg's metadata didn't include them (some legacy packages omit one or
% both). InnerName is `jq-1.8.1-9` style; we don't have CATEGORY in that
% string, so for the missing-CATEGORY case we punt to the caller (the
% `binpkg_exec` orchestrator already knows the category from the cache).
%
% In practice, modern (gpkg-1) binpkgs always ship CATEGORY and PF, so
% this is a defensive no-op for the common case.

binpkg_extract:backfill_category_pf(InnerName, BuildInfoDir) :-
  os:compose_path([BuildInfoDir, 'PF'], PfFile),
  ( exists_file(PfFile)
  -> true
  ;  binpkg_extract:strip_build_id_suffix(InnerName, Pf),
     setup_call_cleanup(
       open(PfFile, write, PfStream),
       format(PfStream, '~w~n', [Pf]),
       close(PfStream)
     )
  ).


%! binpkg_extract:strip_build_id_suffix(+InnerName, -Pf) is det.
%
% Strips the trailing `-<BUILD_ID>` from an inner dir name to recover the
% PF (e.g. `'jq-1.8.1-9'` -> `'jq-1.8.1'`). Falls back to the input
% unchanged if there is no trailing dash-integer (defensive).

binpkg_extract:strip_build_id_suffix(InnerName, Pf) :-
  atom_string(InnerName, InnerStr),
  ( binpkg_extract:rsplit_dash_integer(InnerStr, PfStr)
  -> atom_string(Pf, PfStr)
  ;  Pf = InnerName
  ).


%! binpkg_extract:rsplit_dash_integer(+Str, -Head) is semidet.
%
% Splits Str on its rightmost `-` and unifies Head with the prefix iff
% the suffix is a non-empty integer. Fails otherwise.

binpkg_extract:rsplit_dash_integer(Str, Head) :-
  string_length(Str, Len),
  binpkg_extract:last_dash_pos(Str, Len, Pos),
  Pos > 0,
  After is Pos + 1,
  TailLen is Len - After,
  TailLen > 0,
  sub_string(Str, After, TailLen, 0, TailStr),
  number_string(N, TailStr), integer(N),
  sub_string(Str, 0, Pos, _, Head).

binpkg_extract:last_dash_pos(Str, Len, Pos) :-
  Last is Len - 1,
  binpkg_extract:last_dash_scan(Str, Last, Pos).

binpkg_extract:last_dash_scan(_Str, -1, _) :- !, fail.
binpkg_extract:last_dash_scan(Str, Idx, Idx) :-
  sub_string(Str, Idx, 1, _, "-"), !.
binpkg_extract:last_dash_scan(Str, Idx, Pos) :-
  Prev is Idx - 1,
  binpkg_extract:last_dash_scan(Str, Prev, Pos).


%! binpkg_extract:touch_installed_marker(+BuildDir) is det.
%
% Creates an empty `BuildDir/.installed` file. `ebuild qmerge` checks for
% this marker and bails immediately with "install phase has not been run"
% if it is absent (see `portage/package/ebuild/doebuild.py` ~line 1573).
% Conceptually we are asserting "the install phase happened (in another
% process, namely whoever produced the gpkg)".

binpkg_extract:touch_installed_marker(BuildDir) :-
  os:compose_path([BuildDir, '.installed'], Marker),
  setup_call_cleanup(
    open(Marker, write, S),
    true,
    close(S)
  ).


% -----------------------------------------------------------------------------
%  Process spawning helper
% -----------------------------------------------------------------------------

%! binpkg_extract:run_command(+ExeSpec, +Args, ?ExitCode) is semidet.
%
% Spawns ExeSpec(Args) inheriting the parent's stdout/stderr (so progress
% and error messages flow through to the user's terminal exactly the way
% `ebuild_exec:run_phases/4` already does). If ExitCode is bound on entry,
% succeeds iff the child exits with that code. If unbound, succeeds with
% whatever the child returned and binds ExitCode to it.

binpkg_extract:run_command(Exe, Args, ExitCode) :-
  process_create(
    Exe, Args,
    [stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(Got)),
  ( var(ExitCode) -> ExitCode = Got
  ; Got =:= ExitCode
  ).


%! binpkg_extract:run_command_lines(+ExeSpec, +Args, -Lines) is semidet.
%
% Spawns ExeSpec(Args), captures stdout as a list of lines, and succeeds
% only when the child exits 0.

binpkg_extract:run_command_lines(Exe, Args, Lines) :-
  setup_call_cleanup(
    process_create(Exe, Args, [stdout(pipe(Out)), stderr(null), process(Pid)]),
    ( read_string(Out, _, Text),
      process_wait(Pid, exit(0)),
      split_string(Text, "\n", "", Lines0),
      exclude(==(""), Lines0, Lines)
    ),
    close(Out)).
