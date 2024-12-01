
% -----------------------------------------------
% Hostname-specific configuration - mac-pro.local
% -----------------------------------------------


% Portage repository - sync via git
% ---------------------------------
:- portage:newinstance(repository).
:- portage:init('/Volumes/Storage/Repository/portage-git','/Volumes/Storage/Repository/portage-git/metadata/md5-cache',
                'https://github.com/gentoo-mirror/gentoo','git','eapi').
:- kb:register(portage).


% Overlay repository - local sync
% -------------------------------
% :- overlay:newinstance(repository).
% :- overlay:init('/Volumes/Storage/Repository/overlay',
%                 '/Volumes/Storage/Repository/overlay/metadata/md5-cache',
%                 '/Users/pvdabeel/Desktop/Prolog/Repository/overlay/','rsync','eapi').
% :- kb:register(overlay).
