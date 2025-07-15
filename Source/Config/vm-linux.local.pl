/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele
  
  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% =============================================================================
%  Hostname-specific configuration - vm-linux.local
% =============================================================================


% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).
:- portage:init('/usr/portage','/usr/portage/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).


% -----------------------------------------------------------------------------
%  Overlay repository - local sync
% -----------------------------------------------------------------------------

% :- overlay:newinstance(repository).
% :- overlay:init('/root/repository/overlay',
%                 '/root/repository/overlay/metadata/md5-cache',
%                 '/root/prolog/Repository/overlay/','rsync','eapi').
% :- kb:register(overlay).
