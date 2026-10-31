/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PROFILETEST
Unit tests for profile parent chains (Source/Domain/Gentoo/Preference/profile.pl).

`repo:path` parents, including a profile directory that sits outside
any repository.
*/

:- module(profiletest, []).

:- use_module(library(plunit)).
:- use_module(library(filesex)).

% =============================================================================
%  PROFILETEST declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Profile parent chains
% -----------------------------------------------------------------------------

:- begin_tests(profile_parents).

test(repo_parent_outside_a_repo) :-
  profiletest:with_tree(profiletest:outside_repo).

test(colon_parent_inside_portage2) :-
  profiletest:with_tree(profiletest:inside_portage2).

test(colon_parent_inside_portage1_stays_relative) :-
  profiletest:with_tree(profiletest:inside_portage1).

test(relative_parent) :-
  profiletest:with_tree(profiletest:relative_parent).

:- end_tests(profile_parents).


%! profiletest:with_tree(:Goal) is det
%
% Create a temporary directory, call Goal with its path, then remove it.

profiletest:with_tree(Goal) :-
  gensym(png_profile, Id),
  format(atom(Root), '/tmp/~w', [Id]),
  make_directory(Root),
  setup_call_cleanup(true, call(Goal, Root),
                     delete_directory_and_contents(Root)).


%! profiletest:outside_repo(+Root) is det
%
% A make.profile directory outside the repository accepts `gentoo:base`
% and skips an unknown repository and a `:path` line.

profiletest:outside_repo(Root) :-
  profiletest:repo_tree(Root, Repo),
  os:compose_path(Root, 'make.profile', Profile),
  os:compose_path(Profile, parent, ParentFile),
  profiletest:write_file(ParentFile, 'gentoo:base\nother:base\n:base\n'),
  profiletest:chain([gentoo-Repo], Profile, Dirs),
  profiletest:canon(Repo, 'profiles/base', Base),
  profiletest:canon(Profile, ProfileCanon),
  Dirs == [Base, ProfileCanon].


%! profiletest:inside_portage2(+Root) is det
%
% Inside a portage-2 repository, `:base` names that repository's profile.

profiletest:inside_portage2(Root) :-
  profiletest:repo_tree(Root, Repo),
  profiletest:write_file_at(Repo, 'metadata/layout.conf',
                            'profile-formats = portage-2\n'),
  os:compose_path(Repo, 'profiles/child', Child),
  os:compose_path(Child, parent, ParentFile),
  profiletest:write_file(ParentFile, ':base\n'),
  profiletest:chain([gentoo-Repo], Child, Dirs),
  profiletest:canon(Repo, 'profiles/base', Base),
  profiletest:canon(Child, ChildCanon),
  Dirs == [Base, ChildCanon].


%! profiletest:inside_portage1(+Root) is semidet
%
% Without `portage-2`, a colon parent stays a relative path and the
% missing directory is reported by absolute_file_name/3.

profiletest:inside_portage1(Root) :-
  profiletest:repo_tree(Root, Repo),
  profiletest:write_file_at(Repo, 'metadata/layout.conf',
                            'profile-formats = portage-1\n'),
  os:compose_path(Repo, 'profiles/child', Child),
  os:compose_path(Child, parent, ParentFile),
  profiletest:write_file(ParentFile, 'gentoo:base\n'),
  ( catch(profile:profile_dirs_from_dir([gentoo-Repo], Child, [], _),
          error(existence_error(_, _), _),
          fail) ->
      fail
  ; true
  ).


%! profiletest:relative_parent(+Root) is det
%
% A relative parent entry is unchanged by colon handling.

profiletest:relative_parent(Root) :-
  profiletest:repo_tree(Root, Repo),
  os:compose_path(Repo, 'profiles/child', Child),
  os:compose_path(Child, parent, ParentFile),
  profiletest:write_file(ParentFile, '../base\n'),
  profiletest:chain([gentoo-Repo], Child, Dirs),
  profiletest:canon(Repo, 'profiles/base', Base),
  profiletest:canon(Child, ChildCanon),
  Dirs == [Base, ChildCanon].


%! profiletest:repo_tree(+Root, -Repo) is det
%
% A repository named gentoo with an empty profiles/base directory.

