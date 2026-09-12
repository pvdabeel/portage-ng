/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> GLSA
Gentoo Linux Security Advisory knowledge store.

Parses advisories from a Portage tree's `metadata/glsa/` directory into
Prolog facts (optionally qcompiled as `Knowledge/glsa.qlf`, following the
profile-cache pattern).  Raw `github.com/gentoo/gentoo` trees omit that
directory; `--sync` clones `config:glsa_remote/1` into it.  Advisories
are *not* a package repository: entry identity remains CPVN on
portage/pkg/binpkg.  This module is a sibling knowledge artifact queried
via `glsa:search/2`, with thin bridges into package `query:search`
(`vulnerable/1`, `glsa/1`).

Security computed sets (`@security`, …) expand through `sets:expand/2` by
calling `glsa:security_atoms/2`, which joins these facts against the VDB
and emits `=cat/name-version` remediation atoms (Portage NewAffectedSet
semantics by default).

The hot store holds only title / package / range rows. The full advisory
text (synopsis, description, impact, resolution, references, …) is read
on demand from the XML file by `glsa:detail/2` — used by the `--graph`
security page (`Source/Application/Output/Grapher/security.pl`).
*/

:- module(glsa, []).

% =============================================================================
%  GLSA declarations
% =============================================================================

:- dynamic glsa:advisory/2.
:- dynamic glsa:package/4.
:- dynamic glsa:range/7.
:- dynamic glsa:loaded/0.
:- dynamic glsa:cache_source/1.
:- dynamic glsa:injected_file_override/1.

% -----------------------------------------------------------------------------
%  Configuration and paths
% -----------------------------------------------------------------------------

%! glsa:source_dir(-Dir) is semidet.
%
% Target path for GLSA XML. Prefers `config:glsa_dir/1`, else
% `$PORTDIR/metadata/glsa` from the registered portage repository.

glsa:source_dir(Dir) :-
  current_predicate(config:glsa_dir/1),
  config:glsa_dir(Dir),
  !.
glsa:source_dir(Dir) :-
  catch(portage:get_location(Root), _, fail),
  atomic_list_concat([Root, '/metadata/glsa'], Dir).


%! glsa:directory(-Dir) is semidet.
%
% Succeeds when the on-disk GLSA directory already exists.

glsa:directory(Dir) :-
  glsa:source_dir(Dir),
  exists_directory(Dir).


%! glsa:git_dir(+Dir, -GitDir) is det.
%
% Git metadata directory inside a GLSA checkout.

glsa:git_dir(Dir, GitDir) :-
  atomic_list_concat([Dir, '/.git'], GitDir).


%! glsa:injected_file(-File) is det.
%
% Path of the glsa_injected applied-ID file. Prefers
% `config:glsa_injected_file/1`, else a host-local Knowledge path.

glsa:injected_file(File) :-
  glsa:injected_file_override(File),
  !.
glsa:injected_file(File) :-
  current_predicate(config:glsa_injected_file/1),
  config:glsa_injected_file(File),
  !.
glsa:injected_file(File) :-
  config:installation_dir(Dir),
  config:hostname(Hostname),
  os:compose_path([Dir, 'Source/Knowledge/Sets/glsa_injected', Hostname], File).


%! glsa:cache_file(-File) is det.
%
% Path of the qcompiled GLSA cache (`Knowledge/glsa.qlf`).

glsa:cache_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/glsa.qlf', File).


%! glsa:raw_file(-File) is det.
%
% Path of the textual GLSA cache source (`Knowledge/glsa.raw`).

glsa:raw_file(File) :-
  working_directory(Cwd, Cwd),
  os:compose_path(Cwd, 'Knowledge/glsa.raw', File).


% -----------------------------------------------------------------------------
%  Cache load / save / ensure
% -----------------------------------------------------------------------------

%! glsa:cache_available is semidet.
%
% Succeeds when Knowledge/glsa.qlf exists.

glsa:cache_available :-
  glsa:cache_file(File),
  exists_file(File).


%! glsa:cache_save is det.
%
% Parse `metadata/glsa/` and serialize facts to Knowledge/glsa.qlf.
% Raw git trees omit that directory; `--sync` then clones
% `config:glsa_remote/1` into the source path. No-ops with a notice
% when the directory is still missing after that attempt.

glsa:cache_save :-
  nl,
  message:header(['Syncing security advisories']), nl,
  ( glsa:ensure_directory(Dir) ->
      glsa:parse_directory(Dir, Advisories, Packages, Ranges),
      glsa:write_cache(Advisories, Packages, Ranges),
      length(Advisories, N),
      format('% Updated ~w security advisories~n', [N])
  ; format(user_error, '% glsa:cache_save — no metadata/glsa directory, skipping.~n', [])
  ).


%! glsa:ensure_directory(-Dir) is semidet.
%
% Resolve a usable GLSA XML directory. An existing git checkout is
% pulled; an rsync-populated tree is left as-is; a missing directory
% is cloned from `config:glsa_remote/1`.

glsa:ensure_directory(Dir) :-
  glsa:source_dir(Dir),
  exists_directory(Dir),
  glsa:git_dir(Dir, GitDir),
  exists_directory(GitDir),
  !,
  glsa:sync_git(Dir),
  exists_directory(Dir).
glsa:ensure_directory(Dir) :-
  glsa:source_dir(Dir),
  exists_directory(Dir),
  !.
glsa:ensure_directory(Dir) :-
  glsa:source_dir(Dir),
  glsa:sync_git(Dir),
  exists_directory(Dir).


%! glsa:sync_git(+Dir) is det.
%
% Clone or pull the official GLSA git repo into Dir.

glsa:sync_git(Dir) :-
  config:glsa_remote(Remote),
  file_directory_name(Dir, Parent),
  ( exists_directory(Parent) -> true ; make_directory_path(Parent) ),
  script:exec_streaming(sync, [git, Remote, Dir], []).


%! glsa:cache_load is semidet.
%
% Load Knowledge/glsa.qlf into the local dynamic store. Fails when the
% cache file is absent.

glsa:cache_load :-
  glsa:cache_file(File),
  exists_file(File),
  glsa:clear_facts,
  ensure_loaded(File),
  ( current_predicate(glsadata:advisory/2) ->
      forall(glsadata:advisory(Id, Title),
             assertz(glsa:advisory(Id, Title))),
      forall(glsadata:package(Id, C, N, Arch),
             assertz(glsa:package(Id, C, N, Arch))),
      forall(glsadata:range(Id, C, N, Kind, Op, Ver, Slot),
             assertz(glsa:range(Id, C, N, Kind, Op, Ver, Slot)))
  ; true
  ),
  retractall(glsa:loaded),
  assertz(glsa:loaded),
  retractall(glsa:cache_source(_)),
  assertz(glsa:cache_source(qlf)).


