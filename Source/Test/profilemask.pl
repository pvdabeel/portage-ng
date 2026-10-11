/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/

/** <module> PROFILEMASK
Golden regression for profile package.mask application.

Applies every `package.mask` atom from `Knowledge/profile.qlf` through the
same `profile:apply_entry/3` path used at startup, collects the resulting
`preference:local_masked/2` entry ids, and compares them to the snapshot
embedded in this file (profile_mask_golden_ids/1). Needs
`Knowledge/kb.qlf` and `Knowledge/profile.qlf`.

Usage from the project wrapper:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/profilemask'), [if(true)]).
  profile_mask_golden_main.
  halt.
  PL

Regenerate the golden snapshot after an intentional change:

  ./Source/Application/Wrapper/portage-ng-dev --mode standalone --shell <<'PL'
  load_files(portage('Source/Test/profilemask'), [if(true)]).
  profile_mask_golden_update.
  halt.
  PL

The golden list pins a specific Portage tree snapshot (the tree from
which `Knowledge/kb.qlf` / `Knowledge/profile.qlf` were last generated).
After a `--sync` that changes profile package.mask entries a mismatch is
expected: review the diff and regenerate the snapshot.
*/

:- module(profilemask, [profile_mask_golden_validate/0,
                       profile_mask_golden_validate/1,
                       profile_mask_golden_main/0,
                       profile_mask_golden_update/0]).

:- use_module(library(lists)).
:- use_module(library(option)).
:- use_module(library(readutil)).
:- use_module(library(ordsets)).

% =============================================================================
%  PROFILEMASK declarations
% =============================================================================

% profile-mask-golden-begin
% Golden snapshot (465 entries). Regenerate: profile_mask_golden_update.

