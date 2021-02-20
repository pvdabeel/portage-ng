/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2021, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> CACHE
Cache is an unguarded, dynamic Prolog context that will hold our database
structure. Repository and Knowledgebase are both interfaces to the high
performance cache context.
*/


% ******************
% CACHE declarations
% ******************

:- dynamic cache:repository/1.		% e.g. 'portage'
:- dynamic cache:category/2.		% e.g. 'portage','sys-kernel'
:- dynamic cache:package/3.		% e.g. 'portage','sys-kernel','linux-sources'
:- dynamic cache:entry/6.		% e.g. 'portage',Id,Timestamp,'sys-kernel',linux-sources','5.11.0'
:- dynamic cache:entry_metadata/4.	% e.g. 'portage',Id,'use','build'
:- dynamic cache:manifest/5.		% e.g. 'portage',Path,Timestamp,'sys-kernel','linux-sources'
:- dynamic cache:manifest_metadata/6.	% e.g. 'portage',Path,Filetype,Filename,Filesize,Checksums
