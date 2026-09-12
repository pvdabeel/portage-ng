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
%  Host-specific paths (optional)
% -----------------------------------------------------------------------------

% Uncomment and adjust in your own Source/Config/<host>.pl. Callers guard
% these with current_predicate/1, so leaving them undefined is safe:
% features that need them (vdb contents, --graph, --graph emerge, build
% time estimation) simply skip their work.

% config:pkg_directory('/var/db/pkg').
% config:graph_directory('/root/Graph').
% config:emerge_vp_path('/opt/local/gentoo-prefix/bin/emerge-vp').


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


% -----------------------------------------------------------------------------
%  Local distfiles directory
% -----------------------------------------------------------------------------

:- distfiles:newinstance(repository).

:- config:installation_dir(Dir),
   os:compose_path([Dir,'Repository/portage-git/distfiles'],Distdir),
   distfiles:init(Distdir,'', '', 'local','distfiles').
:- kb:register(distfiles).