%! glsa:ensure_loaded is det.
%
% Ensures advisory facts are available: prefer qlf cache, else live-parse
% the GLSA directory. Idempotent within a process and safe to call from
% concurrent threads (the grapher renders pages in parallel): the first
% caller loads under a mutex, later callers see `glsa:loaded`.

glsa:ensure_loaded :-
  glsa:loaded, !.
glsa:ensure_loaded :-
  with_mutex(glsa_ensure_loaded, glsa:ensure_loaded_locked).


%! glsa:ensure_loaded_locked is det.
%
% Body of ensure_loaded/0, run while holding the load mutex.

glsa:ensure_loaded_locked :-
  glsa:loaded, !.
glsa:ensure_loaded_locked :-
  ( glsa:cache_load -> true
  ; glsa:directory(Dir) ->
      glsa:clear_facts,
      glsa:parse_directory(Dir, Advisories, Packages, Ranges),
      forall(member(advisory(Id, Title), Advisories),
             assertz(glsa:advisory(Id, Title))),
      forall(member(package(Id, C, N, Arch), Packages),
             assertz(glsa:package(Id, C, N, Arch))),
      forall(member(range(Id, C, N, Kind, Op, Ver, Slot), Ranges),
             assertz(glsa:range(Id, C, N, Kind, Op, Ver, Slot))),
      retractall(glsa:loaded),
      assertz(glsa:loaded),
      retractall(glsa:cache_source(_)),
      assertz(glsa:cache_source(live))
  ; retractall(glsa:loaded),
    assertz(glsa:loaded),
    retractall(glsa:cache_source(_)),
    assertz(glsa:cache_source(empty))
  ).


%! glsa:clear_facts is det.
%
% Retracts all in-memory GLSA facts and the loaded flag.

glsa:clear_facts :-
  retractall(glsa:advisory(_, _)),
  retractall(glsa:package(_, _, _, _)),
  retractall(glsa:range(_, _, _, _, _, _, _)),
  retractall(glsa:loaded),
  retractall(glsa:cache_source(_)).


%! glsa:write_cache(+Advisories, +Packages, +Ranges) is det.
%
% Writes Knowledge/glsa.raw and qcompiles it to Knowledge/glsa.qlf.

glsa:write_cache(Advisories, Packages, Ranges) :-
  glsa:raw_file(RawFile),
  file_directory_name(RawFile, Dir),
  ( exists_directory(Dir) -> true ; make_directory_path(Dir) ),
  setup_call_cleanup(
    open(RawFile, write, Out, [encoding(utf8)]),
    ( format(Out, ':- module(glsadata, []).~n', []),
      format(Out, '% Auto-generated GLSA cache — do not edit.~n~n', []),
      format(Out, ':- dynamic advisory/2.~n', []),
      format(Out, ':- dynamic package/4.~n', []),
      format(Out, ':- dynamic range/7.~n~n', []),
      forall(member(advisory(Id, Title), Advisories),
             format(Out, '~q.~n', [advisory(Id, Title)])),
      forall(member(package(Id, C, N, Arch), Packages),
             format(Out, '~q.~n', [package(Id, C, N, Arch)])),
      forall(member(range(Id, C, N, Kind, Op, Ver, Slot), Ranges),
             format(Out, '~q.~n', [range(Id, C, N, Kind, Op, Ver, Slot)]))
    ),
    close(Out)
  ),
  catch(qcompile(RawFile), E,
        format(user_error, '% glsa:cache_save — qcompile failed: ~w~n', [E])),
  glsa:clear_facts,
  forall(member(advisory(Id, Title), Advisories),
         assertz(glsa:advisory(Id, Title))),
  forall(member(package(Id, C, N, Arch), Packages),
         assertz(glsa:package(Id, C, N, Arch))),
  forall(member(range(Id, C, N, Kind, Op, Ver, Slot), Ranges),
         assertz(glsa:range(Id, C, N, Kind, Op, Ver, Slot))),
  retractall(glsa:loaded),
  assertz(glsa:loaded),
  retractall(glsa:cache_source(_)),
  assertz(glsa:cache_source(qlf)).


% -----------------------------------------------------------------------------
%  Applied / injected tracking
% -----------------------------------------------------------------------------

%! glsa:applied(+Id) is semidet.
%
% True when Id appears in the glsa_injected file.

glsa:applied(Id) :-
  glsa:injected_file(File),
  exists_file(File),
  setup_call_cleanup(
    open(File, read, In, [encoding(utf8)]),
    glsa:stream_has_id(In, Id),
    close(In)
  ).


%! glsa:inject(+Id) is det.
%
% Appends Id to glsa_injected when not already present.

glsa:inject(Id) :-
  ( glsa:applied(Id) -> true
  ; glsa:injected_file(File),
    file_directory_name(File, Dir),
    ( exists_directory(Dir) -> true ; make_directory_path(Dir) ),
    setup_call_cleanup(
      open(File, append, Out, [encoding(utf8)]),
      format(Out, '~w~n', [Id]),
      close(Out)
    )
  ).


%! glsa:stream_has_id(+Stream, +Id) is semidet.
%
% Succeeds when a line in Stream equals Id (after whitespace normalize).

glsa:stream_has_id(In, Id) :-
  read_line_to_string(In, Line),
  Line \== end_of_file,
  normalize_space(atom(Tok), Line),
  ( Tok == Id -> true ; glsa:stream_has_id(In, Id) ).


% -----------------------------------------------------------------------------
%  XML parsing (DTD-safe, no load_structure)
% -----------------------------------------------------------------------------

%! glsa:parse_directory(+Dir, -Advisories, -Packages, -Ranges) is det.
%
% Parses every `glsa-*.xml` under Dir. Malformed files are skipped.

glsa:parse_directory(Dir, Advisories, Packages, Ranges) :-
  directory_files(Dir, Entries0),
  findall(Id-Path,
          ( member(F, Entries0),
            atom_concat('glsa-', Rest, F),
            atom_concat(Id, '.xml', Rest),
            os:compose_path(Dir, F, Path)
          ),
          Pairs0),
  sort(Pairs0, Pairs),
  findall(parsed(Adv, Pkgs, Rngs),
          ( member(Id-Path, Pairs),
            catch(glsa:parse_file(Path, Id, Adv, Pkgs, Rngs), E,
                  ( print_message(warning, glsa_parse_error(Id, E)), fail ))
          ),
          Parsed),
  findall(Adv, member(parsed(Adv, _, _), Parsed), Advisories),
  findall(Pkg, (member(parsed(_, Pkgs, _), Parsed), member(Pkg, Pkgs)), Packages),
  findall(Rng, (member(parsed(_, _, Rngs), Parsed), member(Rng, Rngs)), Ranges).