profile_mask_golden_ids([
  'acct-group/automx2-0-r3',
  'acct-user/automx2-0-r3',
  'app-accessibility/mbrola-3.3-r1',
  'app-admin/amazon-ec2-init-20101127-r2',
  'app-admin/mkosi-24.3',
  'app-admin/mkosi-25.3',
  'app-admin/systemdgenie-0.100.0_pre20241202',
  'app-antivirus/lkrg-0.9.9',
  'app-arch/stuffit-5.2.0.611-r1',
  'app-benchmarks/cpuburn-1.4a-r5',
  'app-crypt/libsecret-0.21.7-r1',
  'app-editors/emacs-18.59-r17',
  'app-emulation/crossover-bin-22.1.1',
  'app-emulation/crossover-bin-23.6.0',
  'app-emulation/crossover-bin-24.0.4',
  'app-emulation/crossover-bin-24.0.6',
  'app-emulation/crossover-bin-25.0.0',
  'app-emulation/q4wine-1.4.2',
  'app-emulation/virtualbox-kvm-7.1.14_pre20251103',
  'app-emulation/virtualbox-kvm-7.1.16_pre20251103-r1',
  'app-emulation/virtualbox-kvm-7.2.4_pre20251103',
  'app-emulation/virtualbox-kvm-7.2.6_pre20260201-r1',
  'app-misc/ca-certificates-20250419.3.112',
  'app-misc/screen-5.0.1',
  'app-office/orage-4.21.0',
  'app-text/calibre-8.15.0',
  'app-text/jabref-bin-4.3.1-r1',
  'dev-build/automake-1.11.6-r4',
  'dev-build/xfce4-dev-tools-4.21.0',
  'dev-cpp/glog-0.7.1',
  'dev-db/mysql-8.4.7',
  'dev-db/mysql-8.4.8',
  'dev-embedded/avr-libc-2.1.0',
  'dev-embedded/libftd2xx-1.4.33',
  'dev-embedded/openocd-0.12.0-r1',
  'dev-embedded/openocd-0.12.0-r2',
  'dev-embedded/openocd-9999',
  'dev-lang/tcl-9.0.3-r2',
  'dev-lang/tk-9.0.3-r2',
  'dev-libs/glib-2.86.4-r1',
  'dev-libs/glib-2.86.5-r1',
  'dev-libs/glib-2.88.0-r1',
  'dev-libs/gobject-introspection-1.86.0',
  'dev-libs/gobject-introspection-common-1.86.0',
  'dev-libs/libassuan-3.0.1-r1',
  'dev-libs/libintl-0.25.1',
  'dev-libs/libintl-0.26',
  'dev-libs/libixion-0.20.0',
  'dev-libs/liborcus-0.20.0',
  'dev-perl/Clone-0.480.0',
  'dev-perl/XML-Parser-2.510.0',
  'dev-php/PHP_Timer-5.0.3',
  'dev-python/amodem-1.15.6',
  'dev-python/autobahn-25.10.2',
  'dev-python/autobahn-25.11.1',
  'dev-python/betterproto-2.0.0_beta6',
  'dev-python/betterproto-2.0.0_beta7',
  'dev-python/calver-2025.10.20',
  'dev-python/click-didyoumean-0.3.1',
  'dev-python/csscompressor-0.9.5-r2',
  'dev-python/dparse-0.6.4',
  'dev-python/dunamai-1.26.0',
  'dev-python/flask-migrate-4.1.0',
  'dev-python/flask-sqlalchemy-3.1.1',
  'dev-python/ghp-import-2.1.0-r1',
  'dev-python/griffe-2.0.0',
  'dev-python/griffe-inherited-docstrings-1.1.3',
  'dev-python/grpclib-0.4.9',
  'dev-python/jsmin-3.0.1',
  'dev-python/markdown-exec-1.12.0',
  'dev-python/mergedeep-1.3.4-r1',
  'dev-python/mkdocs-1.6.0',
  'dev-python/mkdocs-1.6.1',
  'dev-python/mkdocs-autorefs-1.4.4',
  'dev-python/mkdocs-bootstrap-1.1.1-r1',
  'dev-python/mkdocs-bootswatch-1.1-r3',
  'dev-python/mkdocs-gen-files-0.6.0',
  'dev-python/mkdocs-get-deps-0.2.0',
  'dev-python/mkdocs-get-deps-0.2.1',
  'dev-python/mkdocs-get-deps-0.2.2',
  'dev-python/mkdocs-git-authors-plugin-0.10.0',
  'dev-python/mkdocs-git-revision-date-localized-plugin-1.5.0',
  'dev-python/mkdocs-git-revision-date-localized-plugin-1.5.1',
  'dev-python/mkdocs-htmlproofer-plugin-1.5.0',
  'dev-python/mkdocs-i18n-0.4.6',
  'dev-python/mkdocs-material-9.7.1',
  'dev-python/mkdocs-material-9.7.2',
  'dev-python/mkdocs-material-9.7.3',
  'dev-python/mkdocs-material-9.7.4',
  'dev-python/mkdocs-material-9.7.5',
  'dev-python/mkdocs-material-extensions-1.3.1',
  'dev-python/mkdocs-minify-plugin-0.8.0',
  'dev-python/mkdocs-monorepo-plugin-1.1.2',
  'dev-python/mkdocs-pymdownx-material-extras-2.8',
  'dev-python/mkdocs-redirects-1.2.2',
  'dev-python/mkdocs-static-i18n-1.3.0',
  'dev-python/mkdocs-static-i18n-1.3.1',
  'dev-python/mkdocstrings-1.0.3',
  'dev-python/mkdocstrings-python-2.0.3',
  'dev-python/mpi4py-3.1.5',
  'dev-python/paginate-0.5.7',
  'dev-python/pipdeptree-2.23.4',
  'dev-python/pipdeptree-2.29.0',
  'dev-python/pipdeptree-2.30.0',
  'dev-python/pipdeptree-2.31.0',
  'dev-python/pipdeptree-2.32.0',
  'dev-python/pipdeptree-2.33.0',
  'dev-python/pipdeptree-2.34.0',
  'dev-python/pipenv-2024.0.2-r1',
  'dev-python/pipx-1.8.0',
  'dev-python/pipx-1.9.0',
  'dev-python/plette-2.1.0',
  'dev-python/plette-2.1.0-r1',
  'dev-python/pockets-0.9.1-r3',
  'dev-python/pygments-ansi-color-0.3.0',
  'dev-python/pygobject-3.52.3',
  'dev-python/pygobject-3.54.3',
  'dev-python/pygobject-3.54.5',
  'dev-python/pyqt6-6.11.0',
  'dev-python/pyqt6-webengine-6.11.0',
  'dev-python/python-systemd-235',
  'dev-python/pythonfinder-2.1.0',
  'dev-python/pythonfinder-3.0.0',
  'dev-python/pythonfinder-3.0.2',
  'dev-python/pythonfinder-3.0.3',
  'dev-python/pyyaml-env-tag-1.1',
  'dev-python/readtime-3.0.0',
  'dev-python/sigstore-protobuf-specs-0.3.2',
  'dev-python/sigstore-protobuf-specs-0.4.1',
  'dev-python/sigstore-protobuf-specs-0.4.2',
  'dev-python/sigstore-protobuf-specs-0.4.3',
  'dev-python/sigstore-protobuf-specs-0.5.0',
  'dev-python/simsimd-6.5.16',
  'dev-python/testtools-2.8.2',
  'dev-python/txaio-25.12.2',
  'dev-python/uritools-6.0.1',
  'dev-python/uv-dynamic-versioning-0.13.0',
  'dev-qt/qt-docs-6.11.0_p202603180534',
  'dev-qt/qt3d-6.11.0',
  'dev-qt/qt5compat-6.11.0',
  'dev-qt/qtbase-6.11.0',
  'dev-qt/qtcharts-6.11.0',
  'dev-qt/qtconnectivity-6.11.0',
  'dev-qt/qtdeclarative-6.11.0',
  'dev-qt/qtgraphs-6.11.0',
  'dev-qt/qthttpserver-6.11.0',
  'dev-qt/qtimageformats-6.11.0',
  'dev-qt/qtlanguageserver-6.11.0',
  'dev-qt/qtlocation-6.11.0',
  'dev-qt/qtmultimedia-6.11.0',
  'dev-qt/qtnetworkauth-6.11.0',
  'dev-qt/qtpositioning-6.11.0',
  'dev-qt/qtquick3d-6.11.0',
  'dev-qt/qtquicktimeline-6.11.0',
  'dev-qt/qtremoteobjects-6.11.0',
  'dev-qt/qtscxml-6.11.0',
  'dev-qt/qtsensors-6.11.0',
  'dev-qt/qtserialbus-6.11.0',
  'dev-qt/qtserialport-6.11.0',
  'dev-qt/qtshadertools-6.11.0',
  'dev-qt/qtspeech-6.11.0',
  'dev-qt/qtsvg-6.11.0',
  'dev-qt/qttools-6.11.0',
  'dev-qt/qttranslations-6.11.0',
  'dev-qt/qtvirtualkeyboard-6.11.0',
  'dev-qt/qtwayland-6.11.0',
  'dev-qt/qtwebchannel-6.11.0',
  'dev-qt/qtwebengine-6.11.0',
  'dev-qt/qtwebsockets-6.11.0',
  'dev-qt/qtwebview-6.11.0',
  'dev-tcltk/tablelist-6.15.1',
  'dev-util/bpf-linker-0.9.15-r1',
  'dev-util/gdbus-codegen-2.86.4',
  'dev-util/gdbus-codegen-2.86.5',
  'dev-util/gdbus-codegen-2.88.0',
  'dev-util/glib-utils-2.86.4',
  'dev-util/glib-utils-2.86.5',
  'dev-util/glib-utils-2.88.0',
  'dev-util/mdds-3.0.0',
  'dev-util/mig-1.8_p20231217',
  'dev-util/mig-1.8_p20260123',
  'dev-util/mig-9999',
  'dev-util/mingw64-runtime-13.0.0',
  'dev-util/mingw64-runtime-14.0.0',
  'games-action/badland-121-r2',
  'games-action/beathazardultra-20130308-r2',
  'games-action/brutal-legend-gog-2.0.0.3',
  'games-action/brutal-legend-hb-20130615-r3',
  'games-action/crimsonland-1.3.5',
  'games-action/guacamelee-20231012',
  'games-action/heretic2-1.06c-r2',
  'games-action/heretic2-demo-1.06a-r2',
  'games-action/hotline-miami-1.0.9a_p20140221-r3',
  'games-action/intrusion2-1.024-r2',
  'games-action/psychonauts-gog-2.0.0.4',
  'games-action/psychonauts-hb-20130506',
  'games-action/shadowgrounds-bin-0_p1-r1',
  'games-action/shadowgrounds-survivor-bin-0_p1-r1',
  'games-action/solar2-1.10-r1',
  'games-action/swordandsworcery-1.02-r5',
  'games-action/trine-enchanted-edition-2.12.508-r4',
  'games-action/trine2-2.01.425-r2',
  'games-arcade/aquaria-1.1.3-r3',
  'games-arcade/barbarian-bin-1.01-r3',
  'games-arcade/dynamitejack-1.0.23-r3',
  'games-arcade/gish-demo-1.6-r1',
  'games-arcade/jardinains-2.0-r4',
  'games-arcade/thinktanks-demo-1.1-r4',
  'games-emulation/gens-2.15.5-r2',
  'games-emulation/vgba-4.8-r1',
  'games-emulation/zinc-1.1-r1',
  'games-emulation/zsnes-2.1.0',
  'games-fps/etqw-bin-1.5-r4',
  'games-fps/etqw-data-1.0-r1',
  'games-fps/etqw-demo-2.0_p1-r4',
  'games-fps/glxquake-bin-0-r3',
  'games-fps/legends-0.4.1.43-r2',
  'games-fps/sauerbraten-2020.12.29',
  'games-fps/soldieroffortune-1.06a-r2',
  'games-fps/ut2003-2225-r6',
  'games-fps/ut2003-demo-2206-r5',
  'games-fps/ut2004-demo-3334-r3',
  'games-misc/little-inferno-20130509-r1',
  'games-misc/papers-please-1.1.65',
  'games-puzzle/braid-gog-2.0.0.3-r1',
  'games-puzzle/braid-hb-20150611-r1',
  'games-puzzle/triptych-1.16',
  'games-roguelike/adom-3.3.3-r2',
  'games-rpg/baldurs-gate-ee-2.6.6.0.47291-r1',
  'games-rpg/broken-age-2.4.800398',
  'games-rpg/costume-quest-2.0.0.3-r1',
  'games-rpg/dear-esther-20130608-r1',
  'games-rpg/dungeon-defenders-20130305-r1',
  'games-rpg/eschalon-book-1-demo-106-r1',
  'games-rpg/wasteland2-1.9.0.13-r2',
  'games-server/etqw-ded-1.5-r1',
  'games-strategy/darwinia-1.43',
  'games-strategy/dominions2-2.16-r1',
  'games-strategy/knights-demo-1.32-r4',
  'games-strategy/spaz-1.605-r1',
  'gnome-base/librsvg-2.40.21-r1',
  'gnome-extra/gnome-logs-43.0',
  'gnome-extra/gnome-logs-45.0',
  'gnome-extra/gnome-logs-49.0',
  'gnome-extra/office-runner-1.0.3',
  'kde-apps/libkcddb-common-25.12.2',
  'kde-apps/libksane-common-25.12.2',
  'kde-frameworks/purpose-kaccounts-services-6.22.0',
  'kde-frameworks/purpose-kaccounts-services-6.23.0',
  'kde-misc/kio-gdrive-common-25.12.2',
  'kde-plasma/drkonqi-6.5.5',
  'kde-plasma/drkonqi-6.6.3',
  'kde-plasma/drkonqi-6.6.4',
  'kde-plasma/plasma-login-manager-6.6.3',
  'kde-plasma/plasma-login-manager-6.6.4',
  'llvm-runtimes/libatomic-stub-0',
  'llvm-runtimes/libgcc-19.1.7',
  'llvm-runtimes/libgcc-19.1.7-r1',
  'llvm-runtimes/libgcc-20.1.8',
  'llvm-runtimes/libgcc-21.1.8',
  'llvm-runtimes/libgcc-22.1.2',
  'llvm-runtimes/libgcc-22.1.3',
  'llvm-runtimes/libgcc-23.0.0.9999',
  'llvm-runtimes/libgcc-23.0.0_pre20260331',
  'mail-mta/postfix-3.12_pre20260410',
  'media-fonts/culmus-0.133-r1',
  'media-libs/libopenaptx-0.2.1-r1',
  'media-libs/libopenaptx-9999',
  'media-libs/openexr-3.4.4',
  'media-plugins/kodi-game-libretro-dosbox-9999',
  'media-plugins/kodi-game-libretro-nestopia-9999',
  'media-sound/aucdtect-0.8.2-r1',
  'media-video/binkplayer-1.99w',
  'media-video/tsmuxer-2.7.0',
  'media-video/vlc-4.0.0_pre20260320',
  'net-dns/ldns-tools-0.1',
  'net-dns/ldns-tools-0.2',
  'net-im/gajim-2.4.4',
  'net-im/gajim-2.4.5',
  'net-libs/libnsl-0-r2',
  'net-libs/libupnp-1.18.4',
  'net-libs/rpcsvc-proto-0-r1',
  'net-mail/automx2-2025.1',
  'net-mail/automx2-2026.1',
  'net-misc/openntpd-6.8_p1-r2',
  'net-misc/ps3mediaserver-1.90.1-r2',
  'net-print/cndrvcups-common-lb-3.70-r1',
  'net-print/cndrvcups-lb-3.70-r1',
  'net-vpn/microsoft-azurevpnclient-3.0.0',
  'perl-core/Params-Check-0.380.0-r3',
  'sci-biology/foldingathome-7.6.13-r1',
  'sci-biology/foldingathome-7.6.21',
  'sci-chemistry/cara-bin-1.8.4-r2',
  'sci-libs/amd-3.0.3',
  'sci-libs/btf-2.0.3',
  'sci-libs/camd-3.0.3',
  'sci-libs/ccolamd-3.0.3',
  'sci-libs/cholmod-4.0.3',
  'sci-libs/colamd-3.0.3',
  'sci-libs/cxsparse-4.0.3',
  'sci-libs/klu-2.0.3',
  'sci-libs/ldl-3.0.3',
  'sci-libs/spqr-3.0.3',
  'sci-libs/suitesparseconfig-7.0.0',
  'sci-libs/umfpack-6.1.0',
  'sci-physics/bullet-3.22b',
  'sys-apps/gentoo-systemd-integration-9-r2',
  'sys-apps/gentoo-systemd-integration-9999',
  'sys-apps/intune-portal-1.2603.31',
  'sys-apps/musl-locales-0.1.0-r3',
  'sys-apps/systemd-258.3',
  'sys-apps/systemd-259.3-r2',
  'sys-apps/systemd-259.4-r1',
  'sys-apps/systemd-260-r2',
  'sys-apps/systemd-260.1',
  'sys-apps/systemd-9999',
  'sys-apps/systemd-initctl-2',
  'sys-apps/systemd-initctl-4',
  'sys-apps/systemd-readahead-216',
  'sys-block/wait-for-dri-devices-rules-1',
  'sys-boot/plymouth-24.004.60-r1',
  'sys-devel/binutils-2.32-r2',
  'sys-devel/binutils-2.33.1-r1',
  'sys-devel/binutils-2.34-r2',
  'sys-devel/binutils-2.35.2',
  'sys-devel/binutils-2.36.1-r2',
  'sys-devel/binutils-2.37_p1-r2',
  'sys-devel/binutils-2.38-r2',
  'sys-devel/binutils-2.39-r5',
  'sys-devel/binutils-2.40-r9',
  'sys-devel/binutils-2.41-r5',
  'sys-devel/binutils-2.42-r2',
  'sys-devel/binutils-2.43-r2',
  'sys-devel/binutils-hppa64-2.37_p1-r2',
  'sys-devel/binutils-hppa64-2.38-r2',
  'sys-devel/binutils-hppa64-2.39-r5',
  'sys-devel/binutils-hppa64-2.40-r7',
  'sys-devel/binutils-hppa64-2.41-r5',
  'sys-devel/binutils-hppa64-2.42-r2',
  'sys-devel/binutils-hppa64-2.43-r2',
  'sys-devel/clang-crossdev-wrappers-16',
  'sys-devel/clang-crossdev-wrappers-17',
  'sys-devel/clang-crossdev-wrappers-18',
  'sys-devel/clang-crossdev-wrappers-19',
  'sys-devel/clang-crossdev-wrappers-20',
  'sys-devel/clang-crossdev-wrappers-21',
  'sys-devel/clang-crossdev-wrappers-22',
  'sys-devel/clang-crossdev-wrappers-23',
  'sys-devel/gcc-10.5.0',
  'sys-devel/gcc-8.5.0-r2',
  'sys-devel/gcc-9.5.0',
  'sys-devel/gettext-0.25.1',
  'sys-devel/gettext-0.26',
  'sys-devel/gettext-1.0',
  'sys-devel/kgcc64-10.5.0',
  'sys-devel/nvptx-tools-0_pre20240809',
  'sys-devel/nvptx-tools-0_pre20260402',
  'sys-devel/nvptx-tools-9999',
  'sys-fs/atari-fdisk-0.7.1.5.4',
  'sys-fs/atari-fdisk-0.7.1.5.4-r1',
  'sys-kernel/gnumach-1.8_p20260224',
  'sys-kernel/gnumach-1.8_p20260330',
  'sys-kernel/gnumach-9999',
  'sys-kernel/hurd-0.9_p20251029',
  'sys-kernel/hurd-0.9_p20260331',
  'sys-kernel/hurd-9999',
  'sys-kernel/rumpkernel-0_pre20250111_p6',
  'sys-kernel/rumpkernel-9999',
  'sys-libs/argp-standalone-1.5.0',
  'sys-libs/binutils-libs-2.34-r2',
  'sys-libs/binutils-libs-2.35.2',
  'sys-libs/binutils-libs-2.36.1-r2',
  'sys-libs/binutils-libs-2.37_p1-r2',
  'sys-libs/binutils-libs-2.38-r2',
  'sys-libs/binutils-libs-2.39-r5',
  'sys-libs/binutils-libs-2.40-r7',
  'sys-libs/binutils-libs-2.41-r5',
  'sys-libs/binutils-libs-2.42-r2',
  'sys-libs/binutils-libs-2.43-r3',
  'sys-libs/error-standalone-1.0',
  'sys-libs/error-standalone-2.0-r1',
  'sys-libs/fts-standalone-1.2.7',
  'sys-libs/fts-standalone-1.2.7-r1',
  'sys-libs/glibc-2.19-r3',
  'sys-libs/glibc-2.31-r7',
  'sys-libs/glibc-2.32-r8',
  'sys-libs/glibc-2.33-r14',
  'sys-libs/glibc-2.34-r14',
  'sys-libs/glibc-2.35-r11',
  'sys-libs/glibc-2.36-r8',
  'sys-libs/glibc-2.37-r10',
  'sys-libs/glibc-2.38-r13',
  'sys-libs/glibc-2.39-r11',
  'sys-libs/glibc-2.40-r11',
  'sys-libs/libucontext-1.3.1',
  'sys-libs/libucontext-1.3.2',
  'sys-libs/libucontext-1.3.3',
  'sys-libs/musl-1.2.5-r8',
  'sys-libs/musl-1.2.6',
  'sys-libs/musl-9999',
  'sys-libs/newlib-4.5.0.20241231-r1',
  'sys-libs/newlib-4.6.0.20260123',
  'sys-libs/newlib-9999',
  'sys-libs/obstack-standalone-1.2.3',
  'sys-libs/queue-standalone-0.1-r1',
  'sys-libs/rpmatch-standalone-1.0-r1',
  'sys-power/libacpica-0_pre20220331_p6',
  'sys-power/libacpica-9999',
  'sys-power/sandmann-bin-1.3.1',
  'sys-power/sandmann-bin-1.4.1-r1',
  'sys-process/systemd-cron-2.4.0',
  'sys-process/systemd-cron-2.4.1',
  'sys-process/systemd-cron-2.5.1',
  'virtual/libcrypt-1-r2',
  'virtual/perl-HTTP-Tiny-0.88.0',
  'virtual/perl-HTTP-Tiny-0.90.0',
  'virtual/perl-IO-Zlib-1.150.0-r1',
  'virtual/perl-Locale-Maketext-1.330.0-r2',
  'virtual/perl-Math-BigInt-FastCalc-0.501.800',
  'virtual/perl-Math-BigInt-FastCalc-0.502.0',
  'virtual/perl-Math-BigRat-2.3.2',
  'virtual/perl-Math-BigRat-2.5.2',
  'virtual/perl-Math-Complex-1.620.0-r1',
  'virtual/perl-Math-Complex-1.630.0',
  'virtual/perl-Module-Load-Conditional-0.740.0-r4',
  'virtual/perl-Params-Check-0.380.0-r15',
  'virtual/perl-Parse-CPAN-Meta-2.150.10-r9',
  'virtual/perl-Term-ReadLine-1.170.0-r9',
  'virtual/perl-Unicode-Collate-1.310.0-r3',
  'virtual/perl-Unicode-Normalize-1.320.0-r2',
  'virtual/perl-bignum-0.670.0-r1',
  'www-misc/profile-sync-daemon-6.35',
  'www-misc/profile-sync-daemon-6.50',
  'www-misc/profile-sync-daemon-9999',
  'www-plugins/chrome-binary-plugins-149.0.7779.3_alpha',
  'www-servers/nginx-unit-1.34.2',
  'www-servers/nginx-unit-1.35.0-r1',
  'x11-drivers/nvidia-drivers-390.157',
  'x11-drivers/nvidia-drivers-470.256.02-r2',
  'x11-drivers/nvidia-drivers-580.94.18',
  'x11-drivers/nvidia-drivers-595.44.05',
  'x11-misc/emacs-desktop-mail-1.3',
  'x11-themes/fluent-icon-theme-2025.08.21',
  'xfce-base/exo-4.21.0-r1',
  'xfce-base/garcon-4.21.0',
  'xfce-base/libxfce4ui-4.21.2',
  'xfce-base/libxfce4ui-4.21.3',
  'xfce-base/libxfce4ui-4.21.4',
  'xfce-base/libxfce4ui-4.21.7',
  'xfce-base/thunar-4.21.4',
  'xfce-base/thunar-4.21.5',
  'xfce-base/tumbler-4.21.0',
  'xfce-base/tumbler-4.21.1',
  'xfce-base/xfce4-appfinder-4.21.0',
  'xfce-base/xfce4-appfinder-4.21.1',
  'xfce-base/xfce4-panel-4.21.1',
  'xfce-base/xfce4-power-manager-4.21.0',
  'xfce-base/xfce4-power-manager-4.21.1',
  'xfce-base/xfce4-session-4.21.0',
  'xfce-base/xfce4-session-4.21.1',
  'xfce-base/xfce4-settings-4.21.0-r1',
  'xfce-base/xfce4-settings-4.21.1',
  'xfce-base/xfconf-4.21.0',
  'xfce-base/xfconf-4.21.1',
  'xfce-base/xfconf-4.21.2'
]).

