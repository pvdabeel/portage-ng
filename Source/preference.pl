/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2024, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PREFERENCE
The preferences module contains build specific preferences
*/

:- module(preference, []).

:- dynamic preference:known_broken/1.
:- dynamic preference:positive_use/1.
:- dynamic preference:negative_usa/1.
:- dynamic preference:use_expand_hidden/1.
:- dynamic preference:masked/1.

% ***********************
% PREFERENCE declarations
% ***********************


%! preference:env_cflags(?Cflags)
%
% Fact which defines the CFLAGS environment variable

preference:env_cflags('-O3 -march=native -pipe').


%! preference:env_cxxflags(?Cxxflags)
%
% Fact which defines the CXXFLAGS environment variable

preference:env_cxxflags('-O3 -march=native -pipe').


%! preference:env_chost(?Chost)
%
% Fact which defines the CHOST environment variable

preference:env_chost('x86_64-pc-linux-gnu').


%! preference:env_makeopts(?Makeopts)
%
% Fact which defines the MAKEOPTS variable

preference:env_makeopts('-j36').


%! preference:env_features(?Features)
%
% Fact which defines the FEATURES variable

preference:env_features('sign -ccache -buildpkg -sandbox -usersandbox -ebuild-locks parallel-fetch parallel-install').


%! preference:accept_keywords(?Keyword)
%
% Fact which defines the ACCEPT_KEYWORDS variable

preference:accept_keywords(stable(amd64)).
preference:accept_keywords(unstable(amd64)).



%! preference:use(?Use)
%
% Fact which defines the USE flags to be used

%preference:use(['X','a52','aac','aacplus','aalib','abi_x86_64','account','acl','aio','alsa','alsa_cards_ens1371','amd64','apache2_modules_auth_basic','apache2_modules_authn_core','apache2_modules_authn_file','apache2_modules_authz_core','apache2_modules_authz_host','apache2_modules_dir','apache2_modules_mime','apache2_modules_socache_shmcb','apache2_modules_unixd','apng','avahi','bzip2','cairo','calligra_features_karbon','calligra_features_sheets','calligra_features_words','cli','collectd_plugins_df','collectd_plugins_interface','collectd_plugins_irq','collectd_plugins_load','collectd_plugins_memory','collectd_plugins_rrdtool','collectd_plugins_swap','collectd_plugins_syslog','container','cpu_flags_x86_aes','cpu_flags_x86_avx','cpu_flags_x86_avx2','cpu_flags_x86_avx512bw','cpu_flags_x86_avx512cd','cpu_flags_x86_avx512dq','cpu_flags_x86_avx512f','cpu_flags_x86_avx512vl','cpu_flags_x86_f16c','cpu_flags_x86_fma3','cpu_flags_x86_mmx','cpu_flags_x86_mmxext','cpu_flags_x86_pclmul','cpu_flags_x86_popcnt','cpu_flags_x86_sse','cpu_flags_x86_sse2','cpu_flags_x86_sse3','cpu_flags_x86_sse4_1','cpu_flags_x86_sse4_2','cpu_flags_x86_ssse3','crypt','cvs','cxx','dbus','directfb','dri','dts','elibc_glibc','elogind','fbcondecor','fontconfig','fortran','gdbm','gif','git','glitz','gmp','gpg','gpm','http','iconv','icu','imap','input_devices_evdev','input_devices_keyboard','input_devices_mouse','input_devices_vmmouse','ipv6','jpeg','jpeg2k','json','kernel_linux','libkms','libtirpc','md5sum','mdnsresponder-compat','messages','mmx','mmxext','mp3','ncurses','nova','npm','nptl','object','opengl','openmp','openssl','pam','pcre','pcre16','pkcs11','png','policykit','pop','proxy','python','python_single_target_python3_7','python_targets_python3_7','qemu','readline','ruby_targets_ruby25','seccomp','sidebar','smime','smp','smtp','split-usr','sqlite','sse','sse2','sse3','sse4','sse4_2','ssh','ssl','ssse3','svg','tcpd','threads','tiff','truetype','unicode','userland_GNU','video_cards_vesa','video_cards_vga','video_cards_vmware','x264','x265','x86emu','xa','xattr','xcb','xkb','xlib-xcb','xvid','zeroconf','zlib']).

