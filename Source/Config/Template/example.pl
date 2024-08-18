
% ------------------------------------------
% Hostname-specific configuration - EXAMPLES
% ------------------------------------------


% Example: Portage repository - sync vie web tarball
% --------------------------------------------------
% :- portage:newinstance(repository).
% :- portage:init('/Users/pvdabeel/Repository/portage-web','/Users/pvdabeel/Repository/portage-web/metadata/md5-cache',
%                 'http://distfiles.gentoo.org/releases/snapshots/current/portage-latest.tar.bz2','http','eapi').
% :- kb:register(portage).


% Example: Portage repository - sync via rsync
% --------------------------------------------
% :- portage:newinstance(repository).
% :- portage:init('/Users/pvdabeel/Repository/portage-rsync','/Users/pvdabeel/Repository/portage-rsync/metadata/md5-cache',
%                 'rsync://rsync.gentoo.org/gentoo-portage','rsync','eapi').
% :- kb:register(portage).


% Example: Portage repository - sync via git
% ------------------------------------------
% :- portage:newinstance(repository).
% :- portage:init('/Users/pvdabeel/portage-git','/Users/pvdabeel/Repository/portage-git/metadata/md5-cache',
%                 'https://github.com/gentoo-mirror/gentoo','git','eapi').
% :- kb:register(portage).


% Example: Overlay repository - local sync
% ----------------------------------------
% :- overlay:newinstance(repository).
% :- overlay:init('/Users/pvdabeel//Repository/overlay',
%                 '/Users/pvdabeel/Repository/overlay/metadata/md5-cache',
%                 '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi').
% :- kb:register(overlay).


% Example: Github code repository - sync via git
% ----------------------------------------------
% :- swipl:newinstance(repository).
% :- swipl:init('/Users/pvdabeel/Repository/swipl-devel',
%               '/Users/pvdabeel/Repository/swipl-devel/metadata',
%               'https://github.com/swi-prolog/swipl-devel','git','cmake').
% :- kb:register(swipl).


% Example: Github code repository - sync via git
% ----------------------------------------------
% :- linux:newinstance(repository).
% :- linux:init('/Users/pvdabeel/Repository/linux',
%               '/Users/pvdabeel/Repository/linux/metadata',
%               'https://github.com/torvalds/linux','git','cmake').
% :- kb:register(linux).


