/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% =============================================================================
%  Hostname-specific configuration - macbook-pro.local
% =============================================================================


% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).
:- portage:init('/Users/pvdabeel/Repository/portage-git','/Users/pvdabeel/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).


% -----------------------------------------------------------------------------
%  Installed package database snapshot (vdb layout)
% -----------------------------------------------------------------------------

:- pkg:newinstance(repository).
:- pkg:init('/Users/pvdabeel/Repository/pkg','', '', 'local','vdb').
:- kb:register(pkg).


% -----------------------------------------------------------------------------
%  Local distfiles directory
% -----------------------------------------------------------------------------

:- distfiles:newinstance(repository).
:- distfiles:init('/Users/pvdabeel/Repository/portage-git/distfiles','', '', 'local','distfiles').
:- kb:register(distfiles).


% -----------------------------------------------------------------------------
%  Ebuild command (Gentoo Prefix wrapper)
% -----------------------------------------------------------------------------

:- asserta(config:ebuild_command('/Users/pvdabeel/gentoo-prefix/bin/ebuild-prefix')).


% -----------------------------------------------------------------------------
%  Overlay repository - local sync
% -----------------------------------------------------------------------------

:- overlay:newinstance(repository).
:- overlay:init('/Users/pvdabeel/Repository/overlay',
                 '/Users/pvdabeel/Repository/overlay/metadata/md5-cache',
                 '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi').
:- kb:register(overlay).