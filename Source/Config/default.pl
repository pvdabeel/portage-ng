/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

% =============================================================================
%  Default configuration
% =============================================================================

% Only used when no hostname specific configuration file is found

% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).

:- config:installation_dir(Dir),
   os:compose_path([Dir,'Repository/portage-git'],Repository),
   os:compose_path([Dir,'Repository/portage-git/metadata/md5-cache'],Cache),
   portage:init(Repository,Cache,
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).