preference:positive_use('a52').
preference:positive_use('aac').
preference:positive_use('aacplus').
preference:positive_use('aalib').
preference:positive_use('abi_x86_64').
preference:positive_use('account').
preference:positive_use('acl').
preference:positive_use('aio').
preference:positive_use('alsa').
preference:positive_use('alsa_cards_ens1371').
preference:positive_use('amd64').
preference:positive_use('apache2_modules_auth_basic').
preference:positive_use('apache2_modules_authn_core').
preference:positive_use('apache2_modules_authn_file').
preference:positive_use('apache2_modules_authz_core').
preference:positive_use('apache2_modules_authz_host').
preference:positive_use('apache2_modules_dir').
preference:positive_use('apache2_modules_mime').
preference:positive_use('apache2_modules_socache_shmcb').
preference:positive_use('apache2_modules_unixd').
preference:positive_use('addc').
preference:positive_use('apng').
preference:positive_use('avahi').
preference:positive_use('bzip2').
preference:positive_use('cairo').
preference:positive_use('calligra_features_karbon').
preference:positive_use('calligra_features_sheets').
preference:positive_use('calligra_features_words').
preference:positive_use('cli').
preference:positive_use('collectd_plugins_df').
preference:positive_use('collectd_plugins_interface').
preference:positive_use('collectd_plugins_irq').
preference:positive_use('collectd_plugins_load').
preference:positive_use('collectd_plugins_memory').
preference:positive_use('collectd_plugins_rrdtool').
preference:positive_use('collectd_plugins_swap').
preference:positive_use('collectd_plugins_syslog').
preference:positive_use('container').
preference:positive_use('cpu_flags_x86_aes').
preference:positive_use('cpu_flags_x86_avx').
preference:positive_use('cpu_flags_x86_avx2').
preference:positive_use('cpu_flags_x86_avx512bw').
preference:positive_use('cpu_flags_x86_avx512cd').
preference:positive_use('cpu_flags_x86_avx512dq').
preference:positive_use('cpu_flags_x86_avx512f').
preference:positive_use('cpu_flags_x86_avx512vl').
preference:positive_use('cpu_flags_x86_f16c').
preference:positive_use('cpu_flags_x86_fma3').
preference:positive_use('cpu_flags_x86_mmx').
preference:positive_use('cpu_flags_x86_mmxext').
preference:positive_use('cpu_flags_x86_pclmul').
preference:positive_use('cpu_flags_x86_popcnt').
preference:positive_use('cpu_flags_x86_sse').
preference:positive_use('cpu_flags_x86_sse2').
preference:positive_use('cpu_flags_x86_sse3').
preference:positive_use('cpu_flags_x86_sse4_1').
preference:positive_use('cpu_flags_x86_sse4_2').
preference:positive_use('cpu_flags_x86_ssse3').
preference:positive_use('crypt').
preference:positive_use('cvs').
preference:positive_use('cxx').
preference:positive_use('dbus').
preference:positive_use('directfb').
preference:positive_use('dri').
preference:positive_use('dts').
preference:positive_use('elibc_glibc').
preference:positive_use('elogind').
preference:positive_use('fbcondecor').
preference:positive_use('fontconfig').
preference:positive_use('fortran').
preference:positive_use('gdbm').
preference:positive_use('gif').
preference:positive_use('git').
preference:positive_use('glitz').
preference:positive_use('gmp').
preference:positive_use('gpg').
preference:positive_use('gpm').
preference:positive_use('http').
preference:positive_use('iconv').
preference:positive_use('icu').
preference:positive_use('imap').
preference:positive_use('input_devices_evdev').
preference:positive_use('input_devices_keyboard').
preference:positive_use('input_devices_mouse').
preference:positive_use('input_devices_vmmouse').
preference:positive_use('ipv6').
preference:positive_use('jpeg').
preference:positive_use('jpeg2k').
preference:positive_use('json').
preference:positive_use('kernel_linux').
preference:positive_use('libkms').
preference:positive_use('libtirpc').
preference:positive_use('md5sum').
preference:positive_use('mdnsresponder-compat').
preference:positive_use('messages').
preference:positive_use('mmx').
preference:positive_use('mmxext').
preference:positive_use('mp3').
preference:positive_use('ncurses').
preference:positive_use('nova').
preference:positive_use('npm').
preference:positive_use('nptl').
preference:positive_use('object').
preference:positive_use('opengl').
preference:positive_use('openmp').
preference:positive_use('openssl').
preference:positive_use('pam').
preference:positive_use('pcre').
preference:positive_use('pcre16').
preference:positive_use('pkcs11').
preference:positive_use('png').
preference:positive_use('policykit').
preference:positive_use('pop').
preference:positive_use('proxy').
preference:positive_use('python').
preference:positive_use('python_single_target_python3_7').
preference:positive_use('python_targets_python3_7').
preference:positive_use('qemu').
preference:positive_use('readline').
preference:positive_use('ruby_targets_ruby25').
preference:positive_use('seccomp').
preference:positive_use('sidebar').
preference:positive_use('smime').
preference:positive_use('smp').
preference:positive_use('smtp').
preference:positive_use('split-usr').
preference:positive_use('sqlite').
preference:positive_use('sse').
preference:positive_use('sse2').
preference:positive_use('sse3').
preference:positive_use('sse4').
preference:positive_use('sse4_2').
preference:positive_use('ssh').
preference:positive_use('ssl').
preference:positive_use('ssse3').
preference:positive_use('svg').
preference:positive_use('tcpd').
preference:positive_use('threads').
preference:positive_use('tiff').
preference:positive_use('truetype').
preference:positive_use('unicode').
preference:positive_use('userland_GNU').
preference:positive_use('video_cards_vesa').
preference:positive_use('video_cards_vga').
preference:positive_use('video_cards_vmware').
preference:positive_use('x264').
preference:positive_use('x265').
preference:positive_use('x86emu').
preference:positive_use('xa').
preference:positive_use('xattr').
preference:positive_use('xcb').
preference:positive_use('xkb').
preference:positive_use('xlib-xcb').
preference:positive_use('xvid').
preference:positive_use('zeroconf').
preference:positive_use('zlib').

