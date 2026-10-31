/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> BINPKGTEST
Unit tests for binary-package extract safety and user-patch skipping.
*/

:- module(binpkgtest, []).

:- use_module(library(plunit)).
:- use_module(library(lists)).

% =============================================================================
%  BINPKGTEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Archive member checker (Gentoo bug 982208)
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_extract_members).

test(accepts_plain_tree) :-
  binpkg_extract:members_safe(image,
    [member(dir, image, ''),
     member(file, 'image/bin/foo', '')]).

test(rejects_absolute_name, [fail]) :-
  binpkg_extract:members_safe(image, [member(file, '/etc/passwd', '')]).

test(rejects_dotdot_name, [fail]) :-
  binpkg_extract:members_safe(image, [member(file, 'image/../../etc/passwd', '')]).

test(rejects_device_node, [fail]) :-
  binpkg_extract:members_safe(image, [member(device, 'image/null', '')]).

test(rejects_write_through_absolute_symlink, [fail]) :-
  binpkg_extract:members_safe(image,
    [member(symlink, 'image/x', '/'),
     member(file, 'image/x/etc/cron.d/evil', '')]).

test(rejects_write_through_dotdot_symlink, [fail]) :-
  binpkg_extract:members_safe(image,
    [member(symlink, link, '..'),
     member(file, 'link/pwned', '')]).

test(allows_internal_symlink) :-
  binpkg_extract:members_safe(image,
    [member(dir, 'image/usr', ''),
     member(dir, 'image/usr/lib', ''),
     member(symlink, 'image/usr/lib64', lib),
     member(file, 'image/usr/lib64/foo.so', '')]).

test(metadata_rejects_symlink, [fail]) :-
  binpkg_extract:members_safe(metadata,
    [member(dir, metadata, ''),
     member(symlink, 'metadata/USE', '/tmp/USE')]).

test(metadata_accepts_regular_files) :-
  binpkg_extract:members_safe(metadata,
    [member(dir, metadata, ''),
     member(file, 'metadata/USE', '')]).

:- end_tests(binpkg_extract_members).


% -----------------------------------------------------------------------------
%  Real tar extract refuses a symlink-escape archive
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_extract_tar).

test(safe_extract_blocks_escape, [setup(binpkgtest:escape_tar_setup(State)),
                                  cleanup(binpkgtest:escape_tar_cleanup(State))]) :-
  State = state(Archive, Dest, Canary),
  binpkg_extract:archive_members(Archive, [], Members),
  \+ binpkg_extract:members_safe(image, Members),
  \+ binpkg_extract:safe_extract(Archive, Dest, [], image),
  \+ exists_file(Canary).

test(safe_extract_accepts_plain, [setup(binpkgtest:plain_tar_setup(State)),
                                  cleanup(binpkgtest:plain_tar_cleanup(State))]) :-
  State = state(Archive, Dest, Expected),
  binpkg_extract:safe_extract(Archive, Dest, [], image),
  exists_file(Expected).

:- end_tests(binpkg_extract_tar).


% -----------------------------------------------------------------------------
%  /etc/portage/patches vs binpkg selection
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_user_patches).

test(pn_directory_applies, [setup(binpkgtest:patches_setup(State)),
                            cleanup(binpkgtest:patches_cleanup(State))]) :-
  binpkg_exec:user_patches_apply('app-misc', foo, '1.0', '0', _).

test(versioned_directory_applies, [setup(binpkgtest:patches_setup(State)),
                                   cleanup(binpkgtest:patches_cleanup(State))]) :-
  binpkg_exec:user_patches_apply('app-misc', bar, '2.1', '0', Dir),
  atom_concat(_, 'bar-2.1', Dir).

test(slot_directory_applies, [setup(binpkgtest:patches_setup(State)),
                              cleanup(binpkgtest:patches_cleanup(State))]) :-
  binpkg_exec:user_patches_apply('app-misc', baz, '3.0', '2', Dir),
  atom_concat(_, 'baz:2', Dir).

test(empty_directory_does_not_apply, [setup(binpkgtest:patches_setup(State)),
                                      cleanup(binpkgtest:patches_cleanup(State)),
                                      fail]) :-
  binpkg_exec:user_patches_apply('app-misc', empty, '1.0', '0', _).

test(other_package_does_not_apply, [setup(binpkgtest:patches_setup(State)),
                                    cleanup(binpkgtest:patches_cleanup(State)),
                                    fail]) :-
  binpkg_exec:user_patches_apply('app-misc', other, '1.0', '0', _).

test(entry_allowed_skips_when_patches,
     [setup(binpkgtest:patches_entry_setup(State)),
      cleanup(binpkgtest:patches_entry_cleanup(State)),
      fail]) :-
  binpkg_exec:entry_allowed(testrepo, 'app-misc/foo-1.0').

test(usepkg_include_does_not_override_patches,
     [setup(binpkgtest:patches_entry_setup(State)),
      cleanup(binpkgtest:patches_entry_cleanup(State)),
      fail]) :-
  asserta(config:usepkg_include_atom(foo), Ref),
  ( binpkg_exec:entry_allowed(testrepo, 'app-misc/foo-1.0')
  -> erase(Ref), true
  ;  erase(Ref), fail
  ).