%! glsa:parse_file(+Path, +Id, -Advisory, -Packages, -Ranges) is semidet.
%
% Parses one GLSA XML file into an advisory fact and package/range lists.

glsa:parse_file(Path, Id, advisory(Id, Title), Packages, Ranges) :-
  read_file_to_string(Path, Content, [encoding(utf8)]),
  ( glsa:xml_tag_text(Content, "title", TitleStr) -> atom_string(Title, TitleStr)
  ; Title = ''
  ),
  !,
  ( glsa:xml_tag_attr(Content, "product", "type", TypeStr) -> true ; TypeStr = "ebuild" ),
  TypeStr == "ebuild",
  !,
  glsa:extract_packages(Content, Id, Packages, Ranges),
  !.


%! glsa:extract_packages(+Content, +Id, -Packages, -Ranges) is det.
%
% Extracts `<package>` blocks and nested vulnerable/unaffected ranges.

glsa:extract_packages(Content, Id, Packages, Ranges) :-
  findall(package(Id, C, N, Arch)-PkgRanges,
          glsa:package_block(Content, C, N, Arch, PkgRanges),
          Pairs),
  findall(package(Id, C, N, Arch), member(package(Id, C, N, Arch)-_, Pairs), Packages),
  findall(range(Id, C, N, Kind, Op, Ver, Slot),
          ( member(package(Id, C, N, _)-PkgRanges, Pairs),
            member(range(Kind, Op, Ver, Slot), PkgRanges)
          ),
          Ranges).


%! glsa:package_block(+Content, -C, -N, -Arch, -Ranges) is nondet.
%
% Backtracks over each `<package …>…</package>` block in Content.

glsa:package_block(Content, C, N, Arch, Ranges) :-
  sub_string(Content, P0, _, _, "<package"),
  sub_string(Content, P0, _, 0, FromPkg),
  once((
    sub_string(FromPkg, PEnd, _, _, "</package>"),
    End is PEnd + 10,
    sub_string(FromPkg, 0, End, _, Block),
    glsa:xml_attr(Block, "name", NameStr)
  )),
  atom_string(NameAtom, NameStr),
  atomic_list_concat([C, N], '/', NameAtom),
  ( once(glsa:xml_attr(Block, "arch", ArchStr))
    -> atom_string(Arch, ArchStr)
    ;  Arch = '*'
  ),
  findall(range(Kind, Op, Ver, Slot),
          glsa:range_element(Block, Kind, Op, Ver, Slot),
          Ranges).


%! glsa:range_element(+Block, -Kind, -Op, -Ver, -Slot) is nondet.
%
% Extracts one `<vulnerable|unaffected range="…">version</…>` element.

glsa:range_element(Block, Kind, Op, Ver, Slot) :-
  member(Kind-Tag, [vulnerable-"vulnerable", unaffected-"unaffected"]),
  string_concat("<", Tag, Open0),
  sub_string(Block, P0, _, _, Open0),
  once((
    sub_string(Block, P0, _, 0, From),
    sub_string(From, PClose, _, _, ">"),
    OpenLen is PClose + 1,
    sub_string(From, 0, OpenLen, _, OpenTag),
    glsa:xml_attr(OpenTag, "range", OpStr),
    atom_string(Op0, OpStr),
    glsa:normalize_op(Op0, Op),
    ( glsa:xml_attr(OpenTag, "slot", SlotStr) ->
        atom_string(Slot0, SlotStr),
        ( Slot0 == '' -> Slot = '*' ; Slot = Slot0 )
    ; Slot = '*'
    ),
    string_concat("</", Tag, Close0),
    string_concat(Close0, ">", Close),
    sub_string(From, OpenLen, _, 0, AfterOpen),
    sub_string(AfterOpen, VLen, _, _, Close),
    sub_string(AfterOpen, 0, VLen, _, VerStr0),
    normalize_space(string(VerStr), VerStr0),
    atom_string(VerAtom, VerStr),
    glsa:parse_version_atom(VerAtom, Ver)
  )).


%! glsa:normalize_op(+Raw, -Op) is semidet.
%
% Accepts the GLSA range attribute tokens.

glsa:normalize_op(le, le).
glsa:normalize_op(lt, lt).
glsa:normalize_op(eq, eq).
glsa:normalize_op(gt, gt).
glsa:normalize_op(ge, ge).
glsa:normalize_op(rge, rge).
glsa:normalize_op(rle, rle).
glsa:normalize_op(rgt, rgt).
glsa:normalize_op(rlt, rlt).


%! glsa:parse_version_atom(+Atom, -Version) is semidet.
%
% Parses a bare version string into a version/7 term.

glsa:parse_version_atom(Atom, Version) :-
  atom_codes(Atom, Codes),
  phrase(eapi:version(Version), Codes, []).


%! glsa:xml_tag_text(+Content, +Tag, -Text) is semidet.
%
% Extracts the text content of the first `<Tag>…</Tag>`.

glsa:xml_tag_text(Content, Tag, Text) :-
  string_concat("<", Tag, Open0),
  string_concat(Open0, ">", Open),
  once((
    sub_string(Content, P0, _, _, Open),
    string_length(Open, OpenLen),
    Start is P0 + OpenLen,
    string_concat("</", Tag, Close0),
    string_concat(Close0, ">", Close),
    sub_string(Content, Start, _, 0, Rest),
    sub_string(Rest, Len, _, _, Close),
    sub_string(Rest, 0, Len, _, Text0),
    normalize_space(string(Text), Text0)
  )).


%! glsa:xml_tag_attr(+Content, +Tag, +Attr, -Value) is semidet.
%
% Extracts Attr from the first opening `<Tag …>` element.

glsa:xml_tag_attr(Content, Tag, Attr, Value) :-
  string_concat("<", Tag, Open0),
  once((
    sub_string(Content, P0, _, _, Open0),
    sub_string(Content, P0, _, 0, From),
    sub_string(From, End, _, _, ">"),
    End1 is End + 1,
    sub_string(From, 0, End1, _, OpenTag),
    glsa:xml_attr(OpenTag, Attr, Value)
  )).


%! glsa:xml_attr(+OpenTag, +Attr, -Value) is semidet.
%
% Reads Attr="Value" or Attr='Value' from an opening tag string.