preference:negative_use('test').
preference:negative_use('static-libs').


%! preference:use_expand_hidden(?Use)
%
% The printer does not print the expanding USE declared as hidden

preference:use_expand_hidden('abi_mips').
preference:use_expand_hidden('abi_ppc').
preference:use_expand_hidden('abi_riscv').
preference:use_expand_hidden('abi_s390').
preference:use_expand_hidden('abi_x86').
preference:use_expand_hidden('cpu_flags_arm').
preference:use_expand_hidden('cpu_flags_ppc').



%! preference:masked(?Repository://?Entry)
%
% Fact which masks a Repository entry

% Disabled for now (performance)
%
% The prover uses the dynamic 'proven:broken/1' to mark some entries as broken
% preference:masked(Repository://Entry) :- prover:broken(Repository://Entry).

preference:masked(portage://'dev-perl/Filesys-SmbClient-3.200.0-r4').

preference:masked(portage://'net-fs/samba-4.18.10').
preference:masked(portage://'net-fs/samba-4.18.11').

preference:masked(portage://'net-fs/samba-4.18.10').
preference:masked(portage://'net-fs/samba-4.18.11').
preference:masked(portage://'net-fs/samba-4.18.8').
preference:masked(portage://'net-fs/samba-4.18.9').
preference:masked(portage://'net-fs/samba-4.19.4').
preference:masked(portage://'net-fs/samba-4.19.6').
preference:masked(portage://'net-fs/samba-4.19.7').
preference:masked(portage://'net-fs/samba-4.20.0').
preference:masked(portage://'net-fs/samba-4.20.1').
preference:masked(portage://'net-fs/samba-4.20.2').
preference:masked(portage://'sci-libs/eccodes-2.18.0').
preference:masked(portage://'sci-libs/hdf5-1.10.5-r1').


%! preference:set(?Name,?List)
%
% A sample set for testing merging different packages

preference:set(prolog,[ portage://'dev-lang/swi-prolog-9.1.2-r1':run, portage://'dev-lang/qu-prolog-10.8':run ]).


%! preference:world(?List)
%
% A sample world list for testing merging different packages

preference:world([ portage://'acct-group/avahi-0-r1':run,portage://'acct-group/input-0-r1':run,portage://'acct-group/kvm-0-r1':run,portage://'acct-group/locate-0-r1':run,portage://'acct-group/man-0-r1':run,portage://'acct-group/netdev-0-r1':run,portage://'acct-group/portage-0':run,portage://'acct-group/render-0-r1':run,portage://'acct-group/sshd-0-r1':run,portage://'acct-group/utmp-0-r1':run,portage://'acct-user/avahi-0-r1':run,portage://'acct-user/man-1-r1':run,portage://'acct-user/portage-0':run,portage://'acct-user/sshd-0-r1':run,portage://'app-admin/eselect-1.4.17':run,portage://'app-admin/logrotate-3.18.0':run,portage://'app-admin/metalog-20200113-r1':run,portage://'app-admin/perl-cleaner-2.28':run,portage://'app-admin/sudo-1.9.5_p2-r1':run,portage://'app-arch/afio-2.5.1-r2':run,portage://'app-arch/bzip2-1.0.8-r1':run,portage://'app-arch/gzip-1.10':run,portage://'app-arch/libarchive-3.5.1':run,portage://'app-arch/pbzip2-1.1.13':run,portage://'app-arch/tar-1.33':run,portage://'app-arch/unzip-6.0_p25-r1':run,portage://'app-arch/xz-utils-5.2.5':run,portage://'app-arch/zstd-1.4.8-r1':run,portage://'app-crypt/gnupg-2.2.27':run,portage://'app-crypt/gpgme-1.15.1':run,portage://'app-crypt/libb2-0.98.1-r3':run,portage://'app-crypt/openpgp-keys-gentoo-release-20200704':run,portage://'app-crypt/p11-kit-0.23.22':run,portage://'app-crypt/rhash-1.4.1':run,portage://'app-doc/xmltoman-0.4-r1':run,portage://'app-editors/nano-5.5':run,portage://'app-editors/vim-8.2.0814-r100':run,portage://'app-editors/vim-core-8.2.0814':run,portage://'app-emulation/open-vm-tools-11.2.5_p17337674':run,portage://'app-emulation/virt-what-1.20':run,portage://'app-eselect/eselect-fontconfig-1.1-r1':run,portage://'app-eselect/eselect-iptables-20200508':run,portage://'app-eselect/eselect-lib-bin-symlink-0.1.1-r1':run,portage://'app-eselect/eselect-pinentry-0.7.1':run,portage://'app-eselect/eselect-python-20200719':run,portage://'app-eselect/eselect-rust-20200419':run,portage://'app-eselect/eselect-vi-1.2':run,portage://'app-misc/c_rehash-1.7-r1':run,portage://'app-misc/editor-wrapper-4-r1':run,portage://'app-misc/mime-types-9':run,portage://'app-misc/pax-utils-1.2.9':run,portage://'app-misc/screen-4.8.0-r1':run,portage://'app-portage/cpuid2cpuflags-11':run,portage://'app-portage/elt-patches-20201205':run,portage://'app-portage/esearch-1.3-r3':run,portage://'app-portage/gemato-16.2':run,portage://'app-portage/genlop-0.30.10-r2':run,portage://'app-portage/gentoolkit-0.5.0-r2':run,portage://'app-portage/portage-utils-0.90.1':run,portage://'app-portage/repoman-3.0.2':run,portage://'app-portage/splat-0.08-r1':run,portage://'app-shells/bash-5.1_p4':run,portage://'app-shells/zsh-5.8':run,portage://'app-text/ansifilter-2.18':run,portage://'app-text/build-docbook-catalog-1.21':run,portage://'app-text/docbook-xml-dtd-4.2-r3':run,portage://'app-text/docbook-xml-dtd-4.1.2-r7':run,portage://'app-text/docbook-xsl-stylesheets-1.79.1-r2':run,portage://'app-text/manpager-1':run,portage://'app-text/opensp-1.5.2-r6':run,portage://'app-text/po4a-0.62':run,portage://'app-text/sgml-common-0.6.3-r7':run,portage://'app-text/xmlto-0.0.28-r3':run,portage://'app-vim/gentoo-syntax-20201216':run,portage://'dev-db/sqlite-3.34.0':run,portage://'dev-lang/nasm-2.15.05':run,portage://'dev-lang/perl-5.32.1':run,portage://'dev-lang/python-3.10.0_alpha5':run,portage://'dev-lang/python-3.9.1-r1':run,portage://'dev-lang/python-3.7.9-r2':run,portage://'dev-lang/python-exec-2.4.6-r4':run,portage://'dev-lang/python-exec-conf-2.4.6':run,portage://'dev-lang/rust-1.49.0':run,portage://'dev-lang/spidermonkey-78.7.1':run,portage://'dev-lang/swig-4.0.2':run,portage://'dev-lang/tcl-8.6.11':run,portage://'dev-libs/elfutils-0.183':run,portage://'dev-libs/expat-2.2.10':run,portage://'dev-libs/fribidi-1.0.9':run,portage://'dev-libs/gmp-6.2.1':run,portage://'dev-libs/icu-68.2':run,portage://'dev-libs/isl-0.23-r1':run,portage://'dev-libs/jsoncpp-1.9.4':run,portage://'dev-libs/libassuan-2.5.4':run,portage://'dev-libs/libbsd-0.10.0':run,portage://'dev-libs/libdaemon-0.14-r3':run,portage://'dev-libs/libdnet-1.14-r2':run,portage://'dev-libs/libedit-20191211.3.1':run,portage://'dev-libs/libevdev-1.11.0':run,portage://'dev-libs/libevent-2.1.12':run,portage://'dev-libs/libffi-3.3-r2':run,portage://'dev-libs/libksba-1.5.0':run,portage://'dev-libs/liblinear-242':run,portage://'dev-libs/libltdl-2.4.6':run,portage://'dev-libs/libmspack-0.10.1_alpha':run,portage://'dev-libs/libpcre-8.44':run,portage://'dev-libs/libpipeline-1.5.3':run,portage://'dev-libs/libtasn1-4.16.0':run,portage://'dev-libs/libunistring-0.9.10':run,portage://'dev-libs/libuv-1.40.0':run,portage://'dev-libs/libxml2-2.9.10-r4':run,portage://'dev-libs/libxslt-1.1.34-r1':run,portage://'dev-libs/libyaml-0.2.5':run,portage://'dev-libs/lzo-2.10':run,portage://'dev-libs/mpc-1.2.1':run,portage://'dev-libs/mpfr-4.1.0':run,portage://'dev-libs/npth-1.6-r1':run,portage://'dev-libs/nspr-4.29':run,portage://'dev-libs/openssl-1.1.1i':run,portage://'dev-libs/popt-1.18':run,portage://'dev-libs/xmlsec-1.2.31':run,portage://'dev-perl/Authen-SASL-2.160.0-r2':run,portage://'dev-perl/Date-Manip-6.820.0':run,portage://'dev-perl/DBD-SQLite-1.660.0':run,portage://'dev-perl/DBI-1.643.0':run,portage://'dev-perl/Devel-Size-0.830.0':run,portage://'dev-perl/Digest-HMAC-1.30.0-r2':run,portage://'dev-perl/Encode-Locale-1.50.0':run,portage://'dev-perl/Error-0.170.290':run,portage://'dev-perl/ExtUtils-Config-0.8.0':run,portage://'dev-perl/ExtUtils-Helpers-0.26.0':run,portage://'dev-perl/ExtUtils-InstallPaths-0.12.0':run,portage://'dev-perl/File-Listing-6.70.0':run,portage://'dev-perl/HTML-Parser-3.720.0':run,portage://'dev-perl/HTML-Tagset-3.200.0-r1':run,portage://'dev-perl/HTTP-Cookies-6.40.0':run,portage://'dev-perl/HTTP-Daemon-6.60.0':run,portage://'dev-perl/HTTP-Date-6.20.0-r1':run,portage://'dev-perl/HTTP-Message-6.130.0':run,portage://'dev-perl/HTTP-Negotiate-6.10.0-r1':run,portage://'dev-perl/IO-HTML-1.1.0':run,portage://'dev-perl/IO-Socket-INET6-2.720.0-r1':run,portage://'dev-perl/IO-Socket-SSL-2.66.0':run,portage://'dev-perl/libwww-perl-6.270.0':run,portage://'dev-perl/Locale-gettext-1.70.0':run,portage://'dev-perl/LWP-MediaTypes-6.20.0-r1':run,portage://'dev-perl/LWP-Protocol-https-6.70.0':run,portage://'dev-perl/MailTools-2.190.0':run,portage://'dev-perl/MIME-Charset-1.12.2':run,portage://'dev-perl/Module-Build-0.422.400':run,portage://'dev-perl/Module-Build-Tiny-0.39.0':run,portage://'dev-perl/Mozilla-CA-20999999':run,portage://'dev-perl/Net-Daemon-0.480.0-r2':run,portage://'dev-perl/Net-HTTP-6.170.0':run,portage://'dev-perl/Net-SSLeay-1.880.0':run,portage://'dev-perl/PlRPC-0.202.0-r3':run,portage://'dev-perl/Pod-Parser-1.630.0-r1':run,portage://'dev-perl/SGMLSpm-1.1-r1':run,portage://'dev-perl/Socket6-0.280.0':run,portage://'dev-perl/Sub-Name-0.210.0':run,portage://'dev-perl/TermReadKey-2.370.0':run,portage://'dev-perl/Text-CharWidth-0.40.0-r1':run,portage://'dev-perl/Text-WrapI18N-0.60.0-r1':run,portage://'dev-perl/TimeDate-2.330.0':run,portage://'dev-perl/Try-Tiny-0.300.0':run,portage://'dev-perl/Unicode-LineBreak-2019.1.0':run,portage://'dev-perl/URI-1.730.0':run,portage://'dev-perl/WWW-RobotRules-6.20.0-r1':run,portage://'dev-perl/XML-Parser-2.440.0':run,portage://'dev-perl/YAML-Tiny-1.730.0':run,portage://'dev-python/certifi-10001-r1':run,portage://'dev-python/chardet-4.0.0':run,portage://'dev-python/cython-0.29.21-r1':run,portage://'dev-python/idna-2.10-r1':run,portage://'dev-python/jinja-2.11.3':run,portage://'dev-python/lxml-4.6.2-r1':run,portage://'dev-python/mako-1.1.4':run,portage://'dev-python/markupsafe-1.1.1-r1':run,portage://'dev-python/PySocks-1.7.1-r1':run,portage://'dev-python/pyyaml-5.4.1':run,portage://'dev-python/requests-2.25.1-r1':run,portage://'dev-python/setuptools_scm-5.0.1':run,portage://'dev-util/cmake-3.19.4':run,portage://'dev-util/desktop-file-utils-0.26-r1':run,portage://'dev-util/glib-utils-2.66.4':run,portage://'dev-util/google-perftools-2.8':run,portage://'dev-util/gperf-3.1':run,portage://'dev-util/gtk-doc-am-1.33.1':run,portage://'dev-util/intltool-0.51.0-r2':run,portage://'dev-util/itstool-2.0.6-r1':run,portage://'dev-util/meson-format-array-0':run,portage://'dev-util/pkgconfig-0.29.2':run,portage://'dev-util/re2c-2.0.3':run,portage://'dev-vcs/cvsps-2.2_beta1-r1':run,portage://'gui-libs/display-manager-init-1.0-r2':run,portage://'mail-mta/nullmailer-2.2-r1':run,portage://'media-fonts/dejavu-2.37':run,portage://'media-fonts/encodings-1.0.5-r1':run,portage://'media-fonts/font-adobe-100dpi-1.0.3-r2':run,portage://'media-fonts/font-adobe-75dpi-1.0.3-r2':run,portage://'media-fonts/font-alias-1.0.4':run,portage://'media-fonts/font-misc-misc-1.1.2-r2':run,portage://'media-fonts/font-util-1.3.2-r1':run,portage://'media-gfx/graphite2-1.3.14':run,portage://'media-gfx/graphviz-2.44.1-r1':run,portage://'media-libs/fontconfig-2.13.1-r2':run,portage://'media-libs/freeglut-3.2.1':run,portage://'media-libs/freetype-2.10.4':run,portage://'media-libs/giflib-5.2.1-r1':run,portage://'media-libs/glu-9.0.1':run,portage://'media-libs/imlib2-1.7.1':run,portage://'media-libs/libepoxy-1.5.5':run,portage://'media-libs/libglvnd-1.3.2-r2':run,portage://'media-libs/libid3tag-0.15.1b-r4':run,portage://'media-libs/libjpeg-turbo-2.0.6':run,portage://'media-libs/libpng-1.6.37-r2':run,portage://'media-libs/tiff-4.2.0':run,portage://'net-analyzer/mtr-0.94':run,portage://'net-analyzer/nmap-7.91-r1':run,portage://'net-dns/avahi-0.8-r2':run,portage://'net-dns/libidn2-2.3.0':run,portage://'net-firewall/iptables-1.8.7':run,portage://'net-libs/gnutls-3.6.15':run,portage://'net-libs/libmnl-1.0.4':run,portage://'net-libs/libnsl-1.3.0-r1':run,portage://'net-libs/libpcap-1.10.0':run,portage://'net-libs/libssh2-1.9.0_p20200614':run,portage://'net-libs/rpcsvc-proto-1.4.2':run,portage://'net-misc/dhcpcd-9.4.0':run,portage://'net-misc/iputils-20210202':run,portage://'net-misc/keychain-2.8.5':run,portage://'net-misc/netifrc-0.7.3':run,portage://'net-misc/openssh-8.4_p1-r3':run,portage://'net-misc/rsync-3.2.3-r1':run,portage://'net-misc/sntpd-3.0-r1':run,portage://'net-misc/wget-1.21.1':run,portage://'perl-core/File-Temp-0.230.900':run,portage://'sys-apps/acl-2.2.53-r1':run,portage://'sys-apps/baselayout-2.7-r1':run,portage://'sys-apps/busybox-1.33.0':run,portage://'sys-apps/coreutils-8.32-r1':run,portage://'sys-apps/debianutils-4.11.2':run,portage://'sys-apps/diffutils-3.7-r1':run,portage://'sys-apps/fbset-2.1':run,portage://'sys-apps/file-5.39-r3':run,portage://'sys-apps/findutils-4.8.0':run,portage://'sys-apps/gawk-5.1.0':run,portage://'sys-apps/grep-3.6':run,portage://'sys-apps/groff-1.22.4':run,portage://'sys-apps/help2man-1.48.1':run,portage://'sys-apps/hwids-20201207':run,portage://'sys-apps/install-xattr-0.8':run,portage://'sys-apps/iproute2-5.10.0':run,portage://'sys-apps/kbd-2.4.0':run,portage://'sys-apps/kmod-28':run,portage://'sys-apps/less-563-r1':run,portage://'sys-apps/man-db-2.9.4':run,portage://'sys-apps/man-pages-5.10':run,portage://'sys-apps/man-pages-posix-2017a':run,portage://'sys-apps/mlocate-0.26-r3':run,portage://'sys-apps/net-tools-2.10':run,portage://'sys-apps/openrc-0.42.1-r1':run,portage://'sys-apps/opentmpfiles-0.2':run,portage://'sys-apps/pciutils-3.7.0':run,portage://'sys-apps/sandbox-2.20':run,portage://'sys-apps/sed-4.8':run,portage://'sys-apps/sysvinit-2.98-r1':run,portage://'sys-apps/texinfo-6.7':run,portage://'sys-apps/util-linux-2.36.2':run,portage://'sys-apps/which-2.21':run,portage://'sys-auth/nss-mdns-0.14.1':run,portage://'sys-auth/passwdqc-1.4.0-r1':run,portage://'sys-block/parted-3.4':run,portage://'sys-boot/efibootmgr-17':run,portage://'sys-devel/autoconf-2.69-r5':run,portage://'sys-devel/autoconf-2.13-r1':run,portage://'sys-devel/autoconf-archive-2019.01.06':run,portage://'sys-devel/autoconf-wrapper-13-r1':run,portage://'sys-devel/automake-1.16.3-r1':run,portage://'sys-devel/automake-wrapper-11':run,portage://'sys-devel/bc-1.07.1-r3':run,portage://'sys-devel/binutils-2.35.2':run,portage://'sys-devel/binutils-config-5.3.2':run,portage://'sys-devel/flex-2.6.4-r1':run,portage://'sys-devel/gcc-10.2.0-r5':run,portage://'sys-devel/gcc-config-2.3.3':run,portage://'sys-devel/gettext-0.21':run,portage://'sys-devel/gnuconfig-20210107':run,portage://'sys-devel/libtool-2.4.6-r6':run,portage://'sys-devel/llvm-11.0.1':run,portage://'sys-devel/llvm-common-11.0.1':run,portage://'sys-devel/m4-1.4.18-r1':run,portage://'sys-devel/make-4.3':run,portage://'sys-devel/patch-2.7.6-r4':run,portage://'sys-devel/prelink-20151030-r1':run,portage://'sys-fs/dosfstools-4.2':run,portage://'sys-fs/eudev-3.2.10':run,portage://'sys-fs/fuse-2.9.9-r1':run,portage://'sys-fs/fuse-common-3.10.1':run,portage://'sys-fs/udev-init-scripts-34':run,portage://'sys-kernel/installkernel-gentoo-2':run,portage://'sys-kernel/linux-headers-5.10':run,portage://'sys-libs/e2fsprogs-libs-1.46.1':run,portage://'sys-libs/efivar-37':run,portage://'sys-libs/glibc-2.32-r7':run,portage://'sys-libs/gpm-1.20.7-r2':run,portage://'sys-libs/libcap-2.48':run,portage://'sys-libs/libtermcap-compat-2.0.8-r4':run,portage://'sys-libs/libunwind-1.5.0-r1':run,portage://'sys-libs/libutempter-1.2.1':run,portage://'sys-libs/mtdev-1.1.6':run,portage://'sys-libs/ncurses-6.2_p20210123':run,portage://'sys-libs/ncurses-compat-6.2':run,portage://'sys-libs/pam-1.5.1':run,portage://'sys-libs/readline-8.1':run,portage://'sys-libs/timezone-data-2021a':run,portage://'sys-libs/zlib-1.2.11-r3':run,portage://'sys-process/cronbase-0.3.7-r6':run,portage://'sys-process/cronie-1.5.5-r1':run,portage://'sys-process/htop-3.0.5':run,portage://'sys-process/parallel-20210122':run,portage://'sys-process/procps-3.3.17':run,portage://'sys-process/psmisc-23.4':run,portage://'virtual/acl-0-r2':run,portage://'virtual/awk-1':run,portage://'virtual/cron-0-r2':run,portage://'virtual/dev-manager-0-r2':run,portage://'virtual/editor-0-r3':run,portage://'virtual/glu-9.0-r2':run,portage://'virtual/jpeg-100':run,portage://'virtual/libc-1-r1':run,portage://'virtual/libelf-3':run,portage://'virtual/libiconv-0-r2':run,portage://'virtual/libintl-0-r2':run,portage://'virtual/libudev-232-r3':run,portage://'virtual/logger-0-r1':run,portage://'virtual/man-0-r4':run,portage://'virtual/mta-1-r1':run,portage://'virtual/opengl-7.0-r2':run,portage://'virtual/os-headers-0-r2':run,portage://'virtual/package-manager-1':run,portage://'virtual/pager-0':run,portage://'virtual/perl-Carp-1.500.0-r3':run,portage://'virtual/perl-Compress-Raw-Bzip2-2.93.0':run,portage://'virtual/perl-Compress-Raw-Zlib-2.93.0':run,portage://'virtual/perl-CPAN-Meta-2.150.10-r4':run,portage://'virtual/perl-CPAN-Meta-YAML-0.18.0-r6':run,portage://'virtual/perl-Digest-SHA-6.20.0-r1':run,portage://'virtual/perl-Encode-3.60.0':run,portage://'virtual/perl-ExtUtils-CBuilder-0.280.234':run,portage://'virtual/perl-ExtUtils-Install-2.140.0-r3':run,portage://'virtual/perl-ExtUtils-Manifest-1.720.0-r1':run,portage://'virtual/perl-ExtUtils-ParseXS-3.400.0-r1':run,portage://'virtual/perl-File-Path-2.160.0-r1':run,portage://'virtual/perl-File-Spec-3.780.0-r1':run,portage://'virtual/perl-File-Temp-0.230.900':run,portage://'virtual/perl-Getopt-Long-2.510.0':run,portage://'virtual/perl-IO-1.430.0':run,portage://'virtual/perl-IO-Compress-2.93.0':run,portage://'virtual/perl-IO-Socket-IP-0.390.0-r3':run,portage://'virtual/perl-JSON-PP-4.40.0':run,portage://'virtual/perl-libnet-3.110.0-r4':run,portage://'virtual/perl-MIME-Base64-3.150.0-r7':run,portage://'virtual/perl-Module-Metadata-1.0.37':run,portage://'virtual/perl-parent-0.238.0':run,portage://'virtual/perl-Parse-CPAN-Meta-2.150.10-r4':run,portage://'virtual/perl-Perl-OSType-1.10.0-r4':run,portage://'virtual/perl-Pod-Parser-1.630.0-r8':run,portage://'virtual/perl-podlators-4.140.0':run,portage://'virtual/perl-Socket-2.29.0':run,portage://'virtual/perl-Storable-3.210.0':run,portage://'virtual/perl-Test-Harness-3.420.0-r3':run,portage://'virtual/perl-Text-ParseWords-3.300.0-r7':run,portage://'virtual/perl-Time-Local-1.280.0-r1':run,portage://'virtual/perl-version-0.992.400-r1':run,portage://'virtual/perl-XSLoader-0.300.0-r3':run,portage://'virtual/pkgconfig-2':run,portage://'virtual/service-manager-1':run,portage://'virtual/ssh-0':run,portage://'virtual/tmpfiles-0-r1':run,portage://'virtual/ttf-fonts-1-r1':run,portage://'virtual/udev-217-r2':run,portage://'virtual/yacc-0':run,portage://'x11-apps/bdftopcf-1.1':run,portage://'x11-apps/iceauth-1.0.8-r1':run,portage://'x11-apps/luit-20190106':run,portage://'x11-apps/mkfontscale-1.2.1':run,portage://'x11-apps/rgb-1.0.6-r1':run,portage://'x11-apps/setxkbmap-1.3.2':run,portage://'x11-apps/xauth-1.1':run,portage://'x11-apps/xinit-1.4.1-r1':run,portage://'x11-apps/xkbcomp-1.4.4':run,portage://'x11-apps/xmessage-1.0.5-r1':run,portage://'x11-apps/xrandr-1.5.1':run,portage://'x11-apps/xrdb-1.2.0':run,portage://'x11-base/xcb-proto-1.14.1':run,portage://'x11-base/xorg-drivers-1.20-r2':run,portage://'x11-base/xorg-proto-2020.1':run,portage://'x11-base/xorg-server-1.20.10-r3':run,portage://'x11-drivers/xf86-input-evdev-2.10.6':run,portage://'x11-drivers/xf86-input-vmmouse-13.1.0-r1':run,portage://'x11-drivers/xf86-video-vesa-2.5.0':run,portage://'x11-drivers/xf86-video-vmware-13.3.0':run,portage://'x11-libs/cairo-1.16.0-r4':run,portage://'x11-libs/gdk-pixbuf-2.42.2':run,portage://'x11-libs/libfontenc-1.1.4':run,portage://'x11-libs/libICE-1.0.10':run,portage://'x11-libs/libpciaccess-0.16':run,portage://'x11-libs/libSM-1.2.3-r1':run,portage://'x11-libs/libX11-1.7.0':run,portage://'x11-libs/libXau-1.0.9-r1':run,portage://'x11-libs/libXaw-1.0.13-r2':run,portage://'x11-libs/libxcb-1.14':run,portage://'x11-libs/libXdmcp-1.1.3':run,portage://'x11-libs/libXext-1.3.4':run,portage://'x11-libs/libXfixes-5.0.3-r3':run,portage://'x11-libs/libXfont2-2.0.4':run,portage://'x11-libs/libXft-2.3.3':run,portage://'x11-libs/libXi-1.7.10':run,portage://'x11-libs/libxkbfile-1.1.0':run,portage://'x11-libs/libXmu-1.1.3':run,portage://'x11-libs/libXpm-3.5.13':run,portage://'x11-libs/libXrandr-1.5.2':run,portage://'x11-libs/libXrender-0.9.10-r2':run,portage://'x11-libs/libxshmfence-1.3-r2':run,portage://'x11-libs/libXt-1.2.1':run,portage://'x11-libs/libXxf86vm-1.1.4-r2':run,portage://'x11-libs/pango-1.42.4-r2':run,portage://'x11-libs/pixman-0.40.0':run,portage://'x11-libs/xtrans-1.4.0':run,portage://'x11-misc/compose-tables-1.7.0':run,portage://'x11-misc/shared-mime-info-2.1':run,portage://'x11-misc/util-macros-1.19.3':run,portage://'x11-misc/xbitmaps-1.1.2-r1':run,portage://'x11-misc/xkeyboard-config-2.31':run,portage://'x11-terms/xterm-366':run,portage://'x11-wm/fluxbox-1.3.7-r4':run ]).