test(ignore_policy_allows_patched_entry,
     [setup(binpkgtest:patches_entry_setup(State)),
      cleanup(binpkgtest:patches_entry_cleanup(State))]) :-
  preference:with_local_flag(nobinpkgrespectuserpatches,
    binpkg_exec:entry_allowed(testrepo, 'app-misc/foo-1.0')).

:- end_tests(binpkg_user_patches).


% -----------------------------------------------------------------------------
%  Binpkg path containment
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_path_security).

test(accepts_contained_regular_file) :-
  binpkgtest:mktemp_dir(Root),
  setup_call_cleanup(
    true,
    ( os:compose_path([Root, cat, pkg], Dir),
      make_directory_path(Dir),
      os:compose_path(Dir, archive, Path),
      setup_call_cleanup(open(Path, write, Out), write(Out, data), close(Out)),
      sanitize:contained_regular_file(Root, 'cat/pkg/archive', Canonical),
      Canonical == Path
    ),
    binpkgtest:rm_rf(Root)).

test(rejects_relative_traversal, [fail]) :-
  sanitize:safe_relative_path('../outside').

test(rejects_absolute_path, [fail]) :-
  sanitize:safe_relative_path('/tmp/outside').

test(rejects_intermediate_symlink,
     [condition(current_predicate(link_file/3)), fail]) :-
  binpkgtest:mktemp_dir(Root),
  setup_call_cleanup(
    true,
    ( binpkgtest:mktemp_dir(Outside),
      setup_call_cleanup(
        true,
        ( os:compose_path(Outside, archive, Archive),
          setup_call_cleanup(open(Archive, write, Out), write(Out, data), close(Out)),
          os:compose_path(Root, linked, Link),
          link_file(Outside, Link, symbolic),
          sanitize:contained_regular_file(Root, 'linked/archive', _)
        ),
        binpkgtest:rm_rf(Outside))
    ),
    binpkgtest:rm_rf(Root)).

:- end_tests(binpkg_path_security).


% -----------------------------------------------------------------------------
%  Internal Manifest and OpenPGP signatures
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_manifest_security).

test(unsigned_manifest_valid) :-
  binpkgtest:gpkg_inner_fixture(unsigned, State),
  setup_call_cleanup(
    true,
    ( State = state(_Root, Inner, _Home),
      binpkg_extract:verify_gpkg_manifest(Inner)
    ),
    binpkgtest:gpkg_inner_cleanup(State)).

test(unsigned_rejected_when_required, [fail]) :-
  binpkgtest:gpkg_inner_fixture(unsigned, State),
  setup_call_cleanup(
    asserta(config:binpkg_signature_policy(require), Ref),
    ( State = state(_Root, Inner, _Home),
      binpkg_extract:verify_gpkg_manifest(Inner)
    ),
    ( erase(Ref), binpkgtest:gpkg_inner_cleanup(State) )).

test(tampered_member_rejected, [fail]) :-
  binpkgtest:gpkg_inner_fixture(unsigned, State),
  setup_call_cleanup(
    true,
    ( State = state(_Root, Inner, _Home),
      os:compose_path(Inner, 'image.tar.zst', Image),
      setup_call_cleanup(open(Image, append, Out), write(Out, tampered), close(Out)),
      binpkg_extract:verify_gpkg_manifest(Inner)
    ),
    binpkgtest:gpkg_inner_cleanup(State)).

test(trusted_signed_manifest,
     [condition(binpkgtest:gpg_available), nondet]) :-
  binpkgtest:gpkg_inner_fixture(signed, State),
  State = state(_Root, Inner, Home),
  setup_call_cleanup(
    asserta(config:binpkg_gpg_verify_home(Home), Ref),
    binpkg_extract:verify_gpkg_manifest(Inner),
    ( erase(Ref), binpkgtest:gpkg_inner_cleanup(State) )).

test(signed_unknown_key_rejected,
     [condition(binpkgtest:gpg_available), fail]) :-
  binpkgtest:gpkg_inner_fixture(signed, State),
  binpkgtest:mktemp_dir(EmptyHome),
  filesex:chmod(EmptyHome, 0o700),
  State = state(_Root, Inner, _Home),
  setup_call_cleanup(
    asserta(config:binpkg_gpg_verify_home(EmptyHome), Ref),
    binpkg_extract:verify_gpkg_manifest(Inner),
    ( erase(Ref),
      binpkgtest:rm_rf(EmptyHome),
      binpkgtest:gpkg_inner_cleanup(State)
    )).

:- end_tests(binpkg_manifest_security).


% -----------------------------------------------------------------------------
%  Runtime-switchable USE flags (GLEP 62, IUSE_RUNTIME)
% -----------------------------------------------------------------------------

:- begin_tests(binpkg_iuse_runtime).

test(source_runtime_flags, [setup(binpkgtest:runtime_fixture(_)),
                            cleanup(binpkgtest:runtime_cleanup)]) :-
  binpkg_exec:entry_runtime_flags(testsrc, 'app-misc/foo-1.0', Flags),
  Flags == [bar, baz].

