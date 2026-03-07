/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GENTOO
Reads standard Gentoo /etc/portage configuration files.

This module makes portage-ng a drop-in replacement for Gentoo's Portage by
reading the same configuration files that Portage reads from /etc/portage/.
Each file is parsed and mapped into the existing preference system.

Supported files:
  - make.conf           → gentoo:env/2  (feeds preference:getenv/2)
  - package.use          → preference:gentoo_package_use_soft/3,
                           preference:package_use_override/4
  - package.mask         → preference:masked/1
  - package.unmask       → unmasks profile/user masks
  - package.accept_keywords → gentoo:package_keyword/2
  - package.license      → gentoo:package_license/2

All package.* files support both single-file and directory layouts (Portage
convention: if the path is a directory, all files in it are read in sorted
order).

The configuration directory defaults to config:portage_confdir/1 (typically
/etc/portage on a Gentoo system, or Source/Config/Config/Gentoo for development).
*/

:- module(gentoo, []).

:- use_module(library(filesex), [directory_file_path/3]).


% =============================================================================
%  Dynamic state
% =============================================================================

:- dynamic gentoo:env/2.
:- dynamic gentoo:package_keyword/2.
:- dynamic gentoo:package_license_entry/2.


% =============================================================================
%  Main entry point
% =============================================================================

%! gentoo:load is det.
%
% Load all /etc/portage configuration files from the directory specified
% by config:portage_confdir/1.  Silently succeeds when the directory does
% not exist or is not configured.

gentoo:load :-
  ( current_predicate(config:portage_confdir/1),
    config:portage_confdir(Dir),
    exists_directory(Dir) ->
      gentoo:load(Dir)
  ; true
  ).


%! gentoo:load(+Dir) is det.
%
% Load all supported configuration files from a given directory.

gentoo:load(Dir) :-
  gentoo:load_make_conf(Dir),
  gentoo:load_package_use(Dir),
  gentoo:load_package_mask(Dir),
  gentoo:load_package_unmask(Dir),
  gentoo:load_package_accept_keywords(Dir),
  gentoo:load_package_license(Dir).


% =============================================================================
%  make.conf
% =============================================================================

%! gentoo:load_make_conf(+Dir) is det.
%
% Parse make.conf and assert gentoo:env/2 facts.  Reuses the same
% key=value parser that profile.pl uses for make.defaults.

gentoo:load_make_conf(Dir) :-
  retractall(gentoo:env(_, _)),
  directory_file_path(Dir, 'make.conf', File),
  ( exists_file(File) ->
      read_file_to_string(File, S, []),
      profile:make_defaults_kv(S, KV),
      dict_pairs(KV, _, Pairs),
      forall(member(K-Vs, Pairs),
             ( ( is_list(Vs) -> atomic_list_concat(Vs, ' ', V) ; V = Vs ),
               assertz(gentoo:env(K, V))
             ))
  ; true
  ).


% =============================================================================
%  package.use
% =============================================================================

%! gentoo:load_package_use(+Dir) is det.
%
% Parse package.use (file or directory) and register per-package USE
% overrides via preference:register_gentoo_package_use/2.

gentoo:load_package_use(Dir) :-
  directory_file_path(Dir, 'package.use', Path),
  gentoo:read_package_lines(Path, Lines),
  forall(member(Line, Lines),
         gentoo:apply_package_use_line(Line)).

gentoo:apply_package_use_line(Line) :-
  split_string(Line, " \t", " \t", Tokens0),
  exclude(==(""), Tokens0, Tokens),
  ( Tokens = [AtomS|FlagSs], FlagSs \== [] ->
      atom_string(Atom, AtomS),
      maplist([S,A]>>atom_string(A,S), FlagSs, FlagAtoms),
      atomic_list_concat(FlagAtoms, ' ', UseStr),
      catch(preference:register_gentoo_package_use(Atom, UseStr), _, true)
  ; true
  ).


% =============================================================================
%  package.mask
% =============================================================================

%! gentoo:load_package_mask(+Dir) is det.
%
% Parse package.mask (file or directory) and mask the matching entries.

gentoo:load_package_mask(Dir) :-
  directory_file_path(Dir, 'package.mask', Path),
  gentoo:read_atom_lines(Path, Atoms),
  forall(member(Atom, Atoms),
         catch(preference:mask_profile_atom(Atom), _, true)).


% =============================================================================
%  package.unmask
% =============================================================================

%! gentoo:load_package_unmask(+Dir) is det.
%
% Parse package.unmask (file or directory) and unmask the matching entries.

gentoo:load_package_unmask(Dir) :-
  directory_file_path(Dir, 'package.unmask', Path),
  gentoo:read_atom_lines(Path, Atoms),
  forall(member(Atom, Atoms),
         catch(preference:unmask_profile_atom(Atom), _, true)).


