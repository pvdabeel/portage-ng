/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CACHE
Cache database structure that holds information about repositories, categories, packages,
repository entries, repository entry metadata, etc.

Query, Repository and Knowledgebase are interfaces to this high performance cache
context. Query defines (inlined) queries on this database, Repository and Knowledgebase
define operations like sync, save, etc.

Indexing of the facts in the cache database is performed JIT by the swi-prolog JIT indexer.
This allows for O(1) lookups.
*/


% ******************
% CACHE declarations
% ******************

:- dynamic cache:repository/1.		% e.g. 'portage'
:- dynamic cache:category/2.		% e.g. 'portage','sys-kernel'
:- dynamic cache:package/3.		% e.g. 'portage','sys-kernel','linux-sources'
:- dynamic cache:entry/5.		% e.g. 'portage','sys-kernel/linux-sources-6.15.0','sys-kernel',linux-sources',[[6,15,0],,,'6.15.0'] (Versions not ordered)
:- dynamic cache:ordered_entry/5.       % e.g. 'portage','sys-kernel/linux-sources-6.15.0','sys-kernel',linux-sources',[[6.15.0],,,'6.15.0'] (Versions ordered)
:- dynamic cache:entry_metadata/4.	% e.g. 'portage','sys-kernel/linux-sources-6.15.0','use','build'
:- dynamic cache:manifest/5.		% e.g. 'portage',Path,Timestamp,'sys-kernel','linux-sources'
:- dynamic cache:manifest_metadata/6.	% e.g. 'portage',Path,Filetype,Filename,Filesize,Checksums
