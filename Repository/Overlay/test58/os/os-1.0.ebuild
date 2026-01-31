# Copyright 2026 Pieter Van den Abeele
# Distributed under the terms of the GNU General Public License v2

EAPI="8"
DESCRIPTION="Operating system meta-package (test58)"
HOMEPAGE="http://www.portage-ng.org/"
SRC_URI=""

LICENSE="GPL-2"
SLOT="0"
KEYWORDS="alpha amd64 arm hppa ia64 m68k mips ppc ppc64 s390 sh sparc x86 sparc-fbsd x86-fbsd"
IUSE=""

# Depend on a package that does not exist as an ebuild; it should be satisfied
# by the provider via PROVIDE (once implemented).
DEPEND="test58/virtualsdk"
RDEPEND="test58/virtualsdk"

src_unpack() { :; }
src_compile() { :; }
src_install() { :; }

