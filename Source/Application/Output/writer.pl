/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WRITER
The Writer produces per-ebuild plan files (.merge, .fetchonly, .info,
.emerge, .pmerge) and HTML index files for the graph directory.

Responsibilities:
- Writing .merge and .fetchonly plan files with timing metadata (% merge / % fetchonly lines). `.fetchonly` is the `:run` proof printed under `preference:local_flag(fetchonly)`.
- Writing .info files with ebuild detail output.
- Writing .emerge files capturing `emerge -vp` output via the gentoo-prefix
  emerge-vp wrapper, wrapped with `% emerge started/ended/wall_time_ms`
  lines so the terminal grapher can render them next to .merge files.
- Writing .pmerge files capturing `pmerge --pretend --verbose` output via
  the gentoo-prefix pmerge wrapper, wrapped with `% pmerge started/ended/wall_time_ms`
  lines so the terminal grapher can render them in the legacy group.
- Writing per-repository / per-category / per-package HTML index files.
- Orchestrating batch proof-file generation for --graph.
- Converting proof files to HTML via the aha script.

The actual terminal rendering of plans and assumptions is handled by the
printer module; the writer calls printer:print/5 and info:print_entry/1
to produce the content written to files.
*/

:- module(writer, []).

% =============================================================================
%  File writers
% =============================================================================


