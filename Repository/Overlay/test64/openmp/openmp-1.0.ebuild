# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="Overlay test64: openmp-style conditional deps"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"

IUSE="gdb-plugin hwloc test verify-sig
      python_single_target_python3_12 python_single_target_python3_13"

# Mirror upstream openmp REQUIRED_USE shape: if gdb-plugin is enabled,
# exactly one python_single_target must be enabled.
REQUIRED_USE="gdb-plugin? ( ^^ ( python_single_target_python3_12 python_single_target_python3_13 ) )"

# Unconditional build deps (mirrors openmp trace: perl/ninja/cmake)
BDEPEND="test64/perl test64/ninja test64/cmake"

# Optional deps behind USE conditionals (mirrors openmp)
DEPEND="
  gdb-plugin? (
    python_single_target_python3_12? ( test64/python[python_single_target_python3_12] )
    python_single_target_python3_13? ( test64/python[python_single_target_python3_13] )
  )
  hwloc? ( test64/hwloc )
"
RDEPEND="${DEPEND}"

# Add a small Portage-like branch to create additional config-time work:
# openmp has `verify-sig? ( || ( gpg gnupg[...] ) gemato )` etc.
# Here we model just the || group.
BDEPEND="${BDEPEND}
  verify-sig? ( || ( test64/gpg test64/gnupg ) )
"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