test(runtime_flag_missing_from_iuse_dropped,
     [setup(binpkgtest:runtime_fixture(_)),
      cleanup(binpkgtest:runtime_cleanup)]) :-
  binpkg_exec:entry_runtime_flags(testsrc, 'app-misc/bad-1.0', Flags),
  Flags == [bar].

test(binpkg_runtime_flags_verbatim_shape,
     [setup(binpkgtest:runtime_fixture(_)),
      cleanup(binpkgtest:runtime_cleanup)]) :-
  binpkg_exec:entry_runtime_flags(binpkg, 'app-misc/foo-1.0-1', Flags),
  Flags == [bar, baz].

test(shared_runtime_flags, [setup(binpkgtest:runtime_fixture(_)),
                            cleanup(binpkgtest:runtime_cleanup)]) :-
  binpkg_exec:runtime_flags(testsrc, 'app-misc/foo-1.0',
                            'app-misc/foo-1.0-1', Flags),
  Flags == [bar, baz].

test(adjust_takes_config_values) :-
  binpkg_exec:adjust_runtime_use([baz], [bar], [bar, baz], absent, Eff),
  sort(Eff, Sorted),
  Sorted == [bar].

test(adjust_keeps_non_runtime_flags) :-
  binpkg_exec:adjust_runtime_use([baz, regular], [bar], [bar, baz],
                                 absent, Eff),
  sort(Eff, Sorted),
  Sorted == [bar, regular].

test(adjust_no_change_when_config_matches) :-
  binpkg_exec:adjust_runtime_use([baz], [baz], [bar, baz], absent, Eff),
  Eff == [baz].

test(adjust_required_use_violation_keeps_built) :-
  ReqUse = terms([at_most_one_of_group([required(bar), required(baz)])]),
  binpkg_exec:adjust_runtime_use([baz], [bar, baz], [bar, baz],
                                 ReqUse, Eff),
  Eff == [baz].

test(adjust_required_use_satisfied_takes_config) :-
  ReqUse = terms([at_most_one_of_group([required(bar), required(baz)])]),
  binpkg_exec:adjust_runtime_use([baz], [bar], [bar, baz], ReqUse, Eff),
  sort(Eff, Sorted),
  Sorted == [bar].

test(adjust_invalid_required_use_keeps_built) :-
  binpkg_exec:adjust_runtime_use([baz], [bar], [bar, baz], invalid, Eff),
  Eff == [baz].

test(required_use_conditional_group) :-
  Terms = [use_conditional_group(positive, bar, _://_,
                                 [required(baz)])],
  binpkg_exec:required_use_holds(Terms, []),
  binpkg_exec:required_use_holds(Terms, [bar, baz]),
  \+ binpkg_exec:required_use_holds(Terms, [bar]).

test(required_use_exactly_one) :-
  Terms = [exactly_one_of_group([required(bar), required(baz)])],
  binpkg_exec:required_use_holds(Terms, [bar]),
  \+ binpkg_exec:required_use_holds(Terms, []),
  \+ binpkg_exec:required_use_holds(Terms, [bar, baz]).

:- end_tests(binpkg_iuse_runtime).


% -----------------------------------------------------------------------------
%  Test fixtures
% -----------------------------------------------------------------------------

%! binpkgtest:runtime_fixture(-State) is det.
%
% Cache facts for the GLEP 62 tests: a source entry (parsed-row
% shape) and a binpkg entry (verbatim-atom shape), both declaring
% IUSE "bar baz regular" with IUSE_RUNTIME "bar baz", plus a source
% entry whose IUSE_RUNTIME names a flag missing from its IUSE.

binpkgtest:runtime_fixture(state) :-
  forall(member(F, [bar, baz, regular]),
         assertz(cache:entry_metadata(testsrc, 'app-misc/foo-1.0', iuse, F))),
  forall(member(F, [bar, baz]),
         assertz(cache:entry_metadata(testsrc, 'app-misc/foo-1.0',
                                      iuse_runtime, F))),
  assertz(cache:entry_metadata(testsrc, 'app-misc/bad-1.0', iuse, bar)),
  forall(member(F, [bar, bogus]),
         assertz(cache:entry_metadata(testsrc, 'app-misc/bad-1.0',
                                      iuse_runtime, F))),
  assertz(cache:entry_metadata(binpkg, 'app-misc/foo-1.0-1',
                               iuse, 'bar baz regular')),
  assertz(cache:entry_metadata(binpkg, 'app-misc/foo-1.0-1',
                               iuse_runtime, 'bar baz')),
  assertz(cache:entry_metadata(binpkg, 'app-misc/foo-1.0-1', use, 'baz')).


%! binpkgtest:runtime_cleanup is det.
%
% Retract the cache facts asserted by runtime_fixture/1.

binpkgtest:runtime_cleanup :-
  retractall(cache:entry_metadata(testsrc, 'app-misc/foo-1.0', _, _)),
  retractall(cache:entry_metadata(testsrc, 'app-misc/bad-1.0', _, _)),
  retractall(cache:entry_metadata(binpkg, 'app-misc/foo-1.0-1', _, _)).


%! binpkgtest:mktemp_dir(-Dir) is det.

