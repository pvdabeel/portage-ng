/*
  Author:   Pieter Van den Abeele
  E-mail:   pvdabeel@mac.com
  Copyright (c) 2005-2026, Pieter Van den Abeele

  Distributed under the terms of the LICENSE file in the root directory of this
  project.
*/


/** <module> FALLBACK
Development defaults mirroring a specific Gentoo system's /etc/portage files.

This module provides hardcoded environment variables, package masks, and
per-package USE overrides that serve as fallback values when no real
`config:portage_confdir/1` is configured.  They mirror the /etc/portage
configuration of a reference Gentoo system (vm-linux) for development and
comparison purposes.

When `config:portage_confdir/1` IS set, `preference:init` loads the real
/etc/portage files via `userconfig:load` instead and these fallback facts
are not consulted for package masks or per-package USE.  The `fallback:env/2`
facts remain available as lowest-priority defaults in the
`preference:getenv/2` fallback chain (OS env > make.conf > fallback:env).

To change the reference system, edit the facts below to match its
/etc/portage/make.conf, package.mask, and package.use.
*/

:- module(fallback, []).

% =============================================================================
%  FALLBACK declarations
% =============================================================================

% -----------------------------------------------------------------------------
%  Environment defaults (mirrors make.conf)
% -----------------------------------------------------------------------------

%! fallback:env(+Name, -Value) is semidet.
%
% Default environment variable values.  Consulted by `preference:getenv/2`
% as the lowest-priority fallback when neither the OS environment nor
% `userconfig:env/2` (make.conf) provides a value.

fallback:env('USE', 'berkdb harfbuzz lto dnet resolutionkms o-flag-munging pgo graphite optimizations aio npm http split-usr -elogind policykit json -systemd -llvm -lua -berkdb -gdbm -introspection -vala -xen -hcache -ruby python gdbm fbcondecor messages smp qemu sqlite mmxext -svg avahi mmx sse sse2 sse3 ssse3 sse4 sse4_2 gmp cvs git x86emu gpg imap pop sidebar smime smtp dbus truetype X -xvmc xa xkb libkms cairo glitz png jpeg tiff gif mp3 opengl xcb xlib-xcb alsa aac aacplus jpeg2k fontconfig openssl ssh threads x264 x265 xvid dts md5sum a52 aalib zeroconf pkcs11 apng xattr nova account container object proxy directfb pcre16 -mdnsresponder-compat gpm').
fallback:env('VIDEO_CARDS', 'vmware vesa vga').
fallback:env('INPUT_DEVICES', 'evdev keyboard mouse vmmouse').
fallback:env('ALSA_CARDS', 'ens1371').
fallback:env('CPU_FLAGS_X86', 'aes avx avx2 avx512f avx512dq avx512cd avx512bw avx512vl f16c fma3 mmx mmxext pclmul popcnt rdrand sse sse2 sse3 sse4_1 sse4_2 ssse3').
fallback:env('PERL_FEATURES', 'ithreads').
fallback:env('RUBY_TARGETS', 'ruby32 ruby33').
fallback:env('ACCEPT_KEYWORDS', '~amd64').
fallback:env('ACCEPT_LICENSE', '-* @FREE').


% -----------------------------------------------------------------------------
%  Package masks (mirrors /etc/portage/package.mask)
% -----------------------------------------------------------------------------

%! fallback:package_mask(+Atom) is nondet.
%
% Atoms to mask.  Applied only when `config:portage_confdir/1` is not set.

fallback:package_mask('sys-apps/systemd').


% -----------------------------------------------------------------------------
%  Per-package USE (mirrors /etc/portage/package.use)
% -----------------------------------------------------------------------------

%! fallback:package_use(+Atom, +UseStr) is nondet.
%
% Per-package USE overrides.  Applied only when `config:portage_confdir/1`
% is not set.

fallback:package_use('app-emulation/open-vm-tools', '-dnet -X -multimon resolutionkms').
fallback:package_use('app-editors/vim',             '-X').
fallback:package_use('dev-lang/swi-prolog',         '-X').
fallback:package_use('www-client/links',            '-X -jpeg -png -tiff').
fallback:package_use('>=sys-libs/gdbm-1.26',        'berkdb').
fallback:package_use('x11-wm/compiz-fusion',         'unsupported emerald').
fallback:package_use('sys-kernel/gentoo-sources',    'symlink build').