% profile-mask-golden-end


% -----------------------------------------------------------------------------
%  Public entry points
% -----------------------------------------------------------------------------

%! profile_mask_golden_validate is semidet.
%! profile_mask_golden_validate(+Options) is semidet.
%
% Compare profile-derived package masks against the golden snapshot.
% Fails when the masked entry set differs (unless update(true)).
%
% Options:
%   * update(Bool)  -- rewrite golden instead of comparing (default false)
%   * verbose(Bool) -- print sample diffs (default true on mismatch)

profile_mask_golden_validate :-
  profile_mask_golden_validate([]).

profile_mask_golden_validate(Options) :-
  ( once(profile_mask_golden_validate_(Options)) ->
      true
  ; halt(1)
  ).

profile_mask_golden_validate_(Options) :-
  option(update(Update), Options, false),
  option(verbose(Verbose), Options, true),
  profile_mask_golden_require_inputs,
  profile_mask_golden_masked_ids(MaskedIds),
  length(MaskedIds, N),
  ( Update == true ->
      profile_mask_golden_source_file(Path),
      profile_mask_golden_write_source(MaskedIds),
      format('profile-mask golden updated: ~w (~D entries)~n', [Path, N])
  ; profile_mask_golden_expected(Expected),
    length(Expected, NE),
    ( MaskedIds == Expected ->
        format('profile-mask golden OK (~D entries).~n', [N])
    ;   ord_subtract(Expected, MaskedIds, OnlyExpected),
        ord_subtract(MaskedIds, Expected, OnlyActual),
        length(OnlyExpected, NExp), length(OnlyActual, NAct),
        format('profile-mask golden FAIL: expected ~D, got ~D (~D only-in-golden, ~D only-in-actual).~n',
               [NE, N, NExp, NAct]),
        ( Verbose == true ->
            profile_mask_golden_print_sample('only in golden', OnlyExpected),
            profile_mask_golden_print_sample('only in actual', OnlyActual)
        ; true
        ),
        fail
    )
  ).


