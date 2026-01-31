# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="Overlay test64 dummy gpg"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE=""

DEPEND=""

# Tie the verify-sig `|| ( gpg gnupg )` choice to python_single_target selection.
# If openmp pulls gpg, it will force python[target=python3_12].
RDEPEND="test64/python[python_single_target_python3_12]"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