glsa:xml_attr(OpenTag, Attr, Value) :-
  string_concat(Attr, "=\"", Needle),
  once((
    sub_string(OpenTag, P0, _, _, Needle),
    string_length(Needle, NLen),
    Start is P0 + NLen,
    sub_string(OpenTag, Start, _, 0, Rest),
    sub_string(Rest, Len, _, _, "\""),
    sub_string(Rest, 0, Len, _, Value)
  )),
  !.
glsa:xml_attr(OpenTag, Attr, Value) :-
  string_concat(Attr, "='", Needle),
  once((
    sub_string(OpenTag, P0, _, _, Needle),
    string_length(Needle, NLen),
    Start is P0 + NLen,
    sub_string(OpenTag, Start, _, 0, Rest),
    sub_string(Rest, Len, _, _, "'"),
    sub_string(Rest, 0, Len, _, Value)
  )).


% -----------------------------------------------------------------------------
%  Advisory detail (on-demand XML read)
% -----------------------------------------------------------------------------
%
% The hot store keeps only title / package / range rows. Consumers that
% want the full advisory text (the `--graph` security page) read the
% XML file for one advisory on demand; nothing here touches the cache.

%! glsa:advisory_file(+Id, -Path) is semidet.
%
% Path of `glsa-<Id>.xml` in the GLSA source directory. Fails when the
% directory or the file is absent (qlf-only hosts).

glsa:advisory_file(Id, Path) :-
  glsa:directory(Dir),
  atomic_list_concat(['glsa-', Id, '.xml'], File),
  os:compose_path(Dir, File, Path),
  exists_file(Path).


%! glsa:advisory_url(+Id, -Url) is det.
%
% Canonical advisory page on security.gentoo.org.

glsa:advisory_url(Id, Url) :-
  atomic_list_concat(['https://security.gentoo.org/glsa/', Id], Url).


%! glsa:bug_url(+Bug, -Url) is det.
%
% Gentoo Bugzilla page for a `<bug>` number.

glsa:bug_url(Bug, Url) :-
  atomic_list_concat(['https://bugs.gentoo.org/', Bug], Url).


%! glsa:detail(+Id, -Detail) is semidet.
%
% Full advisory text for Id, read from its XML file. Detail is a list of
% field terms (each present at most once, absent when the file omits it):
%
%   synopsis(Text)       announced(Date)        revised(Date, Count)
%   access(Text)         severity(Level)        bugs([Bug, ...])
%   background(Blocks)   description(Blocks)    impact(Blocks)
%   workaround(Blocks)   resolution(Blocks)     references([ref(Label, Url), ...])
%
% Blocks is an ordered list of `p(Text)`, `code(Text)` and
% `list([Item, ...])` terms; inline markup is stripped and XML entities
% are decoded, so every Text is plain (unescaped) text. Fails when the
% XML file is not available locally.

glsa:detail(Id, Detail) :-
  glsa:advisory_file(Id, Path),
  glsa:detail_from_file(Path, Detail).


%! glsa:detail_from_file(+Path, -Detail) is det.
%
% detail/2 on an explicit XML file path.

glsa:detail_from_file(Path, Detail) :-
  read_file_to_string(Path, Content, [encoding(utf8)]),
  findall(Field, glsa:detail_field(Content, Field), Detail).


%! glsa:detail_field(+Content, -Field) is nondet.
%
% One detail/2 field extracted from the advisory XML text.

glsa:detail_field(Content, synopsis(Text)) :-
  glsa:xml_tag_text(Content, "synopsis", Raw),
  glsa:plain_text(Raw, Text).
glsa:detail_field(Content, announced(Date)) :-
  glsa:xml_tag_text(Content, "announced", Raw),
  atom_string(Date, Raw).
glsa:detail_field(Content, revised(Date, Count)) :-
  once(glsa:xml_element(Content, "revised", OpenTag, Raw, _)),
  normalize_space(atom(Date), Raw),
  ( glsa:xml_attr(OpenTag, "count", CountStr),
    normalize_space(string(CountNorm), CountStr),
    number_string(Count, CountNorm)
  -> true
  ;  Count = 1
  ).
glsa:detail_field(Content, access(Text)) :-
  glsa:xml_tag_text(Content, "access", Raw),
  glsa:plain_text(Raw, Text).
glsa:detail_field(Content, severity(Level)) :-
  once(glsa:xml_element(Content, "impact", OpenTag, _, _)),
  glsa:xml_attr(OpenTag, "type", Raw),
  normalize_space(atom(Level), Raw).
glsa:detail_field(Content, bugs(Bugs)) :-
  findall(Bug,
          ( glsa:xml_element(Content, "bug", _, Raw, _),
            normalize_space(atom(Bug), Raw),
            Bug \== ''
          ),
          Bugs),
  Bugs \== [].
glsa:detail_field(Content, Field) :-
  member(Tag-Name, ["background"-background, "description"-description,
                    "impact"-impact, "workaround"-workaround,
                    "resolution"-resolution]),
  once(glsa:xml_element(Content, Tag, _, Inner, _)),
  glsa:section_blocks(Inner, Blocks),
  Blocks \== [],
  Field =.. [Name, Blocks].
glsa:detail_field(Content, references(Refs)) :-
  once(glsa:xml_element(Content, "references", _, Inner, _)),
  findall(ref(Label, Url), glsa:uri_element(Inner, Label, Url), Refs),
  Refs \== [].


%! glsa:xml_element(+Content, +Tag, -OpenTag, -Inner, -Rest) is nondet.
%
% Backtracks over every `<Tag …>Inner</Tag>` element in Content, in
% document order. OpenTag is the complete opening tag (for xml_attr/3),
% Inner the raw text between the tags, Rest the text after the closing
% tag. `<Tag/>` yields an empty Inner. Same-tag nesting is not expected
% in GLSA documents and is not handled.

glsa:xml_element(Content, Tag, OpenTag, Inner, Rest) :-
  string_concat("<", Tag, Open0),
  string_length(Open0, OpenLen0),
  string_concat("</", Tag, Close0),
  string_concat(Close0, ">", Close),
  string_length(Close, CloseLen),
  sub_string(Content, P0, _, _, Open0),
  Next is P0 + OpenLen0,
  sub_string(Content, Next, 1, _, Ch),
  memberchk(Ch, [" ", ">", "/", "\n", "\t", "\r"]),
  once((
    sub_string(Content, P0, _, 0, From),
    sub_string(From, PClose, _, _, ">"),
    OpenLen is PClose + 1,
    sub_string(From, 0, OpenLen, _, OpenTag),
    sub_string(From, OpenLen, _, 0, After),
    ( sub_string(OpenTag, _, 2, 0, "/>")
    -> Inner = "",
       Rest = After
    ;  sub_string(After, ILen, _, _, Close),
       sub_string(After, 0, ILen, _, Inner),
       Skip is ILen + CloseLen,
       sub_string(After, Skip, _, 0, Rest)
    )
  )).