profiletest:repo_tree(Root, RepoCanon) :-
  os:compose_path(Root, repo, Repo),
  profiletest:write_file_at(Repo, 'profiles/repo_name', 'gentoo\n'),
  os:compose_path(Repo, 'profiles/base', Base),
  make_directory_path(Base),
  absolute_file_name(Repo, RepoCanon, [file_type(directory), access(read)]).


%! profiletest:chain(+Repos, +Dir, -Dirs) is det
%
% Root-first profile chain of Dir under the supplied repository catalog.

profiletest:chain(Repos, Dir, Dirs) :-
  profile:profile_dirs_from_dir(Repos, Dir, [], Rev),
  reverse(Rev, Dirs).


%! profiletest:canon(+Root, +Rel, -Canon) is det
%
% Canonical directory Root/Rel.

profiletest:canon(Root, Rel, Canon) :-
  os:compose_path(Root, Rel, Path),
  absolute_file_name(Path, Canon, [file_type(directory), access(read)]).


profiletest:canon(Path, Canon) :-
  absolute_file_name(Path, Canon, [file_type(directory), access(read)]).


%! profiletest:write_file_at(+Root, +Rel, +Text) is det
%
% Write Text to Root/Rel, creating parent directories.

profiletest:write_file_at(Root, Rel, Text) :-
  os:compose_path(Root, Rel, Path),
  profiletest:write_file(Path, Text).


%! profiletest:write_file(+Path, +Text) is det
%
% Write Text to Path, creating parent directories.

profiletest:write_file(Path, Text) :-
  file_directory_name(Path, Dir),
  make_directory_path(Dir),
  open(Path, write, Out, [encoding(utf8)]),
  write(Out, Text),
  close(Out).


% -----------------------------------------------------------------------------
%  Full coverage of fallback.pl, userconfig.pl, sets.pl, variant.pl, profile.pl
% -----------------------------------------------------------------------------

:- begin_tests(preference_and_variant_full_coverage).

test(fallback_and_userconfig_coverage, [nondet]) :-
  % 1. fallback.pl
  forall(fallback:env(_, _), true),
  forall(fallback:package_mask(_), true),
  forall(fallback:package_use(_, _), true),
  % 2. userconfig.pl
  profiletest:with_tree(
    [Root]>>(
      profiletest:write_file_at(Root, 'make.conf',
        'USE="foo -bar"\nUSE+="baz"\nARCH="amd64"\n'),
      profiletest:write_file_at(Root, 'package.use/00-test',
        'cat/pkg flag1 -flag2\n'),
      profiletest:write_file_at(Root, 'package.mask',
        '=cat/masked-1.0\n'),
      profiletest:write_file_at(Root, 'package.unmask',
        '=cat/unmasked-1.0\n'),
      profiletest:write_file_at(Root, 'package.accept_keywords/00-kw',
        'cat/kwpkg ~amd64\ncat/barepkg\n'),
      profiletest:write_file_at(Root, 'package.license',
        'cat/licpkg MIT GPL-2\n'),
      setup_call_cleanup(
        asserta(config:portage_confdir(Root)),
        ( userconfig:load,
          userconfig:env('USE', _),
          userconfig:package_keyword('cat/kwpkg', '~amd64'),
          userconfig:package_keyword('cat/barepkg', _),
          userconfig:package_license_entry('cat/licpkg', 'MIT')
        ),
        ( retractall(config:portage_confdir(Root)),
          retractall(userconfig:env(_, _)),
          retractall(userconfig:package_keyword(_, _)),
          retractall(userconfig:package_license_entry(_, _))
        ))
    )).

