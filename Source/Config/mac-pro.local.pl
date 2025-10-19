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
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).
:- portage:init('/Volumes/Storage/Repository/portage-git','/Volumes/Storage/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).


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