%! glsa:section_blocks(+Inner, -Blocks) is det.
%
% Converts the inner XML of a prose section into ordered `p/1`,
% `code/1` and `list/1` blocks. Text outside any block element is kept
% as a paragraph when non-blank.

glsa:section_blocks(Inner, Blocks) :-
  ( glsa:next_block(Inner, Before, Block, Rest)
  -> glsa:loose_paragraph(Before, Blocks, Blocks1),
     Blocks1 = [Block|More],
     glsa:section_blocks(Rest, More)
  ;  glsa:loose_paragraph(Inner, Blocks, [])
  ).


%! glsa:loose_paragraph(+Text, -Blocks, -Tail) is det.
%
% Difference-list cell holding `p(Text)` when Text has content once
% tags are stripped, else the empty cell.

glsa:loose_paragraph(Raw, Blocks, Tail) :-
  glsa:plain_text(Raw, Text),
  ( Text == "" -> Blocks = Tail ; Blocks = [p(Text)|Tail] ).


%! glsa:next_block(+Inner, -Before, -Block, -Rest) is semidet.
%
% Locates the first block element (`p`, `code`, `ul`, `ol`) in Inner.
% Before is the text preceding it, Rest the text following it.

glsa:next_block(Inner, Before, Block, Rest) :-
  findall(P-Tag,
          ( member(Tag, ["p", "code", "ul", "ol"]),
            glsa:tag_position(Inner, Tag, P)
          ),
          Positions),
  Positions \== [],
  min_member(P-Tag, Positions),
  sub_string(Inner, 0, P, _, Before),
  sub_string(Inner, P, _, 0, From),
  once(glsa:xml_element(From, Tag, _, ElInner, Rest)),
  glsa:block_term(Tag, ElInner, Block).


%! glsa:tag_position(+Text, +Tag, -Pos) is semidet.
%
% Offset of the first `<Tag` opening (word boundary respected) in Text.

glsa:tag_position(Text, Tag, Pos) :-
  string_concat("<", Tag, Open0),
  string_length(Open0, Len),
  once((
    sub_string(Text, Pos, _, _, Open0),
    Next is Pos + Len,
    sub_string(Text, Next, 1, _, Ch),
    memberchk(Ch, [" ", ">", "/", "\n", "\t", "\r"])
  )).


%! glsa:block_term(+Tag, +Inner, -Block) is det.
%
% Builds the block term for one element.

glsa:block_term("p", Inner, p(Text)) :-
  glsa:plain_text(Inner, Text).
glsa:block_term("code", Inner, code(Text)) :-
  glsa:code_text(Inner, Text).
glsa:block_term(Tag, Inner, list(Items)) :-
  memberchk(Tag, ["ul", "ol"]),
  findall(Item,
          ( glsa:xml_element(Inner, "li", _, Raw, _),
            glsa:plain_text(Raw, Item),
            Item \== ""
          ),
          Items).


%! glsa:uri_element(+Inner, -Label, -Url) is nondet.
%
% One `<uri link="…">Label</uri>` reference; a `<uri>` without a link
% attribute uses its text as the URL, an empty label falls back to the
% URL.

glsa:uri_element(Inner, Label, Url) :-
  glsa:xml_element(Inner, "uri", OpenTag, Raw, _),
  glsa:plain_text(Raw, LabelStr),
  ( glsa:xml_attr(OpenTag, "link", LinkRaw)
  -> glsa:xml_unescape(LinkRaw, LinkStr),
     normalize_space(atom(Url), LinkStr)
  ;  atom_string(Url, LabelStr)
  ),
  Url \== '',
  ( LabelStr == "" -> Label = Url ; atom_string(Label, LabelStr) ).


%! glsa:plain_text(+Raw, -Text) is det.
%
% Inline XML to plain text: tags stripped, entities decoded, whitespace
% normalized. Text is a string.

glsa:plain_text(Raw, Text) :-
  glsa:strip_tags(Raw, S0),
  glsa:xml_unescape(S0, S1),
  normalize_space(string(Text), S1).


%! glsa:code_text(+Raw, -Text) is det.
%
% `<code>` content to display text: tags stripped, entities decoded,
% surrounding blank lines dropped and the common indentation removed
% while keeping the line structure.

glsa:code_text(Raw, Text) :-
  glsa:strip_tags(Raw, S0),
  glsa:xml_unescape(S0, S1),
  split_string(S1, "\n", "\r", Lines0),
  glsa:trim_blank_lines(Lines0, Lines),
  glsa:common_indent(Lines, Indent),
  maplist(glsa:drop_indent(Indent), Lines, Dedented),
  atomic_list_concat(Dedented, '\n', Atom),
  atom_string(Atom, Text).


%! glsa:trim_blank_lines(+Lines, -Trimmed) is det.
%
% Drops leading and trailing whitespace-only lines.

glsa:trim_blank_lines(Lines0, Lines) :-
  glsa:drop_blank_prefix(Lines0, L1),
  reverse(L1, R1),
  glsa:drop_blank_prefix(R1, R2),
  reverse(R2, Lines).


glsa:drop_blank_prefix([L|Ls], Out) :-
  normalize_space(string(""), L),
  !,
  glsa:drop_blank_prefix(Ls, Out).
glsa:drop_blank_prefix(Ls, Ls).


%! glsa:common_indent(+Lines, -Indent) is det.
%
% Smallest leading-whitespace count over the non-blank lines (0 when
% there are none).

glsa:common_indent(Lines, Indent) :-
  findall(N,
          ( member(L, Lines),
            \+ normalize_space(string(""), L),
            glsa:leading_space_count(L, N)
          ),
          Ns),
  ( Ns == [] -> Indent = 0 ; min_list(Ns, Indent) ).


glsa:leading_space_count(Line, N) :-
  string_codes(Line, Codes),
  glsa:count_leading_space(Codes, 0, N).


glsa:count_leading_space([C|Cs], Acc, N) :-
  ( C == 0'\s ; C == 0'\t ),
  !,
  Acc1 is Acc + 1,
  glsa:count_leading_space(Cs, Acc1, N).
glsa:count_leading_space(_, N, N).


%! glsa:drop_indent(+Indent, +Line, -Out) is det.
%
% Removes up to Indent leading characters; shorter (blank) lines become
% empty.

glsa:drop_indent(Indent, Line, Out) :-
  string_length(Line, Len),
  ( Len =< Indent
  -> Out = ""
  ;  sub_string(Line, Indent, _, 0, Out)
  ).


%! glsa:strip_tags(+In, -Out) is det.
%
% Removes every `<…>` markup run from a string.