% =============================================================================
%  package.accept_keywords
% =============================================================================

%! gentoo:load_package_accept_keywords(+Dir) is det.
%
% Parse package.accept_keywords (file or directory) and assert
% gentoo:package_keyword/2 facts.

gentoo:load_package_accept_keywords(Dir) :-
  retractall(gentoo:package_keyword(_, _)),
  directory_file_path(Dir, 'package.accept_keywords', Path),
  gentoo:read_package_lines(Path, Lines),
  forall(member(Line, Lines),
         gentoo:apply_package_keyword_line(Line)).

gentoo:apply_package_keyword_line(Line) :-
  split_string(Line, " \t", " \t", Tokens0),
  exclude(==(""), Tokens0, Tokens),
  ( Tokens = [AtomS|KeywordSs] ->
      atom_string(Atom, AtomS),
      ( KeywordSs == [] ->
          % Bare atom means accept ~ARCH (Portage convention)
          assertz(gentoo:package_keyword(Atom, '~*'))
      ; forall(member(KS, KeywordSs),
               ( atom_string(KW, KS),
                 assertz(gentoo:package_keyword(Atom, KW))
               ))
      )
  ; true
  ).


% =============================================================================
%  package.license
% =============================================================================

%! gentoo:load_package_license(+Dir) is det.
%
% Parse package.license (file or directory) and assert
% gentoo:package_license_entry/2 facts.

gentoo:load_package_license(Dir) :-
  retractall(gentoo:package_license_entry(_, _)),
  directory_file_path(Dir, 'package.license', Path),
  gentoo:read_package_lines(Path, Lines),
  forall(member(Line, Lines),
         gentoo:apply_package_license_line(Line)).

gentoo:apply_package_license_line(Line) :-
  split_string(Line, " \t", " \t", Tokens0),
  exclude(==(""), Tokens0, Tokens),
  ( Tokens = [AtomS|LicSs], LicSs \== [] ->
      atom_string(Atom, AtomS),
      forall(member(LS, LicSs),
             ( atom_string(Lic, LS),
               assertz(gentoo:package_license_entry(Atom, Lic))
             ))
  ; true
  ).


% =============================================================================
%  Generic file/directory readers
% =============================================================================

%! gentoo:read_atom_lines(+Path, -Atoms) is det.
%
% Read a package.mask/package.unmask style file (or directory of files).
% Returns one atom per non-empty, non-comment line.

gentoo:read_atom_lines(Path, Atoms) :-
  gentoo:collect_files(Path, Files),
  findall(A,
          ( member(F, Files),
            gentoo:read_stripped_lines(F, Lines),
            member(L, Lines),
            L \== "",
            atom_string(A, L)
          ),
          Atoms).


%! gentoo:read_package_lines(+Path, -Lines) is det.
%
% Read a package.use / package.accept_keywords / package.license style
% file (or directory of files).  Returns non-empty, non-comment line
% strings.

gentoo:read_package_lines(Path, Lines) :-
  gentoo:collect_files(Path, Files),
  findall(L,
          ( member(F, Files),
            gentoo:read_stripped_lines(F, Ls),
            member(L, Ls),
            L \== ""
          ),
          Lines).


%! gentoo:collect_files(+Path, -Files) is det.
%
% If Path is a regular file, return [Path].
% If Path is a directory, return all regular files in it in sorted order.
% If Path does not exist, return [].

gentoo:collect_files(Path, Files) :-
  ( exists_file(Path) ->
      Files = [Path]
  ; exists_directory(Path) ->
      directory_files(Path, Entries0),
      exclude(gentoo:dot_entry, Entries0, Entries1),
      msort(Entries1, Entries),
      findall(Full,
              ( member(E, Entries),
                directory_file_path(Path, E, Full),
                exists_file(Full)
              ),
              Files)
  ; Files = []
  ).

gentoo:dot_entry(E) :- sub_atom(E, 0, 1, _, '.').


%! gentoo:read_stripped_lines(+File, -Lines) is det.
%
% Read a file and return its lines with comments stripped and whitespace
% trimmed.  Empty lines are preserved (caller filters them).

gentoo:read_stripped_lines(File, Lines) :-
  catch(read_file_to_string(File, S, []), _, S = ""),
  split_string(S, "\n", "\r\n", RawLines),
  maplist(gentoo:strip_comment_and_trim, RawLines, Lines).

gentoo:strip_comment_and_trim(Raw, Trimmed) :-
  ( sub_string(Raw, Before, _, _, "#") ->
      sub_string(Raw, 0, Before, _, S0)
  ; S0 = Raw
  ),
  normalize_space(string(Trimmed), S0).