%! profile_mask_golden_main is det.
%
% Load kb, then validate against the golden snapshot.

profile_mask_golden_main :-
  kb:load,
  profile_mask_golden_validate.


%! profile_mask_golden_update is det.
%
% Load kb, then rewrite the golden snapshot in this file.

profile_mask_golden_update :-
  kb:load,
  profile_mask_golden_validate([update(true)]).


profile_mask_golden_source_file('Source/Test/profilemask.pl').


%! profile_mask_golden_expected(-Ids) is det.
%
% Sorted entry ids from the checked-in golden snapshot.

profile_mask_golden_expected(Ids) :-
  profile_mask_golden_ids(Golden),
  sort(Golden, Ids).


%! profile_mask_golden_write_source(+Ids) is det.
%
% Rewrite the `profile_mask_golden_ids/1` block in this file.

profile_mask_golden_write_source(Ids) :-
  profile_mask_golden_source_file(RelPath),
  config:working_dir(Dir),
  os:compose_path(Dir, RelPath, Path),
  read_file_to_string(Path, Content, [encoding(utf8)]),
  profile_mask_golden_replace_block(Content, Ids, NewContent),
  NewContent \== '',
  atomic_list_concat([Path, '.tmp'], TmpPath),
  setup_call_cleanup(
    open(TmpPath, write, Out, [encoding(utf8)]),
    format(Out, '~s', [NewContent]),
    close(Out)
  ),
  rename_file(TmpPath, Path).


