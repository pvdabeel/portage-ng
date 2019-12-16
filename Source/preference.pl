/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2019, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> PREFERENCE
The preferences module contains build specific preferences
*/

:- module(preference, []).

:- dynamic preference:known_broken/1.

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

preference:accept_keywords('amd64').


%! preference:use(?Use)
%
% Fact which defines the USE flags to be used

preference:use(['X','a52','aac','aacplus','aalib','abi_x86_64','account','acl','aio','alsa','alsa_cards_ens1371','amd64','apache2_modules_auth_basic','apache2_modules_authn_core','apache2_modules_authn_file','apache2_modules_authz_core','apache2_modules_authz_host','apache2_modules_dir','apache2_modules_mime','apache2_modules_socache_shmcb','apache2_modules_unixd','apng','avahi','bzip2','cairo','calligra_features_karbon','calligra_features_sheets','calligra_features_words','cli','collectd_plugins_df','collectd_plugins_interface','collectd_plugins_irq','collectd_plugins_load','collectd_plugins_memory','collectd_plugins_rrdtool','collectd_plugins_swap','collectd_plugins_syslog','container','cpu_flags_x86_aes','cpu_flags_x86_avx','cpu_flags_x86_avx2','cpu_flags_x86_avx512bw','cpu_flags_x86_avx512cd','cpu_flags_x86_avx512dq','cpu_flags_x86_avx512f','cpu_flags_x86_avx512vl','cpu_flags_x86_f16c','cpu_flags_x86_fma3','cpu_flags_x86_mmx','cpu_flags_x86_mmxext','cpu_flags_x86_pclmul','cpu_flags_x86_popcnt','cpu_flags_x86_sse','cpu_flags_x86_sse2','cpu_flags_x86_sse3','cpu_flags_x86_sse4_1','cpu_flags_x86_sse4_2','cpu_flags_x86_ssse3','crypt','cvs','cxx','dbus','directfb','dri','dts','elibc_glibc','elogind','fbcondecor','fontconfig','fortran','gdbm','gif','git','glitz','gmp','gpg','gpm','http','iconv','icu','imap','input_devices_evdev','input_devices_keyboard','input_devices_mouse','input_devices_vmmouse','ipv6','jpeg','jpeg2k','json','kernel_linux','libkms','libtirpc','md5sum','mdnsresponder-compat','messages','mmx','mmxext','mp3','ncurses','nova','npm','nptl','object','opengl','openmp','openssl','pam','pcre','pcre16','pkcs11','png','policykit','pop','proxy','python','python_single_target_python3_7','python_targets_python3_7','qemu','readline','ruby_targets_ruby25','seccomp','sidebar','smime','smp','smtp','split-usr','sqlite','sse','sse2','sse3','sse4','sse4_2','ssh','ssl','ssse3','svg','tcpd','threads','tiff','truetype','unicode','userland_GNU','video_cards_vesa','video_cards_vga','video_cards_vmware','x264','x265','x86emu','xa','xattr','xcb','xkb','xlib-xcb','xvid','zeroconf','zlib']).


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

% The prover uses the dynamic 'proven:broken/1' to mark some entries as broken
preference:masked(Repository://Entry) :- prover:broken(Repository://Entry).

% The following packages have known broken dependencies in RDEPEND
preference:masked(Repository://Entry) :- preference:known_broken(Repository://Entry).


% run target fail
preference:masked(portage://'app-xemacs/rmail-1.14').          % run target fail

% install target fail
preference:masked(portage://'dev-ros/gmapping-1.3.10').        % install target fail
