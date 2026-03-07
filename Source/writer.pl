/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> WRITER
The Writer produces per-ebuild plan files (.merge, .fetchonly, .info) and
HTML index files for the graph directory.

Responsibilities:
- Writing .merge and .fetchonly plan files with timing metadata.
- Writing .info files with ebuild detail output.
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
% Print merge plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

writer:write_merge_file(Directory,Repository://Entry) :-
  Action = run,
  Extension = '.merge',
  Goals = [Repository://Entry:Action?{[]}],
  get_time(T0),
  ( ( pipeline:prove_plan(Goals, Proof, Model, Plan, Triggers)
    ; prover:assuming(keyword_acceptance,
        prover:assuming(unmask,
          pipeline:prove_plan(Goals, Proof, Model, Plan, Triggers)))
    ),
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
% Print fetchonly plan to file for an entry in a repository
% Assumes directory exists. (See repository:prepare_directory)

writer:write_fetchonly_file(Directory,Repository://Entry) :-
  Action = fetchonly,
  Extension = '.fetchonly',
  Goals = [Repository://Entry:Action?{[]}],
  ( ( pipeline:prove_plan(Goals, Proof, Model, Plan, Triggers)
    ; prover:assuming(keyword_acceptance,
        prover:assuming(unmask,
          pipeline:prove_plan(Goals, Proof, Model, Plan, Triggers)))
    ),
    atomic_list_concat([Directory,'/',Entry,Extension],File)
  ),
  atomic_list_concat([File,'.tmp'], TmpFile),
  ( catch(
      setup_call_cleanup(
        tell(TmpFile),
        ( set_stream(current_output,tty(true)),
          printer:print(Goals,Model,Proof,Plan,Triggers)
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


% =============================================================================
%  Index file writers (HTML)
% =============================================================================


%! writer:write_repository_index_file(+Directory,+Repository)
%
% Write the index file for a given repository, listing all categories.

writer:write_repository_index_file(Directory,Repository) :-
  atomic_list_concat(['Repository: ',Repository],Title),
  atomic_list_concat([Directory,'/index.html'],File),
  tell(File),
  index:print_index(repository,Title,Title,cache:category(Repository,Category),Category,'./.index.css'),
  told.


%! writer:write_category_index_file(+Directory,+Repository,+Category)
%
% Write the index file for a given category, listing all packages.

writer:write_category_index_file(Directory,Repository,Category) :-
  atomic_list_concat(['Category: ',Repository,'://',Category],Title),
  atomic_list_concat(['Category: <a href=\"../index.html\">',Repository,'</a>://',Category],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/index.html'],File),
  tell(File),
  index:print_index(category,Title,TitleHtml,cache:package(Repository,Category,Name),Name,'../.index.css'),
  told.


%! writer:write_package_index_file(+Directory,+Repository,+Category,+Name)
%
% Write the index file for a given package, listing all entries

writer:write_package_index_file(Directory,Repository,Category,Name) :-
  atomic_list_concat(['Package: ',Repository,'://',Category,'/',Name],Title),
  atomic_list_concat(['Package: <a href=\"../index.html\">',Repository,'</a>://<a href=\"./index.html\">',Category,'</a>/',Name],TitleHtml),
  atomic_list_concat([Directory,'/',Category,'/',Name,'.html'],File),
  tell(File),
  index:print_index(package,Title,TitleHtml,( cache:ordered_entry(Repository,_,Category,Name,Ver), eapi:version_full(Ver,Version) ),[Name,Version],'../.index.css'),
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


%! writer:write_proof_files(+Directory,+Repository)
%
% Print merge, fetchonly & info to file for all entries in a repository
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
               (writer:write_info_file(Directory,Repository://Entry);true))).


%! writer:produce_html(+Directory)
%
% For a given directory with proof files, convert the files into html.

writer:produce_html(Directory) :-
  message:scroll_notice(['Now running Aha ...']),
  message:hc,
  script:exec(print,['aha',Directory]),
  message:sc.