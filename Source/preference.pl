/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2020, Pieter Van den Abeele

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

preference:positive_use('X').
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


%! preference:printing_style(?Setting)
%
% Fact which defines the printing style ('short', 'column' or 'fancy')

preference:printing_style('column').


%! preference:masked(?Repository://?Entry)
%
% Fact which masks a Repository entry

% Disabled for now (performance)
%
% The prover uses the dynamic 'proven:broken/1' to mark some entries as broken
% preference:masked(Repository://Entry) :- prover:broken(Repository://Entry).
%
% The following packages have known broken dependencies in RDEPEND
% preference:masked(Repository://Entry) :- preference:known_broken(Repository://Entry).


% The following packages fail:

% 1. KEYWORD-related failure:
%
% Fails when only accept_keywords(stable(amd64)) is set
% Fixed temporarily by adding unstable keyword to default config
%
% preference:masked(portage://'app-xemacs/dired-1.19').                % 2020-05-09
% preference:masked(portage://'app-xemacs/ediff-1.77').                % 2020-05-09
% preference:masked(portage://'app-xemacs/edit-utils-2.44').           % 2020-05-09
% preference:masked(portage://'dev-java/xom-1.3.2').                   % 2020-05-09
% preference:masked(portage://'dev-lang/mono-6.10.0.104').             % 2020-12-25
% preference:masked(portage://'dev-lang/mono-6.6.0.161').              % 2020-05-09
% preference:masked(portage://'dev-lang/scala-2.12.10').               % 2020-05-09
% preference:masked(portage://'media-libs/openimageio-2.2.10.0').      % 2021-01-08
% preference:masked(portage://'media-libs/openimageio-2.2.9.0-r1').    % 2020-12-25
%
% We should set accept_keywords(_) for the following:
preference:masked(portage://'dev-vcs/mercurial-9999').                 % 2020-05-09

% 2. Timeout fails
%
% Fixed by setting timeout to 120 seconds
% Need better handling of large lists across backtracking to improve this
% or keep lists smaller
%
% preference:masked(portage://'kde-apps/kde-apps-meta-20.08.3').       % 2021-01-08
% preference:masked(portage://'kde-apps/kde-apps-meta-20.12.1').       % 2021-01-08
% preference:masked(portage://'kde-apps/kde-meta-20.08.3').            % 2020-12-25

% 3. To be investigated fails
%
% To be investigated (keyword constraint failure?)
preference:masked(portage://'net-fs/samba-4.13.2-r1').                 % 2021-01-08
preference:masked(portage://'net-fs/samba-4.13.3').                    % 2021-01-08
preference:masked(portage://'sci-libs/hdf5-1.10.5-r1').                % 2020-05-09