binpkgtest:mktemp_dir(Dir) :-
  tmp_file(binpkgtest, Tmp),
  ( exists_file(Tmp) -> delete_file(Tmp) ; true ),
  make_directory(Tmp),
  Dir = Tmp.


%! binpkgtest:rm_rf(+Dir) is det.

binpkgtest:rm_rf(Dir) :-
  ( exists_directory(Dir)
  -> catch(process_create(path(rm), ['-rf', Dir], [process(Pid)]), _, true),
     ( var(Pid) -> true ; process_wait(Pid, _) )
  ;  true
  ).


%! binpkgtest:escape_tar_setup(-State) is det.
%
% Builds an archive whose first member is a symlink `link` -> `../canary`
% and whose second member is `link/pwned`. An unrestricted extract into
% Dest would write Dest/../canary/pwned.

binpkgtest:escape_tar_setup(state(Archive, Dest, Canary)) :-
  binpkgtest:mktemp_dir(Root),
  os:compose_path([Root, src], Src),
  os:compose_path([Root, dest], Dest),
  os:compose_path([Root, canary], CanaryDir),
  os:compose_path([Root, staged], Staged),
  os:compose_path([CanaryDir, pwned], Canary),
  make_directory(Src),
  make_directory(Dest),
  make_directory(CanaryDir),
  os:compose_path([Src, link], Link),
  process_create(path(ln), ['-s', '../canary', Link], [process(Ln)]),
  process_wait(Ln, exit(0)),
  os:compose_path([Root, 'escape.tar'], Archive),
  process_create(path(tar), ['-cf', Archive, '-C', Src, link], [process(Tar1)]),
  process_wait(Tar1, exit(0)),
  os:compose_path([Staged, link], StagedLink),
  make_directory_path(StagedLink),
  os:compose_path([StagedLink, pwned], StagedFile),
  setup_call_cleanup(
    open(StagedFile, write, Out),
    write(Out, pwned),
    close(Out)),
  process_create(path(tar),
                 ['-uf', Archive, '-C', Staged, 'link/pwned'],
                 [process(Tar2)]),
  process_wait(Tar2, exit(0)),
  nb_setval(binpkgtest_escape_root, Root).


%! binpkgtest:escape_tar_cleanup(+State) is det.

binpkgtest:escape_tar_cleanup(_) :-
  ( nb_current(binpkgtest_escape_root, Root)
  -> binpkgtest:rm_rf(Root),
     nb_delete(binpkgtest_escape_root)
  ;  true
  ).


%! binpkgtest:plain_tar_setup(-State) is det.

binpkgtest:plain_tar_setup(state(Archive, Dest, Expected)) :-
  binpkgtest:mktemp_dir(Root),
  os:compose_path([Root, src], Src),
  os:compose_path([Root, dest], Dest),
  make_directory(Src),
  make_directory(Dest),
  os:compose_path([Src, image], ImageDir),
  make_directory(ImageDir),
  os:compose_path([ImageDir, hello], Hello),
  setup_call_cleanup(
    open(Hello, write, Out),
    write(Out, hi),
    close(Out)),
  os:compose_path([Root, 'plain.tar'], Archive),
  process_create(path(tar), ['-cf', Archive, '-C', Src, image], [process(Pid)]),
  process_wait(Pid, exit(0)),
  os:compose_path([Dest, image, hello], Expected),
  nb_setval(binpkgtest_plain_root, Root).


%! binpkgtest:plain_tar_cleanup(+State) is det.

binpkgtest:plain_tar_cleanup(_) :-
  ( nb_current(binpkgtest_plain_root, Root)
  -> binpkgtest:rm_rf(Root),
     nb_delete(binpkgtest_plain_root)
  ;  true
  ).


%! binpkgtest:patches_setup(-State) is det.

binpkgtest:patches_setup(conf(ConfDir, Ref)) :-
  binpkgtest:mktemp_dir(ConfDir),
  binpkgtest:write_patch(ConfDir, 'app-misc', foo, 'fix.patch'),
  binpkgtest:write_patch(ConfDir, 'app-misc', 'bar-2.1', 'ver.patch'),
  binpkgtest:write_patch(ConfDir, 'app-misc', 'baz:2', 'slot.diff'),
  os:compose_path([ConfDir, patches, 'app-misc', empty], EmptyDir),
  make_directory_path(EmptyDir),
  asserta(config:portage_confdir(ConfDir), Ref).


%! binpkgtest:patches_cleanup(+State) is det.

binpkgtest:patches_cleanup(conf(ConfDir, Ref)) :-
  erase(Ref),
  retractall(binpkg_exec:user_patches_warned(_, _)),
  binpkgtest:rm_rf(ConfDir).


%! binpkgtest:patches_entry_setup(-State) is det.

binpkgtest:patches_entry_setup(entry(ConfState, CacheRef)) :-
  binpkgtest:patches_setup(ConfState),
  assertz(cache:ordered_entry(testrepo, 'app-misc/foo-1.0',
                              'app-misc', foo, '1.0'), CacheRef).


%! binpkgtest:patches_entry_cleanup(+State) is det.

binpkgtest:patches_entry_cleanup(entry(ConfState, CacheRef)) :-
  erase(CacheRef),
  binpkgtest:patches_cleanup(ConfState).


