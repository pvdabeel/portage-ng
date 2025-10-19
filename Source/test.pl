/*

  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2025, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.

*/

/** <module> TEST
This module implements a few tests
*/

:- module(test, []).

:- dynamic failed/1.

% =============================================================================
%  TEST declarations
% =============================================================================

%! test:cases(?List)
%
% Declares a list of cases

test:investigating([
portage://'app-admin/ansible-12.0.0':run?{[]},
portage://'app-admin/ansible-11.9.0':run?{[]},
portage://'app-admin/ansible-core-2.18.6':run?{[]},
portage://'app-admin/ansible-core-2.18.3':run?{[]},
portage://'app-admin/awscli-1.42.45':run?{[]},
portage://'app-admin/awscli-1.42.40':run?{[]},
portage://'app-admin/awscli-1.42.35':run?{[]},
portage://'app-admin/awscli-1.42.25':run?{[]},
portage://'app-admin/awscli-1.42.21':run?{[]},
portage://'app-backup/backuppc-4.4.0-r3':run?{[]},
portage://'app-backup/backuppc-4.4.0-r2':run?{[]},
portage://'app-backup/backuppc-4.4.0-r1':run?{[]},
portage://'app-backup/backuppc-3.3.1-r6':run?{[]},
portage://'app-containers/docker-28.4.0':run?{[]},
portage://'app-editors/gedit-48.1':run?{[]},
portage://'app-editors/gedit-plugins-48.1':run?{[]},
portage://'app-editors/gnome-text-editor-48.3':run?{[]},
portage://'app-editors/neovim-9999':run?{[]},
portage://'app-editors/neovim-0.11.4':run?{[]},
portage://'app-editors/neovim-0.11.3':run?{[]},
portage://'app-editors/neovim-0.11.2':run?{[]},
portage://'app-metrics/ceph_exporter-4.2.5':run?{[]},
portage://'app-metrics/ceph_exporter-4.1.1-r1':run?{[]},
portage://'app-misc/piper-0.7-r1':run?{[]},
portage://'app-text/foliate-3.3.0-r1':run?{[]},
portage://'app-text/papers-48.5':run?{[]},
portage://'app-text/xapers-0.9.3':run?{[]},
portage://'dev-ada/VSS-25.0.0-r1':run?{[]},
portage://'dev-ada/ada_language_server-25.0.20241014-r4':run?{[]},
portage://'dev-ada/ada_libfswatch-2024.07.09-r1':run?{[]},
portage://'dev-ada/aws-25.1.0-r3':run?{[]},
portage://'dev-ada/gnatcoll-bindings-25.0.0-r1':run?{[]},
portage://'dev-ada/gnatcoll-core-25.0.0-r2':run?{[]},
portage://'dev-ada/gnatcoll-db-25.0.0-r2':run?{[]},
portage://'dev-ada/gnatdoc-25.0.0-r4':run?{[]},
portage://'dev-ada/gnatformat-25.0.0-r1':run?{[]},
portage://'dev-ada/gpr-25.0.0-r3':run?{[]},
portage://'dev-ada/gpr-24.2.0':run?{[]},
portage://'dev-ada/gpr-24.0.0-r2':run?{[]},
portage://'dev-ada/gprbuild-25.0.0-r5':run?{[]},
portage://'dev-ada/lal-refactor-25.0.0-r2':run?{[]},
portage://'dev-ada/langkit-25.0.0-r5':run?{[]},
portage://'dev-ada/langkit-24.0.0-r2':run?{[]},
portage://'dev-ada/langkit-contrib-25.0.0-r2':run?{[]},
portage://'dev-ada/libadalang-25.0.0-r1':run?{[]},
portage://'dev-ada/libadalang-24.0.0-r3':run?{[]},
portage://'dev-ada/libadalang-tools-25.0.0-r2':run?{[]},
portage://'dev-ada/libgpr-25.0.0-r3':run?{[]},
portage://'dev-ada/markdown-25.0.0-r2':run?{[]},
portage://'dev-ada/prettier-ada-25.0.0-r2':run?{[]},
portage://'dev-ada/templates-parser-25.0.0-r4':run?{[]},
portage://'dev-ada/templates-parser-24.0.0-r1':run?{[]},
portage://'dev-debug/gef-9999':run?{[]},
portage://'dev-debug/gef-2025.01':run?{[]},
portage://'dev-debug/gef-2024.06':run?{[]},
portage://'dev-debug/gef-2023.08':run?{[]},
portage://'dev-debug/pwndbg-99999999':run?{[]},
portage://'dev-debug/pwndbg-20250530':run?{[]},
portage://'dev-debug/pwndbg-20250418-r1':run?{[]},
portage://'dev-debug/pwndbg-20250418':run?{[]},
portage://'dev-debug/pwndbg-20250219':run?{[]},
portage://'dev-erlang/p1_pgsql-1.1.32':run?{[]},
portage://'dev-erlang/xmpp-1.10.1':run?{[]},
portage://'dev-java/commons-validator-1.10.0':run?{[]},
portage://'dev-lang/spark-2024.01.11-r2':run?{[]},
portage://'dev-libs/gobject-introspection-1.86.0':run?{[]},
portage://'dev-lisp/cl-ppcre-unicode-2.1.2':run?{[]},
portage://'dev-perl/Filesys-SmbClient-3.200.0-r5':run?{[]},
portage://'dev-php/pecl-http-4.2.6':run?{[]},
portage://'dev-python/boto3-1.40.45':run?{[]},
portage://'dev-python/boto3-1.40.40':run?{[]},
portage://'dev-python/boto3-1.40.35':run?{[]},
portage://'dev-python/boto3-1.40.30':run?{[]},
portage://'dev-python/boto3-1.40.25':run?{[]},
portage://'dev-python/boto3-1.40.21':run?{[]},
portage://'dev-python/elasticsearch-9.0.4':run?{[]},
portage://'dev-python/elasticsearch-9.0.2':run?{[]},
portage://'dev-python/gdb-pt-dump-9999':run?{[]},
portage://'dev-python/gdb-pt-dump-0.0.0_p20250105':run?{[]},
portage://'dev-python/gdb-pt-dump-0.0.0_p20240401':run?{[]},
portage://'dev-python/myst-parser-4.0.1-r1':run?{[]},
portage://'dev-python/myst-parser-4.0.1':run?{[]},
portage://'dev-python/notebook-7.4.7':run?{[]},
portage://'dev-python/notebook-7.3.3':run?{[]},
portage://'dev-python/pycurl-7.45.7':run?{[]},
portage://'dev-python/pycurl-7.45.6':run?{[]},
portage://'dev-python/pycurl-requests-0.5.1':run?{[]},
portage://'dev-python/pycurl-requests-0.5.0-r1':run?{[]},
portage://'dev-python/pyopenssl-25.3.0':run?{[]},
portage://'dev-python/pyopenssl-25.2.0':run?{[]},
portage://'dev-python/pypi-attestations-0.0.27':run?{[]},
portage://'dev-python/python-tests-3.13.7':run?{[]},
portage://'dev-python/python-tests-0.3.13.5_p1':run?{[]},
portage://'dev-python/qiskit-aer-0.17.2':run?{[]},
portage://'dev-python/spyder-6.0.8':run?{[]},
portage://'dev-python/spyder-kernels-3.1.0_beta2':run?{[]},
portage://'dev-python/spyder-kernels-3.1.0_beta1':run?{[]},
portage://'dev-python/spyder-kernels-3.1.0':run?{[]},
portage://'dev-python/spyder-kernels-3.0.5':run?{[]},
portage://'dev-python/spyder-line-profiler-0.4.1':run?{[]},
portage://'dev-python/spyder-notebook-0.6.2':run?{[]},
portage://'dev-python/spyder-unittest-0.7.0':run?{[]},
portage://'dev-ruby/actioncable-7.1.5.2':run?{[]},
portage://'dev-ruby/actionmailbox-7.1.5.2':run?{[]},
portage://'dev-ruby/actionmailer-7.1.5.2':run?{[]},
portage://'dev-ruby/actionpack-7.1.5.2':run?{[]},
portage://'dev-ruby/actiontext-7.1.5.2':run?{[]},
portage://'dev-ruby/actionview-7.1.5.2':run?{[]},
portage://'dev-ruby/activejob-7.1.5.2':run?{[]},
portage://'dev-ruby/activestorage-7.1.5.2':run?{[]},
portage://'dev-ruby/ammeter-1.1.7':run?{[]},
portage://'dev-ruby/dry-struct-1.8.0':run?{[]},
portage://'dev-ruby/maxitest-5.5.0':run?{[]},
portage://'dev-ruby/neovim-ruby-client-0.10.0':run?{[]},
portage://'dev-ruby/rails-7.1.5.2':run?{[]},
portage://'dev-ruby/railties-7.1.5.2':run?{[]},
portage://'dev-ruby/ruby-cairo-gobject-4.2.4':run?{[]},
portage://'dev-ruby/ruby-gdk3-4.2.4':run?{[]},
portage://'dev-ruby/ruby-pango-4.2.4':run?{[]},
portage://'dev-ruby/ruby-poppler-4.2.4':run?{[]},
portage://'dev-util/buildbot-9999':run?{[]},
portage://'dev-util/buildbot-3.11.9':run?{[]},
portage://'dev-util/buildbot-3.11.1':run?{[]},
portage://'dev-util/buildbot-3.11.0':run?{[]},
portage://'dev-util/buildbot-console-view-3.11.9':run?{[]},
portage://'dev-util/buildbot-console-view-3.11.1':run?{[]},
portage://'dev-util/buildbot-console-view-3.11.0':run?{[]},
portage://'dev-util/buildbot-react-console-view-3.11.9':run?{[]},
portage://'dev-util/buildbot-react-console-view-3.11.1':run?{[]},
portage://'dev-util/buildbot-react-console-view-3.11.0':run?{[]},
portage://'dev-util/buildbot-waterfall-view-3.11.9':run?{[]},
portage://'dev-util/buildbot-waterfall-view-3.11.1':run?{[]},
portage://'dev-util/buildbot-waterfall-view-3.11.0':run?{[]},
portage://'dev-util/coccigrep-1.21':run?{[]},
portage://'dev-util/gnome-builder-48.2':run?{[]},
portage://'dev-util/gnome-builder-47.2-r2':run?{[]},
portage://'dev-util/gnome-builder-47.2-r1':run?{[]},
portage://'dev-util/pkgcheck-0.10.34':run?{[]},
portage://'dev-util/rpmdevtools-9.6':run?{[]},
portage://'dev-vcs/gitolite-3.6.13':run?{[]},
portage://'dev-vcs/gitolite-gentoo-3.6.13.1':run?{[]},
portage://'dev-vcs/gitolite-gentoo-3.6.6.1-r3':run?{[]},
portage://'dev-vcs/tortoisehg-6.9-r1':run?{[]},
portage://'dev-vcs/tortoisehg-6.9':run?{[]},
portage://'games-strategy/naev-0.12.6':run?{[]},
portage://'games-strategy/naev-0.12.5':run?{[]},
portage://'gnome-base/gnome-45.2':run?{[]},
portage://'gnome-base/gnome-control-center-48.4':run?{[]},
portage://'gnome-base/gnome-control-center-48.3':run?{[]},
portage://'gnome-base/gnome-control-center-47.7':run?{[]},
portage://'gnome-base/gnome-control-center-47.6':run?{[]},
portage://'gnome-base/gnome-core-apps-45.2':run?{[]},
portage://'gnome-base/gnome-light-45.2':run?{[]},
portage://'gnome-base/gnome-shell-48.4':run?{[]},
portage://'gnome-base/gnome-shell-48.3-r1':run?{[]},
portage://'gnome-base/nautilus-48.4.1':run?{[]},
portage://'gnome-base/nautilus-48.3':run?{[]},
portage://'gnome-extra/gnome-calculator-48.1':run?{[]},
portage://'gnome-extra/gnome-calendar-48.1':run?{[]},
portage://'gnome-extra/gnome-firmware-47.0-r1':run?{[]},
portage://'gnome-extra/gnome-shell-extension-weather-oclock-49.0':run?{[]},
portage://'gnome-extra/gnome-shell-frippery-48.0':run?{[]},
portage://'gui-apps/railway-2.8.2':run?{[]},
portage://'kde-apps/kalgebra-25.08.1':run?{[]},
portage://'kde-apps/kalgebra-25.04.3':run?{[]},
portage://'kde-apps/kde-apps-meta-25.08.1':run?{[]},
portage://'kde-apps/kde-apps-meta-25.04.3':run?{[]},
portage://'kde-apps/kdeedu-meta-25.08.1':run?{[]},
portage://'kde-apps/kdeedu-meta-25.04.3-r2':run?{[]},
portage://'kde-apps/kdenetwork-filesharing-25.08.1':run?{[]},
portage://'kde-apps/kdenetwork-filesharing-25.04.3':run?{[]},
portage://'kde-apps/kdenetwork-meta-25.08.1':run?{[]},
portage://'kde-apps/kdeutils-meta-25.08.1':run?{[]},
portage://'kde-misc/kio-gdrive-25.08.1':run?{[]},
portage://'kde-plasma/plasma-meta-6.4.5':run?{[]},
portage://'mate-extra/caja-admin-0.0.5':run?{[]},
portage://'media-gfx/ahoviewer-2.0.0_pre20241230':run?{[]},
portage://'media-gfx/ahoviewer-2.0.0_pre20220827-r2':run?{[]},
portage://'media-gfx/alembic-1.8.8':run?{[]},
portage://'media-gfx/alembic-1.8.6-r1':run?{[]},
portage://'media-gfx/entangle-3.0-r3':run?{[]},
portage://'media-gfx/eog-plugins-44.1':run?{[]},
portage://'media-gfx/freecad-1.0.1':run?{[]},
portage://'media-gfx/krita-6.0.0_alpha_pre20250902':run?{[]},
portage://'media-gfx/krita-5.2.13':run?{[]},
portage://'media-gfx/loupe-48.1-r2':run?{[]},
portage://'media-libs/libquvi-0.9.4-r101':run?{[]},
portage://'media-sound/jalv-1.6.9_pre20250802':run?{[]},
portage://'media-sound/rhythmbox-3.4.8-r2':run?{[]},
portage://'media-sound/rhythmbox-3.4.7-r6':run?{[]},
portage://'media-video/cclive-0.9.3-r2':run?{[]},
portage://'media-video/pitivi-2023.03-r2':run?{[]},
portage://'media-video/totem-43.2':run?{[]},
portage://'media-video/totem-43.1':run?{[]},
portage://'net-analyzer/gr-fosphor-9999':run?{[]},
portage://'net-analyzer/gr-fosphor-0.0_p20210108-r2':run?{[]},
portage://'net-analyzer/gvm-25.5.0':run?{[]},
portage://'net-analyzer/gvmd-26.3.0':run?{[]},
portage://'net-analyzer/nmbscan-1.2.5-r1':run?{[]},
portage://'net-dns/hash-slinger-3.4':run?{[]},
portage://'net-fs/samba-4.23.0':run?{[]},
portage://'net-fs/samba-4.22.4':run?{[]},
portage://'net-fs/samba-4.22.3':run?{[]},
portage://'net-fs/samba-4.21.8':run?{[]},
portage://'net-fs/samba-4.21.7':run?{[]},
portage://'net-fs/samba-4.20.8-r1':run?{[]},
portage://'net-fs/smbnetfs-0.6.3':run?{[]},
portage://'net-im/ejabberd-25.04':run?{[]},
portage://'net-im/fractal-12.1-r1':run?{[]},
portage://'net-im/gajim-2.3.6':run?{[]},
portage://'net-im/gajim-2.3.5':run?{[]},
portage://'net-im/prosody-13.0.2':run?{[]},
portage://'net-im/prosody-modules-9999':run?{[]},
portage://'net-im/prosody-modules-0_pre20241231':run?{[]},
portage://'net-misc/dropbear-2025.88-r1':run?{[]},
portage://'net-misc/dropbear-2025.87':run?{[]},
portage://'net-misc/gns3-gui-2.2.52':run?{[]},
portage://'net-misc/gns3-gui-2.2.51':run?{[]},
portage://'net-misc/gns3-server-2.2.52':run?{[]},
portage://'net-misc/gns3-server-2.2.51':run?{[]},
portage://'net-misc/modemmanager-1.24.0':run?{[]},
portage://'net-misc/seafile-9.0.15':run?{[]},
portage://'net-misc/seafile-9.0.13':run?{[]},
portage://'net-misc/seafile-client-9.0.15':run?{[]},
portage://'net-misc/seafile-client-9.0.13':run?{[]},
portage://'net-misc/smb4k-4.0.4':run?{[]},
portage://'net-misc/smbc-1.2.2-r4':run?{[]},
portage://'net-misc/tuba-0.10.2':run?{[]},
portage://'net-misc/tuba-0.10.1':run?{[]},
portage://'net-nds/nsscache-0.49-r1':run?{[]},
portage://'net-nds/smbldap-tools-0.9.10-r1':run?{[]},
portage://'net-news/liferea-1.16.5':run?{[]},
portage://'net-news/liferea-1.15.8-r2':run?{[]},
portage://'net-news/liferea-1.15.5-r2':run?{[]},
portage://'net-p2p/deluge-9999':run?{[]},
portage://'net-p2p/deluge-2.2.0':run?{[]},
portage://'net-p2p/deluge-2.1.1-r7':run?{[]},
portage://'net-p2p/deluge-2.1.1-r6':run?{[]},
portage://'net-p2p/deluge-2.1.1-r5':run?{[]},
portage://'net-print/hplip-3.25.6-r1':run?{[]},
portage://'net-print/hplip-3.25.6':run?{[]},
portage://'net-print/hplip-3.25.2':run?{[]},
portage://'net-print/hplip-plugin-3.25.6':run?{[]},
portage://'net-print/hplip-plugin-3.25.2':run?{[]},
portage://'net-vpn/eduvpn-client-4.4.0-r1':run?{[]},
portage://'net-wireless/gqrx-9999':run?{[]},
portage://'net-wireless/gqrx-2.17.7':run?{[]},
portage://'net-wireless/gqrx-2.17.6':run?{[]},
portage://'net-wireless/gqrx-2.17.2-r1':run?{[]},
portage://'net-wireless/gqrx-scanner-1.0.4':run?{[]},
portage://'net-wireless/gr-ieee802154-9999':run?{[]},
portage://'net-wireless/gr-ieee802154-0.0_p20230828':run?{[]},
portage://'net-wireless/gr-ieee802154-0.0_p20210719-r4':run?{[]},
portage://'net-wireless/gr-iqbal-9999':run?{[]},
portage://'net-wireless/gr-iqbal-0.38.3':run?{[]},
portage://'net-wireless/gr-iqbal-0.38.2_p20210108-r1':run?{[]},
portage://'net-wireless/gr-osmosdr-9999':run?{[]},
portage://'net-wireless/gr-osmosdr-0.2.6':run?{[]},
portage://'net-wireless/gr-paint-0.0_p20250824':run?{[]},
portage://'net-wireless/gr-paint-0.0_p20230427-r2':run?{[]},
portage://'net-wireless/gr-rds-9999':run?{[]},
portage://'net-wireless/gr-rds-0.0_p20250404':run?{[]},
portage://'net-wireless/gr-rds-0.0_p20220804-r3':run?{[]},
portage://'net-wireless/urh-9999':run?{[]},
portage://'net-wireless/urh-2.9.8-r2':run?{[]},
portage://'sci-astronomy/stellarium-25.3':run?{[]},
portage://'sci-astronomy/stellarium-25.2':run?{[]},
portage://'sci-astronomy/stellarium-25.1':run?{[]},
portage://'sci-electronics/kicad-meta-9.0.4':run?{[]},
portage://'sci-electronics/kicad-meta-9.0.2':run?{[]},
portage://'sci-geosciences/gnome-maps-48.7':run?{[]},
portage://'sci-geosciences/gnome-maps-48.6':run?{[]},
portage://'sci-geosciences/qgis-9999':run?{[]},
portage://'sci-geosciences/qgis-3.42.3':run?{[]},
portage://'sci-libs/fetk-1.5':run?{[]},
portage://'sci-libs/mc-1.5-r1':run?{[]},
portage://'sci-mathematics/alectryon-1.4.0-r2':run?{[]},
portage://'sci-misc/boinc-7.24.1-r2':run?{[]},
portage://'sci-ml/accelerate-1.7.0':run?{[]},
portage://'sci-ml/accelerate-1.6.0-r5':run?{[]},
portage://'sci-ml/datasets-3.5.0':run?{[]},
portage://'sci-ml/evaluate-0.4.3-r2':run?{[]},
portage://'sci-ml/fastai-2.7.19':run?{[]},
portage://'sci-ml/pytorch-2.8.0':run?{[]},
portage://'sci-ml/pytorch-2.7.1-r1':run?{[]},
portage://'sci-ml/torchdata-0.11.0':run?{[]},
portage://'sci-ml/torchvision-0.21.0-r2':run?{[]},
portage://'sci-ml/transformers-4.56.2':run?{[]},
portage://'sci-ml/transformers-4.55.4':run?{[]},
portage://'sci-physics/rivet-9999':run?{[]},
portage://'sci-physics/rivet-4.1.1':run?{[]},
portage://'sci-physics/rivet-4.1.0':run?{[]},
portage://'sci-physics/rivet-4.0.2':run?{[]},
portage://'sci-physics/rivet-3.1.11':run?{[]},
portage://'sci-visualization/pythonprop-0.30.1_p20240217-r1':run?{[]},
portage://'sec-policy/selinux-accountsd-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-amanda-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-android-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-apache-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-apcupsd-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-awstats-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-bitlbee-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-chromium-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-collectd-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-crio-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-cups-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-cvs-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-dbskk-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-devicekit-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-djbdns-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-dkim-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-docker-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-dropbox-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-evolution-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-finger-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-fprintd-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-git-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-gpg-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-kubernetes-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-modemmanager-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-mozilla-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-munin-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-nagios-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-nginx-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-nut-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-pan-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-phpfpm-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-podman-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-qemu-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-rootlesskit-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-rtkit-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-smokeping-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-squid-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-tcpd-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-telnet-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-thunderbird-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-uucp-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-vmware-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-webalizer-2.20250618-r1':run?{[]},
portage://'sec-policy/selinux-xscreensaver-2.20250618-r1':run?{[]},
portage://'sys-apps/busybox-9999':run?{[]},
portage://'sys-apps/busybox-1.36.1-r3':run?{[]},
portage://'sys-apps/xdg-desktop-portal-gnome-48.0':run?{[]},
portage://'sys-auth/sssd-2.11.1':run?{[]},
portage://'sys-auth/sssd-2.9.7':run?{[]},
portage://'sys-block/targetcli-fb-2.1.58-r1':run?{[]},
portage://'sys-cluster/ceph-20.1.0-r2':run?{[]},
portage://'sys-cluster/ceph-19.2.3':run?{[]},
portage://'sys-cluster/ceph-19.2.2-r6':run?{[]},
portage://'sys-cluster/ceph-19.2.2-r4':run?{[]},
portage://'sys-cluster/ceph-18.2.7':run?{[]},
portage://'sys-cluster/ceph-18.2.4-r4':run?{[]},
portage://'sys-kernel/dracut-crypt-ssh-1.0.8-r1':run?{[]},
portage://'sys-kernel/virtme-ng-1.38':run?{[]},
portage://'sys-kernel/virtme-ng-1.36':run?{[]},
portage://'sys-kernel/virtme-ng-1.33':run?{[]},
portage://'sys-libs/ldb-2.9.2':run?{[]},
portage://'sys-libs/tevent-0.17.1':run?{[]},
portage://'sys-libs/tevent-0.16.2':run?{[]},
portage://'sys-libs/tevent-0.16.1':run?{[]},
portage://'virtual/ldb-2.11.0':run?{[]},
portage://'virtual/ldb-2.10.0':run?{[]},
portage://'virtual/ldb-2.9.2':run?{[]},
portage://'www-apps/gitea-1.23.8':run?{[]},
portage://'www-apps/nanoc-4.13.4':run?{[]},
portage://'www-apps/nanoc-4.13.3':run?{[]},
portage://'x11-misc/gpaste-3.42.5':run?{[]},
portage://'xfce-base/thunar-4.21.2':run?{[]},
portage://'xfce-base/thunar-4.21.1':run?{[]},
portage://'xfce-base/xfce4-appfinder-4.21.0':run?{[]},
portage://'xfce-base/xfce4-panel-4.21.0':run?{[]},
portage://'xfce-base/xfce4-power-manager-4.21.0':run?{[]},
portage://'xfce-base/xfce4-session-4.21.0':run?{[]},
portage://'xfce-base/xfce4-settings-4.21.0-r1':run?{[]}]).



test:cases([overlay://'test01/web-1.0':run?{[]},
            overlay://'test02/web-2.0':run?{[]},
            overlay://'test03/web-1.0':run?{[]},
            overlay://'test04/web-1.0':run?{[]},
            overlay://'test05/web-1.0':run?{[]},
            overlay://'test06/web-1.0':run?{[]},
            overlay://'test07/web-1.0':run?{[]},
            overlay://'test08/web-1.0':run?{[]},
            overlay://'test09/os-1.0':run?{[]},
            overlay://'test10/os-1.0':run?{[]},
            overlay://'test11/os-1.0':run?{[]},
            overlay://'test12/web-1.0':run?{[]},
            overlay://'test13/web-1.0':run?{[]},
            overlay://'test14/web-1.0':run?{[]},
            overlay://'test15/web-1.0':run?{[]},
            overlay://'test16/web-1.0':run?{[]},
            overlay://'test17/web-1.0':run?{[]},
            overlay://'test18/web-1.0':run?{[]},
            overlay://'test19/web-1.0':run?{[]},
            overlay://'test20/web-1.0':run?{[]},
            overlay://'test21/web-1.0':run?{[]},
            overlay://'test22/web-1.0':run?{[]},
            overlay://'test23/web-1.0':run?{[]},
            overlay://'test24/web-1.0':run?{[]},
            overlay://'test25/web-1.0':run?{[]},
            overlay://'test26/web-1.0':run?{[]},
            overlay://'test27/web-1.0':run?{[]},
            overlay://'test28/web-1.0':run?{[]},
            overlay://'test29/web-1.0':run?{[]},
            overlay://'test30/web-1.0':run?{[]},
            overlay://'test31/web-1.0':run?{[]},
            overlay://'test32/os-1.0':run?{[]},
            overlay://'test33/app-1.0':run?{[]},
            overlay://'test34/app-1.0':run?{[]},
            overlay://'test35/app-1.0':run?{[]},
            overlay://'test36/app-1.0':run?{[]},
            overlay://'test37/app-1.0':run?{[]},
            overlay://'test38/app-1.0':run?{[]},
            overlay://'test39/app-1.0':run?{[]},
            overlay://'test40/os-1.0':run?{[]},
            overlay://'test41/app-1.0':run?{[]},
            overlay://'test42/app-1.0':run?{[]},
            overlay://'test43/app-1.0':run?{[]},
            overlay://'test44/app-1.0':run?{[]},
            overlay://'test45/app-1.0':run?{[]},
            overlay://'test46/app-1.0':run?{[]},
            overlay://'test47/api-docs-1.0':run?{[]},
            overlay://'test48/app-1.0':run?{[]},
            overlay://'test49/app-1.0':run?{[]},
            overlay://'test50/app-1.0':run?{[]},
            overlay://'test51/app-1.0':install?{[]},
            overlay://'test52/app-1.0':run?{[]},
            overlay://'test53/app-1.0':run?{[]},
            overlay://'test54/app-1.0':run?{[]}
            ]).

test:basics([overlay://'test01/os-1.0':download?{[]},
             overlay://'test01/os-1.0':install?{[]},
             overlay://'test01/os-1.0':run?{[]},
             overlay://'test01/app-1.0':download?{[]},
             overlay://'test01/app-1.0':install?{[]}]).


test:problem([portage://'app-backup/backuppc-4.4.0-r3':run?{[]},
              portage://'dev-libs/glib-2.84.0':run?{[]},
              portage://'dev-haskell/cabal-3.4.1.0-r1':run?{[]}]).

test:slotreq([overlay://'test41/app-1.0':run?{[]},
              overlay://'test42/app-1.0':run?{[]},
              overlay://'test43/app-1.0':run?{[]},
              overlay://'test44/app-1.0':run?{[]}]).

test:diamond([overlay://'test45/app-1.0':run?{[]}]).

test:doublediamond([overlay://'test46/app-1.0':run?{[]}]).

test:softuse([overlay://'test49/app-1.0':run?{[]}]).

test:pms([overlay://'test50/app-1.0':run?{[]}]).

test:simple([overlay://'test51/app-1.0':install?{[]}]).

test:new([%overlay://'test54/app-1.0':run?{[]},
          overlay://'test55/app-1.0':run?{[]}]).
          %overlay://'test56/app-1.0':run?{[]}]).

test:failures([overlay://'test46/app-1.0':run?{[]},
             overlay://'test49/app-1.0':run?{[]}]).

%test:slow([portage://'dev-erlang/p1_pgsql-1.1.32':run?{[]}]).
%           portage://'dev-erlang/xmpp-1.10.1':run?{[]}]).



%! test:run(+Atom)
%
% Runs specific test cases and outputs individual results to files in Tests directory

test:run(Cases) :-
  % Ensure Tests directory exists
  retractall(test:failed(_)),
  config:working_dir(Dir),
  atomic_list_concat([Dir, '/Source/Tests'], TestsDir),
  (exists_directory(TestsDir) -> true ; make_directory(TestsDir)),
  Inner =.. [Cases,List],
  Outer =.. [:, test, Inner],
  call(Outer),
  forall(member(Case,List),
         (test:run_single_case(Case);
          assertz(test:failed(Case)),
          message:color(red),message:color(bold),
          message:print('false'),nl,
          message:color(normal),message:style(normal),nl,nl)),
  nl,nl,
  (test:failed(_)
   -> (message:color(lightred),message:color(bold),
       message:print('The following test cases failed:'),nl,nl,
       message:color(red),
       forall(test:failed(Case),
              (write(' * '),writeln(Case))),
       message:color(normal),message:style(normal),nl,nl)
   ;  true).


%! test:run(application)
%
% Runs application tests

test:run(application) :-
  message:header(['Testing reader: ']),
  reader:test(portage),nl,
  message:header(['Testing parser: ']),
  parser:test(portage),nl,
  message:header(['Testing prover: ']),
  prover:test(portage),nl,
  message:header(['Testing planner: ']),
  planner:test(portage),nl,
  message:header(['Testing builder: ']),
  builder:test(portage).


%! test:run_single_case(+Atom)
%
% Runs a single test case and outputs result to file with proper error handling

test:run_single_case(Repo://Id:Action?{Context}) :-
  writeln(Repo://Id:Action?{Context}),
  config:working_dir(Dir),
  split_string(Id,'/','',[Category,Package]),
  Repo:get_location(RepoLoc),
  atomic_list_concat([RepoLoc,'/',Category,'/description.txt'],Description),
  atomic_list_concat([RepoLoc,'/',Category,'/emerge-',Category,'.log'],EmergeLog),
  atomic_list_concat([Repo, Category,Package, Action], '_', TestName),
  atomic_list_concat([Dir, '/Source/Tests/', TestName, '.txt'], FilePath),
  open(FilePath, write, Stream),
  prover:prove(Repo://Id:Action?{Context},t,Proof,t,Model,t,Constraints,t,Triggers),
  with_output_to(Stream,
       ((writeln(Repo://Id:Action?{Context}),
         planner:plan(Proof,Triggers,t,Plan),
         nl,
         message:color(cyan),
         writeln('Proof:'),
         message:color(normal),
         write_proof(Proof),
         nl,
         message:color(cyan),
         writeln('Model:'),
         message:color(normal),
         write_model(Model),
         nl,
         message:color(cyan),
         writeln('Constraints:'),
         message:color(normal),
         write_constraints(Constraints),
         nl,
         message:color(cyan),
         writeln('Triggers:'),
         message:color(normal),
         write_triggers(Triggers),
         nl,
         message:color(cyan),
         writeln('Plan:'),
         message:color(normal),
         write_plan(Plan),
         nl,
         printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan));
        (Failure = true,
         message:color(red),
         message:style(bold),
         message:print('false'),nl,
         message:color(normal),
         message:style(normal),
         nl,nl))),
  close(Stream),
  (Failure == true
   -> message:color(red),message:color(bold),
      message:print('false'),nl,
      message:color(normal),message:style(normal),nl,nl,true
   ;  (message:hl,message:color(cyan),
       test:write_description(Description),
       message:color(normal),message:hl,
       printer:print([Repo://Id:Action?{Context}],Model,Proof,Plan),
       %nl,nl)).
       message:header('Gentoo emerge output:'),
       test:write_description(EmergeLog),nl,nl;true)).


%! write_description(+File)
%
% Writes description to current output

write_description(File) :-
    setup_call_cleanup(
        open(File, read, In),
        copy_stream_data(In, user_output),
        close(In)
    ).

%! write_proof(+Proof)
%
% Writes proof information to current output

write_proof(Proof) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Proof,Value),
     (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_model(+Model)
%
% Writes model information to current output

write_model(Model) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Model,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_constraints(+Constraints)
%
% Writes constraints information to current output

write_constraints(Constraints) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Constraints,Value),
       (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).

%! write_triggers(+Triggers)
%
% Writes triggers information to current output

write_triggers(Triggers) :-
  message:color(darkgray),
  forall(gen_assoc(Key,Triggers,Value),
      (write(Key),write(' - '),write(Value),nl)),nl,
  message:color(cyan).


%! write_plan(+Plan)
%
% Writes plan information to current output

write_plan(Plan) :-
  message:color(darkgray),
  forall(member(Step,Plan),
      writeln(Step)),nl,nl,
  message:color(normal).