profile_mask_golden_replace_block(Content, Ids, NewContent) :-
  profile_mask_golden_marker_begin(Begin),
  profile_mask_golden_marker_end(End),
  sub_string(Content, PrefixLen, BeginLen, _, Begin),
  sub_string(Content, EndBefore, EndLen, SuffixLen, End),
  EndBefore >= PrefixLen + BeginLen,
  sub_string(Content, 0, PrefixLen, _, Prefix),
  SuffixStart is EndBefore + EndLen,
  sub_string(Content, SuffixStart, SuffixLen, _, Suffix),
  profile_mask_golden_format_block(Ids, Block),
  string_concat(Prefix, Block, Temp),
  string_concat(Temp, Suffix, NewContent).


profile_mask_golden_marker_begin(Marker) :-
  atomic_list_concat(['% ', 'profile-mask', '-golden-begin', '\n'], Marker).


profile_mask_golden_marker_end(Marker) :-
  atomic_list_concat(['% ', 'profile-mask', '-golden-end', '\n'], Marker).


profile_mask_golden_format_block(Ids, Block) :-
  profile_mask_golden_marker_begin(Begin),
  profile_mask_golden_marker_end(End),
  length(Ids, N),
  profile_mask_golden_ids_list_lines(Ids, Lines),
  atomic_list_concat(Lines, "\n", Body),
  format(string(Header),
         '% Golden snapshot (~D entries). Regenerate: profile_mask_golden_update.~n',
         [N]),
  format(string(List), 'profile_mask_golden_ids([~n~s~n]).~n', [Body]),
  atomic_list_concat([Begin, Header, "\n", List, "\n", End], Block).