%! binpkgtest:write_patch(+ConfDir, +Cat, +Leaf, +File) is det.

binpkgtest:write_patch(ConfDir, Cat, Leaf, File) :-
  os:compose_path([ConfDir, patches, Cat, Leaf], Dir),
  make_directory_path(Dir),
  os:compose_path([Dir, File], Path),
  setup_call_cleanup(
    open(Path, write, Out),
    write(Out, '--- a\n+++ b\n'),
    close(Out)).


%! binpkgtest:gpg_available is semidet.

binpkgtest:gpg_available :-
  absolute_file_name(path(gpg), _, [access(execute), file_errors(fail)]).


%! binpkgtest:gpkg_inner_fixture(+Mode, -State) is det.

binpkgtest:gpkg_inner_fixture(Mode, state(Root, Inner, Home)) :-
  binpkgtest:mktemp_dir(Root),
  os:compose_path(Root, inner, Inner),
  make_directory(Inner),
  binpkgtest:write_bytes(Inner, 'gpkg-1', "gpkg-1\n"),
  binpkgtest:write_bytes(Inner, 'image.tar.zst', "image payload\n"),
  binpkgtest:write_bytes(Inner, 'metadata.tar.zst', "metadata payload\n"),
  ( Mode == signed
  -> os:compose_path(Root, gnupg, Home),
     make_directory(Home),
     filesex:chmod(Home, 0o700),
     binpkgtest:gpg_generate_key(Home),
     binpkgtest:gpg_sign_member(Home, Inner, 'image.tar.zst'),
     binpkgtest:gpg_sign_member(Home, Inner, 'metadata.tar.zst')
  ;  Home = ''
  ),
  binpkgtest:write_inner_manifest(Root, Inner, PlainManifest),
  ( Mode == signed
  -> os:compose_path(Inner, 'Manifest', Manifest),
     binpkgtest:run_gpg(
       ['--homedir', Home, '--batch', '--yes', '--armor',
        '--output', Manifest, '--clearsign', PlainManifest])
  ;  os:compose_path(Inner, 'Manifest', Manifest),
     copy_file(PlainManifest, Manifest)
  ).


%! binpkgtest:gpkg_inner_cleanup(+State) is det.

binpkgtest:gpkg_inner_cleanup(state(Root, _, _)) :-
  binpkgtest:rm_rf(Root).


%! binpkgtest:write_bytes(+Dir, +Name, +Contents) is det.

binpkgtest:write_bytes(Dir, Name, Contents) :-
  os:compose_path(Dir, Name, Path),
  setup_call_cleanup(
    open(Path, write, Out, [type(binary)]),
    format(Out, '~s', [Contents]),
    close(Out)).


%! binpkgtest:write_inner_manifest(+Root, +Inner, -Path) is det.

binpkgtest:write_inner_manifest(Root, Inner, Path) :-
  directory_files(Inner, Names0),
  exclude(binpkgtest:dot_name, Names0, Names),
  os:compose_path(Root, 'Manifest.plain', Path),
  setup_call_cleanup(
    open(Path, write, Out, [encoding(utf8)]),
    forall(member(Name, Names),
      ( os:compose_path(Inner, Name, File),
        size_file(File, Size),
        mirror:openssl_file_hash(File, '-blake2b512', Blake),
        mirror:openssl_file_hash(File, '-sha512', Sha),
        format(Out, 'DATA ~w ~d BLAKE2B ~w SHA512 ~w~n',
               [Name, Size, Blake, Sha])
      )),
    close(Out)).


binpkgtest:dot_name('.').
binpkgtest:dot_name('..').


%! binpkgtest:gpg_generate_key(+Home) is det.

binpkgtest:gpg_generate_key(Home) :-
  binpkgtest:run_gpg(
    ['--homedir', Home, '--batch', '--passphrase', '',
     '--quick-gen-key', 'portage-ng unit test <unit@example.invalid>',
     'default', 'default', 'never']).


%! binpkgtest:gpg_sign_member(+Home, +Inner, +Name) is det.

binpkgtest:gpg_sign_member(Home, Inner, Name) :-
  os:compose_path(Inner, Name, Path),
  atom_concat(Path, '.sig', Signature),
  binpkgtest:run_gpg(
    ['--homedir', Home, '--batch', '--yes', '--armor',
     '--output', Signature, '--detach-sign', Path]).


%! binpkgtest:run_gpg(+Args) is det.

binpkgtest:run_gpg(Args) :-
  process_create(path(gpg), Args,
                 [stdin(null), stdout(null), stderr(null), process(Pid)]),
  process_wait(Pid, exit(0)).


% -----------------------------------------------------------------------------
%  Full coverage for binpkg_index.pl, binpkg_extract.pl, and binpkg_exec.pl
% -----------------------------------------------------------------------------

:- dynamic binpkg:get_location/1.
:- dynamic binpkg:get_cache/1.
:- dynamic binpkg:sync/1.
:- dynamic pkg:get_location/1.
:- dynamic bsrc_repo:get_ebuild_file/2.

:- begin_tests(binpkg_full_coverage).

