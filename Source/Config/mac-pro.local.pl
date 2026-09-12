/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% =============================================================================
%  Hostname-specific configuration - mac-pro.local
% =============================================================================


% -----------------------------------------------------------------------------
%  Host-specific paths
% -----------------------------------------------------------------------------

% Installed package database (vdb), graph output directory and the
% gentoo-prefix emerge-vp wrapper used by --graph emerge.

config:pkg_directory('/Volumes/Storage/Repository/pkg').
config:graph_directory('/Volumes/Storage/Graph').
config:emerge_vp_path('/Volumes/Storage/gentoo-prefix/bin/emerge-vp').


% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).
:- portage:init('/Volumes/Storage/Repository/portage-git','/Volumes/Storage/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).

% -----------------------------------------------------------------------------
%  Installed package database snapshot (vdb layout)
% -----------------------------------------------------------------------------

:- pkg:newinstance(repository).
:- pkg:init('/Volumes/Storage/Repository/pkg','', '', 'local','vdb').
:- kb:register(pkg).


% -----------------------------------------------------------------------------
%  Local distfiles directory
% -----------------------------------------------------------------------------

:- distfiles:newinstance(repository).
:- distfiles:init('/Volumes/Storage/Distfiles/distfiles','', '', 'local','distfiles').
:- kb:register(distfiles).


% -----------------------------------------------------------------------------
%  Gentoo Bugzilla - paginated REST sync into Knowledge/bugs.qlf
% -----------------------------------------------------------------------------

:- bugzilla:newinstance(repository).
:- config:installation_dir(Dir),
   os:compose_path([Dir,'Knowledge/bugs.qlf'],Cache),
   bugzilla:init('/Volumes/Storage/Repository/bugzilla',Cache,
                 'https://bugs.gentoo.org','rest','bugzilla').
:- kb:register(bugzilla).

config:repository_sync_limit(bugzilla, 1).

% Trusted LAN distfiles mirror (cleartext). Tried before the public
% https mirror when curl_allow_http is enabled.
config:mirror_url('http://mac-pro.local/distfiles').
:- retractall(config:curl_allow_http(_)).
config:curl_allow_http(true).


% -----------------------------------------------------------------------------
%  Overlay repository - local sync
% -----------------------------------------------------------------------------

:- overlay:newinstance(repository).
:- overlay:init('/Volumes/Storage/Repository/overlay',
                '/Volumes/Storage/Repository/overlay/metadata/md5-cache',
                '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi').
:- kb:register(overlay).


% -----------------------------------------------------------------------------
%  Github code repository - sync via git
% -----------------------------------------------------------------------------

%:- swipl:newinstance(repository).
%:- swipl:init('/Volumes/Storage/Repository/swipl-devel',
%              '/Volumes/Storage/Repository/swipl-devel/metadata',
%              'https://github.com/swi-prolog/swipl-devel','git','cmake').
%:- kb:register(swipl).


% -----------------------------------------------------------------------------
%  Github code repository - sync via git
% -----------------------------------------------------------------------------

%:- linux:newinstance(repository).
%:- linux:init('/Volumes/Storage/Repository/linux',
%              '/Volumes/Storage/Repository/linux/metadata',
%              'https://github.com/torvalds/linux','git','cmake').
%:- kb:register(linux).