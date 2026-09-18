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
%  Test fixtures
% -----------------------------------------------------------------------------

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