test(binpkg_index_full_coverage, [nondet]) :-
  binpkgtest:mktemp_dir(Dir),
  setup_call_cleanup(
    true,
    ( os:compose_path(Dir, 'Packages', PkgFile),
      IndexContent =
        "ARCH: amd64\nVERSION: 2\n\n\nCPV: app-misc/jq-1.8.1\nBUILD_ID: 9\nPATH: app-misc/jq/jq-1.8.1-9.gpkg.tar\nUSE: oniguruma\nbad line without separator\n\nCPV: app-misc/legacy-1.0\nPATH: app-misc/legacy/legacy-1.0-3.xpak\n",
      setup_call_cleanup(
        open(PkgFile, write, Out, [encoding(utf8)]),
        write(Out, IndexContent),
        close(Out)),
      binpkg_index:parse_file(PkgFile, _Header, Records),
      binpkg_index:record_count(PkgFile, 2),
      binpkg_index:project_records(Records, Rows, ['app-misc'], ['app-misc'-jq, 'app-misc'-legacy]),
      length(Rows, 2),
      % Also test parse_stream on open stream & empty file
      setup_call_cleanup(
        open_string(IndexContent, S1),
        binpkg_index:parse_stream(S1, _, [_, _]),
        close(S1)),
      setup_call_cleanup(
        open_string("", S2),
        binpkg_index:parse_stream(S2, [], []),
        close(S2)),
      binpkg_index:parse_file('/no/such/Packages', [], []),
      \+ binpkg_index:trailing_dash_int(nodash, _)
    ),
    binpkgtest:rm_rf(Dir)).

test(binpkg_extract_full_coverage, [nondet]) :-
  binpkgtest:mktemp_dir(Root),
  setup_call_cleanup(
    true,
    ( % 1. Pure helpers in binpkg_extract
      forall(member(Ch-Tp, [
        "-"-file, "d"-dir, "l"-symlink, "h"-hardlink,
        "b"-device, "c"-device, "p"-fifo, "s"-socket,
        "g"-skip, "x"-skip, "?"-other
      ]), binpkg_extract:type_char(Ch, Tp)),
      forall(member(K-FT, [
        image-device, image-fifo, image-socket, image-other,
        outer-symlink, outer-hardlink, metadata-symlink, metadata-hardlink
      ]), binpkg_extract:forbidden_type(K, FT)),
      binpkg_extract:members_safe(image, [member(skip, 'pax_global_header', ''),
                                          member(dir, 'image/.', ''),
                                          member(symlink, 'image/sub/l', 'a'),
                                          member(file, 'image/sub/l/f', '')]),
      binpkg_extract:skip_component(""),
      binpkg_extract:join_target(["image", "sub"], '../a', ["image", "a"]),
      binpkg_extract:strip_build_id_suffix('jq-1.8.1-9', 'jq-1.8.1'),
      binpkg_extract:strip_build_id_suffix('nodash', 'nodash'),
      % 2. Build a complete valid gpkg.tar with image.tar.zst + metadata.tar.zst + environment.bz2
      InnerName = 'jq-1.8.1-9',
      os:compose_path([Root, 'stage', InnerName], StageInner),
      make_directory_path(StageInner),
      % Create image/etc/env.d/99jq inside image staging
      os:compose_path([Root, 'img_stage', 'image', 'etc', 'env.d'], ImgEnvDir),
      make_directory_path(ImgEnvDir),
      os:compose_path(ImgEnvDir, '99jq', ImgEnvFile),
      setup_call_cleanup(open(ImgEnvFile, write, SE), writeln(SE, 'FOO=1'), close(SE)),
      os:compose_path(StageInner, 'image.tar.zst', ImageTarZst),
      os:compose_path(Root, 'img_stage', ImgStageRoot),
      binpkg_extract:run_command(path(tar), ['--zstd', '-cf', ImageTarZst, '-C', ImgStageRoot, 'image'], 0),
      % Create metadata/environment.bz2 inside metadata staging
      os:compose_path([Root, 'meta_stage', 'metadata'], MetaStageDir),
      make_directory_path(MetaStageDir),
      os:compose_path(MetaStageDir, 'environment', RawEnv),
      setup_call_cleanup(
        open(RawEnv, write, SRE),
        format(SRE, 'export MERGE_TYPE="source"~nexport EMERGE_FROM="ebuild"~nKEEP_VAR="1"~n', []),
        close(SRE)),
      binpkg_extract:run_command(path(bzip2), ['-f', RawEnv], 0),
      os:compose_path(StageInner, 'metadata.tar.zst', MetaTarZst),
      os:compose_path(Root, 'meta_stage', MetaStageRoot),
      binpkg_extract:run_command(path(tar), ['--zstd', '-cf', MetaTarZst, '-C', MetaStageRoot, 'metadata'], 0),
      binpkgtest:write_bytes(StageInner, 'gpkg-1', "gpkg-1\n"),
      binpkgtest:write_inner_manifest(Root, StageInner, PlainMan),
      os:compose_path(StageInner, 'Manifest', InnerManifest),
      copy_file(PlainMan, InnerManifest),
      os:compose_path(Root, 'jq-1.8.1-9.gpkg.tar', GpkgPath),
      os:compose_path(Root, 'stage', StageRoot),
      binpkg_extract:run_command(path(tar), ['-cf', GpkgPath, '-C', StageRoot, InnerName], 0),
      size_file(GpkgPath, GpkgSize),
      mirror:openssl_file_hash(GpkgPath, '-md5', GpkgMd5),
      mirror:openssl_file_hash(GpkgPath, '-sha1', GpkgSha1),
      Hashes = [alg_hash(md5, GpkgMd5), alg_hash(sha1, GpkgSha1)],
      os:compose_path(Root, 'builddir', BuildDir),
      make_directory_path(BuildDir),
      binpkg_extract:prepare_builddir(GpkgPath, InnerName, BuildDir, GpkgSize, Hashes, StagedGpkg),
      exists_file(StagedGpkg),
      % Also exercise rewrite_binary_merge_markers when EnvFile is absent
      os:compose_path(Root, 'fresh_env', FreshEnv),
      binpkg_extract:rewrite_binary_merge_markers(FreshEnv),
      exists_file(FreshEnv)
    ),
    binpkgtest:rm_rf(Root)).

