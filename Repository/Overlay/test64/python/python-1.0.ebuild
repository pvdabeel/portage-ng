# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="Overlay test64 dummy python"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE="python_single_target_python3_12 python_single_target_python3_13"

# Force a choice, like real python_single_target handling.
REQUIRED_USE="^^ ( python_single_target_python3_12 python_single_target_python3_13 )"

DEPEND=""

# Deliberately create an "opposite-target" cycle back to openmp.
# This should force backtracking when openmp (via gdb-plugin) requires
# python[target] but python[target] pulls openmp[other-target].
RDEPEND="
  python_single_target_python3_12? ( test64/openmp[python_single_target_python3_13] )
  python_single_target_python3_13? ( test64/openmp[python_single_target_python3_12] )
"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