test(variant_module_full_coverage, [nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  DepA = package_dependency(install, no, vcat, alt_a, none, version_none, [], []),
  DepB = package_dependency(install, no, vcat, alt_b, none, version_none, [], []),
  GatedTree = all_of_group([
                any_of_group([
                  exactly_one_of_group([
                    at_most_one_of_group([
                      use_conditional_group(positive, outer_f, qtest://'vcat/vpkg-1.0', [
                        use_conditional_group(positive, vflag_pos, qtest://'vcat/vpkg-1.0',
                          [all_of_group([any_of_group([use_conditional_group(positive, x, qtest://'vcat/vpkg-1.0',
                             [exactly_one_of_group([at_most_one_of_group([DepA])])])])])]),
                        use_conditional_group(negative, vflag_neg, qtest://'vcat/vpkg-1.0', [DepB]),
                        any_of_group([DepA, DepA, DepB]),
                        exactly_one_of_group([DepA, DepB])
                      ])
                    ])
                  ])
                ])
              ]),
  setup_call_cleanup(
    ( assertz(cache:ordered_entry(Vdb, 'vcat/vpkg-1.0', vcat, vpkg, V1)),
      assertz(cache:ordered_entry(portage, 'vcat/vpkg-1.0', vcat, vpkg, V1)),
      assertz(cache:ordered_entry(qtest, 'vcat/vpkg-1.0', vcat, vpkg, V1)),
      assertz(cache:ordered_entry(qtest, 'vcat/vpkg-2.0', vcat, vpkg, V2)),
      assertz(cache:ordered_entry(qtest, 'vcat/alt_a-1.0', vcat, alt_a, V1)),
      assertz(cache:ordered_entry(qtest, 'vcat/alt_b-1.0', vcat, alt_b, V1)),
      assertz(cache:entry_metadata(qtest, 'vcat/vpkg-1.0', iuse, plus(vflag_pos))),
      assertz(cache:entry_metadata(qtest, 'vcat/vpkg-1.0', iuse, vflag_neg)),
      assertz(cache:entry_metadata(qtest, 'vcat/vpkg-1.0', iuse, kernel_linux)),
      assertz(cache:entry_metadata(qtest, 'vcat/vpkg-1.0', depend, GatedTree)),
      memo:clear_caches
    ),
    ( variant:ensure_tree_entry(Vdb://'vcat/vpkg-1.0', portage://'vcat/vpkg-1.0'),
      variant:ensure_tree_entry(qtest://'vcat/vpkg-1.0', qtest://'vcat/vpkg-1.0'),
      Q = qualified_target(none, qtest, vcat, vpkg, version_none, [[], []]),
      ( catch(variant:goal_to_entry(target(Q, 'vcat/vpkg'):run?{[]}, _), _, fail) -> true ; true ),
      variant:detect_pivots(t, [qtest://'vcat/vpkg-1.0':run?{[]}], 1, UsePivots1, BranchPivots1),
      length(UsePivots1, 1),
      length(BranchPivots1, 1),
      variant:detect_pivots(t, [qtest://'vcat/vpkg-1.0':run?{[]}], 10, UsePivots, BranchPivots),
      variant:pivots_to_specs(UsePivots, BranchPivots, Specs),
      Specs \== [],
      variant:branch_label(other_group, raw_chosen, raw_alt, _),
      variant:user_flags_to_specs([vflag_pos, vflag_neg], [qtest://'vcat/vpkg-1.0':run?{[]}], t, UserSpecs),
      forall(member(Sp, UserSpecs),
             ( variant:apply(Sp), variant:cleanup )),
      forall(member(BSp, Specs),
             ( variant:apply(BSp), variant:cleanup )),
      PlanBase = [[rule(qtest://'vcat/vpkg-1.0':install?{[]}, []),
                   assumed(rule(qtest://'vcat/alt_a-1.0':install?{[]}, []))] ],
      PlanVar  = [[rule(qtest://'vcat/vpkg-2.0':install?{[]}, []),
                   rule(assumed(qtest://'vcat/alt_b-1.0':install?{[]}), [])] ],
      variant:plan_entries(PlanBase, BaseEntries),
      variant:plan_entries(PlanVar, VarEntries),
      variant:plan_diff(BaseEntries, VarEntries, diff([_], [_], [_]))
    ),
    ( variant:cleanup,
      retractall(cache:ordered_entry(Vdb, 'vcat/vpkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(portage, 'vcat/vpkg-1.0', _, _, _)),
      retractall(cache:ordered_entry(qtest, _, vcat, _, _)),
      retractall(cache:entry_metadata(qtest, 'vcat/vpkg-1.0', _, _)),
      memo:clear_caches
    )).

test(sets_module_full_coverage, [nondet]) :-
  V1 = version([1,0], '', 4, 0, [], 0, '1.0'),
  V2 = version([2,0], '', 4, 0, [], 0, '2.0'),
  knowledgebase:vdb_repository(Vdb),
  profiletest:with_tree(
    [Root]>>(
      os:compose_path([Root, 'scat/spkg-2.0'], VdbEntryDir),
      make_directory_path(VdbEntryDir),
      profiletest:write_file_at(VdbEntryDir, 'PROPERTIES', 'live interactive'),
      profiletest:write_file_at(VdbEntryDir, 'BUILD_TIME', '1000'),
      profiletest:write_file_at(VdbEntryDir, 'RDEPEND',
        ' u1? ( !u2? ( ( || ( ^^ ( ?? ( scat/other:0= ) ) ) ) sys-libs/glibc ) )'),
      profiletest:write_file_at(VdbEntryDir, 'CONTENTS',
        'obj /usr/lib64/libpreserved.so.1.2 abc 123\n'),
      os:compose_path(Root, 'preserved_libs_registry', RegFile),
      profiletest:write_file(RegFile,
        '{"scat/owner-1.0": ["scat/owner-1.0", "1", ["/usr/lib64/libpreserved.so.1.2"]], "alt": ["/usr/lib64/libalt.so.1"], "bad": 123}'),
      setup_call_cleanup(
        ( asserta(config:pkg_directory(Root)),
          asserta(config:preserved_libs_registry_override(RegFile)),
          assertz(cache:repository(binpkg)),
          assertz(cache:ordered_entry(binpkg, 'scat/spkg-2.0', scat, spkg, V2)),
          assertz(cache:entry_metadata(binpkg, 'scat/spkg-2.0', build_time, '2000')),
          assertz(cache:ordered_entry(Vdb, 'scat/spkg-2.0', scat, spkg, V2)),
          assertz(cache:entry_metadata(Vdb, 'scat/spkg-2.0', slot, slot('0'))),
          assertz(cache:entry_metadata(Vdb, 'scat/spkg-2.0', slot, subslot('1'))),
          assertz(cache:entry_metadata(Vdb, 'scat/spkg-2.0', use, u1)),
          assertz(cache:entry_metadata(Vdb, 'scat/spkg-2.0', needed_elf2,
                                       'X86_64;/usr/bin/spkg;;;/usr/lib64,libalt.so.1;x86_64')),
          assertz(cache:ordered_entry(Vdb, 'scat/livecached-1.0', scat, livecached, V1)),
          assertz(cache:entry_metadata(Vdb, 'scat/livecached-1.0', properties, live)),
          assertz(cache:entry_metadata(Vdb, 'scat/livecached-1.0', needed_elf2, 'malformed')),
          assertz(cache:ordered_entry(qtest, 'scat/spkg-1.0', scat, spkg, V1)),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-1.0', slot, slot('0'))),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-1.0', slot, subslot('2'))),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-1.0', keywords, stable(amd64))),
          assertz(cache:ordered_entry(qtest, 'scat/spkg-2.0', scat, spkg, V2)),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-2.0', slot, slot('0'))),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-2.0', slot, subslot('2'))),
          assertz(cache:entry_metadata(qtest, 'scat/spkg-2.0', keywords, stable(amd64)))
        ),
        ( forall(sets:is_computed_set(SetName),
                 sets:expand(SetName, _)),
          sets:expand(unknown_set_xyz, []),
          sets:same_build_time(100, '100'),
          sets:same_build_time(abc, abc),
          forall(sets:libc_package(_, _), true),
          sets:entry_has_rebuilt_binary(Vdb://'scat/spkg-2.0'),
          sets:entry_deps_outdated(Vdb://'scat/spkg-2.0'),
          sets:entry_slot_changed(Vdb://'scat/spkg-2.0'),
          sets:max_version_pair([V1-a, V2-b, V1-c], V2-b),
          sets:canonicalize_dep(other_dep_term, other_dep_term)
        ),
        ( retractall(config:pkg_directory(Root)),
          retractall(config:preserved_libs_registry_override(RegFile)),
          retractall(cache:repository(binpkg)),
          retractall(cache:ordered_entry(binpkg, 'scat/spkg-2.0', _, _, _)),
          retractall(cache:entry_metadata(binpkg, 'scat/spkg-2.0', _, _)),
          retractall(cache:ordered_entry(Vdb, _, scat, _, _)),
          retractall(cache:entry_metadata(Vdb, 'scat/spkg-2.0', _, _)),
          retractall(cache:entry_metadata(Vdb, 'scat/livecached-1.0', _, _)),
          retractall(cache:ordered_entry(qtest, _, scat, _, _)),
          retractall(cache:entry_metadata(qtest, 'scat/spkg-1.0', _, _)),
          retractall(cache:entry_metadata(qtest, 'scat/spkg-2.0', _, _))
        ))
    )).

test(profile_module_full_coverage, [nondet]) :-
  profiletest:with_tree(
    [Root]>>(
      profiletest:repo_tree(Root, Repo),
      profiletest:write_file_at(Repo, 'metadata/layout.conf',
                                'profile-formats = portage-2\n'),
      profiletest:write_file_at(Repo, 'profiles/package.mask', 'cat/global_masked\n'),
      profiletest:write_file_at(Repo, 'profiles/package.unmask', 'cat/global_unmasked\n'),
      profiletest:write_file_at(Repo, 'profiles/license_groups', 'FREE GPL-2 MIT\n'),
      profiletest:write_file_at(Repo, 'profiles/use.desc',
                                '# comment\nflag_d - Desc for flag_d\n'),
      % Base profile (EAPI 9)
      profiletest:write_file_at(Repo, 'profiles/base/eapi', '9\n'),
      profiletest:write_file_at(Repo, 'profiles/base/make.defaults',
        'export USE="base_on -base_off"\nUSE_EXPAND="CPU_FLAGS_X86 -OLD_EXP"\nCPU_FLAGS_X86="sse -avx"\n'),
      profiletest:write_file_at(Repo, 'profiles/base/use.force', 'forced_f\n-unforced_f\n'),
      profiletest:write_file_at(Repo, 'profiles/base/use.mask', 'masked_f\n-unmasked_f\n'),
      profiletest:write_file_at(Repo, 'profiles/base/packages',
        '*>=sys-apps/baselayout-2.0:0\n*sys-apps/sed\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.mask', 'cat/prof_masked\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.unmask', 'cat/prof_unmasked\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use', 'cat/pkg u_on -u_off\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use.mask', 'cat/pkg pm_f\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use.force', 'cat/pkg pf_f\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use.stable', 'cat/pkg ps_on -ps_off\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use.stable.mask', 'cat/pkg psm_f\n'),
      profiletest:write_file_at(Repo, 'profiles/base/package.use.stable.force', 'cat/pkg psf_f\n'),
      % Child profile with implicit parent (no parent file inside base/sub)
      os:compose_path(Repo, 'profiles/base/sub', SubDir),
      make_directory_path(SubDir),
      profiletest:write_file_at(Repo, 'profiles/base/sub/package.use.mask', 'cat/pkg -pm_f\n'),
      os:compose_path(Root, 'Knowledge', KDir),
      make_directory_path(KDir),
      working_directory(OldCwd, Root),
      setup_call_cleanup(
        ( retractall(portage:get_location(_)),
          asserta(portage:get_location(Repo)),
          retractall(config:gentoo_profile(_)),
          asserta(config:gentoo_profile('base/sub')),
          profile:reset_cache
        ),
        with_output_to(string(_),
          ( profile:profile_use_terms('base/sub', _),
            profile:profile_use_mask('base/sub', _),
            profile:profile_use_force('base/sub', _),
            profile:profile_package_mask_atoms('base/sub', _),
            forall(member(PAtom, ['>=c/p-1.0', '<=c/p-1.0', '>c/p-1.0', '<c/p-1.0', '=c/p-1.0', '~c/p-1.0']),
                   profile:strip_version_prefix(PAtom, 'c/p-1.0')),
            profile:eapi_major('invalid', 0),
            profile:join_profile_path('/profiles', '', '/profiles'),
            profile:package_use_net_functor(other_basename, pkg_use_force),
            profile:load_use_descriptions,
            profile:use_description(flag_d, _),
            profile:cache_save,
            profile:cache_available,
            profile:cache_load(_, _, _),
            profile:apply_cached_profile_data,
            profile:apply_entry(package_use_mask, spec_m, pm_f),
            profile:apply_entry(use, s_m, stable_masked),
            profile:apply_entry(use, s_f, stable_forced),
            profile:apply_entry(use, minus(s_off), stable),
            profile:apply_entry(use, s_on, stable),
            profile:apply_entry(unknown_type, k, v),
            retractall(config:gentoo_profile(_)),
            profile:cache_save
          )),
        ( working_directory(_, OldCwd),
          profile:reset_cache,
          retractall(portage:get_location(Repo)),
          retractall(config:gentoo_profile(_)),
          assertz(config:gentoo_profile('default/linux/amd64/23.0/split-usr/no-multilib'))
        ))
    )).

:- end_tests(preference_and_variant_full_coverage).