test(binpkg_exec_full_coverage, [nondet]) :-
  binpkgtest:mktemp_dir(Root),
  os:compose_path([Root, 'app-misc', 'jq'], PkgSubDir),
  make_directory_path(PkgSubDir),
  os:compose_path(PkgSubDir, 'jq-1.8.1-9.gpkg.tar', GpkgPath),
  setup_call_cleanup(open(GpkgPath, write, SG), write(SG, 'dummy'), close(SG)),
  size_file(GpkgPath, GpkgSize),
  mirror:openssl_file_hash(GpkgPath, '-md5', GpkgMd5),
  mirror:openssl_file_hash(GpkgPath, '-sha1', GpkgSha1),
  os:compose_path(Root, 'Packages', IndexFile),
  setup_call_cleanup(open(IndexFile, write, SI), writeln(SI, 'ARCH: amd64'), close(SI)),
  os:compose_path(Root, 'jq-1.8.1.ebuild', EbuildPath),
  setup_call_cleanup(open(EbuildPath, write, SEB), writeln(SEB, '# ebuild'), close(SEB)),
  os:compose_path([Root, 'vdb', 'dev-libs', 'onig-1.0'], VdbEntryDir),
  make_directory_path(VdbEntryDir),
  os:compose_path(VdbEntryDir, 'SLOT', VdbSlotFile),
  setup_call_cleanup(open(VdbSlotFile, write, SVS), writeln(SVS, '0/5'), close(SVS)),
  V1 = version([1,8,1], '', 4, 0, [], 0, '1.8.1'),
  setup_call_cleanup(
    ( asserta(binpkg:get_location(Root)),
      asserta(binpkg:get_cache(IndexFile)),
      asserta((binpkg:sync(kb) :- !)),
      asserta(pkg:get_location(Root)),
      asserta(bsrc_repo:get_ebuild_file('app-misc/jq-1.8.1', EbuildPath)),
      asserta(config:build_root(Root)),
      asserta(config:ebuild_command(true)),
      assertz(cache:repository(binpkg)),
      assertz(cache:ordered_entry(bsrc_repo, 'app-misc/jq-1.8.1', 'app-misc', jq, V1)),
      assertz(cache:entry_metadata(bsrc_repo, 'app-misc/jq-1.8.1', slot, slot('0'))),
      assertz(cache:entry_metadata(bsrc_repo, 'app-misc/jq-1.8.1', slot, subslot('1'))),
      assertz(cache:entry_metadata(bsrc_repo, 'app-misc/jq-1.8.1', iuse, plus(onig))),
      assertz(cache:entry_metadata(bsrc_repo, 'app-misc/jq-1.8.1', iuse, minus(doc))),
      assertz(cache:ordered_entry(binpkg, 'app-misc/jq-1.8.1-9', 'app-misc', jq, V1)),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', build_id, 9)),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', path, 'app-misc/jq/jq-1.8.1-9.gpkg.tar')),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', slot, '0/1')),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', keywords, 'amd64 ~x86')),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', use, 'onig')),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', size, GpkgSize)),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', md5, GpkgMd5)),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', sha1, GpkgSha1)),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', required_use, 'onig !doc')),
      assertz(cache:entry_metadata(binpkg, 'app-misc/jq-1.8.1-9', depend,
        'dev-libs/onig:0/5= ( dev-libs/a ) || ( dev-libs/b ) onig? ( dev-libs/c ) !onig? ( dev-libs/d ) ^^ ( dev-libs/e ) ?? ( dev-libs/f )')),
      assertz(cache:ordered_entry(pkg, 'dev-libs/onig-1.0', 'dev-libs', onig, V1)),
      assertz(cache:entry_metadata(pkg, 'dev-libs/onig-1.0', slot, slot('0'))),
      assertz(cache:entry_metadata(pkg, 'dev-libs/onig-1.0', slot, subslot('5'))),
      assertz(cache:entry_metadata(pkg, 'dev-libs/onig-1.0', installed, true))
    ),
    with_output_to(string(_),
      ( % Policy helpers
        binpkg_exec:consumption_enabled,
        preference:with_local_flag(usepkgonly, binpkg_exec:binary_only),
        binpkg_exec:respect_use_policy(strict),
        binpkg_exec:changed_deps_policy(warn),
        binpkg_exec:respect_user_patches_policy(respect),
        binpkg_exec:src_slot(bsrc_repo, 'app-misc/jq-1.8.1', '0'),
        binpkg_exec:src_slot(bsrc_repo, 'app-misc/unknown', '0'),
        binpkg_exec:version_pvr(V1, '1.8.1', '1.8.1', 0),
        binpkg_exec:version_pvr(version_none, none, none, 0),
        binpkg_exec:version_pvr('1.8.1-r2', '1.8.1', '1.8.1-r2', 2),
        binpkg_exec:use_sets_match(strict, [a], [a]),
        binpkg_exec:use_sets_match(relaxed, [a, b], [a]),
        binpkg_exec:iuse_flag_name(minus(doc), doc),
        binpkg_exec:iuse_flag_name(bare_flag, bare_flag),
        binpkg_exec:flag_set_member(minus(doc), doc),
        binpkg_exec:binpkg_required_use('app-misc/jq-1.8.1-9', _),
        binpkg_exec:required_use_holds([
          blocking(doc),
          use_conditional_group(negative, doc, _://_, [required(onig)]),
          any_of_group([required(onig)]),
          all_of_group([required(onig)])
        ], [onig]),
        % Subslot walk & VDB disk/cache lookup BEFORE inject_built_binpkg overwrites metadata
        os:compose_path(Root, 'vdb', VdbDiskRoot),
        retractall(pkg:get_location(_)),
        asserta(pkg:get_location(VdbDiskRoot)),
        binpkg_exec:available_for(bsrc_repo, 'app-misc/jq-1.8.1', [], 'app-misc/jq-1.8.1-9'),
        retractall(pkg:get_location(_)),
        binpkg_exec:live_install_subslot('dev-libs', onig, '0', '5'),
        binpkg_exec:find_live_install_for_slot('dev-libs', onig, (-), _),
        binpkg_exec:find_live_install_for_slot('dev-libs', onig, '0', _),
        binpkg_exec:walk_dep_subslot(other_term, []),
        % Index refresh & baseline
        binpkg_exec:record_index_baseline(binpkg, none),
        binpkg_exec:record_index_baseline(binpkg, 1.0),
        binpkg_exec:apply_refresh_policy(manual),
        binpkg_exec:apply_refresh_policy(mtime),
        binpkg_exec:apply_refresh_policy(other),
        binpkg_exec:ensure_index_fresh,
        binpkg_exec:refresh_if_stale(nonexistent_repo),
        % Self-inject
        binpkg_exec:inject_built_binpkg(bsrc_repo, 'app-misc/jq-1.8.1', []),
        % Rejection diagnostics
        asserta(config:binpkg_debug(true)),
        binpkg_exec:maybe_diagnose_rejection(bsrc_repo, 'app-misc/none-1.0', [], 'app-misc', none, V1),
        binpkg_exec:diagnose_candidate(bsrc_repo, 'app-misc/jq-1.8.1', 'app-misc/jq-1.8.1-9', []),
        binpkg_exec:diagnose_candidate(bsrc_repo, 'app-misc/jq-1.8.1', 'app-misc/missing-1.0-1', []),
        retractall(config:binpkg_debug(true)),
        % Execution & qmerge
        binpkg_exec:execute(install, bsrc_repo, 'app-misc/jq-1.8.1', 'app-misc/jq-1.8.1-9', [], _),
        binpkg_exec:run_qmerge('app-misc/jq-1.8.1-9', EbuildPath, GpkgPath, Root, 'onig', 0),
        retractall(config:deconflict_collisions(_)),
        asserta(config:deconflict_collisions(off)),
        binpkg_exec:run_qmerge('app-misc/jq-1.8.1-9', EbuildPath, GpkgPath, Root, 'onig', 0),
        retractall(config:deconflict_collisions(_)),
        assertz(config:deconflict_collisions(override)),
        binpkg_exec:log_qmerge_collision_retry('app-misc/jq-1.8.1-9', 1)
      )),
    ( retractall(binpkg:get_location(_)),
      retractall(binpkg:get_cache(_)),
      retractall(binpkg:sync(_)),
      retractall(pkg:get_location(_)),
      retractall(bsrc_repo:get_ebuild_file(_, _)),
      retractall(config:build_root(Root)),
      retractall(config:ebuild_command(true)),
      retractall(cache:repository(binpkg)),
      retractall(cache:category(binpkg, _)),
      retractall(cache:package(binpkg, _, _)),
      retractall(cache:ordered_entry(bsrc_repo, _, _, _, _)),
      retractall(cache:entry_metadata(bsrc_repo, _, _, _)),
      retractall(cache:ordered_entry(binpkg, _, _, _, _)),
      retractall(cache:entry_metadata(binpkg, _, _, _)),
      retractall(cache:ordered_entry(pkg, 'dev-libs/onig-1.0', _, _, _)),
      retractall(cache:entry_metadata(pkg, 'dev-libs/onig-1.0', _, _)),
      binpkgtest:rm_rf(Root)
    )).

:- end_tests(binpkg_full_coverage).

