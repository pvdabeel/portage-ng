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