profile_mask_golden_ids_list_lines([], []).
profile_mask_golden_ids_list_lines([Last], [Line]) :-
  format(string(Line), "  ~q", [Last]).
profile_mask_golden_ids_list_lines([H|T], [Line|Rest]) :-
  T \== [],
  format(string(Line), "  ~q,", [H]),
  profile_mask_golden_ids_list_lines(T, Rest).


%! profile_mask_golden_require_inputs is det.
%
% Fail fast when kb/profile caches needed for the regression are missing.

profile_mask_golden_require_inputs :-
  ( current_predicate(cache:ordered_entry/5) ->
      true
  ;  throw(error(existence_error(procedure, cache:ordered_entry/5),
                 context(profile_mask_golden_validate/1,
                         'call kb:load before profile_mask_golden_validate/1')))
  ),
  ( profile:cache_load(_, _, _) ->
      true
  ;  throw(error(existence_error(source, 'Knowledge/profile.qlf'),
                 context(profile_mask_golden_validate/1,
                         'run --sync or build profile cache first')))
  ),
  ( current_predicate(profiledata:entry/3) ->
      true
  ;  throw(error(existence_error(procedure, profiledata:entry/3),
                 context(profile_mask_golden_validate/1, _)))
  ).


%! profile_mask_golden_masked_ids(-Ids) is det.
%
% Apply profile `package.mask` entries in cache order and return sorted ids.
% The live `preference:local_masked/2` facts (profile + user config) are
% snapshotted up front and restored afterwards, so running the golden
% regression does not clobber the session's mask state.

profile_mask_golden_masked_ids(Ids) :-
  findall(local_masked(SavedId, SavedRepo),
          preference:local_masked(SavedId, SavedRepo),
          Saved),
  setup_call_cleanup(
    retractall(preference:local_masked(_,_)),
    ( forall(profiledata:entry(package_mask, Atom, true),
             profile:apply_entry(package_mask, Atom, true)),
      findall(Id, preference:local_masked(Id, portage), Ids0),
      sort(Ids0, Ids)
    ),
    ( retractall(preference:local_masked(_,_)),
      forall(member(local_masked(SavedId, SavedRepo), Saved),
             assertz(preference:local_masked(SavedId, SavedRepo)))
    )
  ).


%! profile_mask_golden_print_sample(+Label, +Ids) is det.
%
% Print up to five sample ids from a diff list.

profile_mask_golden_print_sample(Label, Ids) :-
  length(Ids, N),
  ( N =:= 0 ->
      true
  ;   TopN is min(5, N),
      length(Sample, TopN),
      append(Sample, _, Ids),
      format('  ~w (~D):', [Label, N]),
      forall(member(Id, Sample), format(' ~w', [Id])),
      ( N > TopN -> format(' ...') ; true ),
      nl
  ).