glsa:strip_tags(In, Out) :-
  string_codes(In, Codes),
  glsa:strip_tag_codes(Codes, Stripped),
  string_codes(Out, Stripped).


glsa:strip_tag_codes([], []).
glsa:strip_tag_codes([0'<|T], Out) :-
  !,
  glsa:skip_past_gt(T, Rest),
  glsa:strip_tag_codes(Rest, Out).
glsa:strip_tag_codes([C|T], [C|Out]) :-
  glsa:strip_tag_codes(T, Out).


glsa:skip_past_gt([], []).
glsa:skip_past_gt([0'>|T], T) :- !.
glsa:skip_past_gt([_|T], Rest) :-
  glsa:skip_past_gt(T, Rest).


%! glsa:xml_unescape(+In, -Out) is det.
%
% Decodes the XML predefined entities and numeric character references.
% Unknown entities are left untouched.

glsa:xml_unescape(In, Out) :-
  string_codes(In, Codes),
  glsa:unescape_codes(Codes, Decoded),
  string_codes(Out, Decoded).


glsa:unescape_codes([], []).
glsa:unescape_codes([0'&|T], [C|Out]) :-
  glsa:entity_reference(T, C, Rest),
  !,
  glsa:unescape_codes(Rest, Out).
glsa:unescape_codes([C|T], [C|Out]) :-
  glsa:unescape_codes(T, Out).


%! glsa:entity_reference(+Codes, -Char, -Rest) is semidet.
%
% Codes start right after `&`; succeeds when they open a known entity
% terminated by `;`.

glsa:entity_reference(Codes, Char, Rest) :-
  append(Name, [0';|Rest], Codes),
  !,
  length(Name, Len),
  Len >= 2, Len =< 8,
  atom_codes(Entity, Name),
  glsa:entity_char(Entity, Char).


glsa:entity_char(lt,   0'<).
glsa:entity_char(gt,   0'>).
glsa:entity_char(amp,  0'&).
glsa:entity_char(quot, 0'").
glsa:entity_char(apos, 0'\').
glsa:entity_char(Entity, Char) :-
  atom_concat('#x', Hex, Entity),
  !,
  atom_codes(Hex, HexCodes),
  catch(number_codes(Char, [0'0, 0'x|HexCodes]), _, fail),
  integer(Char).
glsa:entity_char(Entity, Char) :-
  atom_concat('#', Dec, Entity),
  atom_number(Dec, Char),
  integer(Char).


% -----------------------------------------------------------------------------
%  Version / ARCH matching
% -----------------------------------------------------------------------------

%! glsa:host_arch(-Arch) is semidet.
%
% Host ARCH via `userconfig:current_arch/1` when available, else ARCH /
% ACCEPT_KEYWORDS from preference/env.

glsa:host_arch(Arch) :-
  current_predicate(userconfig:current_arch/1),
  catch(userconfig:current_arch(Arch), _, fail),
  !.
glsa:host_arch(Arch) :-
  catch(preference:getenv('ARCH', Arch0), _, fail),
  Arch0 \== '',
  !,
  Arch = Arch0.
glsa:host_arch(Arch) :-
  catch(preference:getenv('ACCEPT_KEYWORDS', KW), _, fail),
  KW \== '',
  atomic_list_concat([Tok|_], ' ', KW),
  Tok \== '',
  ( atom_concat('~', Arch, Tok) -> true ; Arch = Tok ).


%! glsa:arch_matches(+ArchSpec) is semidet.
%
% True when ArchSpec is `*` or lists the host ARCH. When ARCH is unknown,
% only `*` matches (conservative: do not claim vulnerability).

glsa:arch_matches('*') :- !.
glsa:arch_matches(ArchSpec) :-
  glsa:host_arch(Host),
  atomic_list_concat(Parts, ' ', ArchSpec),
  memberchk(Host, Parts).


%! glsa:version_matches(+Op, +Bound, +Candidate) is semidet.
%
% True when Candidate satisfies the GLSA range Op against Bound.

glsa:version_matches(le, Bound, Cand) :-
  !,
  \+ eapi:version_compare(>, Cand, Bound).
glsa:version_matches(lt, Bound, Cand) :-
  !,
  eapi:version_compare(<, Cand, Bound).
glsa:version_matches(eq, Bound, Cand) :-
  !,
  eapi:version_compare(=, Cand, Bound).
glsa:version_matches(gt, Bound, Cand) :-
  !,
  eapi:version_compare(>, Cand, Bound).
glsa:version_matches(ge, Bound, Cand) :-
  !,
  \+ eapi:version_compare(<, Cand, Bound).
glsa:version_matches(rge, Bound, Cand) :-
  !,
  glsa:same_base_version(Bound, Cand),
  glsa:revision_compare(>=, Cand, Bound).
glsa:version_matches(rle, Bound, Cand) :-
  !,
  glsa:same_base_version(Bound, Cand),
  glsa:revision_compare(=<, Cand, Bound).
glsa:version_matches(rgt, Bound, Cand) :-
  !,
  glsa:same_base_version(Bound, Cand),
  glsa:revision_compare(>, Cand, Bound).
glsa:version_matches(rlt, Bound, Cand) :-
  !,
  glsa:same_base_version(Bound, Cand),
  glsa:revision_compare(<, Cand, Bound).


%! glsa:same_base_version(+A, +B) is semidet.
%
% True when two version/7 terms share everything except revision/Full.

glsa:same_base_version(version(N, A, SR, SN, ST, _, _),
                       version(N, A, SR, SN, ST, _, _)).


%! glsa:revision_compare(+Op, +Cand, +Bound) is semidet.
%
% Compares the revision fields of two version/7 terms.

glsa:revision_compare(Op, version(_,_,_,_,_, RevC, _),
                          version(_,_,_,_,_, RevB, _)) :-
  ( Op == (>)  -> RevC > RevB
  ; Op == (<)  -> RevC < RevB
  ; Op == (>=) -> RevC >= RevB
  ; Op == (=<) -> RevC =< RevB
  ).


%! glsa:slot_matches(+Req, +EntrySlot) is semidet.
%
% Slot filter: `*` matches any; otherwise exact canonical slot match.

glsa:slot_matches('*', _) :- !.
glsa:slot_matches(Req, EntrySlot) :-
  slotmeta:canon_slot(Req, R),
  slotmeta:canon_slot(EntrySlot, E),
  R == E.


%! glsa:range_matches(+Id, +C, +N, +Kind, +Ver, +Slot) is semidet.
%
% True when some Kind range for Id/C/N matches Ver in Slot.

glsa:range_matches(Id, C, N, Kind, Ver, Slot) :-
  glsa:range(Id, C, N, Kind, Op, Bound, ReqSlot),
  glsa:slot_matches(ReqSlot, Slot),
  glsa:version_matches(Op, Bound, Ver).


% -----------------------------------------------------------------------------
%  Vulnerability and merge list
% -----------------------------------------------------------------------------

%! glsa:is_vulnerable(+Id) is semidet.
%
% True when the host has an installed package covered by a vulnerable
% range of Id (and not covered by an unaffected range), for a matching
% ARCH, with at least one tree upgrade available.

glsa:is_vulnerable(Id) :-
  glsa:ensure_loaded,
  glsa:package(Id, C, N, Arch),
  glsa:arch_matches(Arch),
  glsa:vulnerable_installed(Id, C, N, InstalledVer, Slot),
  glsa:least_upgrade(C, N, Slot, InstalledVer, Id, _Upgrade),
  !.


%! glsa:vulnerable_installed(+Id, +C, +N, -Ver, -Slot) is nondet.
%
% Installed versions of C/N that match a vulnerable range and do not
% match an unaffected range of Id.

glsa:vulnerable_installed(Id, C, N, Ver, Slot) :-
  knowledgebase:vdb_repository(Vdb),
  query:search([category(C), name(N), version(Ver)], Vdb://Entry),
  Ver \== version_none,
  slotmeta:entry_slot_default(Vdb, Entry, Slot),
  glsa:range_matches(Id, C, N, vulnerable, Ver, Slot),
  \+ glsa:range_matches(Id, C, N, unaffected, Ver, Slot).


%! glsa:entry_covered(+Id, +Repo://+Entry) is semidet.
%
% True when Entry's C/N/version/slot is covered by a vulnerable range of
% Id and not by an unaffected range (ARCH ignored — caller filters).

glsa:entry_covered(Id, Repo://Entry) :-
  glsa:ensure_loaded,
  query:search([category(C), name(N), version(Ver)], Repo://Entry),
  Ver \== version_none,
  slotmeta:entry_slot_default(Repo, Entry, Slot),
  glsa:package(Id, C, N, _),
  glsa:range_matches(Id, C, N, vulnerable, Ver, Slot),
  \+ glsa:range_matches(Id, C, N, unaffected, Ver, Slot).


%! glsa:least_upgrade(+C, +N, +Slot, +InstalledVer, +Id, -UpgradeEntry) is semidet.
%
% Smallest visible tree version in Slot that matches an unaffected range
% of Id and is greater than InstalledVer (Portage least-change).

glsa:least_upgrade(C, N, Slot, InstalledVer, Id, BestRepo://BestEntry) :-
  findall(Ver-(Repo://Entry),
          ( query:search([select(repository, notequal, pkg),
                          category(C), name(N), version(Ver)], Repo://Entry),
            \+ knowledgebase:is_vdb_repository(Repo),
            slotmeta:entry_slot_default(Repo, Entry, Slot),
            sets:entry_visible(Repo://Entry),
            eapi:version_compare(>, Ver, InstalledVer),
            glsa:range_matches(Id, C, N, unaffected, Ver, Slot)
          ),
          Pairs),
  Pairs \== [],
  glsa:min_version_pair(Pairs, _- (BestRepo://BestEntry)).


%! glsa:min_version_pair(+Pairs, -Min) is det.
%
% Selects the lowest-version Version-Entry pair.

glsa:min_version_pair([First|Rest], Min) :-
  foldl(glsa:keep_lower_version, Rest, First, Min).


%! glsa:keep_lower_version(+Cand, +Acc, -Best) is det.
%
% Fold step retaining the lower-versioned pair.

glsa:keep_lower_version(Ver-Entry, AccVer-AccEntry, Best) :-
  ( eapi:version_compare(<, Ver, AccVer)
    -> Best = Ver-Entry
    ;  Best = AccVer-AccEntry
  ).


%! glsa:merge_list(+Id, -Atoms) is det.
%
% Least-change upgrade atoms (`=cat/name-version`) for advisory Id.

glsa:merge_list(Id, Atoms) :-
  glsa:ensure_loaded,
  findall(Atom,
          ( glsa:package(Id, C, N, Arch),
            glsa:arch_matches(Arch),
            glsa:vulnerable_installed(Id, C, N, InstalledVer, Slot),
            glsa:least_upgrade(C, N, Slot, InstalledVer, Id, _://Entry),
            atom_concat('=', Entry, Atom)
          ),
          Atoms0),
  sort(Atoms0, Atoms).


% -----------------------------------------------------------------------------
%  Search API
% -----------------------------------------------------------------------------

%! glsa:search(+Query, -Id) is nondet.
%
% Search advisories. Query is a goal or list of goals among:
%   id(Id), title(Title), package(C,N), applied(Bool), vulnerable(Bool).

glsa:search(Query, Id) :-
  glsa:ensure_loaded,
  ( is_list(Query) -> Goals = Query ; Goals = [Query] ),
  glsa:advisory(Id, Title),
  glsa:search_goals(Goals, Id, Title).


%! glsa:search_goals(+Goals, +Id, +Title) is semidet.
%
% Applies each search constraint to Id/Title.

glsa:search_goals([], _, _).
glsa:search_goals([G|Gs], Id, Title) :-
  glsa:search_goal(G, Id, Title),
  glsa:search_goals(Gs, Id, Title).


%! glsa:search_goal(+Goal, +Id, +Title) is semidet.
%
% One search constraint.

glsa:search_goal(id(Id), Id, _).
glsa:search_goal(title(Title), _, Title).
glsa:search_goal(package(C, N), Id, _) :-
  glsa:package(Id, C, N, _).
glsa:search_goal(applied(true), Id, _) :-
  glsa:applied(Id).
glsa:search_goal(applied(false), Id, _) :-
  \+ glsa:applied(Id).
glsa:search_goal(vulnerable(true), Id, _) :-
  glsa:is_vulnerable(Id).
glsa:search_goal(vulnerable(false), Id, _) :-
  \+ glsa:is_vulnerable(Id).


% -----------------------------------------------------------------------------
%  Package-centric views
% -----------------------------------------------------------------------------

%! glsa:package_advisories(+C, +N, -Ids) is det.
%
% Advisory ids whose `<affected>` list names package C/N, newest first
% (ids are `YYYYMM-NN`, so the standard order of atoms is chronological).

glsa:package_advisories(C, N, Ids) :-
  glsa:ensure_loaded,
  findall(Id, glsa:package(Id, C, N, _), Ids0),
  sort(Ids0, Ascending),
  reverse(Ascending, Ids).


%! glsa:entry_status(+Id, +Repo://+Entry, -Status) is det.
%
% How advisory Id relates to one tree entry (ARCH ignored):
%
%   - `vulnerable`  — a vulnerable range covers Entry's version/slot and
%                     no unaffected range does (same test as entry_covered/2)
%   - `unaffected`  — an unaffected range covers it
%   - `unlisted`    — the advisory names the package but neither range
%                     mentions this version/slot (or Entry is unknown)

glsa:entry_status(Id, Repo://Entry, Status) :-
  glsa:ensure_loaded,
  (   query:search([category(C), name(N), version(Ver)], Repo://Entry),
      Ver \== version_none,
      slotmeta:entry_slot_default(Repo, Entry, Slot),
      glsa:package(Id, C, N, _)
  ->  (   glsa:range_matches(Id, C, N, unaffected, Ver, Slot)
      ->  Status = unaffected
      ;   glsa:range_matches(Id, C, N, vulnerable, Ver, Slot)
      ->  Status = vulnerable
      ;   Status = unlisted
      )
  ;   Status = unlisted
  ).


% -----------------------------------------------------------------------------
%  Security set expansion
% -----------------------------------------------------------------------------

%! glsa:security_atoms(+Filter, -Atoms) is det.
%
% Expands a Portage security-set filter to sorted `=cpv` remediation atoms.
% Filter is one of: security, affected, new_glsa, new_affected.
%
% Driven from the VDB (installed packages) rather than scanning every
% advisory, so expansion stays near-linear in installed CPV count.

glsa:security_atoms(Filter, Atoms) :-
  glsa:ensure_loaded,
  findall(Atom,
          ( knowledgebase:vdb_repository(Vdb),
            query:search([category(C), name(N), version(Ver)], Vdb://Entry),
            Ver \== version_none,
            slotmeta:entry_slot_default(Vdb, Entry, Slot),
            glsa:package(Id, C, N, Arch),
            glsa:arch_matches(Arch),
            glsa:filter_allows(Filter, Id),
            glsa:range_matches(Id, C, N, vulnerable, Ver, Slot),
            \+ glsa:range_matches(Id, C, N, unaffected, Ver, Slot),
            glsa:least_upgrade(C, N, Slot, Ver, Id, _://UpEntry),
            atom_concat('=', UpEntry, Atom)
          ),
          Atoms0),
  glsa:reduce_atoms(Atoms0, Atoms).


%! glsa:filter_allows(+Filter, +Id) is semidet.
%
% Portage security set class filters. For atom expansion, `security` and
% `affected` coincide (only vulnerable installs yield atoms); `new_*`
% additionally require the advisory not be in glsa_injected.
% `is_vulnerable/1` remains available for `glsa:search`.

glsa:filter_allows(security, _).
glsa:filter_allows(affected, _).
glsa:filter_allows(new_glsa, Id) :-
  \+ glsa:applied(Id).
glsa:filter_allows(new_affected, Id) :-
  \+ glsa:applied(Id).


%! glsa:reduce_atoms(+Atoms, -Reduced) is det.
%
% Per cat/name:slot keep the highest-version `=cpv` atom (Portage `_reduce`).

glsa:reduce_atoms([], []) :- !.
glsa:reduce_atoms(Atoms0, Reduced) :-
  findall(Key-Atom,
          ( member(Atom, Atoms0),
            glsa:atom_cn_slot_ver(Atom, C, N, Slot, _Ver),
            Key = C-N-Slot
          ),
          Pairs0),
  keysort(Pairs0, Sorted),
  glsa:keep_highest_per_key(Sorted, Kept),
  findall(A, member(_-A, Kept), Atoms1),
  sort(Atoms1, Reduced).


%! glsa:atom_cn_slot_ver(+Atom, -C, -N, -Slot, -Ver) is semidet.
%
% Parses `=cat/name-version` and resolves slot from the tree entry.

glsa:atom_cn_slot_ver(Atom, C, N, Slot, Ver) :-
  atom_concat('=', Entry, Atom),
  cache:ordered_entry(Repo, Entry, C, N, Ver),
  \+ knowledgebase:is_vdb_repository(Repo),
  slotmeta:entry_slot_default(Repo, Entry, Slot),
  !.
glsa:atom_cn_slot_ver(Atom, C, N, '0', Ver) :-
  atom_concat('=', Entry, Atom),
  atomic_list_concat([C, Rest], '/', Entry),
  atom_codes(Rest, Codes),
  phrase((eapi:package(N), eapi:version0(Ver)), Codes, []),
  Ver \== version_none.


%! glsa:keep_highest_per_key(+SortedPairs, -Kept) is det.
%
% From keysorted Key-Atom pairs, keep the highest-version atom per Key.

glsa:keep_highest_per_key([], []).
glsa:keep_highest_per_key([K-A|Rest], [K-Best|Out]) :-
  glsa:take_key_group(Rest, K, [K-A], Group, Rest2),
  glsa:highest_atom(Group, Best),
  glsa:keep_highest_per_key(Rest2, Out).


%! glsa:take_key_group(+Rest, +K, +Acc, -Group, -Rest2) is det.
%
% Collects consecutive pairs sharing key K.

glsa:take_key_group([K-A|Rest], K, Acc, Group, Rest2) :-
  !,
  glsa:take_key_group(Rest, K, [K-A|Acc], Group, Rest2).
glsa:take_key_group(Rest, _, Acc, Acc, Rest).


%! glsa:highest_atom(+Group, -Atom) is det.
%
% Picks the `=cpv` with the highest version from a Key-Atom group.

glsa:highest_atom([_-A], A) :- !.
glsa:highest_atom(Group, Best) :-
  findall(Ver-A,
          ( member(_-A, Group),
            ( glsa:atom_cn_slot_ver(A, _, _, _, Ver) -> true ; Ver = version_none )
          ),
          Pairs),
  glsa:max_version_pair(Pairs, _-Best).


%! glsa:max_version_pair(+Pairs, -Max) is det.
%
% Highest-version Version-Atom pair.

glsa:max_version_pair([First|Rest], Max) :-
  foldl(glsa:keep_higher_version, Rest, First, Max).


%! glsa:keep_higher_version(+Cand, +Acc, -Best) is det.
%
% Fold step retaining the higher-versioned pair.

glsa:keep_higher_version(Ver-A, AccVer-AccA, Best) :-
  ( eapi:version_compare(>, Ver, AccVer)
    -> Best = Ver-A
    ;  Best = AccVer-AccA
  ).


% -----------------------------------------------------------------------------
%  Message hook
% -----------------------------------------------------------------------------

:- multifile prolog:message//1.

prolog:message(glsa_parse_error(Id, E)) -->
  ['GLSA ~w: parse skipped (~w)'-[Id, E]].