%! writer:write_merge_file(+Directory,+Repository://Entry)
%
% Proves and writes the merge plan to file for an entry in a repository.
% Uses prove_plan_with_fallback for the canonical 5-tier fallback chain.
% Assumes directory exists. (See repository:prepare_directory)

writer:write_merge_file(Directory,Repository://Entry) :-
  Action = run,
  Extension = '.merge',
  Goals = [Repository://Entry:Action?{[]}],
  get_time(T0),
  ( pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers, _FallbackUsed),
    atomic_list_concat([Directory,'/',Entry,Extension],File)
  ),
  atomic_list_concat([File,'.tmp'], TmpFile),
  ( catch(
      setup_call_cleanup(
        tell(TmpFile),
        ( set_stream(current_output,tty(true)),
          timing:print_timing_header('merge', T0),
          printer:print(Goals,Model,Proof,Plan,Triggers),
          timing:print_timing_footer('merge', T0)
        ),
        told
      ),
      _E,
      ( told, fail )
    )
  -> catch(rename_file(TmpFile, File), _, true)
  ; ( ( catch(delete_file(TmpFile), _, true) ),
      with_mutex(mutex,message:warning([Repository,'://',Entry,' ',Action]))
    )
  ).


%! writer:write_fetchonly_file(+Directory,+Repository://Entry)
%
% Proves the same :run plan as write_merge_file/2, then prints it under
% preference:local_flag(fetchonly) so the file lists downloads and
% configuration pre-actions only. Uses prove_plan_with_fallback for the
% canonical 5-tier fallback chain. Assumes directory exists.

writer:write_fetchonly_file(Directory,Repository://Entry) :-
  Action = run,
  Extension = '.fetchonly',
  Goals = [Repository://Entry:Action?{[]}],
  get_time(T0),
  ( pipeline:prove_plan_with_fallback(Goals, Proof, Model, Plan, Triggers, _FallbackUsed),
    atomic_list_concat([Directory,'/',Entry,Extension],File)
  ),
  atomic_list_concat([File,'.tmp'], TmpFile),
  ( catch(
      setup_call_cleanup(
        tell(TmpFile),
        ( set_stream(current_output,tty(true)),
          timing:print_timing_header('fetchonly', T0),
          preference:with_local_flag(fetchonly,
            printer:print(Goals,Model,Proof,Plan,Triggers)),
          timing:print_timing_footer('fetchonly', T0)
        ),
        told
      ),
      _E,
      ( told, fail )
    )
  -> catch(rename_file(TmpFile, File), _, true)
  ; ( ( catch(delete_file(TmpFile), _, true) ),
      with_mutex(mutex,message:warning([Repository,'://',Entry,' fetchonly']))
    )
  ).


%! writer:write_info_file(+Directory,+Repository://Entry)
%
% Print info to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

writer:write_info_file(Directory,Repository://Entry) :-
  (atomic_list_concat([Directory,'/',Entry,'.info'],File)),
  (tell(File),
   set_stream(current_output,tty(true)),
   info:print_entry(Repository://Entry)
   -> told
   ;  (told,with_mutex(mutex,message:warning([Repository,'://',Entry,' ',info])))).


% -----------------------------------------------------------------------------
%  Emerge file writer
% -----------------------------------------------------------------------------

%! writer:write_emerge_file(+Directory, +Repository://Entry) is det.
%
% Run the external `emerge-vp` wrapper for the ebuild and write its
% output to <Directory>/<Entry>.emerge, wrapped with timing lines
% (`% emerge started/ended/wall_time_ms`). Replaces the legacy
% generate-emerge-files.sh shell driver.
%
% Skips when the .emerge file is already newer than the corresponding
% .ebuild (incremental mode). Set `config:force_emerge_regen(true)` to
% bypass the check (this is what `--graph emerge full` does).
% Assumes Directory exists. (See repository:prepare_directory.)

writer:write_emerge_file(Directory, Repository://Entry) :-
  atomic_list_concat([Directory,'/',Entry,'.emerge'], File),
  ( catch(Repository:get_ebuild_file(Entry, Ebuild), _, fail) -> true
  ; with_mutex(mutex, message:warning([Repository,'://',Entry,' emerge (no ebuild)'])),
    fail
  ),
  ( writer:emerge_file_fresh(File, Ebuild)
  -> true
  ;  writer:do_write_emerge_file(File, Repository://Entry)
  ).


%! writer:emerge_file_fresh(+EmergeFile, +EbuildFile) is semidet.
%
% Succeed when EmergeFile exists and is newer than EbuildFile, *and*
% no forced-regeneration override is active.

writer:emerge_file_fresh(EmergeFile, Ebuild) :-
  \+ config:force_emerge_regen(true),
  exists_file(EmergeFile),
  exists_file(Ebuild),
  time_file(EmergeFile, FT),
  time_file(Ebuild, ET),
  FT > ET.


%! writer:do_write_emerge_file(+OutFile, +Repository://Entry) is det.
%
% Resolve the emerge-vp binary for the current host, spawn it on the
% target ebuild (with stdout+stderr merged to OutFile via an atomic
% rename), and surround the output with timing header/footer lines.

writer:do_write_emerge_file(OutFile, Repository://Entry) :-
  atom_concat(OutFile, '.tmp', TmpFile),
  atom_concat('=', Entry, EmergeTarget),
  ( current_predicate(config:emerge_vp_path/1),
    config:emerge_vp_path(EmergeBin) -> true
  ; config:hostname(H),
    with_mutex(mutex,
      message:warning(['No config:emerge_vp_path/1 in Source/Config/', H,
                       '.pl; cannot write .emerge'])),
    fail
  ),
  config:emerge_vp_timeout(Timeout),
  file_directory_name(OutFile, OutDir),
  catch(os:ensure_directory_path(OutDir), _, true),
  get_time(T0),
  ( catch(
      setup_call_cleanup(
        tell(TmpFile),
        ( set_stream(current_output, tty(true)),
          timing:print_timing_header('emerge', T0),
          nl,
          writer:run_emerge_vp(EmergeBin, EmergeTarget, Timeout),
          nl,
          timing:print_timing_footer('emerge', T0)
        ),
        told
      ),
      E,
      ( told,
        catch(delete_file(TmpFile), _, true),
        term_to_atom(E, EA),
        with_mutex(mutex,
          message:warning([Repository,'://',Entry,' emerge (',EA,')'])),
        fail
      )
    )
  -> catch(rename_file(TmpFile, OutFile), _, true)
  ;  catch(delete_file(TmpFile), _, true),
     with_mutex(mutex, message:warning([Repository,'://',Entry,' emerge']))
  ).


%! writer:run_emerge_vp(+Bin, +Target, +Timeout) is det.
%
% Spawn `Bin --color y Target`, stream stdout+stderr to current_output,
% and bound the run with Timeout seconds. On timeout the child is sent
% SIGKILL. Replicates `gtimeout T emerge-vp --color y =cat/pkg-ver 2>&1`.

writer:run_emerge_vp(Bin, Target, Timeout) :-
  writer:run_captured(Bin, ['--color','y', Target], Timeout).



% -----------------------------------------------------------------------------
%  Pmerge file writer
% -----------------------------------------------------------------------------

%! writer:write_pmerge_file(+Directory, +Repository://Entry) is det.
%
% Run the external `pmerge` wrapper for the ebuild and write its
% output to <Directory>/<Entry>.pmerge, wrapped with timing lines
% (`% pmerge started/ended/wall_time_ms`). The invocation is
% `pmerge --pretend --verbose`.
%
% Skips when the .pmerge file is already newer than the corresponding
% .ebuild (incremental mode). Set `config:force_pmerge_regen(true)` to
% bypass the check (this is what `--graph pmerge full` does).
% Assumes Directory exists. (See repository:prepare_directory.)

writer:write_pmerge_file(Directory, Repository://Entry) :-
  atomic_list_concat([Directory,'/',Entry,'.pmerge'], File),
  ( catch(Repository:get_ebuild_file(Entry, Ebuild), _, fail) -> true
  ; with_mutex(mutex, message:warning([Repository,'://',Entry,' pmerge (no ebuild)'])),
    fail
  ),
  ( writer:pmerge_file_fresh(File, Ebuild)
  -> true
  ;  writer:do_write_pmerge_file(File, Repository://Entry)
  ).


%! writer:pmerge_file_fresh(+PmergeFile, +EbuildFile) is semidet.
%
% Succeed when PmergeFile exists and is newer than EbuildFile, and
% no forced-regeneration override is active.

writer:pmerge_file_fresh(PmergeFile, Ebuild) :-
  \+ config:force_pmerge_regen(true),
  exists_file(PmergeFile),
  exists_file(Ebuild),
  time_file(PmergeFile, FT),
  time_file(Ebuild, ET),
  FT > ET.


%! writer:do_write_pmerge_file(+OutFile, +Repository://Entry) is det.
%
% Resolve the pmerge binary for the current host, spawn
% `pmerge --pretend --verbose` on the target ebuild (with stdout+stderr
% merged to OutFile via an atomic rename), and surround the output with
% timing header/footer lines. `--color true` forces ANSI when stdout is
% a pipe, matching emerge-vp's `--color y`.

writer:do_write_pmerge_file(OutFile, Repository://Entry) :-
  atom_concat(OutFile, '.tmp', TmpFile),
  atom_concat('=', Entry, PmergeTarget),
  ( current_predicate(config:pmerge_path/1),
    config:pmerge_path(PmergeBin) -> true
  ; config:hostname(H),
    with_mutex(mutex,
      message:warning(['No config:pmerge_path/1 in Source/Config/', H,
                       '.pl; cannot write .pmerge'])),
    fail
  ),
  config:pmerge_timeout(Timeout),
  file_directory_name(OutFile, OutDir),
  catch(os:ensure_directory_path(OutDir), _, true),
  get_time(T0),
  ( catch(
      setup_call_cleanup(
        tell(TmpFile),
        ( set_stream(current_output, tty(true)),
          timing:print_timing_header('pmerge', T0),
          nl,
          writer:run_pmerge(PmergeBin, PmergeTarget, Timeout),
          nl,
          timing:print_timing_footer('pmerge', T0)
        ),
        told
      ),
      E,
      ( told,
        catch(delete_file(TmpFile), _, true),
        term_to_atom(E, EA),
        with_mutex(mutex,
          message:warning([Repository,'://',Entry,' pmerge (',EA,')'])),
        fail
      )
    )
  -> catch(rename_file(TmpFile, OutFile), _, true)
  ;  catch(delete_file(TmpFile), _, true),
     with_mutex(mutex, message:warning([Repository,'://',Entry,' pmerge']))
  ).


%! writer:run_pmerge(+Bin, +Target, +Timeout) is det.
%
% Spawn `Bin --pretend --verbose --color true Target` and bound the run
% with Timeout seconds.

writer:run_pmerge(Bin, Target, Timeout) :-
  writer:run_captured(Bin, ['--pretend','--verbose','--color','true', Target], Timeout).


%! writer:run_captured(+Bin, +Args, +Timeout) is det.
%
% Spawn Bin with Args, stream stdout+stderr to current_output, and bound
% the run with Timeout seconds. On timeout the child is sent SIGKILL.

writer:run_captured(Bin, Args, Timeout) :-
  process_set_method(vfork),
  process_create(Bin, Args,
                 [ stdout(pipe(Out)),
                   stderr(pipe(Out)),
                   process(Pid) ]),
  call_cleanup(
    copy_stream_data(Out, current_output),
    ( close(Out),
      ( process_wait(Pid, _, [timeout(Timeout)])
      -> true
      ;  catch(process_kill(Pid, 9), _, true),
         catch(process_wait(Pid, _), _, true)
      )
    )).


% =============================================================================
%  Index file writers (HTML)
% =============================================================================


%! writer:write_repository_index_file(+Directory,+Repository)
%
% Write the index file for a given repository, listing all categories.

writer:write_repository_index_file(Directory,Repository) :-
  atomic_list_concat([Directory,'/index.html'],File),
  tell(File),
  index:print_repository_index(Repository),
  told.


%! writer:write_category_index_file(+Directory,+Repository,+Category)
%
% Write the index file for a given category, listing all packages.

writer:write_category_index_file(Directory,Repository,Category) :-
  atomic_list_concat([Directory,'/',Category,'/index.html'],File),
  tell(File),
  index:print_category_index(Repository, Category),
  told.


%! writer:write_package_index_file(+Directory,+Repository,+Category,+Name)
%
% Write the index file for a given package, listing all versions with graph links.

writer:write_package_index_file(Directory,Repository,Category,Name) :-
  atomic_list_concat([Directory,'/',Category,'/',Name,'.html'],File),
  tell(File),
  index:print_package_index(Repository, Category, Name),
  told.


%! writer:write_index_files(+Directory,+Repository)
%
% Print index files for repository, its categories and packages.
% Assumes directory exists. (See repository:prepare_directory)

writer:write_index_files(Directory,Repository) :-

  writer:write_repository_index_file(Directory,Repository),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://Category,
              cache:category(Repository,Category),
              writer:write_category_index_file(Directory,Repository,Category)),

  tester:test(parallel_verbose,
              'Writing index files',
              Repository://CategoryName,
              (cache:package(Repository,Category,Name),
               atomic_list_concat([Category,'/',Name],CategoryName)),
              writer:write_package_index_file(Directory,Repository,Category,Name)).


%! writer:write_graph_files(+Directory,+Repository)
%
% Write HTML graph files for all entries in a repository.
% Assumes directory exists. (See repository:prepare_directory)

writer:write_graph_files(Directory,Repository) :-
  grapher:write_graph_files(Directory,Repository).


%! writer:write_proof_files(+Directory,+Repository)
%
% Write text proof files (.merge, .fetchonly, .info) for all entries
% in a repository. When config:graph_include_emerge(true), also writes
% .emerge files via the emerge-vp wrapper (otherwise use
% `--graph emerge` for explicit regeneration). When
% config:graph_include_pmerge(true), also writes .pmerge files
% (otherwise use `--graph pmerge`).
% Assumes directory exists. (See repository:prepare_directory)

writer:write_proof_files(Directory,Repository) :-
  tester:test(parallel_verbose,
              'Writing proof files',
              Repository://Entry,
              (Repository:entry(Entry),
               (config:graph_modified_only(true)
                -> Repository:entry(Entry,Time),
                   Repository:get_ebuild_file(Entry,Ebuild),
                   system:exists_file(Ebuild),
                   system:time_file(Ebuild,Modified),
                   Modified > Time
                ;  true)),
	      ((writer:write_merge_file(Directory,Repository://Entry);true),
	       (writer:write_fetchonly_file(Directory,Repository://Entry);true),
               (writer:write_info_file(Directory,Repository://Entry);true))),
  ( config:graph_include_emerge(true)
  -> writer:write_emerge_files(Directory, Repository)
  ;  true
  ),
  ( config:graph_include_pmerge(true)
  -> writer:write_pmerge_files(Directory, Repository)
  ;  true
  ).


%! writer:write_emerge_files(+Directory, +Repository) is det.
%
% Generate `.emerge` files for every entry in Repository by invoking the
% gentoo-prefix `emerge-vp` wrapper. Honours `config:graph_modified_only/1`
% for coarse filtering (skip ebuilds whose source isn't newer than the
% md5-cache entry) and the per-file mtime check in
% writer:emerge_file_fresh/2 for fine-grained incremental behaviour.
%
% Concurrency is controlled by `config:emerge_vp_concurrency/1`
% (default 1, matching the legacy generate-emerge-files.sh).

writer:write_emerge_files(Directory, Repository) :-
  config:emerge_vp_concurrency(N),
  Goal = writer:write_emerge_file_with_progress(Directory, Repository://Entry),
  ( integer(N), N > 1
  -> concurrent_forall(writer:emerge_candidate(Repository, Entry), Goal,
                       [threads(N)])
  ;  forall(writer:emerge_candidate(Repository, Entry), Goal)
  ),
  with_mutex(mutex, format('~N')).


%! writer:emerge_candidate(+Repository, -Entry) is nondet.
%
% Enumerate ebuild entries that should be considered for .emerge and
% .pmerge generation. When config:graph_modified_only/1 is true, only yields
% entries whose .ebuild is newer than the md5-cache mtime; otherwise
% yields every entry.

writer:emerge_candidate(Repository, Entry) :-
  Repository:entry(Entry),
  ( config:graph_modified_only(true)
  -> Repository:entry(Entry, Time),
     catch(Repository:get_ebuild_file(Entry, Ebuild), _, fail),
     system:exists_file(Ebuild),
     system:time_file(Ebuild, Modified),
     Modified > Time
  ;  true
  ).


%! writer:write_emerge_file_with_progress(+Directory, +Repository://Entry) is det.
%
% Wrap writer:write_emerge_file/2 with mutex-protected progress output
% so the user sees per-ebuild status during long `--graph emerge` runs.

writer:write_emerge_file_with_progress(Directory, Repository://Entry) :-
  with_mutex(mutex,
    message:scroll_notice(['Writing emerge - ',Repository,'://',Entry])),
  ( catch(writer:write_emerge_file(Directory, Repository://Entry), E,
          ( term_to_atom(E, EA),
            with_mutex(mutex,
              message:warning([Repository,'://',Entry,' emerge (',EA,')']))
          ))
  ; true
  ).


%! writer:write_pmerge_files(+Directory, +Repository) is det.
%
% Generate `.pmerge` files for every entry in Repository by invoking
% `pmerge --pretend --verbose`. Honours `config:graph_modified_only/1`
% for coarse filtering and the per-file mtime check in
% writer:pmerge_file_fresh/2 for fine-grained incremental behaviour.
%
% Concurrency is controlled by `config:pmerge_concurrency/1` (default 1).

writer:write_pmerge_files(Directory, Repository) :-
  config:pmerge_concurrency(N),
  Goal = writer:write_pmerge_file_with_progress(Directory, Repository://Entry),
  ( integer(N), N > 1
  -> concurrent_forall(writer:emerge_candidate(Repository, Entry), Goal,
                       [threads(N)])
  ;  forall(writer:emerge_candidate(Repository, Entry), Goal)
  ),
  with_mutex(mutex, format('~N')).


%! writer:write_pmerge_file_with_progress(+Directory, +Repository://Entry) is det.
%
% Wrap writer:write_pmerge_file/2 with mutex-protected progress output
% so the user sees per-ebuild status during long `--graph pmerge` runs.

writer:write_pmerge_file_with_progress(Directory, Repository://Entry) :-
  with_mutex(mutex,
    message:scroll_notice(['Writing pmerge - ',Repository,'://',Entry])),
  ( catch(writer:write_pmerge_file(Directory, Repository://Entry), E,
          ( term_to_atom(E, EA),
            with_mutex(mutex,
              message:warning([Repository,'://',Entry,' pmerge (',EA,')']))
          ))
  ; true
  ).


%! writer:produce_html(+Directory)
%
% For a given directory with proof files, convert the files into html.

writer:produce_html(Directory) :-
  message:scroll_notice(['Now running Aha ...']),
  message:hc,
  script:exec(print,['aha',Directory]),
  message:sc.