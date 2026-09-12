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
%  /etc/portage configuration directory
% -----------------------------------------------------------------------------
%
% Real /etc/portage. userconfig:load reads make.conf, package.use,
% package.mask, package.unmask, package.accept_keywords, package.license
% from this directory. builder:execute_suggestion writes prover-derived
% overrides into the package.{use,unmask,accept_keywords}/00portage-ng-auto
% file under it.

config:portage_confdir('/etc/portage').


% -----------------------------------------------------------------------------
%  Host-specific paths
% -----------------------------------------------------------------------------

% Installed package database (vdb) and graph output directory. No
% config:emerge_vp_path/1 here: traditional emerge is available natively,
% so --graph emerge falls back to a clear warning if requested.

config:pkg_directory('/var/db/pkg').
config:graph_directory('/root/Graph').


% -----------------------------------------------------------------------------
%  Portage repository - sync via git
% -----------------------------------------------------------------------------

:- portage:newinstance(repository).
:- portage:init('/usr/portage','/usr/portage/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).


% -----------------------------------------------------------------------------
%  Installed package database snapshot (vdb layout)
% -----------------------------------------------------------------------------

:- pkg:newinstance(repository).
:- pkg:init('/var/db/pkg','', '', 'local','vdb').
:- kb:register(pkg).


% -----------------------------------------------------------------------------
%  Local distfiles directory
% -----------------------------------------------------------------------------

:- distfiles:newinstance(repository).
:- distfiles:init('/var/cache/distfiles','', '', 'local','distfiles').
:- kb:register(distfiles).


% -----------------------------------------------------------------------------
%  Binary package cache (gpkg multi-instance)
% -----------------------------------------------------------------------------
%
% Location: directory containing the per-CPV gpkg.tar files (one subtree
%           per category, e.g. /srv/.../binpkgs/app-misc/jq/jq-1.8.1-9.gpkg.tar).
% Cache:    full path to the RFC822-style `Packages` index file at the
%           root of that directory. binpkg_index:parse_file reads this file
%           during repository:sync(kb).
%
% Repository is populated externally by tinderbox-ng matrix sessions
% (FEATURES=buildpkg) and by emerge's bintree.inject(). This config just
% tells portage-ng where to look.

:- binpkg:newinstance(repository).
:- binpkg:init('/srv/tinderbox-ng/shared/binpkgs',
               '/srv/tinderbox-ng/shared/binpkgs/Packages',
               '', 'local', 'binpkg').
:- kb:register(binpkg).


% -----------------------------------------------------------------------------
%  Overlay repository - local sync
% -----------------------------------------------------------------------------

% :- overlay:newinstance(repository).
% :- overlay:init('/root/repository/overlay',
%                 '/root/repository/overlay/metadata/md5-cache',
%                 '/root/prolog/Repository/overlay/','rsync','eapi').
% :- kb:register(overlay).