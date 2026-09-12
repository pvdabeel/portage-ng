/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% =============================================================================
%  Hostname-specific configuration - imac-pro.local
% =============================================================================


% -----------------------------------------------------------------------------
%  Host-specific paths
% -----------------------------------------------------------------------------

% Installed package database (vdb), graph output directory and the
% gentoo-prefix emerge-vp wrapper used by --graph emerge.

config:pkg_directory('/Volumes/Disk 1/Repository/pkg').
config:graph_directory('/Volumes/Disk 1/Graph').
config:emerge_vp_path('/Volumes/Disk 1/gentoo-prefix/bin/emerge-vp').


% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:-  portage:newinstance(repository).
:-  portage:init('/Volumes/Disk 1/Repository/portage-git','/Volumes/Disk 1/Repository/portage-git/metadata/md5-cache',
               'https://github.com/gentoo-mirror/gentoo','git','eapi').
:-  kb:register(portage).


% -----------------------------------------------------------------------------
%  Installed package database snapshot (vdb layout)
% -----------------------------------------------------------------------------

:- pkg:newinstance(repository).
:- pkg:init('/Volumes/Disk 1/Repository/pkg','', '', 'local','vdb').
:- kb:register(pkg).


% -----------------------------------------------------------------------------
%  Local distfiles directory
% -----------------------------------------------------------------------------

:- distfiles:newinstance(repository).
:- distfiles:init('/Volumes/Disk 1/Distfiles/distfiles','', '', 'local','distfiles').
:- kb:register(distfiles).


% -----------------------------------------------------------------------------
%  Gentoo Bugzilla - paginated REST sync into Knowledge/bugs.qlf
% -----------------------------------------------------------------------------

:- bugzilla:newinstance(repository).
:- config:installation_dir(Dir),
   os:compose_path([Dir,'Knowledge/bugs.qlf'],Cache),
   bugzilla:init('/Volumes/Disk 1/Repository/bugzilla',Cache,
                 'https://bugs.gentoo.org','rest','bugzilla').
:- kb:register(bugzilla).

config:repository_sync_limit(bugzilla, 1).


% -----------------------------------------------------------------------------
%  Overlay repository - local sync
% -----------------------------------------------------------------------------

% :- overlay:newinstance(repository).
% :- overlay:init('/Volumes/Disk 1/Repository/overlay',
%                 '/Volumes/Disk 1/Repository/overlay/metadata/md5-cache',
%                 '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi').
% :- kb:register(overlay).